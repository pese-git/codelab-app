import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcNotification, JsonRpcResponse;
import 'package:test/test.dart';

import 'support/layered_config_source.dart';
import 'support/server_harness.dart';

/// Проекция вызова `agent` живьём через `AcpAgentServer` (agent-acp-server
/// «Вызов agent», «Итог субагента»; design.md change
/// `add-subagents-and-tasks` D24, D28; задачи 2.1 и 2.8).
///
/// Почему отдельный файл: сценарии идут через настоящее ядро со scripted
/// моделью, где шаги корня и ребёнка идут одним списком по порядку запросов;
/// ядро с `agent` и адаптерная проекция приходят задачами 2.3–2.8, поэтому
/// файл красный до них: инструмента `agent` в реестре сессии ещё нет, вызов
/// получает `title: "agent"`, `kind: other` и ошибку «unknown tool».
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  Map<String, Object?> agentCall(Map<String, Object?> args) => {
    'reply': [
      {
        'toolCall': {'id': 'call_1', 'name': 'agent', 'arguments': args},
      },
    ],
  };

  const exploreArgs = {
    'type': 'explore',
    'description': 'Find auth code',
    'prompt': 'Find where authentication is implemented.',
  };

  Future<String> ready(List<Map<String, Object?>> steps) async {
    // D40: `agent` виден модели с окном не меньше порога (32768), а модель
    // harness по умолчанию — 32000: окно задаёт конфиг теста.
    h = await ServerHarness.start(
      steps: steps,
      configSource: LayeredConfigSource(
        extra: {
          'providers': {
            'a': {
              'kind': 'openai-compatible',
              'base_url': 'https://a.test/v1',
              'models': {
                'm1': {'context_window': 65536},
              },
            },
          },
        },
      ),
    );
    await h.initialize();
    return h.newSession();
  }

  List<Map<String, Object?>> updatesBefore(JsonRpcResponse response) =>
      TestClient.updates(
        h.client.received.take(h.client.received.indexOf(response)),
      );

  Map<String, Object?> codelab(Map<String, Object?> update) =>
      ((update['_meta']! as Map)['codelab']! as Map).cast<String, Object?>();

  /// Читает кадры агента, пока не придёт `tool_call_update` со статусом.
  Future<void> untilStatus(String callId, String status) async {
    while (true) {
      final frame = await h.client.next();
      if (frame case JsonRpcNotification(:final params)) {
        final update = (params! as Map)['update']! as Map;
        if (update['toolCallId'] == callId && update['status'] == status) {
          return;
        }
      }
    }
  }

  test('the first frame has _meta.codelab.subagent {id, type}; the final '
      'update has the bare report and the summary of the child', () async {
    final sessionId = await ready([
      agentCall(exploreArgs),
      {
        'reply': [
          {'text': 'Auth lives in lib/auth.dart.'},
        ],
        'usage': {'input': 100, 'output': 20},
      },
      {
        'reply': [
          {'text': 'Done.'},
        ],
      },
    ]);

    final response = await h.prompt(sessionId, 'Where is auth?');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final updates = updatesBefore(response);
    final calls = updates.where((u) => u['sessionUpdate'] == 'tool_call');
    // Вызовов ребёнка клиент не видит (§17.3.7): единственный tool_call —
    // вызов `agent` корня.
    expect(calls.map((u) => u['toolCallId']), ['call_1']);
    final first = calls.single;
    expect(first['kind'], 'think');
    expect(first['title'], 'Subagent explore: Find auth code');
    expect(first['rawInput'], exploreArgs);
    final id = ((codelab(first)['subagent']! as Map)['id']! as String);
    expect(id, matches(r'^sub_[0-9a-z]{8}$'));
    expect((codelab(first)['subagent']! as Map)['type'], 'explore');

    final finished = updates.lastWhere(
      (u) => u['toolCallId'] == 'call_1' && u['status'] == 'completed',
    );
    // Отчёт — тело без обёртки `<subagent-report>` и без ограды.
    expect(finished['content'], [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': 'Auth lives in lib/auth.dart.'},
      },
    ]);
    final subagent = codelab(finished)['subagent']! as Map;
    expect(subagent['id'], id, reason: 'the same id as in the first frame');
    final summary = (subagent['summary']! as Map).cast<String, Object?>();
    expect(summary['toolCalls'], 0);
    expect(summary['tokens'], {'input': 100, 'output': 20});
    expect(summary['durationMs'], isA<int>());
  });

  test('a progress line arrives as tool_call_update with one text block '
      'between in_progress and completed', () async {
    final sessionId = await ready([
      agentCall(exploreArgs),
      {
        'reply': [
          {'text': 'Report.'},
        ],
      },
      {
        'reply': [
          {'text': 'Done.'},
        ],
      },
    ]);

    final response = await h.prompt(sessionId, 'Where is auth?');

    final forCall = [
      for (final u in updatesBefore(response))
        if (u['toolCallId'] == 'call_1' &&
            u['sessionUpdate'] == 'tool_call_update')
          u,
    ];
    expect(forCall.first['status'], 'in_progress');
    expect(forCall.last['status'], 'completed');
    final progress = forCall.where(
      (u) => u['status'] == 'in_progress' && u['content'] != null,
    );
    expect(progress, isNotEmpty);
    for (final update in progress) {
      final blocks = update['content']! as List;
      expect(blocks, hasLength(1));
      expect(
        (((blocks.single as Map)['content']) as Map)['text'],
        startsWith('explore · '),
      );
    }
  });

  // D28: id резервируется в `present` до `ToolCallStarted`, поэтому он есть в
  // первом кадре и отклонённого вызова; ребёнок и журнал не создаются, и
  // модель получает ошибку проверки (§17.3.2).
  test('a rejected call still has the id in the first frame but starts no '
      'child', () async {
    final sessionId = await ready([
      agentCall({...exploreArgs, 'description': 'x'}),
      {
        'reply': [
          {'text': 'Fixing the call.'},
        ],
      },
    ]);

    final response = await h.prompt(sessionId, 'Where is auth?');

    final updates = updatesBefore(response);
    final first = updates.firstWhere((u) => u['sessionUpdate'] == 'tool_call');
    expect(
      (codelab(first)['subagent']! as Map)['id'],
      matches(r'^sub_[0-9a-z]{8}$'),
    );
    final finished = updates.lastWhere(
      (u) => u['toolCallId'] == 'call_1' && u['status'] == 'failed',
    );
    expect(
      ((finished['content']! as List).single as Map)['content'],
      containsPair(
        'text',
        contains('Invalid agent call: description must be 3-60 characters.'),
      ),
    );
    expect(h.logger.eventsOf('subagent.start'), isEmpty);
    // Только два запроса корня: ребёнок не делал запросов к модели.
    expect(h.model.requests, hasLength(2));
  });

  // D24, второй вариант сценария «Итог субагента»: ход отменён во время
  // работы ребёнка — `failed` с `outcome: cancelled`, а `summary` с
  // фактическими значениями всё равно приходит.
  test('a cancelled turn: failed, outcome cancelled and the summary '
      'stays', () async {
    final sessionId = await ready([
      agentCall(exploreArgs),
      {'waitForCancel': true},
    ]);

    final turn = h.prompt(sessionId, 'Where is auth?');
    await untilStatus('call_1', 'in_progress');
    await pumpEventQueue();
    await h.client.notify('session/cancel', {'sessionId': sessionId});
    final response = await turn;

    expect(response.resultMap, {'stopReason': 'cancelled'});
    final finished = updatesBefore(
      response,
    ).lastWhere((u) => u['toolCallId'] == 'call_1' && u['status'] != null);
    expect(finished['status'], 'failed');
    final meta = codelab(finished);
    expect(meta['outcome'], 'cancelled');
    final subagent = meta['subagent']! as Map;
    expect(subagent['id'], matches(r'^sub_[0-9a-z]{8}$'));
    final summary = (subagent['summary']! as Map).cast<String, Object?>();
    expect(summary['toolCalls'], 0);
    expect(summary['durationMs'], isA<int>());
  });
}
