import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'approval_policy.dart';
import 'domain_models.dart';

part 'state_machines.freezed.dart';

class StateTransitionException implements Exception {
  const StateTransitionException(this.message);

  final String message;

  @override
  String toString() => 'StateTransitionException: $message';
}

@freezed
sealed class StateTransitionResult<T> with _$StateTransitionResult<T> {
  const StateTransitionResult._();

  const factory StateTransitionResult.applied({required T state}) =
      AppliedStateTransition<T>;

  const factory StateTransitionResult.ignored({
    required T state,
    required String reason,
  }) = IgnoredStateTransition<T>;

  const factory StateTransitionResult.rejected({required String reason}) =
      RejectedStateTransition<T>;

  bool get isApplied => this is AppliedStateTransition<T>;

  T get stateOrThrow {
    return switch (this) {
      AppliedStateTransition<T>(:final state) ||
      IgnoredStateTransition<T>(:final state) => state,
      RejectedStateTransition<T>(:final reason) =>
        throw StateTransitionException(reason),
    };
  }
}

@freezed
sealed class ConnectionStateEvent with _$ConnectionStateEvent {
  const factory ConnectionStateEvent.connect() = ConnectionConnectRequested;

  const factory ConnectionStateEvent.initialize() =
      ConnectionInitializeRequested;

  const factory ConnectionStateEvent.ready({
    required ProtocolVersion protocolVersion,
    Implementation? agentInfo,
    @Default(AgentCapabilities()) AgentCapabilities capabilities,
  }) = ConnectionReadyReceived;

  const factory ConnectionStateEvent.fail({
    required ConnectionFailureReason reason,
    required String message,
    Object? cause,
  }) = ConnectionFailureReceived;

  const factory ConnectionStateEvent.disconnect() =
      ConnectionDisconnectReceived;
}

@freezed
sealed class PromptTurnStateEvent with _$PromptTurnStateEvent {
  const factory PromptTurnStateEvent.start({DateTime? startedAt}) =
      PromptTurnStartRequested;

  const factory PromptTurnStateEvent.update({required SessionUpdate update}) =
      PromptTurnUpdateReceived;

  const factory PromptTurnStateEvent.requestApproval({
    required ApprovalRequest approval,
  }) = PromptTurnApprovalRequested;

  const factory PromptTurnStateEvent.selectApproval({
    required ApprovalRequestId approvalId,
    required PermissionOptionId optionId,
    DateTime? resolvedAt,
  }) = PromptTurnApprovalSelected;

  const factory PromptTurnStateEvent.cancelApproval({
    required ApprovalRequestId approvalId,
    DateTime? resolvedAt,
  }) = PromptTurnApprovalCancelled;

  const factory PromptTurnStateEvent.complete({
    required StopReason stopReason,
    DateTime? completedAt,
  }) = PromptTurnCompleted;

  const factory PromptTurnStateEvent.fail({
    required String message,
    DateTime? completedAt,
  }) = PromptTurnFailed;

  const factory PromptTurnStateEvent.cancel({DateTime? completedAt}) =
      PromptTurnCancelled;
}

@freezed
sealed class SessionStateEvent with _$SessionStateEvent {
  const factory SessionStateEvent.activate({DateTime? updatedAt}) =
      SessionActivateRequested;

  const factory SessionStateEvent.startTurn({
    required PromptTurn turn,
    DateTime? startedAt,
  }) = SessionTurnStartRequested;

  const factory SessionStateEvent.update({required SessionUpdate update}) =
      SessionUpdateReceived;

  const factory SessionStateEvent.requestApproval({
    required ApprovalRequest approval,
  }) = SessionApprovalRequested;

  const factory SessionStateEvent.selectApproval({
    required ApprovalRequestId approvalId,
    required PermissionOptionId optionId,
    DateTime? resolvedAt,
  }) = SessionApprovalSelected;

  const factory SessionStateEvent.cancelApproval({
    required ApprovalRequestId approvalId,
    DateTime? resolvedAt,
  }) = SessionApprovalCancelled;

  const factory SessionStateEvent.completeTurn({
    required StopReason stopReason,
    DateTime? completedAt,
  }) = SessionTurnCompleted;

  const factory SessionStateEvent.failTurn({
    required String message,
    DateTime? completedAt,
  }) = SessionTurnFailed;

  const factory SessionStateEvent.cancelTurn({DateTime? completedAt}) =
      SessionTurnCancelled;
}

class ConnectionStateMachine {
  const ConnectionStateMachine._();

