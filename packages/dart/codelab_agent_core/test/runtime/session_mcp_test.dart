import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../mcp/fake_mcp_connector.dart';
import '../permissions/fake_gate.dart';
import '../session/recording_store.dart';
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
  Map<String, String> env = const {},
  List<String> args = const [],
}) => McpStdioServerConfig(
  name: name,
  command: '/usr/bin/$name',
  args: args,
  env: env,
  origin: origin,
);

McpHttpServerConfig _http(
  String name, {
  McpServerOrigin origin = McpServerOrigin.session,
  List<(String, String)> headers = const [],
}) => McpHttpServerConfig(
  name: name,
  url: Uri.parse('https://$name.example.com/mcp'),
  headers: headers,
  origin: origin,
);

/// MCP-серверы сессии (agent-runtime «MCP-серверы сессии»; design.md change
/// `add-agent-mcp-client`, D6): слияние, фильтр, изоляция, закрытие, журнал.
void main() {
  CoreHarness harness(
    List<Map<String, Object?>> steps, {
    FakeMcpConnector? mcp,
    List<McpServerConfig> config = const [],
    Map<HostCapability, CapabilityState> narrow = const {},
    SessionStore? sessions,
  }) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: {...noExec, ...narrow},
    gate: FakeGate(),
    sessions: sessions,
    steps: steps,
    mcp: mcp,
    mcpServers: config,
  );

  Map<String, Object?> expectTools(List<String> tools) => {
    ...textStep('ok'),
    'expect': {'tools': tools},
  };

  group('list of servers', () {
    test('config servers come first; a client server replaces the config one '
        'with the same name', () async {
      final mcp = FakeMcpConnector();
      final h = harness(
        const [],
        mcp: mcp,
        config: [
          _http('github', origin: McpServerOrigin.config),
          _stdio('extra', origin: McpServerOrigin.config),
        ],
      );

      await h.core.runtime.createSession(
        SessionSpec(
          cwd: '/proj',
          mcpServers: [_stdio('github'), _stdio('other')],
        ),
      );

      final servers = mcp.requests.single.servers;
      expect([for (final s in servers) s.name], ['extra', 'github', 'other']);
      expect(servers[1], isA<McpStdioServerConfig>());
      expect(servers[1].origin, McpServerOrigin.session);
    });

    test('a duplicate name and an empty name are skipped', () async {
      final mcp = FakeMcpConnector();
      final h = harness(const [], mcp: mcp);

      await h.core.runtime.createSession(
        SessionSpec(
          cwd: '/proj',
          mcpServers: [_stdio('a'), _stdio('a'), _stdio('')],
        ),
      );

      expect([for (final s in mcp.requests.single.servers) s.name], ['a']);
      final skipped = h.logger.eventsOf('mcp.server.skipped');
      expect(skipped, hasLength(2));
      expect(skipped.map((r) => r.fields['reason']), [
        contains('duplicate'),
        contains('empty'),
      ]);
      expect(skipped.first.fields['server'], 'a');
      expect(skipped.first.fields['transport'], 'stdio');
      expect(skipped.first.fields['session_id'], isA<String>());
    });

    test(
      'the request carries the cwd and the names of the base registry',
      () async {
        final mcp = FakeMcpConnector();
        final h = harness(const [], mcp: mcp);

        await h.core.runtime.createSession(
          SessionSpec(cwd: '/proj', mcpServers: [_stdio('a')]),
        );

        final request = mcp.requests.single;
        expect(request.cwd, '/proj');
        expect(request.reservedNames, _base.toSet());
        expect(request.sessionId.value, isNotEmpty);
      },
    );

    test('a session without servers does not call the connector', () async {
      final mcp = FakeMcpConnector();
      final h = harness([expectTools(_base)], mcp: mcp);

      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.prompt([const TextContent('hi')]);

      expect(mcp.requests, isEmpty);
      h.model.verify();
    });
  });

  group('capability filter', () {
    test('a capability that is off skips every server with the reason of the '
        'plan', () async {
      final h = harness([expectTools(_base)]);

      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('a'), _http('b')]),
      );
      await session.prompt([const TextContent('hi')]);

      final skipped = h.logger.eventsOf('mcp.server.skipped');
      expect(skipped, hasLength(2));
      for (final record in skipped) {
        expect(record.fields['reason'], 'сервис MCP не передан');
      }
      h.model.verify();
    });

    test(
      'a transport outside the capability is skipped with the profile',
      () async {
        final mcp = FakeMcpConnector(transports: {'http'});
        final h = harness(
          const [],
          mcp: mcp,
          narrow: {
            HostCapability.mcp: const CapabilityTransport({
              'http',
            }, 'без процессов'),
          },
        );

        await h.core.runtime.createSession(
          SessionSpec(cwd: '/proj', mcpServers: [_stdio('p'), _http('w')]),
        );

        expect([for (final s in mcp.requests.single.servers) s.name], ['w']);
        final skipped = h.logger.eventsOf('mcp.server.skipped').single.fields;
        expect(skipped['server'], 'p');
        expect(skipped['transport'], 'stdio');
        expect(
          skipped['reason'],
          'transport stdio is off in profile agent-serve: без процессов',
        );
      },
    );
  });

  group('registration and isolation', () {
    test('tools of the session follow the base ones in the request', () async {
      final mcp = FakeMcpConnector(
        toolsOf: (_) => [
          _mcpTool('mcp__fake__echo'),
          _mcpTool('mcp__fake__get'),
        ],
      );
      final h = harness([
        expectTools([..._base, 'mcp__fake__echo', 'mcp__fake__get']),
      ], mcp: mcp);

      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('fake')]),
      );
      await session.prompt([const TextContent('hi')]);

      h.model.verify();
      expect(
        h.core.plan.toolNames,
        _base,
        reason: 'CorePlan keeps only the base registry (D6)',
      );
    });

    test('another session does not see the tools', () async {
      final mcp = FakeMcpConnector(
        toolsOf: (request) =>
            request.servers.isEmpty ? const [] : [_mcpTool('mcp__fake__echo')],
      );
      final h = harness([
        expectTools([..._base, 'mcp__fake__echo']),
        expectTools(_base),
      ], mcp: mcp);
      final a = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('fake')]),
      );
      final b = await h.core.runtime.createSession(SessionSpec(cwd: '/proj'));

      await a.prompt([const TextContent('hi')]);
      await b.prompt([const TextContent('hi')]);

      h.model.verify();
    });

    test('loadSession connects the servers given by the client', () async {
      final store = MemorySessionStore();
      final first = harness(const [], sessions: store);
      final created = await first.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await created.close();
      final mcp = FakeMcpConnector(
        toolsOf: (_) => [_mcpTool('mcp__fake__echo')],
      );
      final h = harness(
        [
          expectTools([..._base, 'mcp__fake__echo']),
        ],
        mcp: mcp,
        sessions: store,
      );

      final loaded = await h.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
        mcpServers: [_stdio('fake')],
      );
      await loaded.prompt([const TextContent('hi')]);

      expect([for (final s in mcp.requests.single.servers) s.name], ['fake']);
      h.model.verify();
    });
  });

  group('list_changed at a step boundary (D6)', () {
    test('a new tool appears for the next step, never inside a pack', () async {
      late final FakeMcpConnector mcp;
      final first = _mcpTool(
        'mcp__fake__a',
        onExecute: (_, _) {
          // Уведомление пришло, пока исполняется пакет вызовов.
          mcp.sessions.single.pending = McpToolsUpdate(
            tools: [
              _mcpTool('mcp__fake__a'),
              _mcpTool('mcp__fake__b'),
              _mcpTool('mcp__fake__lookup'),
            ],
            servers: const [McpServerSummary(name: 'fake', toolCount: 3)],
          );
          return const ToolExecutionResult([TextContent('a done')]);
        },
      );
      final second = _mcpTool('mcp__fake__b');
      mcp = FakeMcpConnector(toolsOf: (_) => [first, second]);
      final h = harness([
        {
          'reply': [
            {
              'toolCall': {
                'id': 'c1',
                'name': 'mcp__fake__a',
                'arguments': <String, Object?>{},
              },
            },
            {
              'toolCall': {
                'id': 'c2',
                'name': 'mcp__fake__b',
                'arguments': <String, Object?>{},
              },
            },
          ],
          'expect': {
            'tools': [..._base, 'mcp__fake__a', 'mcp__fake__b'],
          },
        },
        {
          ...textStep('done'),
          'expect': {
            'tools': [
              ..._base,
              'mcp__fake__a',
              'mcp__fake__b',
              'mcp__fake__lookup',
            ],
            'systemPrompt': {r'$textContains': '- fake: 3 tools'},
          },
        },
      ], mcp: mcp);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('fake')]),
      );

      await session.prompt([const TextContent('go')]);

      h.model.verify();
      expect(
        second.executed,
        hasLength(1),
        reason: 'the old set served the pack',
      );
    });

    test(
      'an update that arrived between turns is applied before the next turn',
      () async {
        final mcp = FakeMcpConnector(
          toolsOf: (_) => [_mcpTool('mcp__fake__a')],
        );
        final h = harness([
          expectTools([..._base, 'mcp__fake__a']),
          expectTools([..._base, 'mcp__fake__a', 'mcp__fake__new']),
        ], mcp: mcp);
        final session = await h.core.runtime.createSession(
          SessionSpec(cwd: '/proj', mcpServers: [_stdio('fake')]),
        );
        await session.prompt([const TextContent('one')]);

        mcp.sessions.single.pending = McpToolsUpdate(
          tools: [_mcpTool('mcp__fake__a'), _mcpTool('mcp__fake__new')],
          servers: const [McpServerSummary(name: 'fake', toolCount: 2)],
        );
        await session.prompt([const TextContent('two')]);

        h.model.verify();
      },
    );
  });

  group('close', () {
    test('transports close after the turn is idle', () async {
      final order = <String>[];
      final blocking = _mcpTool(
        'mcp__fake__wait',
        onExecute: (_, ctx) async {
          await ctx.cancel.onCancel;
          order.add('tool cancelled');
          throw const CancelledException(null);
        },
      );
      final mcp = FakeMcpConnector(
        toolsOf: (_) => [blocking],
        onClose: () => order.add('mcp closed'),
      );
      final h = harness([
        {
          'reply': [
            {
              'toolCall': {
                'id': 'c1',
                'name': 'mcp__fake__wait',
                'arguments': <String, Object?>{},
              },
            },
          ],
        },
      ], mcp: mcp);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('fake')]),
      );
      final turn = session.prompt([const TextContent('go')]);
      await pumpEventQueue();

      await session.close();
      await turn;

      expect(order, ['tool cancelled', 'mcp closed']);
      expect(mcp.sessions.single.closed, 1);
    });

    test('dispose closes the servers of every session', () async {
      final mcp = FakeMcpConnector();
      final h = harness(const [], mcp: mcp);
      await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('a')]),
      );
      await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('b')]),
      );

      await h.core.runtime.dispose();

      expect(mcp.sessions.map((s) => s.closed), [1, 1]);
    });
  });

  group('journal', () {
    test('descriptions of servers are never written (D6, D13)', () async {
      final store = MemorySessionStore();
      final mcp = FakeMcpConnector(
        toolsOf: (_) => [_mcpTool('mcp__fake__echo')],
      );
      final h = harness(
        [
          {
            'reply': [
              {
                'toolCall': {
                  'id': 'c1',
                  'name': 'mcp__fake__echo',
                  'arguments': <String, Object?>{},
                },
              },
            ],
          },
          textStep('done'),
        ],
        mcp: mcp,
        sessions: store,
      );
      final session = await h.core.runtime.createSession(
        SessionSpec(
          cwd: '/proj',
          mcpServers: [
            _stdio(
              'fake',
              env: {'API_KEY': 'sk-123'},
              args: ['--token', 'arg-secret'],
            ),
            _http('web', headers: [('Authorization', 'Bearer t-456')]),
          ],
        ),
      );

      await session.prompt([const TextContent('go')]);
      await session.close();

      final journal = store.textOf(session.id)!;
      for (final secret in [
        'sk-123',
        'arg-secret',
        'Bearer t-456',
        '/usr/bin/fake',
        'web.example.com',
        'API_KEY',
        'Authorization',
      ]) {
        expect(journal, isNot(contains(secret)), reason: secret);
      }
      expect(journal, contains('mcp__fake__echo'), reason: 'calls are written');
    });
  });

  group('robustness', () {
    test(
      'a connector that throws leaves the session without MCP (D13 fields)',
      () async {
        final mcp = FakeMcpConnector(failWith: StateError('boom sk-123'));
        final h = harness([expectTools(_base)], mcp: mcp);

        final session = await h.core.runtime.createSession(
          SessionSpec(cwd: '/proj', mcpServers: [_stdio('a'), _http('b')]),
        );
        await session.prompt([const TextContent('hi')]);

        h.model.verify();
        final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
        expect(failed['session_id'], session.id.value);
        expect(failed['server'], 'a,b');
        expect(failed['transport'], 'stdio,http');
        expect(failed['reason'], 'MCP connector failed: StateError');
        expect('${h.logger.records}', isNot(contains('sk-123')));
      },
    );

    test('a failing journal closes the servers that were connected', () async {
      final store = RecordingStore()..failAppends = true;
      final mcp = FakeMcpConnector(toolsOf: (_) => [_mcpTool('mcp__fake__a')]);
      final h = harness(const [], mcp: mcp, sessions: store);

      await expectLater(
        h.core.runtime.createSession(
          SessionSpec(cwd: '/proj', mcpServers: [_stdio('fake')]),
        ),
        throwsA(isA<StateError>()),
      );

      expect(mcp.sessions.single.closed, 1);
    });

    test('a failing loadSession closes the servers too', () async {
      final store = RecordingStore();
      final first = harness(const [], sessions: store);
      final created = await first.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await created.close();
      final mcp = FakeMcpConnector();
      final h = harness(const [], mcp: mcp, sessions: store);
      // Запись `cwd_changed` падает уже после подключения серверов.
      store.failAppends = true;

      await expectLater(
        h.core.runtime.loadSession(
          created.id,
          const SessionHostPorts(),
          cwd: '/other',
          mcpServers: [_stdio('fake')],
        ),
        throwsA(isA<StateError>()),
      );

      expect(mcp.sessions.single.closed, 1);
    });

    test(
      'a tool without the mcp__ prefix or with a built-in name is not registered',
      () async {
        final mcp = FakeMcpConnector(
          toolsOf: (_) => [
            _mcpTool('read'),
            _mcpTool('plain'),
            _mcpTool('mcp__fake__ok'),
          ],
        );
        final h = harness([
          expectTools([..._base, 'mcp__fake__ok']),
        ], mcp: mcp);

        final session = await h.core.runtime.createSession(
          SessionSpec(cwd: '/proj', mcpServers: [_stdio('fake')]),
        );
        await session.prompt([const TextContent('hi')]);

        h.model.verify();
        final invalid = h.logger.eventsOf('mcp.tool.invalid');
        expect(invalid.map((r) => r.fields['tool']), ['read', 'plain']);
      },
    );

    test('dispose cancels the token handed to the connector', () async {
      final mcp = FakeMcpConnector();
      final h = harness(const [], mcp: mcp);
      await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('a')]),
      );
      final cancel = mcp.requests.single.cancel;
      expect(cancel.isCancelled, isFalse);

      await h.core.runtime.dispose();

      expect(cancel.isCancelled, isTrue);
    });
  });
}
