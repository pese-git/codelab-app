import 'dart:async';
import 'dart:io';

import 'package:acp_transports/acp_transports.dart';
import 'package:test/test.dart';

void main() {
  test('exports transport and protocol markers', () {
    expect(acpTransportsPackageName, 'acp_transports');
    expect(acpProtocolPackageName, 'acp_protocol');
  });

  test('AcpTransport exposes inbound stream and outbound send port', () async {
    final transport = _BoundaryTransport();
    addTearDown(transport.close);

    final inbound = transport.inbound.first;
    const message = JsonRpcMessage.notification(
      method: 'session/update',
      params: {'sessionId': 'session-1'},
    );

    transport.emitInbound(message);

    expect(await inbound, message);

    final outbound = JsonRpcMessage.request(
      id: const JsonRpcId.integer(1),
      method: 'initialize',
      params: {'protocolVersion': 1},
    );

    await transport.send(outbound);

    expect(transport.sentMessages, [outbound]);
  });

  test(
    'AcpTransport exposes lifecycle, diagnostics, failures, and close',
    () async {
      final transport = _BoundaryTransport();
      addTearDown(transport.close);

      final events = <AcpTransportEvent>[];
      final subscription = transport.events.listen(events.add);
      addTearDown(subscription.cancel);

      await transport.start();

      transport.emitDiagnostic(
        const AcpTransportEvent.diagnostic(
          message: 'agent stderr line',
          severity: AcpTransportDiagnosticSeverity.warning,
          source: 'stderr',
        ),
      );
      transport.emitFailure(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'agent exited unexpectedly',
        ),
      );

      await transport.close();
      await pumpEventQueue();
      await subscription.cancel();

      expect(transport.state, AcpTransportState.closed);
      expect(
        events.whereType<AcpTransportStateChanged>().map(
          (event) => event.state,
        ),
        [
          AcpTransportState.connecting,
          AcpTransportState.connected,
          AcpTransportState.closing,
          AcpTransportState.closed,
        ],
      );
      expect(
        events.whereType<AcpTransportDiagnostic>().single,
        isA<AcpTransportDiagnostic>()
            .having((event) => event.message, 'message', 'agent stderr line')
            .having(
              (event) => event.severity,
              'severity',
              AcpTransportDiagnosticSeverity.warning,
            )
            .having((event) => event.source, 'source', 'stderr'),
      );
      expect(
        events.whereType<AcpTransportFailure>().single.error,
        isA<AcpTransportException>()
            .having(
              (error) => error.code,
              'code',
              AcpTransportErrorCode.disconnected,
            )
            .having(
              (error) => error.message,
              'message',
              'agent exited unexpectedly',
            ),
      );
    },
  );

  test('StdioAcpTransport exchanges JSON-RPC over stdout and stdin', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'stdio_acp_transport_test_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final agent = File('${tempDir.path}/test_agent.dart');
    await agent.writeAsString('''
import 'dart:convert';
import 'dart:io';

void main() {
  stderr.writeln('agent ready');
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final message = jsonDecode(line) as Map<String, Object?>;
    stdout.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': message['id'],
      'result': {'ok': true, 'method': message['method']},
    }));
  });
}
''');

    final transport = StdioAcpTransport(
      StdioAcpTransportConfig(
        command: _dartExecutable(),
        args: [agent.path],
        cwd: tempDir.path,
        env: const {'TEST_AGENT_ENV': 'enabled'},
      ),
    );
    addTearDown(transport.close);

    final events = <AcpTransportEvent>[];
    final subscription = transport.events.listen(events.add);
    addTearDown(subscription.cancel);
    final diagnostic = transport.events
        .where((event) => event is AcpTransportDiagnostic)
        .cast<AcpTransportDiagnostic>()
        .firstWhere((event) => event.message == 'agent ready');

    await transport.start();

    final inbound = transport.inbound.first;
    await transport.send(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(7),
        method: 'initialize',
        params: {'protocolVersion': 1},
      ),
    );

    expect(
      await inbound,
      JsonRpcMessage.response(
        id: const JsonRpcId.integer(7),
        result: {'ok': true, 'method': 'initialize'},
      ),
    );

    expect(
      await diagnostic,
      isA<AcpTransportDiagnostic>()
          .having((event) => event.message, 'message', 'agent ready')
          .having((event) => event.source, 'source', 'stderr'),
    );

    expect(transport.state, AcpTransportState.connected);
    expect(
      events.whereType<AcpTransportStateChanged>().map((event) => event.state),
      containsAllInOrder([
        AcpTransportState.connecting,
        AcpTransportState.connected,
      ]),
    );
  });
}

String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dart = File(
      '$flutterRoot/bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
    );
    if (dart.existsSync()) {
      return dart.path;
    }
  }

  final resolvedExecutable = File(Platform.resolvedExecutable);
  if (resolvedExecutable.uri.pathSegments.last == 'dart') {
    return resolvedExecutable.path;
  }

  for (
    var directory = Directory.current;
    directory.parent.path != directory.path;
    directory = directory.parent
  ) {
    final dart = File(
      '${directory.path}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
    );
    if (dart.existsSync()) {
      return dart.path;
    }
  }

  throw StateError('Unable to locate Dart executable for stdio test agent.');
}

final class _BoundaryTransport implements AcpTransport {
  final _inboundController = StreamController<JsonRpcMessage>();
  final _eventController = StreamController<AcpTransportEvent>.broadcast();
  final sentMessages = <JsonRpcMessage>[];

  var _state = AcpTransportState.idle;
  var _closed = false;

  @override
  Stream<JsonRpcMessage> get inbound => _inboundController.stream;

  @override
  Stream<AcpTransportEvent> get events => _eventController.stream;

  @override
  AcpTransportState get state => _state;

  @override
  Future<void> start() async {
    _setState(AcpTransportState.connecting);
    _setState(AcpTransportState.connected);
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (_closed) {
      throw const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'transport is closed',
      );
    }

    sentMessages.add(message);
  }

  void emitInbound(JsonRpcMessage message) {
    _inboundController.add(message);
  }

  void emitDiagnostic(AcpTransportEvent diagnostic) {
    _eventController.add(diagnostic);
  }

  void emitFailure(AcpTransportException error) {
    _eventController.add(AcpTransportEvent.failure(error));
  }

  @override
  Future<void> close({Duration? timeout}) async {
    if (_closed) {
      return;
    }

    _setState(AcpTransportState.closing);
    _closed = true;
    _setState(AcpTransportState.closed);
    unawaited(_inboundController.close());
    unawaited(_eventController.close());
  }

  void _setState(AcpTransportState state) {
    _state = state;
    _eventController.add(AcpTransportEvent.stateChanged(state));
  }
}