  static StateTransitionResult<ClientConnectionState> reduce(
    ClientConnectionState state,
    ConnectionStateEvent event,
  ) {
    return switch (event) {
      ConnectionConnectRequested() => _connect(state),
      ConnectionInitializeRequested() => _initialize(state),
      ConnectionReadyReceived(
        :final protocolVersion,
        :final agentInfo,
        :final capabilities,
      ) =>
        _ready(
          state,
          protocolVersion: protocolVersion,
          agentInfo: agentInfo,
          capabilities: capabilities,
        ),
      ConnectionFailureReceived(:final reason, :final message, :final cause) =>
        _fail(state, reason: reason, message: message, cause: cause),
      ConnectionDisconnectReceived() => _disconnect(state),
    };
  }

  static StateTransitionResult<ClientConnectionState> connect(
    ClientConnectionState state,
  ) {
    return reduce(state, const ConnectionStateEvent.connect());
  }

  static StateTransitionResult<ClientConnectionState> initialize(
    ClientConnectionState state,
  ) {
    return reduce(state, const ConnectionStateEvent.initialize());
  }

  static StateTransitionResult<ClientConnectionState> ready(
    ClientConnectionState state, {
    required ProtocolVersion protocolVersion,
    Implementation? agentInfo,
    AgentCapabilities capabilities = const AgentCapabilities(),
  }) {
    return reduce(
      state,
      ConnectionStateEvent.ready(
        protocolVersion: protocolVersion,
        agentInfo: agentInfo,
        capabilities: capabilities,
      ),
    );
  }

  static StateTransitionResult<ClientConnectionState> fail(
    ClientConnectionState state, {
    required ConnectionFailureReason reason,
    required String message,
    Object? cause,
  }) {
    return reduce(
      state,
      ConnectionStateEvent.fail(reason: reason, message: message, cause: cause),
    );
  }

  static StateTransitionResult<ClientConnectionState> disconnect(
    ClientConnectionState state,
  ) {
    return reduce(state, const ConnectionStateEvent.disconnect());
  }

  static StateTransitionResult<ClientConnectionState> _connect(
    ClientConnectionState state,
  ) {
    return switch (state) {
      ClientConnectionDisconnected() || ClientConnectionFailed() => _applied(
        const ClientConnectionState.connecting(),
      ),
      _ => _rejected('connection is already active'),
    };
  }

  static StateTransitionResult<ClientConnectionState> _initialize(
    ClientConnectionState state,
  ) {
    return switch (state) {
      ClientConnectionConnecting() => _applied(
        const ClientConnectionState.initializing(),
      ),
      _ => _rejected('connection can initialize only after connecting'),
    };
  }

  static StateTransitionResult<ClientConnectionState> _ready(
    ClientConnectionState state, {
    required ProtocolVersion protocolVersion,
    Implementation? agentInfo,
    AgentCapabilities capabilities = const AgentCapabilities(),
  }) {
    return switch (state) {
      ClientConnectionInitializing() => _applied(
        ClientConnectionState.ready(
          protocolVersion: protocolVersion,
          agentInfo: agentInfo,
          capabilities: capabilities,
        ),
      ),
      _ => _rejected('connection can become ready only after initialization'),
    };
  }

  static StateTransitionResult<ClientConnectionState> _fail(
    ClientConnectionState state, {
    required ConnectionFailureReason reason,
    required String message,
    Object? cause,
  }) {
    return switch (state) {
      ClientConnectionDisconnected() => _rejected(
        'disconnected connection cannot fail again',
      ),
      _ => _applied(
        ClientConnectionState.failed(
          reason: reason,
          message: message,
          cause: cause,
        ),
      ),
    };
  }

  static StateTransitionResult<ClientConnectionState> _disconnect(
    ClientConnectionState state,
  ) {
    return switch (state) {
      ClientConnectionDisconnected() => _ignored(
        state,
        'connection is already disconnected',
      ),
      _ => _applied(const ClientConnectionState.disconnected()),
    };
  }
}

class PromptTurnStateMachine {
  const PromptTurnStateMachine._();

  static StateTransitionResult<PromptTurn> reduce(
    PromptTurn turn,
    PromptTurnStateEvent event,
  ) {
    return switch (event) {
      PromptTurnStartRequested(:final startedAt) => _start(
        turn,
        startedAt: startedAt,
      ),
      PromptTurnUpdateReceived(:final update) => _applyUpdate(turn, update),
      PromptTurnApprovalRequested(:final approval) => _requestApproval(
        turn,
        approval,
      ),
      PromptTurnApprovalSelected(
        :final approvalId,
        :final optionId,
        :final resolvedAt,
      ) =>
        _selectApproval(
          turn,
          approvalId: approvalId,
          optionId: optionId,
          resolvedAt: resolvedAt,
        ),
      PromptTurnApprovalCancelled(:final approvalId, :final resolvedAt) =>
        _cancelApproval(turn, approvalId: approvalId, resolvedAt: resolvedAt),
      PromptTurnCompleted(:final stopReason, :final completedAt) => _complete(
        turn,
        stopReason: stopReason,
        completedAt: completedAt,
      ),
      PromptTurnFailed(:final message, :final completedAt) => _fail(
        turn,
        message: message,
        completedAt: completedAt,
      ),
      PromptTurnCancelled(:final completedAt) => _cancel(
        turn,
        completedAt: completedAt,
      ),
    };
  }

