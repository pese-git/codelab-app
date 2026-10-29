// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/core_stack.dart';
import 'support/harness.dart';

/// Задача 9.3 change `add-agent-mcp-client` (agent-mcp-client «Обновление
/// списка инструментов», оба сценария; design.md D6): `tools/list_changed`
/// применяется только на границе шага, до сборки следующего запроса к
/// модели, и никогда внутри пакета вызовов.
///
/// Тесты идут через настоящее ядро (`buildAgentCore`) с `McpClientConnector`
/// над `FakeMcpServer`: проверяется весь путь «уведомление → перечитывание →
/// `takeUpdate` → `StepUpdate.tools` / `StepUpdate.systemPrompt`».

const _slow = FakeMcpTool('slow');
const _echo = FakeMcpTool('echo');
const _lookup = FakeMcpTool('lookup');

List<String> _mcpNames(LlmContext context) => [
  for (final tool in context.tools)
    if (tool.name.startsWith('mcp__')) tool.name,
];

Map<String, Object?> _call(String id, String tool) => {
  'toolCall': {'id': id, 'name': tool, 'arguments': <String, Object?>{}},
};

/// Пока исполняется `mcp__fake__slow`, сервер объявляет новый набор.
Future<void> _announceDuringSlowCall(
  FakeMcpServer server,
  Completer<Map<String, Object?>> gate,
  List<FakeMcpTool> fresh, {
  int times = 1,
  Object? subscriptionId,
}) async {
  // Ожидание ограничено: зависший сценарий падает, а не крутится вечно.
  for (var i = 0; i < 100 && server.calls.isEmpty; i++) {
    await pumpEventQueue();
  }
  expect(server.calls, isNotEmpty);
  for (var i = 0; i < times; i++) {
    server.notifyToolsListChanged(
      newTools: fresh,
      subscriptionId: subscriptionId,
    );
  }
  await pumpEventQueue();
  gate.complete({
    'content': [
      {'type': 'text', 'text': 'slow done'},
    ],
  });
}

