// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

McpStdioServerConfig _stdio(
  String name, {
  List<String> args = const [],
  McpServerOrigin origin = McpServerOrigin.session,
}) => McpStdioServerConfig(
  name: name,
  command: '/usr/bin/$name',
  args: args,
  origin: origin,
);

FakeMcpServer _server(List<String> tools) => FakeMcpServer(
  era: FakeMcpEra.modern,
  tools: [for (final t in tools) FakeMcpTool(t)],
);

List<String> _names(McpSessionTools session) => [
  for (final t in session.tools) t.name,
];

/// `McpSessionTools.replaceServers` коннектора (agent-runtime «MCP-серверы
/// сессии», `setMcpServers`; design.md change `add-agent-mcp-client`, D11):
/// совпавшие остаются, исчезнувшие закрыты, новые подключены, серверы конфига
/// не тронуты.
void main() {
  late McpHarness h;
  late FakeMcpTransportFactory factory;
  late Map<String, FakeMcpServer> fakes;
  setUp(() => h = McpHarness());

  McpClientConnector connector() => McpClientConnector(
    transports: McpTransports(stdio: factory),
    clock: h.clock,
  );

  var cancelSource = CancelTokenSource();
  McpConnectRequest request(List<McpServerConfig> servers) => McpConnectRequest(
    sessionId: const SessionId('s1'),
    cwd: '/proj',
    servers: servers,
    reservedNames: const {'read', 'write'},
    logger: h.logger,
    cancel: cancelSource.token,
  );

  setUp(() {
    cancelSource = CancelTokenSource();
    fakes = {
      'a': _server(['t']),
      'b': _server(['t']),
      'c': _server(['t']),
      'cfg': _server(['t']),
    };
    factory = FakeMcpTransportFactory(fakes);
  });

  test('a matching server is kept: no reconnect, no close', () async {
    final session = await connector().connect(
      request([_stdio('a'), _stdio('b')]),
    );

    await session.replaceServers([_stdio('a'), _stdio('b')]);

    expect(factory.opened, ['a', 'b'], reason: 'nothing was opened again');
    expect(fakes['a']!.closedTransports, 0);
    expect(fakes['b']!.closedTransports, 0);
    expect(_names(session), ['mcp__a__t', 'mcp__b__t']);
  });

  test('a vanished server is closed, a new one is connected, in the order '
      'of the list', () async {
    final session = await connector().connect(
      request([_stdio('a'), _stdio('b')]),
    );

    await session.replaceServers([_stdio('c'), _stdio('b')]);

    expect(fakes['a']!.closedTransports, 1);
    expect(fakes['b']!.closedTransports, 0);
    expect(factory.opened, ['a', 'b', 'c']);
    expect(_names(session), ['mcp__c__t', 'mcp__b__t']);
    expect(session.servers.map((s) => s.name), ['c', 'b']);
  });

  test(
    'a server with the same name and other parameters is reconnected',
    () async {
      final session = await connector().connect(request([_stdio('a')]));

      await session.replaceServers([
        _stdio('a', args: ['--new']),
      ]);

      expect(fakes['a']!.closedTransports, 1);
      expect(factory.opened, ['a', 'a']);
      expect(_names(session), ['mcp__a__t']);
    },
  );

  test('an empty list closes every server', () async {
    final session = await connector().connect(
      request([_stdio('a'), _stdio('b')]),
    );

    await session.replaceServers(const []);

    expect(fakes['a']!.closedTransports, 1);
    expect(fakes['b']!.closedTransports, 1);
    expect(session.tools, isEmpty);
    expect(session.servers, isEmpty);
  });

  test('a server of the config that is in the list is not touched', () async {
    final cfg = _stdio('cfg', origin: McpServerOrigin.config);
    final session = await connector().connect(request([cfg, _stdio('a')]));

    await session.replaceServers([cfg, _stdio('b')]);

    expect(fakes['cfg']!.closedTransports, 0);
    expect(factory.opened, ['cfg', 'a', 'b']);
    expect(_names(session), ['mcp__cfg__t', 'mcp__b__t']);
  });

  test('a new server never takes the names of a working one, even if it '
      'stands first in the list', () async {
    // `my_srv` и `my.srv` дают одно имя инструмента `mcp__my_srv__t` (E-05).
    fakes['my_srv'] = _server(['t']);
    fakes['my.srv'] = _server(['t']);
    final session = await connector().connect(request([_stdio('my_srv')]));

    await session.replaceServers([_stdio('my.srv'), _stdio('my_srv')]);

    expect(_names(session), ['mcp__my_srv__t']);
    expect(session.servers.map((s) => s.name), ['my_srv']);
    expect(fakes['my_srv']!.closedTransports, 0);
    expect(fakes['my.srv']!.closedTransports, 1);
    final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
    expect(failed['server'], 'my.srv');
    expect(failed['reason'], contains('MCP server "my_srv"'));
  });

  test('a new server that fails to start is logged; the rest are '
      'unaffected', () async {
    factory = FakeMcpTransportFactory(
      fakes,
      failures: {'b': 'spawn failed: no such file'},
    );
    final session = await connector().connect(request([_stdio('a')]));

    await session.replaceServers([_stdio('a'), _stdio('b'), _stdio('c')]);

    expect(_names(session), ['mcp__a__t', 'mcp__c__t']);
    final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
    expect(failed['server'], 'b');
    expect(failed['reason'], 'spawn failed: no such file');
  });

  test('a server that was disabled by a collision is tried again when it '
      'is still in the list', () async {
    fakes['my_srv'] = _server(['t']);
    fakes['my.srv'] = _server(['t']);
    final session = await connector().connect(
      request([_stdio('my_srv'), _stdio('my.srv')]),
    );
    expect(session.servers.map((s) => s.name), ['my_srv']);

    await session.replaceServers([_stdio('my.srv')]);

    expect(session.servers.map((s) => s.name), ['my.srv']);
    expect(_names(session), ['mcp__my_srv__t']);
    expect(factory.opened, ['my_srv', 'my.srv', 'my.srv']);
  });

  test('after close nothing is connected', () async {
    final session = await connector().connect(request([_stdio('a')]));
    await session.close();

    await session.replaceServers([_stdio('b')]);

    expect(factory.opened, ['a']);
  });

  test('a cancelled token abandons a hanging new server at once: transport '
      'closed, no wait for connectTimeout', () async {
    fakes['hang'] = FakeMcpServer(
      era: FakeMcpEra.legacy,
      silentInitialize: true,
      tools: [const FakeMcpTool('t')],
    );
    final session = await connector().connect(request([_stdio('a')]));

    final replacing = session.replaceServers([_stdio('a'), _stdio('hang')]);
    await h.clock.elapse(Duration.zero);
    cancelSource.cancel();
    await replacing;

    expect(fakes['hang']!.closedTransports, 1);
    expect(_names(session), ['mcp__a__t']);
    expect(fakes['a']!.closedTransports, 0);
  });
}
