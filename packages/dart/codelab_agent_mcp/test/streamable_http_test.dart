// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/src/mcp_client.dart';
import 'package:codelab_agent_mcp/src/protocol.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// Тест DoD задачи 9.1 change `add-agent-mcp-client` (agent-mcp-client:
/// «Транспорт streamable HTTP», «Эпоха сервера и версия протокола»; D10).
///
/// Сервер — HTTP-обработчик `FakeMcpServer` на `MockClient`: ни сети, ни
/// реального времени (PKG-6); паузы `retry` двигает `FakeClock`.

const _echo = FakeMcpTool('echo');
const _protocolHeader = 'mcp-protocol-version';
const _sessionHeader = 'mcp-session-id';
const _secret = 'Bearer top-secret-token';

Map<String, Object?> _text(String text) => {
  'content': [
    {'type': 'text', 'text': text},
  ],
};

String _errorText(McpCallOutcome outcome) => (outcome as McpCallError).text;

String _b64(String value) => '=?base64?${base64.encode(utf8.encode(value))}?=';

/// Обёртка над обработчиком сервера: [override] может ответить вместо него
/// (редирект, огромное тело, нестандартный статус); `null` — делегировать.
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
  final Map<String, Object?>? message = request.method == 'POST'
      ? (jsonDecode(text) as Map).cast<String, Object?>()
      : null;
  return await override(request, message) ??
      await server.handleHttp(request, Stream.value(bytes));
});

List<String> _methods(FakeMcpServer server, [String http = 'POST']) => [
  for (final r in server.httpLog)
    if (r.method == http && r.json?['method'] is String)
      r.json!['method']! as String,
];