  static StateTransitionResult<PromptTurn> start(
    PromptTurn turn, {
    DateTime? startedAt,
  }) {
    return reduce(turn, PromptTurnStateEvent.start(startedAt: startedAt));
  }

  static StateTransitionResult<PromptTurn> applyUpdate(
    PromptTurn turn,
    SessionUpdate update,
  ) {
    return reduce(turn, PromptTurnStateEvent.update(update: update));
  }

  static StateTransitionResult<PromptTurn> requestApproval(
    PromptTurn turn,
    ApprovalRequest approval,
  ) {
    return reduce(
      turn,
      PromptTurnStateEvent.requestApproval(approval: approval),
    );
  }

  static StateTransitionResult<PromptTurn> selectApproval(
    PromptTurn turn, {
    required ApprovalRequestId approvalId,
    required PermissionOptionId optionId,
    DateTime? resolvedAt,
  }) {
    return reduce(
      turn,
      PromptTurnStateEvent.selectApproval(
        approvalId: approvalId,
        optionId: optionId,
        resolvedAt: resolvedAt,
      ),
    );
  }

  static StateTransitionResult<PromptTurn> cancelApproval(
    PromptTurn turn, {
    required ApprovalRequestId approvalId,
    DateTime? resolvedAt,
  }) {
    return reduce(
      turn,
      PromptTurnStateEvent.cancelApproval(
        approvalId: approvalId,
        resolvedAt: resolvedAt,
      ),
    );
  }

  static StateTransitionResult<PromptTurn> complete(
    PromptTurn turn, {
    required StopReason stopReason,
    DateTime? completedAt,
  }) {
    return reduce(
      turn,
      PromptTurnStateEvent.complete(
        stopReason: stopReason,
        completedAt: completedAt,
      ),
    );
  }

  static StateTransitionResult<PromptTurn> fail(
    PromptTurn turn, {
    required String message,
    DateTime? completedAt,
  }) {
    return reduce(
      turn,
      PromptTurnStateEvent.fail(message: message, completedAt: completedAt),
    );
  }

  static StateTransitionResult<PromptTurn> cancel(
    PromptTurn turn, {
    DateTime? completedAt,
  }) {
    return reduce(turn, PromptTurnStateEvent.cancel(completedAt: completedAt));
  }

  static StateTransitionResult<PromptTurn> _start(
    PromptTurn turn, {
    DateTime? startedAt,
  }) {
    return switch (turn.status) {
      PromptTurnStatus.pending => _applied(
        turn.copyWith(
          status: PromptTurnStatus.running,
          startedAt: startedAt ?? turn.startedAt,
        ),
      ),
      _ => _rejected('prompt turn can start only while pending'),
    };
  }

  static StateTransitionResult<PromptTurn> _applyUpdate(
    PromptTurn turn,
    SessionUpdate update,
  ) {
    if (turn.isTerminal) {
      return _ignored(turn, 'terminal prompt turn ignores late updates');
    }

    final next = _applyUpdateToTurn(turn, update);
    if (next == turn) {
      return _ignored(
        turn,
        'duplicate session update has no new visible effect',
      );
    }

    if (next.status == PromptTurnStatus.pending) {
      return _applied(next.copyWith(status: PromptTurnStatus.running));
    }

    return _applied(next);
  }

  static StateTransitionResult<PromptTurn> _requestApproval(
    PromptTurn turn,
    ApprovalRequest approval,
  ) {
    return switch (turn.status) {
      PromptTurnStatus.running || PromptTurnStatus.awaitingApproval => _applied(
        turn.copyWith(
          status: PromptTurnStatus.awaitingApproval,
          approvals: {...turn.approvals, approval.id: approval},
        ),
      ),
      _ when turn.isTerminal => _ignored(
        turn,
        'terminal prompt turn ignores approval requests',
      ),
      PromptTurnStatus.cancelling => _rejected(
        'cancelling prompt turn cannot request approval',
      ),
      _ => _rejected('prompt turn cannot request approval before running'),
    };
  }

