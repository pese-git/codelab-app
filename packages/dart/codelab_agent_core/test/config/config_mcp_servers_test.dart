import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// MCP-серверы конфигурации (agent-configuration «MCP-серверы
/// конфигурации»; design.md change `add-agent-configuration`, D10).
void main() {
  ConfigLoadResult withServers(
    List<Map<String, Object?>> servers, {
    Map<String, String> environment = const {},
    List<ConfigTree> before = const [],
  }) => load([
    ...before,
    layer(
      withValues(baseValues(), {
        'mcp': {'servers': servers},
      }),
    ),
  ], environment: environment);

  test('stdio and http map to McpServerConfig(origin: config) with '
      'timeouts and the header order of the file', () {
    final result = withServers([
      {
        'name': 'fake',
        'type': 'stdio',
        'command': 'fake-mcp',
        'args': ['--a', '--b'],
        'env': {'K': 'v'},
        'connect_timeout': '3s',
        'call_timeout': '2m',
      },
      {
        'name': 'gh',
        'type': 'http',
        'url': 'https://gh.test/mcp',
        'headers': {'B-Second': '2', 'A-First': '1'},
      },
    ]);

    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    final [stdio as McpStdioServerConfig, http as McpHttpServerConfig] =
        result.config!.mcpServers;
    expect(stdio.origin, McpServerOrigin.config);
    expect(stdio.command, 'fake-mcp');
    expect(stdio.args, ['--a', '--b']);
    expect(stdio.env, {'K': 'v'});
    expect(stdio.connectTimeout, const Duration(seconds: 3));
    expect(stdio.callTimeout, const Duration(minutes: 2));
    expect(http.origin, McpServerOrigin.config);
    expect(http.url, Uri.parse('https://gh.test/mcp'));
    expect(http.headers, [('B-Second', '2'), ('A-First', '1')]);
    expect(http.connectTimeout, defaultMcpConnectTimeout);
    expect(http.callTimeout, isNull, reason: 'no key: connector default');
  });

  test('type: sse is a problem with the key path (E-03)', () {
    final result = withServers([
      {'name': 'old', 'type': 'sse', 'url': 'https://x.test/sse'},
    ]);

    final issue = issuesAt(result, 'mcp.servers[old].type').single;
    expect(issue.kind, ConfigIssueKind.value);
    expect(issue.message, 'only stdio and http are supported');
    expect(result.config, isNull);
  });

  test('type and the transport fields are required', () {
    final result = withServers([
      {'name': 'a'},
      {'name': 'b', 'type': 'stdio'},
      {'name': 'c', 'type': 'http'},
    ]);

    expect(issuesAt(result, 'mcp.servers[a].type'), hasLength(1));
    expect(issuesAt(result, 'mcp.servers[b].command'), hasLength(1));
    expect(issuesAt(result, 'mcp.servers[c].url'), hasLength(1));
  });

  test('a url without an http scheme is a problem', () {
    final result = withServers([
      {'name': 'a', 'type': 'http', 'url': 'gh.test/mcp'},
      {'name': 'b', 'type': 'http', 'url': 'ftp://gh.test/mcp'},
    ]);

    expect(issuesAt(result, 'mcp.servers[a].url'), hasLength(1));
    expect(issuesAt(result, 'mcp.servers[b].url'), hasLength(1));
  });

  test('call_timeout outside 1s..24h is a problem', () {
    final result = withServers([
      {'name': 'a', 'type': 'stdio', 'command': 'c', 'call_timeout': '0s'},
      {'name': 'b', 'type': 'stdio', 'command': 'c', 'call_timeout': '25h'},
      {'name': 'c', 'type': 'stdio', 'command': 'c', 'call_timeout': '24h'},
      {'name': 'd', 'type': 'stdio', 'command': 'c', 'call_timeout': '1s'},
    ]);

    expect(issuesAt(result, 'mcp.servers[a].call_timeout'), hasLength(1));
    expect(issuesAt(result, 'mcp.servers[b].call_timeout'), hasLength(1));
    expect(issuesAt(result, 'mcp.servers[c].call_timeout'), isEmpty);
    expect(issuesAt(result, 'mcp.servers[d].call_timeout'), isEmpty);
  });

  test('enabled: false removes the server and logs mcp.server.skipped', () {
    final result = withServers([
      {'name': 'off', 'type': 'stdio', 'command': 'c', 'enabled': false},
      {'name': 'on', 'type': 'stdio', 'command': 'c'},
    ]);

    expect([for (final s in result.config!.mcpServers) s.name], ['on']);
    final skipped = warningsOf(result, 'mcp.server.skipped').single;
    expect(skipped.fields, {'server': 'off', 'reason': 'disabled in config'});
    expect(skipped.level, LogLevel.info);
  });

  test('a duplicate name in one file is a problem', () {
    final result = withServers([
      {'name': 'a', 'type': 'stdio', 'command': 'c'},
      {'name': 'a', 'type': 'stdio', 'command': 'd'},
    ]);

    expect(issuesAt(result, 'mcp.servers[a]'), hasLength(1));
  });

  test(
    'the same name in two layers: the later one replaces, '
    'enabled: false switches off (scenario "Серверы сливаются по имени")',
    () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/proj'],
            'mcp': {
              'servers': [
                {'name': 'github', 'type': 'http', 'url': 'https://a.test/mcp'},
                {'name': 'files', 'type': 'stdio', 'command': 'files-mcp'},
              ],
            },
          }),
        ),
        layer({
          'mcp': {
            'servers': [
              {'name': 'github', 'type': 'http', 'url': 'https://b.test/mcp'},
              {'name': 'files', 'enabled': false},
            ],
          },
        }, kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final servers = result.config!.mcpServers;
      expect(servers, hasLength(1));
      expect((servers.single as McpHttpServerConfig).url.host, 'b.test');
    },
  );

  test('toString does not reveal env or headers', () {
    final result = withServers([
      {
        'name': 'fake',
        'type': 'stdio',
        'command': 'c',
        'env': {'K': 'sk-test-secret'},
      },
      {
        'name': 'gh',
        'type': 'http',
        'url': 'https://gh.test/mcp',
        'headers': {'Authorization': 'sk-test-secret'},
      },
    ]);

    for (final server in result.config!.mcpServers) {
      expect(server.toString(), isNot(contains('sk-test-secret')));
    }
  });

  test('callTimeout is not part of the connection identity', () {
    const a = McpStdioServerConfig(name: 'x', command: 'c');
    const b = McpStdioServerConfig(
      name: 'x',
      command: 'c',
      callTimeout: Duration(seconds: 5),
    );

    expect(a.sameConnection(b), isTrue);
  });
}
