import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' show ioProviderCheck;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Проверка `/models` (client-agent-setup «Проверка списка моделей»;
/// design.md change `add-provider-setup-ui`, D8; SETUP-10, SETUP-23).
///
/// Ключ — только фиктивный маркер `sk-test-leak-…`; сети нет: `MockClient` и
/// сервер на loopback.
void main() {
  const leak = 'sk-test-leak-0123456789';
  const timeout = Duration(seconds: 5);
  final key = SecretValue(leak);

  late RecordingLogger logger;

  setUp(() => logger = RecordingLogger());

  HttpProviderCheck checkOver(
    Future<http.Response> Function(http.Request request) handler,
  ) => HttpProviderCheck(() => MockClient(handler), logger: logger);

  String everything(Object result) =>
      '$result ${logger.records.map((r) => '${r.event} ${r.fields} ${r.error}')}';

  group('заголовки и пути', () {
    test('OpenAI-совместимый и Anthropic', () async {
      final seen = <http.Request>[];
      final check = checkOver((request) async {
        seen.add(request);
        return http.Response('{"data":[]}', 200);
      });

      await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        SecretValue('k'),
        timeout: timeout,
      );
      await check.listModels(
        'anthropic',
        Uri.parse('https://a'),
        SecretValue('k'),
        timeout: timeout,
      );

      expect(seen[0].method, 'GET');
      expect(seen[0].url, Uri.parse('https://h/v1/models'));
      expect(seen[0].headers['Authorization'], 'Bearer k');
      expect(seen[1].url, Uri.parse('https://a/v1/models'));
      expect(seen[1].headers['x-api-key'], 'k');
      expect(seen[1].headers['anthropic-version'], isNotEmpty);
      expect(seen[1].headers.containsKey('Authorization'), isFalse);
    });

    test(
      'завершающий слэш адреса убирается, без ключа нет заголовка',
      () async {
        late http.Request seen;
        final check = checkOver((request) async {
          seen = request;
          return http.Response('{"data":[]}', 200);
        });

        await check.listModels(
          'openai-compatible',
          Uri.parse('http://localhost:11434/v1/'),
          null,
          timeout: timeout,
        );

        expect(seen.url, Uri.parse('http://localhost:11434/v1/models'));
        expect(seen.headers.containsKey('Authorization'), isFalse);
      },
    );

    test('редиректы запрещены на уровне запроса (SETUP-23)', () async {
      late http.Request seen;
      final check = checkOver((request) async {
        seen = request;
        return http.Response('{"data":[]}', 200);
      });

      await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: timeout,
      );

      expect(seen.followRedirects, isFalse);
    });

    test('неизвестный вид не делает запрос', () async {
      var calls = 0;
      final check = checkOver((request) async {
        calls++;
        return http.Response('', 200);
      });

      final result = await check.listModels(
        'gemini',
        Uri.parse('https://g'),
        key,
        timeout: timeout,
      );

      expect(
        (result as CheckFailure).failure.kind,
        ProviderCheckFailureKind.badResponse,
      );
      expect(calls, 0);
    });
  });

  group('виды провайдеров', () {
    test('supportsProviderCheck: только openai-compatible и anthropic', () {
      expect(supportsProviderCheck('openai-compatible'), isTrue);
      expect(supportsProviderCheck('anthropic'), isTrue);
      expect(supportsProviderCheck('gemini'), isFalse);
      expect(supportsProviderCheck('whatever'), isFalse);
    });

    test('defaultProviderBaseUrl: умолчания ядра для вида без base_url', () {
      expect(
        defaultProviderBaseUrl('anthropic'),
        Uri.parse('https://api.anthropic.com'),
      );
      expect(
        defaultProviderBaseUrl('gemini'),
        Uri.parse('https://generativelanguage.googleapis.com'),
      );
      // У openai-compatible умолчания нет: `base_url` обязателен.
      expect(defaultProviderBaseUrl('openai-compatible'), isNull);
      expect(defaultProviderBaseUrl('whatever'), isNull);
    });
  });

  group('разбор ответа', () {
    test('200: модели и окно контекста из трёх полей', () async {
      final check = checkOver(
        (request) async => http.Response(
          jsonEncode({
            'data': [
              {'id': 'a', 'context_length': 1000},
              {'id': 'b', 'context_window': 2000},
              {'id': 'c', 'max_context_length': 3000},
              {'id': 'd'},
              {'id': 'e', 'context_length': 'many'},
              {'noid': true},
            ],
          }),
          200,
        ),
      );

      final result = await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: timeout,
      );

      final models = (result as CheckOk).models;
      expect(models.map((m) => m.id), ['a', 'b', 'c', 'd', 'e']);
      expect(models.map((m) => m.contextWindow), [
        1000,
        2000,
        3000,
        null,
        null,
      ]);
    });

    for (final body in const ['not json', '[]', '{"data":"x"}', '{}']) {
      test('200 с телом «$body» — badResponse', () async {
        final check = checkOver((request) async => http.Response(body, 200));

        final result = await check.listModels(
          'openai-compatible',
          Uri.parse('https://h/v1'),
          key,
          timeout: timeout,
        );

        expect(
          (result as CheckFailure).failure.kind,
          ProviderCheckFailureKind.badResponse,
        );
      });
    }
  });

  group('виды отказа', () {
    const cases = <int, ProviderCheckFailureKind>{
      401: ProviderCheckFailureKind.unauthorized,
      403: ProviderCheckFailureKind.unauthorized,
      404: ProviderCheckFailureKind.notFound,
      302: ProviderCheckFailureKind.badResponse,
      429: ProviderCheckFailureKind.badResponse,
      500: ProviderCheckFailureKind.badResponse,
    };
    cases.forEach((status, kind) {
      test('HTTP $status → ${kind.name} со статусом', () async {
        final check = checkOver(
          (request) async => http.Response(
            'body',
            status,
            headers: {'location': 'https://elsewhere.invalid/'},
          ),
        );

        final result = await check.listModels(
          'openai-compatible',
          Uri.parse('https://h/v1'),
          key,
          timeout: timeout,
        );

        final failure = (result as CheckFailure).failure;
        expect(failure.kind, kind);
        expect(failure.statusCode, status);
      });
    });

    test('ошибка соединения → unreachable', () async {
      final check = checkOver(
        (request) async =>
            throw http.ClientException('Connection refused', request.url),
      );

      final result = await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: timeout,
      );

      expect(
        (result as CheckFailure).failure.kind,
        ProviderCheckFailureKind.unreachable,
      );
    });

    test('вид ошибки определяет классификатор, а не текст', () async {
      // Текст похож на TLS, но классификатор не вызывается для текста: без
      // классификатора любая ошибка клиента — unreachable.
      final plain = checkOver(
        (request) async => throw http.ClientException(
          'HandshakeException: CERTIFICATE_VERIFY_FAILED',
          request.url,
        ),
      );
      final seen = <Object>[];
      final classified = HttpProviderCheck(
        () => MockClient((request) async => throw StateError('tls')),
        logger: logger,
        classifier: (error) {
          seen.add(error);
          return error is StateError ? ProviderCheckFailureKind.tlsError : null;
        },
      );

      final a = await plain.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: timeout,
      );
      final b = await classified.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: timeout,
      );

      expect(
        (a as CheckFailure).failure.kind,
        ProviderCheckFailureKind.unreachable,
      );
      expect(
        (b as CheckFailure).failure.kind,
        ProviderCheckFailureKind.tlsError,
      );
      expect(seen.single, isA<StateError>());
    });

    test('таймаут → timeout', () async {
      final never = Completer<http.Response>();
      final check = checkOver((request) => never.future);

      final result = await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: const Duration(milliseconds: 1),
      );

      expect(
        (result as CheckFailure).failure.kind,
        ProviderCheckFailureKind.timeout,
      );
    });
  });

  group('закрытие соединения', () {
    test('по таймауту клиент попытки закрывается', () async {
      final clients = <_RecordingClient>[];
      final check = HttpProviderCheck(() {
        final client = _RecordingClient(Completer<http.StreamedResponse>());
        clients.add(client);
        return client;
      }, logger: logger);

      await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: const Duration(milliseconds: 1),
      );

      expect(clients.single.closeCalls, 1);
    });

    test('после успеха и после отказа клиент тоже закрыт', () async {
      final clients = <_RecordingClient>[];
      var status = 200;
      final check = HttpProviderCheck(() {
        final completer = Completer<http.StreamedResponse>()
          ..complete(
            http.StreamedResponse(
              Stream.value(utf8.encode('{"data":[]}')),
              status,
            ),
          );
        final client = _RecordingClient(completer);
        clients.add(client);
        return client;
      }, logger: logger);

      await check.listModels(
        'anthropic',
        Uri.parse('https://a'),
        key,
        timeout: timeout,
      );
      status = 401;
      await check.listModels(
        'anthropic',
        Uri.parse('https://a'),
        key,
        timeout: timeout,
      );

      expect(clients.map((c) => c.closeCalls), [1, 1]);
      // Каждая проверка — свой клиент: повтор не наследует состояние попытки.
      expect(clients, hasLength(2));
    });
  });

  group('отмена (закрытие страницы во время Check)', () {
    test('отмена до ответа закрывает клиент и не ждёт таймаута', () async {
      final client = _RecordingClient(Completer<http.StreamedResponse>());
      final check = HttpProviderCheck(() => client, logger: logger);
      final source = CancelTokenSource();

      final pending = check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: const Duration(minutes: 5),
        cancel: source.token,
      );
      await client.sent.future;
      source.cancel();
      final result = await pending;

      expect(result, isA<CheckCancelled>());
      expect(client.closeCalls, 1);
      expect(everything(result), isNot(contains(leak)));
    });

    test('уже отменённый токен — запрос не уходит', () async {
      final clients = <_RecordingClient>[];
      final check = HttpProviderCheck(() {
        final client = _RecordingClient(Completer<http.StreamedResponse>());
        clients.add(client);
        return client;
      });
      final source = CancelTokenSource()..cancel();

      final result = await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: timeout,
        cancel: source.token,
      );

      expect(result, isA<CheckCancelled>());
      // Запрос не уходит: клиент даже не создаётся.
      expect(clients, isEmpty);
    });

    test('отмена после ответа ничего не меняет', () async {
      final completer = Completer<http.StreamedResponse>()
        ..complete(
          http.StreamedResponse(
            Stream.value(utf8.encode('{"data":[{"id":"m"}]}')),
            200,
          ),
        );
      final client = _RecordingClient(completer);
      final check = HttpProviderCheck(() => client);
      final source = CancelTokenSource();

      final result = await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: timeout,
        cancel: source.token,
      );
      source.cancel();
      await Future<void>.value();

      expect((result as CheckOk).models.single.id, 'm');
      expect(client.closeCalls, 1);
    });
  });

  group('тело ошибки и ключ скрыты (SETUP-1)', () {
    test('401 с телом, цитирующим ключ', () async {
      final check = checkOver(
        (request) async => http.Response('invalid key $leak', 401),
      );

      final result = await check.listModels(
        'openai-compatible',
        Uri.parse('https://user:pw@h:8443/v1?token=$leak'),
        key,
        timeout: timeout,
      );

      expect(
        (result as CheckFailure).failure.kind,
        ProviderCheckFailureKind.unauthorized,
      );
      expect(everything(result), isNot(contains(leak)));
      expect(everything(result), isNot(contains('invalid key')));
    });

    test('исключение клиента с ключом в тексте', () async {
      final check = checkOver(
        (request) async =>
            throw http.ClientException('failed with $leak', request.url),
      );

      final result = await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        key,
        timeout: timeout,
      );

      expect(everything(result), isNot(contains(leak)));
    });

    test('в журнале только scheme://host:port', () async {
      final check = checkOver(
        (request) async => http.Response('{"data":[]}', 200),
      );

      await check.listModels(
        'openai-compatible',
        Uri.parse('https://user:pw@h.example/v1/secret-path?token=$leak'),
        key,
        timeout: timeout,
      );

      final text = everything('');
      expect(text, contains('https://h.example:443'));
      expect(text, isNot(contains('secret-path')));
      expect(text, isNot(contains('token')));
      expect(text, isNot(contains('user')));
      expect(text, isNot(contains(leak)));
    });

    test('SecretValue не печатает значение', () {
      expect('$key', '***');
      expect(jsonEncode({'k': key}), '{"k":"***"}');
      expect(key.reveal(), leak);
    });
  });

  group('настоящий IOClient на loopback (ioProviderCheck)', () {
    late List<HttpServer> servers;

    setUp(() => servers = []);
    tearDown(() async {
      for (final server in servers) {
        await server.close(force: true);
      }
    });

    Future<HttpServer> serve(
      FutureOr<void> Function(HttpRequest request) handler,
    ) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      server.listen(handler);
      return server;
    }

    Uri base(HttpServer server, [String path = '/v1']) =>
        Uri.parse('http://127.0.0.1:${server.port}$path');

    test('200 и тело 401 через настоящий клиент', () async {
      final seen = <String?>[];
      final server = await serve((request) async {
        seen.add(request.headers.value('authorization'));
        if (request.headers.value('authorization') == 'Bearer $leak') {
          request.response
            ..statusCode = 200
            ..write('{"data":[{"id":"m","context_length":4096}]}');
        } else {
          request.response
            ..statusCode = 401
            ..write('invalid key $leak');
        }
        await request.response.close();
      });

      final ok = await ioProviderCheck().listModels(
        'openai-compatible',
        base(server),
        key,
        timeout: timeout,
      );
      final denied = await ioProviderCheck().listModels(
        'openai-compatible',
        base(server),
        SecretValue('wrong'),
        timeout: timeout,
      );

      expect((ok as CheckOk).models.single.contextWindow, 4096);
      expect(
        (denied as CheckFailure).failure.kind,
        ProviderCheckFailureKind.unauthorized,
      );
      expect('$denied ${denied.failure.message}', isNot(contains(leak)));
    });

    test('порт закрыт → unreachable', () async {
      final server = await serve((request) {});
      final uri = base(server);
      await server.close(force: true);

      final result = await ioProviderCheck().listModels(
        'openai-compatible',
        uri,
        key,
        timeout: timeout,
      );

      expect(
        (result as CheckFailure).failure.kind,
        ProviderCheckFailureKind.unreachable,
      );
    });

    test('https к серверу без TLS → tlsError', () async {
      final server = await serve((request) {});

      final result = await ioProviderCheck().listModels(
        'openai-compatible',
        Uri.parse('https://127.0.0.1:${server.port}/v1'),
        key,
        timeout: timeout,
      );

      expect(
        (result as CheckFailure).failure.kind,
        ProviderCheckFailureKind.tlsError,
      );
    });

    test('отмена закрывает соединение, таймаут не ждём', () async {
      final closed = Completer<void>();
      final received = Completer<void>();
      final server = await serve((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.listen((_) {}, onDone: closed.complete, onError: (_) {});
        received.complete();
      });
      final source = CancelTokenSource();

      final pending = ioProviderCheck().listModels(
        'openai-compatible',
        base(server),
        key,
        timeout: const Duration(minutes: 5),
        cancel: source.token,
      );
      await received.future;
      source.cancel();
      final result = await pending;

      expect(result, isA<CheckCancelled>());
      await closed.future.timeout(const Duration(seconds: 5));
    });

    test('таймаут закрывает соединение со стороны клиента', () async {
      final closed = Completer<void>();
      final server = await serve((request) async {
        // Ответа не будет: ждём, пока клиент оборвёт соединение.
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.listen((_) {}, onDone: closed.complete, onError: (_) {});
      });

      final result = await ioProviderCheck().listModels(
        'openai-compatible',
        base(server),
        key,
        timeout: const Duration(milliseconds: 200),
      );

      expect(
        (result as CheckFailure).failure.kind,
        ProviderCheckFailureKind.timeout,
      );
      await closed.future.timeout(const Duration(seconds: 5));
    });
  });
}

/// Клиент, который считает `close()` и отвечает заранее заданным ответом.
final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._response);

  final Completer<http.StreamedResponse> _response;
  int closeCalls = 0;

  /// Завершается, когда запрос дошёл до клиента.
  final sent = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent.complete();
    return _response.future;
  }

  @override
  void close() => closeCalls++;
}