  static StateTransitionResult<PromptTurn> _selectApproval(
    PromptTurn turn, {
    required ApprovalRequestId approvalId,
    required PermissionOptionId optionId,
    DateTime? resolvedAt,
  }) {
    final approval = turn.approvals[approvalId];
    if (turn.isTerminal || turn.status == PromptTurnStatus.cancelling) {
      return _ignored(turn, 'ended prompt turn ignores approval selection');
    }
    if (approval == null) {
      return _ignored(turn, 'approval request is not active on this turn');
    }

    return _applied(
      _resolveApproval(
        turn,
        approval.copyWith(
          status: ApprovalStatus.selected,
          selectedOptionId: optionId,
          resolvedAt: resolvedAt ?? approval.resolvedAt,
        ),
      ),
    );
  }

  static StateTransitionResult<PromptTurn> _cancelApproval(
    PromptTurn turn, {
    required ApprovalRequestId approvalId,
    DateTime? resolvedAt,
  }) {
    final approval = turn.approvals[approvalId];
    if (turn.isTerminal || turn.status == PromptTurnStatus.cancelling) {
      return _ignored(turn, 'ended prompt turn ignores approval cancellation');
    }
    if (approval == null) {
      return _ignored(turn, 'approval request is not active on this turn');
    }

    return _applied(
      _resolveApproval(
        turn,
        approval.copyWith(
          status: ApprovalStatus.cancelled,
          resolvedAt: resolvedAt ?? approval.resolvedAt,
        ),
      ),
    );
  }

  static StateTransitionResult<PromptTurn> _complete(
    PromptTurn turn, {
    required StopReason stopReason,
    DateTime? completedAt,
  }) {
    if (turn.isTerminal) {
      return _ignored(turn, 'terminal prompt turn ignores completion');
    }

    return _applied(
      turn.copyWith(
        status: _statusForStopReason(stopReason),
        stopReason: stopReason,
        completedAt: completedAt ?? turn.completedAt,
      ),
    );
  }

  static StateTransitionResult<PromptTurn> _fail(
    PromptTurn turn, {
    required String message,
    DateTime? completedAt,
  }) {
    if (turn.isTerminal) {
      return _ignored(turn, 'terminal prompt turn ignores failure');
    }

    return _applied(
      turn.copyWith(
        status: PromptTurnStatus.failed,
        failureMessage: message,
        completedAt: completedAt ?? turn.completedAt,
      ),
    );
  }

  static StateTransitionResult<PromptTurn> _cancel(
    PromptTurn turn, {
    DateTime? completedAt,
  }) {
    if (turn.isTerminal) {
      return _ignored(turn, 'terminal prompt turn ignores cancellation');
    }
    if (turn.status == PromptTurnStatus.cancelling) {
      return _ignored(turn, 'prompt turn is already cancelling');
    }

    // The turn stays open until the agent answers its `session/prompt`
    // (05-Prompt Turn.md#cancellation): updates sent before that answer still
    // belong to it, and the answer's stop reason settles it in `_complete`.
    return _applied(
      turn.copyWith(
        status: PromptTurnStatus.cancelling,
        toolCalls: {
          for (final entry in turn.toolCalls.entries)
            entry.key: _isUnfinished(entry.value.status)
                ? entry.value.copyWith(
                    status: ToolCallStatus.failed,
                    cancelledByClient: true,
                  )
                : entry.value,
        },
        approvals: {
          for (final entry in turn.approvals.entries)
            entry.key: entry.value.isResolved
                ? entry.value
                : entry.value.copyWith(
                    status: ApprovalStatus.cancelled,
                    resolvedAt: completedAt ?? entry.value.resolvedAt,
                  ),
        },
      ),
    );
  }

  static PromptTurn _resolveApproval(
    PromptTurn turn,
    ApprovalRequest approval,
  ) {
    final approvals = {...turn.approvals, approval.id: approval};
    final hasPending = approvals.values.any((approval) => !approval.isResolved);

    return turn.copyWith(
      status: hasPending
          ? PromptTurnStatus.awaitingApproval
          : PromptTurnStatus.running,
      approvals: approvals,
    );
  }
}

class SessionStateMachine {
  const SessionStateMachine._();

  static StateTransitionResult<AcpSession> reduce(
    AcpSession session,
    SessionStateEvent event,
  ) {
    return switch (event) {
      SessionActivateRequested(:final updatedAt) => _activate(
        session,
        updatedAt: updatedAt,
      ),
      SessionTurnStartRequested(:final turn, :final startedAt) => _startTurn(
        session,
        turn,
        startedAt: startedAt,
      ),
      SessionUpdateReceived(:final update) => _applyUpdate(session, update),
      SessionApprovalRequested(:final approval) => _requestApproval(
        session,
        approval,
      ),
      SessionApprovalSelected(
        :final approvalId,
        :final optionId,
        :final resolvedAt,
      ) =>
        _selectApproval(
          session,
          approvalId: approvalId,
          optionId: optionId,
          resolvedAt: resolvedAt,
        ),
      SessionApprovalCancelled(:final approvalId, :final resolvedAt) =>
        _cancelApproval(
          session,
          approvalId: approvalId,
          resolvedAt: resolvedAt,
        ),
      SessionTurnCompleted(:final stopReason, :final completedAt) =>
        _completeTurn(
          session,
          stopReason: stopReason,
          completedAt: completedAt,
        ),
      SessionTurnFailed(:final message, :final completedAt) => _failTurn(
        session,
        message: message,
        completedAt: completedAt,
      ),
      SessionTurnCancelled(:final completedAt) => _cancelTurn(
        session,
        completedAt: completedAt,
      ),
    };
  }

