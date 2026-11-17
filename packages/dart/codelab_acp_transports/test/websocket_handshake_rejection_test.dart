// Отказ рукопожатия WebSocket сохраняет HTTP-статус в типизированном виде
// (task 3.3a change `add-app-settings-shell`; design.md D12). Настоящий
// HttpServer на loopback, только фиктивные токены.

import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer http;
  var status = HttpStatus.unauthorized;

  setUp(() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) {
      request.response
        ..statusCode = status
        ..close();
    });
  });

  tearDown(() => http.close(force: true));

  for (final code in [HttpStatus.unauthorized, HttpStatus.forbidden]) {
    test('a $code handshake reports the numeric status in the cause', () async {
      status = code;
      final transport = WebSocketAcpTransport(
        WebSocketAcpTransportConfig(
          uri: Uri.parse('ws://127.0.0.1:${http.port}/acp'),
          token: 'fake-secret-token',
        ),
      );
      final failures = <AcpTransportException>[];
      transport.events.listen((event) {
        if (event is AcpTransportFailure) failures.add(event.error);
      });

      Object? thrown;
      try {
        await transport.start();
      } on Object catch (error) {
        thrown = error;
      }

      // start() по-прежнему пробрасывает исходную ошибку, а событие сбоя
      // несёт обёртку startFailed с типизированной причиной.
      expect(thrown, isA<AcpWebSocketHandshakeRejected>());
      expect((thrown! as AcpWebSocketHandshakeRejected).statusCode, code);
      final error = failures.single;
      expect(error.code, AcpTransportErrorCode.startFailed);
      expect((error.cause! as AcpWebSocketHandshakeRejected).statusCode, code);
      expect(error.toString(), isNot(contains('fake-secret-token')));
      expect(error.message, isNot(contains('fake-secret-token')));
      expect(thrown.toString(), isNot(contains('fake-secret-token')));
      expect(transport.state, AcpTransportState.failed);
      await transport.close();
    });
  }

  test('the authorization header still reaches the server', () async {
    await http.close(force: true);
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? seen;
    http.listen((request) async {
      seen = request.headers.value(HttpHeaders.authorizationHeader);
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.close();
    });
    final transport = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(
        uri: Uri.parse('ws://127.0.0.1:${http.port}/acp'),
        token: 'fake-secret-token',
      ),
    );

    await transport.start();

    expect(seen, 'Bearer fake-secret-token');
    await transport.close();
  });

  test(
    'a redirect to another origin never carries the authorization header',
    () async {
      // Редирект не должен уносить заголовок авторизации на другой хост.
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => target.close(force: true));
      final targetAuth = <String?>[];
      target.listen((request) {
        targetAuth.add(request.headers.value(HttpHeaders.authorizationHeader));
        request.response.close();
      });
      await http.close(force: true);
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((request) {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${target.port}/acp',
          )
          ..close();
      });
      final transport = WebSocketAcpTransport(
        WebSocketAcpTransportConfig(
          uri: Uri.parse('ws://127.0.0.1:${http.port}/acp'),
          token: 'fake-secret-token',
        ),
      );

      Object? thrown;
      try {
        await transport.start();
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<AcpWebSocketHandshakeRejected>());
      // SDK не копирует Authorization на другой origin; хост B вправе получить
      // запрос, но только без токена; B отвечает 200, не 101 — отказ рукопожатия.
      expect(targetAuth.whereType<String>(), isEmpty);
      expect((thrown! as AcpWebSocketHandshakeRejected).statusCode, 200);
      await transport.close();
    },
  );

  test('close() during a pending handshake closes the late socket', () async {
    await http.close(force: true);
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = Completer<HttpRequest>();
    final closedByClient = Completer<void>();
    http.listen(requested.complete);
    final transport = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(
        uri: Uri.parse('ws://127.0.0.1:${http.port}/acp'),
      ),
    );
    final started = transport.start().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    final request = await requested.future;

    await transport.close();
    // Сервер завершает рукопожатие только после close() клиента.
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((_) {}, onDone: closedByClient.complete);

    await closedByClient.future.timeout(const Duration(seconds: 5));
    await started;
    expect(transport.state, AcpTransportState.closed);
  });

  test('an invalid header value is rejected without leaking it', () async {
    const marker = 'sk-test-leak-0123456789';
    final transport = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(
        uri: Uri.parse('ws://127.0.0.1:${http.port}/acp'),
        token: 'abc\n$marker',
      ),
    );
    final failures = <AcpTransportException>[];
    transport.events.listen((event) {
      if (event is AcpTransportFailure) failures.add(event.error);
    });

    Object? thrown;
    try {
      await transport.start();
    } on Object catch (error) {
      thrown = error;
    }

    expect(thrown, isA<AcpTransportException>());
    expect(thrown.toString(), isNot(contains(marker)));
    final error = failures.single;
    expect(error.code, AcpTransportErrorCode.startFailed);
    expect(error.cause, isNull);
    expect('${error.message} $error', isNot(contains(marker)));
    await transport.close();
  });

  test('a refused connection fails start() without hanging', () async {
    final port = http.port;
    await http.close(force: true);
    final transport = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(uri: Uri.parse('ws://127.0.0.1:$port/acp')),
    );

    await expectLater(
      transport.start().timeout(const Duration(seconds: 5)),
      throwsA(isA<SocketException>()),
    );
    expect(transport.state, AcpTransportState.failed);
    await transport.close();
  });
}
