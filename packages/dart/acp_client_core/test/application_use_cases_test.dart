import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(transport: transport);
  });

  tearDown(() async {
    await client.dispose();
    await transport.close();
  });

  test('CreateSession sends session/new and stores active session', () async {
    final changes = <AcpSession>[];
    final subscription = client.sessionChanges.listen(changes.add);
    final createSession = CreateSession(client);

    final future = createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    ).run();
    await _pump();

    final request = transport.sentMessages.single as JsonRpcRequest;
    expect(request.method, sessionNewMethod);
    expect(
      NewSessionRequest.fromJson(request.params),
      const NewSessionRequest(cwd: '/workspace', mcpServers: []),
    );

    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(
          sessionId: SessionId('session-1'),
        ).toJson(),
      ),
    );

    final result = await future;
    final session = result.getOrElse((failure) => fail('$failure'));
    expect(session.id, const SessionId('session-1'));
    expect(session.cwd, '/workspace');
    expect(session.status, SessionLifecycleStatus.active);
    expect(client.sessionById(const SessionId('session-1')), session);
    expect(changes.single, session);

    await subscription.cancel();
  });

  test('SetSessionConfigOption sends session/set_config_option and stores the '
      "response's configOptions", () async {
    await _createSession(client, transport);
    transport.drainSentMessages();

    final future = SetSessionConfigOption(client)(
      const SetSessionConfigOptionCommand(
        sessionId: SessionId('session-1'),
        configId: SessionConfigId('model'),
        value: SessionConfigValueId('gpt-5'),
      ),
    ).run();
    await _pump();

    final request = transport.sentMessages.single as JsonRpcRequest;
    expect(request.method, sessionSetConfigOptionMethod);
    expect(
      SetSessionConfigOptionRequest.fromJson(request.params),
      const SetSessionConfigOptionRequest(
        sessionId: SessionId('session-1'),
        configId: SessionConfigId('model'),
        value: SessionConfigValueId('gpt-5'),
      ),
    );

    const updatedOption = SessionConfigOption.select(
      id: SessionConfigId('model'),
      name: 'Model',
      currentValue: SessionConfigValueId('gpt-5'),
      options: [
        SessionConfigSelectOption(
          value: SessionConfigValueId('gpt-5'),
          name: 'GPT-5',
        ),
      ],
    );
    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const SetSessionConfigOptionResponse(
          configOptions: [updatedOption],
        ).toJson(),
      ),
    );

    final result = await future;
    final session = result.getOrElse((failure) => fail('$failure'));
    expect(session.configOptions, [updatedOption]);
    expect(client.sessionById(const SessionId('session-1'))?.configOptions, [
      updatedOption,
    ]);
  });

  test(
    "SetSessionConfigOption does not change the session's configOptions when "
    'the agent rejects the request',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();

      final future = SetSessionConfigOption(client)(
        const SetSessionConfigOptionCommand(
          sessionId: SessionId('session-1'),
          configId: SessionConfigId('model'),
          value: SessionConfigValueId('unknown-model'),
        ),
      ).run();
      await _pump();
      final request = transport.sentMessages.single as JsonRpcRequest;

      transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          error: const JsonRpcError(
            code: -32000,
            message: 'unknown config value',
          ),
        ),
      );

      final result = await future;
      expect(result.isLeft(), isTrue);
      expect(
        client.sessionById(const SessionId('session-1'))?.configOptions,
        isNull,
      );
    },
  );

  test('LoadSession sends session/load and stores active session', () async {
    final changes = <AcpSession>[];
    final subscription = client.sessionChanges.listen(changes.add);
    final loadSession = LoadSession(client);

    final future = loadSession(
      const LoadSessionCommand(
        sessionId: SessionId('session-1'),
        cwd: '/workspace',
      ),
    ).run();
    await _pump();

    final request = transport.sentMessages.single as JsonRpcRequest;
    expect(request.method, sessionLoadMethod);
    expect(
      LoadSessionRequest.fromJson(request.params),
      const LoadSessionRequest(
        sessionId: SessionId('session-1'),
        cwd: '/workspace',
        mcpServers: [],
      ),
    );

    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const LoadSessionResponse().toJson(),
      ),
    );

    final result = await future;
    final session = result.getOrElse((failure) => fail('$failure'));
    expect(session.id, const SessionId('session-1'));
    expect(session.cwd, '/workspace');
    expect(session.status, SessionLifecycleStatus.active);
    expect(client.sessionById(const SessionId('session-1')), session);
    expect(changes.single, session);

    await subscription.cancel();
  });

  test('LoadSession returns typed transport failure when send fails', () async {
    transport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'disconnected',
      ),
    );

    final result = await LoadSession(client)(
      const LoadSessionCommand(
        sessionId: SessionId('session-1'),
        cwd: '/workspace',
      ),
    ).run();

    expect(result.isLeft(), isTrue);
    result.match((failure) {
      expect(failure, isA<AcpClientTransportFailure>());
      expect(
        (failure as AcpClientTransportFailure).code,
        AcpTransportErrorCode.disconnected,
      );
    }, (_) => fail('expected transport failure'));
    expect(
      client.diagnostics,
      contains(
        isA<DiagnosticEntry>()
            .having(
              (entry) => entry.severity,
              'severity',
              DiagnosticSeverity.error,
            )
            .having((entry) => entry.source, 'source', 'transport'),
      ),
    );
    expect(
      client.diagnostics,
      contains(
        isA<DiagnosticEntry>()
            .having(
              (entry) => entry.message,
              'message',
              'Failed to send ACP request session/load.',
            )
            .having((entry) => entry.source, 'source', 'application.protocol')
            .having(
              (entry) => entry.context,
              'context',
              containsPair('method', sessionLoadMethod),
            ),
      ),
    );
  });

  test('CreateSession records decode failure diagnostics', () async {
    final future = CreateSession(client)(
      const CreateSessionCommand(cwd: '/workspace'),
    ).run();
    await _pump();

    final request = transport.sentMessages.single as JsonRpcRequest;
    transport.emitInbound(
      JsonRpcMessage.response(id: request.id, result: const {'modes': {}}),
    );

    final result = await future;
    expect(result.isLeft(), isTrue);
    result.match((failure) {
      expect(failure, isA<AcpClientUnexpectedFailure>());
    }, (_) => fail('expected decode failure'));
    expect(
      client.diagnostics.single,
      isA<DiagnosticEntry>()
          .having(
            (entry) => entry.message,
            'message',
            'Failed to decode ACP response for session/new.',
          )
          .having((entry) => entry.source, 'source', 'application.protocol')
          .having(
            (entry) => entry.context,
            'context',
            allOf(
              containsPair('method', sessionNewMethod),
              containsPair('requestId', 1),
              containsPair('result', {'modes': {}}),
            ),
          ),
    );
  });

  test('connect performs initialize and becomes ready on a compatible '
      'protocol version', () async {
    final freshTransport = FakeAcpTransport()
      ..initializeProtocolVersion =
          AcpClientApplication.supportedProtocolVersion
      ..initializeAgentInfo = const Implementation(
        name: 'test-agent',
        version: '1.0.0',
      );
    final freshClient = AcpClientApplication(transport: FakeAcpTransport());
    addTearDown(freshClient.dispose);

    final result = await freshClient.connect(freshTransport);

    expect(result, isA<ClientConnectionReady>());
    final ready = result as ClientConnectionReady;
    expect(
      ready.protocolVersion,
      AcpClientApplication.supportedProtocolVersion,
    );
    expect(ready.agentInfo?.name, 'test-agent');
    expect(freshClient.connectionState, isA<ClientConnectionReady>());

    final sentInitialize = freshTransport.sentMessages.single as JsonRpcRequest;
    expect(sentInitialize.method, initializeMethod);
  });

  test('connect closes the transport and fails when the agent negotiates an '
      'unsupported protocol version', () async {
    final freshTransport = FakeAcpTransport()
      ..initializeProtocolVersion = const ProtocolVersion(9999);
    final freshClient = AcpClientApplication(transport: FakeAcpTransport());
    addTearDown(freshClient.dispose);

    await expectLater(
      freshClient.connect(freshTransport),
      throwsA(isA<UnsupportedProtocolVersionException>()),
    );

    expect(freshTransport.state, AcpTransportState.closed);
    expect(freshClient.connectionState, isA<ClientConnectionFailed>());
    final failed = freshClient.connectionState as ClientConnectionFailed;
    expect(failed.reason, ConnectionFailureReason.unsupportedProtocolVersion);
  });

  test('Reconnect replaces transport and starts the replacement', () async {
    await client.dispose();
    final replacement = FakeAcpTransport();
    client = AcpClientApplication(
      transport: transport,
      reconnectTransport: () => replacement,
    );

    final result = await Reconnect(client)(const ReconnectCommand()).run();

    expect(
      result.getOrElse((failure) => fail('$failure')),
      isA<ClientConnectionReady>(),
    );
    expect(transport.state, AcpTransportState.closed);
    expect(replacement.state, AcpTransportState.connected);

    await replacement.close();
  });

  test('Reconnect can use command replacement factory', () async {
    final replacement = FakeAcpTransport();

    final result = await Reconnect(client)(
      ReconnectCommand(transportFactory: () => replacement),
    ).run();

    expect(
      result.getOrElse((failure) => fail('$failure')),
      isA<ClientConnectionReady>(),
    );
    expect(transport.state, AcpTransportState.closed);
    expect(replacement.state, AcpTransportState.connected);

    await replacement.close();
  });

  test('Reconnect returns typed failure without transport factory', () async {
    final result = await Reconnect(client)(const ReconnectCommand()).run();

    expect(result.isLeft(), isTrue);
    result.match((failure) {
      expect(failure, isA<AcpClientStateRejectedFailure>());
    }, (_) => fail('expected state failure'));
  });

  test('Reconnect bumps the connection generation', () async {
    expect(client.generation, 0);

    final replacement = FakeAcpTransport();
    await Reconnect(client)(
      ReconnectCommand(transportFactory: () => replacement),
    ).run();

    expect(client.generation, 1);

    await replacement.close();
  });

  test('unexpected transport failure while ready surfaces as '
      'ClientConnectionFailed on connectionStateChanges', () async {
    final freshTransport = FakeAcpTransport()
      ..initializeProtocolVersion =
          AcpClientApplication.supportedProtocolVersion;
    final freshClient = AcpClientApplication(transport: FakeAcpTransport());
    addTearDown(freshClient.dispose);
    await freshClient.connect(freshTransport);
    expect(freshClient.connectionState, isA<ClientConnectionReady>());

    final states = <ClientConnectionState>[];
    final subscription = freshClient.connectionStateChanges.listen(states.add);

    freshTransport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'Stdio ACP agent exited unexpectedly with code 1.',
      ),
    );

    expect(freshClient.connectionState, isA<ClientConnectionFailed>());
    final failed = freshClient.connectionState as ClientConnectionFailed;
    expect(failed.reason, ConnectionFailureReason.disconnected);
    expect(failed.message, 'Stdio ACP agent exited unexpectedly with code 1.');
    expect(states, [isA<ClientConnectionFailed>()]);

    await subscription.cancel();
  });

  test('transport failure while already disconnected does not throw or '
      'change connection state', () async {
    expect(client.connectionState, isA<ClientConnectionDisconnected>());

    expect(
      () => transport.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'late failure after disconnect',
        ),
      ),
      returnsNormally,
    );

    expect(client.connectionState, isA<ClientConnectionDisconnected>());
  });

  test('transport failure from a transport replaced by reconnect does not '
      'affect the current connection', () async {
    final oldTransport = FakeAcpTransport()
      ..initializeProtocolVersion =
          AcpClientApplication.supportedProtocolVersion;
    final newTransport = FakeAcpTransport()
      ..initializeProtocolVersion =
          AcpClientApplication.supportedProtocolVersion;
    final freshClient = AcpClientApplication(
      transport: FakeAcpTransport(),
      reconnectTransport: () => newTransport,
    );
    addTearDown(freshClient.dispose);
    await freshClient.connect(oldTransport);

    final result = await Reconnect(freshClient)(const ReconnectCommand()).run();
    expect(result.isRight(), isTrue);
    expect(freshClient.connectionState, isA<ClientConnectionReady>());

    // The old transport is no longer bound (its generation was superseded) —
    // a late failure from it must not reach the current connection state.
    oldTransport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'stale failure from superseded transport',
      ),
    );

    expect(freshClient.connectionState, isA<ClientConnectionReady>());

    await newTransport.close();
  });

  test('SendPrompt does not overwrite turn state with a stale failure when '
      'reconnect races the in-flight response', () async {
    await _createSession(client, transport);
    transport.drainSentMessages();

    final promptFuture = client.sendPrompt(
      const SendPromptCommand(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    );
    // Attach the expectation immediately so the rejection below is never
    // briefly unhandled while the test awaits other steps in between.
    final promptExpectation = expectLater(
      promptFuture,
      throwsA(isA<AcpClientApplicationException>()),
    );
    await _pump();
    expect(transport.sentMessages, hasLength(1));
    expect(
      client.sessionById(const SessionId('session-1'))?.activeTurn?.status,
      PromptTurnStatus.running,
    );

    final replacement = FakeAcpTransport();
    await client.reconnect(
      ReconnectCommand(transportFactory: () => replacement),
    );
    expect(client.generation, 1);

    // The old transport's failed pending request now resolves; a stale
    // generation must not be allowed to mutate turn state that belongs to
    // the superseded connection into "failed".
    await promptExpectation;

    final turn = client.sessionById(const SessionId('session-1'))?.activeTurn;
    expect(turn, isNotNull);
    expect(turn?.status, PromptTurnStatus.running);

    await replacement.close();
  });

  test('SendPrompt streams updates and completes from stopReason', () async {
    await _createSession(client, transport);
    transport.drainSentMessages();

    final changes = <AcpSession>[];
    final subscription = client.sessionChanges.listen(changes.add);
    final sendPrompt = SendPrompt(client);

    final future = sendPrompt(
      const SendPromptCommand(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    ).run();
    await _pump();

    final request = transport.sentMessages.single as JsonRpcRequest;
    expect(request.method, sessionPromptMethod);
    expect(
      PromptRequest.fromJson(request.params),
      const PromptRequest(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    );
    expect(changes.single.status, SessionLifecycleStatus.runningTurn);
    expect(changes.single.turns.single.status, PromptTurnStatus.running);

    transport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: const SessionNotification(
          sessionId: SessionId('session-1'),
          update: SessionUpdate.agentMessageChunk(
            content: ContentBlock.text(text: 'hi'),
          ),
        ).toJson(),
      ),
    );

    final updated = client.sessionById(const SessionId('session-1'));
    expect(updated?.turns.single.updates, hasLength(1));
    expect(updated?.turns.single.status, PromptTurnStatus.running);

    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
      ),
    );

    final result = await future;
    final turn = result.getOrElse((failure) => fail('$failure'));
    expect(turn.status, PromptTurnStatus.completed);
    expect(turn.stopReason, StopReason.endTurn);
    expect(turn.updates.single, isA<AgentMessageChunk>());

    final session = client.sessionById(const SessionId('session-1'));
    expect(session?.status, SessionLifecycleStatus.active);
    expect(session?.turns.single, turn);
    expect(changes.map((session) => session.status), [
      SessionLifecycleStatus.runningTurn,
      SessionLifecycleStatus.runningTurn,
      SessionLifecycleStatus.active,
    ]);

    await subscription.cancel();
  });

  test(
    'SendPrompt deduplicates and accepts interleaved running updates',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();

      final promptFuture = SendPrompt(client)(
        const SendPromptCommand(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      ).run();
      await _pump();
      final promptRequest = transport.sentMessages.single as JsonRpcRequest;

      const messageUpdate = SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: 'hi'),
      );
      const toolUpdate = SessionUpdate.toolCallUpdate(
        toolCallUpdate: ToolCallUpdate(
          toolCallId: ToolCallId('tool-1'),
          title: 'Read file',
          kind: ToolKind.read,
          status: ToolCallStatus.inProgress,
        ),
      );
      transport.emitInbound(_sessionUpdate(messageUpdate));
      transport.emitInbound(_sessionUpdate(toolUpdate));
      transport.emitInbound(_sessionUpdate(messageUpdate));
      transport.emitInbound(_sessionUpdate(toolUpdate));

      final running = client.sessionById(const SessionId('session-1'));
      expect(running?.turns.single.updates, [messageUpdate, toolUpdate]);
      expect(running?.turns.single.toolCalls, hasLength(1));
      expect(
        running?.turns.single.toolCalls[const ToolCallId('tool-1')]?.title,
        'Read file',
      );

      transport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id,
          result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
        ),
      );

      final turn = (await promptFuture).getOrElse(
        (failure) => fail('$failure'),
      );
      expect(turn.status, PromptTurnStatus.completed);
      expect(turn.updates, [messageUpdate, toolUpdate]);
    },
  );

  test(
    'SendPrompt maps protocol error responses to failure diagnostics',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();

      final promptFuture = SendPrompt(client)(
        const SendPromptCommand(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      ).run();
      await _pump();
      final request = transport.sentMessages.single as JsonRpcRequest;

      transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          error: const JsonRpcError(
            code: -32000,
            message: 'agent rejected prompt',
          ),
        ),
      );

      final result = await promptFuture;
      expect(result.isLeft(), isTrue);
      result.match((failure) {
        expect(failure, isA<AcpClientUnexpectedFailure>());
      }, (_) => fail('expected protocol error failure'));
      expect(
        client.sessionById(const SessionId('session-1'))?.turns.single.status,
        PromptTurnStatus.failed,
      );
      expect(
        client.diagnostics,
        contains(
          isA<DiagnosticEntry>()
              .having(
                (entry) => entry.message,
                'message',
                'ACP request session/prompt failed: agent rejected prompt',
              )
              .having((entry) => entry.source, 'source', 'application.protocol')
              .having(
                (entry) => entry.context,
                'context',
                allOf(
                  containsPair('method', sessionPromptMethod),
                  containsPair('requestId', request.id.toJsonValue()),
                ),
              ),
        ),
      );
    },
  );

  test('SendPrompt maps transport failure events to diagnostics', () async {
    await _createSession(client, transport);
    transport.drainSentMessages();

    transport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.receiveFailed,
        message: 'socket read failed',
        cause: 'broken frame',
      ),
    );

    final result = await SendPrompt(client)(
      const SendPromptCommand(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    ).run();

    expect(result.isLeft(), isTrue);
    result.match((failure) {
      expect(failure, isA<AcpClientTransportFailure>());
    }, (_) => fail('expected transport failure'));
    expect(
      client.diagnostics,
      contains(
        isA<DiagnosticEntry>()
            .having((entry) => entry.message, 'message', 'socket read failed')
            .having((entry) => entry.source, 'source', 'transport')
            .having(
              (entry) => entry.context,
              'context',
              allOf(
                containsPair('code', AcpTransportErrorCode.receiveFailed.name),
                containsPair('cause', 'broken frame'),
              ),
            ),
      ),
    );
  });

  test('SendPrompt returns typed failure when session is missing', () async {
    final sendPrompt = SendPrompt(client);

    final result = await sendPrompt(
      const SendPromptCommand(
        sessionId: SessionId('missing-session'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    ).run();

    expect(result.isLeft(), isTrue);
    result.match((failure) {
      expect(failure, isA<AcpClientMissingSessionFailure>());
      expect(
        (failure as AcpClientMissingSessionFailure).sessionId,
        const SessionId('missing-session'),
      );
    }, (_) => fail('expected missing session failure'));
    expect(transport.sentMessages, isEmpty);
  });

  test(
    'RespondToPermission sends selected response and resumes turn',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();
      final promptFuture = SendPrompt(client)(
        const SendPromptCommand(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      ).run();
      await _pump();
      final promptRequest = transport.sentMessages.single as JsonRpcRequest;

      transport.emitInbound(_permissionRequest());

      final awaiting = client.sessionById(const SessionId('session-1'));
      expect(awaiting?.status, SessionLifecycleStatus.awaitingApproval);
      expect(
        awaiting
            ?.turns
            .single
            .approvals[const ApprovalRequestId('permission-42')]
            ?.status,
        ApprovalStatus.pending,
      );
      expect(
        awaiting
            ?.turns
            .single
            .approvals[const ApprovalRequestId('permission-42')]
            ?.riskLevel,
        ApprovalRiskLevel.shell,
      );
      expect(
        awaiting
            ?.turns
            .single
            .approvals[const ApprovalRequestId('permission-42')]
            ?.toolCall
            .riskLevel,
        ApprovalRiskLevel.shell,
      );
      transport.drainSentMessages();

      final result = await RespondToPermission(client)(
        const RespondToPermissionCommand.selected(
          sessionId: SessionId('session-1'),
          approvalId: ApprovalRequestId('permission-42'),
          optionId: PermissionOptionId('allow-once'),
        ),
      ).run();

      final approval = result.getOrElse((failure) => fail('$failure'));
      expect(approval.status, ApprovalStatus.selected);
      expect(approval.selectedOptionId, const PermissionOptionId('allow-once'));

      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.id, const JsonRpcId.integer(42));
      expect(
        RequestPermissionResponse.fromJson(response.result),
        const RequestPermissionResponse(
          outcome: RequestPermissionOutcome.selected(
            optionId: PermissionOptionId('allow-once'),
          ),
        ),
      );
      expect(
        client.sessionById(const SessionId('session-1'))?.status,
        SessionLifecycleStatus.runningTurn,
      );

      transport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id,
          result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
        ),
      );
      (await promptFuture).getOrElse((failure) => fail('$failure'));
    },
  );

  test('ignores duplicate permission request ids', () async {
    await _createSession(client, transport);
    transport.drainSentMessages();
    final changes = <AcpSession>[];
    final subscription = client.sessionChanges.listen(changes.add);
    final promptFuture = SendPrompt(client)(
      const SendPromptCommand(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    ).run();
    await _pump();
    final promptRequest = transport.sentMessages.single as JsonRpcRequest;

    final permissionRequest = _permissionRequest();
    transport.emitInbound(permissionRequest);
    transport.emitInbound(permissionRequest);

    final session = client.sessionById(const SessionId('session-1'));
    expect(session?.turns.single.approvals, hasLength(1));
    expect(
      session?.turns.single.approvals.keys,
      contains(const ApprovalRequestId('permission-42')),
    );
    expect(changes.map((session) => session.status), [
      SessionLifecycleStatus.runningTurn,
      SessionLifecycleStatus.awaitingApproval,
    ]);

    transport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest.id,
        result: const PromptResponse(stopReason: StopReason.cancelled).toJson(),
      ),
    );
    await promptFuture;
    await subscription.cancel();
  });

  test(
    'CancelTurn sends session/cancel and cancels pending approval',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();
      final promptFuture = SendPrompt(client)(
        const SendPromptCommand(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      ).run();
      await _pump();
      final promptRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.emitInbound(_permissionRequest());
      transport.drainSentMessages();

      final result = await CancelTurn(client)(
        const CancelTurnCommand(sessionId: SessionId('session-1')),
      ).run();

      final turn = result.getOrElse((failure) => fail('$failure'));
      expect(turn.status, PromptTurnStatus.cancelled);
      expect(
        turn.approvals[const ApprovalRequestId('permission-42')]?.status,
        ApprovalStatus.cancelled,
      );

      final cancel = transport.sentMessages[0] as JsonRpcNotification;
      expect(cancel.method, sessionCancelMethod);
      expect(
        CancelNotification.fromJson(cancel.params),
        const CancelNotification(sessionId: SessionId('session-1')),
      );

      final permissionResponse = transport.sentMessages[1] as JsonRpcResponse;
      expect(permissionResponse.id, const JsonRpcId.integer(42));
      expect(
        RequestPermissionResponse.fromJson(permissionResponse.result),
        const RequestPermissionResponse(
          outcome: RequestPermissionOutcome.cancelled(),
        ),
      );

      transport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id,
          result: const PromptResponse(
            stopReason: StopReason.cancelled,
          ).toJson(),
        ),
      );
      final promptResult = await promptFuture;
      expect(
        promptResult.getOrElse((failure) => fail('$failure')).status,
        PromptTurnStatus.cancelled,
      );
    },
  );

  test('CancelTurn responds cancelled for every pending approval', () async {
    await _createSession(client, transport);
    transport.drainSentMessages();
    final promptFuture = SendPrompt(client)(
      const SendPromptCommand(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    ).run();
    await _pump();
    final promptRequest = transport.sentMessages.single as JsonRpcRequest;
    transport.emitInbound(_permissionRequest());
    transport.emitInbound(_permissionRequest(id: 43, toolCallId: 'tool-2'));
    transport.drainSentMessages();

    final result = await CancelTurn(client)(
      const CancelTurnCommand(sessionId: SessionId('session-1')),
    ).run();

    final turn = result.getOrElse((failure) => fail('$failure'));
    expect(turn.status, PromptTurnStatus.cancelled);
    expect(
      turn.approvals.values.map((approval) => approval.status),
      everyElement(ApprovalStatus.cancelled),
    );
    expect(transport.sentMessages, hasLength(3));
    expect(
      transport.sentMessages.whereType<JsonRpcResponse>().map(
        (response) => response.id,
      ),
      [const JsonRpcId.integer(42), const JsonRpcId.integer(43)],
    );

    transport.emitInbound(
      JsonRpcMessage.response(
        id: promptRequest.id,
        result: const PromptResponse(stopReason: StopReason.cancelled).toJson(),
      ),
    );
    await promptFuture;
  });

  test(
    'CancelTurn is idempotent after the turn is locally cancelled',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();
      final promptFuture = SendPrompt(client)(
        const SendPromptCommand(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      ).run();
      await _pump();
      final promptRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.drainSentMessages();

      final firstResult = await CancelTurn(client)(
        const CancelTurnCommand(sessionId: SessionId('session-1')),
      ).run();
      final firstTurn = firstResult.getOrElse((failure) => fail('$failure'));
      expect(firstTurn.status, PromptTurnStatus.cancelled);
      expect(transport.sentMessages, hasLength(1));

      final secondResult = await CancelTurn(client)(
        const CancelTurnCommand(sessionId: SessionId('session-1')),
      ).run();
      final secondTurn = secondResult.getOrElse((failure) => fail('$failure'));
      expect(secondTurn, firstTurn);
      expect(transport.sentMessages, hasLength(1));

      transport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id,
          result: const PromptResponse(
            stopReason: StopReason.cancelled,
          ).toJson(),
        ),
      );
      final promptResult = await promptFuture;
      expect(
        promptResult.getOrElse((failure) => fail('$failure')).status,
        PromptTurnStatus.cancelled,
      );
    },
  );

  test(
    'CancelTurn keeps local cancellation when pending permission response fails',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();
      final sentSubscription = transport.sent.listen((message) {
        if (message case JsonRpcNotification(method: sessionCancelMethod)) {
          transport.failNextSend(
            const AcpTransportException(
              code: AcpTransportErrorCode.disconnected,
              message: 'disconnected before permission response',
            ),
          );
        }
      });
      addTearDown(sentSubscription.cancel);

      final promptFuture = SendPrompt(client)(
        const SendPromptCommand(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      ).run();
      await _pump();
      final promptRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.emitInbound(_permissionRequest());
      transport.drainSentMessages();

      final cancelResult = await CancelTurn(client)(
        const CancelTurnCommand(sessionId: SessionId('session-1')),
      ).run();

      expect(cancelResult.isLeft(), isTrue);
      cancelResult.match((failure) {
        expect(failure, isA<AcpClientTransportFailure>());
      }, (_) => fail('expected transport failure'));
      final session = client.sessionById(const SessionId('session-1'));
      expect(session?.status, SessionLifecycleStatus.active);
      expect(session?.turns.single.status, PromptTurnStatus.cancelled);
      expect(session?.diagnostics.single.severity, DiagnosticSeverity.error);
      expect(session?.diagnostics.single.source, 'application.permission');
      expect(
        session?.diagnostics.single.context,
        containsPair('method', sessionRequestPermissionMethod),
      );
      expect(
        session
            ?.turns
            .single
            .approvals[const ApprovalRequestId('permission-42')]
            ?.status,
        ApprovalStatus.cancelled,
      );

      transport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id,
          result: const PromptResponse(
            stopReason: StopReason.cancelled,
          ).toJson(),
        ),
      );
      final promptResult = await promptFuture;
      final turn = promptResult.getOrElse((failure) => fail('$failure'));
      expect(turn.status, PromptTurnStatus.cancelled);
      expect(
        client.sessionById(const SessionId('session-1'))?.status,
        SessionLifecycleStatus.active,
      );
    },
  );

  test('records redacted transport diagnostics on sessions', () async {
    await _createSession(client, transport);

    transport.emitDiagnostic(
      message: 'Authorization: Bearer transport-token',
      severity: AcpTransportDiagnosticSeverity.warning,
      source: 'stderr',
    );

    final diagnostic = client
        .sessionById(const SessionId('session-1'))
        ?.diagnostics
        .single;
    expect(client.diagnostics.single, diagnostic);
    expect(diagnostic?.message, 'Authorization: Bearer $redactedSecret');
    expect(diagnostic?.severity, DiagnosticSeverity.warning);
    expect(diagnostic?.source, 'stderr');
  });

  test('records redacted diagnostics for invalid session updates', () async {
    await _createSession(client, transport);

    transport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: const {
          'sessionId': 'session-1',
          'update': {'session_token': 'secret-token'},
        },
      ),
    );

    final diagnostic = client
        .sessionById(const SessionId('session-1'))
        ?.diagnostics
        .single;
    expect(diagnostic?.message, 'Failed to handle ACP session update.');
    expect(diagnostic?.severity, DiagnosticSeverity.error);
    expect(diagnostic?.context['params'], {
      'sessionId': redactedSecret,
      'update': {'session_token': redactedSecret},
    });
  });

  test('ignores interleaved updates for unknown sessions', () async {
    await _createSession(client, transport);
    final changes = <AcpSession>[];
    final subscription = client.sessionChanges.listen(changes.add);

    transport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: const SessionNotification(
          sessionId: SessionId('missing-session'),
          update: SessionUpdate.agentMessageChunk(
            content: ContentBlock.text(text: 'late'),
          ),
        ).toJson(),
      ),
    );

    expect(changes, isEmpty);
    expect(client.sessionById(const SessionId('session-1'))?.turns, isEmpty);

    await subscription.cancel();
  });

  test(
    'keeps cancelled prompt terminal through late update and final response',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();
      final changes = <AcpSession>[];
      final subscription = client.sessionChanges.listen(changes.add);
      final promptFuture = SendPrompt(client)(
        const SendPromptCommand(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      ).run();
      await _pump();
      final promptRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.drainSentMessages();

      final cancelResult = await CancelTurn(client)(
        const CancelTurnCommand(sessionId: SessionId('session-1')),
      ).run();
      expect(
        cancelResult.getOrElse((failure) => fail('$failure')).status,
        PromptTurnStatus.cancelled,
      );

      transport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: const SessionNotification(
            sessionId: SessionId('session-1'),
            update: SessionUpdate.agentMessageChunk(
              content: ContentBlock.text(text: 'late'),
            ),
          ).toJson(),
        ),
      );

      final afterLateUpdate = client.sessionById(const SessionId('session-1'));
      expect(afterLateUpdate?.status, SessionLifecycleStatus.active);
      expect(afterLateUpdate?.turns.single.status, PromptTurnStatus.cancelled);
      expect(afterLateUpdate?.turns.single.updates, isEmpty);

      transport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id,
          result: const PromptResponse(
            stopReason: StopReason.cancelled,
          ).toJson(),
        ),
      );
      final promptResult = await promptFuture;
      final finalTurn = promptResult.getOrElse((failure) => fail('$failure'));
      expect(finalTurn.status, PromptTurnStatus.cancelled);
      expect(finalTurn.stopReason, StopReason.cancelled);
      expect(
        client.sessionById(const SessionId('session-1'))?.turns.single,
        finalTurn,
      );
      expect(changes.map((session) => session.turns.single.status), [
        PromptTurnStatus.running,
        PromptTurnStatus.cancelled,
        PromptTurnStatus.cancelled,
        PromptTurnStatus.cancelled,
      ]);

      await subscription.cancel();
    },
  );

  test(
    'RespondToPermission returns typed failure for unavailable option',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();
      final promptFuture = SendPrompt(client)(
        const SendPromptCommand(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      ).run();
      await _pump();
      final promptRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.emitInbound(_permissionRequest());
      transport.drainSentMessages();

      final result = await RespondToPermission(client)(
        const RespondToPermissionCommand.selected(
          sessionId: SessionId('session-1'),
          approvalId: ApprovalRequestId('permission-42'),
          optionId: PermissionOptionId('missing-option'),
        ),
      ).run();

      expect(result.isLeft(), isTrue);
      result.match((failure) {
        expect(failure, isA<AcpClientStateRejectedFailure>());
      }, (_) => fail('expected state failure'));
      expect(transport.sentMessages, isEmpty);

      transport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id,
          result: const PromptResponse(
            stopReason: StopReason.cancelled,
          ).toJson(),
        ),
      );
      await promptFuture;
    },
  );

  test(
    'RespondToPermission keeps approval pending when response send fails',
    () async {
      await _createSession(client, transport);
      transport.drainSentMessages();
      final promptFuture = SendPrompt(client)(
        const SendPromptCommand(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      ).run();
      await _pump();
      final promptRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.emitInbound(_permissionRequest());
      transport.drainSentMessages();
      transport.failNextSend(
        const AcpTransportException(
          code: AcpTransportErrorCode.sendFailed,
          message: 'permission response failed',
        ),
      );

      final result = await RespondToPermission(client)(
        const RespondToPermissionCommand.selected(
          sessionId: SessionId('session-1'),
          approvalId: ApprovalRequestId('permission-42'),
          optionId: PermissionOptionId('allow-once'),
        ),
      ).run();

      expect(result.isLeft(), isTrue);
      result.match((failure) {
        expect(failure, isA<AcpClientTransportFailure>());
      }, (_) => fail('expected transport failure'));
      expect(
        client
            .sessionById(const SessionId('session-1'))
            ?.turns
            .single
            .approvals[const ApprovalRequestId('permission-42')]
            ?.status,
        ApprovalStatus.pending,
      );
      expect(
        client.diagnostics,
        contains(
          isA<DiagnosticEntry>()
              .having(
                (entry) => entry.message,
                'message',
                'Failed to send ACP response session/request_permission.',
              )
              .having(
                (entry) => entry.source,
                'source',
                'application.permission',
              )
              .having(
                (entry) => entry.context,
                'context',
                allOf(
                  containsPair('method', sessionRequestPermissionMethod),
                  containsPair('requestId', 42),
                  containsPair('approvalId', 'permission-42'),
                ),
              ),
        ),
      );

      transport.emitInbound(
        JsonRpcMessage.response(
          id: promptRequest.id,
          result: const PromptResponse(
            stopReason: StopReason.cancelled,
          ).toJson(),
        ),
      );
      await promptFuture;
    },
  );
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
  final result = await future;
  result.getOrElse((failure) => fail('$failure'));
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

JsonRpcNotification _sessionUpdate(SessionUpdate update) {
  return JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: SessionNotification(
          sessionId: const SessionId('session-1'),
          update: update,
        ).toJson(),
      )
      as JsonRpcNotification;
}

JsonRpcRequest _permissionRequest({int id = 42, String toolCallId = 'tool-1'}) {
  return JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: const SessionId('session-1'),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(toolCallId),
            title: 'Run command',
            kind: ToolKind.execute,
          ),
          options: const [
            PermissionOption(
              optionId: PermissionOptionId('allow-once'),
              name: 'Allow once',
              kind: PermissionOptionKind.allowOnce,
            ),
          ],
        ).toJson(),
      )
      as JsonRpcRequest;
}