  static StateTransitionResult<AcpSession> activate(
    AcpSession session, {
    DateTime? updatedAt,
  }) {
    return reduce(session, SessionStateEvent.activate(updatedAt: updatedAt));
  }

  static StateTransitionResult<AcpSession> startTurn(
    AcpSession session,
    PromptTurn turn, {
    DateTime? startedAt,
  }) {
    return reduce(
      session,
      SessionStateEvent.startTurn(turn: turn, startedAt: startedAt),
    );
  }

  static StateTransitionResult<AcpSession> applyUpdate(
    AcpSession session,
    SessionUpdate update,
  ) {
    return reduce(session, SessionStateEvent.update(update: update));
  }

  /// Раскладывает историю, повторённую агентом в ответ на `session/load`,
  /// в завершённые ходы сессии.
  ///
  /// Почему: при `session/load` агент шлёт всю переписку уведомлениями
  /// `session/update` до ответа (`03-Session Setup.md#loading-a-session`,
  /// `agent-core/13-acp-adapter.md` §13.5), а в сессии клиента нет активного
  /// хода, к которому их можно применить, — [applyUpdate] их бы отбросил.
  ///
  /// Для чего: восстановить видимую историю загруженной сессии. ACP не
  /// передаёт в реплее границы ходов и `stopReason`, поэтому ход открывает
  /// `user_message_chunk`, пришедший после ответа агента (подряд идущие
  /// чанки пользователя — одна реплика в `PromptTurn.prompt`, а не в
  /// `updates`). Ход реплея закрыт как [PromptTurnStatus.completed] без
  /// `stopReason`: это прошлое, и показывать его выполняющимся нельзя
  /// (`session-lifecycle.md` §51). Сессионные обновления применяются к
  /// сессии, как в [applyUpdate].
  ///
  /// Как использовать: приложение вызывает после успешного ответа
  /// `session/load` с буфером обновлений этой сессии в порядке прихода;
  /// [nextTurnId] выдаёт идентификаторы ходов. Ходы добавляются к
  /// `session.turns`; сессия должна быть без активного хода.
  static AcpSession replayHistory(
    AcpSession session,
    List<SessionUpdate> updates, {
    required PromptTurnId Function() nextTurnId,
  }) {
    var current = session;
    PromptTurn? turn;

    void closeTurn() {
      final closed = turn;
      if (closed == null) {
        return;
      }
      current = current.copyWith(
        turns: [
          ...current.turns,
          closed.copyWith(status: PromptTurnStatus.completed),
        ],
      );
      turn = null;
    }

    for (final update in updates) {
      final scoped = _applySessionScopedUpdate(current, update);
      if (scoped != null) {
        current = scoped;
        continue;
      }

      if (update case UserMessageChunk(:final content)) {
        final open = turn;
        if (open != null && open.updates.isEmpty) {
          turn = open.copyWith(prompt: [...open.prompt, content]);
          continue;
        }
        closeTurn();
        turn = PromptTurn(
          id: nextTurnId(),
          sessionId: session.id,
          prompt: [content],
          status: PromptTurnStatus.running,
        );
        continue;
      }

      turn = _applyUpdateToTurn(
        turn ??
            PromptTurn(
              id: nextTurnId(),
              sessionId: session.id,
              prompt: const [],
              status: PromptTurnStatus.running,
            ),
        update,
      );
    }
    closeTurn();

    return current.copyWith(status: SessionLifecycleStatus.active);
  }

  static StateTransitionResult<AcpSession> requestApproval(
    AcpSession session,
    ApprovalRequest approval,
  ) {
    return reduce(
      session,
      SessionStateEvent.requestApproval(approval: approval),
    );
  }

  static StateTransitionResult<AcpSession> selectApproval(
    AcpSession session, {
    required ApprovalRequestId approvalId,
    required PermissionOptionId optionId,
    DateTime? resolvedAt,
  }) {
    return reduce(
      session,
      SessionStateEvent.selectApproval(
        approvalId: approvalId,
        optionId: optionId,
        resolvedAt: resolvedAt,
      ),
    );
  }

