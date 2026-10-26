// Тесты резолвера настоящих транспортов (tasks 5.3; spec acp-client-kit
// «IO-адаптеры клиента», «Профили и резолверы транспорта»): процесс агента и
// WebSocket-сервер на loopback, Dart VM.

import 'dart:async';
import 'dart:io';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_client_io/acp_client_io.dart';
import 'package:acp_client_kit/acp_client_kit.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart'
    show writeCodelabCompatibleStdioAgent;
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_transports/io.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late AcpClientApplication application;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('acp_client_io_');
    application = AcpClientApplication(transport: _IdleTransport());
  });
  tearDown(() async {
    await application.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('a stdio profile starts the agent process and connects', () async {
    final agent = await writeCodelabCompatibleStdioAgent(tmp);
    final workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [ioTransportResolver()],
    );
    addTearDown(workspace.dispose);

    await workspace.connect(
      StdioProfile(
        id: 'local',
        label: 'Local agent',
        command: _dartExecutable(),
        args: [agent.path, 'serve', '--stdio'],
        runInProjectDirectory: true,
      ),
      projectDirectory: tmp.path,
    );

    expect(workspace.current.connection, const ConnectionView.connected());
  });

  test('a WebSocket profile sends the bearer token from the secret '
      'source', () async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => http.close(force: true));
    final authorization = Completer<String?>();
    http.listen((request) async {
      authorization.complete(request.headers.value('authorization'));
      final server = WebSocketServerAcpTransport(
        await WebSocketTransformer.upgrade(request),
      );
      await server.start();
      server.inbound.listen((message) {
        if (message case JsonRpcRequest(:final id, method: initializeMethod)) {
          unawaited(
            server.send(
              encodeAcpResponse(
                id: id,
                method: initializeMethod,
                result: const InitializeResponse(
                  protocolVersion: ProtocolVersion(1),
                ),
              ),
            ),
          );
        }
      });
    });
    final secrets = InMemorySecretSource()..write('ws', 's3cr3t');
    final workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [ioTransportResolver(secrets: secrets)],
    );
    addTearDown(workspace.dispose);

    await workspace.connect(
      WebSocketProfile(
        id: 'remote',
        label: 'Remote agent',
        uri: Uri.parse('ws://127.0.0.1:${http.port}/acp'),
        tokenRef: 'ws',
      ),
      projectDirectory: tmp.path,
    );

    expect(await authorization.future, 'Bearer s3cr3t');
    expect(workspace.current.connection, const ConnectionView.connected());
  });
}

/// Путь к `dart`: под `flutter test` (`melos run test`)
/// `Platform.resolvedExecutable` — это `flutter_tester`, а агенту из
/// `acp_testing` нужен Dart VM; поэтому сначала берётся SDK из `FLUTTER_ROOT`.
String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dart = File('$flutterRoot/bin/cache/dart-sdk/bin/dart');
    if (dart.existsSync()) {
      return dart.path;
    }
  }
  return Platform.resolvedExecutable;
}

/// Начальный транспорт `AcpClientApplication`: в тестах его сразу заменяет
/// транспорт резолвера.
final class _IdleTransport implements AcpTransport {
  final _inbound = StreamController<JsonRpcMessage>.broadcast();
  final _events = StreamController<AcpTransportEvent>.broadcast();

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => AcpTransportState.idle;

  @override
  Future<void> start() async {}

  @override
  Future<void> send(JsonRpcMessage message) async {}

  @override
  Future<void> close({Duration? timeout}) async {
    await _inbound.close();
    await _events.close();
  }
}
