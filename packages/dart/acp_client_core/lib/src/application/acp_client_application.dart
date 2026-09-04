import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';

import '../domain/approval_policy.dart';
import '../domain/domain_models.dart';
import '../domain/fs_access.dart';
import '../domain/secret_redaction.dart';
import '../domain/state_machines.dart';
import '../domain/terminal_access.dart';
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

final class UnsupportedProtocolVersionException
    extends AcpClientApplicationException {
  UnsupportedProtocolVersionException({
    required this.requestedVersion,
    required this.agentVersion,
  }) : super(
         'Agent negotiated unsupported ACP protocol version '
         '${agentVersion.value} (client supports '
         '${requestedVersion.value}).',
       );

  final ProtocolVersion requestedVersion;
  final ProtocolVersion agentVersion;
}

final class AcpClientApplication {
  AcpClientApplication({
    required AcpTransport transport,
    AcpTransportFactory? reconnectTransport,
    Implementation? clientInfo,
    TextFileReader? textFileReader,
    TextFileWriter? textFileWriter,
    TerminalProcessRunner? terminalProcessRunner,
  }) : _transport = transport,
       _reconnectTransport = reconnectTransport,
       _clientInfo = clientInfo,
       _textFileReader = textFileReader,
       _textFileWriter = textFileWriter,
       _terminalProcessRunner = terminalProcessRunner {
    _bindTransport();
  }

  /// The ACP protocol version CodeLab implements and requires the agent to
  /// negotiate during `initialize`.
  static const supportedProtocolVersion = ProtocolVersion(1);

  AcpTransport _transport;
  final AcpTransportFactory? _reconnectTransport;
  final Implementation? _clientInfo;

  /// `null` when the composition root did not wire an fs adapter — in that
  /// case `initialize` honestly announces `clientCapabilities.fs.*` as
  /// `false` (see `_establishConnection`) and any inbound `fs/*` request is
  /// answered with a protocol error rather than acted on.
  final TextFileReader? _textFileReader;
  final TextFileWriter? _textFileWriter;

  /// `null` when the composition root did not wire a terminal adapter — in
  /// that case `initialize` honestly announces `clientCapabilities.terminal`
  /// as `false` and any inbound `terminal/*` request is answered with a
  /// protocol error rather than acted on. Same reasoning as
  /// [_textFileReader]/[_textFileWriter].
  final TerminalProcessRunner? _terminalProcessRunner;

  /// Session-scoped registry of terminal processes started via
  /// `terminal/create`, keyed first by the owning [SessionId] then by
  /// [TerminalId] — see `add-acp-terminal-client-support/design.md`,
  /// Decision 3. A [TerminalId] absent from its session's map is
  /// indistinguishable from one that was never created or already released
  /// via `terminal/release` (both surface as [UnknownTerminalFailure]).
  final _terminals = <SessionId, Map<TerminalId, TerminalProcessHandle>>{};
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
  final _connectionStateController =
      StreamController<ClientConnectionState>.broadcast(sync: true);

  late StreamSubscription<JsonRpcMessage> _inboundSubscription;
  late StreamSubscription<AcpTransportEvent> _eventSubscription;

  var _nextRequestId = 1;
  var _nextTurnId = 1;
  var _nextDiagnosticId = 1;

  ClientConnectionState _connectionState =
      const ClientConnectionState.disconnected();

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

  ClientConnectionState get connectionState => _connectionState;

  Stream<ClientConnectionState> get connectionStateChanges =>
      _connectionStateController.stream;

  List<AcpSession> get sessions => List.unmodifiable(_sessions.values);

  List<DiagnosticEntry> get diagnostics => List.unmodifiable(_diagnostics);

  AcpSession? sessionById(SessionId sessionId) => _sessions[sessionId];

