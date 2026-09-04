import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeAcpTransport transport;
  late FakeTerminalProcessRunner runner;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    await transport.start();
    runner = FakeTerminalProcessRunner();
    client = AcpClientApplication(
      transport: transport,
      terminalProcessRunner: runner,
    );
    await _createSession(client, transport);
    transport.drainSentMessages();
  });

  tearDown(() async {
    await client.dispose();
    await transport.close();
  });

  test(
    'terminal/create starts the process immediately, without an approval '
    'request, and returns terminalId without waiting for completion',
    () async {
      transport.emitInbound(_createRequest(id: 1, command: 'npm'));
      await _pump();

      expect(runner.started, hasLength(1));
      expect(runner.started.single.command, 'npm');
      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.id, const JsonRpcId.integer(1));
      expect(response.error, isNull);
      final result = CreateTerminalResponse.fromJson(response.result);
      expect(result.terminalId.value, isNotEmpty);
      // No pending approval was created for this — the session stays idle.
      expect(
        client.sessionById(const SessionId('session-1'))?.status,
        SessionLifecycleStatus.active,
      );
    },
  );

  test('terminal/create with a cwd outside the working directory is rejected '
      'without starting a process', () async {
    transport.emitInbound(_createRequest(id: 2, command: 'npm', cwd: '/etc'));
    await _pump();

    expect(runner.started, isEmpty);
    final response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.id, const JsonRpcId.integer(2));
    expect(response.error, isNotNull);
    expect(response.error!.code, jsonRpcInvalidParamsCode);
  });

  test('terminal/output returns accumulated output and exitStatus: null for a '
      'running process', () async {
    transport.emitInbound(_createRequest(id: 3, command: 'npm'));
    await _pump();
    final terminalId = _terminalIdFrom(transport.sentMessages.single);
    transport.drainSentMessages();

    runner.handles.single.appendOutput('installing...\n');

    transport.emitInbound(_outputRequest(id: 4, terminalId: terminalId));
    await _pump();

    final response = transport.sentMessages.single as JsonRpcResponse;
    expect(
      TerminalOutputResponse.fromJson(response.result),
      const TerminalOutputResponse(output: 'installing...\n', truncated: false),
    );
  });

  test('terminal/wait_for_exit blocks until the process exits and returns the '
      'exit code/signal', () async {
    transport.emitInbound(_createRequest(id: 5, command: 'npm'));
    await _pump();
    final terminalId = _terminalIdFrom(transport.sentMessages.single);
    transport.drainSentMessages();

    transport.emitInbound(_waitForExitRequest(id: 6, terminalId: terminalId));
    await _pump();
    // Still running — no response yet.
    expect(transport.sentMessages, isEmpty);

    runner.handles.single.exit(exitCode: 0);
    await _pump();

    final response = transport.sentMessages.single as JsonRpcResponse;
    expect(
      WaitForTerminalExitResponse.fromJson(response.result),
      const WaitForTerminalExitResponse(exitCode: 0),
    );
  });

  test('terminal/kill does not release terminalId — output/wait_for_exit/'
      'release still work afterwards', () async {
    transport.emitInbound(_createRequest(id: 7, command: 'npm'));
    await _pump();
    final terminalId = _terminalIdFrom(transport.sentMessages.single);
    transport.drainSentMessages();

    transport.emitInbound(_killRequest(id: 8, terminalId: terminalId));
    await _pump();

    final killResponse = transport.sentMessages.single as JsonRpcResponse;
    expect(killResponse.error, isNull);
    expect(runner.handles.single.killCallCount, 1);
    expect(runner.handles.single.state, isA<TerminalProcessExited>());
    transport.drainSentMessages();

    transport.emitInbound(_outputRequest(id: 9, terminalId: terminalId));
    await _pump();
    expect((transport.sentMessages.single as JsonRpcResponse).error, isNull);
    transport.drainSentMessages();

    transport.emitInbound(_releaseRequest(id: 10, terminalId: terminalId));
    await _pump();
    expect((transport.sentMessages.single as JsonRpcResponse).error, isNull);
  });

  test('terminal/kill on an already-exited process is a no-op — no error and '
      'the recorded exit status is not overwritten', () async {
    transport.emitInbound(_createRequest(id: 11, command: 'npm'));
    await _pump();
    final terminalId = _terminalIdFrom(transport.sentMessages.single);
    transport.drainSentMessages();

    runner.handles.single.exit(exitCode: 0);

    transport.emitInbound(_killRequest(id: 12, terminalId: terminalId));
    await _pump();

    final response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.error, isNull);
    // kill() was still called once by the handler (it's the adapter's own
    // job to no-op internally), but the exit status recorded before it —
    // exitCode 0, no signal — was not replaced by a synthetic killed one.
    expect(runner.handles.single.killCallCount, 1);
    final state = runner.handles.single.state as TerminalProcessExited;
    expect(state.exitCode, 0);
    expect(state.signal, isNull);
  });

  test('terminal/release frees resources — later terminal/* calls with the '
      'same terminalId return "unknown terminal"', () async {
    transport.emitInbound(_createRequest(id: 13, command: 'npm'));
    await _pump();
    final terminalId = _terminalIdFrom(transport.sentMessages.single);
    transport.drainSentMessages();

    transport.emitInbound(_releaseRequest(id: 14, terminalId: terminalId));
    await _pump();
    expect((transport.sentMessages.single as JsonRpcResponse).error, isNull);
    transport.drainSentMessages();

    transport.emitInbound(_outputRequest(id: 15, terminalId: terminalId));
    await _pump();
    var response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.error, isNotNull);
    expect(response.error!.code, jsonRpcInvalidParamsCode);
    transport.drainSentMessages();

    transport.emitInbound(_waitForExitRequest(id: 16, terminalId: terminalId));
    await _pump();
    response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.error, isNotNull);
    transport.drainSentMessages();

    transport.emitInbound(_killRequest(id: 17, terminalId: terminalId));
    await _pump();
    response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.error, isNotNull);
    transport.drainSentMessages();

    transport.emitInbound(_releaseRequest(id: 18, terminalId: terminalId));
    await _pump();
    response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.error, isNotNull);
  });

  test('output exceeding outputByteLimit is truncated from the start and '
      'reported as truncated: true', () async {
    transport.emitInbound(
      _createRequest(id: 19, command: 'npm', outputByteLimit: 5),
    );
    await _pump();
    final terminalId = _terminalIdFrom(transport.sentMessages.single);
    transport.drainSentMessages();

    runner.handles.single.appendOutput('0123456789');

    transport.emitInbound(_outputRequest(id: 20, terminalId: terminalId));
    await _pump();

    final response = TerminalOutputResponse.fromJson(
      (transport.sentMessages.single as JsonRpcResponse).result,
    );
    expect(response.truncated, isTrue);
    expect(response.output, hasLength(5));
    expect(response.output, '56789');
  });

  test('a connection failure kills every active terminal process across every '
      'session', () async {
    final freshTransport = FakeAcpTransport()
      ..initializeProtocolVersion =
          AcpClientApplication.supportedProtocolVersion;
    final freshRunner = FakeTerminalProcessRunner();
    final freshClient = AcpClientApplication(
      transport: FakeAcpTransport(),
      terminalProcessRunner: freshRunner,
    );
    addTearDown(freshClient.dispose);
    await freshClient.connect(freshTransport);
    freshTransport.drainSentMessages();
    await _createSession(freshClient, freshTransport);
    freshTransport.drainSentMessages();

    freshTransport.emitInbound(_createRequest(id: 1, command: 'npm'));
    await _pump();
    freshTransport.drainSentMessages();
    expect(freshRunner.handles, hasLength(1));
    expect(freshRunner.handles.single.state, isA<TerminalProcessRunning>());

    freshTransport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'Stdio ACP agent exited unexpectedly with code 1.',
      ),
    );
    await _pump();

    expect(freshRunner.handles.single.killCallCount, 1);
    expect(freshRunner.handles.single.state, isA<TerminalProcessExited>());
  });

  test('initialize announces clientCapabilities.terminal matching whether a '
      'terminal adapter is wired in', () async {
    Future<bool> initializeAndGetCapability({
      TerminalProcessRunner? terminalProcessRunner,
    }) async {
      final freshTransport = FakeAcpTransport();
      final freshClient = AcpClientApplication(
        transport: FakeAcpTransport(),
        terminalProcessRunner: terminalProcessRunner,
      );
      addTearDown(freshClient.dispose);
      await freshClient.connect(freshTransport);
      final sent = freshTransport.sentMessages.single as JsonRpcRequest;
      return InitializeRequest.fromJson(
        sent.params,
      ).clientCapabilities.terminal;
    }

    expect(await initializeAndGetCapability(), isFalse);
    expect(
      await initializeAndGetCapability(
        terminalProcessRunner: FakeTerminalProcessRunner(),
      ),
      isTrue,
    );
  });
}

