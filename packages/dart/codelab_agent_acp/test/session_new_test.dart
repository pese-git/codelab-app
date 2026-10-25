import 'package:acp_protocol/acp_protocol.dart' hide SessionId;
import 'package:codelab_agent_core/codelab_agent_core.dart';
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

  test('an MCP server is skipped with mcp.server.skipped', () async {
    h = await ServerHarness.start();
    await h.initialize();

    final response = await newSession(
      '/work/demo',
      mcpServers: [
        {
          'name': 'github',
          'type': 'http',
          'url': 'https://example.com/mcp',
          'headers': <Object?>[],
        },
      ],
    );

    expect(response.error, isNull);
    expect(h.logger.eventsOf('mcp.server.skipped'), hasLength(1));
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
}