  static StateTransitionResult<AcpSession> cancelApproval(
    AcpSession session, {
    required ApprovalRequestId approvalId,
    DateTime? resolvedAt,
  }) {
    return reduce(
      session,
      SessionStateEvent.cancelApproval(
        approvalId: approvalId,
        resolvedAt: resolvedAt,
      ),
    );
  }

  static StateTransitionResult<AcpSession> completeTurn(
    AcpSession session, {
    required StopReason stopReason,
    DateTime? completedAt,
  }) {
    return reduce(
      session,
      SessionStateEvent.completeTurn(
        stopReason: stopReason,
        completedAt: completedAt,
      ),
    );
  }

  static StateTransitionResult<AcpSession> failTurn(
    AcpSession session, {
    required String message,
    DateTime? completedAt,
  }) {
    return reduce(
      session,
      SessionStateEvent.failTurn(message: message, completedAt: completedAt),
    );
  }

  static StateTransitionResult<AcpSession> cancelTurn(
    AcpSession session, {
    DateTime? completedAt,
  }) {
    return reduce(
      session,
      SessionStateEvent.cancelTurn(completedAt: completedAt),
    );
  }

  static StateTransitionResult<AcpSession> _activate(
    AcpSession session, {
    DateTime? updatedAt,
  }) {
    return switch (session.status) {
      SessionLifecycleStatus.idle || SessionLifecycleStatus.active => _applied(
        session.copyWith(
          status: SessionLifecycleStatus.active,
          updatedAt: updatedAt ?? session.updatedAt,
        ),
      ),
      _ => _rejected(
        'session cannot become active from ${session.status.name}',
      ),
    };
  }

  static StateTransitionResult<AcpSession> _startTurn(
    AcpSession session,
    PromptTurn turn, {
    DateTime? startedAt,
  }) {
    if (session.status != SessionLifecycleStatus.idle &&
        session.status != SessionLifecycleStatus.active) {
      return _rejected('session already has an active prompt turn');
    }

    final startedTurn = PromptTurnStateMachine.start(
      turn,
      startedAt: startedAt,
    );
    if (startedTurn case RejectedStateTransition<PromptTurn>(:final reason)) {
      return _rejected(reason);
    }

    return _applied(
      session.copyWith(
        status: SessionLifecycleStatus.runningTurn,
        turns: [...session.turns, startedTurn.stateOrThrow],
        updatedAt: startedAt ?? session.updatedAt,
      ),
    );
  }

  static StateTransitionResult<AcpSession> _applyUpdate(
    AcpSession session,
    SessionUpdate update,
  ) {
    // Сессионные обновления (команды, опции, режим, заголовок) относятся к
    // сессии, а не к ходу: ACP разрешает их «в любой момент сессии», в том
    // числе до первого хода и в реплее `session/load`
    // (`14-Slash Commands.md`, `13-Session Config Options.md`,
    // `12-Session Model.md`, `04-Session List.md#updating-session-metadata`,
    // `03-Session Setup.md#loading-a-session`).
    // Применяем их к сессии всегда, а при активном ходе ещё и проводим через
    // ход, чтобы они оставались в его журнале протокола.
    final scoped = _applySessionScopedUpdate(session, update);
    if (scoped != null) {
      final activeTurn = scoped.activeTurn;
      if (activeTurn == null) {
        return _applied(scoped);
      }

      final turn = PromptTurnStateMachine.applyUpdate(activeTurn, update);
      return _sessionResultFromTurnResult(scoped, turn);
    }

    final activeTurn = session.activeTurn;
    if (activeTurn == null) {
      return _ignored(session, 'session has no active prompt turn');
    }

    final turn = PromptTurnStateMachine.applyUpdate(activeTurn, update);
    return _sessionResultFromTurnResult(session, turn);
  }

  static StateTransitionResult<AcpSession> _requestApproval(
    AcpSession session,
    ApprovalRequest approval,
  ) {
    final activeTurn = session.activeTurn;
    if (activeTurn == null) {
      return _ignored(session, 'session has no active prompt turn');
    }

    final turn = PromptTurnStateMachine.requestApproval(activeTurn, approval);
    return switch (turn) {
      RejectedStateTransition<PromptTurn>(:final reason) => _rejected(reason),
      IgnoredStateTransition<PromptTurn>(:final state, :final reason) =>
        _ignored(_replaceTurn(session, state), reason),
      AppliedStateTransition<PromptTurn>(:final state) => _applied(
        _replaceTurn(
          session,
          state,
          status: SessionLifecycleStatus.awaitingApproval,
        ),
      ),
    };
  }

  static StateTransitionResult<AcpSession> _selectApproval(
    AcpSession session, {
    required ApprovalRequestId approvalId,
    required PermissionOptionId optionId,
    DateTime? resolvedAt,
  }) {
    final activeTurn = session.activeTurn;
    if (activeTurn == null) {
      return _ignored(session, 'session has no active prompt turn');
    }

    final turn = PromptTurnStateMachine.selectApproval(
      activeTurn,
      approvalId: approvalId,
      optionId: optionId,
      resolvedAt: resolvedAt,
    );

    return _sessionResultFromTurnResult(session, turn);
  }

