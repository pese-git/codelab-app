// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/src/mcp_client.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// Исправления по ревью итерации 3 change `add-agent-mcp-client`
/// (streamable HTTP, D10): отмена до заголовков, ограниченное ожидание
/// `send`, ответ `200 application/json` без своего id, лимит SSE на событие,
/// пауза `retry`, причины и логи транспорта.

const _echo = FakeMcpTool('echo');

String _errorText(McpCallOutcome outcome) => (outcome as McpCallError).text;

/// Клиент: [override] отвечает вместо сервера (`null` — делегировать).
http.Client _intercept(
  FakeMcpServer server,
  Future<http.StreamedResponse?> Function(
    http.BaseRequest request,
    Map<String, Object?>? message,
  )
  override,
) => MockClient.streaming((request, body) async {
  final bytes = await body.toBytes();
  final text = utf8.decode(bytes);
  final Map<String, Object?>? message =
      request.method == 'POST' && text.isNotEmpty
      ? (jsonDecode(text) as Map).cast<String, Object?>()
      : null;
  return await override(request, message) ??
      await server.handleHttp(request, Stream.value(bytes));
});

/// Ответ `200 application/json` с готовым телом.
http.StreamedResponse _json(String body, {int status = 200}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  late McpHarness h;
  setUp(() => h = McpHarness());

  group('retry in SSE', () {
    test('the resume pause is clamped to connectTimeout', () async {
      final server = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);
      final client = await h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          if (message?['method'] != 'tools/call') {
            return null;
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode('id: e1\nretry: 86400000\ndata:\n\n')),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );

      final call = client.callTool('echo', const {}, cancel: CancelToken.none);
      await pumpEventQueue();
      await h.clock.elapse(const Duration(seconds: 10));
      await pumpEventQueue();
      final outcome = await call;

      // `GET` ушёл (пауза зажата до 10 с), фейк не знает события `e1`.
      expect(server.httpLog.where((r) => r.method == 'GET'), hasLength(1));
      expect(_errorText(outcome), contains('disconnected during the call'));
    });

    test('an absurd retry does not break the stream or the zone', () async {
      final server = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);
      final client = await h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          if (message?['method'] != 'tools/call') {
            return null;
          }
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'id: e1\nretry: ${'9' * 25}\ndata:\n\n'
                'data: ${jsonEncode({
                  'jsonrpc': '2.0',
                  'id': message!['id'],
                  'result': {
                    'content': [
                      {'type': 'text', 'text': 'ok'},
                    ],
                  },
                })}\n\n',
              ),
            ),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(outcome, isA<McpCallDone>());
    });
  });

  group('abandon and bounded send', () {
    test('abandon before the headers aborts the request', () async {
      final server = FakeMcpServer(tools: [_echo]);
      var aborted = false;
      final client = await h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          if (message?['method'] != 'tools/call') {
            return null;
          }
          final trigger = (request as http.Abortable).abortTrigger!;
          await trigger;
          aborted = true;
          throw http.RequestAbortedException();
        }),
      );
      final source = CancelTokenSource();
      final call = client.callTool('echo', const {}, cancel: source.token);
      await pumpEventQueue();

      source.cancel('stop');

      await expectLater(call, throwsA(isA<CancelledException>()));
      await pumpEventQueue();
      expect(aborted, isTrue, reason: 'the server saw the cancellation');
    });

    test('a listen without headers does not hold the connection: the ack '
        'timeout applies', () async {
      final server = FakeMcpServer(tools: [_echo], listChanged: true);
      final connecting = h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          if (message?['method'] == 'subscriptions/listen') {
            return Completer<http.StreamedResponse?>().future;
          }
          return null;
        }),
      );
      await pumpEventQueue();

      await h.clock.elapse(const Duration(seconds: 5));
      final client = await connecting;

      expect(client.isConnected, isTrue);
      expect(client.tools, hasLength(1));
      expect(
        h.logger
            .eventsOf('mcp.message.ignored')
            .where((r) => r.fields['kind'] == 'subscription_failed'),
        hasLength(1),
      );
    });

    test('a slow 202 on notifications/cancelled does not delay the '
        'cancellation', () async {
      final gate = Completer<Map<String, Object?>>();
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        responses: {'echo': FakeToolResponse.gated(gate)},
      );
      final client = await h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          if (message?['method'] == 'notifications/cancelled') {
            return Completer<http.StreamedResponse?>().future;
          }
          return null;
        }),
      );
      final source = CancelTokenSource();
      final call = client.callTool('echo', const {}, cancel: source.token);
      await pumpEventQueue();

      source.cancel('stop');

      await expectLater(call, throwsA(isA<CancelledException>()));
    });

    test(
      'a hanging notifications/initialized ends with connectTimeout',
      () async {
        final server = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);
        final connecting = h.connectHttp(
          server,
          client: _intercept(server, (request, message) async {
            if (message?['method'] == 'notifications/initialized') {
              return Completer<http.StreamedResponse?>().future;
            }
            return null;
          }),
        );
        final failure = expectLater(
          connecting,
          throwsA(isA<McpConnectException>()),
        );
        await pumpEventQueue();

        await h.clock.elapse(const Duration(seconds: 10));
        await failure;

        expect(
          h.logged('mcp.server.failed')['reason'],
          'no answer to notifications/initialized within 10 s',
        );
      },
    );
  });

  group('200 application/json without an answer of its own', () {
    Future<McpCallOutcome> callWith(String body) async {
      final server = FakeMcpServer(tools: [_echo]);
      final client = await h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          return message?['method'] == 'tools/call' ? _json(body) : null;
        }),
      );
      return client.callTool('echo', const {}, cancel: CancelToken.none);
    }

    test('a notification only: a local failure, not a hang', () async {
      final outcome = await callWith(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'notifications/message',
          'params': <String, Object?>{},
        }),
      );

      expect(
        _errorText(outcome),
        'MCP server fake transport error: unexpected response (HTTP 200)',
      );
    });

    test('a foreign id: a local failure', () async {
      final outcome = await callWith(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 9999,
          'result': <String, Object?>{},
        }),
      );

      expect(_errorText(outcome), contains('unexpected response (HTTP 200)'));
    });

    test('an error with id null is bound to the request', () async {
      final outcome = await callWith(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32603, 'message': 'boom'},
        }),
      );

      expect(
        _errorText(outcome),
        'MCP server fake returned an error: boom (code -32603)',
      );
    });

    test('not JSON: "invalid JSON in the response"', () async {
      final outcome = await callWith('not json at all');

      expect(
        _errorText(outcome),
        'MCP server fake transport error: invalid JSON in the response',
      );
    });
  });

  group('failures and reasons', () {
    test('a 2xx that is neither JSON nor SSE: unexpected response', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final client = await h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          return message?['method'] == 'tools/call'
              ? http.StreamedResponse(const Stream.empty(), 204)
              : null;
        }),
      );

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(
        _errorText(outcome),
        'MCP server fake transport error: unexpected response (HTTP 204)',
      );
    });

    test(
      'a refused connection: connection failed with the runtimeType only',
      () async {
        final server = FakeMcpServer(tools: [_echo]);
        final client = await h.connectHttp(server);
        server.crash();

        final outcome = await client.callTool(
          'echo',
          const {},
          cancel: CancelToken.none,
        );

        expect(
          _errorText(outcome),
          'MCP server fake disconnected during the call: '
          'connection failed: ClientException',
        );
      },
    );

    test('a redirect: the exact reason, the body is discarded', () async {
      final server = FakeMcpServer(tools: [_echo]);
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = _intercept(
        server,
        (request, message) async =>
            http.StreamedResponse(body.stream, 307, headers: {'location': 'x'}),
      );

      await expectLater(
        h.connectHttp(server, client: client),
        throwsA(isA<McpConnectException>()),
      );

      expect(
        h.logged('mcp.server.failed')['reason'],
        'disconnected: HTTP redirect (307) is not followed',
      );
      await pumpEventQueue();
      expect(cancelled, isTrue);
    });

    test('404 with a session logs mcp.server.closed', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        httpSessionId: 's-1',
      );
      final client = await h.connectHttp(server);
      server.expireSession();

      await client.callTool('echo', const {}, cancel: CancelToken.none);

      final closed = h.logged('mcp.server.closed');
      expect(closed, containsPair('transport', 'http'));
      expect(closed, containsPair('reason', 'HTTP session expired'));
      expect(closed, containsPair('server', 'fake'));
    });

    test('a closed GET stream is logged at debug level', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        listChanged: true,
      );
      await h.connectHttp(server);

      server.closeGetStream();
      await pumpEventQueue();

      final ignored = h.logger
          .eventsOf('mcp.message.ignored')
          .where((r) => r.fields['kind'] == 'notification_stream_closed')
          .single;
      expect(ignored.level, LogLevel.debug);
      expect(ignored.fields['server'], 'fake');
    });
  });

  group('SSE limit is per event', () {
    test('a long stream above 16 MiB in small events lives', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final padding = 'x' * (20 * 1024);
      final client = await h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          if (message?['method'] != 'tools/call') {
            return null;
          }
          Iterable<List<int>> chunks() sync* {
            for (var i = 0; i < 900; i++) {
              yield utf8.encode(
                'data: ${jsonEncode({
                  'jsonrpc': '2.0',
                  'method': 'notifications/progress',
                  'params': {'progressToken': 'p', 'pad': padding},
                })}\n\n',
              );
            }
            yield utf8.encode(
              'data: ${jsonEncode({
                'jsonrpc': '2.0',
                'id': message!['id'],
                'result': {
                  'resultType': 'complete',
                  'content': [
                    {'type': 'text', 'text': 'end'},
                  ],
                },
              })}\n\n',
            );
          }

          return http.StreamedResponse(
            Stream.fromIterable(chunks()),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(outcome, isA<McpCallDone>());
    });
  });

  group('tools and subscription', () {
    test('x-mcp-header on a property without type is invalid', () async {
      final server = FakeMcpServer(
        tools: [
          const FakeMcpTool('good'),
          FakeMcpTool(
            'untyped',
            inputSchema: {
              'type': 'object',
              'properties': {
                'a': {'x-mcp-header': 'A'},
              },
            },
          ),
        ],
      );

      final client = await h.connectHttp(server);

      expect([for (final t in client.tools) t.name], ['good']);
      expect(h.logged('mcp.tool.invalid'), containsPair('tool', 'untyped'));
    });

    test('-32020: onToolsChanged once when the set changed, never when it '
        'did not', () async {
      final annotated = FakeMcpTool(
        'get',
        inputSchema: {
          'type': 'object',
          'properties': {
            'region': {'type': 'string', 'x-mcp-header': 'Region'},
          },
        },
      );
      final changedServer = FakeMcpServer(tools: const [FakeMcpTool('get')]);
      var changed = 0;
      final first = await h.connectHttp(
        changedServer,
        onToolsChanged: (_) => changed++,
      );
      changedServer.setTools([annotated]);
      await first.callTool('get', {'region': 'eu'}, cancel: CancelToken.none);
      expect(changed, 1);

      final h2 = McpHarness();
      final same = FakeMcpServer(tools: const [_echo]);
      var rejected = false;
      var unchanged = 0;
      final second = await h2.connectHttp(
        same,
        onToolsChanged: (_) => unchanged++,
        client: _intercept(same, (request, message) async {
          if (message?['method'] == 'tools/call' && !rejected) {
            rejected = true;
            return _json(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': message!['id'],
                'error': {'code': -32020, 'message': 'mismatch'},
              }),
              status: 400,
            );
          }
          return null;
        }),
      );
      final outcome = await second.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );
      expect(outcome, isA<McpCallDone>());
      expect(unchanged, 0);
    });

    test('the ack of a reissued subscription waits min(5 s, connectTimeout / '
        '2)', () async {
      final server = FakeMcpServer(tools: [_echo], listChanged: true);
      final client = await h.connectHttp(
        server,
        connectTimeout: const Duration(seconds: 4),
      );
      final first = server.httpLog
          .firstWhere((r) => r.json?['method'] == 'subscriptions/listen')
          .json!['id']!;
      server.listen = FakeListen.withhold;

      server.abortResponse(first);
      await pumpEventQueue();
      bool failed() => h.logger
          .eventsOf('mcp.message.ignored')
          .any((r) => r.fields['kind'] == 'subscription_failed');

      await h.clock.elapse(const Duration(milliseconds: 1999));
      expect(failed(), isFalse);
      await h.clock.elapse(const Duration(milliseconds: 1));
      expect(failed(), isTrue);
      expect(client.isConnected, isTrue);
    });
  });
}
