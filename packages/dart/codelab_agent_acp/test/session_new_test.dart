import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' hide SessionId;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «session/new» (задача 2.4, §13.4, ACP-8).
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  Future<JsonRpcResponse> newSession(
    String cwd, {
    List<Object?> mcpServers = const [],
  }) => h.client.request('session/new', {'cwd': cwd, 'mcpServers': mcpServers});

  test('modes and options; commands only after the answer', () async {
    h = await ServerHarness.start();
    await h.initialize();

    final response = await newSession('/work/demo');

    final result = response.resultMap;
    final sessionId = result['sessionId']! as String;
    expect(sessionId, hasLength(26));
    expect(result['modes'], {
      'currentModeId': 'standard',
      'availableModes': [
        {
          'id': 'plan',
          'name': 'Plan',
          'description': 'Read and plan only, no changes',
        },
        {
          'id': 'ask',
          'name': 'Ask',
          'description': 'Approve every call, including reads',
        },
        {
          'id': 'standard',
          'name': 'Standard',
          'description':
              'Reads without asking, edits and commands with approval',
        },
        {
          'id': 'accept-edits',
          'name': 'Accept edits',
          'description':
              'Reads and edits without asking, commands and network with approval',
        },
        {
          'id': 'bypass',
          'name': 'Bypass',
          'description':
              'No approval except for critical commands, agent config edits and network access',
        },
      ],
    });
    expect(result['configOptions'], [
      {
        'id': 'mode',
        'name': 'Mode',
        'category': 'mode',
        'type': 'select',
        'currentValue': 'standard',
        'options': [
          {'value': 'plan', 'name': 'Plan'},
          {'value': 'ask', 'name': 'Ask'},
          {'value': 'standard', 'name': 'Standard'},
          {'value': 'accept-edits', 'name': 'Accept edits'},
          {'value': 'bypass', 'name': 'Bypass'},
        ],
      },
      {
        'id': 'model',
        'name': 'Model',
        'category': 'model',
        'type': 'select',
        'currentValue': 'scripted/scripted-1',
        'options': [
          {'value': 'scripted/scripted-1', 'name': 'scripted-1'},
        ],
      },
    ]);

    final commands = (await h.client.next()) as JsonRpcNotification;
    expect(commands.method, 'session/update');
    expect(commands.params, {
      'sessionId': sessionId,
      'update': {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': <Object?>[],
      },
    });
    // ACP-8: до ответа на session/new уведомлений сессии нет.
    final order = h.client.received;
    expect(order.indexOf(response), lessThan(order.indexOf(commands)));
  });

  test('a relative cwd is -32602 and no session is created', () async {
    h = await ServerHarness.start();
    await h.initialize();

    final response = await newSession('work/demo');

    expect(response.errorCode, jsonRpcInvalidParamsCode);
    expect(
      await h.store.list(),
      isA<SessionPage>().having((p) => p.items, 'items', isEmpty),
    );
  });

  test('with local listing a missing directory is -32602', () async {
    final local = MemoryExecutionEnv(cwd: '/work/demo');
    h = await ServerHarness.start(localListing: (_) => local);
    await h.initialize();

    final missing = await newSession('/work/elsewhere');
    final present = await newSession('/work/demo');

    expect(missing.errorCode, jsonRpcInvalidParamsCode);
    expect(present.error, isNull);
  });

  // --- MCP-серверы сессии (agent-acp-server «session/new», шаг 2; D11) ---

  const stdioFake = {
    'name': 'fake',
    'command': 'fake-mcp',
    'args': ['--stdio'],
    'env': [
      {'name': 'TOKEN', 'value': 'first'},
      {'name': 'TOKEN', 'value': 'last'},
    ],
  };
  const httpWeb = {
    'type': 'http',
    'name': 'web',
    'url': 'https://example.com/mcp',
    'headers': [
      {'name': 'Authorization', 'value': 'Bearer x'},
      {'name': 'X-Second', 'value': '2'},
    ],
  };

  List<Map<String, Object?>> skipped() => [
    for (final e in h.logger.eventsOf('mcp.server.skipped')) e.fields,
  ];

  test(
    'stdio and http servers map to McpServerConfig of the session',
    () async {
      final spy = SpyMcpConnector();
      h = await ServerHarness.start(mcp: (_) => spy);
      await h.initialize();

      final response = await newSession(
        '/work/demo',
        mcpServers: [stdioFake, httpWeb],
      );

      expect(response.error, isNull);
      final servers = spy.requests.single.servers;
      expect(servers, hasLength(2));
      final stdio = servers[0] as McpStdioServerConfig;
      expect(stdio.name, 'fake');
      expect(stdio.command, 'fake-mcp');
      expect(stdio.args, ['--stdio']);
      // При повторе имени побеждает последнее значение.
      expect(stdio.env, {'TOKEN': 'last'});
      expect(stdio.origin, McpServerOrigin.session);
      final http = servers[1] as McpHttpServerConfig;
      expect(http.url, Uri.parse('https://example.com/mcp'));
      expect(http.headers, [('Authorization', 'Bearer x'), ('X-Second', '2')]);
      expect(http.origin, McpServerOrigin.session);
      expect(skipped(), isEmpty);
    },
  );

  test('an sse server is skipped with mcp.server.skipped', () async {
    final spy = SpyMcpConnector();
    h = await ServerHarness.start(mcp: (_) => spy);
    await h.initialize();

    final response = await newSession(
      '/work/demo',
      mcpServers: [
        {
          'type': 'sse',
          'name': 'old',
          'url': 'https://example.com/sse',
          'headers': <Object?>[],
        },
        stdioFake,
      ],
    );

    expect(response.error, isNull);
    expect(skipped(), [containsPair('server', 'old')]);
    expect(skipped().single, containsPair('transport', 'sse'));
    expect(
      skipped().single,
      containsPair('reason', 'transport sse is not supported'),
    );
    expect(skipped().single, contains('session_id'));
    // Остальные серверы передаются ядру.
    expect([for (final s in spy.requests.single.servers) s.name], ['fake']);
  });

  test('an unknown transport is skipped and the session is created', () async {
    final spy = SpyMcpConnector();
    h = await ServerHarness.start(mcp: (_) => spy);
    await h.initialize();

    final response = await newSession(
      '/work/demo',
      mcpServers: [
        {'type': 'websocket', 'name': 'future', 'url': 'wss://x', 'extra': 1},
        stdioFake,
      ],
    );

    expect(response.error, isNull);
    expect(response.resultMap['sessionId'], isA<String>());
    expect(skipped().single, containsPair('server', 'future'));
    expect(skipped().single, containsPair('transport', 'websocket'));
    expect(skipped().single, containsPair('reason', 'unknown transport'));
    expect([for (final s in spy.requests.single.servers) s.name], ['fake']);
  });

  test('an unparsable http url is skipped and stdio still connects', () async {
    final spy = SpyMcpConnector();
    h = await ServerHarness.start(mcp: (_) => spy);
    await h.initialize();

    final response = await newSession(
      '/work/demo',
      mcpServers: [
        {
          'type': 'http',
          'name': 'web',
          'url': 'http://[',
          'headers': <Object?>[],
        },
        stdioFake,
      ],
    );

    expect(response.error, isNull);
    expect(skipped().single, containsPair('reason', 'invalid url'));
    expect(skipped().single, containsPair('server', 'web'));
    expect([for (final s in spy.requests.single.servers) s.name], ['fake']);
  });

  test(
    'skip logs carry session_id and cap client strings at 64 runes',
    () async {
      h = await ServerHarness.start(mcp: (_) => SpyMcpConnector());
      await h.initialize();
      final long = 'я' * 200;

      final response = await newSession(
        '/work/demo',
        mcpServers: [
          {'type': 'websocket', 'name': long},
          {'type': long, 'name': 'future'},
        ],
      );

      final sessionId = response.resultMap['sessionId']! as String;
      final logs = skipped();
      expect(logs, hasLength(2));
      for (final fields in logs) {
        expect(fields['session_id'], sessionId);
        expect(
          (fields['server']! as String).runes.length,
          lessThanOrEqualTo(64),
        );
        expect(
          (fields['transport']! as String).runes.length,
          lessThanOrEqualTo(64),
        );
      }
      expect(logs[0]['server'], 'я' * 64);
      expect(logs[1]['transport'], 'я' * 64);
    },
  );

  test('an unknown transport without a name is skipped too', () async {
    h = await ServerHarness.start(mcp: (_) => SpyMcpConnector());
    await h.initialize();

    final response = await newSession(
      '/work/demo',
      mcpServers: [
        {'type': 'websocket', 'url': 'wss://x'},
      ],
    );

    expect(response.error, isNull);
    expect(skipped().single, containsPair('reason', 'unknown transport'));
  });

  test('a known type stays strict: http without url is -32602', () async {
    h = await ServerHarness.start(mcp: (_) => SpyMcpConnector());
    await h.initialize();

    final response = await newSession(
      '/work/demo',
      mcpServers: [
        {'type': 'http', 'name': 'web', 'headers': <Object?>[]},
      ],
    );

    expect(response.errorCode, jsonRpcInvalidParamsCode);
    expect(
      await h.store.list(),
      isA<SessionPage>().having((p) => p.items, 'items', isEmpty),
    );
  });

  test('a server that fails to connect is not a request error', () async {
    h = await ServerHarness.start(
      mcp: (clock) => McpClientConnector(
        transports: McpTransports(
          stdio: FakeMcpTransportFactory(
            {},
            failures: {'fake': 'spawn failed: not found'},
          ),
        ),
        clock: clock,
      ),
      narrow: const {
        HostCapability.mcp: CapabilityTransport({'stdio'}, 'тест'),
      },
    );
    await h.initialize();

    final response = await newSession('/work/demo', mcpServers: [stdioFake]);

    expect(response.error, isNull);
    expect(h.logger.eventsOf('mcp.server.failed'), hasLength(1));
  });

  test('tools of a connected server are visible from the first turn', () async {
    final fake = FakeMcpServer(tools: [const FakeMcpTool('echo')]);
    final old = FakeMcpServer(
      era: FakeMcpEra.legacy,
      tools: [const FakeMcpTool('echo')],
    );
    h = await ServerHarness.start(
      steps: [
        {
          'reply': [
            {'text': 'ok'},
          ],
        },
      ],
      mcp: (clock) => McpClientConnector(
        transports: McpTransports(
          stdio: FakeMcpTransportFactory({'fake': fake, 'old': old}),
          http: FakeMcpTransportFactory({}),
        ),
        clock: clock,
      ),
    );
    await h.initialize();
    final id =
        (await newSession(
              '/work/demo',
              mcpServers: [
                {
                  'name': 'fake',
                  'command': 'x',
                  'args': <Object?>[],
                  'env': <Object?>[],
                },
                {
                  'name': 'old',
                  'command': 'y',
                  'args': <Object?>[],
                  'env': <Object?>[],
                },
              ],
            )).resultMap['sessionId']!
            as String;
    await h.client.next();

    expect((await h.prompt(id, 'hi')).error, isNull);

    expect(
      h.toolsSeen.single,
      containsAll(['mcp__fake__echo', 'mcp__old__echo']),
    );
  });

  test('the session journal starts with model_change', () async {
    h = await ServerHarness.start();
    await h.initialize();

    final id =
        (await newSession('/work/demo')).resultMap['sessionId']! as String;

    final snapshot = await h.store.open(SessionId(id));
    expect(snapshot.header.cwd, '/work/demo');
    expect(snapshot.records.first, isA<ModelChangeRecord>());
  });

  // Рабочая папка — ссылка на каталог (как /tmp на macOS): сессия
  // создаётся (фикстура acp/session-list-cwd-filter).
  test('a cwd that links to a directory is accepted', () async {
    final tmp = Directory.systemTemp.createTempSync('cwd_link_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final real = Directory('${tmp.path}/real')..createSync();
    final link = Link('${tmp.path}/link')..createSync(real.path);
    h = await ServerHarness.start(
      localListing: (cwd) => LocalExecutionEnv(cwd: cwd),
    );
    await h.initialize();

    final response = await newSession(link.path);

    expect(response.error, isNull);
  });
}