void main() {
  late McpHarness h;
  setUp(() => h = McpHarness());

  group('both eras', () {
    for (final era in [FakeMcpEra.modern, FakeMcpEra.legacy]) {
      test('POST headers and 202 for notifications (${era.name})', () async {
        final server = FakeMcpServer(era: era, tools: [_echo]);

        await h.connectHttp(
          server,
          headers: [('Authorization', _secret), ('Accept', 'text/plain')],
        );

        final posts = server.httpLog.where((r) => r.method == 'POST');
        expect(posts, isNotEmpty);
        for (final post in posts) {
          expect(post.headers['content-type'], 'application/json');
          // Служебные заголовки перекрывают заголовки сервера.
          expect(post.headers['accept'], 'application/json, text/event-stream');
          expect(post.headers['authorization'], _secret);
        }
        if (era == FakeMcpEra.legacy) {
          // `notifications/initialized` принят с 202 и без тела.
          expect(_methods(server), contains('notifications/initialized'));
          expect(server.violations, isEmpty);
        }
      });
    }

    test('an SSE answer with a progress notification and a keep-alive '
        'comment gives the result; the transport stays alive', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        httpStyle: FakeHttpStyle.sse,
        responses: {'echo': FakeToolResponse.result(_text('hi'))},
      );
      final client = await h.connectHttp(server);

      final outcome = await client.callTool('echo', {
        'text': 'hi',
      }, cancel: CancelToken.none);

      expect((outcome as McpCallDone).result.content.single['text'], 'hi');
      final ignored = h.logger
          .eventsOf('mcp.message.ignored')
          .where((r) => r.fields['kind'] == 'unknown_notification');
      expect(ignored, isNotEmpty);
      expect(client.isConnected, isTrue);
      final second = await client.callTool('echo', const {
        'text': 'again',
      }, cancel: CancelToken.none);
      expect(second, isA<McpCallDone>());
    });

    test('a redirect is not followed: the connection fails', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final requests = <http.BaseRequest>[];
      final client = _intercept(server, (request, message) async {
        requests.add(request);
        return http.StreamedResponse(
          const Stream.empty(),
          307,
          headers: {'location': 'https://evil.example.org/mcp'},
        );
      });

      await expectLater(
        h.connectHttp(server, client: client, headers: [('X-Key', _secret)]),
        throwsA(isA<McpConnectException>()),
      );

      expect(requests, hasLength(1));
      expect(requests.single.followRedirects, isFalse);
      expect(requests.single.url.host, 'mcp.example.com');
      final failed = h.logged('mcp.server.failed');
      expect(failed['reason'], contains('307'));
      expect(failed['reason'], isNot(contains('evil')));
    });

    test('a scheme other than http and https is "invalid url"', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final factory = StreamableHttpTransportFactory(
        client: server.httpClient(),
        clock: h.clock,
      );

      await expectLater(
        factory.open(
          McpHttpServerConfig(name: 'web', url: Uri.parse('ftp://host/mcp')),
          cwd: '/proj',
          cancel: CancelToken.none,
          logger: h.logger,
        ),
        throwsA(
          isA<McpTransportException>().having(
            (e) => e.message,
            'message',
            'invalid url',
          ),
        ),
      );
      expect(server.httpLog, isEmpty);
    });

    test('a response body above 16 MiB is an error', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final chunk = Uint8List(1 << 20)..fillRange(0, 1 << 20, 0x20);
      final client = _intercept(server, (request, message) async {
        if (message?['method'] != 'tools/call') {
          return null;
        }
        return http.StreamedResponse(
          Stream.fromIterable([for (var i = 0; i < 17; i++) chunk]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final mcp = await h.connectHttp(server, client: client);

      final outcome = await mcp.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(_errorText(outcome), contains('too large'));
      expect(mcp.isConnected, isTrue);
    });

    test('no header value reaches the log', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        listChanged: true,
        httpSessionId: 'session-secret-42',
      );
      final client = await h.connectHttp(
        server,
        headers: [('Authorization', _secret)],
      );
      server.expireSession();
      await client.callTool('echo', const {}, cancel: CancelToken.none);
      await client.close();

      for (final record in h.logger.records) {
        final text = jsonEncode(record.fields);
        expect(text, isNot(contains('top-secret')), reason: record.event);
        expect(text, isNot(contains('session-secret')), reason: record.event);
      }
    });
  });

  group('modern', () {
    test(
      'mirror headers on every request, no session, GET or DELETE',
      () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        final client = await h.connectHttp(server);
        await client.callTool('echo', const {}, cancel: CancelToken.none);
        await client.close();

        for (final r in server.httpLog) {
          expect(r.method, 'POST', reason: 'no GET or DELETE in modern');
          expect(r.headers[_protocolHeader], '2026-07-28');
          expect(r.headers['mcp-method'], r.json!['method']);
          expect(r.headers, isNot(contains(_sessionHeader)));
        }
        final call = server.httpLog.lastWhere(
          (r) => r.json!['method'] == 'tools/call',
        );
        expect(call.headers['mcp-name'], 'echo');
        expect(
          server.httpLog
              .where((r) => r.json!['method'] != 'tools/call')
              .map((r) => r.headers.containsKey('mcp-name')),
          everyElement(isFalse),
        );
        expect(server.violations, isEmpty);
      },
    );

    test('Mcp-Param-* from x-mcp-header with base64 encoding', () async {
      final tool = FakeMcpTool(
        'get_weather',
        inputSchema: {
          'type': 'object',
          'properties': {
            'region': {'type': 'string', 'x-mcp-header': 'Region'},
            'city': {'type': 'string', 'x-mcp-header': 'City'},
            'marker': {'type': 'string', 'x-mcp-header': 'Marker'},
            'padded': {'type': 'string', 'x-mcp-header': 'Padded'},
            'count': {'type': 'integer', 'x-mcp-header': 'Count'},
            'flag': {'type': 'boolean', 'x-mcp-header': 'Flag'},
            'missing': {'type': 'string', 'x-mcp-header': 'Missing'},
            'nothing': {'type': 'string', 'x-mcp-header': 'Nothing'},
            'opts': {
              'type': 'object',
              'properties': {
                'deep': {'type': 'string', 'x-mcp-header': 'Deep'},
              },
            },
          },
        },
      );
      final server = FakeMcpServer(tools: [tool]);
      final client = await h.connectHttp(server);

      final outcome = await client.callTool('get_weather', {
        'region': 'Москва',
        'city': 'Oslo',
        'marker': '=?base64?literal?=',
        'padded': ' a ',
        'count': 42,
        'flag': false,
        'nothing': null,
        'opts': {'deep': 'x'},
      }, cancel: CancelToken.none);

      expect(outcome, isA<McpCallDone>());
      final call = server.httpLog.lastWhere(
        (r) => r.json!['method'] == 'tools/call',
      );
      expect(call.headers['mcp-name'], 'get_weather');
      expect(call.headers['mcp-param-region'], _b64('Москва'));
      expect(call.headers['mcp-param-city'], 'Oslo');
      expect(call.headers['mcp-param-marker'], _b64('=?base64?literal?='));
      expect(call.headers['mcp-param-padded'], _b64(' a '));
      expect(call.headers['mcp-param-count'], '42');
      expect(call.headers['mcp-param-flag'], 'false');
      expect(call.headers['mcp-param-deep'], 'x');
      // Нет значения или `null` — заголовка нет.
      expect(call.headers, isNot(contains('mcp-param-missing')));
      expect(call.headers, isNot(contains('mcp-param-nothing')));
      expect(server.violations, isEmpty);
    });

    test(
      'a name outside the safe set is carried in Mcp-Name as base64',
      () async {
        final server = FakeMcpServer(tools: [const FakeMcpTool('погода')]);
        final client = await h.connectHttp(server);

        await client.callTool('погода', const {}, cancel: CancelToken.none);

        final call = server.httpLog.lastWhere(
          (r) => r.json!['method'] == 'tools/call',
        );
        expect(call.headers['mcp-name'], _b64('погода'));
      },
    );

    test(
      'tools with an invalid x-mcp-header are excluded (HTTP only)',
      () async {
        Map<String, Object?> schema(Map<String, Object?> properties) => {
          'type': 'object',
          'properties': properties,
        };
        final tools = [
          const FakeMcpTool('good'),
          FakeMcpTool(
            'empty_name',
            inputSchema: schema({
              'a': {'type': 'string', 'x-mcp-header': ''},
            }),
          ),
          FakeMcpTool(
            'not_a_token',
            inputSchema: schema({
              'a': {'type': 'string', 'x-mcp-header': 'bad name'},
            }),
          ),
          FakeMcpTool(
            'duplicate',
            inputSchema: schema({
              'a': {'type': 'string', 'x-mcp-header': 'Same'},
              'b': {'type': 'string', 'x-mcp-header': 'same'},
            }),
          ),
          FakeMcpTool(
            'number',
            inputSchema: schema({
              'a': {'type': 'number', 'x-mcp-header': 'N'},
            }),
          ),
          FakeMcpTool(
            'object',
            inputSchema: schema({
              'a': {'type': 'object', 'x-mcp-header': 'O'},
            }),
          ),
          FakeMcpTool(
            'in_items',
            inputSchema: schema({
              'list': {
                'type': 'array',
                'items': {'type': 'string', 'x-mcp-header': 'Item'},
              },
            }),
          ),
          FakeMcpTool(
            'in_one_of',
            inputSchema: schema({
              'a': {
                'oneOf': [
                  {'type': 'string', 'x-mcp-header': 'Alt'},
                ],
              },
            }),
          ),
          FakeMcpTool(
            'valid_nested',
            inputSchema: schema({
              'o': schema({
                'a': {'type': 'integer', 'x-mcp-header': 'Nested'},
              }),
            }),
          ),
        ];
        final server = FakeMcpServer(tools: tools);

        final http = await h.connectHttp(server);

        expect([for (final t in http.tools) t.name], ['good', 'valid_nested']);
        final invalid = h.logger.eventsOf('mcp.tool.invalid');
        expect(
          [for (final r in invalid) r.fields['tool']],
          [
            'empty_name',
            'not_a_token',
            'duplicate',
            'number',
            'object',
            'in_items',
            'in_one_of',
          ],
        );
        expect(
          invalid.map((r) => r.fields['reason']),
          everyElement('invalid x-mcp-header'),
        );

        // stdio аннотации игнорирует (MAY): те же инструменты остаются.
        final stdioHarness = McpHarness();
        final stdio = await stdioHarness.connect(FakeMcpServer(tools: tools));
        expect(stdio.tools, hasLength(tools.length));
      },
    );

    test('-32020 gives one tools/list and a retry with a new id', () async {
      final annotated = FakeMcpTool(
        'get_weather',
        inputSchema: {
          'type': 'object',
          'properties': {
            'region': {'type': 'string', 'x-mcp-header': 'Region'},
          },
        },
      );
      final server = FakeMcpServer(tools: const [FakeMcpTool('get_weather')]);
      final client = await h.connectHttp(server);
      // Схема изменилась без уведомления: клиент ещё шлёт вызов без заголовка.
      server.setTools([annotated]);
      final before = server.httpLog.length;

      final outcome = await client.callTool('get_weather', {
        'region': 'eu',
      }, cancel: CancelToken.none);

      expect(outcome, isA<McpCallDone>());
      final tail = server.httpLog.skip(before).toList();
      expect(
        [for (final r in tail) r.json!['method']],
        ['tools/call', 'tools/list', 'tools/call'],
      );
      expect(tail[0].json!['id'], isNot(tail[2].json!['id']));
      expect(tail[0].headers, isNot(contains('mcp-param-region')));
      expect(tail[2].headers['mcp-param-region'], 'eu');
      expect(server.calls, hasLength(1));
    });

    test(
      '-32020 twice: the second error is the result, no third try',
      () async {
        final server = FakeMcpServer(tools: const [_echo]);
        final client = await h.connectHttp(
          server,
          client: _intercept(server, (request, message) async {
            if (message?['method'] != 'tools/call') {
              return null;
            }
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': message!['id'],
                    'error': {'code': -32020, 'message': 'Header mismatch'},
                  }),
                ),
              ),
              400,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final outcome = await client.callTool(
          'echo',
          const {},
          cancel: CancelToken.none,
        );

        expect(_errorText(outcome), contains('(code -32020)'));
        expect(_methods(server).where((m) => m == 'tools/list'), hasLength(2));
      },
    );

    test(
      'subscriptions/listen is a long stream carrying list_changed',
      () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        final seen = <List<String>>[];
        await h.connectHttp(
          server,
          onToolsChanged: (tools) => seen.add([for (final t in tools) t.name]),
        );

        server.notifyToolsListChanged(
          newTools: [_echo, const FakeMcpTool('b')],
        );
        await pumpEventQueue();
        server.notifyToolsListChanged(newTools: [const FakeMcpTool('c')]);
        await pumpEventQueue();

        expect(seen, [
          ['echo', 'b'],
          ['c'],
        ]);
        expect(server.subscriptions, 1);
      },
    );

    test(
      'cancel closes the response stream and sends no notifications/cancelled',
      () async {
        final gate = Completer<Map<String, Object?>>();
        final server = FakeMcpServer(
          tools: [_echo],
          responses: {'echo': FakeToolResponse.gated(gate)},
        );
        final client = await h.connectHttp(server);
        final source = CancelTokenSource();
        final call = client.callTool('echo', const {}, cancel: source.token);
        await pumpEventQueue();
        final callId = server.httpLog
            .lastWhere((r) => r.json!['method'] == 'tools/call')
            .json!['id']!;

        source.cancel('stop');

        await expectLater(call, throwsA(isA<CancelledException>()));
        await pumpEventQueue();
        expect(server.abandoned, [callId]);
        expect(_methods(server), isNot(contains('notifications/cancelled')));
        expect(server.cancelledRequestIds, isEmpty);
      },
    );
  });

  group('era probe over HTTP', () {
    for (final status in [400, 404, 405]) {
      test(
        '$status with -32022 means: no common version, no fallback',
        () async {
          final server = FakeMcpServer(
            era: FakeMcpEra.legacy,
            tools: [_echo],
            probeReply: FakeHttpReply.error(
              status,
              -32022,
              supported: const ['2025-11-25'],
            ),
          );

          await expectLater(
            h.connectHttp(server),
            throwsA(isA<McpConnectException>()),
          );

          expect(_methods(server), ['server/discover']);
          expect(
            h.logged('mcp.server.failed')['reason'],
            'no common protocol version: server supports [2025-11-25]',
          );
          expect(
            h.logged('mcp.server.era'),
            containsPair('probe', 'modern_error'),
          );
        },
      );
    }

    final fallbacks = {
      '400 with an empty body': FakeHttpReply(400, ''),
      '404': FakeHttpReply(404, ''),
      '405': FakeHttpReply(405, ''),
      '404 with -32601': FakeHttpReply.error(404, -32601),
    };
    fallbacks.forEach((name, reply) {
      test('$name falls back to initialize', () async {
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          probeReply: reply,
        );

        final client = await h.connectHttp(server);

        expect(client.era, McpEra.legacy);
        expect(_methods(server).take(2), ['server/discover', 'initialize']);
        expect(
          h.logged('mcp.server.era'),
          containsPair('probe', 'fallback_error'),
        );
      });
    });
  });

  group('legacy', () {
    test('Mcp-Session-Id and MCP-Protocol-Version follow initialize', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        listChanged: true,
        httpSessionId: 's-1',
        legacyVersion: '2025-06-18',
      );
      final client = await h.connectHttp(server);
      await client.callTool('echo', const {}, cancel: CancelToken.none);
      await client.close();

      final init = server.httpLog.firstWhere(
        (r) => r.json?['method'] == 'initialize',
      );
      expect(init.headers, isNot(contains(_sessionHeader)));
      final after = server.httpLog.skipWhile((r) => r != init).skip(1);
      expect(after, isNotEmpty);
      for (final r in after) {
        expect(r.headers[_sessionHeader], 's-1', reason: r.method);
        expect(r.headers[_protocolHeader], '2025-06-18', reason: r.method);
      }
      expect(
        server.httpLog.map((r) => r.method),
        containsAll(['POST', 'GET', 'DELETE']),
      );
    });

    test('no MCP-Protocol-Version for 2025-03-26', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        httpSessionId: 's-1',
        legacyVersion: '2025-03-26',
      );
      final client = await h.connectHttp(server);
      await client.callTool('echo', const {}, cancel: CancelToken.none);

      // Проба `server/discover` — modern-запрос и несёт свой заголовок;
      // после `initialize` заголовка нет.
      final afterInit = server.httpLog
          .skipWhile((r) => r.json?['method'] != 'initialize')
          .toList();
      expect(afterInit.length, greaterThan(2));
      for (final r in afterInit) {
        expect(r.headers, isNot(contains(_protocolHeader)));
      }
      expect(server.httpLog.last.headers[_sessionHeader], 's-1');
    });

    test(
      'a GET stream carries list_changed when the server announces it',
      () async {
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          listChanged: true,
          httpSessionId: 's-1',
        );
        final seen = <int>[];
        await h.connectHttp(server, onToolsChanged: (t) => seen.add(t.length));

        final get = server.httpLog.singleWhere((r) => r.method == 'GET');
        expect(get.headers['accept'], contains('text/event-stream'));
        server.notifyToolsListChanged(
          newTools: [_echo, const FakeMcpTool('b')],
        );
        await pumpEventQueue();

        expect(seen, [2]);
      },
    );

    test('405 on GET means: no stream, the server stays connected', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        listChanged: true,
        allowGetStream: false,
      );

      final client = await h.connectHttp(server);
      await pumpEventQueue();

      expect(client.isConnected, isTrue);
      expect(server.httpLog.where((r) => r.method == 'GET'), hasLength(1));
    });

    test('no GET when the server does not announce listChanged', () async {
      final server = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);

      await h.connectHttp(server);

      expect(server.httpLog.where((r) => r.method == 'GET'), isEmpty);
    });

    test('404 with a session means "HTTP session expired"', () async {
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        httpSessionId: 's-1',
      );
      final client = await h.connectHttp(server);
      server.expireSession();

      final first = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );
      final second = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(
        _errorText(first),
        'MCP server fake disconnected during the call: HTTP session expired',
      );
      expect(
        _errorText(second),
        'MCP server fake is not connected. Continue without it.',
      );
      expect(
        h.logged('mcp.server.failed'),
        containsPair('reason', 'disconnected: HTTP session expired'),
      );
    });

    test('close sends DELETE; 405 is normal', () async {
      for (final allowed in [true, false]) {
        final local = McpHarness();
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          httpSessionId: 's-1',
          allowDelete: allowed,
        );
        final client = await local.connectHttp(server);

        await client.close();
        await client.close();

        final deletes = server.httpLog.where((r) => r.method == 'DELETE');
        expect(deletes, hasLength(1), reason: 'allowed=$allowed');
        expect(deletes.single.headers[_sessionHeader], 's-1');
      }
    });

    test(
      'cancel sends notifications/cancelled and closes the stream',
      () async {
        final gate = Completer<Map<String, Object?>>();
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          responses: {'echo': FakeToolResponse.gated(gate)},
        );
        final client = await h.connectHttp(server);
        final source = CancelTokenSource();
        final call = client.callTool('echo', const {}, cancel: source.token);
        await pumpEventQueue();
        final callId = server.httpLog
            .lastWhere((r) => r.json!['method'] == 'tools/call')
            .json!['id']!;

        source.cancel('stop');

        await expectLater(call, throwsA(isA<CancelledException>()));
        await pumpEventQueue();
        expect(server.cancelledRequestIds, [callId]);
        expect(server.abandoned, [callId]);
      },
    );

    group('polling: Last-Event-ID resume', () {
      test(
        'resumes after the retry pause, without a second tools/call',
        () async {
          final server = FakeMcpServer(
            era: FakeMcpEra.legacy,
            tools: [_echo],
            legacyVersion: '2025-11-25',
            pollCloses: 1,
            responses: {'echo': FakeToolResponse.result(_text('late'))},
          );
          final client = await h.connectHttp(server);

          final call = client.callTool(
            'echo',
            const {},
            cancel: CancelToken.none,
          );
          await pumpEventQueue();
          await h.clock.elapse(const Duration(milliseconds: 99));
          expect(
            server.httpLog.where((r) => r.method == 'GET'),
            isEmpty,
            reason: 'retry: 100 not yet elapsed',
          );
          await h.clock.elapse(const Duration(milliseconds: 1));
          await pumpEventQueue();
          final outcome = await call;

          expect(
            (outcome as McpCallDone).result.content.single['text'],
            'late',
          );
          final gets = server.httpLog.where((r) => r.method == 'GET').toList();
          expect(gets, hasLength(1));
          expect(gets.single.headers['last-event-id'], 'e1');
          expect(
            _methods(server).where((m) => m == 'tools/call'),
            hasLength(1),
          );
          expect(server.calls, hasLength(1));
        },
      );

      test('without retry the pause is one second', () async {
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          pollCloses: 1,
          pollRetry: null,
        );
        final client = await h.connectHttp(server);

        final call = client.callTool(
          'echo',
          const {},
          cancel: CancelToken.none,
        );
        await pumpEventQueue();
        await h.clock.elapse(const Duration(milliseconds: 999));
        expect(server.httpLog.where((r) => r.method == 'GET'), isEmpty);
        await h.clock.elapse(const Duration(milliseconds: 1));
        await pumpEventQueue();

        expect(await call, isA<McpCallDone>());
      });

      test('no more than 5 resumes per request', () async {
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          pollCloses: 10,
        );
        final client = await h.connectHttp(server);

        final call = client.callTool(
          'echo',
          const {},
          cancel: CancelToken.none,
        );
        for (var i = 0; i < 8; i++) {
          await pumpEventQueue();
          await h.clock.elapse(const Duration(milliseconds: 100));
        }
        await pumpEventQueue();
        final outcome = await call;

        expect(
          _errorText(outcome),
          'MCP server fake disconnected during the call: '
          'response stream closed',
        );
        expect(server.httpLog.where((r) => r.method == 'GET'), hasLength(5));
        expect(server.calls, hasLength(1));
      });

      test('a stream closed without event ids is not resumed', () async {
        final gate = Completer<Map<String, Object?>>();
        final server = FakeMcpServer(
          era: FakeMcpEra.legacy,
          tools: [_echo],
          responses: {'echo': FakeToolResponse.gated(gate)},
        );
        final client = await h.connectHttp(server);
        final call = client.callTool(
          'echo',
          const {},
          cancel: CancelToken.none,
        );
        await pumpEventQueue();

        server.abortResponse(
          server.httpLog
              .lastWhere((r) => r.json!['method'] == 'tools/call')
              .json!['id']!,
        );
        final outcome = await call;

        expect(_errorText(outcome), contains('disconnected during the call'));
        expect(server.httpLog.where((r) => r.method == 'GET'), isEmpty);
        expect(server.calls, hasLength(1));
      });
    });
  });

  group('broken response stream without resume', () {
    for (final era in [FakeMcpEra.modern, FakeMcpEra.legacy]) {
      test('tools/call is not repeated (${era.name})', () async {
        final gate = Completer<Map<String, Object?>>();
        final server = FakeMcpServer(
          era: era,
          tools: [_echo],
          responses: {'echo': FakeToolResponse.gated(gate)},
        );
        final client = await h.connectHttp(server);
        final call = client.callTool(
          'echo',
          const {},
          cancel: CancelToken.none,
        );
        await pumpEventQueue();

        server.abortResponse(
          server.httpLog
              .lastWhere((r) => r.json!['method'] == 'tools/call')
              .json!['id']!,
        );
        final outcome = await call;

        expect(
          _errorText(outcome),
          'MCP server fake disconnected during the call: '
          'response stream closed',
        );
        expect(_methods(server).where((m) => m == 'tools/call'), hasLength(1));
        expect(client.isConnected, isTrue);
      });
    }

    test(
      'tools/list and server/discover are repeated once with a new id',
      () async {
        final server = FakeMcpServer(
          tools: [_echo],
          abortDiscover: 1,
          abortListResponses: 1,
        );

        final client = await h.connectHttp(server);

        expect(client.tools, hasLength(1));
        for (final method in ['server/discover', 'tools/list']) {
          final sent = server.httpLog
              .where((r) => r.json?['method'] == method)
              .toList();
          expect(sent, hasLength(2), reason: method);
          expect(sent[0].json!['id'], isNot(sent[1].json!['id']));
        }
      },
    );

    test('a second break of tools/list fails the connection', () async {
      final server = FakeMcpServer(tools: [_echo], abortListResponses: 2);

      await expectLater(
        h.connectHttp(server),
        throwsA(isA<McpConnectException>()),
      );

      expect(_methods(server).where((m) => m == 'tools/list'), hasLength(2));
    });

    group('subscriptions/listen', () {
      test('a break before the ack is repeated once; the new id is the '
          'subscriptionId', () async {
        final server = FakeMcpServer(
          tools: [_echo],
          listChanged: true,
          abortListens: 1,
        );
        final seen = <int>[];
        await h.connectHttp(server, onToolsChanged: (t) => seen.add(t.length));

        final listens = server.httpLog
            .where((r) => r.json?['method'] == 'subscriptions/listen')
            .toList();
        expect(listens, hasLength(2));
        expect(listens[0].json!['id'], isNot(listens[1].json!['id']));
        // Список читается после подписки: отдельное перечитывание не нужно.
        expect(_methods(server).where((m) => m == 'tools/list'), hasLength(1));

        server.notifyToolsListChanged(
          newTools: [_echo, const FakeMcpTool('b')],
          subscriptionId: listens[0].json!['id'],
        );
        await pumpEventQueue();
        expect(seen, isEmpty, reason: 'the old subscriptionId is not accepted');

        server.notifyToolsListChanged(
          newTools: [_echo, const FakeMcpTool('b')],
        );
        await pumpEventQueue();
        expect(seen, [2]);
      });

      test('a live subscription broken after the ack is reissued, then '
          'tools/list is read once', () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        final seen = <List<String>>[];
        final client = await h.connectHttp(
          server,
          onToolsChanged: (t) => seen.add([for (final d in t) d.name]),
        );
        final firstListen = server.httpLog
            .firstWhere((r) => r.json?['method'] == 'subscriptions/listen')
            .json!['id']!;
        final listsBefore = _methods(server).where((m) => m == 'tools/list');

        // Изменение в окне обрыва: уведомление потеряно.
        server.setTools([_echo, const FakeMcpTool('b')]);
        server.abortResponse(firstListen);
        await pumpEventQueue();

        final listens = server.httpLog
            .where((r) => r.json?['method'] == 'subscriptions/listen')
            .toList();
        expect(listens, hasLength(2));
        expect(
          _methods(server).where((m) => m == 'tools/list').length,
          listsBefore.length + 1,
        );
        expect(seen, [
          ['echo', 'b'],
        ]);
        expect(client.isConnected, isTrue);

        server.notifyToolsListChanged(
          newTools: [const FakeMcpTool('c')],
          subscriptionId: firstListen,
        );
        await pumpEventQueue();
        expect(seen, hasLength(1), reason: 'old id is not accepted');
        server.notifyToolsListChanged(newTools: [const FakeMcpTool('c')]);
        await pumpEventQueue();
        expect(seen.last, ['c']);
      });

      test('the second break: connected, no updates; failed before the ack, '
          'closed after it', () async {
        final before = FakeMcpServer(
          tools: [_echo],
          listChanged: true,
          abortListens: 2,
        );
        var calls = 0;

        final client = await h.connectHttp(
          before,
          onToolsChanged: (_) => calls++,
        );
        before.notifyToolsListChanged();
        await pumpEventQueue();

        expect(client.isConnected, isTrue);
        expect(calls, 0);
        expect(
          h.logger
              .eventsOf('mcp.message.ignored')
              .where((r) => r.fields['kind'] == 'subscription_failed'),
          hasLength(1),
        );

        final h2 = McpHarness();
        final after = FakeMcpServer(tools: [_echo], listChanged: true);
        var calls2 = 0;
        final client2 = await h2.connectHttp(
          after,
          onToolsChanged: (_) => calls2++,
        );
        final first = after.httpLog
            .firstWhere((r) => r.json?['method'] == 'subscriptions/listen')
            .json!['id']!;
        after.abortResponse(first);
        await pumpEventQueue();
        final second = after.httpLog
            .lastWhere((r) => r.json?['method'] == 'subscriptions/listen')
            .json!['id']!;
        calls2 = 0;
        after.abortResponse(second);
        await pumpEventQueue();
        after.notifyToolsListChanged();
        await pumpEventQueue();

        expect(client2.isConnected, isTrue);
        expect(calls2, 0);
        expect(
          after.httpLog.where(
            (r) => r.json?['method'] == 'subscriptions/listen',
          ),
          hasLength(2),
        );
        expect(
          h2.logger
              .eventsOf('mcp.message.ignored')
              .where((r) => r.fields['kind'] == 'subscription_closed'),
          hasLength(1),
        );
      });
    });
  });

  // basic/index.md «Error Codes»: локальные сбои транспорта не оформляются
  // кодом JSON-RPC (диапазон -32000…-32019 — legacy, ошибку нельзя
  // спутать с ответом сервера).
  group('local transport failures carry no JSON-RPC code', () {
    http.Client failing(FakeMcpServer server, String method, int status) =>
        _intercept(server, (request, message) async {
          if (message?['method'] != method) {
            return null;
          }
          return http.StreamedResponse(const Stream.empty(), status);
        });

    test(
      '500 without a body on tools/call: text without code, no repeat',
      () async {
        final server = FakeMcpServer(tools: [_echo]);
        final client = await h.connectHttp(
          server,
          client: failing(server, 'tools/call', 500),
        );

        final outcome = await client.callTool(
          'echo',
          const {},
          cancel: CancelToken.none,
        );

        expect(
          _errorText(outcome),
          'MCP server fake transport error: HTTP 500',
        );
        expect(client.isConnected, isTrue);
        for (final record in h.logger.records) {
          expect(jsonEncode(record.fields), isNot(contains('-32000')));
        }
        // Запрос ушёл на сервер один раз: `tools/call` не повторяется.
        expect(server.calls, isEmpty);
      },
    );

    test('500 without a body on tools/list is not repeated; the reason has '
        'the method and no code', () async {
      final server = FakeMcpServer(tools: [_echo]);
      var lists = 0;
      final inner = failing(server, 'tools/list', 500);
      final client = MockClient.streaming((request, body) async {
        final bytes = await body.toBytes();
        if (utf8.decode(bytes).contains('"tools/list"')) {
          lists++;
        }
        return inner.send(
          http.Request(request.method, request.url)
            ..headers.addAll(request.headers)
            ..bodyBytes = bytes,
        );
      });

      await expectLater(
        h.connectHttp(server, client: client),
        throwsA(isA<McpConnectException>()),
      );

      expect(lists, 1);
      expect(
        h.logged('mcp.server.failed')['reason'],
        'tools/list failed: HTTP 500',
      );
    });

    test('a too large body: text without code', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final chunk = Uint8List(1 << 20);
      final client = await h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          if (message?['method'] != 'tools/call') {
            return null;
          }
          return http.StreamedResponse(
            Stream.fromIterable([for (var i = 0; i < 17; i++) chunk]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(
        _errorText(outcome),
        'MCP server fake transport error: response body too large',
      );
    });

    test('an error with a real JSON-RPC body keeps the server code', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final client = await h.connectHttp(
        server,
        client: _intercept(server, (request, message) async {
          if (message?['method'] != 'tools/call') {
            return null;
          }
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': null,
                  'error': {'code': -32603, 'message': 'boom'},
                }),
              ),
            ),
            500,
          );
        }),
      );

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(
        _errorText(outcome),
        'MCP server fake returned an error: boom (code -32603)',
      );
    });
  });

  group('factory and connector', () {
    test(
      'McpClientConnector connects an http server through the factory',
      () async {
        final server = FakeMcpServer(tools: [_echo]);
        final connector = McpClientConnector(
          transports: McpTransports(
            http: StreamableHttpTransportFactory(
              client: server.httpClient(),
              clock: h.clock,
            ),
          ),
          clock: h.clock,
        );
        expect(connector.transports, {'http'});

        final session = await connector.connect(
          McpConnectRequest(
            sessionId: const SessionId('s1'),
            cwd: '/proj',
            servers: [
              McpHttpServerConfig(
                name: 'web',
                url: Uri.parse('https://mcp.example.com/mcp'),
                headers: const [('Authorization', _secret)],
              ),
            ],
            reservedNames: const {},
            logger: h.logger,
            cancel: CancelToken.none,
          ),
        );

        expect([for (final t in session.tools) t.name], ['mcp__web__echo']);
        expect(server.httpLog.first.headers['authorization'], _secret);
        await session.close();
      },
    );

    test('an invalid url is a failed server, not an exception', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final connector = McpClientConnector(
        transports: McpTransports(
          http: StreamableHttpTransportFactory(
            client: server.httpClient(),
            clock: h.clock,
          ),
        ),
        clock: h.clock,
      );

      final session = await connector.connect(
        McpConnectRequest(
          sessionId: const SessionId('s1'),
          cwd: '/proj',
          servers: [
            McpHttpServerConfig(name: 'web', url: Uri.parse('ftp://h/mcp')),
          ],
          reservedNames: const {},
          logger: h.logger,
          cancel: CancelToken.none,
        ),
      );

      expect(session.tools, isEmpty);
      expect(
        h.logged('mcp.server.failed'),
        containsPair('reason', 'invalid url'),
      );
      expect(server.httpLog, isEmpty);
    });
  });
}
