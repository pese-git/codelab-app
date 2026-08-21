import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';

import '../domain/domain_models.dart';
import '../domain/state_machines.dart';
import 'application_models.dart';

final class AcpClientApplicationException implements Exception {
  const AcpClientApplicationException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AcpClientApplicationException: $message';
}

final class MissingAcpSessionException extends AcpClientApplicationException {
  const MissingAcpSessionException({
    required this.sessionId,
    required String message,
  }) : super(message);

  final SessionId sessionId;
}

final class AcpClientApplication {
  AcpClientApplication({required AcpTransport transport})
    : _transport = transport {
    _inboundSubscription = _transport.inbound.listen(_handleInboundMessage);
    _eventSubscription = _transport.events.listen(_handleTransportEvent);
  }

  final AcpTransport _transport;
  final _pendingRequests = <JsonRpcId, _PendingAcpRequest>{};
  final _pendingPermissionRequests =
      <ApprovalRequestId, _PendingPermissionRequest>{};
  final _sessions = <SessionId, AcpSession>{};
  final _sessionController = StreamController<AcpSession>.broadcast(sync: true);

  late final StreamSubscription<JsonRpcMessage> _inboundSubscription;
  late final StreamSubscription<AcpTransportEvent> _eventSubscription;

  var _nextRequestId = 1;
  var _nextTurnId = 1;
  var _nextDiagnosticId = 1;

  Stream<AcpSession> get sessionChanges => _sessionController.stream;

  List<AcpSession> get sessions => List.unmodifiable(_sessions.values);

  AcpSession? sessionById(SessionId sessionId) => _sessions[sessionId];

