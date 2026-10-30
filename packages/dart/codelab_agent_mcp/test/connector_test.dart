// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/src/protocol.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';
import 'support/throwing_transport.dart';

McpStdioServerConfig _stdio(String name) =>
    McpStdioServerConfig(name: name, command: '/usr/bin/$name');

McpHttpServerConfig _http(String name) => McpHttpServerConfig(
  name: name,
  url: Uri.parse('https://$name.example.com/mcp'),
);

FakeMcpServer _server(List<String> tools, {bool slow = false}) => FakeMcpServer(
  era: slow ? FakeMcpEra.legacy : FakeMcpEra.modern,
  // «Медленный» сервер отвечает на пробу только по таймауту (5 с на
  // FakeClock): подключается позже остальных.
  legacyProbe: FakeLegacyProbe.silent,
  tools: [for (final t in tools) FakeMcpTool(t)],
);

List<String> _names(McpSessionTools session) => [
  for (final t in session.tools) t.name,
];

/// `McpClientConnector` (design.md change `add-agent-mcp-client`, D6):
/// порядок регистрации, коллизии имён, изоляция сбоев, `list_changed`.
void main() {
  late McpHarness h;
  setUp(() => h = McpHarness());

  McpClientConnector connector(Map<String, FakeMcpServer> servers) =>
      McpClientConnector(
        transports: McpTransports(
          stdio: FakeMcpTransportFactory(servers),
          http: FakeMcpTransportFactory(servers),
        ),
        clock: h.clock,
      );

  McpConnectRequest request(
    List<McpServerConfig> servers, {
    Set<String> reserved = const {'read', 'write'},
  }) => McpConnectRequest(
    sessionId: const SessionId('s1'),
    cwd: '/proj',
    servers: servers,
    reservedNames: reserved,
    logger: h.logger,
    cancel: CancelToken.none,
  );

  test('transports are the union of the factories', () {
    final c = McpClientConnector(
      transports: McpTransports(stdio: FakeMcpTransportFactory({})),
      clock: h.clock,
    );

    expect(c.transports, {'stdio'});
    expect(connector({}).transports, {'stdio', 'http'});
  });

  test(
    'the transport gets a logger that carries the session_id (D13)',
    () async {
      final factory = FakeMcpTransportFactory({
        'fake': _server(['t']),
      });
      final c = McpClientConnector(
        transports: McpTransports(stdio: factory),
        clock: h.clock,
      );

      await c.connect(request([_stdio('fake')]));
      factory.loggers.single.log(LogLevel.info, 'mcp.server.closed');

      expect(
        h.logger.eventsOf('mcp.server.closed').single.fields['session_id'],
        's1',
      );
    },
  );

  group('registration order', () {
    test('follows the list, not the order of connections', () async {
      final slow = _server(['slow_tool'], slow: true);
      final fast = _server(['fast_tool']);
      final c = connector({'slow': slow, 'fast': fast});

      final connecting = c.connect(request([_stdio('slow'), _stdio('fast')]));
      await h.clock.elapse(const Duration(seconds: 5));
      final session = await connecting;

      expect(_names(session), ['mcp__slow__slow_tool', 'mcp__fast__fast_tool']);
      expect(h.logger.eventsOf('mcp.server.connect'), hasLength(2));
      expect(
        h.logger.eventsOf('mcp.server.connect').first.fields['server'],
        'fast',
        reason: 'the fast server did connect first',
      );
    });

    test('inside a server the order of tools/list is kept', () async {
      final c = connector({
        's': _server(['b', 'a', 'c']),
      });

      final session = await c.connect(request([_stdio('s')]));

      expect(_names(session), ['mcp__s__b', 'mcp__s__a', 'mcp__s__c']);
    });

    test('summaries tell the tool count of every connected server', () async {
      final c = connector({
        'two': _server(['a', 'b']),
        'none': _server([]),
      });

      final session = await c.connect(request([_stdio('two'), _stdio('none')]));

      expect(
        [for (final s in session.servers) (s.name, s.toolCount)],
        [('two', 2), ('none', 0)],
      );
    });
  });

  group('name collisions disable the later server (E-05, HOST-5)', () {
    test(
      'two servers whose names collapse, the later connects first',
      () async {
        final first = _server(['t'], slow: true);
        final later = _server(['t']);
        final c = connector({'my.srv': first, 'my_srv': later});

        final connecting = c.connect(
          request([_stdio('my.srv'), _stdio('my_srv')]),
        );
        await h.clock.elapse(const Duration(seconds: 5));
        final session = await connecting;

        // Сервер, стоящий в списке раньше, выигрывает при любом порядке
        // подключения.
        expect(_names(session), ['mcp__my_srv__t']);
        final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
        expect(failed['server'], 'my_srv');
        expect(failed['reason'], contains('mcp__my_srv__t'));
        expect(failed['reason'], contains('MCP server "my.srv"'));
        expect(later.closedTransports, 1);
        expect(first.closedTransports, 0);
        expect(session.servers.map((s) => s.name), ['my.srv']);
      },
    );

    test('a collision inside one server disables the whole server', () async {
      final x = _server(['get issue', 'get_issue']);
      final c = connector({
        'x': x,
        'y': _server(['other']),
      });

      final session = await c.connect(request([_stdio('x'), _stdio('y')]));

      expect(_names(session), ['mcp__y__other']);
      final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
      expect(failed['server'], 'x');
      expect(failed['reason'], contains('mcp__x__get_issue'));
      expect(x.closedTransports, 1);
    });

    test('a collision with a built-in tool disables the server', () async {
      final fake = _server(['echo']);
      final c = connector({'fake': fake});

      final session = await c.connect(
        request([_stdio('fake')], reserved: {'mcp__fake__echo'}),
      );

      expect(session.tools, isEmpty);
      expect(
        h.logger.eventsOf('mcp.server.failed').single.fields['reason'],
        'tool name mcp__fake__echo collides with built-in tool mcp__fake__echo',
      );
      expect(fake.closedTransports, 1);
    });
  });

  group('failures stay with their server', () {
    test('a spawn failure is logged and the others are connected', () async {
      final factory = FakeMcpTransportFactory(
        {
          'ok': _server(['t']),
        },
        failures: {'bad': 'spawn failed: no such file'},
      );
      final c = McpClientConnector(
        transports: McpTransports(stdio: factory),
        clock: h.clock,
      );

      final session = await c.connect(request([_stdio('bad'), _stdio('ok')]));

      expect(_names(session), ['mcp__ok__t']);
      final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
      expect(failed['server'], 'bad');
      expect(failed['transport'], 'stdio');
      expect(failed['reason'], 'spawn failed: no such file');
    });

    test('a server that does not connect in time has no tools', () async {
      final hang = FakeMcpServer(
        era: FakeMcpEra.legacy,
        silentInitialize: true,
        tools: [const FakeMcpTool('t')],
      );
      final c = connector({
        'hang': hang,
        'ok': _server(['t']),
      });

      final connecting = c.connect(request([_stdio('hang'), _stdio('ok')]));
      await h.clock.elapse(const Duration(seconds: 10));
      final session = await connecting;

      expect(_names(session), ['mcp__ok__t']);
      expect(hang.closedTransports, 1);
    });

    test(
      'a server missing from the factory is a failure, not an exception',
      () async {
        final c = McpClientConnector(
          transports: McpTransports(stdio: FakeMcpTransportFactory({})),
          clock: h.clock,
        );

        final session = await c.connect(request([_http('web')]));

        expect(session.tools, isEmpty);
        expect(
          h.logger.eventsOf('mcp.server.failed').single.fields['reason'],
          'transport http is not available',
        );
      },
    );
  });

  test('close closes every client once', () async {
    final a = _server(['t']);
    final b = _server(['t']);
    final c = connector({'a': a, 'b': b});
    final session = await c.connect(request([_stdio('a'), _http('b')]));

    await session.close();
    await session.close();

    expect([a.closedTransports, b.closedTransports], [1, 1]);
  });

  test('the era of HTTP servers is cached across sessions', () async {
    final first = FakeMcpServer(
      era: FakeMcpEra.legacy,
      tools: [const FakeMcpTool('t')],
    );
    final second = FakeMcpServer(
      era: FakeMcpEra.legacy,
      tools: [const FakeMcpTool('t')],
    );
    final c = connector({'web': first});
    await c.connect(request([_http('web')]));
    final c2 = McpClientConnector(
      transports: McpTransports(http: FakeMcpTransportFactory({'web': second})),
      clock: h.clock,
      eraCache: c.eraCache,
    );

    await c2.connect(request([_http('web')]));

    expect(second.methods.first, 'initialize');
    expect(c.eraCache.lookup('https://web.example.com'), McpEra.legacy);
  });

  group('tools/list_changed', () {
    test('takeUpdate returns the new set once and logs the change', () async {
      final fake = FakeMcpServer(
        tools: [const FakeMcpTool('a'), const FakeMcpTool('b')],
        listChanged: true,
      );
      final c = connector({'fake': fake});
      final session = await c.connect(request([_stdio('fake')]));
      expect(session.takeUpdate(), isNull);

      fake.notifyToolsListChanged(
        newTools: [const FakeMcpTool('b'), const FakeMcpTool('lookup')],
      );
      await h.clock.elapse(Duration.zero);
      final update = session.takeUpdate();

      expect(
        [for (final t in update!.tools) t.name],
        ['mcp__fake__b', 'mcp__fake__lookup'],
      );
      expect(update.servers.single.toolCount, 2);
      expect(session.takeUpdate(), isNull);
      final changed = h.logger.eventsOf('mcp.tools.changed').single.fields;
      expect(changed['server'], 'fake');
      expect(changed['added'], ['mcp__fake__lookup']);
      expect(changed['removed'], ['mcp__fake__a']);
    });

    test('a new set with a collision disables the server', () async {
      final fake = FakeMcpServer(
        tools: [const FakeMcpTool('a')],
        listChanged: true,
      );
      final other = _server(['t']);
      final c = connector({'fake': fake, 'other': other});
      final session = await c.connect(
        request([_stdio('fake'), _stdio('other')]),
      );

      fake.notifyToolsListChanged(
        newTools: [const FakeMcpTool('x y'), const FakeMcpTool('x_y')],
      );
      await h.clock.elapse(Duration.zero);
      final update = session.takeUpdate();
      await h.clock.elapse(Duration.zero);

      expect([for (final t in update!.tools) t.name], ['mcp__other__t']);
      expect(
        h.logger.eventsOf('mcp.server.failed').single.fields['reason'],
        contains('mcp__fake__x_y'),
      );
      expect(fake.closedTransports, 1);
    });
  });

  group('non-MCP failures stay with their server', () {
    test(
      'a transport that throws on initialized does not spoil the others',
      () async {
        final ok = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [const FakeMcpTool('t')],
        );
        final bad = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [const FakeMcpTool('t')],
        );
        final inner = FakeMcpTransportFactory({'ok': ok, 'bad': bad});
        final c = McpClientConnector(
          transports: McpTransports(
            stdio: ThrowingFactory(inner, {'bad'}, 'notifications/initialized'),
          ),
          clock: h.clock,
        );

        final session = await c.connect(request([_stdio('ok'), _stdio('bad')]));

        expect(_names(session), ['mcp__ok__t']);
        expect(bad.closedTransports, 1);
        expect(ok.closedTransports, 0);
        final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
        expect(failed['server'], 'bad');
        expect(failed['transport'], 'stdio');
      },
    );

    test(
      'a factory that throws a foreign exception closes the transport',
      () async {
        final bad = FakeMcpServer(tools: [const FakeMcpTool('t')]);
        final inner = FakeMcpTransportFactory({
          'ok': _server(['t']),
          'bad': bad,
        });
        final factory = ThrowingFactory(inner, {'bad'}, 'x')..failOpen = true;
        final c = McpClientConnector(
          transports: McpTransports(stdio: factory),
          clock: h.clock,
        );

        final session = await c.connect(request([_stdio('bad'), _stdio('ok')]));

        expect(_names(session), ['mcp__ok__t']);
        expect(
          h.logger.eventsOf('mcp.server.failed').single.fields['reason'],
          'unexpected error: StateError',
        );
      },
    );
  });

  test('an update that collides disables the server that sent it', () async {
    final updater = FakeMcpServer(
      tools: [const FakeMcpTool('a')],
      listChanged: true,
    );
    final later = _server(['t']);
    final c = connector({'my.srv': updater, 'my_srv': later});
    final session = await c.connect(
      request([_stdio('my.srv'), _stdio('my_srv')]),
    );

    // Сервер, стоящий в списке раньше, присылает имя, уже занятое более
    // поздним: отключается тот, чьё обновление вызвало коллизию.
    updater.notifyToolsListChanged(newTools: [const FakeMcpTool('t')]);
    await h.clock.elapse(Duration.zero);
    final update = session.takeUpdate();
    await h.clock.elapse(Duration.zero);

    expect([for (final t in update!.tools) t.name], ['mcp__my_srv__t']);
    expect(updater.closedTransports, 1);
    expect(later.closedTransports, 0);
    final failed = h.logger.eventsOf('mcp.server.failed').single.fields;
    expect(failed['server'], 'my.srv');
  });

  test('a server that fails to close is logged, not thrown', () async {
    final updater = FakeMcpServer(
      tools: [const FakeMcpTool('a b')],
      listChanged: true,
    );
    final c = connector({'x': updater});
    final session = await c.connect(request([_stdio('x')]));

    updater.notifyToolsListChanged(
      newTools: [const FakeMcpTool('a b'), const FakeMcpTool('a_b')],
    );
    await h.clock.elapse(Duration.zero);

    expect(session.takeUpdate()!.tools, isEmpty);
    await h.clock.elapse(Duration.zero);
  });

  // Таймаут вызова сервера из `mcp.servers[*].call_timeout` (design.md change
  // `add-agent-configuration`, D10): сервер с собственным сроком сильнее
  // общего `McpClientOptions.callTimeout`.
  group('call timeout per server', () {
    ToolContext toolContext() => ToolContext(
      env: MemoryExecutionEnv(cwd: '/'),
      cancel: CancelToken.none,
      onUpdate: (_) {},
      toolCallId: 'tc-1',
      services: ToolServices(clock: h.clock, logger: h.logger),
      supportsImages: false,
    );

    test('a server with callTimeout gets the cancel signal and its own '
        'seconds; a server without waits for the connector option', () async {
      final gateA = Completer<Map<String, Object?>>();
      final gateB = Completer<Map<String, Object?>>();
      final a = FakeMcpServer(
        tools: [const FakeMcpTool('echo')],
        responses: {'echo': FakeToolResponse.gated(gateA)},
      );
      final b = FakeMcpServer(
        tools: [const FakeMcpTool('echo')],
        responses: {'echo': FakeToolResponse.gated(gateB)},
      );
      final c = McpClientConnector(
        transports: McpTransports(
          stdio: FakeMcpTransportFactory({'a': a, 'b': b}),
        ),
        clock: h.clock,
        options: const McpClientOptions(callTimeout: Duration(minutes: 10)),
      );
      final session = await c.connect(
        request([
          McpStdioServerConfig(
            name: 'a',
            command: '/usr/bin/a',
            callTimeout: const Duration(seconds: 2),
          ),
          _stdio('b'),
        ]),
      );
      final toolA = session.tools.firstWhere((t) => t.name == 'mcp__a__echo');
      final toolB = session.tools.firstWhere((t) => t.name == 'mcp__b__echo');

      final callA = toolA.execute(const {}, toolContext());
      final callB = toolB.execute(const {}, toolContext());
      await h.clock.elapse(const Duration(seconds: 2));
      final resultA = await callA;

      expect(
        resultA.content.whereType<TextContent>().single.text,
        contains('MCP server a did not answer tools/call within 2 s.'),
      );
      expect(a.cancelledRequestIds, hasLength(1));
      expect(b.cancelledRequestIds, isEmpty);

      await h.clock.elapse(const Duration(seconds: 597));
      expect(b.cancelledRequestIds, isEmpty, reason: '599 s < 600 s');
      await h.clock.elapse(const Duration(seconds: 1));
      final resultB = await callB;

      expect(
        resultB.content.whereType<TextContent>().single.text,
        contains('within 600 s.'),
      );
      expect(b.cancelledRequestIds, hasLength(1));
    });
  });
}
