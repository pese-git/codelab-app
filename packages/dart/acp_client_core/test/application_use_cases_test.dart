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
      AcpTransportState.connected,
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

  test('keeps cancelled prompt terminal when late update arrives', () async {
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
        result: const PromptResponse(stopReason: StopReason.cancelled).toJson(),
      ),
    );
    await promptFuture;
  });

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

JsonRpcRequest _permissionRequest() {
  return JsonRpcMessage.request(
        id: const JsonRpcId.integer(42),
        method: sessionRequestPermissionMethod,
        params: const RequestPermissionRequest(
          sessionId: SessionId('session-1'),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId('tool-1'),
            title: 'Run command',
            kind: ToolKind.execute,
          ),
          options: [
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