  static StateTransitionResult<AcpSession> _cancelApproval(
    AcpSession session, {
    required ApprovalRequestId approvalId,
    DateTime? resolvedAt,
  }) {
    final activeTurn = session.activeTurn;
    if (activeTurn == null) {
      return _ignored(session, 'session has no active prompt turn');
    }

    final turn = PromptTurnStateMachine.cancelApproval(
      activeTurn,
      approvalId: approvalId,
      resolvedAt: resolvedAt,
    );

    return _sessionResultFromTurnResult(session, turn);
  }

  static StateTransitionResult<AcpSession> _completeTurn(
    AcpSession session, {
    required StopReason stopReason,
    DateTime? completedAt,
  }) {
    final activeTurn = session.activeTurn;
    if (activeTurn == null) {
      return _ignored(session, 'session has no active prompt turn');
    }

    final turn = PromptTurnStateMachine.complete(
      activeTurn,
      stopReason: stopReason,
      completedAt: completedAt,
    );
    return switch (turn) {
      RejectedStateTransition<PromptTurn>(:final reason) => _rejected(reason),
      IgnoredStateTransition<PromptTurn>(:final state, :final reason) =>
        _ignored(_replaceTurn(session, state), reason),
      AppliedStateTransition<PromptTurn>(:final state) => _applied(
        _replaceTurn(session, state, status: SessionLifecycleStatus.active),
      ),
    };
  }

  static StateTransitionResult<AcpSession> _failTurn(
    AcpSession session, {
    required String message,
    DateTime? completedAt,
  }) {
    final activeTurn = session.activeTurn;
    if (activeTurn == null) {
      return _applied(session.copyWith(status: SessionLifecycleStatus.failed));
    }

    final turn = PromptTurnStateMachine.fail(
      activeTurn,
      message: message,
      completedAt: completedAt,
    );
    return switch (turn) {
      RejectedStateTransition<PromptTurn>(:final reason) => _rejected(reason),
      IgnoredStateTransition<PromptTurn>(:final state, :final reason) =>
        _ignored(_replaceTurn(session, state), reason),
      AppliedStateTransition<PromptTurn>(:final state) => _applied(
        _replaceTurn(session, state, status: SessionLifecycleStatus.failed),
      ),
    };
  }

  static StateTransitionResult<AcpSession> _cancelTurn(
    AcpSession session, {
    DateTime? completedAt,
  }) {
    final activeTurn = session.activeTurn;
    if (activeTurn == null) {
      return _ignored(session, 'session has no active prompt turn');
    }

    final turn = PromptTurnStateMachine.cancel(
      activeTurn,
      completedAt: completedAt,
    );
    return switch (turn) {
      RejectedStateTransition<PromptTurn>(:final reason) => _rejected(reason),
      IgnoredStateTransition<PromptTurn>(:final state, :final reason) =>
        _ignored(_replaceTurn(session, state), reason),
      AppliedStateTransition<PromptTurn>(:final state) => _applied(
        _replaceTurn(session, state),
      ),
    };
  }

  static AcpSession _replaceTurn(
    AcpSession session,
    PromptTurn turn, {
    SessionLifecycleStatus? status,
  }) {
    final turns = [
      for (final existing in session.turns)
        if (existing.id == turn.id) turn else existing,
    ];

    return session.copyWith(
      status: status ?? _sessionStatusForTurn(turn),
      turns: turns,
      updatedAt: turn.completedAt ?? turn.startedAt ?? session.updatedAt,
    );
  }

  /// Применяет обновление уровня сессии; `null` — обновление относится к
  /// ходу. `session_info_update` без `title` заголовок не стирает: в ACP
  /// отсутствующее поле означает «без изменений»
  /// (`04-Session List.md#updating-session-metadata`), а `null` («стереть»)
  /// модель `acp_protocol` от отсутствия не отличает.
  static AcpSession? _applySessionScopedUpdate(
    AcpSession session,
    SessionUpdate update,
  ) {
    return switch (update) {
      AvailableCommandsUpdate(:final availableCommands) => session.copyWith(
        availableCommands: availableCommands,
      ),
      ConfigOptionUpdate(:final configOptions) => session.copyWith(
        configOptions: configOptions,
      ),
      CurrentModeUpdate(:final currentModeId) => session.copyWith(
        modes: session.modes?.copyWith(currentModeId: currentModeId),
      ),
      SessionInfoUpdate(:final title) => session.copyWith(
        title: title ?? session.title,
      ),
      _ => null,
    };
  }