CreateTerminalRequest _createRequestParams({
  required String command,
  String? cwd,
  int? outputByteLimit,
}) {
  return CreateTerminalRequest(
    sessionId: const SessionId('session-1'),
    command: command,
    cwd: cwd,
    outputByteLimit: outputByteLimit,
  );
}

JsonRpcRequest _createRequest({
  required int id,
  required String command,
  String? cwd,
  int? outputByteLimit,
}) {
  return JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: terminalCreateMethod,
        params: _createRequestParams(
          command: command,
          cwd: cwd,
          outputByteLimit: outputByteLimit,
        ).toJson(),
      )
      as JsonRpcRequest;
}

JsonRpcRequest _outputRequest({
  required int id,
  required TerminalId terminalId,
}) {
  return JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: terminalOutputMethod,
        params: TerminalOutputRequest(
          sessionId: const SessionId('session-1'),
          terminalId: terminalId,
        ).toJson(),
      )
      as JsonRpcRequest;
}

JsonRpcRequest _waitForExitRequest({
  required int id,
  required TerminalId terminalId,
}) {
  return JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: terminalWaitForExitMethod,
        params: WaitForTerminalExitRequest(
          sessionId: const SessionId('session-1'),
          terminalId: terminalId,
        ).toJson(),
      )
      as JsonRpcRequest;
}

