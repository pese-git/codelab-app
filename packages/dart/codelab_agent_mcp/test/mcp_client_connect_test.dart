// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/src/mcp_client.dart';
import 'package:codelab_agent_mcp/src/protocol.dart';
import 'package:codelab_agent_mcp/testing.dart';

import 'support/throwing_transport.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

const _echo = FakeMcpTool('echo');
const _meta = 'io.modelcontextprotocol/protocolVersion';

void main() {
  late McpHarness h;
  setUp(() => h = McpHarness());

  group('modern', () {
    test(
      'no initialize, _meta on every request, subscription, two pages',
      () async {
        final server = FakeMcpServer(
          tools: [_echo, const FakeMcpTool('lookup')],
          pageSize: 1,
          listChanged: true,
        );

        final client = await h.connect(server);

        expect([for (final t in client.tools) t.name], ['echo', 'lookup']);
        expect(server.methods, [
          'server/discover',
          'subscriptions/listen',
          'tools/list',
          'tools/list',
        ]);
        for (final request in server.requests) {
          final meta = (request['params'] as Map)['_meta'] as Map;
          expect(meta[_meta], '2026-07-28', reason: '${request['method']}');
          expect(meta['io.modelcontextprotocol/clientCapabilities'], isEmpty);
          expect(
            (meta['io.modelcontextprotocol/clientInfo'] as Map)['name'],
            'codelab-agent',
          );
        }
        expect(server.subscriptions, 1);
        expect(client.era, McpEra.modern);
        expect(h.logged('mcp.server.era'), containsPair('era', 'modern'));
        expect(
          h.logged('mcp.server.era'),
          containsPair('probe', 'discover_result'),
        );
        expect(h.logged('mcp.server.connect'), containsPair('tools', 2));
        expect(h.logged('mcp.server.connect'), containsPair('server', 'fake'));
        expect(
          h.logged('mcp.server.connect'),
          containsPair('session_id', 's1'),
        );
      },
    );

    test('a server without tools is connected with zero tools', () async {
      final server = FakeMcpServer(tools: const [], advertiseTools: false);

      final client = await h.connect(server);

      expect(client.tools, isEmpty);
      expect(server.methods, ['server/discover']);
    });

    test(
      'a subscription without toolsListChanged lives without updates',
      () async {
        final server = FakeMcpServer(
          tools: [_echo],
          listChanged: true,
          acknowledgeToolsListChanged: false,
        );
        var calls = 0;

        await h.connect(server, onToolsChanged: (_) => calls++);
        server.notifyToolsListChanged();
        await h.clock.elapse(Duration.zero);

        expect(calls, 0);
      },
    );
  });

  group('legacy', () {
    test('stdio falls back to initialize on -32601', () async {
      final server = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);

      final client = await h.connect(server);

      expect(client.era, McpEra.legacy);
      expect(client.protocolVersion, '2025-11-25');
      expect(server.methods, [
        'server/discover',
        'initialize',
        'notifications/initialized',
        'tools/list',
      ]);
      final initialize = server.requests.firstWhere(
        (r) => r['method'] == 'initialize',
      );
      expect((initialize['params'] as Map)['protocolVersion'], '2025-11-25');
      expect((initialize['params'] as Map)['capabilities'], isEmpty);
      // Legacy-запросы `_meta` протокола не несут (D2).
      for (final method in ['initialize', 'tools/list']) {
        final request = server.requests.firstWhere(
          (r) => r['method'] == method,
        );
        expect(
          (request['params'] as Map?)?.containsKey('_meta') ?? false,
          isFalse,
          reason: method,
        );
      }
      expect(server.violations, isEmpty);
      expect(h.logged('mcp.server.era'), containsPair('era', 'legacy'));
      expect(
        h.logged('mcp.server.era'),
        containsPair('probe', 'fallback_error'),
      );
    });

    test(
      'a silent server is probed for min(5 s, connectTimeout / 2)',
      () async {
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          legacyProbe: FakeLegacyProbe.silent,
        );

        final connected = h.connect(server);
        await h.clock.elapse(const Duration(seconds: 4));
        expect(server.methods, ['server/discover']);
        await h.clock.elapse(const Duration(seconds: 1));
        final client = await connected;

        expect(client.era, McpEra.legacy);
        expect(server.methods, contains('initialize'));
        expect(
          h.logged('mcp.server.era'),
          containsPair('probe', 'fallback_timeout'),
        );

        // Поздний ответ на пробу игнорируется (AGENTS.md §9).
        server.answerSilentProbe();
        await h.clock.elapse(Duration.zero);
        expect(h.logger.eventsOf('mcp.message.ignored'), hasLength(1));
        expect(
          h.logger.eventsOf('mcp.message.ignored').single.fields,
          containsPair('kind', 'late_response'),
        );
        expect(client.isConnected, isTrue);
      },
    );

    test('the probe time is half of a short connectTimeout', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        legacyProbe: FakeLegacyProbe.silent,
      );

      final connected = h.connect(
        server,
        connectTimeout: const Duration(seconds: 4),
      );
      await h.clock.elapse(const Duration(seconds: 2));
      await connected;

      expect(server.methods, contains('initialize'));
    });

    for (final version in ['2025-06-18', '2025-03-26']) {
      test(
        'the version $version in the initialize answer is accepted',
        () async {
          final server = FakeMcpServer(
            era: FakeMcpEra.legacy,
            legacyVersion: version,
            tools: [_echo],
          );

          final client = await h.connect(server);

          expect(client.protocolVersion, version);
          expect(client.tools, hasLength(1));
        },
      );
    }

    test('2024-11-05 is not supported', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        legacyVersion: '2024-11-05',
      );

      await expectLater(
        h.connect(server),
        throwsA(
          isA<McpConnectException>().having(
            (e) => e.reason,
            'reason',
            'unsupported protocol version 2024-11-05',
          ),
        ),
      );

      expect(
        h.logged('mcp.server.failed'),
        containsPair('reason', 'unsupported protocol version 2024-11-05'),
      );
      expect(server.closedTransports, 1);
    });

    test(
      'initialize timeout closes the transport without cancellation',
      () async {
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          silentInitialize: true,
        );

        final failed = expectLater(
          h.connect(server),
          throwsA(isA<McpConnectException>()),
        );
        await h.clock.elapse(const Duration(seconds: 10));
        await failed;

        expect(server.cancelledRequestIds, isEmpty);
        expect(server.closedTransports, 1);
        expect(h.logger.eventsOf('mcp.server.failed'), hasLength(1));
      },
    );

    test('a ping gets an empty result, other requests get -32601', () async {
      final server = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);
      await h.connect(server);

      server.sendRequest('ping', id: 'p1');
      server.sendRequest('sampling/createMessage', id: 'p2');
      await h.clock.elapse(Duration.zero);

      expect(server.responsesFromClient, hasLength(2));
      expect(server.responsesFromClient[0]['id'], 'p1');
      expect(server.responsesFromClient[0]['result'], isEmpty);
      expect(server.responsesFromClient[1]['id'], 'p2');
      expect((server.responsesFromClient[1]['error'] as Map)['code'], -32601);
    });

    test('a task-only tool is skipped with mcp.tool.invalid', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        declareTaskCalls: true,
        tools: [
          _echo,
          const FakeMcpTool('slow', taskSupport: 'required'),
          const FakeMcpTool('maybe', taskSupport: 'optional'),
        ],
      );

      final client = await h.connect(server);

      expect([for (final t in client.tools) t.name], ['echo', 'maybe']);
      final invalid = h.logger.eventsOf('mcp.tool.invalid').single.fields;
      expect(invalid['tool'], 'slow');
      expect(invalid['reason'], 'task support required');
    });

    test('taskSupport required is fine when tasks are not declared', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [const FakeMcpTool('slow', taskSupport: 'required')],
      );

      final client = await h.connect(server);

      expect(client.tools, hasLength(1));
    });
  });

  group('no common version', () {
    test('-32022 names the supported versions and never falls back', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.modern,
        supportedVersions: const ['2027-01-01'],
        refuseWithUnsupportedVersion: true,
      );

      await expectLater(
        h.connect(server),
        throwsA(
          isA<McpConnectException>().having(
            (e) => e.reason,
            'reason',
            'no common protocol version: server supports [2027-01-01]',
          ),
        ),
      );

      expect(server.methods, ['server/discover']);
      expect(h.logged('mcp.server.era'), containsPair('probe', 'modern_error'));
      expect(h.logged('mcp.server.failed')['reason'], contains('2027-01-01'));
      expect(server.closedTransports, 1);
    });

    test(
      'a DiscoverResult without the modern version is the same failure',
      () async {
        final server = FakeMcpServer(
          era: FakeMcpEra.modern,
          supportedVersions: const ['2027-01-01'],
        );

        await expectLater(
          h.connect(server),
          throwsA(
            isA<McpConnectException>().having(
              (e) => e.reason,
              'reason',
              contains('no common protocol version'),
            ),
          ),
        );

        expect(server.methods, ['server/discover']);
      },
    );
  });

  group('tools/list', () {
    test('100 pages are the limit', () async {
      final server = FakeMcpServer(tools: [_echo], endlessPages: true);

      await expectLater(
        h.connect(server),
        throwsA(
          isA<McpConnectException>().having(
            (e) => e.reason,
            'reason',
            'tools/list pagination did not end',
          ),
        ),
      );

      expect(server.methods.where((m) => m == 'tools/list'), hasLength(100));
      expect(server.closedTransports, 1);
    });

    test('an empty string cursor is a cursor, not the end', () async {
      final server = FakeMcpServer(
        tools: [_echo, const FakeMcpTool('lookup')],
        pageSize: 1,
        emptyStringFirstCursor: true,
      );

      final client = await h.connect(server);

      expect([for (final t in client.tools) t.name], ['echo', 'lookup']);
      final lists = server.requests.where((r) => r['method'] == 'tools/list');
      expect((lists.last['params'] as Map)['cursor'], '');
    });

    test('outbound ids are integers without repeats', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo, const FakeMcpTool('b')],
        pageSize: 1,
      );

      await h.connect(server);

      final ids = [
        for (final r in server.requests)
          if (r.containsKey('id')) r['id'],
      ];
      expect(ids.every((id) => id is int), isTrue);
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('era cache of HTTP servers', () {
    test('the second connection skips the probe', () async {
      final cache = McpEraCache();
      final first = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);
      await h.connect(first, kind: 'http', cache: cache);
      expect(cache.lookup('https://mcp.example.com'), McpEra.legacy);

      final second = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);
      final h2 = McpHarness();
      await h2.connect(second, kind: 'http', cache: cache);

      expect(second.methods, [
        'initialize',
        'notifications/initialized',
        'tools/list',
      ]);
      expect(h2.logged('mcp.server.era'), containsPair('probe', 'cached'));
    });

    test('a modern cache that does not hold is probed again', () async {
      final cache = McpEraCache()
        ..store('https://mcp.example.com', McpEra.modern);
      final server = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);

      final client = await h.connect(server, kind: 'http', cache: cache);

      expect(client.era, McpEra.legacy);
      expect(server.methods.first, 'server/discover');
      expect(cache.lookup('https://mcp.example.com'), McpEra.legacy);
      expect(
        h.logged('mcp.server.era'),
        containsPair('probe', 'fallback_error'),
      );
    });

    test('a legacy cache that does not hold is probed again', () async {
      final cache = McpEraCache()
        ..store('https://mcp.example.com', McpEra.legacy);
      final server = FakeMcpServer(tools: [_echo]);

      final client = await h.connect(server, kind: 'http', cache: cache);

      expect(client.era, McpEra.modern);
      expect(
        server.methods,
        containsAllInOrder(['initialize', 'server/discover']),
      );
      expect(cache.lookup('https://mcp.example.com'), McpEra.modern);
      expect(
        h.logged('mcp.server.era'),
        containsPair('probe', 'discover_result'),
      );
    });

    test('stdio servers are not cached', () async {
      final cache = McpEraCache();
      await h.connect(FakeMcpServer(era: FakeMcpEra.legacy), cache: cache);

      expect(cache.isEmpty, isTrue);
    });
  });

  group('tools/list_changed', () {
    test(
      'a modern notification of our subscription re-reads the list',
      () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        final seen = <List<String>>[];
        await h.connect(
          server,
          onToolsChanged: (tools) => seen.add([for (final t in tools) t.name]),
        );

        server.notifyToolsListChanged(
          newTools: [_echo, const FakeMcpTool('x')],
        );
        await h.clock.elapse(Duration.zero);

        expect(seen, [
          ['echo', 'x'],
        ]);
      },
    );

    test(
      'a modern notification of a foreign subscription is ignored',
      () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        var calls = 0;
        await h.connect(server, onToolsChanged: (_) => calls++);
        final before = server.methods.length;

        server.notifyToolsListChanged(subscriptionId: 999);
        await h.clock.elapse(Duration.zero);

        expect(calls, 0);
        expect(server.methods.length, before);
      },
    );

    test(
      'a legacy notification on the common channel re-reads the list',
      () async {
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          listChanged: true,
        );
        final seen = <int>[];
        await h.connect(
          server,
          onToolsChanged: (tools) => seen.add(tools.length),
        );

        server.notifyToolsListChanged(
          newTools: [_echo, const FakeMcpTool('x')],
        );
        await h.clock.elapse(Duration.zero);

        expect(seen, [2]);
      },
    );

    test('two notifications in a row make at most two tools/list', () async {
      final server = FakeMcpServer(tools: [_echo], listChanged: true);
      final seen = <List<String>>[];
      await h.connect(
        server,
        onToolsChanged: (tools) => seen.add([for (final t in tools) t.name]),
      );
      final before = server.methods.where((m) => m == 'tools/list').length;

      server.notifyToolsListChanged(newTools: [_echo]);
      server.notifyToolsListChanged(newTools: [_echo, const FakeMcpTool('b')]);
      await h.clock.elapse(Duration.zero);

      final after = server.methods.where((m) => m == 'tools/list').length;
      expect(after - before, lessThanOrEqualTo(2));
      expect(seen.last, ['echo', 'b']);
    });
  });

  test('the connect log never carries secrets of the server config', () async {
    final server = FakeMcpServer(tools: [_echo]);
    final client = await McpClient.connect(
      server: McpStdioServerConfig(
        name: 'fake',
        command: 'fake-mcp',
        args: const ['--token', 'arg-secret'],
        env: const {'API_KEY': 'sk-123'},
      ),
      transport: server.connect(),
      clock: h.clock,
      logger: h.logger,
      sessionId: const SessionId('s1'),
    );

    expect(client.isConnected, isTrue);
    expect('${h.logger.records}', isNot(contains('sk-123')));
    expect('${h.logger.records}', isNot(contains('arg-secret')));
  });

  group('subscription (D5)', () {
    test('two acknowledgements in a row do not crash the process', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        listChanged: true,
        duplicateAck: true,
      );

      final client = await h.connect(server);

      expect(client.isConnected, isTrue);
      expect(client.tools, hasLength(1));
    });

    for (final listen in [
      FakeListen.error,
      FakeListen.close,
      FakeListen.abort,
    ]) {
      test(
        '${listen.name} before the ack means: connected without updates',
        () async {
          final server = FakeMcpServer(
            tools: [_echo],
            listChanged: true,
            listen: listen,
          );
          var calls = 0;

          final client = await h.connect(
            server,
            onToolsChanged: (_) => calls++,
          );
          server.notifyToolsListChanged();
          await h.clock.elapse(Duration.zero);

          expect(client.isConnected, isTrue);
          expect(client.tools, hasLength(1));
          expect(calls, 0);
          final ignored = h.logger
              .eventsOf('mcp.message.ignored')
              .where((r) => r.fields['kind'] == 'subscription_failed');
          expect(ignored, hasLength(1));
        },
      );
    }

    test(
      'an error before the ack is logged with the method and code',
      () async {
        final server = FakeMcpServer(
          tools: [_echo],
          listChanged: true,
          listen: FakeListen.error,
        );

        await h.connect(server);

        final fields = h.logger
            .eventsOf('mcp.message.ignored')
            .firstWhere((r) => r.fields['kind'] == 'subscription_failed')
            .fields;
        expect(fields['method'], 'subscriptions/listen');
        expect(fields['code'], -32603);
      },
    );

    test(
      'silence is awaited for min(5 s, connectTimeout / 2), then no updates',
      () async {
        final server = FakeMcpServer(
          tools: [_echo],
          listChanged: true,
          listen: FakeListen.withhold,
        );
        var calls = 0;

        final connected = h.connect(server, onToolsChanged: (_) => calls++);
        await h.clock.elapse(const Duration(seconds: 4));
        expect(server.methods, ['server/discover', 'subscriptions/listen']);
        await h.clock.elapse(const Duration(seconds: 1));
        final client = await connected;

        expect(client.isConnected, isTrue);
        expect(client.tools, hasLength(1));

        // Подтверждение после таймаута не роняет процесс и ничего не включает.
        server.sendAck();
        server.notifyToolsListChanged();
        await h.clock.elapse(Duration.zero);
        expect(calls, 0);
      },
    );

    test(
      'a graceful closure is logged and the closed request is not cancelled',
      () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        final client = await h.connect(server);

        server.closeSubscription();
        await h.clock.elapse(Duration.zero);
        await client.close();

        expect(
          h.logger
              .eventsOf('mcp.message.ignored')
              .where((r) => r.fields['kind'] == 'subscription_closed'),
          hasLength(1),
        );
        expect(server.cancelledRequestIds, isEmpty);
      },
    );
  });

  group('robustness of the incoming channel', () {
    test('a batch is rejected in the modern era, accepted in legacy', () async {
      final modern = FakeMcpServer(tools: [_echo]);
      await h.connect(modern);

      modern.pushRaw('[{"jsonrpc":"2.0","method":"notifications/x"}]');
      await h.clock.elapse(Duration.zero);

      expect(
        h.logger
            .eventsOf('mcp.message.ignored')
            .where((r) => r.fields['kind'] == 'parse_error'),
        hasLength(1),
      );

      final h2 = McpHarness();
      final legacy = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);
      await h2.connect(legacy);
      legacy.pushRaw('[{"jsonrpc":"2.0","method":"notifications/x"}]');
      await h2.clock.elapse(Duration.zero);
      expect(
        h2.logger
            .eventsOf('mcp.message.ignored')
            .where((r) => r.fields['kind'] == 'unknown_notification'),
        hasLength(1),
      );
    });

    test('a stream error makes the client disconnected', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final client = await h.connect(server);

      server.breakStream();
      await h.clock.elapse(Duration.zero);

      expect(client.isConnected, isFalse);
      expect(
        h.logger.eventsOf('mcp.server.failed').single.fields['reason'],
        'disconnected: transport error',
      );
    });

    test('after close the notifications are no longer handled', () async {
      final server = FakeMcpServer(tools: [_echo], listChanged: true);
      var calls = 0;
      final client = await h.connect(server, onToolsChanged: (_) => calls++);
      await client.close();

      server.notifyToolsListChanged();
      await h.clock.elapse(Duration.zero);

      expect(calls, 0);
    });
  });

  group('failures that are not MCP errors', () {
    test(
      'a transport that throws on initialized fails only the connection',
      () async {
        final server = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);
        final transport = ThrowingTransport(
          server.connect(),
          'notifications/initialized',
        );

        await expectLater(
          McpClient.connect(
            server: const McpStdioServerConfig(name: 'fake', command: 'x'),
            transport: transport,
            clock: h.clock,
            logger: h.logger,
            sessionId: const SessionId('s1'),
          ),
          throwsA(isA<McpConnectException>()),
        );

        expect(server.closedTransports, 1);
        expect(
          h.logger.eventsOf('mcp.server.failed').single.fields['reason'],
          'unexpected error: StateError',
        );
      },
    );

    test('a tool with fields of a wrong type is kept', () async {
      final server = FakeMcpServer(
        tools: [
          const FakeMcpTool('odd', extra: {'title': 1, 'description': 2}),
        ],
      );

      final client = await h.connect(server);

      expect(client.tools.single.name, 'odd');
      expect(client.tools.single.title, isNull);
      expect(client.tools.single.description, isNull);
    });

    test('reasons carry no strings of the server', () async {
      final server = FakeMcpServer(
        supportedVersions: const ['evil\nversion with spaces'],
        refuseWithUnsupportedVersion: true,
      );

      await expectLater(
        h.connect(server),
        throwsA(
          isA<McpConnectException>().having(
            (e) => e.reason,
            'reason',
            'no common protocol version: server supports []',
          ),
        ),
      );
    });
  });

  group('list_changed during the handshake and refresh failures', () {
    test(
      'a notification during tools/list triggers a re-read after the handshake',
      () async {
        final server = FakeMcpServer(
          tools: [_echo],
          listChanged: true,
          notifyDuringFirstList: [_echo, const FakeMcpTool('late')],
        );
        final seen = <List<String>>[];

        await h.connect(
          server,
          onToolsChanged: (tools) => seen.add([for (final t in tools) t.name]),
        );
        await h.clock.elapse(Duration.zero);

        expect(seen, [
          ['echo', 'late'],
        ]);
      },
    );

    test(
      'a failed refresh logs mcp.tools.refresh_failed and keeps the set',
      () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        final client = await h.connect(server);
        server.failListErrors = 1;

        server.notifyToolsListChanged();
        await h.clock.elapse(Duration.zero);

        expect(client.tools.map((t) => t.name), ['echo']);
        expect(h.logger.eventsOf('mcp.server.failed'), isEmpty);
        final fields = h.logger.eventsOf('mcp.tools.refresh_failed').single;
        expect(fields.level, LogLevel.warning);
        expect(fields.fields['server'], 'fake');
        expect(fields.fields['reason'], 'tools/list failed (code -32603)');
      },
    );
  });
}