  static StateTransitionResult<AcpSession> _sessionResultFromTurnResult(
    AcpSession session,
    StateTransitionResult<PromptTurn> turn,
  ) {
    return switch (turn) {
      RejectedStateTransition<PromptTurn>(:final reason) => _rejected(reason),
      IgnoredStateTransition<PromptTurn>(:final state, :final reason) =>
        _ignored(_replaceTurn(session, state), reason),
      AppliedStateTransition<PromptTurn>(:final state) => _applied(
        _replaceTurn(session, state),
      ),
    };
  }
}

StateTransitionResult<T> _applied<T>(T state) {
  return StateTransitionResult.applied(state: state);
}

StateTransitionResult<T> _ignored<T>(T state, String reason) {
  return StateTransitionResult.ignored(state: state, reason: reason);
}

StateTransitionResult<T> _rejected<T>(String reason) {
  return StateTransitionResult.rejected(reason: reason);
}

PromptTurn _applyUpdateToTurn(PromptTurn turn, SessionUpdate update) {
  return switch (update) {
    ToolCallSessionUpdate(:final toolCall) => _applyToolCallUpdate(
      turn,
      update,
      ToolCallRecord.fromToolCall(
        toolCall,
        riskLevel: ApprovalPolicy.classifyToolCall(toolCall),
      ),
    ),
    ToolCallUpdateSessionUpdate(:final toolCallUpdate) => _applyToolCallUpdate(
      turn,
      update,
      _mergeToolCallUpdate(
        turn.toolCalls[toolCallUpdate.toolCallId],
        toolCallUpdate,
      ),
    ),
    _ when turn.updates.contains(update) => turn,
    _ => turn.copyWith(updates: [...turn.updates, update]),
  };
}

PromptTurn _applyToolCallUpdate(
  PromptTurn turn,
  SessionUpdate update,
  ToolCallRecord record,
) {
  if (turn.toolCalls[record.id] == record) {
    return turn;
  }

  return turn.copyWith(
    updates: [...turn.updates, update],
    toolCalls: {...turn.toolCalls, record.id: record},
  );
}

ToolCallRecord _mergeToolCallUpdate(
  ToolCallRecord? current,
  ToolCallUpdate update,
) {
  // A call the client cancelled stays ended unless the agent reports how it
  // actually ended: a late non-final status does not put it back to work.
  final cancelledByClient = current?.cancelledByClient ?? false;
  final status = cancelledByClient && _isUnfinished(update.status)
      ? current!.status
      : update.status ?? current?.status ?? ToolCallStatus.pending;
  return ToolCallRecord(
    id: update.toolCallId,
    title: update.title ?? current?.title ?? update.toolCallId.value,
    kind: update.kind ?? current?.kind ?? ToolKind.other,
    status: status,
    cancelledByClient: cancelledByClient && status != ToolCallStatus.completed,
    riskLevel: ApprovalPolicy.max(
      current?.riskLevel ?? ApprovalRiskLevel.readOnly,
      ApprovalPolicy.classifyToolCallUpdate(update),
    ),
    content: update.content ?? current?.content ?? const [],
    locations: update.locations ?? current?.locations ?? const [],
    rawInput: update.rawInput ?? current?.rawInput,
    rawOutput: update.rawOutput ?? current?.rawOutput,
    startedAt: current?.startedAt,
    completedAt: current?.completedAt,
  );
}

bool _isUnfinished(ToolCallStatus? status) => switch (status) {
  ToolCallStatus.pending || ToolCallStatus.inProgress => true,
  ToolCallStatus.completed || ToolCallStatus.failed || null => false,
};

PromptTurnStatus _statusForStopReason(StopReason stopReason) {
  return switch (stopReason) {
    StopReason.endTurn => PromptTurnStatus.completed,
    StopReason.maxTokens ||
    StopReason.maxTurnRequests => PromptTurnStatus.maxed,
    StopReason.refusal => PromptTurnStatus.refused,
    StopReason.cancelled => PromptTurnStatus.cancelled,
  };
}

SessionLifecycleStatus _sessionStatusForTurn(PromptTurn turn) {
  return switch (turn.status) {
    PromptTurnStatus.awaitingApproval =>
      SessionLifecycleStatus.awaitingApproval,
    PromptTurnStatus.pending ||
    PromptTurnStatus.running => SessionLifecycleStatus.runningTurn,
    PromptTurnStatus.cancelling => SessionLifecycleStatus.cancellingTurn,
    PromptTurnStatus.failed => SessionLifecycleStatus.failed,
    PromptTurnStatus.completed ||
    PromptTurnStatus.refused ||
    PromptTurnStatus.maxed ||
    PromptTurnStatus.cancelled => SessionLifecycleStatus.active,
  };
}
