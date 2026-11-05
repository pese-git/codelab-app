// Классификация сбоев проверки профиля (task 3.3 change
// `add-app-settings-shell`; spec acp-client-kit «IO-адаптеры клиента»,
// «Проверка профиля без сессии»; design.md, D12). Настоящие процессы и
// WebSocket-сервер на loopback, Dart VM.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart'
    show writeCodelabCompatibleStdioAgent;
import 'package:codelab_acp_transports/codelab_acp_transports.dart'
    show AcpTransport;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:test/test.dart';

ProfileProbe _probe() => ProfileProbe(
  resolvers: [ioTransportResolver(secrets: const ProfileSecretSource({}))],
  classifier: classifyProbeFailure,
);

void main() {
  test('a missing command is CommandNotFound', () async {
    final outcome = await _probe().probe(
      const StdioProfile(id: 'x', label: 'X', command: '/nonexistent/agent'),
    );

    expect(outcome, isA<CommandNotFound>());
  });

  test('a closed port is Unreachable.connectionRefused', () async {
    // Порт занимаем и сразу освобождаем: на нём никто не слушает.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);

    final outcome = await _probe().probe(
      WebSocketProfile(
        id: 'x',
        label: 'X',
        uri: Uri.parse('ws://127.0.0.1:$port'),
      ),
    );

    expect(outcome, isA<Unreachable>());
    expect(
      (outcome! as Unreachable).reason,
      UnreachableReason.connectionRefused,
    );
  });

  group('typed errno classification (no network)', () {
    // Одна известная пара на платформу: тест не копирует таблицу прода, а
    // сверяет её с независимо известными значениями ОС.
    final known = switch (Platform.operatingSystem) {
      'macos' || 'ios' => (refused: 61, hostNotFound: 8),
      'linux' || 'android' => (refused: 111, hostNotFound: -2),
      'windows' => (refused: 10061, hostNotFound: 11001),
      _ => null,
    };

    Future<ProfileProbeOutcome?> probeThrowing(Object error) => ProfileProbe(
      resolvers: [_ThrowingResolver(error)],
      classifier: classifyProbeFailure,
    ).probe(WebSocketProfile(id: 'x', label: 'X', uri: Uri.parse('ws://h:1')));

    test('host-not-found errno is Unreachable.hostNotFound', () async {
      final outcome = await probeThrowing(
        SocketException('x', osError: OSError('x', known!.hostNotFound)),
      );

      expect((outcome! as Unreachable).reason, UnreachableReason.hostNotFound);
    }, skip: known == null ? 'platform without an errno table' : false);

    test('ECONNREFUSED errno is Unreachable.connectionRefused', () async {
      final outcome = await probeThrowing(
        SocketException('x', osError: OSError('x', known!.refused)),
      );

      expect(
        (outcome! as Unreachable).reason,
        UnreachableReason.connectionRefused,
      );
    }, skip: known == null ? 'platform without an errno table' : false);

    test('an unfamiliar errno is Unreachable.unknown', () async {
      final error = SocketException('x', osError: OSError('x', 424242));

      expect(classifyProbeFailure(error), isNull);
      final outcome = await probeThrowing(error);
      expect((outcome! as Unreachable).reason, UnreachableReason.unknown);
    });
  });

  test('a TLS handshake against a plain HTTP server is tlsFailed', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) => request.response.close());

    final outcome = await _probe().probe(
      WebSocketProfile(
        id: 'x',
        label: 'X',
        uri: Uri.parse('wss://127.0.0.1:${server.port}'),
      ),
    );

    expect(outcome, isA<Unreachable>());
    expect((outcome! as Unreachable).reason, UnreachableReason.tlsFailed);
  });

  for (final status in [HttpStatus.unauthorized, HttpStatus.forbidden]) {
    test(
      'a $status handshake is Unauthorized from the typed status (task 3.3a), '
      'never guessed from text',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) {
          request.response
            ..statusCode = status
            ..close();
        });

        final outcome = await _probe().probe(
          WebSocketProfile(
            id: 'x',
            label: 'X',
            uri: Uri.parse('ws://127.0.0.1:${server.port}'),
          ),
        );

        expect(outcome, isA<Unauthorized>());
      },
    );
  }

  test('a 500 handshake is Unreachable.httpStatus with statusCode', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    });

    final outcome = await _probe().probe(
      WebSocketProfile(
        id: 'x',
        label: 'X',
        uri: Uri.parse('ws://127.0.0.1:${server.port}'),
      ),
    );

    expect(outcome, isA<Unreachable>());
    final unreachable = outcome! as Unreachable;
    expect(unreachable.reason, UnreachableReason.httpStatus);
    expect(unreachable.statusCode, HttpStatus.internalServerError);
  });

  test('a real agent process answers initialize: Reachable', () async {
    final tmp = Directory.systemTemp.createTempSync('probe_io_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final agent = await writeCodelabCompatibleStdioAgent(tmp);

    final outcome = await _probe().probe(
      StdioProfile(
        id: 'x',
        label: 'X',
        command: Platform.resolvedExecutable,
        args: [agent.path, 'serve', '--stdio'],
      ),
      projectDirectory: tmp.path,
    );

    expect(outcome, isA<Reachable>());
  });

  test('message text never influences the classification', () async {
    final error = StateError('connection refused 401');

    expect(classifyProbeFailure(error), isNull);
    final outcome = await ProfileProbe(
      resolvers: [_ThrowingResolver(error)],
      classifier: classifyProbeFailure,
    ).probe(WebSocketProfile(id: 'x', label: 'X', uri: Uri.parse('ws://h:1')));
    expect((outcome! as Unreachable).reason, UnreachableReason.unknown);
  });
}

/// Резолвер, который при открытии бросает заданную ошибку: даёт классификатору
/// построенную ошибку без сети.
final class _ThrowingResolver implements TransportResolver {
  _ThrowingResolver(this.error);

  final Object error;

  @override
  bool supports(ConnectionProfile profile) => true;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) => Future.error(error);
}
