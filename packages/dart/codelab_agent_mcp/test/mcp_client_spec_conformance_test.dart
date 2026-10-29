import 'dart:convert';

// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'package:codelab_agent_mcp/src/mcp_client.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

const _echo = FakeMcpTool('echo');

Object _lastId(FakeMcpServer server, String method) =>
    server.requests.lastWhere((r) => r['method'] == method)['id']!;

// Итерация 1б change `add-agent-mcp-client`: отступления клиента от
// нормативного текста MCP (`2026-07-28` и legacy `2025-11-25`), найденные
// аудитом. Каждый тест назван по пункту спецификации.
void main() {
  late McpHarness h;
  setUp(() => h = McpHarness());

  group('requests from the server', () {
    test(
      'modern: no response is written (stdio.md, streamable-http.md)',
      () async {
        final server = FakeMcpServer(tools: [_echo]);
        await h.connect(server);

        server.sendRequest('ping', id: 'p1');
        server.sendRequest('sampling/createMessage', id: 'p2');
        await h.clock.elapse(Duration.zero);

        expect(server.responsesFromClient, isEmpty);
        final ignored = h.logger
            .eventsOf('mcp.message.ignored')
            .where((r) => r.fields['kind'] == 'server_request')
            .map((r) => r.fields['method'])
            .toList();
        expect(ignored, ['ping', 'sampling/createMessage']);
      },
    );

    test(
      'legacy: a ping inside the handshake window gets an empty result',
      () async {
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          pingBeforeInitializeResult: true,
        );

        await h.connect(server);

        expect(server.responsesFromClient, hasLength(1));
        expect(server.responsesFromClient.single['id'], 'handshake-ping');
        expect(server.responsesFromClient.single['result'], isEmpty);
        expect(server.responsesFromClient.single.containsKey('error'), isFalse);
      },
    );
  });

  group('requests from the server: edge cases', () {
    test('a request during the discover probe stays unanswered', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        legacyProbe: FakeLegacyProbe.silent,
      );
      final connected = h.connect(server);

      server.sendRequest('ping', id: 'during-probe');
      await h.clock.elapse(Duration.zero);
      await h.clock.elapse(const Duration(seconds: 5));
      await connected;

      expect(
        server.responsesFromClient.where((r) => r['id'] == 'during-probe'),
        isEmpty,
      );
      expect(
        h.logger
            .eventsOf('mcp.message.ignored')
            .where((r) => r.fields['kind'] == 'server_request'),
        hasLength(1),
      );
    });

    test('a method longer than 64 runes is truncated in the log', () async {
      final server = FakeMcpServer(tools: [_echo]);
      await h.connect(server);

      server.sendRequest('${'я' * 100}/method', id: 'long');
      await h.clock.elapse(Duration.zero);

      final method =
          h.logger
                  .eventsOf('mcp.message.ignored')
                  .firstWhere((r) => r.fields['kind'] == 'server_request')
                  .fields['method']!
              as String;
      expect(method.runes.length, 64);
      expect(method, 'я' * 64);
    });
  });

  group('foreign and early notifications/cancelled', () {
    test(
      'a foreign requestId is unknown_notification, subscription lives',
      () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        var calls = 0;
        await h.connect(server, onToolsChanged: (_) => calls++);

        server.pushRaw(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'notifications/cancelled',
            'params': {'requestId': 987654},
          }),
        );
        await h.clock.elapse(Duration.zero);
        server.notifyToolsListChanged();
        await h.clock.elapse(Duration.zero);

        expect(
          h.logger
              .eventsOf('mcp.message.ignored')
              .where((r) => r.fields['kind'] == 'unknown_notification'),
          hasLength(1),
        );
        expect(calls, 1);
      },
    );

    test('cancelled before the ack: connected without updates', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        listChanged: true,
        listen: FakeListen.withhold,
      );
      var calls = 0;
      final connected = h.connect(server, onToolsChanged: (_) => calls++);

      // Пока `subscriptions/listen` не дошёл до сервера, снимать нечего.
      await h.clock.elapse(Duration.zero);
      expect(server.subscriptions, 1);
      server.cancelSubscription();
      await h.clock.elapse(Duration.zero);
      final client = await connected;
      server.notifyToolsListChanged();
      await h.clock.elapse(Duration.zero);

      expect(client.isConnected, isTrue);
      expect(client.tools, hasLength(1));
      expect(calls, 0);
      expect(
        h.logger
            .eventsOf('mcp.message.ignored')
            .where((r) => r.fields['kind'] == 'subscription_closed'),
        hasLength(1),
      );
      expect(server.cancelledRequestIds, isEmpty);
    });
  });

  group('the server cancels the subscription (cancellation.md)', () {
    test('ends the subscription, logs it and lives without updates', () async {
      final server = FakeMcpServer(tools: [_echo], listChanged: true);
      var calls = 0;
      final client = await h.connect(server, onToolsChanged: (_) => calls++);

      server.cancelSubscription();
      await h.clock.elapse(Duration.zero);
      server.notifyToolsListChanged();
      await h.clock.elapse(Duration.zero);

      expect(client.isConnected, isTrue);
      expect(calls, 0);
      expect(
        h.logger
            .eventsOf('mcp.message.ignored')
            .where((r) => r.fields['kind'] == 'subscription_closed'),
        hasLength(1),
      );
    });

    test('close() does not cancel the already closed subscription', () async {
      final server = FakeMcpServer(tools: [_echo], listChanged: true);
      final client = await h.connect(server);

      server.cancelSubscription();
      await h.clock.elapse(Duration.zero);
      await client.close();

      expect(server.cancelledRequestIds, isEmpty);
    });
  });

  group('probe rejected with a modern code', () {
    for (final code in [-32020, -32021]) {
      test('$code is not reported as a version mismatch', () async {
        final server = FakeMcpServer(probeErrorCode: code);

        await expectLater(
          h.connect(server),
          throwsA(
            isA<McpConnectException>().having(
              (e) => e.reason,
              'reason',
              'server rejected the probe (code $code)',
            ),
          ),
        );
      });
    }
  });

  group('timeouts send the cancellation signal (cancellation.md)', () {
    test('ack timeout on stdio: notifications/cancelled, once', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        listChanged: true,
        listen: FakeListen.withhold,
      );
      final connected = h.connect(server);
      await h.clock.elapse(const Duration(seconds: 5));
      final client = await connected;

      final listenId = _lastId(server, 'subscriptions/listen');
      expect(server.cancelledRequestIds, [listenId]);
      await client.close();
      expect(server.cancelledRequestIds, [listenId]);
    });

    test('ack timeout on http: the response stream is abandoned', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        listChanged: true,
        listen: FakeListen.withhold,
      );
      final connected = h.connect(server, kind: 'http');
      await h.clock.elapse(const Duration(seconds: 5));
      await connected;

      expect(server.abandoned, [_lastId(server, 'subscriptions/listen')]);
      expect(server.cancelledRequestIds, isEmpty);
    });

    test('tools/list refresh timeout on stdio', () async {
      final server = FakeMcpServer(tools: [_echo], listChanged: true);
      final client = await h.connect(server);
      server.silentLists = 1;

      server.notifyToolsListChanged();
      await h.clock.elapse(const Duration(seconds: 10));

      expect(server.cancelledRequestIds, [_lastId(server, 'tools/list')]);
      expect(client.tools, hasLength(1));
      expect(
        h.logger.eventsOf('mcp.tools.refresh_failed').single.fields['reason'],
        'no answer to tools/list',
      );
    });

    test('tools/list refresh timeout on http', () async {
      final server = FakeMcpServer(tools: [_echo], listChanged: true);
      await h.connect(server, kind: 'http');
      server.silentLists = 1;

      server.notifyToolsListChanged();
      await h.clock.elapse(const Duration(seconds: 10));

      expect(server.abandoned, [_lastId(server, 'tools/list')]);
      expect(server.cancelledRequestIds, isEmpty);
    });

    test('the discover probe timeout is not cancelled', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        legacyProbe: FakeLegacyProbe.silent,
      );
      final connected = h.connect(server);
      await h.clock.elapse(const Duration(seconds: 5));
      await connected;

      expect(server.cancelledRequestIds, isEmpty);
    });
  });
}
