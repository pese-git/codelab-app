import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart';
import '../support/models.dart';
import 'subagent_rig.dart';

/// Журнал субагента глубины 1 (agent-subagents «Журнал субагента и
/// прерывание», сценарий «Раскладка внука» в части глубины 1; agent-sessions
/// «Формат журнала JSONL», «Запись журнала из событий», «Дочерние журналы не
/// в списке сессий»; SUB-9, SUB-10; design.md change
/// `add-subagents-and-tasks`, D7, D36 Т4; `agent-core/17-3-subagents.md`
/// §17.3.6).
///
/// Красные до задач 2.4 и 2.7: нет `SessionStore.createChild`, поля заголовка
/// `parent` и записей `subagent`. Журналы читаются из `MemorySessionStore`
/// текстом: хранилище отдаёт его по id и для дочерних журналов.
void main() {
  List<Map<String, Object?>> lines(String text) => [
    for (final line in const LineSplitter().convert(text))
      jsonDecode(line) as Map<String, Object?>,
  ];

  /// Корень с одним ребёнком `explore` (режим типа — plan).
  Future<SubagentRig> oneChild() async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep(
            'c1',
            'agent',
            agentArgs(
              'find the parser',
              description: 'Find parser',
              type: 'explore',
            ),
          ),
          replyStep('thanks'),
        ],
        'find the parser': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}),
          replyStep('The parser is in lib/parser.dart'),
        ],
      },
    );
    await rig.open();
    await rig.run('go');
    return rig;
  }

  test('заголовок журнала ребёнка: поле parent с прямым родителем, корнем, '
      'вызовом, id, типом и глубиной 1', () async {
    final rig = await oneChild();

    final started = rig.eventsOf<SubagentStarted>().single;
    final child = lines(rig.store.textOf(started.childSessionId)!);

    expect(child.first['type'], 'session');
    expect(child.first['id'], started.childSessionId.value);
    expect(child.first['parent'], {
      'sessionId': rig.session.id.value,
      'rootSessionId': rig.session.id.value,
      'toolCallId': 'c1',
      'subagentId': started.subagentId,
      'agent': 'explore',
      'depth': 1,
    });
    expect(started.journalPath, isNotEmpty);
  });

  test(
    'первые записи журнала ребёнка: model_change, mode_change с '
    'эффективным режимом на запуске, затем user-сообщение с prompt',
    () async {
      final rig = await oneChild();

      final started = rig.eventsOf<SubagentStarted>().single;
      final child = lines(rig.store.textOf(started.childSessionId)!);

      expect(
        [for (final r in child.skip(1).take(3)) r['type']],
        ['model_change', 'mode_change', 'message'],
      );
      expect(child[2]['modeId'], 'plan', reason: 'тип explore работает в plan');
      final message = child[3]['message']! as Map<String, Object?>;
      expect(message['role'], 'user');
      expect(jsonEncode(message['content']), contains('find the parser'));
    },
  );

  test('записи subagent журнала родителя: running при получении слота и '
      'итоговая durable до результата вызова (SUB-10)', () async {
    final rig = await oneChild();

    final started = rig.eventsOf<SubagentStarted>().single;
    final root = lines(rig.rootJournal);
    final records = [
      for (final (i, r) in root.indexed)
        if (r['type'] == 'subagent') (i, r),
    ];
    expect(records, hasLength(2));
    final (runningAt, running) = records.first;
    final (finalAt, done) = records.last;
    expect(running['status'], 'running');
    expect(running['subagentId'], started.subagentId);
    expect(running['toolCallId'], 'c1');
    expect(running['agent'], 'explore');
    expect(running['description'], 'Find parser');
    expect(running['childSessionId'], started.childSessionId.value);
    expect(running['journal'], started.journalPath);
    expect(done['status'], 'completed');
    expect(done['report'], 'The parser is in lib/parser.dart');
    expect(done['toolCalls'], 1);
    expect(done['durationMs'], isA<int>());
    expect(done['usage'], isA<Map<String, Object?>>());
    // Записи — после сообщения с вызовом agent и до его результата.
    int messageIndex(String role, {String? toolCallId}) => root.indexWhere(
      (r) =>
          r['type'] == 'message' &&
          (r['message']! as Map)['role'] == role &&
          (toolCallId == null ||
              (r['message']! as Map)['toolCallId'] == toolCallId),
    );
    expect(runningAt, greaterThan(messageIndex('assistant')));
    expect(finalAt, lessThan(messageIndex('toolResult', toolCallId: 'c1')));
  });

  test('сценарий «Дочерние журналы не в списке сессий»: два ребёнка — '
      'listSessions возвращает одну сессию, open по id ребёнка — '
      'SessionNotFound', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          multiCallStep([
            ('c1', 'agent', agentArgs('child one', description: 'One')),
            ('c2', 'agent', agentArgs('child two', description: 'Two')),
          ]),
          replyStep('thanks'),
        ],
        'child one': [replyStep('one')],
        'child two': [replyStep('two')],
      },
    );
    await rig.open();
    await rig.run('go');

    final page = await rig.core.runtime.listSessions();
    final children = [
      for (final s in rig.eventsOf<SubagentStarted>()) s.childSessionId,
    ];

    expect(children, hasLength(2));
    expect(page.items.map((s) => s.id), [rig.session.id]);
    for (final id in children) {
      await expectLater(rig.store.open(id), throwsA(isA<SessionNotFound>()));
      await expectLater(
        rig.core.runtime.loadSession(id, const SessionHostPorts()),
        throwsA(isA<SessionNotFound>()),
        reason: 'D7: session/load с id ребёнка — «не найдена» (-32002)',
      );
    }
  });

  test('события ребёнка не пишутся в журнал родителя: SubagentProgress и '
      'SubagentActivity не оставляют записей (agent-sessions, таблица '
      'событий)', () async {
    final rig = await oneChild();

    final types = [for (final r in lines(rig.rootJournal)) r['type']];

    expect(types.where((t) => t == 'subagent'), hasLength(2));
    // Текст ответа ребёнка живёт в записи subagent и в результате вызова,
    // но отдельным сообщением родителя не является.
    final assistants = [
      for (final r in lines(rig.rootJournal))
        if (r['type'] == 'message' &&
            (r['message']! as Map)['role'] == 'assistant')
          r,
    ];
    expect(assistants, hasLength(2), reason: 'вызов agent и ответ "thanks"');
  });

  // Лечение журнала с итогом `max_tokens` (D41 п. 6; S-13; §17.3.6,
  // «Прерывание»). Красный до задачи 2.20: `parseFailure` не знает
  // `max_tokens` и читает его как `error`, поэтому вылеченный результат
  // получил бы тело «Subagent failed: …» и `reason="error"`, а не то, что
  // увидела бы модель в живом ходе. Журнал собран построчно: сбой процесса
  // между итоговой записью и результатом вызова в тесте невоспроизводим.
  test('итоговая запись failure: max_tokens после open даёт тот же результат, '
      'что и живой ход', () async {
    const rootId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
    final crashed = journal([
      header(cwd: '/proj', id: rootId.value),
      modelChange('m1', null),
      user('u1', 'm1', text: 'run it'),
      answer(
        'a1',
        'u1',
        calls: [
          ('c1', 'agent', {'description': 'Review it', 'prompt': 'task a'}),
        ],
      ),
      jsonEncode({
        'type': 'subagent',
        'id': 's1',
        'parentId': 'a1',
        'timestamp': at,
        'subagentId': 'sub_aaaaaaaa',
        'toolCallId': 'c1',
        'agent': 'review',
        'description': 'Review it',
        'status': 'failed',
        'failure': 'max_tokens',
        'report': '',
        'toolCalls': 2,
        'durationMs': 1500,
      }),
    ]);
    final store = MemorySessionStore()..putText(rootId, crashed);
    final rig = SubagentRig(
      store: store,
      scripts: {
        'run it': [replyStep('Continuing.')],
      },
    );

    await rig.load(rootId);
    await rig.run('continue');

    final request = rig.requestsOf('run it').single;
    final text = resultText(request, 'c1');
    expect(text, contains('status="failed"'));
    expect(text, contains('reason="max_tokens"'));
    expect(
      text,
      contains(
        'Subagent stopped: it hit the output token limit before writing a '
        'report.',
      ),
    );
    expect(resultIsError(request, 'c1'), isTrue);
    expect(rig.requests.keys, ['run it'], reason: 'ребёнок не перезапущен');
  });

  // Задача 3.6 (design.md, D43 п. 5; §17.3.6 «Атрибут `truncated` при
  // лечении»; agent-subagents «Усечённый отчёт после сбоя»). Журнал собран
  // построчно: сбой между итоговой записью и результатом вызова в тесте
  // невоспроизводим. Красные до кода: поле `truncated` записью не читается, и
  // вылеченная обёртка теряет атрибут, который есть у живого хода.
  Future<String> healedWrapper({required Map<String, Object?> extra}) async {
    const rootId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0D');
    final crashed = journal([
      header(cwd: '/proj', id: rootId.value),
      modelChange('m1', null),
      user('u1', 'm1', text: 'run it'),
      answer(
        'a1',
        'u1',
        calls: [
          ('c1', 'agent', {'description': 'Review it', 'prompt': 'task a'}),
        ],
      ),
      jsonEncode({
        'type': 'subagent',
        'id': 's1',
        'parentId': 'a1',
        'timestamp': at,
        'subagentId': 'sub_aaaaaaaa',
        'toolCallId': 'c1',
        'agent': 'review',
        'description': 'Review it',
        'status': 'completed',
        'report':
            'line 0\n[report truncated: 10 of 99 bytes shown; the full '
            'report is in the subagent journal]',
        'toolCalls': 2,
        'durationMs': 1500,
        ...extra,
      }),
    ]);
    final store = MemorySessionStore()..putText(rootId, crashed);
    final rig = SubagentRig(
      store: store,
      scripts: {
        'run it': [replyStep('Continuing.')],
      },
    );

    await rig.load(rootId);
    await rig.run('continue');

    return resultText(rig.requestsOf('run it').single, 'c1');
  }

  test('усечённый отчёт после сбоя: запись с truncated: true даёт обёртку '
      'с truncated="true", как живой ход', () async {
    final text = await healedWrapper(extra: {'truncated': true});

    expect(text, contains('status="completed"'));
    expect(text, contains('truncated="true"'));
  });

  test('запись без поля truncated (старый журнал) читается как не '
      'усечённая: обёртка без атрибута', () async {
    final text = await healedWrapper(extra: const {});

    expect(text, contains('status="completed"'));
    expect(text, isNot(contains('truncated=')));
  });

  test('живой ход: итоговая запись усечённого report_max_bytes отчёта '
      'несёт truncated: true, неусечённого — без поля', () async {
    Future<Map<String, Object?>> finalRecord(String reply) async {
      final rig = SubagentRig(
        config: CoreConfig(
          defaultModel: subagentTestModel,
          subagents: const SubagentsConfig(reportMaxBytes: 1024),
        ),
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('write the report')),
            replyStep('done'),
          ],
          'write the report': [replyStep(reply)],
        },
      );
      await rig.open();
      await rig.run('go');
      return lines(rig.rootJournal).lastWhere((r) => r['type'] == 'subagent');
    }

    final cut = await finalRecord(
      [for (var i = 0; i < 400; i++) 'line $i of the report'].join('\n'),
    );
    final whole = await finalRecord('short report');

    expect(cut['truncated'], isTrue);
    expect(whole.containsKey('truncated'), isFalse);
  });
}
