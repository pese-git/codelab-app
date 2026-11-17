import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcRequest, JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/layered_config_source.dart';
import 'support/server_harness.dart';

/// Вызовы потомков деревом живьём через `AcpAgentServer` (agent-acp-server
/// «Шаги потомков деревом»: «Вызовы ребёнка и внука», «Статусы вызова
/// потомка», «Запрос разрешения в строке своего вызова», «Клиент без
/// согласия», «Команда потомка через терминал клиента»; design.md change
/// `add-subagents-and-tasks` D21, D47 Т2–Т4, D48 п. 1; задача 5.1
/// `[protocol]`).
///
/// Почему отдельный файл: сценарии идут через настоящее ядро со scripted
/// моделью, где шаги корня, ребёнка и внука идут одним списком по порядку
/// запросов к модели. Файл охраняет проекцию вызовов потомков (цепочки,
/// терминал потомка, `in_progress` хуком хоста); тест «Клиент без согласия»
/// охраняет SUB-12.
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  /// Согласие клиента CodeLab на вызовы потомков (D9): целое `version: 1`.
  Map<String, Object?> clientCaps({required bool consent}) => {
    'fs': {'readTextFile': true, 'writeTextFile': true},
    'terminal': true,
    '_meta': {
      'codelab': {
        'tasks': {'version': 1},
        'subagents': {'version': 1},
        if (consent) 'subagentToolCalls': {'version': 1},
      },
    },
  };

  Map<String, Object?> toolCall(
    String id,
    String name,
    Map<String, Object?> args,
  ) => {
    'reply': [
      {
        'toolCall': {'id': id, 'name': name, 'arguments': args},
      },
    ],
  };

  Map<String, Object?> text(String value) => {
    'reply': [
      {'text': value},
    ],
  };

  Map<String, Object?> agentArgs(String type, String description) => {
    'type': type,
    'description': description,
    'prompt': 'Do the $description work and report.',
  };

  Future<String> ready(
    List<Map<String, Object?>> steps, {
    required bool consent,
    ExecutionEnv Function(String cwd)? localEnv,
  }) async {
    // D40: `agent` виден модели с окном не меньше порога (32768), а модель
    // harness по умолчанию — 32000: окно задаёт конфиг теста.
    h = await ServerHarness.start(
      steps: steps,
      localEnv: localEnv,
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
    await h.initialize(clientCapabilities: clientCaps(consent: consent));
    return h.newSession();
  }

  List<Map<String, Object?>> updatesBefore(JsonRpcResponse response) =>
      TestClient.updates(
        h.client.received.take(h.client.received.indexOf(response)),
      );

  Map<String, Object?> codelab(Map<String, Object?> update) =>
      (((update['_meta'] as Map?)?['codelab']) as Map? ?? const {})
          .cast<String, Object?>();

  /// Кадры вызова [id]: `<вид> <статус>` без строк прогресса (`content` у
  /// `in_progress`), по порядку.
  List<String> statusesOf(List<Map<String, Object?>> updates, String id) => [
    for (final u in updates)
      if (u['toolCallId'] == id &&
          !(u['status'] == 'in_progress' && u['content'] != null))
        '${u['sessionUpdate']} ${u['status']}',
  ];

  Future<MemoryExecutionEnv> files() async {
    final env = MemoryExecutionEnv(cwd: '/work/demo');
    await env.writeText('/work/demo/lib/auth.dart', 'void login() {}\n');
    await env.writeText('/work/demo/test/auth_test.dart', 'void main() {}\n');
    return env;
  }

  /// Ответ на `session/request_permission` и запись порядка кадров.
  void answerPermission(String optionId) =>
      h.client.handlers['session/request_permission'] = (_) => {
        'outcome': {'outcome': 'selected', 'optionId': optionId},
      };

  /// Терминал клиента: `terminal/create` → `term_1`, выход 0.
  void serveTerminal() {
    final handlers = h.client.handlers;
    handlers['terminal/create'] = (_) => {'terminalId': 'term_1'};
    handlers['terminal/wait_for_exit'] = (_) => {'exitCode': 0};
    handlers['terminal/output'] = (_) => {
      'output': 'done\n',
      'truncated': false,
      'exitStatus': {'exitCode': 0},
    };
    handlers['terminal/release'] = (_) => <String, Object?>{};
  }

  List<String> methodsOf(String prefix) => [
    for (final frame in h.client.received)
      if (frame case JsonRpcRequest(
        :final method,
      ) when method.startsWith(prefix))
        method,
  ];

  /// Шаги: корень поручает `general`; ребёнок читает файл и поручает внуку
  /// `explore`; внук читает файл; отчёты возвращаются вверх.
  List<Map<String, Object?>> treeSteps() => [
    toolCall('call_1', 'agent', agentArgs('general', 'Audit auth')),
    toolCall('call_1', 'read', {'path': 'lib/auth.dart'}),
    toolCall('call_2', 'agent', agentArgs('explore', 'List tests')),
    toolCall('call_1', 'read', {'path': 'test/auth_test.dart'}),
    text('Tests are in test/auth_test.dart.'),
    text('Auth is in lib/auth.dart.'),
    text('Done.'),
  ];

  // «Вызовы ребёнка и внука» (D47 Т2, Q16): цепочка `call_1/call_1`,
  // `call_1/call_2`, `call_1/call_2/call_1`, `parentToolCallId` и `{id, type}`
  // внука у вложенного `agent`, `summary` в его финальном обновлении, текстов
  // потомков в кадрах нет.
  test(
    'child and grandchild calls come as a tree of chained tool calls',
    () async {
      final sessionId = await ready(treeSteps(), consent: true);
      h.client.serveFiles(await files());

      final response = await h.prompt(sessionId, 'Audit the auth and tests');

      expect(response.resultMap, {'stopReason': 'end_turn'});
      final updates = updatesBefore(response);
      final calls = updates.where((u) => u['sessionUpdate'] == 'tool_call');
      expect(calls.map((u) => u['toolCallId']), [
        'call_1',
        'call_1/call_1',
        'call_1/call_2',
        'call_1/call_2/call_1',
      ]);
      expect(calls.map((u) => codelab(u)['parentToolCallId']), [
        null,
        'call_1',
        'call_1',
        'call_1/call_2',
      ]);
      final nested = calls.singleWhere(
        (u) => u['toolCallId'] == 'call_1/call_2',
      );
      expect(nested['kind'], 'think');
      final nestedSubagent = codelab(nested)['subagent']! as Map;
      expect(nestedSubagent['id'], matches(r'^sub_[0-9a-z]{8}$'));
      expect(nestedSubagent['type'], 'explore');

      final nestedFinal = updates.lastWhere(
        (u) => u['toolCallId'] == 'call_1/call_2' && u['status'] == 'completed',
      );
      final finalSubagent = codelab(nestedFinal)['subagent']! as Map;
      expect(finalSubagent['id'], nestedSubagent['id']);
      expect((finalSubagent['summary']! as Map)['toolCalls'], 1);
      expect(codelab(nestedFinal)['parentToolCallId'], 'call_1');
      // Тексты потомков не отправляются: единственный ответ — корня.
      final chunks = [
        for (final u in updates)
          if (u['sessionUpdate'] == 'agent_message_chunk')
            ((u['content']! as Map)['text']),
      ];
      expect(chunks.join(), 'Done.');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // «Статусы вызова потомка», D48 п. 1: `pending → in_progress → итог`, как у
  // вызова корня; `in_progress` шлёт хук хоста ядра, переданный потомкам
  // (после 5.3).
  test(
    'a descendant call goes pending, in_progress, then the result',
    () async {
      final sessionId = await ready(treeSteps(), consent: true);
      h.client.serveFiles(await files());

      final response = await h.prompt(sessionId, 'Audit the auth and tests');

      final updates = updatesBefore(response);
      for (final id in const [
        'call_1/call_1',
        'call_1/call_2',
        'call_1/call_2/call_1',
      ]) {
        expect(statusesOf(updates, id), [
          'tool_call pending',
          'tool_call_update in_progress',
          'tool_call_update completed',
        ], reason: id);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  List<Map<String, Object?>> reviewSteps({required String childText}) => [
    toolCall('call_1', 'agent', agentArgs('review', 'Check the diff')),
    toolCall('call_1', 'exec', {'command': 'git diff --stat'}),
    text(childText),
    text('Done.'),
  ];

  // «Запрос разрешения в строке своего вызова»: `tool_call` `call_1/call_1`
  // приходит раньше `session/request_permission` с тем же
  // `toolCall.toolCallId` (D42 Т5, D47 Т3).
  test(
    'the child tool_call precedes its permission request with the same id',
    () async {
      final sessionId = await ready(
        reviewSteps(childText: 'Rejected.'),
        consent: true,
      );
      answerPermission('reject_once');

      final response = await h.prompt(sessionId, 'Check the diff');

      expect(response.resultMap, {'stopReason': 'end_turn'});
      final received = h.client.received;
      final callIndex = received.indexWhere(
        (f) => TestClient.updates([f]).any(
          (u) =>
              u['sessionUpdate'] == 'tool_call' &&
              u['toolCallId'] == 'call_1/call_1',
        ),
      );
      final askIndex = received.indexWhere(
        (f) =>
            f is JsonRpcRequest &&
            f.method == 'session/request_permission' &&
            ((f.params! as Map)['toolCall'] as Map)['toolCallId'] ==
                'call_1/call_1',
      );
      expect(callIndex, isNonNegative, reason: 'tool_call of the child call');
      expect(askIndex, isNonNegative);
      expect(callIndex, lessThan(askIndex));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // «Статусы вызова потомка», вторая часть: у `exec`, требующего вопроса, —
  // `tool_call` (`pending`), `session/request_permission`, после ответа
  // `in_progress`, итог. Команда идёт на `localEnv` хоста: терминал клиента
  // здесь не нужен (его проверяет тест Т4 ниже).
  test('a child exec: pending, the question, in_progress after the answer, '
      'then the result', () async {
    final sessionId = await ready(
      reviewSteps(childText: 'Could not run it.'),
      consent: true,
      localEnv: (cwd) => MemoryExecutionEnv(cwd: cwd),
    );
    answerPermission('allow_once');

    final response = await h.prompt(sessionId, 'Check the diff');

    final received = h.client.received;
    int indexOfUpdate(String sessionUpdate, {String? status}) =>
        received.indexWhere(
          (f) => TestClient.updates([f]).any(
            (u) =>
                u['sessionUpdate'] == sessionUpdate &&
                u['toolCallId'] == 'call_1/call_1' &&
                (status == null || u['status'] == status),
          ),
        );
    final pending = indexOfUpdate('tool_call', status: 'pending');
    final inProgress = indexOfUpdate('tool_call_update', status: 'in_progress');
    final ask = received.indexWhere(
      (f) => f is JsonRpcRequest && f.method == 'session/request_permission',
    );
    expect(pending, isNonNegative);
    expect(inProgress, isNonNegative);
    expect(pending, lessThan(ask));
    expect(ask, lessThan(inProgress));
    final last = updatesBefore(
      response,
    ).lastWhere((u) => u['toolCallId'] == 'call_1/call_1');
    expect(last['status'], anyOf('completed', 'failed'));
  }, timeout: const Timeout(Duration(seconds: 30)));

  // «Клиент без согласия» (SUB-12): тот же сценарий без
  // `clientCapabilities._meta.codelab.subagentToolCalls` — кадров с id
  // потомков нет, остаётся один вызов `agent` корня, как в
  // `acp/prompt-subagent-tool-call`; запрос разрешения идёт по-прежнему с
  // цепочкой в `toolCallId` (agent-acp-server «Запрос разрешения ребёнка»).
  // Охраняет мост от протечки кадров потомков (SUB-12).
  test('a client without the consent gets only the agent call and the '
      'question with the chain', () async {
    final sessionId = await ready(
      reviewSteps(childText: 'Rejected.'),
      consent: false,
    );
    answerPermission('reject_once');

    final response = await h.prompt(sessionId, 'Check the diff');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final updates = updatesBefore(response);
    expect(
      updates
          .where((u) => u['sessionUpdate'] == 'tool_call')
          .map((u) => u['toolCallId']),
      ['call_1'],
    );
    expect(
      updates.where((u) => (u['toolCallId'] as String? ?? '').contains('/')),
      isEmpty,
    );
    expect(statusesOf(updates, 'call_1'), [
      'tool_call pending',
      'tool_call_update in_progress',
      'tool_call_update completed',
    ]);
    final ask = h.client.received.whereType<JsonRpcRequest>().singleWhere(
      (f) => f.method == 'session/request_permission',
    );
    expect(
      ((ask.params! as Map)['toolCall'] as Map)['toolCallId'],
      'call_1/call_1',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  // «Команда потомка через терминал клиента», дефект D47 Т4: `exec` потомка
  // идёт через тот же `AcpClientExecutionEnv` и после `terminal/create` ждёт
  // `terminalShown`, а мост завершал ожидание только по `ToolCallProgress`
  // корня. Команда ребёнка висела, если клиент объявил `terminal: true`.
  // Тест не должен висеть: ограничение по времени превращает зависание в
  // падение теста. Два варианта — с согласием и без: исполнение команды от
  // согласия не зависит.
  for (final consent in [true, false]) {
    test('a child exec runs through the client terminal '
        '(${consent ? 'with' : 'without'} the consent)', () async {
      final sessionId = await ready(
        reviewSteps(childText: 'Ran it.'),
        consent: consent,
      );
      answerPermission('allow_once');
      serveTerminal();

      final JsonRpcResponse response;
      try {
        response = await h.prompt(sessionId, 'Check the diff');
      } on TimeoutException {
        fail(
          'the child exec hangs (D47 Т4): terminal requests so far: '
          '${methodsOf('terminal/')}',
        );
      }

      expect(response.resultMap, {'stopReason': 'end_turn'});
      expect(
        methodsOf('terminal/'),
        containsAllInOrder(['terminal/create', 'terminal/wait_for_exit']),
      );
      final updates = updatesBefore(response);
      final terminalFrames = [
        for (final u in updates)
          if (u['toolCallId'] == 'call_1/call_1')
            for (final c in (u['content'] as List<Object?>?) ?? const [])
              if ((c! as Map)['type'] == 'terminal') c,
      ];
      if (consent) {
        // Клиент с согласием видит терминал в строке вызова ребёнка.
        expect(terminalFrames, [
          {'type': 'terminal', 'terminalId': 'term_1'},
        ]);
      } else {
        // Без согласия кадров вызова ребёнка нет вовсе (SUB-12).
        expect(
          updates.where(
            (u) => (u['toolCallId'] as String? ?? '').contains('/'),
          ),
          isEmpty,
        );
      }
      // Ребёнок получил результат и сдал отчёт корню.
      final report = updates.lastWhere(
        (u) => u['toolCallId'] == 'call_1' && u['status'] == 'completed',
      );
      expect(
        (((report['content']! as List).single as Map)['content']
            as Map)['text'],
        'Ran it.',
      );
    }, timeout: const Timeout(Duration(seconds: 10)));
  }
}
