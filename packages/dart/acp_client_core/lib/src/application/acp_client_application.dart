import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';

import '../domain/approval_policy.dart';
import '../domain/domain_models.dart';
import '../domain/secret_redaction.dart';
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
  AcpClientApplication({
    required AcpTransport transport,
    AcpTransportFactory? reconnectTransport,
  }) : _transport = transport,
       _reconnectTransport = reconnectTransport {
    _bindTransport();
  }

  AcpTransport _transport;
  final AcpTransportFactory? _reconnectTransport;
  final _pendingRequests = <JsonRpcId, _PendingAcpRequest>{};
  final _pendingPermissionRequests =
      <ApprovalRequestId, _PendingPermissionRequest>{};
  final _handledPermissionRequests = <ApprovalRequestId>{};
  final _sessions = <SessionId, AcpSession>{};
  final _diagnostics = <DiagnosticEntry>[];
  final _redactor = const SecretRedactor();
  final _sessionController = StreamController<AcpSession>.broadcast(sync: true);
  final _diagnosticController = StreamController<DiagnosticEntry>.broadcast(
    sync: true,
  );

  late StreamSubscription<JsonRpcMessage> _inboundSubscription;
  late StreamSubscription<AcpTransportEvent> _eventSubscription;

  var _nextRequestId = 1;
  var _nextTurnId = 1;
  var _nextDiagnosticId = 1;

  /// Incremented every time the underlying transport is replaced
  /// (initial [connect] counts as generation 0, each [reconnect] bumps it).
  ///
  /// In-flight operations capture the generation they started with and
  /// discard their result instead of mutating session state if a reconnect
  /// happened while they were awaiting a response, so a stale prompt/cancel/
  /// permission outcome from a superseded transport can never be applied on
  /// top of the state produced by a newer connection.
  var _generation = 0;

  int get generation => _generation;

  Stream<AcpSession> get sessionChanges => _sessionController.stream;

  Stream<DiagnosticEntry> get diagnosticChanges => _diagnosticController.stream;

  List<AcpSession> get sessions => List.unmodifiable(_sessions.values);

  List<DiagnosticEntry> get diagnostics => List.unmodifiable(_diagnostics);

  AcpSession? sessionById(SessionId sessionId) => _sessions[sessionId];

  Future<AcpTransportState> connect(
    AcpTransport transport, {
    Duration? closeTimeout,
  }) async {
    await _replaceTransport(transport, closeTimeout: closeTimeout);

    try {
      await _transport.start();
    } on Object catch (error) {
      throw AcpClientApplicationException(
        'Failed to connect ACP transport.',
        cause: error,
      );
    }

    return _transport.state;
  }

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

  Future<AcpSession> loadSession(LoadSessionCommand command) async {
    final response = await _sendRequest<LoadSessionResponse>(
      method: sessionLoadMethod,
      params: LoadSessionRequest(
        sessionId: command.sessionId,
        cwd: command.cwd,
        mcpServers: command.mcpServers,
        meta: command.meta,
      ),
    );
    final session = AcpSession(
      id: command.sessionId,
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
    final generation = _generation;
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
      _requireCurrentGeneration(generation);
      final completedSession = SessionStateMachine.completeTurn(
        _requireSession(command.sessionId),
        stopReason: response.stopReason,
        completedAt: DateTime.now(),
      ).stateOrThrow;

      _storeSession(completedSession);
      return completedSession.turns.last;
    } on Object catch (error) {
      if (generation != _generation) {
        rethrow;
      }
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
    final generation = _generation;
    final session = _requireSession(command.sessionId);
    final activeTurn = session.activeTurn;
    if (activeTurn == null) {
      final lastTurn = session.turns.lastOrNull;
      if (lastTurn?.status == PromptTurnStatus.cancelled) {
        return lastTurn!;
      }

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

    Object? permissionSendError;
    StackTrace? permissionSendStackTrace;
    for (final approval in pendingApprovals) {
      try {
        await _sendPermissionResponse(
          approval.id,
          const RequestPermissionResponse(
            outcome: RequestPermissionOutcome.cancelled(),
          ),
        );
      } on Object catch (error, stackTrace) {
        permissionSendError ??= error;
        permissionSendStackTrace ??= stackTrace;
      }
    }

    _requireCurrentGeneration(generation);
    final cancelled = SessionStateMachine.cancelTurn(
      _requireSession(command.sessionId),
      completedAt: DateTime.now(),
    ).stateOrThrow;

    _storeSession(cancelled);
    if (permissionSendError != null) {
      Error.throwWithStackTrace(
        permissionSendError,
        permissionSendStackTrace ?? StackTrace.current,
      );
    }

    return cancelled.turns.last;
  }

  Future<AcpTransportState> reconnect(ReconnectCommand command) async {
    final createTransport = command.transportFactory ?? _reconnectTransport;
    if (createTransport == null) {
      throw const StateTransitionException(
        'reconnect requires a replacement transport factory',
      );
    }

    await _replaceTransport(
      await createTransport(),
      closeTimeout: command.closeTimeout,
    );

    try {
      await _transport.start();
    } on Object catch (error) {
      throw AcpClientApplicationException(
        'Failed to reconnect ACP transport.',
        cause: error,
      );
    }

    return _transport.state;
  }

  Future<void> _replaceTransport(
    AcpTransport transport, {
    Duration? closeTimeout,
  }) async {
    // Bump the generation before yielding on any await below so that
    // operations still in flight on the old transport observe the new
    // generation as soon as their continuation resumes, even if that
    // continuation is scheduled while this method is still tearing down
    // the old transport.
    _generation++;
    await _inboundSubscription.cancel();
    await _eventSubscription.cancel();
    _failPendingRequests(
      const AcpClientApplicationException('ACP transport was replaced.'),
    );
    _pendingPermissionRequests.clear();
    _handledPermissionRequests.clear();
    await _transport.close(timeout: closeTimeout);

    _transport = transport;
    _bindTransport();
  }

  Future<ApprovalRequest> respondToPermission(
    RespondToPermissionCommand command,
  ) async {
    final generation = _generation;
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
    _requireCurrentGeneration(generation);

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
    _failPendingRequests(
      const AcpClientApplicationException('ACP application disposed.'),
    );
    _pendingPermissionRequests.clear();
    _handledPermissionRequests.clear();
    await _transport.close();
    await _diagnosticController.close();
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
      _recordDiagnostic(
        message: 'Failed to send ACP request $method.',
        severity: DiagnosticSeverity.error,
        source: 'application.protocol',
        cause: error,
        context: {'method': method, 'requestId': id.toJsonValue()},
      );
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
      _recordDiagnostic(
        message: 'Failed to send ACP notification $method.',
        severity: DiagnosticSeverity.error,
        source: 'application.protocol',
        cause: error,
        context: {'method': method},
      );
      throw AcpClientApplicationException(
        'Failed to send ACP notification $method.',
        cause: error,
      );
    }
  }

  void _bindTransport() {
    final boundGeneration = _generation;
    _inboundSubscription = _transport.inbound.listen((message) {
      if (boundGeneration != _generation) {
        return;
      }
      _handleInboundMessage(message);
    });
    _eventSubscription = _transport.events.listen((event) {
      if (boundGeneration != _generation) {
        return;
      }
      _handleTransportEvent(event);
    });
  }

  void _failPendingRequests(Object error) {
    for (final pending in _pendingRequests.values) {
      pending.completeError(error);
    }
    _pendingRequests.clear();
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
      _recordDiagnostic(
        message:
            'ACP request ${pending.method} failed: ${response.error?.message}',
        severity: DiagnosticSeverity.error,
        source: 'application.protocol',
        cause: response.error,
        context: {
          'method': pending.method,
          'requestId': response.id.toJsonValue(),
          'error': response.error?.toJson(),
        },
      );
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
      _recordDiagnostic(
        message: 'Failed to decode ACP response for ${pending.method}.',
        severity: DiagnosticSeverity.error,
        source: 'application.protocol',
        cause: error,
        context: {
          'method': pending.method,
          'requestId': response.id.toJsonValue(),
          'result': response.result,
        },
      );
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
      final approvalId = _approvalRequestId(request.id);
      if (_handledPermissionRequests.contains(approvalId)) {
        return;
      }

      final session = _sessions[permissionRequest.sessionId];
      final activeTurn = session?.activeTurn;
      if (session == null || activeTurn == null) {
        _sendCancelledPermissionResponse(request.id);
        _handledPermissionRequests.add(approvalId);
        return;
      }

      final toolCall = _toolCallRecordFromUpdate(permissionRequest.toolCall);
      final approval = ApprovalRequest(
        id: approvalId,
        sessionId: permissionRequest.sessionId,
        turnId: activeTurn.id,
        toolCall: toolCall,
        options: permissionRequest.options,
        riskLevel: toolCall.riskLevel,
        requestedAt: DateTime.now(),
      );
      final next = SessionStateMachine.requestApproval(
        session,
        approval,
      ).stateOrThrow;

      _pendingPermissionRequests[approval.id] = _PendingPermissionRequest(
        requestId: request.id,
      );
      _handledPermissionRequests.add(approval.id);
      _storeSession(next);
    } on Object catch (error) {
      _sendCancelledPermissionResponse(request.id);
      _recordDiagnostic(
        message: 'Failed to handle ACP permission request.',
        severity: DiagnosticSeverity.error,
        source: 'application.permission',
        cause: error,
        context: {
          'method': request.method,
          'requestId': request.id.toJsonValue(),
          'params': request.params,
        },
      );
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
    } on Object catch (error) {
      _recordDiagnostic(
        message: 'Failed to handle ACP session update.',
        severity: DiagnosticSeverity.error,
        source: 'application.protocol',
        cause: error,
        context: {'method': notification.method, 'params': notification.params},
      );
    }
  }

  void _handleTransportEvent(AcpTransportEvent event) {
    switch (event) {
      case AcpTransportDiagnostic(
        :final message,
        :final severity,
        :final source,
      ):
        _recordDiagnostic(
          message: message,
          severity: _mapDiagnosticSeverity(severity),
          source: source,
        );
      case AcpTransportFailure(:final error):
        _recordDiagnostic(
          message: error.message,
          severity: DiagnosticSeverity.error,
          source: 'transport',
          cause: error,
          context: {'code': error.code.name, 'cause': error.cause?.toString()},
        );
      case AcpTransportStateChanged():
        break;
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
      _recordDiagnostic(
        message: 'Failed to send ACP response $sessionRequestPermissionMethod.',
        severity: DiagnosticSeverity.error,
        source: 'application.permission',
        cause: error,
        context: {
          'method': sessionRequestPermissionMethod,
          'requestId': pending.requestId.toJsonValue(),
          'approvalId': approvalId.value,
        },
      );
      throw AcpClientApplicationException(
        'Failed to send ACP response $sessionRequestPermissionMethod.',
        cause: error,
      );
    }

    _pendingPermissionRequests.remove(approvalId);
    _handledPermissionRequests.add(approvalId);
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
        .catchError((Object error) {
          _recordDiagnostic(
            message:
                'Failed to send cancelled ACP response $sessionRequestPermissionMethod.',
            severity: DiagnosticSeverity.error,
            source: 'application.permission',
            cause: error,
            context: {
              'method': sessionRequestPermissionMethod,
              'requestId': requestId.toJsonValue(),
            },
          );
        });
    unawaited(response);
  }

  void _recordDiagnostic({
    required String message,
    required DiagnosticSeverity severity,
    String? source,
    Object? cause,
    Map<String, Object?> context = const {},
  }) {
    final entry = DiagnosticEntry(
      id: DiagnosticEntryId('diagnostic-${_nextDiagnosticId++}'),
      message: _redactor.redactText(message),
      severity: severity,
      source: source,
      context: _redactor.redactMap(context),
      cause: cause == null ? null : _redactor.redactText(cause.toString()),
      createdAt: DateTime.now(),
    );

    _diagnostics.add(entry);
    if (!_diagnosticController.isClosed) {
      _diagnosticController.add(entry);
    }

    for (final session in _sessions.values.toList(growable: false)) {
      _storeSession(
        session.copyWith(diagnostics: [...session.diagnostics, entry]),
      );
    }
  }

  ApprovalRequestId _approvalRequestId(JsonRpcId requestId) {
    return ApprovalRequestId('permission-${requestId.toJsonValue()}');
  }

  ToolCallRecord _toolCallRecordFromUpdate(ToolCallUpdate update) {
    final riskLevel = ApprovalPolicy.classifyToolCallUpdate(update);
    return ToolCallRecord(
      id: update.toolCallId,
      title: update.title ?? update.toolCallId.value,
      kind: update.kind ?? ToolKind.other,
      status: update.status ?? ToolCallStatus.pending,
      riskLevel: riskLevel,
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

  void _requireCurrentGeneration(int expectedGeneration) {
    if (expectedGeneration != _generation) {
      throw const StateTransitionException(
        'operation is stale: ACP transport was reconnected while this '
        'operation was in flight',
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
