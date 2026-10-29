import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../mcp/fake_mcp_connector.dart';
import '../permissions/fake_gate.dart';
import '../tools/fake_tools.dart';

const _base = ['read', 'write', 'edit', 'update_plan', 'ls', 'search'];

FakeTool _mcpTool(
  String name, {
  FutureOr<ToolExecutionResult> Function(
    Map<String, Object?> args,
    ToolContext ctx,
  )?
  onExecute,
}) => FakeTool(name, tier: ToolTier.exec, onExecute: onExecute);

McpStdioServerConfig _stdio(
  String name, {
  McpServerOrigin origin = McpServerOrigin.session,
}) =>
    McpStdioServerConfig(name: name, command: '/usr/bin/$name', origin: origin);

/// Инструменты `mcp__<сервер>__t` по одному на сервер: так фейковый коннектор
/// имитирует итог настоящего `replaceServers`.
List<AgentTool> _toolsOf(List<McpServerConfig> servers) => [
  for (final server in servers) _mcpTool('mcp__${server.name}__t'),
];

/// `AgentSession.setMcpServers` (agent-runtime «MCP-серверы сессии»,
/// `setMcpServers`; design.md change `add-agent-mcp-client`, D11): совпавшие
/// остаются, исчезнувшие закрыты, новые подключены, серверы конфига не
/// тронуты, во время хода — после `TurnEnded`.
///
/// Сравнение «совпало ли по `name` и параметрам» и закрытие процессов — дело
/// `McpSessionTools.replaceServers` (тест коннектора в `codelab_agent_mcp`);
/// здесь проверяется, что делает ядро: какой список передаёт, когда и как
/// обновляет набор модели.
void main() {
  CoreHarness harness(
    List<Map<String, Object?>> steps, {
    FakeMcpConnector? mcp,
    List<McpServerConfig> config = const [],
    Map<HostCapability, CapabilityState> narrow = const {},
  }) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: {...noExec, ...narrow},
    gate: FakeGate(),
    steps: steps,
    mcp: mcp,
    mcpServers: config,
  );

  Map<String, Object?> expectTools(List<String> tools) => {
    ...textStep('ok'),
    'expect': {'tools': tools},
  };

  Future<AgentSession> open(
    CoreHarness h, [
    List<McpServerConfig> servers = const [],
  ]) => h.core.runtime.createSession(
    SessionSpec(cwd: '/proj', mcpServers: servers),
  );

  List<String> names(List<McpServerConfig> servers) => [
    for (final s in servers) s.name,
  ];

  group('a session without a turn', () {
    test('the set is replaced at once; the next request has the new tools '
        'and the prompt', () async {
      final mcp = FakeMcpConnector(
        toolsOf: (_) => [_mcpTool('mcp__a__t')],
        toolsOnReplace: _toolsOf,
      );
      final h = harness([
        {
          ...textStep('ok'),
          'expect': {
            'tools': [..._base, 'mcp__b__t', 'mcp__c__t'],
            'systemPrompt': {r'$textContains': '- b:'},
          },
        },
      ], mcp: mcp);
      final session = await open(h, [_stdio('a')]);

      await session.setMcpServers([_stdio('b'), _stdio('c')]);

      expect(names(mcp.sessions.single.replaced.single), [
        'b',
        'c',
      ], reason: 'applied before the future completes');
      await session.prompt([const TextContent('hi')]);
      h.model.verify();
    });

    test('an empty list removes every server of the client', () async {
      final mcp = FakeMcpConnector(
        toolsOf: (_) => [_mcpTool('mcp__a__t')],
        toolsOnReplace: _toolsOf,
      );
      final h = harness([expectTools(_base)], mcp: mcp);
      final session = await open(h, [_stdio('a')]);

      await session.setMcpServers(const []);
      await session.prompt([const TextContent('hi')]);

      expect(mcp.sessions.single.replaced.single, isEmpty);
      h.model.verify();
    });

    test('servers of the config stay in the list in front of the servers of '
        'the client and are the same objects', () async {
      final cfg = _stdio('cfg', origin: McpServerOrigin.config);
      final mcp = FakeMcpConnector(toolsOf: (_) => const []);
      final h = harness(const [], mcp: mcp, config: [cfg]);
      final session = await open(h, [_stdio('a')]);

      await session.setMcpServers([_stdio('b')]);

      final list = mcp.sessions.single.replaced.single;
      expect(names(list), ['cfg', 'b']);
      expect(list.first, same(cfg), reason: 'not touched');
    });

    test('a server of the client replaces the config one with the same '
        'name; the skip of the config server is logged once, at the '
        'creation', () async {
      final mcp = FakeMcpConnector(toolsOf: (_) => const []);
      final h = harness(
        const [],
        mcp: mcp,
        config: [_stdio('github', origin: McpServerOrigin.config)],
      );
      final session = await open(h, [_stdio('github')]);
      List<Object?> skips() => h.logger
          .eventsOf('mcp.server.skipped')
          .map((r) => r.fields['reason'])
          .toList();
      expect(skips(), [
        'replaced by a server of the client with the same name',
      ]);

      await session.setMcpServers([_stdio('github')]);
      await session.setMcpServers([_stdio('github')]);

      final list = mcp.sessions.single.replaced.last;
      expect(list.single.origin, McpServerOrigin.session);
      expect(skips(), hasLength(1), reason: 'not logged again by the update');
    });

    test('a session that had no servers connects on the first call', () async {
      final mcp = FakeMcpConnector(toolsOf: (_) => [_mcpTool('mcp__a__t')]);
      final h = harness([
        expectTools([..._base, 'mcp__a__t']),
      ], mcp: mcp);
      final session = await open(h);
      expect(mcp.requests, isEmpty);

      await session.setMcpServers([_stdio('a')]);
      await session.prompt([const TextContent('hi')]);

      expect(names(mcp.requests.single.servers), ['a']);
      expect(mcp.requests.single.cwd, '/proj');
      expect(mcp.requests.single.reservedNames, _base.toSet());
      h.model.verify();
    });

    test('an empty name and a duplicate are skipped with a log', () async {
      final mcp = FakeMcpConnector(toolsOf: (_) => const []);
      final h = harness(const [], mcp: mcp);
      final session = await open(h, [_stdio('a')]);

      await session.setMcpServers([_stdio('b'), _stdio('b'), _stdio('')]);

      expect(names(mcp.sessions.single.replaced.single), ['b']);
      expect(
        h.logger.eventsOf('mcp.server.skipped').map((r) => r.fields['reason']),
        [contains('duplicate'), contains('empty')],
      );
    });

    test('without a connector the servers are skipped, not an error', () async {
      final h = harness([expectTools(_base)]);
      final session = await open(h);

      await session.setMcpServers([_stdio('a')]);
      await session.prompt([const TextContent('hi')]);

      expect(
        h.logger.eventsOf('mcp.server.skipped').single.fields['reason'],
        'сервис MCP не передан',
      );
      h.model.verify();
    });

    test('a failing connector keeps the previous set and is logged without '
        'the text of the error', () async {
      final mcp = FakeMcpConnector(
        toolsOf: (_) => [_mcpTool('mcp__a__t')],
        failReplaceWith: StateError('boom sk-123'),
      );
      final h = harness([
        expectTools([..._base, 'mcp__a__t']),
      ], mcp: mcp);
      final session = await open(h, [_stdio('a')]);

      await session.setMcpServers([_stdio('b')]);
      await session.prompt([const TextContent('hi')]);

      final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
      expect(failed['session_id'], session.id.value);
      expect(failed['reason'], 'MCP connector failed: StateError');
      expect('${h.logger.records}', isNot(contains('sk-123')));
      h.model.verify();
    });

    test('a closed session refuses the call', () async {
      final mcp = FakeMcpConnector();
      final h = harness(const [], mcp: mcp);
      final session = await open(h, [_stdio('a')]);
      await session.close();

      await expectLater(
        session.setMcpServers([_stdio('b')]),
        throwsA(isA<StateError>()),
      );
      expect(mcp.sessions.single.replaced, isEmpty);
    });
  });

  group('races and failures', () {
    test('of two calls without waiting the last one wins', () async {
      final mcp = FakeMcpConnector(toolsOf: (_) => [_mcpTool('mcp__a__t')]);
      final h = harness(const [], mcp: mcp);
      final session = await open(h, [_stdio('a')]);

      final first = session.setMcpServers([_stdio('b')]);
      final second = session.setMcpServers([_stdio('c')]);
      await Future.wait([first, second]);

      expect(mcp.sessions.single.replaced.map(names), [
        ['c'],
      ], reason: 'the stale set is not applied after the newer one');
    });

    test('close during a connection of a new server cancels it and does not '
        'wait for connectTimeout', () async {
      final mcp = FakeMcpConnector(
        toolsOf: (_) => [_mcpTool('mcp__a__t')],
        replaceBlocksUntilCancel: true,
      );
      final h = harness(const [], mcp: mcp);
      final session = await open(h, [_stdio('a')]);
      final applying = session.setMcpServers([_stdio('b')]);
      await pumpEventQueue();
      expect(mcp.sessions.single.replaced, hasLength(1), reason: 'in flight');

      await session.close();
      await applying;

      expect(mcp.requests.single.cancel.isCancelled, isTrue);
      expect(mcp.sessions.single.closed, 1);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('a failing refresh is logged with server and transport', () async {
      final mcp = FakeMcpConnector(
        toolsOf: (_) => [_mcpTool('mcp__a__t')],
        failToolsReadAfterReplace: true,
      );
      final h = harness(const [], mcp: mcp);
      final session = await open(h, [_stdio('a')]);

      await session.setMcpServers([_stdio('b'), _stdio('c')]);

      final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
      expect(failed['server'], 'b,c');
      expect(failed['transport'], 'stdio');
      expect(failed['reason'], 'MCP connector failed: StateError');
    });
  });

  group('a session with a turn', () {
    /// Ход с вызовом `mcp__a__t`, который висит, пока тест не отпустит
    /// [release]; затем ещё один ход с набором, каким он должен стать.
    ({
      CoreHarness h,
      FakeMcpConnector mcp,
      Completer<void> release,
      List<String> order,
    })
    build({List<String> nextTools = const []}) {
      final release = Completer<void>();
      final order = <String>[];
      late final FakeMcpConnector mcp;
      mcp = FakeMcpConnector(
        toolsOf: (_) => [
          _mcpTool(
            'mcp__a__t',
            onExecute: (_, ctx) async {
              await Future.any([release.future, ctx.cancel.onCancel]);
              ctx.cancel.throwIfCancelled();
              return const ToolExecutionResult([TextContent('done')]);
            },
          ),
        ],
        toolsOnReplace: (servers) {
          order.add('replace');
          return _toolsOf(servers);
        },
      );
      final inTurn = [..._base, 'mcp__a__t'];
      final h = harness([
        {
          'reply': [
            {
              'toolCall': {
                'id': 'c1',
                'name': 'mcp__a__t',
                'arguments': <String, Object?>{},
              },
            },
          ],
          'expect': {'tools': inTurn},
        },
        {
          ...textStep('done'),
          // Следующий шаг того же хода: набор прежний (D6, D11).
          'expect': {'tools': inTurn},
        },
        expectTools(nextTools.isEmpty ? inTurn : nextTools),
      ], mcp: mcp);
      return (h: h, mcp: mcp, release: release, order: order);
    }

    test('the call returns at once; the set changes after TurnEnded, never '
        'inside the turn', () async {
      final t = build(nextTools: [..._base, 'mcp__b__t']);
      final session = await open(t.h, [_stdio('a')]);
      session.events.listen((event) {
        if (event is TurnEnded) {
          t.order.add('TurnEnded');
        }
      });
      final turn = session.prompt([const TextContent('go')]);
      await pumpEventQueue();

      await session.setMcpServers([_stdio('b')]);
      expect(t.mcp.sessions.single.replaced, isEmpty);

      t.release.complete();
      await turn;
      // Следующий ход ждёт применения: набор уже новый.
      await session.prompt([const TextContent('next')]);

      expect(t.order.take(2), [
        'TurnEnded',
        'replace',
      ], reason: 'the set changes after the turn that was running');
      expect(names(t.mcp.sessions.single.replaced.single), ['b']);
      t.h.model.verify();
    });

    test('the last call during a turn wins', () async {
      final t = build(nextTools: [..._base, 'mcp__c__t']);
      final session = await open(t.h, [_stdio('a')]);
      final turn = session.prompt([const TextContent('go')]);
      await pumpEventQueue();

      await session.setMcpServers([_stdio('b')]);
      await session.setMcpServers([_stdio('c')]);
      t.release.complete();
      await turn;
      await session.prompt([const TextContent('next')]);

      expect(names(t.mcp.sessions.single.replaced.single), ['c']);
      t.h.model.verify();
    });

    test('close drops an update that waits for the end of the turn', () async {
      final t = build();
      final session = await open(t.h, [_stdio('a')]);
      final turn = session.prompt([const TextContent('go')]);
      await pumpEventQueue();
      await session.setMcpServers([_stdio('b')]);

      await session.close();
      await turn;

      expect(t.mcp.sessions.single.replaced, isEmpty);
      expect(t.mcp.sessions.single.closed, 1);
    });
  });
}