void main() {
  for (final era in [FakeMcpEra.modern, FakeMcpEra.legacy]) {
    group('${era.name}: a notification in the middle of a pack', () {
      late Completer<Map<String, Object?>> gate;
      late FakeMcpServer server;
      late CoreStack stack;

      setUp(() {
        gate = Completer();
        server = FakeMcpServer(
          era: era,
          tools: [_slow, _echo],
          listChanged: true,
          responses: {'slow': FakeToolResponse.gated(gate)},
        );
        stack = CoreStack.build(
          server: server,
          steps: [
            {
              'reply': [
                _call('c1', 'mcp__fake__slow'),
                _call('c2', 'mcp__fake__echo'),
              ],
            },
            {
              'reply': [
                {'text': 'done'},
              ],
            },
          ],
          gate: (_) => _AllowAll(),
        );
      });

      test('applies to the next request only; the pack runs on the old set; '
          'the mcp section is rebuilt; mcp.tools.changed is logged', () async {
        final session = await stack.session();
        final turn = session.prompt([const TextContent('go')]);

        await _announceDuringSlowCall(server, gate, [_slow, _echo, _lookup]);
        await turn;

        final requests = stack.model.requests;
        expect(requests, hasLength(2));
        expect(_mcpNames(requests[0]), ['mcp__fake__slow', 'mcp__fake__echo']);
        expect(_mcpNames(requests[1]), [
          'mcp__fake__slow',
          'mcp__fake__echo',
          'mcp__fake__lookup',
        ]);
        // Пакет исполнился по прежнему набору.
        expect(server.calls.map((c) => c['name']), ['slow', 'echo']);
        expect(requests[0].systemPrompt, contains('- fake: 2 tools'));
        expect(requests[1].systemPrompt, contains('- fake: 3 tools'));
        final changed = stack.logger.eventsOf('mcp.tools.changed').single;
        expect(changed.fields, containsPair('server', 'fake'));
        expect(changed.fields['added'], ['mcp__fake__lookup']);
        expect(changed.fields['removed'], isEmpty);
      });

      test('two notifications give at most two tools/list', () async {
        final session = await stack.session();
        final listsBefore = server.methods
            .where((m) => m == 'tools/list')
            .length;
        final turn = session.prompt([const TextContent('go')]);

        await _announceDuringSlowCall(server, gate, [
          _slow,
          _echo,
          _lookup,
        ], times: 2);
        await turn;

        final lists =
            server.methods.where((m) => m == 'tools/list').length - listsBefore;
        expect(lists, inInclusiveRange(1, 2));
        expect(
          _mcpNames(stack.model.requests[1]),
          contains('mcp__fake__lookup'),
        );
      });
    });
  }

  group('whose notification is accepted', () {
    late McpHarness h;
    setUp(() => h = McpHarness());

    test(
      'modern: only with the subscriptionId of its own subscription',
      () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        final seen = <int>[];
        await h.connect(server, onToolsChanged: (t) => seen.add(t.length));

        server.notifyToolsListChanged(
          newTools: [_echo, _lookup],
          subscriptionId: 'someone-else',
        );
        await h.clock.elapse(Duration.zero);
        expect(seen, isEmpty);
        expect(
          h.logger
              .eventsOf('mcp.message.ignored')
              .where((r) => r.fields['kind'] == 'unknown_notification'),
          hasLength(1),
        );

        server.notifyToolsListChanged(newTools: [_echo, _lookup]);
        await h.clock.elapse(Duration.zero);
        expect(seen, [2]);
      },
    );

    test('legacy: from the common channel, without a subscription', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        listChanged: true,
      );
      final seen = <int>[];
      await h.connect(server, onToolsChanged: (t) => seen.add(t.length));

      server.notifyToolsListChanged(newTools: [_echo, _lookup]);
      await h.clock.elapse(Duration.zero);

      expect(seen, [2]);
      expect(server.subscriptions, 0);
    });
  });

  group('collision in the new set', () {
    test('disables the server whose update caused it; the other stays, the '
        'mcp section is rebuilt', () async {
      // Имена серверов после замены символов совпадают (`my.srv` → `my_srv`),
      // поэтому одинаковые имена инструментов дают одинаковые имена для модели.
      final updater = FakeMcpServer(
        tools: [const FakeMcpTool('a')],
        listChanged: true,
      );
      final later = FakeMcpServer(tools: [const FakeMcpTool('t')]);
      final stack = CoreStack.build(
        server: updater,
        transports: McpTransports(
          stdio: FakeMcpTransportFactory({'my.srv': updater, 'my_srv': later}),
        ),
        servers: const [
          McpStdioServerConfig(name: 'my.srv', command: 'a'),
          McpStdioServerConfig(name: 'my_srv', command: 'b'),
        ],
        steps: [
          {
            'reply': [
              {'text': 'first'},
            ],
          },
          {
            'reply': [
              {'text': 'second'},
            ],
          },
        ],
        gate: (_) => _AllowAll(),
      );
      final session = await stack.session();
      await session.prompt([const TextContent('one')]);

      // Более ранний сервер присылает имя, уже занятое более поздним:
      // отключается тот, чьё обновление вызвало коллизию.
      updater.notifyToolsListChanged(newTools: [const FakeMcpTool('t')]);
      await pumpEventQueue();
      await session.prompt([const TextContent('two')]);

      final requests = stack.model.requests;
      expect(_mcpNames(requests[0]), ['mcp__my_srv__a', 'mcp__my_srv__t']);
      expect(_mcpNames(requests[1]), ['mcp__my_srv__t']);
      expect(requests[1].systemPrompt, contains('- my_srv: 1 tool'));
      final failed = stack.logger.eventsOf('mcp.server.failed').single;
      expect(failed.fields['server'], 'my.srv');
      expect(failed.fields['reason'], contains('collides'));
      expect(updater.closedTransports, 1);
      expect(later.closedTransports, 0);
    });
  });
}

final class _AllowAll implements PermissionGate {
  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async => PermissionDecision.allowOnce;
}