JsonRpcRequest _killRequest({required int id, required TerminalId terminalId}) {
  return JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: terminalKillMethod,
        params: KillTerminalCommandRequest(
          sessionId: const SessionId('session-1'),
          terminalId: terminalId,
        ).toJson(),
      )
      as JsonRpcRequest;
}

JsonRpcRequest _releaseRequest({
  required int id,
  required TerminalId terminalId,
}) {
  return JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: terminalReleaseMethod,
        params: ReleaseTerminalRequest(
          sessionId: const SessionId('session-1'),
          terminalId: terminalId,
        ).toJson(),
      )
      as JsonRpcRequest;
}

TerminalId _terminalIdFrom(JsonRpcMessage message) {
  final response = message as JsonRpcResponse;
  return CreateTerminalResponse.fromJson(response.result).terminalId;
}

Future<void> _createSession(
  AcpClientApplication client,
  FakeAcpTransport transport,
) async {
  final future = CreateSession(client)(
    const CreateSessionCommand(cwd: '/workspace'),
  ).run();
  await _pump();
  final request = transport.sentMessages.single as JsonRpcRequest;
  transport.emitInbound(
    JsonRpcMessage.response(
      id: request.id,
      result: const NewSessionResponse(
        sessionId: SessionId('session-1'),
      ).toJson(),
    ),
  );
  await future;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
