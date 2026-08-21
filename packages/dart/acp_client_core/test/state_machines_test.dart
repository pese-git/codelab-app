import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectionStateMachine', () {
    test('moves through connect initialize ready lifecycle', () {
      final connecting = ConnectionStateMachine.connect(
        const ClientConnectionState.disconnected(),
      );
      final initializing = ConnectionStateMachine.initialize(
        connecting.stateOrThrow,
      );
      final ready = ConnectionStateMachine.ready(
        initializing.stateOrThrow,
        protocolVersion: const ProtocolVersion(1),
        agentInfo: const Implementation(name: 'agent', version: '0.1.0'),
      );

      expect(connecting, isA<AppliedStateTransition<ClientConnectionState>>());
      expect(connecting.stateOrThrow, isA<ClientConnectionConnecting>());
      expect(initializing.stateOrThrow, isA<ClientConnectionInitializing>());
      expect(ready.stateOrThrow, isA<ClientConnectionReady>());
    });

    test('rejects ready before initialize', () {
      final result = ConnectionStateMachine.ready(
        const ClientConnectionState.connecting(),
        protocolVersion: const ProtocolVersion(1),
      );

      expect(result, isA<RejectedStateTransition<ClientConnectionState>>());
      expect(
        () => result.stateOrThrow,
        throwsA(isA<StateTransitionException>()),
      );
    });

    test('supports exhaustive event reducer calls', () {
      final result = ConnectionStateMachine.reduce(
        const ClientConnectionState.disconnected(),
        const ConnectionStateEvent.connect(),
      );

      expect(result.stateOrThrow, isA<ClientConnectionConnecting>());
    });
  });

  group('PromptTurnStateMachine', () {
    test('moves pending prompt through running approval and completion', () {
      final running = PromptTurnStateMachine.start(_pendingTurn);
      final awaitingApproval = PromptTurnStateMachine.requestApproval(
        running.stateOrThrow,
        _approval,
      );
      final approved = PromptTurnStateMachine.selectApproval(
        awaitingApproval.stateOrThrow,
        approvalId: _approval.id,
        optionId: const PermissionOptionId('allow-once'),
      );
      final completed = PromptTurnStateMachine.complete(
        approved.stateOrThrow,
        stopReason: StopReason.endTurn,
      );

      expect(running.stateOrThrow.status, PromptTurnStatus.running);
      expect(
        awaitingApproval.stateOrThrow.status,
        PromptTurnStatus.awaitingApproval,
      );
      expect(
        awaitingApproval.stateOrThrow.approvals[_approval.id]?.status,
        ApprovalStatus.pending,
      );
      expect(approved.stateOrThrow.status, PromptTurnStatus.running);
      expect(
        approved.stateOrThrow.approvals[_approval.id]?.status,
        ApprovalStatus.selected,
      );
      expect(completed.stateOrThrow.status, PromptTurnStatus.completed);
      expect(completed.stateOrThrow.stopReason, StopReason.endTurn);
      expect(completed.stateOrThrow.isTerminal, isTrue);
    });

    test('maps prompt stop reasons to terminal statuses', () {
      expect(
        PromptTurnStateMachine.complete(
          PromptTurnStateMachine.start(_pendingTurn).stateOrThrow,
          stopReason: StopReason.refusal,
        ).stateOrThrow.status,
        PromptTurnStatus.refused,
      );
      expect(
        PromptTurnStateMachine.complete(
          PromptTurnStateMachine.start(_pendingTurn).stateOrThrow,
          stopReason: StopReason.maxTokens,
        ).stateOrThrow.status,
        PromptTurnStatus.maxed,
      );
      expect(
        PromptTurnStateMachine.complete(
          PromptTurnStateMachine.start(_pendingTurn).stateOrThrow,
          stopReason: StopReason.cancelled,
        ).stateOrThrow.status,
        PromptTurnStatus.cancelled,
      );
    });

    test('rejects approval requests before a turn is running', () {
      final result = PromptTurnStateMachine.requestApproval(
        _pendingTurn,
        _approval,
      );

      expect(result, isA<RejectedStateTransition<PromptTurn>>());
    });

    test('keeps terminal prompt states stable for late updates and cancel', () {
      final completed = PromptTurnStateMachine.complete(
        PromptTurnStateMachine.start(_pendingTurn).stateOrThrow,
        stopReason: StopReason.endTurn,
      ).stateOrThrow;
      final update = const SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: 'late'),
      );
      final lateUpdate = PromptTurnStateMachine.applyUpdate(completed, update);
      final lateCancel = PromptTurnStateMachine.cancel(completed);

      expect(lateUpdate, isA<IgnoredStateTransition<PromptTurn>>());
      expect(lateUpdate.stateOrThrow, completed);
      expect(lateCancel, isA<IgnoredStateTransition<PromptTurn>>());
      expect(lateCancel.stateOrThrow, completed);
    });

    test('tracks tool calls from updates', () {
      final withTool = PromptTurnStateMachine.applyUpdate(
        PromptTurnStateMachine.start(_pendingTurn).stateOrThrow,
        const SessionUpdate.toolCall(
          toolCall: ToolCall(
            toolCallId: ToolCallId('tool-1'),
            title: 'Read file',
            kind: ToolKind.read,
            status: ToolCallStatus.inProgress,
          ),
        ),
      ).stateOrThrow;
      final completedTool = PromptTurnStateMachine.applyUpdate(
        withTool,
        const SessionUpdate.toolCallUpdate(
          toolCallUpdate: ToolCallUpdate(
            toolCallId: ToolCallId('tool-1'),
            status: ToolCallStatus.completed,
          ),
        ),
      ).stateOrThrow;

      expect(
        withTool.toolCalls[const ToolCallId('tool-1')]?.title,
        'Read file',
      );
      expect(
        completedTool.toolCalls[const ToolCallId('tool-1')]?.status,
        ToolCallStatus.completed,
      );
    });

    test('ignores duplicate message chunk updates', () {
      const update = SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: 'hi'),
      );
      final running = PromptTurnStateMachine.start(_pendingTurn).stateOrThrow;
      final first = PromptTurnStateMachine.applyUpdate(running, update);
      final duplicate = PromptTurnStateMachine.applyUpdate(
        first.stateOrThrow,
        update,
      );

      expect(first, isA<AppliedStateTransition<PromptTurn>>());
      expect(first.stateOrThrow.updates, [update]);
      expect(duplicate, isA<IgnoredStateTransition<PromptTurn>>());
      expect(duplicate.stateOrThrow.updates, [update]);
    });

    test('merges duplicate tool call updates by toolCallId', () {
      const update = SessionUpdate.toolCallUpdate(
        toolCallUpdate: ToolCallUpdate(
          toolCallId: ToolCallId('tool-1'),
          title: 'Run command',
          status: ToolCallStatus.inProgress,
        ),
      );
      final running = PromptTurnStateMachine.start(_pendingTurn).stateOrThrow;
      final first = PromptTurnStateMachine.applyUpdate(running, update);
      final duplicate = PromptTurnStateMachine.applyUpdate(
        first.stateOrThrow,
        update,
      );

      expect(first.stateOrThrow.toolCalls, hasLength(1));
      expect(
        first.stateOrThrow.toolCalls[const ToolCallId('tool-1')]?.status,
        ToolCallStatus.inProgress,
      );
      expect(duplicate, isA<IgnoredStateTransition<PromptTurn>>());
      expect(duplicate.stateOrThrow.updates, [update]);
      expect(duplicate.stateOrThrow.toolCalls, hasLength(1));
    });
  });

  group('SessionStateMachine', () {
    test('moves session through active running awaitingApproval active', () {
      const idle = AcpSession(id: _sessionId, cwd: '/workspace');
      final active = SessionStateMachine.activate(idle);
      final running = SessionStateMachine.startTurn(
        active.stateOrThrow,
        _pendingTurn,
      );
      final awaitingApproval = SessionStateMachine.requestApproval(
        running.stateOrThrow,
        _approval,
      );
      final approved = SessionStateMachine.selectApproval(
        awaitingApproval.stateOrThrow,
        approvalId: _approval.id,
        optionId: const PermissionOptionId('allow-once'),
      );
      final completed = SessionStateMachine.completeTurn(
        approved.stateOrThrow,
        stopReason: StopReason.endTurn,
      );

      expect(active.stateOrThrow.status, SessionLifecycleStatus.active);
      expect(running.stateOrThrow.status, SessionLifecycleStatus.runningTurn);
      expect(
        awaitingApproval.stateOrThrow.status,
        SessionLifecycleStatus.awaitingApproval,
      );
      expect(approved.stateOrThrow.status, SessionLifecycleStatus.runningTurn);
      expect(completed.stateOrThrow.status, SessionLifecycleStatus.active);
      expect(
        completed.stateOrThrow.turns.single.status,
        PromptTurnStatus.completed,
      );
    });

    test('rejects a second active turn', () {
      final running = SessionStateMachine.startTurn(
        const AcpSession(id: _sessionId, cwd: '/workspace'),
        _pendingTurn,
      );
      final secondTurn = SessionStateMachine.startTurn(
        running.stateOrThrow,
        _secondPendingTurn,
      );

      expect(secondTurn, isA<RejectedStateTransition<AcpSession>>());
    });

    test('cancels pending approvals when a turn is cancelled', () {
      final running = SessionStateMachine.startTurn(
        const AcpSession(id: _sessionId, cwd: '/workspace'),
        _pendingTurn,
      );
      final awaitingApproval = SessionStateMachine.requestApproval(
        running.stateOrThrow,
        _approval,
      );
      final cancelled = SessionStateMachine.cancelTurn(
        awaitingApproval.stateOrThrow,
      ).stateOrThrow;

      expect(cancelled.status, SessionLifecycleStatus.active);
      expect(cancelled.turns.single.status, PromptTurnStatus.cancelled);
      expect(
        cancelled.turns.single.approvals[_approval.id]?.status,
        ApprovalStatus.cancelled,
      );
    });

    test('ignores updates when no turn is active', () {
      final result = SessionStateMachine.applyUpdate(
        const AcpSession(id: _sessionId, cwd: '/workspace'),
        const SessionUpdate.agentMessageChunk(
          content: ContentBlock.text(text: 'late'),
        ),
      );

      expect(result, isA<IgnoredStateTransition<AcpSession>>());
    });

    test('keeps cancelled turn terminal when late update arrives', () {
      final running = SessionStateMachine.startTurn(
        const AcpSession(id: _sessionId, cwd: '/workspace'),
        _pendingTurn,
      );
      final cancelled = SessionStateMachine.cancelTurn(
        running.stateOrThrow,
      ).stateOrThrow;
      final late = SessionStateMachine.applyUpdate(
        cancelled,
        const SessionUpdate.agentMessageChunk(
          content: ContentBlock.text(text: 'late'),
        ),
      );

      expect(late, isA<IgnoredStateTransition<AcpSession>>());
      expect(late.stateOrThrow.status, SessionLifecycleStatus.active);
      expect(late.stateOrThrow.turns.single.status, PromptTurnStatus.cancelled);
      expect(late.stateOrThrow.turns.single.updates, isEmpty);
    });
  });
}

const _sessionId = SessionId('session-1');

const _pendingTurn = PromptTurn(
  id: PromptTurnId('turn-1'),
  sessionId: _sessionId,
  prompt: [ContentBlock.text(text: 'hello')],
);

const _secondPendingTurn = PromptTurn(
  id: PromptTurnId('turn-2'),
  sessionId: _sessionId,
  prompt: [ContentBlock.text(text: 'again')],
);

const _approval = ApprovalRequest(
  id: ApprovalRequestId('approval-1'),
  sessionId: _sessionId,
  turnId: PromptTurnId('turn-1'),
  toolCall: ToolCallRecord(
    id: ToolCallId('tool-1'),
    title: 'Run command',
    kind: ToolKind.execute,
    riskLevel: ApprovalRiskLevel.shell,
  ),
  options: [
    PermissionOption(
      optionId: PermissionOptionId('allow-once'),
      name: 'Allow once',
      kind: PermissionOptionKind.allowOnce,
    ),
  ],
);
