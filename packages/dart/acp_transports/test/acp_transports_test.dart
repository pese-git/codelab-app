import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart'
    show writeCodelabCompatibleStdioAgent;
import 'package:acp_transports/acp_transports.dart'
    hide JsonRpcId, JsonRpcMessage, acpProtocolPackageName;
import 'package:test/test.dart';

void main() {
  test('exports transport and protocol markers', () {
    expect(acpTransportsPackageName, 'acp_transports');
    expect(acpProtocolPackageName, 'acp_protocol');
  });

  test('exports editable Codelab Agent stdio profile', () {
    expect(codelabAgentStdioProfile.name, 'Codelab Agent');
    expect(codelabAgentStdioProfile.type, 'custom');
    expect(codelabAgentStdioProfile.command, 'codelab');
    expect(codelabAgentStdioProfile.args, ['serve', '--stdio']);
    expect(codelabAgentStdioProfile.env, {'CODELAB_LOG_LEVEL': 'DEBUG'});
    expect(codelabAgentStdioProfile.cwd, isNull);

    final edited = codelabAgentStdioProfile.copyWith(
      command: '/opt/homebrew/bin/codelab',
      cwd: '/workspace',
      env: {...codelabAgentStdioProfile.env, 'CODELAB_AGENT_PROFILE': 'local'},
    );

    expect(edited.name, 'Codelab Agent');
    expect(edited.type, 'custom');
    expect(edited.command, '/opt/homebrew/bin/codelab');
    expect(edited.args, ['serve', '--stdio']);
    expect(edited.cwd, '/workspace');
    expect(edited.env, {
      'CODELAB_LOG_LEVEL': 'DEBUG',
      'CODELAB_AGENT_PROFILE': 'local',
    });
  });

  test('Codelab Agent profile creates stdio transport config', () {
    expect(
      codelabAgentStdioProfile.toTransportConfig(),
      const StdioAcpTransportConfig(
        command: 'codelab',
        args: ['serve', '--stdio'],
        env: {'CODELAB_LOG_LEVEL': 'DEBUG'},
      ),
    );
  });

  test(
    'StdioAcpTransport completes codelab serve --stdio compatible flow',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'codelab_compatible_stdio_flow_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final agent = await writeCodelabCompatibleStdioAgent(tempDir);
      final transport = StdioAcpTransport(
        StdioAcpTransportConfig(
          command: _dartExecutable(),
          args: [agent.path, ...codelabAgentStdioProfile.args],
          cwd: tempDir.path,
          env: codelabAgentStdioProfile.env,
        ),
      );
      addTearDown(transport.close);

      final diagnostic = transport.events
          .where((event) => event is AcpTransportDiagnostic)
          .cast<AcpTransportDiagnostic>()
          .firstWhere(
            (event) => event.message == 'codelab-compatible test agent ready',
          );

      await transport.start();

      final initializeResponse = _responseWithId(
        transport,
        const JsonRpcId.integer(1),
      );
      await transport.send(
        encodeAcpRequest(
          id: const JsonRpcId.integer(1),
          method: initializeMethod,
          params: const InitializeRequest(
            protocolVersion: ProtocolVersion(1),
            clientInfo: Implementation(
              name: 'codelab-transport-test',
              version: '0.1.0',
            ),
          ),
        ),
      );

      final initialized =
          decodeAcpResponseResult(
                method: initializeMethod,
                response: await initializeResponse,
              )
              as InitializeResponse;
      expect(initialized.protocolVersion, const ProtocolVersion(1));
      expect(initialized.agentInfo?.name, 'codelab-compatible-test-agent');

      final newSessionResponse = _responseWithId(
        transport,
        const JsonRpcId.integer(2),
      );
      await transport.send(
        encodeAcpRequest(
          id: const JsonRpcId.integer(2),
          method: sessionNewMethod,
          params: NewSessionRequest(cwd: tempDir.path, mcpServers: const []),
        ),
      );

      final session =
          decodeAcpResponseResult(
                method: sessionNewMethod,
                response: await newSessionResponse,
              )
              as NewSessionResponse;
      expect(session.sessionId, const SessionId('codelab-test-session'));

      final promptUpdate = transport.inbound
          .where((message) => message is JsonRpcNotification)
          .cast<JsonRpcNotification>()
          .firstWhere((message) => message.method == sessionUpdateMethod);
      final promptResponse = _responseWithId(
        transport,
        const JsonRpcId.integer(3),
      );
      await transport.send(
        encodeAcpRequest(
          id: const JsonRpcId.integer(3),
          method: sessionPromptMethod,
          params: PromptRequest(
            sessionId: session.sessionId,
            prompt: const [ContentBlock.text(text: 'ping')],
          ),
        ),
      );

      final update =
          decodeAcpNotificationParams(await promptUpdate)
              as SessionNotification;
      expect(update.sessionId, session.sessionId);
      expect(
        update.update,
        isA<AgentMessageChunk>().having(
          (chunk) => chunk.content,
          'content',
          isA<TextContent>().having(
            (content) => content.text,
            'text',
            'hello from compatible stdio agent',
          ),
        ),
      );

      final prompted =
          decodeAcpResponseResult(
                method: sessionPromptMethod,
                response: await promptResponse,
              )
              as PromptResponse;
      expect(prompted.stopReason, StopReason.endTurn);
      expect(
        await diagnostic.timeout(const Duration(seconds: 5)),
        isA<AcpTransportDiagnostic>().having(
          (event) => event.source,
          'source',
          'stderr',
        ),
      );
      expect(transport.state, AcpTransportState.connected);
    },
  );

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

  test('StdioAcpTransport reports unexpected process exit', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'stdio_acp_transport_exit_test_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final agent = File('${tempDir.path}/exit_agent.dart');
    await agent.writeAsString('''
import 'dart:io';

void main() {
  stderr.writeln('agent exiting');
  exitCode = 42;
}
''');

    final transport = StdioAcpTransport(
      StdioAcpTransportConfig(command: _dartExecutable(), args: [agent.path]),
    );
    addTearDown(transport.close);

    final failure = transport.events
        .where((event) => event is AcpTransportFailure)
        .cast<AcpTransportFailure>()
        .map((event) => event.error)
        .first;

    await transport.start();

    expect(
      await failure.timeout(const Duration(seconds: 5)),
      isA<AcpTransportException>()
          .having(
            (error) => error.code,
            'code',
            AcpTransportErrorCode.disconnected,
          )
          .having(
            (error) => error.message,
            'message',
            contains('exited unexpectedly'),
          ),
    );
    expect(transport.state, AcpTransportState.failed);
  });

  test('StdioAcpTransport closes stdin and waits for graceful exit', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'stdio_acp_transport_graceful_close_test_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final marker = File('${tempDir.path}/stdin_closed.txt');
    final agent = File('${tempDir.path}/graceful_agent.dart');
    await agent.writeAsString('''
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  await stdin.transform(utf8.decoder).drain<void>();
  await File(args.single).writeAsString('closed');
}
''');

    final transport = StdioAcpTransport(
      StdioAcpTransportConfig(
        command: _dartExecutable(),
        args: [agent.path, marker.path],
      ),
    );

    await transport.start();
    await transport.close(timeout: const Duration(seconds: 5));

    expect(transport.state, AcpTransportState.closed);
    expect(await marker.readAsString(), 'closed');
  });

  test(
    'StdioAcpTransport maps invalid stdout JSON to protocol failure',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'stdio_acp_transport_invalid_json_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final agent = File('${tempDir.path}/invalid_json_agent.dart');
      await agent.writeAsString('''
import 'dart:io';

void main() {
  stdout.writeln('{not json');
}
''');

      final transport = StdioAcpTransport(
        StdioAcpTransportConfig(command: _dartExecutable(), args: [agent.path]),
      );
      addTearDown(transport.close);

      final failure = transport.events
          .where((event) => event is AcpTransportFailure)
          .cast<AcpTransportFailure>()
          .map((event) => event.error)
          .first;

      await transport.start();

      expect(
        await failure.timeout(const Duration(seconds: 5)),
        isA<AcpTransportException>()
            .having(
              (error) => error.code,
              'code',
              AcpTransportErrorCode.protocolViolation,
            )
            .having(
              (error) => error.message,
              'message',
              contains('invalid ACP JSON-RPC'),
            ),
      );
      expect(transport.state, AcpTransportState.failed);
    },
  );

  test('StdioAcpTransport keeps stderr diagnostics out of inbound', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'stdio_acp_transport_stderr_test_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final agent = File('${tempDir.path}/stderr_agent.dart');
    await agent.writeAsString('''
import 'dart:io';

void main() async {
  stderr.writeln('diagnostic only');
  await Future<void>.delayed(const Duration(milliseconds: 200));
}
''');

    final transport = StdioAcpTransport(
      StdioAcpTransportConfig(command: _dartExecutable(), args: [agent.path]),
    );
    addTearDown(transport.close);

    final diagnostic = transport.events
        .where((event) => event is AcpTransportDiagnostic)
        .cast<AcpTransportDiagnostic>()
        .firstWhere((event) => event.message == 'diagnostic only');
    var inboundCount = 0;
    final inboundSubscription = transport.inbound.listen((_) {
      inboundCount += 1;
    });
    addTearDown(inboundSubscription.cancel);

    await transport.start();

    expect(
      await diagnostic.timeout(const Duration(seconds: 5)),
      isA<AcpTransportDiagnostic>()
          .having((event) => event.message, 'message', 'diagnostic only')
          .having((event) => event.source, 'source', 'stderr'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(inboundCount, 0);
  });

  test('WebSocketAcpTransport exchanges JSON-RPC messages', () async {
    final server = await _WebSocketTestServer.start((socket, _) {
      socket.listen((data) {
        final message = jsonDecode(data as String) as Map<String, Object?>;
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': {'ok': true, 'method': message['method']},
          }),
        );
      });
    });
    addTearDown(server.close);

    final transport = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(uri: server.uri),
    );
    addTearDown(transport.close);

    final events = <AcpTransportEvent>[];
    final subscription = transport.events.listen(events.add);
    addTearDown(subscription.cancel);

    await transport.start();

    final inbound = transport.inbound.first;
    await transport.send(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(11),
        method: 'initialize',
        params: {'protocolVersion': 1},
      ),
    );

    expect(
      await inbound.timeout(const Duration(seconds: 5)),
      JsonRpcMessage.response(
        id: const JsonRpcId.integer(11),
        result: {'ok': true, 'method': 'initialize'},
      ),
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

  test(
    'WebSocketAcpTransport sends configured headers and bearer token',
    () async {
      final requestHeaders = Completer<HttpHeaders>();
      final server = await _WebSocketTestServer.start((socket, request) {
        requestHeaders.complete(request.headers);
        socket.close();
      });
      addTearDown(server.close);

      final config = WebSocketAcpTransportConfig(
        uri: server.uri,
        headers: const {'X-Agent-Workspace': 'codelab'},
        token: 'secret-token',
      );
      final transport = WebSocketAcpTransport(config);
      addTearDown(transport.close);

      await transport.start();

      final headers = await requestHeaders.future.timeout(
        const Duration(seconds: 5),
      );
      expect(headers.value('X-Agent-Workspace'), 'codelab');
      expect(headers.value('Authorization'), 'Bearer secret-token');
      expect(config.effectiveHeaders, {
        'X-Agent-Workspace': 'codelab',
        'Authorization': 'Bearer secret-token',
      });
    },
  );

  test(
    'WebSocketAcpTransport maps invalid inbound JSON to protocol failure',
    () async {
      final server = await _WebSocketTestServer.start((socket, _) {
        socket.add('{not json');
      });
      addTearDown(server.close);

      final transport = WebSocketAcpTransport(
        WebSocketAcpTransportConfig(uri: server.uri),
      );
      addTearDown(transport.close);

      final failure = transport.events
          .where((event) => event is AcpTransportFailure)
          .cast<AcpTransportFailure>()
          .map((event) => event.error)
          .first;

      await transport.start();

      expect(
        await failure.timeout(const Duration(seconds: 5)),
        isA<AcpTransportException>()
            .having(
              (error) => error.code,
              'code',
              AcpTransportErrorCode.protocolViolation,
            )
            .having(
              (error) => error.message,
              'message',
              contains('invalid ACP JSON-RPC'),
            ),
      );
      expect(transport.state, AcpTransportState.failed);
    },
  );

  test('WebSocketAcpTransport reports unexpected disconnect', () async {
    final server = await _WebSocketTestServer.start((socket, _) {
      socket.close();
    });
    addTearDown(server.close);

    final transport = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(uri: server.uri),
    );
    addTearDown(transport.close);

    final failure = transport.events
        .where((event) => event is AcpTransportFailure)
        .cast<AcpTransportFailure>()
        .map((event) => event.error)
        .first;

    await transport.start();

    expect(
      await failure.timeout(const Duration(seconds: 5)),
      isA<AcpTransportException>()
          .having(
            (error) => error.code,
            'code',
            AcpTransportErrorCode.disconnected,
          )
          .having(
            (error) => error.message,
            'message',
            contains('disconnected unexpectedly'),
          ),
    );
    expect(transport.state, AcpTransportState.failed);
  });
}

Future<JsonRpcResponse> _responseWithId(AcpTransport transport, JsonRpcId id) {
  return transport.inbound
      .where((message) => message is JsonRpcResponse)
      .cast<JsonRpcResponse>()
      .firstWhere((message) => message.id == id)
      .timeout(const Duration(seconds: 5));
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

final class _WebSocketTestServer {
  _WebSocketTestServer._(this._server);

  final HttpServer _server;

  Uri get uri => Uri(
    scheme: 'ws',
    host: InternetAddress.loopbackIPv4.host,
    port: _server.port,
  );

  static Future<_WebSocketTestServer> start(
    void Function(WebSocket socket, HttpRequest request) onConnection,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        onConnection(socket, request);
      }),
    );
    return _WebSocketTestServer._(server);
  }

  Future<void> close() => _server.close(force: true);
}
