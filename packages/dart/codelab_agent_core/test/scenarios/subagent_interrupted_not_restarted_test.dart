import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart';
import '../subagents/subagent_rig.dart';

/// `core/subagent-interrupted-not-restarted` (agent-subagents «Журнал
/// субагента и прерывание», сценарий «Сбой с двумя детьми»; S-13, SUB-9,
/// SUB-10; design.md change `add-subagents-and-tasks`, D7;
/// `agent-core/17-3-subagents.md` §17.3.6, «Прерывание»).
///
/// Красный до задачи 2.7: `healInterruptedTurn` не знает записей `subagent`
/// — вызов `agent` с итоговой записью получил бы общий `interrupted`, а
/// прерванный ребёнок не получил бы записи `failed/interrupted`.
///
/// «Сбой» — журнал корня на момент, когда ребёнок A завершён (итоговая
/// запись есть, результата вызова нет), а B ещё работает. Журнал собран
/// построчно: настоящий сбой процесса в тесте ядра невоспроизводим, а формат
/// записей фиксирует agent-sessions «Формат журнала JSONL». Лечение журнала
/// самого ребёнка (`openChild`) — задача 4.4.
void main() {
  const rootId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  String subagentRecord(
    String id,
    String? parent, {
    required String subagentId,
    required String callId,
    required String agent,
    required String status,
    Map<String, Object?> extra = const {},
  }) => jsonEncode({
    'type': 'subagent',
    'id': id,
    'parentId': parent,
    'timestamp': at,
    'subagentId': subagentId,
    'toolCallId': callId,
    'agent': agent,
    'description': 'Job $subagentId',
    'childSessionId':
        '01JB8Q3A1D2E3F4G5H6J7K8M9${subagentId.substring(4, 5).toUpperCase()}',
    'journal': 'proj/root/subagents/child-$subagentId.jsonl',
    'status': status,
    ...extra,
  });

  /// Журнал на момент сбоя: A завершён, B работает, результатов вызовов нет.
  String crashedJournal() => journal([
    header(cwd: '/proj', id: rootId.value),
    modelChange('m1', null),
    user('u1', 'm1', text: 'run both'),
    answer(
      'a1',
      'u1',
      calls: [
        ('c1', 'agent', {'description': 'Job A', 'prompt': 'task a'}),
        ('c2', 'agent', {'description': 'Job B', 'prompt': 'task b'}),
      ],
    ),
    subagentRecord(
      's1',
      'a1',
      subagentId: 'sub_aaaaaaaa',
      callId: 'c1',
      agent: 'explore',
      status: 'running',
    ),
    subagentRecord(
      's2',
      's1',
      subagentId: 'sub_bbbbbbbb',
      callId: 'c2',
      agent: 'general',
      status: 'running',
    ),
    subagentRecord(
      's3',
      's2',
      subagentId: 'sub_aaaaaaaa',
      callId: 'c1',
      agent: 'explore',
      status: 'completed',
      extra: {
        'report': 'Report of A',
        'usage': {
          'input': 100,
          'output': 20,
          'cacheRead': 0,
          'cacheWrite': 0,
          'cost': {
            'input': 0.0,
            'output': 0.0,
            'cacheRead': 0.0,
            'cacheWrite': 0.0,
          },
        },
        'toolCalls': 3,
        'durationMs': 4200,
      },
    ),
  ]);

  List<Map<String, Object?>> records(String text, String type) => [
    for (final line in const LineSplitter().convert(text))
      if ((jsonDecode(line) as Map<String, Object?>)['type'] == type)
        jsonDecode(line) as Map<String, Object?>,
  ];

  test('A получает отчёт из итоговой записи, B — interrupted, ни один '
      'ребёнок не запущен снова', () async {
    final store = MemorySessionStore()..putText(rootId, crashedJournal());
    final rig = SubagentRig(
      store: store,
      scripts: {
        'run both': [replyStep('Continuing.')],
      },
    );

    await rig.load(rootId);
    await rig.run('continue');

    final request = rig.requestsOf('run both').single;
    // Вызов A: результат из записи, с обёрткой §17.3.5, не ошибка.
    expect(
      resultText(request, 'c1'),
      contains(
        '<subagent-report id="sub_aaaaaaaa" agent="explore" '
        'status="completed"',
      ),
    );
    expect(resultText(request, 'c1'), contains('Report of A'));
    expect(resultIsError(request, 'c1'), isFalse);
    // Вызов B: стандартный синтетический результат прерывания.
    expect(resultText(request, 'c2'), startsWith('Tool call was interrupted'));
    expect(resultIsError(request, 'c2'), isTrue);
    // Никто не перезапущен: к модели обращался только корень (ключ ребёнка —
    // его `prompt`, «task a» или «task b»).
    expect(rig.requests.keys, ['run both']);
  });

  test('для B дописана запись subagent{status: failed, failure: '
      'interrupted}; для A новых записей нет', () async {
    final store = MemorySessionStore()..putText(rootId, crashedJournal());
    final rig = SubagentRig(
      store: store,
      scripts: {
        'run both': [replyStep('Continuing.')],
      },
    );

    await rig.load(rootId);

    final subagents = records(store.textOf(rootId)!, 'subagent');
    expect(subagents, hasLength(4));
    final healed = subagents.last;
    expect(healed['subagentId'], 'sub_bbbbbbbb');
    expect(healed['toolCallId'], 'c2');
    expect(healed['status'], 'failed');
    expect(healed['failure'], 'interrupted');
    expect(
      subagents.where((r) => r['subagentId'] == 'sub_aaaaaaaa'),
      hasLength(2),
      reason: 'итоговая запись A уже есть, лечение её не дублирует',
    );
  });

  test('повторное открытие журнала ничего не дописывает: лечение '
      'идемпотентно', () async {
    final store = MemorySessionStore()..putText(rootId, crashedJournal());
    final first = SubagentRig(
      store: store,
      scripts: {
        'run both': [replyStep('x')],
      },
    );
    await first.load(rootId);
    final healed = store.textOf(rootId)!;

    final second = SubagentRig(
      store: store,
      scripts: {
        'run both': [replyStep('x')],
      },
    );
    await second.load(rootId);

    expect(store.textOf(rootId), healed);
  });
}
