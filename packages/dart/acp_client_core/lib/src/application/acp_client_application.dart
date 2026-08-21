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

  Future<void> dispose() async {
    await _inboundSubscription.cancel();
    await _eventSubscription.cancel();
    for (final pending in _pendingRequests.values) {
      pending.completeError(
        const AcpClientApplicationException('ACP application disposed.'),
      );
    }
    _pendingRequests.clear();
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

  void _handleInboundMessage(JsonRpcMessage message) {
    switch (message) {
      case JsonRpcResponse():
        _completePendingRequest(message);
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