  Future<AcpSession> createSession(CreateSessionCommand command) async {
    final response = await _sendRequest<NewSessionResponse>(
      method: sessionNewMethod,
      params: NewSessionRequest(
        cwd: command.cwd,
        mcpServers: command.mcpServers,
        meta: command.meta,
      ),
    );
    final session = AcpSession(
      id: response.sessionId,
      cwd: command.cwd,
      status: SessionLifecycleStatus.active,
      modes: response.modes,
      configOptions: response.configOptions,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _storeSession(session);
    return session;
  }

  Future<PromptTurn> sendPrompt(SendPromptCommand command) async {
    final session = _requireSession(command.sessionId);
    final turn = PromptTurn(
      id: PromptTurnId('turn-${_nextTurnId++}'),
      sessionId: command.sessionId,
      prompt: command.prompt,
    );
    final runningSession = SessionStateMachine.startTurn(
      session,
      turn,
      startedAt: DateTime.now(),
    ).stateOrThrow;

    _storeSession(runningSession);

    try {
      final response = await _sendRequest<PromptResponse>(
        method: sessionPromptMethod,
        params: PromptRequest(
          sessionId: command.sessionId,
          prompt: command.prompt,
          meta: command.meta,
        ),
      );
      final completedSession = SessionStateMachine.completeTurn(
        _requireSession(command.sessionId),
        stopReason: response.stopReason,
        completedAt: DateTime.now(),
      ).stateOrThrow;

      _storeSession(completedSession);
      return completedSession.turns.last;
    } on Object catch (error) {
      final failedSession = SessionStateMachine.failTurn(
        _requireSession(command.sessionId),
        message: error.toString(),
        completedAt: DateTime.now(),
      ).stateOrThrow;

      _storeSession(failedSession);
      rethrow;
    }
  }

  Future<PromptTurn> cancelTurn(CancelTurnCommand command) async {
    final session = _requireSession(command.sessionId);
    final activeTurn = session.activeTurn;
    if (activeTurn == null) {
      throw const StateTransitionException(
        'session has no active prompt turn to cancel',
      );
    }

    final pendingApprovals = activeTurn.approvals.values
        .where((approval) => !approval.isResolved)
        .toList(growable: false);

    await _sendNotification(
      method: sessionCancelMethod,
      params: CancelNotification(
        sessionId: command.sessionId,
        meta: command.meta,
      ),
    );

    for (final approval in pendingApprovals) {
      await _sendPermissionResponse(
        approval.id,
        const RequestPermissionResponse(
          outcome: RequestPermissionOutcome.cancelled(),
        ),
      );
    }

    final cancelled = SessionStateMachine.cancelTurn(
      _requireSession(command.sessionId),
      completedAt: DateTime.now(),
    ).stateOrThrow;

    _storeSession(cancelled);
    return cancelled.turns.last;
  }

  Future<ApprovalRequest> respondToPermission(
    RespondToPermissionCommand command,
  ) async {
    final session = _requireSession(command.sessionId);
    final activeTurn = session.activeTurn;
    final approval = activeTurn?.approvals[command.approvalId];
    if (activeTurn == null || approval == null || approval.isResolved) {
      throw const StateTransitionException('permission request is not pending');
    }

    final response = switch (command) {
      SelectPermissionCommand(:final optionId, :final meta) => () {
        _requirePermissionOption(approval, optionId);
        return RequestPermissionResponse(
          outcome: RequestPermissionOutcome.selected(
            optionId: optionId,
            meta: meta,
          ),
        );
      }(),
      CancelPermissionCommand(:final meta) => RequestPermissionResponse(
        outcome: const RequestPermissionOutcome.cancelled(),
        meta: meta,
      ),
    };

    await _sendPermissionResponse(command.approvalId, response);

    final resolved = switch (command) {
      SelectPermissionCommand(:final optionId) =>
        SessionStateMachine.selectApproval(
          _requireSession(command.sessionId),
          approvalId: command.approvalId,
          optionId: optionId,
          resolvedAt: DateTime.now(),
        ).stateOrThrow,
      CancelPermissionCommand() => SessionStateMachine.cancelApproval(
        _requireSession(command.sessionId),
        approvalId: command.approvalId,
        resolvedAt: DateTime.now(),
      ).stateOrThrow,
    };

    _storeSession(resolved);
    return resolved.turns.last.approvals[command.approvalId]!;
  }

  Future<void> dispose() async {
    await _inboundSubscription.cancel();
    await _eventSubscription.cancel();
    for (final pending in _pendingRequests.values) {
      pending.completeError(
        const AcpClientApplicationException('ACP application disposed.'),
      );
    }
    _pendingRequests.clear();
    _pendingPermissionRequests.clear();
    await _sessionController.close();
  }

  Future<T> _sendRequest<T>({
    required String method,
    required Object params,
  }) async {
    final id = JsonRpcId.integer(_nextRequestId++);
    final pending = _PendingAcpRequest(method);
    _pendingRequests[id] = pending;

    try {
      await _transport.send(
        encodeAcpRequest(id: id, method: method, params: params),
      );
    } on Object catch (error) {
      _pendingRequests.remove(id);
      throw AcpClientApplicationException(
        'Failed to send ACP request $method.',
        cause: error,
      );
    }

    final result = await pending.future;
    if (result is T) {
      return result as T;
    }

    throw AcpClientApplicationException(
      'ACP response for $method decoded to ${result.runtimeType}, expected $T.',
    );
  }

  Future<void> _sendNotification({
    required String method,
    required Object params,
  }) async {
    try {
      await _transport.send(
        encodeAcpNotification(method: method, params: params),
      );
    } on Object catch (error) {
      throw AcpClientApplicationException(
        'Failed to send ACP notification $method.',
        cause: error,
      );
    }
  }

  void _handleInboundMessage(JsonRpcMessage message) {
    switch (message) {
      case JsonRpcResponse():
        _completePendingRequest(message);
      case JsonRpcRequest(method: sessionRequestPermissionMethod):
        _handlePermissionRequest(message);
      case JsonRpcNotification(method: sessionUpdateMethod):
        _handleSessionUpdate(message);
      case JsonRpcNotification():
      case JsonRpcRequest():
        break;
    }
  }

  void _completePendingRequest(JsonRpcResponse response) {
    final pending = _pendingRequests.remove(response.id);
    if (pending == null) {
      return;
    }
    if (response.error != null) {
      pending.completeError(
        AcpClientApplicationException(
          'ACP request ${pending.method} failed: ${response.error?.message}',
          cause: response.error,
        ),
      );
      return;
    }

    try {
      pending.complete(
        decodeAcpResponseResult(method: pending.method, response: response),
      );
    } on Object catch (error) {
      pending.completeError(
        AcpClientApplicationException(
          'Failed to decode ACP response for ${pending.method}.',
          cause: error,
        ),
      );
    }
  }

  void _handlePermissionRequest(JsonRpcRequest request) {
    try {
      final permissionRequest =
          decodeAcpRequestParams(request) as RequestPermissionRequest;
      final session = _sessions[permissionRequest.sessionId];
      final activeTurn = session?.activeTurn;
      if (session == null || activeTurn == null) {
        _sendCancelledPermissionResponse(request.id);
        return;
      }

      final approval = ApprovalRequest(
        id: _approvalRequestId(request.id),
        sessionId: permissionRequest.sessionId,
        turnId: activeTurn.id,
        toolCall: _toolCallRecordFromUpdate(permissionRequest.toolCall),
        options: permissionRequest.options,
        requestedAt: DateTime.now(),
      );
      final next = SessionStateMachine.requestApproval(
        session,
        approval,
      ).stateOrThrow;

      _pendingPermissionRequests[approval.id] = _PendingPermissionRequest(
        requestId: request.id,
      );
      _storeSession(next);
    } on Object {
      _sendCancelledPermissionResponse(request.id);
      // Structured diagnostics and protocol-error surfacing arrive in task 4.8.
    }
  }

  void _handleSessionUpdate(JsonRpcNotification notification) {
    try {
      final sessionNotification =
          decodeAcpNotificationParams(notification) as SessionNotification;
      final session = _sessions[sessionNotification.sessionId];
      if (session == null) {
        return;
      }

      final next = SessionStateMachine.applyUpdate(
        session,
        sessionNotification.update,
      ).stateOrThrow;
      _storeSession(next);
    } on Object {
      // Structured diagnostics and protocol-error surfacing arrive in task 4.8.
    }
  }

  void _handleTransportEvent(AcpTransportEvent event) {
    if (event case AcpTransportDiagnostic(
      :final message,
      :final severity,
      :final source,
    )) {
      for (final session in _sessions.values.toList(growable: false)) {
        _storeSession(
          session.copyWith(
            diagnostics: [
              ...session.diagnostics,
              DiagnosticEntry(
                id: DiagnosticEntryId('diagnostic-${_nextDiagnosticId++}'),
                message: message,
                severity: _mapDiagnosticSeverity(severity),
                source: source,
                createdAt: DateTime.now(),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _sendPermissionResponse(
    ApprovalRequestId approvalId,
    RequestPermissionResponse response,
  ) async {
    final pending = _pendingPermissionRequests[approvalId];
    if (pending == null) {
      throw const StateTransitionException('permission request is not pending');
    }

    try {
      await _transport.send(
        encodeAcpResponse(
          id: pending.requestId,
          method: sessionRequestPermissionMethod,
          result: response,
        ),
      );
    } on Object catch (error) {
      throw AcpClientApplicationException(
        'Failed to send ACP response $sessionRequestPermissionMethod.',
        cause: error,
      );
    }

    _pendingPermissionRequests.remove(approvalId);
  }

  void _sendCancelledPermissionResponse(JsonRpcId requestId) {
    final response = _transport
        .send(
          encodeAcpResponse(
            id: requestId,
            method: sessionRequestPermissionMethod,
            result: const RequestPermissionResponse(
              outcome: RequestPermissionOutcome.cancelled(),
            ),
          ),
        )
        .catchError((Object _) {
          // Structured diagnostics and protocol-error surfacing arrive in task 4.8.
        });
    unawaited(response);
  }

  ApprovalRequestId _approvalRequestId(JsonRpcId requestId) {
    return ApprovalRequestId('permission-${requestId.toJsonValue()}');
  }

  ToolCallRecord _toolCallRecordFromUpdate(ToolCallUpdate update) {
    return ToolCallRecord(
      id: update.toolCallId,
      title: update.title ?? update.toolCallId.value,
      kind: update.kind ?? ToolKind.other,
      status: update.status ?? ToolCallStatus.pending,
      content: update.content ?? const [],
      locations: update.locations ?? const [],
      rawInput: update.rawInput,
      rawOutput: update.rawOutput,
    );
  }

  void _requirePermissionOption(
    ApprovalRequest approval,
    PermissionOptionId optionId,
  ) {
    final hasOption = approval.options.any((option) {
      return option.optionId == optionId;
    });
    if (!hasOption) {
      throw const StateTransitionException(
        'permission option is not available for this request',
      );
    }
  }

  AcpSession _requireSession(SessionId sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw MissingAcpSessionException(
        sessionId: sessionId,
        message: 'Session ${sessionId.value} is not active.',
      );
    }

    return session;
  }

  void _storeSession(AcpSession session) {
    _sessions[session.id] = session;
    if (!_sessionController.isClosed) {
      _sessionController.add(session);
    }
  }
}

final class _PendingAcpRequest {
  _PendingAcpRequest(this.method);

  final String method;
  final _completer = Completer<Object>();

  Future<Object> get future => _completer.future;

  void complete(Object value) => _completer.complete(value);

  void completeError(Object error) => _completer.completeError(error);
}

final class _PendingPermissionRequest {
  const _PendingPermissionRequest({required this.requestId});

  final JsonRpcId requestId;
}

DiagnosticSeverity _mapDiagnosticSeverity(
  AcpTransportDiagnosticSeverity severity,
) {
  return switch (severity) {
    AcpTransportDiagnosticSeverity.debug => DiagnosticSeverity.debug,
    AcpTransportDiagnosticSeverity.info => DiagnosticSeverity.info,
    AcpTransportDiagnosticSeverity.warning => DiagnosticSeverity.warning,
    AcpTransportDiagnosticSeverity.error => DiagnosticSeverity.error,
  };
}