  Future<ClientConnectionState> connect(
    AcpTransport transport, {
    Duration? closeTimeout,
  }) async {
    await _replaceTransport(transport, closeTimeout: closeTimeout);
    return _establishConnection();
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

  Future<AcpSession> setSessionConfigOption(
    SetSessionConfigOptionCommand command,
  ) async {
    final session = _requireSession(command.sessionId);
    final response = await _sendRequest<SetSessionConfigOptionResponse>(
      method: sessionSetConfigOptionMethod,
      params: SetSessionConfigOptionRequest(
        sessionId: command.sessionId,
        configId: command.configId,
        value: command.value,
        meta: command.meta,
      ),
    );
    final updatedSession = session.copyWith(
      configOptions: response.configOptions,
    );

    _storeSession(updatedSession);
    return updatedSession;
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

  Future<ClientConnectionState> reconnect(ReconnectCommand command) async {
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

    return _establishConnection();
  }

  /// Starts the freshly bound transport and performs the ACP `initialize`
  /// handshake required before any session operation, per
  /// `docs/acp/protocol/02-Initialization.md`.
  Future<ClientConnectionState> _establishConnection() async {
    if (_connectionState is! ClientConnectionDisconnected) {
      _transitionConnection(const ConnectionStateEvent.disconnect());
    }
    _transitionConnection(const ConnectionStateEvent.connect());

    try {
      await _transport.start();
    } on Object catch (error) {
      _transitionConnection(
        ConnectionStateEvent.fail(
          reason: ConnectionFailureReason.startFailed,
          message: 'Failed to start ACP transport.',
          cause: error,
        ),
      );
      throw AcpClientApplicationException(
        'Failed to connect ACP transport.',
        cause: error,
      );
    }

    _transitionConnection(const ConnectionStateEvent.initialize());

    final InitializeResponse response;
    try {
      response = await _sendRequest<InitializeResponse>(
        method: initializeMethod,
        params: InitializeRequest(
          protocolVersion: supportedProtocolVersion,
          clientInfo: _clientInfo,
          clientCapabilities: ClientCapabilities(
            fs: FileSystemCapabilities(
              readTextFile: _textFileReader != null,
              writeTextFile: _textFileWriter != null,
            ),
            terminal: _terminalProcessRunner != null,
          ),
        ),
      );
    } on Object catch (error) {
      _transitionConnection(
        ConnectionStateEvent.fail(
          reason: ConnectionFailureReason.protocolViolation,
          message: 'Failed to negotiate ACP protocol version.',
          cause: error,
        ),
      );
      rethrow;
    }

    if (response.protocolVersion != supportedProtocolVersion) {
      final failure = UnsupportedProtocolVersionException(
        requestedVersion: supportedProtocolVersion,
        agentVersion: response.protocolVersion,
      );
      _transitionConnection(
        ConnectionStateEvent.fail(
          reason: ConnectionFailureReason.unsupportedProtocolVersion,
          message: failure.message,
        ),
      );
      await _transport.close();
      throw failure;
    }

    _transitionConnection(
      ConnectionStateEvent.ready(
        protocolVersion: response.protocolVersion,
        agentInfo: response.agentInfo,
        capabilities: response.agentCapabilities,
      ),
    );

    return _connectionState;
  }

  void _transitionConnection(ConnectionStateEvent event) {
    _connectionState = ConnectionStateMachine.reduce(
      _connectionState,
      event,
    ).stateOrThrow;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(_connectionState);
    }
    // Any terminal process left running belongs to a connection that is
    // now gone or about to be replaced — kill it here rather than at each
    // individual call site that can reach disconnected/failed (spontaneous
    // failure, the defensive reset `_establishConnection` performs before
    // every connect()/reconnect(), ...), see design.md, Decision 6.
    if (_connectionState is ClientConnectionDisconnected ||
        _connectionState is ClientConnectionFailed) {
      unawaited(_killAllTerminalProcesses());
    }
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
    await _killAllTerminalProcesses();
    await _transport.close();
    await _diagnosticController.close();
    await _sessionController.close();
    await _connectionStateController.close();
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
      case JsonRpcRequest(method: fsReadTextFileMethod):
        unawaited(_handleReadTextFileRequest(message));
      case JsonRpcRequest(method: fsWriteTextFileMethod):
        unawaited(_handleWriteTextFileRequest(message));
      case JsonRpcRequest(method: terminalCreateMethod):
        unawaited(_handleCreateTerminalRequest(message));
      case JsonRpcRequest(method: terminalOutputMethod):
        unawaited(_handleTerminalOutputRequest(message));
      case JsonRpcRequest(method: terminalWaitForExitMethod):
        unawaited(_handleWaitForTerminalExitRequest(message));
      case JsonRpcRequest(method: terminalKillMethod):
        unawaited(_handleKillTerminalCommandRequest(message));
      case JsonRpcRequest(method: terminalReleaseMethod):
        unawaited(_handleReleaseTerminalRequest(message));
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

  /// Handles an incoming `fs/read_text_file` request — no approval step (see
  /// `openspec/changes/add-acp-fs-client-support/design.md`, Decision 1):
  /// working-directory containment is the only gate.
  Future<void> _handleReadTextFileRequest(JsonRpcRequest request) async {
    final reader = _textFileReader;
    if (reader == null) {
      await _sendAcpMethodError(
        request.id,
        method: fsReadTextFileMethod,
        error: const AcpProtocolError.internalError(
          'fs/read_text_file is not supported by this client.',
        ),
      );
      return;
    }

    try {
      final readRequest =
          decodeAcpRequestParams(request) as ReadTextFileRequest;
      final session = _sessions[readRequest.sessionId];
      if (session == null) {
        await _sendAcpMethodError(
          request.id,
          method: fsReadTextFileMethod,
          error: AcpProtocolError.invalidAcpParams(
            method: fsReadTextFileMethod,
            message: 'Unknown session "${readRequest.sessionId.value}".',
          ),
        );
        return;
      }

      final resolvedPath = resolveWithinWorkingDirectory(
        path: readRequest.path,
        workingDirectory: session.cwd,
      );
      final content = await reader.readText(
        path: resolvedPath,
        line: readRequest.line,
        limit: readRequest.limit,
      );
      await _transport.send(
        encodeAcpResponse(
          id: request.id,
          method: fsReadTextFileMethod,
          result: ReadTextFileResponse(content: content),
        ),
      );
    } on PathOutsideWorkingDirectoryFailure catch (error) {
      _recordDiagnostic(
        message: 'Rejected fs/read_text_file outside working directory.',
        severity: DiagnosticSeverity.warning,
        source: 'application.fs',
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: fsReadTextFileMethod,
        error: AcpProtocolError.invalidAcpParams(
          method: fsReadTextFileMethod,
          message: error.toString(),
        ),
      );
    } on FsIoFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        method: fsReadTextFileMethod,
        error: AcpProtocolError.internalError(error.message),
      );
    } on Object catch (error) {
      _recordDiagnostic(
        message: 'Failed to handle ACP fs/read_text_file request.',
        severity: DiagnosticSeverity.error,
        source: 'application.fs',
        cause: error,
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: fsReadTextFileMethod,
        error: AcpProtocolError.internalError('Failed to read file: $error'),
      );
    }
  }

