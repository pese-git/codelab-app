// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/core_stack.dart';

const _envSecret = 'sk-123';
const _headerSecret = 'Bearer t-456';
const _argSecret = 'arg-secret-789';

/// Ни одна запись лога и журнала не содержит секретов серверов (agent-mcp-client
/// «Наблюдаемость MCP без секретов»; design.md change `add-agent-mcp-client`,
/// D6, D13).
void main() {
  String everything(CoreStack stack, AgentSession session) {
    final records = [
      for (final r in stack.logger.records)
        jsonEncode({
          'event': r.event,
          'level': r.level.name,
          'fields': r.fields,
          'error': r.error,
          'stack': r.stack,
        }),
    ].join('\n');
    return '$records\n${stack.store.textOf(session.id)}';
  }

  void expectNoSecrets(String text) {
    for (final secret in [_envSecret, _headerSecret, _argSecret]) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  }

  McpStdioServerConfig stdio(String name) => McpStdioServerConfig(
    name: name,
    command: '/opt/$name',
    args: const ['--token', _argSecret],
    env: const {'API_KEY': _envSecret},
  );

  McpHttpServerConfig http(String name) => McpHttpServerConfig(
    name: name,
    url: Uri.parse('https://$name.example.com/mcp'),
    headers: const [('Authorization', _headerSecret)],
  );

  test('failed servers leave no secrets in the log and the journal', () async {
    final failing = {
      // Запуск не удался.
      'spawn': FakeMcpServer(),
      // Нет общей версии.
      'old': FakeMcpServer(
        supportedVersions: const ['2027-01-01'],
        refuseWithUnsupportedVersion: true,
      ),
      // Legacy-версия вне набора.
      'ancient': FakeMcpServer(
        era: FakeMcpEra.legacy,
        legacyVersion: '2024-11-05',
      ),
      // Коллизия имён.
      'dup': FakeMcpServer(
        tools: const [FakeMcpTool('a b'), FakeMcpTool('a_b')],
      ),
    };
    final factory = FakeMcpTransportFactory(
      failing,
      failures: const {'spawn': 'spawn failed: no such file'},
    );
    final stack = CoreStack.build(
      server: FakeMcpServer(),
      steps: [
        {
          'reply': [
            {'text': 'done'},
          ],
        },
      ],
      gate: (_) => null,
      transports: McpTransports(stdio: factory, http: factory),
      servers: [stdio('spawn'), http('old'), stdio('ancient'), http('dup')],
    );
    final session = await stack.session();
    await session.prompt([const TextContent('hi')]);
    await session.close();

    final failed = stack.logger.eventsOf('mcp.server.failed');
    expect(failed.map((r) => r.fields['server']).toSet(), {
      'spawn',
      'old',
      'ancient',
      'dup',
    });
    expectNoSecrets(everything(stack, session));
  });

  test('a server that crashed after connecting leaks nothing either', () async {
    final server = FakeMcpServer(tools: const [FakeMcpTool('echo')]);
    final stack = CoreStack.build(
      server: server,
      steps: [
        {
          'reply': [
            {'text': 'done'},
          ],
        },
      ],
      gate: (_) => null,
      servers: [stdio('fake')],
    );
    final session = await stack.session();

    server.crash(reason: 'process exited with code 1');
    await session.prompt([const TextContent('hi')]);
    await session.close();

    expect(stack.logger.eventsOf('mcp.server.failed'), isNotEmpty);
    expectNoSecrets(everything(stack, session));
  });

  test('a skipped server logs no description either', () async {
    final stack = CoreStack.build(
      server: FakeMcpServer(),
      steps: [
        {
          'reply': [
            {'text': 'done'},
          ],
        },
      ],
      gate: (_) => null,
      servers: [stdio('a'), stdio('a'), http('web')],
    );
    final session = await stack.session();
    await session.prompt([const TextContent('hi')]);
    await session.close();

    expect(stack.logger.eventsOf('mcp.server.skipped'), isNotEmpty);
    expectNoSecrets(everything(stack, session));
  });

  test('events carry exactly the fields of D13', () async {
    const common = {'session_id', 'server'};
    const allowed = <String, Set<String>>{
      'mcp.server.skipped': {'transport', 'reason'},
      'mcp.server.era': {'transport', 'era', 'protocol_version', 'probe'},
      'mcp.server.connect': {
        'transport',
        'era',
        'protocol_version',
        'server_info',
        'tools',
        'duration_ms',
      },
      'mcp.server.failed': {'transport', 'reason'},
      'mcp.tools.changed': {'added', 'removed'},
      'mcp.tools.refresh_failed': {'reason'},
      'mcp.tool.invalid': {'tool', 'reason'},
      'mcp.tool.description_truncated': {'tool', 'length'},
      'mcp.call.cancelled': {'tool_call_id', 'request_id'},
      'mcp.call.timeout': {'tool_call_id', 'request_id'},
      'mcp.message.ignored': {'kind'},
    };
    final gate = Completer<Map<String, Object?>>();
    final modern = FakeMcpServer(
      tools: [
        FakeMcpTool('long', description: 'x' * 3000),
        const FakeMcpTool('slow'),
        const FakeMcpTool('bad', inputSchema: 'oops'),
      ],
      responses: {'slow': FakeToolResponse.gated(gate)},
      listChanged: true,
    );
    final legacy = FakeMcpServer(
      era: FakeMcpEra.legacy,
      declareTaskCalls: true,
      tools: const [FakeMcpTool('t', taskSupport: 'required')],
    );
    final factory = FakeMcpTransportFactory({'m': modern, 'l': legacy});
    final stack = CoreStack.build(
      server: modern,
      steps: [
        {
          'reply': [
            {'text': 'done'},
          ],
        },
      ],
      gate: (_) => null,
      transports: McpTransports(stdio: factory, http: factory),
      servers: [stdio('m'), stdio('l'), stdio('absent')],
    );
    final session = await stack.session();

    modern.notifyToolsListChanged(newTools: const [FakeMcpTool('fresh')]);
    await session.prompt([const TextContent('hi')]);
    await session.close();

    final mcp = stack.logger.records.where((r) => r.event.startsWith('mcp.'));
    expect(mcp, isNotEmpty);
    for (final record in mcp) {
      final fields = allowed[record.event];
      expect(fields, isNotNull, reason: 'unexpected event ${record.event}');
      expect(
        record.fields.keys.toSet().difference({...common, ...fields!}),
        isEmpty,
        reason: record.event,
      );
      expect(record.fields['session_id'], isNotNull, reason: record.event);
    }
    expect(
      mcp.map((r) => r.event).toSet(),
      containsAll([
        'mcp.server.era',
        'mcp.server.connect',
        'mcp.tool.invalid',
        'mcp.tool.description_truncated',
        'mcp.tools.changed',
      ]),
    );
    for (final record in stack.logger.eventsOf('mcp.server.failed')) {
      expect(
        (record.fields['reason'] as String).length,
        lessThanOrEqualTo(200),
      );
    }
  });
}