  /// Handles an incoming `fs/write_text_file` request — see
  /// [_handleReadTextFileRequest] for why there is no approval step.
  Future<void> _handleWriteTextFileRequest(JsonRpcRequest request) async {
    final writer = _textFileWriter;
    if (writer == null) {
      await _sendAcpMethodError(
        request.id,
        method: fsWriteTextFileMethod,
        error: const AcpProtocolError.internalError(
          'fs/write_text_file is not supported by this client.',
        ),
      );
      return;
    }

    try {
      final writeRequest =
          decodeAcpRequestParams(request) as WriteTextFileRequest;
      final session = _sessions[writeRequest.sessionId];
      if (session == null) {
        await _sendAcpMethodError(
          request.id,
          method: fsWriteTextFileMethod,
          error: AcpProtocolError.invalidAcpParams(
            method: fsWriteTextFileMethod,
            message: 'Unknown session "${writeRequest.sessionId.value}".',
          ),
        );
        return;
      }

      final resolvedPath = resolveWithinWorkingDirectory(
        path: writeRequest.path,
        workingDirectory: session.cwd,
      );
      await writer.writeText(path: resolvedPath, content: writeRequest.content);
      _recordDiagnostic(
        message: 'Wrote file via fs/write_text_file.',
        severity: DiagnosticSeverity.info,
        source: 'application.fs',
        context: {
          'sessionId': writeRequest.sessionId.value,
          'requestId': request.id.toJsonValue(),
        },
      );
      await _transport.send(
        encodeAcpResponse(
          id: request.id,
          method: fsWriteTextFileMethod,
          result: const WriteTextFileResponse(),
        ),
      );
    } on PathOutsideWorkingDirectoryFailure catch (error) {
      _recordDiagnostic(
        message: 'Rejected fs/write_text_file outside working directory.',
        severity: DiagnosticSeverity.warning,
        source: 'application.fs',
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: fsWriteTextFileMethod,
        error: AcpProtocolError.invalidAcpParams(
          method: fsWriteTextFileMethod,
          message: error.toString(),
        ),
      );
    } on FsIoFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        method: fsWriteTextFileMethod,
        error: AcpProtocolError.internalError(error.message),
      );
    } on Object catch (error) {
      _recordDiagnostic(
        message: 'Failed to handle ACP fs/write_text_file request.',
        severity: DiagnosticSeverity.error,
        source: 'application.fs',
        cause: error,
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: fsWriteTextFileMethod,
        error: AcpProtocolError.internalError('Failed to write file: $error'),
      );
    }
  }

  /// Handles an incoming `terminal/create` request — no approval step (see
  /// `openspec/changes/add-acp-terminal-client-support/design.md`,
  /// Decision 1): working-directory containment is the only gate, same
  /// position as `fs/*` (see [_handleReadTextFileRequest]). The process is
  /// started and its [TerminalId] returned immediately, without waiting for
  /// completion — per ACP, `terminal/wait_for_exit` is a separate call.
  Future<void> _handleCreateTerminalRequest(JsonRpcRequest request) async {
    final runner = _terminalProcessRunner;
    if (runner == null) {
      await _sendAcpMethodError(
        request.id,
        method: terminalCreateMethod,
        error: const AcpProtocolError.internalError(
          'terminal/create is not supported by this client.',
        ),
      );
      return;
    }

    try {
      final createRequest =
          decodeAcpRequestParams(request) as CreateTerminalRequest;
      final session = _sessions[createRequest.sessionId];
      if (session == null) {
        await _sendAcpMethodError(
          request.id,
          method: terminalCreateMethod,
          error: AcpProtocolError.invalidAcpParams(
            method: terminalCreateMethod,
            message: 'Unknown session "${createRequest.sessionId.value}".',
          ),
        );
        return;
      }

      final resolvedCwd = createRequest.cwd == null
          ? session.cwd
          : resolveWithinWorkingDirectory(
              path: createRequest.cwd!,
              workingDirectory: session.cwd,
            );

      final handle = await runner.start(
        command: createRequest.command,
        args: createRequest.args,
        env: {
          for (final variable in createRequest.env)
            variable.name: variable.value,
        },
        cwd: resolvedCwd,
        outputByteLimit: createRequest.outputByteLimit,
      );

      final terminalId = _newTerminalId(request.id);
      (_terminals[createRequest.sessionId] ??= {})[terminalId] = handle;

      _recordDiagnostic(
        message: 'Started terminal process via terminal/create.',
        severity: DiagnosticSeverity.info,
        source: 'application.terminal',
        context: {
          'sessionId': createRequest.sessionId.value,
          'terminalId': terminalId.value,
          'command': createRequest.command,
          'args': createRequest.args,
          'cwd': resolvedCwd,
        },
      );

      await _transport.send(
        encodeAcpResponse(
          id: request.id,
          method: terminalCreateMethod,
          result: CreateTerminalResponse(terminalId: terminalId),
        ),
      );
    } on PathOutsideWorkingDirectoryFailure catch (error) {
      _recordDiagnostic(
        message: 'Rejected terminal/create outside working directory.',
        severity: DiagnosticSeverity.warning,
        source: 'application.terminal',
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: terminalCreateMethod,
        error: AcpProtocolError.invalidAcpParams(
          method: terminalCreateMethod,
          message: error.toString(),
        ),
      );
    } on TerminalStartFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        method: terminalCreateMethod,
        error: AcpProtocolError.internalError(error.message),
      );
    } on Object catch (error) {
      _recordDiagnostic(
        message: 'Failed to handle ACP terminal/create request.',
        severity: DiagnosticSeverity.error,
        source: 'application.terminal',
        cause: error,
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: terminalCreateMethod,
        error: AcpProtocolError.internalError(
          'Failed to start terminal: $error',
        ),
      );
    }
  }

  Future<void> _handleTerminalOutputRequest(JsonRpcRequest request) async {
    if (_terminalProcessRunner == null) {
      await _sendAcpMethodError(
        request.id,
        method: terminalOutputMethod,
        error: const AcpProtocolError.internalError(
          'terminal/output is not supported by this client.',
        ),
      );
      return;
    }

    try {
      final outputRequest =
          decodeAcpRequestParams(request) as TerminalOutputRequest;
      final handle = _requireTerminal(
        outputRequest.sessionId,
        outputRequest.terminalId,
      );

      await _transport.send(
        encodeAcpResponse(
          id: request.id,
          method: terminalOutputMethod,
          result: TerminalOutputResponse(
            output: handle.output,
            truncated: handle.truncated,
            exitStatus: _terminalExitStatus(handle.state),
          ),
        ),
      );
    } on UnknownTerminalFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        method: terminalOutputMethod,
        error: AcpProtocolError.invalidAcpParams(
          method: terminalOutputMethod,
          message: error.toString(),
        ),
      );
    } on Object catch (error) {
      _recordDiagnostic(
        message: 'Failed to handle ACP terminal/output request.',
        severity: DiagnosticSeverity.error,
        source: 'application.terminal',
        cause: error,
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: terminalOutputMethod,
        error: AcpProtocolError.internalError(
          'Failed to read terminal output: $error',
        ),
      );
    }
  }

  Future<void> _handleWaitForTerminalExitRequest(JsonRpcRequest request) async {
    if (_terminalProcessRunner == null) {
      await _sendAcpMethodError(
        request.id,
        method: terminalWaitForExitMethod,
        error: const AcpProtocolError.internalError(
          'terminal/wait_for_exit is not supported by this client.',
        ),
      );
      return;
    }

    try {
      final waitRequest =
          decodeAcpRequestParams(request) as WaitForTerminalExitRequest;
      final handle = _requireTerminal(
        waitRequest.sessionId,
        waitRequest.terminalId,
      );

      final exited = await handle.waitForExit();
      final status = switch (exited) {
        TerminalProcessExited(:final exitCode, :final signal) => (
          exitCode: exitCode,
          signal: signal,
        ),
        // A conformant TerminalProcessRunner.waitForExit() never resolves
        // before the process exits — a `running()` result here is an
        // adapter bug, not a normal outcome, so it is reported like any
        // other unexpected failure rather than silently coerced.
        TerminalProcessRunning() => throw const AcpClientApplicationException(
          'terminal process runner resolved waitForExit() while still '
          'running.',
        ),
      };
      await _transport.send(
        encodeAcpResponse(
          id: request.id,
          method: terminalWaitForExitMethod,
          result: WaitForTerminalExitResponse(
            exitCode: status.exitCode,
            signal: status.signal,
          ),
        ),
      );
    } on UnknownTerminalFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        method: terminalWaitForExitMethod,
        error: AcpProtocolError.invalidAcpParams(
          method: terminalWaitForExitMethod,
          message: error.toString(),
        ),
      );
    } on Object catch (error) {
      _recordDiagnostic(
        message: 'Failed to handle ACP terminal/wait_for_exit request.',
        severity: DiagnosticSeverity.error,
        source: 'application.terminal',
        cause: error,
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: terminalWaitForExitMethod,
        error: AcpProtocolError.internalError(
          'Failed to wait for terminal exit: $error',
        ),
      );
    }
  }

  /// Handles an incoming `terminal/kill` request. Killing an already-exited
  /// process is a no-op, not an error (`TerminalProcessHandle.kill` itself
  /// guarantees the atomicity — see design.md, Risks) — the `terminalId`
  /// remains valid afterwards for `output`/`wait_for_exit`/`release`.
  Future<void> _handleKillTerminalCommandRequest(JsonRpcRequest request) async {
    if (_terminalProcessRunner == null) {
      await _sendAcpMethodError(
        request.id,
        method: terminalKillMethod,
        error: const AcpProtocolError.internalError(
          'terminal/kill is not supported by this client.',
        ),
      );
      return;
    }

    try {
      final killRequest =
          decodeAcpRequestParams(request) as KillTerminalCommandRequest;
      final handle = _requireTerminal(
        killRequest.sessionId,
        killRequest.terminalId,
      );

      await handle.kill();

      await _transport.send(
        encodeAcpResponse(
          id: request.id,
          method: terminalKillMethod,
          result: const KillTerminalCommandResponse(),
        ),
      );
    } on UnknownTerminalFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        method: terminalKillMethod,
        error: AcpProtocolError.invalidAcpParams(
          method: terminalKillMethod,
          message: error.toString(),
        ),
      );
    } on Object catch (error) {
      _recordDiagnostic(
        message: 'Failed to handle ACP terminal/kill request.',
        severity: DiagnosticSeverity.error,
        source: 'application.terminal',
        cause: error,
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: terminalKillMethod,
        error: AcpProtocolError.internalError(
          'Failed to kill terminal: $error',
        ),
      );
    }
  }

  /// Handles an incoming `terminal/release` request. Unlike `kill`, this
  /// removes the [TerminalId] from the session's registry entirely — every
  /// later `terminal/*` call with this id, including another `release`,
  /// then sees it as [UnknownTerminalFailure] (design.md, Decision 3).
  Future<void> _handleReleaseTerminalRequest(JsonRpcRequest request) async {
    if (_terminalProcessRunner == null) {
      await _sendAcpMethodError(
        request.id,
        method: terminalReleaseMethod,
        error: const AcpProtocolError.internalError(
          'terminal/release is not supported by this client.',
        ),
      );
      return;
    }

    try {
      final releaseRequest =
          decodeAcpRequestParams(request) as ReleaseTerminalRequest;
      final handle = _requireTerminal(
        releaseRequest.sessionId,
        releaseRequest.terminalId,
      );

      await handle.kill();
      _terminals[releaseRequest.sessionId]?.remove(releaseRequest.terminalId);

      await _transport.send(
        encodeAcpResponse(
          id: request.id,
          method: terminalReleaseMethod,
          result: const ReleaseTerminalResponse(),
        ),
      );
    } on UnknownTerminalFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        method: terminalReleaseMethod,
        error: AcpProtocolError.invalidAcpParams(
          method: terminalReleaseMethod,
          message: error.toString(),
        ),
      );
    } on Object catch (error) {
      _recordDiagnostic(
        message: 'Failed to handle ACP terminal/release request.',
        severity: DiagnosticSeverity.error,
        source: 'application.terminal',
        cause: error,
        context: {'requestId': request.id.toJsonValue()},
      );
      await _sendAcpMethodError(
        request.id,
        method: terminalReleaseMethod,
        error: AcpProtocolError.internalError(
          'Failed to release terminal: $error',
        ),
      );
    }
  }

  TerminalProcessHandle _requireTerminal(
    SessionId sessionId,
    TerminalId terminalId,
  ) {
    final handle = _terminals[sessionId]?[terminalId];
    if (handle == null) {
      throw UnknownTerminalFailure(terminalId);
    }
    return handle;
  }

  TerminalExitStatus? _terminalExitStatus(TerminalProcessState state) {
    return switch (state) {
      TerminalProcessRunning() => null,
      TerminalProcessExited(:final exitCode, :final signal) =>
        TerminalExitStatus(exitCode: exitCode, signal: signal),
    };
  }

  /// Derives a [TerminalId] from the agent's own JSON-RPC request id for
  /// this `terminal/create` call — same "derive from the triggering
  /// request" approach as [_approvalRequestId], avoiding a new ID-generation
  /// dependency for what is already a unique-per-request value.
  TerminalId _newTerminalId(JsonRpcId requestId) {
    return TerminalId('term-${requestId.toJsonValue()}');
  }

  /// Kills every terminal process across every session, without releasing
  /// their registry entries — mirrors `terminal/kill`'s own semantics
  /// (design.md, Decision 6): this is a connection-teardown safety net
  /// (spontaneous disconnect/failure, a fresh `connect()`/`reconnect()`
  /// tearing down the previous connection, or [dispose]), not a graceful
  /// `terminal/release` on the agent's behalf.
  Future<void> _killAllTerminalProcesses() async {
    if (_terminals.isEmpty) {
      return;
    }

    final handles = _terminals.values
        .expand((session) => session.values)
        .toList(growable: false);
    _terminals.clear();

    // Each kill is isolated so one adapter failure can't stop the rest from
    // being attempted, and so this fire-and-forget cleanup (called via
    // `unawaited` from `_transitionConnection`) never surfaces an unhandled
    // async error.
    await Future.wait(
      handles.map((handle) async {
        try {
          await handle.kill();
        } on Object catch (error) {
          _recordDiagnostic(
            message: 'Failed to kill a terminal process during teardown.',
            severity: DiagnosticSeverity.warning,
            source: 'application.terminal',
            cause: error,
          );
        }
      }),
    );
  }

  Future<void> _sendAcpMethodError(
    JsonRpcId id, {
    required String method,
    required AcpProtocolError error,
  }) async {
    try {
      await _transport.send(
        JsonRpcMessage.response(id: id, error: error.toJsonRpcError()),
      );
    } on Object catch (sendError) {
      _recordDiagnostic(
        message: 'Failed to send ACP error response for $method.',
        severity: DiagnosticSeverity.error,
        source: 'application.protocol',
        cause: sendError,
        context: {'method': method, 'requestId': id.toJsonValue()},
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
        // Unexpected transport loss (e.g. the stdio child process dying)
        // must reach `connectionStateChanges`, not just diagnostics —
        // otherwise the UI has no way to observe it and stays stuck showing
        // a connection/turn that no longer exists. `disconnected` is the
        // only state `ConnectionStateMachine._fail` rejects, so guard
        // against it the same way `_establishConnection` already does
        // before an intentional disconnect.
        if (_connectionState is! ClientConnectionDisconnected) {
          _transitionConnection(
            ConnectionStateEvent.fail(
              reason: _connectionFailureReasonFor(error.code),
              message: error.message,
              cause: error.cause,
            ),
          );
        }
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

ConnectionFailureReason _connectionFailureReasonFor(
  AcpTransportErrorCode code,
) {
  return switch (code) {
    AcpTransportErrorCode.startFailed => ConnectionFailureReason.startFailed,
    AcpTransportErrorCode.sendFailed => ConnectionFailureReason.sendFailed,
    AcpTransportErrorCode.receiveFailed =>
      ConnectionFailureReason.receiveFailed,
    AcpTransportErrorCode.protocolViolation =>
      ConnectionFailureReason.protocolViolation,
    AcpTransportErrorCode.closed => ConnectionFailureReason.closed,
    AcpTransportErrorCode.timeout => ConnectionFailureReason.timeout,
    AcpTransportErrorCode.disconnected => ConnectionFailureReason.disconnected,
    AcpTransportErrorCode.unknown => ConnectionFailureReason.unknown,
  };
}
