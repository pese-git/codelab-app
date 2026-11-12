import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';

import '../domain/approval_policy.dart';
import '../domain/domain_models.dart';
import '../domain/fs_access.dart';
import '../domain/logger.dart';
import '../domain/prompt_failure.dart';
import '../domain/secret_redaction.dart';
import '../domain/state_machines.dart';
import '../domain/terminal_access.dart';
import '../infrastructure/structured_log_logger.dart';
import 'application_models.dart';

final class AcpClientApplicationException implements Exception {
  const AcpClientApplicationException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AcpClientApplicationException: $message';
}

/// Запрос снят, потому что транспорт соединения неожиданно отказал.
///
/// Почему: после отказа транспорта ответа на запрос уже не будет, а
/// ожидающий `session/prompt` должен завершиться, чтобы ход получил
/// `PromptFailure.connectionLost`, а не остался `running` (design D2 change
/// `add-connection-and-error-states`).
///
/// Для чего: типизированная причина ошибки ожидающих запросов при потере
/// соединения; по ней `sendPrompt` отличает обрыв от ответа-ошибки агента.
///
/// Как использовать: бросается из методов [AcpClientApplication], чей запрос
/// ждал ответа в момент отказа транспорта состояния `ready`.
final class AcpConnectionLostException extends AcpClientApplicationException {
  const AcpConnectionLostException(super.message);
}

final class MissingAcpSessionException extends AcpClientApplicationException {
  const MissingAcpSessionException({
    required this.sessionId,
    required String message,
  }) : super(message);

  final SessionId sessionId;
}

/// Агент не ответил на запрос клиента за отведённое время.
///
/// Почему: без таймаута зависший агент оставляет запрос висеть навсегда —
/// кнопка, ждущая ответа на `session/new` или `session/load`, не
/// разблокируется (design D2 change `add-session-list-and-reload`).
///
/// Для чего: типизированный исход запроса, снятого по таймауту; хост
/// показывает его как обычную ошибку запроса.
///
/// Как использовать: бросается из методов [AcpClientApplication], которые
/// отправляют запрос, кроме [AcpClientApplication.sendPrompt]; время
/// задаёт `requestTimeout` конструктора.
final class AcpRequestTimeoutException extends AcpClientApplicationException {
  AcpRequestTimeoutException({required this.method, required this.timeout})
    : super(
        'ACP request $method timed out after ${timeout.inMilliseconds} ms.',
      );

  /// Метод ACP снятого запроса.
  final String method;
  final Duration timeout;
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
    Duration requestTimeout = defaultRequestTimeout,
    Logger? logger,
  }) : _transport = transport,
       _requestTimeout = requestTimeout,
       _reconnectTransport = reconnectTransport,
       _clientInfo = clientInfo,
       _textFileReader = textFileReader,
       _textFileWriter = textFileWriter,
       _terminalProcessRunner = terminalProcessRunner,
       _rawLogger = logger ?? StructuredLogLogger('codelab_client_acp') {
    _bindTransport();
  }

  /// The ACP protocol version CodeLab implements and requires the agent to
  /// negotiate during `initialize`.
  static const supportedProtocolVersion = ProtocolVersion(1);

  /// Таймаут исходящего запроса по умолчанию (`09-10`, задача 5.2).
  static const defaultRequestTimeout = Duration(seconds: 60);

  /// Сколько ждать ответа на исходящий запрос, кроме `session/prompt`: ход
  /// длится сколько угодно и прерывается `session/cancel`, а не таймером
  /// (design D2 change `add-session-list-and-reload`).
  final Duration _requestTimeout;

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

  /// Буферы реплея `session/load` по id загружаемой сессии.
  ///
  /// Почему: агент повторяет историю уведомлениями `session/update` до ответа
  /// на `session/load` (`03-Session Setup.md#loading-a-session`), а сессия
  /// клиента появляется только по ответу (`session-lifecycle.md` §19).
  ///
  /// Для чего: [_handleSessionUpdate] складывает сюда обновления загружаемой
  /// сессии вместо применения к прежнему состоянию; [loadSession] после
  /// ответа раскладывает их в ходы (`SessionStateMachine.replayHistory`) и
  /// убирает буфер при любом исходе запроса.
  final _sessionReplays = <SessionId, List<_BufferedUpdate>>{};

  /// Число `session/new` в полёте и обновления неизвестных сессий, пришедшие
  /// за это время.
  ///
  /// Почему: агент вправе прислать `session/update` сразу за ответом на
  /// `session/new` (`available_commands_update`, `14-Slash Commands.md`), и
  /// транспорт доставляет оба кадра раньше, чем [createSession] вернёт
  /// управление после `await` и заведёт сессию. Без буфера такие обновления
  /// терялись (design D7 change `add-command-palette-agent-commands`).
  ///
  /// Для чего: [_handleSessionUpdate] складывает сюда обновления сессии, которой
  /// ещё нет, пока идёт хоть один `session/new`; [createSession] применяет
  /// обновления своей сессии после ответа, а когда запросов в полёте не
  /// остаётся, буфер очищается — обновления так и не созданных сессий
  /// отбрасываются, как прежде.
  var _sessionsBeingCreated = 0;
  final _earlyUpdates = <SessionId, List<_BufferedUpdate>>{};

  /// Сессии, чей ход прервала замена транспорта.
  ///
  /// Почему: обрыв соединения отменяет ход на стороне агента (у stdio
  /// умирает процесс, у `codelab-agent serve --ws` `detachGrace` ноль), но
  /// ACP об этом не сообщает: реплей `session/load` не передаёт
  /// `stopReason`, и прерванный ход выглядел бы «завершённым неизвестно как»
  /// (design D2 change `cancel-turn-on-ws-disconnect`).
  ///
  /// Для чего: метку ставят [reconnect] до фабрики транспорта (с откатом у
  /// сессий с идущим ходом при сбое фабрики, D22 change
  /// `require-project-folder`) и [_replaceTransport] для сессий с активным
  /// ходом. Успешный [loadSession] помечает последний ход реплея отменённым
  /// и убирает id. [sendPrompt] снимает метку в начале нового хода и при
  /// ответе с `stopReason` не `cancelled`. Ошибка `session/load` метку
  /// сохраняет до следующей загрузки.
  final _interruptedTurns = <SessionId>{};

  /// Bounded ring buffer — see `docs/architecture/observability.md` §28.
  /// Only bounds this in-memory list (used by the UI inspector); the full
  /// structured-logging output is unaffected, see `_logDiagnosticEntry`.
  static const _maxDiagnostics = 500;
  final _diagnostics = <DiagnosticEntry>[];
  final _redactor = const SecretRedactor();

  /// Unbound base logger, injected or defaulted to the `structured_log`
  /// adapter (`design.md` Decision 7 — global singleton, deliberately not
  /// an injected `StructlogConfiguration` instance).
  final Logger _rawLogger;

  /// Application-level structured events (`category=application`).
  late final Logger _logger = _rawLogger.bind({
    logCategoryKey: applicationLogCategory,
  });

  /// Developer-only full ACP payload tracing (`category=protocol`),
  /// off by default — see `design.md` Decision 4.
  late final Logger _protocolTraceLogger = _rawLogger.bind({
    logCategoryKey: protocolTraceLogCategory,
  });
  final _sessionController = StreamController<AcpSession>.broadcast(sync: true);
  final _diagnosticController = StreamController<DiagnosticEntry>.broadcast(
    sync: true,
  );
  final _connectionStateController =
      StreamController<ClientConnectionState>.broadcast(sync: true);

  /// Ядро закрыто: ставится первым синхронным действием [dispose] (D12 change
  /// `add-client-process-shutdown-on-exit`).
  ///
  /// Почему флаг, а не состояние: это окончательный односторонний переход,
  /// который операции, уже идущие в другом `Future` (Connect, Reconnect,
  /// старт `terminal/create`), проверяют после каждого `await`, чтобы не
  /// привязать и не запустить транспорт и не оставить процесс без владельца.
  var _disposed = false;

  /// Мемоизированный проход [dispose]: повторный вызов ждёт тот же `Future`.
  Future<void>? _disposing;

  /// Незавершённые старты `terminal/create` (D12): [dispose] ждёт их, чтобы
  /// процесс, запущенный в момент закрытия, был завершён, а не осиротел.
  final _pendingTerminalStarts = <Future<void>>{};

  /// Массовые завершения terminal-процессов, запущенные разрывом соединения
  /// (D4, D12): [dispose] ждёт их так же, как старты. Иначе выход в течение
  /// 2 с после Reconnect или падения агента не дождался бы `SIGKILL` процессу,
  /// игнорирующему `SIGTERM`. Элемент убирает сам завершившийся `Future`.
  final _pendingTerminalKills = <Future<void>>{};

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
    _sessionsBeingCreated += 1;
    final NewSessionResponse response;
    try {
      response = await _sendRequest<NewSessionResponse>(
        method: sessionNewMethod,
        params: NewSessionRequest(
          cwd: command.cwd,
          mcpServers: command.mcpServers,
          meta: command.meta,
        ),
      );
    } finally {
      _sessionsBeingCreated -= 1;
    }
    final early = _earlyUpdates.remove(response.sessionId) ?? const [];
    if (_sessionsBeingCreated == 0) {
      _earlyUpdates.clear();
    }
    var session = AcpSession(
      id: response.sessionId,
      cwd: command.cwd,
      status: SessionLifecycleStatus.active,
      modes: response.modes,
      configOptions: response.configOptions,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    // Признак незнакомого вида лежит рядом с обновлением и доходит до домена
    // (D9 change `tolerate-unknown-tool-kind`). Обновление вызова здесь всё
    // равно будет отброшено: у новой сессии нет хода, а `_applyUpdate`
    // отбрасывает обновления вызовов без хода; признак сохраняется ради
    // единообразия с реплеем.
    for (final buffered in early) {
      session = SessionStateMachine.applyUpdate(
        session,
        buffered.update,
        toolKindUnrecognized: buffered.toolKindUnrecognized,
      ).stateOrThrow;
    }

    _storeSession(session);
    return session;
  }

  Future<AcpSession> loadSession(LoadSessionCommand command) async {
    // Буфер заводится до отправки: реплей может прийти раньше, чем `await`
    // вернёт управление.
    final replay = <_BufferedUpdate>[];
    _sessionReplays[command.sessionId] = replay;
    final LoadSessionResponse response;
    try {
      response = await _sendRequest<LoadSessionResponse>(
        method: sessionLoadMethod,
        params: LoadSessionRequest(
          sessionId: command.sessionId,
          cwd: command.cwd,
          mcpServers: command.mcpServers,
          meta: command.meta,
        ),
      );
    } finally {
      // Повторный `loadSession` той же сессии заменяет буфер — чужой не
      // трогаем.
      if (identical(_sessionReplays[command.sessionId], replay)) {
        _sessionReplays.remove(command.sessionId);
      }
    }

    final replayed = SessionStateMachine.replayHistory(
      AcpSession(
        id: command.sessionId,
        cwd: command.cwd,
        status: SessionLifecycleStatus.active,
        modes: response.modes,
        configOptions: response.configOptions,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      [for (final buffered in replay) buffered.update],
      nextTurnId: () => PromptTurnId('turn-${_nextTurnId++}'),
      // Индексы признака стабильны: буфер реплея — список только для
      // добавления, которым владеет одна загрузка (D9).
      toolKindUnrecognizedAt: {
        for (var i = 0; i < replay.length; i++)
          if (replay[i].toolKindUnrecognized) i,
      },
    );
    // Ответ приходит после реплея и описывает итоговое состояние сессии,
    // поэтому его режимы и опции главнее обновлений из реплея.
    final merged = replayed.copyWith(
      modes: response.modes ?? replayed.modes,
      configOptions: response.configOptions ?? replayed.configOptions,
    );
    final session = _interruptedTurns.remove(command.sessionId)
        ? _markInterruptedTurn(merged)
        : merged;

    _storeSession(session);
    return session;
  }

  /// Последний ход реплея [session] — прерванный заменой транспорта ход:
  /// агент пишет реплику в журнал в начале хода (`agent-core` §8). Ход
  /// показывается отменённым, как его и закончил агент (D2 change
  /// `cancel-turn-on-ws-disconnect`).
  AcpSession _markInterruptedTurn(AcpSession session) {
    final last = session.turns.lastOrNull;
    if (last == null) {
      return session;
    }
    _logger
        .bind({logComponentKey: clientComponent})
        .withCorrelation(
          connectionGeneration: _generation,
          sessionId: session.id.value,
        )
        .info('turn_interrupted', context: {'turn_id': last.id.value});
    return session.copyWith(
      turns: [
        ...session.turns.take(session.turns.length - 1),
        last.copyWith(
          status: PromptTurnStatus.cancelled,
          stopReason: StopReason.cancelled,
        ),
      ],
    );
  }

  /// Страница сессий агента — `session/list` (`04-Session List.md`).
  ///
  /// [cwd] — абсолютный путь проекта, [cursor] — `nextCursor` прошлой
  /// страницы как есть: курсор непрозрачен, его не разбирают и не сохраняют
  /// между запусками. Без `sessionCapabilities.list` в ответе `initialize`
  /// (или до него) запрос не отправляется — ACP запрещает его — и бросается
  /// [AcpClientApplicationException] (design D1 change
  /// `add-session-list-and-reload`).
  Future<SessionListPage> listSessions({String? cwd, String? cursor}) async {
    final state = _connectionState;
    if (state is! ClientConnectionReady ||
        state.capabilities.sessionCapabilities.list == null) {
      throw const AcpClientApplicationException(
        'The ACP agent does not support session/list.',
      );
    }
    final response = await _sendRequest<ListSessionsResponse>(
      method: sessionListMethod,
      params: ListSessionsRequest(cwd: cwd, cursor: cursor),
    );
    return SessionListPage(
      sessions: response.sessions,
      nextCursor: response.nextCursor,
    );
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
    // Новый ход: прежний прерванный уже не последний (D2 change
    // `cancel-turn-on-ws-disconnect`).
    _interruptedTurns.remove(command.sessionId);
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
      // Метку снимает лишь ответ с `stopReason` не `cancelled`: честно
      // законченный в окне `reconnect` ход не прерван, реплей покажет его
      // ответ. Отменённый агентом (выгрузка) остаётся с меткой; ошибка
      // запроса (ветка `catch` ниже) тоже считается прерыванием.
      if (response.stopReason != StopReason.cancelled) {
        _interruptedTurns.remove(command.sessionId);
      }
      final completedSession = SessionStateMachine.completeTurn(
        _requireSession(command.sessionId),
        stopReason: response.stopReason,
        completedAt: DateTime.now(),
      ).stateOrThrow;

      _storeSession(completedSession);
      return completedSession.turns.last;
    } on Object catch (error) {
      if (generation != _generation) {
        _logStaleEvent('send_prompt_result', generation);
        rethrow;
      }
      final failedSession = SessionStateMachine.failTurn(
        _requireSession(command.sessionId),
        message: error.toString(),
        failure: _promptFailureOf(error),
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
    if (activeTurn?.status == PromptTurnStatus.cancelling) {
      return activeTurn!;
    }
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

  /// Переподключение на транспорт из фабрики.
  ///
  /// Параллельные вызовы не сериализуются здесь: это забота вызывающего.
  /// Kit вытесняет устаревшую попытку номером `_attempt`
  /// (`ClientWorkspace._reconnect`, `_isStale`), а `open` встроенного агента
  /// сериализует `EmbeddedTransportResolver` (`_tail`). Откат метки при сбое
  /// фабрики закрывает основные случаи наложения.
  Future<ClientConnectionState> reconnect(ReconnectCommand command) async {
    final createTransport = command.transportFactory ?? _reconnectTransport;
    if (createTransport == null) {
      throw const StateTransitionException(
        'reconnect requires a replacement transport factory',
      );
    }

    // Фабрика транспорта может долго открывать нового агента и при этом
    // освобождать прежнего (встроенный агент, D22 change
    // `require-project-folder`): выгрузка отменяет ход, и ответ
    // `session/prompt` приходит до `_replaceTransport`. Метка ставится до
    // фабрики, иначе ход закончился бы раньше замены и после `session/load`
    // (реплей без `stopReason`) показался бы «unknown», а не отменённым.
    final marked = _markActiveTurnsInterrupted();
    _logInterruptMark('turn_interrupt_marked', marked);
    final AcpTransport replacement;
    try {
      replacement = await createTransport();
    } on Object {
      // Откат только у сессий, чей ход ещё идёт: он остался на прежнем
      // транспорте, и чужая метка перезагрузила бы его отменённым без
      // причины. Ход, уже закончившийся в окне фабрики (выгрузка старого
      // агента отменила его, `_openSerialized` встроенного агента падает
      // позже), сохраняет метку: следующий `reconnect` загрузит его
      // отменённым, а не «unknown». Так же сохраняется метка, поставленная
      // обработчиком обрыва в этом окне.
      final rollback = {
        for (final id in marked)
          if (_sessions[id]?.activeTurn != null) id,
      };
      _interruptedTurns.removeAll(rollback);
      _logInterruptMark('turn_interrupt_mark_rolled_back', rollback);
      rethrow;
    }
    // Ядро закрыли, пока фабрика открывала транспорт: привязывать и запускать
    // его нельзя (иначе stdio-процесс агента осиротеет), только закрыть
    // (D12 change `add-client-process-shutdown-on-exit`).
    if (_disposed) {
      await _closeUnusedTransport(replacement);
      throw const AcpClientApplicationException('ACP application disposed.');
    }
    await _replaceTransport(replacement, closeTimeout: command.closeTimeout);

    return _establishConnection();
  }

  /// Starts the freshly bound transport and performs the ACP `initialize`
  /// handshake required before any session operation, per
  /// `docs/protocols/acp/protocol/02-Initialization.md`.
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
    // Процесс агента завершает сам транспорт: [dispose] уже вызвал его
    // `close`, и мемоизированное закрытие подхватило запуск (D12, D13).
    if (_disposed) {
      throw const AcpClientApplicationException('ACP application disposed.');
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
    final previousState = _connectionState;
    _connectionState = ConnectionStateMachine.reduce(
      _connectionState,
      event,
    ).stateOrThrow;

    // Structured lifecycle event (OBS-001) — single choke point for every
    // connection state transition, see `docs/architecture/observability.md`
    // §6.
    final connectionLogger = _logger
        .bind({logComponentKey: clientComponent})
        .withCorrelation(connectionGeneration: _generation);
    final logContext = {
      'from': previousState.runtimeType.toString(),
      'to': _connectionState.runtimeType.toString(),
    };
    if (_connectionState is ClientConnectionFailed) {
      connectionLogger.warning('connection_state_changed', context: logContext);
    } else {
      connectionLogger.info('connection_state_changed', context: logContext);
    }

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
      final killing = _killAllTerminalProcesses(
        _TerminalKillReason.connectionClosed,
      );
      _pendingTerminalKills.add(killing);
      // `_killAllTerminalProcesses` ошибок не бросает (сбои изолированы), так
      // что `unawaited` не теряет ошибок (§12).
      unawaited(
        killing.whenComplete(() => _pendingTerminalKills.remove(killing)),
      );
    }
  }

  /// Помечает сессии с идущим ходом прерванными и возвращает те, что
  /// помечены впервые, чтобы вызывающий мог снять метку при отказе.
  ///
  /// Почему общий метод: метка нужна и до открытия нового транспорта
  /// ([reconnect]), и при самой замене ([_replaceTransport]) (D2 change
  /// `cancel-turn-on-ws-disconnect`).
  void _logInterruptMark(String event, Set<SessionId> ids) {
    for (final id in ids) {
      _logger
          .bind({logComponentKey: clientComponent})
          .withCorrelation(
            connectionGeneration: _generation,
            sessionId: id.value,
          )
          .debug(event);
    }
  }

  Set<SessionId> _markActiveTurnsInterrupted() => {
    for (final session in _sessions.values)
      if (session.activeTurn != null && _interruptedTurns.add(session.id))
        session.id,
  };

  Future<void> _replaceTransport(
    AcpTransport transport, {
    Duration? closeTimeout,
  }) async {
    // Поколение растёт до первого `await` ниже: операции, ещё идущие на
    // старом транспорте, увидят новое поколение, как только продолжатся,
    // даже если их продолжение запланировано, пока этот метод закрывает
    // старый транспорт (§9, поздние события).
    _generation++;
    // Ход, шедший в момент замены, агент отменил вместе с соединением; ход
    // остаётся `running` до `session/load`, который и покажет его
    // отменённым (D2 change `cancel-turn-on-ws-disconnect`).
    _markActiveTurnsInterrupted();
    // Одобрения и карты запросов снимаются синхронно, до первого `await`:
    // иначе ответ пользователя успел бы уйти в старый транспорт, а одобрение
    // потом стало бы `cancelled` (агент получил бы allow, состояние —
    // cancelled), а устаревший id попал бы в `_handledPermissionRequests` и
    // проглотил бы запрос нового соединения с тем же JSON-RPC id (ровно один
    // ответ, AGENTS.md §10).
    _dropPendingApprovals('ACP transport was replaced.');
    _pendingPermissionRequests.clear();
    _handledPermissionRequests.clear();
    await _inboundSubscription.cancel();
    await _eventSubscription.cancel();
    _failPendingRequests(
      const AcpClientApplicationException('ACP transport was replaced.'),
    );
    await _transport.close(timeout: closeTimeout);

    // [dispose] мог прийти, пока закрывался прежний транспорт: новый не
    // привязывается и не запускается (D12 change
    // `add-client-process-shutdown-on-exit`).
    if (_disposed) {
      await _closeUnusedTransport(transport);
      throw const AcpClientApplicationException('ACP application disposed.');
    }

    _transport = transport;
    _bindTransport();
  }

  /// Закрывает транспорт, который так и не был привязан к ядру.
  ///
  /// Почему ошибки глотаются: исключение закрытия не должно заслонять
  /// причину отказа подключения («ядро закрыто»); `close()` не запущенного
  /// транспорта мгновенный (D12).
  Future<void> _closeUnusedTransport(AcpTransport transport) async {
    try {
      await transport.close();
    } on Object {
      // Нечего делать: транспорт не использовался и не принадлежит ядру.
    }
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

  /// Закрывает ядро клиента: снимает подписки, завершает terminal-процессы и
  /// закрывает транспорт.
  ///
  /// Почему параллельно: завершение процесса может занять до ~2 s
  /// (`SIGTERM` → `SIGKILL`), закрытие stdio-транспорта — ещё до 2+2 s; вместе
  /// друг за другом они выходят за общий предел выхода приложения (D4 change
  /// `add-client-process-shutdown-on-exit`). Порядок между ними ACP не
  /// задаёт, а входящая подписка снята до обоих шагов — агент уже не пришлёт
  /// `terminal/*`.
  ///
  /// Почему мемоизирован и окончателен (D12): вызов может прийти во время
  /// Connect, Reconnect или старта `terminal/create`. Первым синхронным
  /// действием ставится флаг «закрыто»; идущие операции видят его после
  /// своего `await`, не привязывают новый транспорт, не регистрируют
  /// запущенный процесс и завершаются `AcpClientApplicationException`.
  /// Повторный вызов возвращает тот же `Future`.
  ///
  /// Как использовать: composition root передаёт [closeTimeout] — предел
  /// корректного закрытия транспорта (`AcpTransport.close(timeout:)`); без
  /// него поведение прежнее. Повторный вызов не шлёт сигналов: реестр пуст.
  Future<void> dispose({Duration? closeTimeout}) {
    _disposed = true;
    return _disposing ??= _dispose(closeTimeout);
  }

  Future<void> _dispose(Duration? closeTimeout) async {
    await _inboundSubscription.cancel();
    await _eventSubscription.cancel();
    _failPendingRequests(
      const AcpClientApplicationException('ACP application disposed.'),
    );
    _pendingPermissionRequests.clear();
    _handledPermissionRequests.clear();
    await Future.wait([
      _killAllTerminalProcesses(_TerminalKillReason.dispose),
      Future.wait(_pendingTerminalStarts.toList(growable: false)),
      Future.wait(_pendingTerminalKills.toList(growable: false)),
      _transport.close(timeout: closeTimeout),
    ]);
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
      await _sendTracedMessage(
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

    // Таймер снимает запрос, если агент молчит: ответ после этого
    // [_completePendingRequest] уже не найдёт и только запишет в журнал.
    final timer = method == sessionPromptMethod
        ? null
        : Timer(_requestTimeout, () {
            if (!identical(_pendingRequests[id], pending)) {
              return;
            }
            _pendingRequests.remove(id);
            _logger
                .bind({logComponentKey: protocolComponent})
                .withCorrelation(
                  connectionGeneration: _generation,
                  requestId: id.toJsonValue().toString(),
                )
                .warning(
                  'request_timeout',
                  context: {
                    'method': method,
                    'timeout_ms': _requestTimeout.inMilliseconds,
                  },
                );
            pending.completeError(
              AcpRequestTimeoutException(
                method: method,
                timeout: _requestTimeout,
              ),
            );
          });
    final Object result;
    try {
      result = await pending.future;
    } finally {
      timer?.cancel();
    }
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
      await _sendTracedMessage(
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

  /// Sends [message] over the transport, tracing its full raw payload to
  /// the developer-only protocol-trace channel first — a single choke
  /// point covering every outbound ACP wire message (`design.md`
  /// Decision 4/6), used in place of `_transport.send(...)` everywhere in
  /// this class.
  Future<void> _sendTracedMessage(JsonRpcMessage message) {
    _traceProtocolMessage('outbound', message);
    return _transport.send(message);
  }

  void _traceProtocolMessage(String direction, JsonRpcMessage message) {
    _protocolTraceLogger
        .withCorrelation(connectionGeneration: _generation)
        .trace(
          'protocol_message',
          context: {'direction': direction, 'payload': message.toJson()},
        );
  }

  void _bindTransport() {
    final boundGeneration = _generation;
    _inboundSubscription = _transport.inbound.listen((message) {
      if (boundGeneration != _generation) {
        _logStaleEvent('inbound_message', boundGeneration);
        return;
      }
      _traceProtocolMessage('inbound', message);
      _handleInboundMessage(message);
    });
    _eventSubscription = _transport.events.listen((event) {
      if (boundGeneration != _generation) {
        _logStaleEvent('transport_event', boundGeneration);
        return;
      }
      _handleTransportEvent(event);
    });
  }

  /// Logs an event discarded because it belongs to a superseded transport
  /// generation — see `docs/architecture/observability.md` §20. Tagged
  /// with [eventGeneration] (the stale event's own generation), not the
  /// current one, so it can be told apart from the connection that
  /// superseded it.
  ///
  /// Для устаревших ответов на `terminal/*` вызывающий добавляет [method] и
  /// [requestId] запроса (§16): без них нельзя понять, какой запрос остался
  /// без ответа. Оба поля — не секреты.
  void _logStaleEvent(
    String kind,
    int eventGeneration, {
    String? method,
    JsonRpcId? requestId,
  }) {
    _logger
        .bind({logComponentKey: transportComponent})
        .withCorrelation(connectionGeneration: eventGeneration)
        .debug(
          'event_ignored',
          context: {
            'reason': 'stale_generation',
            'kind': kind,
            'method': ?method,
            'request_id': ?requestId?.toJsonValue().toString(),
          },
        );
  }

  /// Снимает ожидающие одобрения: запрос принадлежит оборванному соединению.
  ///
  /// Почему: ответ на `session/request_permission` возможен только в том
  /// соединении, которое его прислало (D22 change `require-project-folder`);
  /// без снятия сессия, не восстановленная в новом соединении, навсегда
  /// сохраняла бы одобрение, на которое некуда ответить, а позднее решение
  /// ушло бы в чужое соединение (AGENTS.md §9, §10).
  ///
  /// Для чего: источник истины сессии — одобрение становится `cancelled`
  /// (ход возвращается из `awaitingApproval`), поэтому проекции хостов,
  /// `respondToPermission` и `session/load` видят одно состояние. Следующий
  /// `session/load` пересоберёт ход по реплею агента. Журнал содержит только
  /// идентификаторы, без аргументов вызова.
  void _dropPendingApprovals(String reason) {
    final dropped = <(AcpSession, ApprovalRequest)>[];
    for (final session in _sessions.values.toList(growable: false)) {
      var updated = session;
      for (final turn in session.turns) {
        for (final approval in turn.approvals.values) {
          if (approval.status != ApprovalStatus.pending) {
            continue;
          }
          final result = SessionStateMachine.cancelApproval(
            updated,
            approvalId: approval.id,
            resolvedAt: DateTime.now(),
          );
          if (result is AppliedStateTransition<AcpSession>) {
            updated = result.state;
            dropped.add((session, approval));
          }
        }
      }
      if (!identical(updated, session)) {
        _storeSession(updated);
      }
    }
    // Журнал пишется после цикла: `_recordDiagnostic` пересохраняет сессии из
    // `_sessions`, и запись внутри цикла была бы затёрта последующим
    // `_storeSession(updated)` копией без неё.
    for (final (session, approval) in dropped) {
      _recordDiagnostic(
        message: 'Pending permission request dropped: $reason',
        severity: DiagnosticSeverity.warning,
        source: 'application.permission',
        sessionId: session.id.value,
        toolCallId: approval.toolCall.id.value,
        context: {
          'sessionId': session.id.value,
          'approvalId': approval.id.value,
          'toolCallId': approval.toolCall.id.value,
        },
      );
    }
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
        // A notification gets no reply, so an unknown one (e.g. a custom
        // `_vendor/...` extension) is simply not our concern.
        break;
      case JsonRpcRequest():
        unawaited(_rejectUnsupportedRequest(message));
    }
  }

  /// Answers a request this client does not handle with `-32601 Method not
  /// found`. JSON-RPC requires a reply to every request, and ACP spells this
  /// out for unrecognized custom methods (`15-Extensibility.md`); staying
  /// silent would leave the agent waiting forever. Only the method and id are
  /// logged: the params of an unknown request may carry secrets.
  Future<void> _rejectUnsupportedRequest(JsonRpcRequest request) async {
    _recordDiagnostic(
      message: 'Rejected unsupported agent request ${request.method}.',
      severity: DiagnosticSeverity.warning,
      source: 'application.protocol',
      context: {
        'method': request.method,
        'requestId': request.id.toJsonValue(),
      },
    );
    await _sendAcpMethodError(
      request.id,
      method: request.method,
      error: AcpProtocolError.unknownMethod(request.method),
    );
  }

  void _completePendingRequest(JsonRpcResponse response) {
    final pending = _pendingRequests.remove(response.id);
    if (pending == null) {
      // Запрос уже снят — по таймауту или при замене транспорта; поздний
      // ответ состояние не меняет (spec acp-protocol-client «Таймаут
      // исходящих запросов»).
      _logger
          .bind({logComponentKey: protocolComponent})
          .withCorrelation(
            connectionGeneration: _generation,
            requestId: response.id.toJsonValue().toString(),
          )
          .debug('response_ignored', context: {'reason': 'no_pending_request'});
      return;
    }
    if (response.error != null) {
      _recordDiagnostic(
        message:
            'ACP request ${pending.method} failed: ${response.error?.message}',
        severity: DiagnosticSeverity.error,
        source: 'application.protocol',
        cause: response.error,
        requestId: response.id.toJsonValue().toString(),
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
        requestId: response.id.toJsonValue().toString(),
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

      // До проверки активного хода: запрос, отвеченный `cancelled` из-за
      // отсутствия хода, тоже фиксируется (D4).
      final toolKindUnrecognized = _logUnrecognizedToolKind(
        rawToolCall: _rawField(request.params, 'toolCall'),
        method: request.method,
        sessionId: permissionRequest.sessionId.value,
        toolCallId: permissionRequest.toolCall.toolCallId.value,
      );

      final session = _sessions[permissionRequest.sessionId];
      final activeTurn = session?.activeTurn;
      // A cancelling turn answers late permission requests `cancelled` like
      // a missing turn (05-Prompt Turn.md#cancellation).
      if (session == null ||
          activeTurn == null ||
          activeTurn.status == PromptTurnStatus.cancelling) {
        _sendCancelledPermissionResponse(request.id);
        _handledPermissionRequests.add(approvalId);
        return;
      }

      final toolCall = _toolCallRecordFromUpdate(
        permissionRequest.toolCall,
        known: activeTurn.toolCalls[permissionRequest.toolCall.toolCallId],
        toolKindUnrecognized: toolKindUnrecognized,
      );
      final approval = ApprovalRequest(
        id: approvalId,
        sessionId: permissionRequest.sessionId,
        turnId: activeTurn.id,
        toolCall: toolCall,
        options: permissionRequest.options,
        riskLevel: toolCall.riskLevel,
        critical:
            _isCritical(permissionRequest.meta) ||
            _isCritical(permissionRequest.toolCall.meta),
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
      await _sendTracedMessage(
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
    } on FsNotFoundFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        method: fsReadTextFileMethod,
        error: AcpProtocolError.resourceNotFound('$error'),
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
      await _sendTracedMessage(
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

  /// Обрабатывает входящий `terminal/create`: запускает процесс и сразу
  /// возвращает его [TerminalId], не дожидаясь завершения.
  ///
  /// Почему без approval: для `terminal/*` собственного гейта нет, вместо него
  /// обязателен containment `cwd` рабочей папкой сессии (`AGENTS.md` §10;
  /// `add-acp-terminal-client-support/design.md`, Decision 2). Выход за
  /// границы отклоняется до запуска. Ожидание завершения — отдельный вызов
  /// `terminal/wait_for_exit`.
  ///
  /// Если за время старта ядро закрыто или соединение сменилось, процесс
  /// завершается, в реестр не попадает, ответа нет, а в журнал пишется
  /// `event_ignored` с методом и id запроса (D12, D15, §9).
  Future<void> _handleCreateTerminalRequest(JsonRpcRequest request) async {
    // Поколение запроса: ответ уходит только в его соединение (D15).
    final generation = _generation;
    final runner = _terminalProcessRunner;
    if (runner == null) {
      await _sendAcpMethodError(
        request.id,
        generation: generation,
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
          generation: generation,
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

      // Старт и возможное завершение «опоздавшего» процесса — один `Future`
      // в [_pendingTerminalStarts]: [dispose] ждёт его, иначе процесс,
      // запущенный после очистки реестра, остался бы без владельца (D12).
      final startSettled = Completer<void>();
      _pendingTerminalStarts.add(startSettled.future);
      final TerminalId terminalId;
      try {
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

        // Ядро закрыто или соединение сменилось, пока процесс стартовал:
        // реестр уже очищен, регистрировать нельзя, ответ некому.
        if (_disposed || generation != _generation) {
          // Сначала запускаем завершение, потом журнал в `try`: сбой
          // логгера не должен оставить процесс без владельца (D15).
          final killing = _killIsolated(handle);
          try {
            _logStaleEvent(
              'terminal_create_result',
              generation,
              method: terminalCreateMethod,
              requestId: request.id,
            );
          } on Object {
            // Намеренно пусто: см. комментарий выше.
          }
          await killing;
          return;
        }
        terminalId = _newTerminalId(request.id);
        (_terminals[createRequest.sessionId] ??= {})[terminalId] = handle;
      } finally {
        startSettled.complete();
        _pendingTerminalStarts.remove(startSettled.future);
      }

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

      await _sendTerminalResponse(
        generation,
        terminalCreateMethod,
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
        generation: generation,
        method: terminalCreateMethod,
        error: AcpProtocolError.invalidAcpParams(
          method: terminalCreateMethod,
          message: error.toString(),
        ),
      );
    } on TerminalStartFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        generation: generation,
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
        generation: generation,
        method: terminalCreateMethod,
        error: AcpProtocolError.internalError(
          'Failed to start terminal: $error',
        ),
      );
    }
  }

  /// Обрабатывает входящий `terminal/output`: отдаёт накопленный вывод и, если
  /// процесс вышел, статус выхода.
  ///
  /// Ответ принадлежит соединению запроса: устаревший ответ не отправляется
  /// (D15, §9). Неизвестный [TerminalId] — `invalidAcpParams`.
  Future<void> _handleTerminalOutputRequest(JsonRpcRequest request) async {
    // Поколение запроса: ответ уходит только в его соединение (D15).
    final generation = _generation;
    if (_terminalProcessRunner == null) {
      await _sendAcpMethodError(
        request.id,
        generation: generation,
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

      await _sendTerminalResponse(
        generation,
        terminalOutputMethod,
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
        generation: generation,
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
        generation: generation,
        method: terminalOutputMethod,
        error: AcpProtocolError.internalError(
          'Failed to read terminal output: $error',
        ),
      );
    }
  }

  /// Обрабатывает входящий `terminal/wait_for_exit`: отвечает после выхода
  /// процесса его кодом или сигналом.
  ///
  /// Почему отдельно от `create`: ACP делит запуск и ожидание. Пока процесс
  /// работает, соединение могло смениться — тогда ответ не отправляется
  /// (D15, §9). Неизвестный [TerminalId] — `invalidAcpParams`.
  Future<void> _handleWaitForTerminalExitRequest(JsonRpcRequest request) async {
    // Поколение запроса: ответ уходит только в его соединение (D15).
    final generation = _generation;
    if (_terminalProcessRunner == null) {
      await _sendAcpMethodError(
        request.id,
        generation: generation,
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
      await _sendTerminalResponse(
        generation,
        terminalWaitForExitMethod,
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
        generation: generation,
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
        generation: generation,
        method: terminalWaitForExitMethod,
        error: AcpProtocolError.internalError(
          'Failed to wait for terminal exit: $error',
        ),
      );
    }
  }

  /// Обрабатывает входящий `terminal/kill`: завершает процесс, не удаляя
  /// [TerminalId] из реестра.
  ///
  /// Почему не ошибка для вышедшего процесса: `TerminalProcessHandle.kill`
  /// для него no-op и сам гарантирует атомарность (design.md, Risks).
  /// `SIGTERM`, затем `SIGKILL` не позже ~2 с (D4). Ответ уходит только в
  /// соединение запроса (D15, §9). После kill агент всё ещё читает вывод и
  /// должен вызвать `terminal/release`.
  Future<void> _handleKillTerminalCommandRequest(JsonRpcRequest request) async {
    // Поколение запроса: ответ уходит только в его соединение (D15).
    final generation = _generation;
    if (_terminalProcessRunner == null) {
      await _sendAcpMethodError(
        request.id,
        generation: generation,
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

      await _sendTerminalResponse(
        generation,
        terminalKillMethod,
        encodeAcpResponse(
          id: request.id,
          method: terminalKillMethod,
          result: const KillTerminalCommandResponse(),
        ),
      );
    } on UnknownTerminalFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        generation: generation,
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
        generation: generation,
        method: terminalKillMethod,
        error: AcpProtocolError.internalError(
          'Failed to kill terminal: $error',
        ),
      );
    }
  }

  /// Обрабатывает входящий `terminal/release`: завершает процесс и удаляет
  /// [TerminalId] из реестра сессии.
  ///
  /// В отличие от `kill`, любой следующий вызов с этим id, включая повторный
  /// `release`, даёт [UnknownTerminalFailure] (design.md, Decision 3). Запись
  /// удаляется только если в ней тот же handle: пока `kill()` шёл, Reconnect
  /// мог очистить реестр, а новый агент — создать процесс с тем же id (D15, §9).
  Future<void> _handleReleaseTerminalRequest(JsonRpcRequest request) async {
    // Поколение запроса: ответ уходит только в его соединение (D15).
    final generation = _generation;
    if (_terminalProcessRunner == null) {
      await _sendAcpMethodError(
        request.id,
        generation: generation,
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
      // За время `kill()` Reconnect мог очистить реестр, а новый агент —
      // создать процесс с тем же `terminalId` (id запросов нумеруются заново):
      // удаляем запись только если в ней всё ещё наш handle (D15, §9).
      final sessionTerminals = _terminals[releaseRequest.sessionId];
      if (identical(sessionTerminals?[releaseRequest.terminalId], handle)) {
        sessionTerminals!.remove(releaseRequest.terminalId);
      }

      await _sendTerminalResponse(
        generation,
        terminalReleaseMethod,
        encodeAcpResponse(
          id: request.id,
          method: terminalReleaseMethod,
          result: const ReleaseTerminalResponse(),
        ),
      );
    } on UnknownTerminalFailure catch (error) {
      await _sendAcpMethodError(
        request.id,
        generation: generation,
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
        generation: generation,
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

  /// Завершает terminal-процессы всех сессий, не освобождая их записи в
  /// реестре как `terminal/release`.
  ///
  /// Почему: страховка при разрыве соединения (самопроизвольный обрыв, новый
  /// `connect()`/`reconnect()` поверх прежнего) и при [dispose], а не
  /// корректный `terminal/release` от имени агента (design.md, Decision 6
  /// `add-acp-terminal-client-support`).
  ///
  /// Как работает (D15 change `add-client-process-shutdown-on-exit`): реестр
  /// очищается один раз; сначала запускаются все `kill()`, затем в `try`
  /// пишется событие журнала, затем ожидаются `kill()`. Так сбой логгера не
  /// оставит процессы живыми (реестр уже пуст, повторный вызов их не найдёт)
  /// и не выйдет исключением из [dispose]. Событие `terminal_processes_killed`
  /// содержит только число и причину — без команд, `cwd` и `terminalId` (D6).
  Future<void> _killAllTerminalProcesses(_TerminalKillReason reason) async {
    final handles = _terminals.values
        .expand((session) => session.values)
        .toList(growable: false);
    _terminals.clear();
    if (handles.isEmpty) {
      return;
    }

    final kills = [for (final handle in handles) _killIsolated(handle)];
    try {
      _logger
          .bind({logComponentKey: clientComponent})
          .withCorrelation(connectionGeneration: _generation)
          .info(
            'terminal_processes_killed',
            context: {'count': handles.length, 'reason': reason.logName},
          );
    } on Object {
      // Писать о сбое журнала некуда (как в `CodeLabRootLifecycle._step`,
      // D5): процессы уже завершаются, выход не должен упасть из-за логгера.
    }
    await Future.wait(kills);
  }

  /// Завершает один процесс, изолируя сбой адаптера.
  ///
  /// Почему: сбой одного `kill()` не должен помешать остальным, а
  /// fire-and-forget вызов из `_transitionConnection` не должен порождать
  /// необработанную асинхронную ошибку. Первый `kill()` вызывается
  /// синхронно, до первого `await`.
  Future<void> _killIsolated(TerminalProcessHandle handle) async {
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
  }

  /// Отправляет ответ на `terminal/*`, только если он ещё нужен (D15).
  ///
  /// Почему: обработчики `kill`/`release`/`wait_for_exit` ждут процесс, и за
  /// это время Reconnect может заменить транспорт. Нумерация JSON-RPC id у
  /// нового агента начинается заново, поэтому ответ старого соединения мог бы
  /// подменить результат чужого запроса (`AGENTS.md` §9). После [dispose]
  /// ответ уходит в закрытый транспорт и порождает ложную диагностику.
  ///
  /// [method] и id ответа попадают в запись `event_ignored` (§16): по ним
  /// видно, какой именно запрос остался без ответа; секретов в них нет.
  Future<void> _sendTerminalResponse(
    int generation,
    String method,
    JsonRpcResponse message,
  ) {
    if (_isStaleTerminalResponse(generation, method, message.id)) {
      return Future<void>.value();
    }
    return _sendTracedMessage(message);
  }

  /// `true` и запись `event_ignored`, если ответ принадлежит закрытому ядру
  /// или прежнему соединению ([generation] — поколение запроса).
  bool _isStaleTerminalResponse(int generation, String method, JsonRpcId id) {
    if (!_disposed && generation == _generation) {
      return false;
    }
    _logStaleEvent(
      'terminal_response',
      generation,
      method: method,
      requestId: id,
    );
    return true;
  }

  Future<void> _sendAcpMethodError(
    JsonRpcId id, {
    required String method,
    required AcpProtocolError error,
    int? generation,
  }) async {
    // Ошибка на `terminal/*` тоже принадлежит соединению запроса (D15);
    // [generation] передают только обработчики `terminal/*`.
    if (generation != null &&
        _isStaleTerminalResponse(generation, method, id)) {
      return;
    }
    try {
      await _sendTracedMessage(
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
    final unsupportedKind = unsupportedSessionUpdateKind(notification.params);
    if (unsupportedKind != null) {
      _skipUnsupportedSessionUpdate(notification, unsupportedKind);
      return;
    }

    try {
      final sessionNotification =
          decodeAcpNotificationParams(notification) as SessionNotification;
      final update = sessionNotification.update;
      // Признак считается один раз по сырым params и едет рядом с
      // обновлением через буферы реплея и раннего применения (D4, D9). Запись
      // журнала пишется при приёме, до буферов: реплей тоже фиксируется.
      var toolKindUnrecognized = false;
      final toolCallId = switch (update) {
        ToolCallSessionUpdate(:final toolCall) => toolCall.toolCallId,
        ToolCallUpdateSessionUpdate(:final toolCallUpdate) =>
          toolCallUpdate.toolCallId,
        _ => null,
      };
      if (toolCallId != null) {
        final recognizedAsUnknown = _logUnrecognizedToolKind(
          rawToolCall: _rawField(notification.params, 'update'),
          method: notification.method,
          sessionId: sessionNotification.sessionId.value,
          toolCallId: toolCallId.value,
          sessionUpdate: update is ToolCallSessionUpdate
              ? 'tool_call'
              : 'tool_call_update',
        );
        // `tool_call` признак не получает: его вид — `other` без записи, на
        // которую можно опереться (D9).
        toolKindUnrecognized =
            recognizedAsUnknown && update is ToolCallUpdateSessionUpdate;
      }
      final buffered = (
        update: update,
        toolKindUnrecognized: toolKindUnrecognized,
      );

      final replay = _sessionReplays[sessionNotification.sessionId];
      // Реплей загружаемой сессии идёт в буфер, даже если сессия с тем же id
      // уже есть: история заменит прежнее состояние после ответа.
      if (replay != null) {
        replay.add(buffered);
        return;
      }

      final session = _sessions[sessionNotification.sessionId];
      if (session == null) {
        if (_sessionsBeingCreated > 0) {
          (_earlyUpdates[sessionNotification.sessionId] ??= []).add(buffered);
        }
        return;
      }

      final next = SessionStateMachine.applyUpdate(
        session,
        update,
        toolKindUnrecognized: toolKindUnrecognized,
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

  /// Поле сырого объекта `params` (`update` / `toolCall`) или `null`.
  ///
  /// Почему сырой payload: после мягкого разбора (D1) незнакомый вид в DTO
  /// неотличим от явного `other`, поэтому признак «вид незнаком» считается по
  /// исходным данным (D4).
  Object? _rawField(Object? params, String name) =>
      params is Map ? params[name] : null;

  /// Пишет одну запись WARN, если сырой `kind` вызова незнаком клиенту, и
  /// возвращает, был ли он незнаком.
  ///
  /// Почему журнал, а не [_recordDiagnostic]: деградация (вид сведён к
  /// `other`, D1) не мешает работе, а диагностика сессий добавляла бы запись
  /// каждой сессии и публиковала состояние на каждое такое сообщение — по той
  /// же причине, что и у [_skipUnsupportedSessionUpdate]. Уровень WARN, а не
  /// DEBUG: клиент не пропускает данные, а меняет их смысл, и это должно быть
  /// видно в release-журнале без трассировки (D4; `observability.md` §8).
  ///
  /// Без payload (`observability.md` §11): только корреляция и усечённое
  /// до 64 символов значение вида, пропущенное через [SecretRedactor].
  /// Полный кадр остаётся в developer-only protocol-трассировке.
  ///
  /// Как использовать: вызывать сразу после успешного разбора, до ветвления
  /// на буферы и проверку активного хода; [sessionUpdate] — только для
  /// `session/update`.
  bool _logUnrecognizedToolKind({
    required Object? rawToolCall,
    required String method,
    required String sessionId,
    required String toolCallId,
    String? sessionUpdate,
  }) {
    final rawKind = unrecognizedToolKind(rawToolCall);
    if (rawKind == null) {
      return false;
    }
    // Сначала маскирование по полной строке, затем усечение (D4): обратный
    // порядок разрезал бы секрет (PEM-блок) до того, как шаблон его узнает, и
    // фрагмент ушёл бы в журнал без маскирования.
    final redacted = _redactor.redactText(rawKind);
    final truncated = redacted.length > 64
        ? redacted.substring(0, 64)
        : redacted;
    _logger
        .bind({logComponentKey: protocolComponent})
        .withCorrelation(
          connectionGeneration: _generation,
          sessionId: sessionId,
          toolCallId: toolCallId,
        )
        .warning(
          'Unknown ACP tool kind treated as other.',
          context: {
            'source': 'application.protocol',
            'method': method,
            'sessionUpdate': ?sessionUpdate,
            'toolKind': truncated,
          },
        );
    return true;
  }

  /// A `session/update` of a kind this client does not model (e.g.
  /// `usage_update`) has nothing to apply, so it is dropped, not reported as an
  /// error. It goes to the structured log only: [_recordDiagnostic] would add
  /// an entry to every session and to the Debug log panel on each such update,
  /// and some agents send them several times per turn.
  ///
  /// Two records with the same text: the application one (console,
  /// `application.log`, remote log server) carries only the kind and the
  /// session id, because the payload may contain user text and raw protocol
  /// dumps must not reach release logs by default
  /// (`observability.md` §11). The payload goes to the developer-only
  /// protocol-trace channel, secrets masked by the shared redaction processor.
  void _skipUnsupportedSessionUpdate(
    JsonRpcNotification notification,
    String kind,
  ) {
    const message = 'Skipped unsupported ACP session update.';
    final params = notification.params;
    final sessionId = params is Map<String, dynamic>
        ? params['sessionId']
        : null;
    final sessionIdValue = sessionId is String ? sessionId : null;

    _logger
        .bind({logComponentKey: protocolComponent})
        .withCorrelation(
          connectionGeneration: _generation,
          sessionId: sessionIdValue,
        )
        .debug(
          message,
          context: {'source': 'application.protocol', 'sessionUpdate': kind},
        );
    _protocolTraceLogger
        .bind({logComponentKey: protocolComponent})
        .withCorrelation(
          connectionGeneration: _generation,
          sessionId: sessionIdValue,
        )
        .debug(
          message,
          context: {
            'source': 'application.protocol',
            'sessionUpdate': kind,
            'payload': params,
          },
        );
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
          component: transportComponent,
        );
      case AcpTransportFailure(:final error):
        _recordDiagnostic(
          message: error.message,
          severity: DiagnosticSeverity.error,
          source: 'transport',
          component: transportComponent,
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
        final wasReady = _connectionState is ClientConnectionReady;
        // Агент может завершиться и во время `initialize` (неверные
        // аргументы, сбой старта): ответа на него тоже не будет, и `connect`
        // не должен ждать таймаута запроса (tasks 3.6 change
        // `add-codelab-cli`).
        final wasInitializing =
            _connectionState is ClientConnectionInitializing;
        if (wasReady) {
          // Агент отменяет ход вместе с соединением, как и при замене
          // транспорта: после `session/load` последний ход реплея будет
          // показан отменённым (D2 change `cancel-turn-on-ws-disconnect`).
          for (final session in _sessions.values) {
            if (session.activeTurn != null) {
              _interruptedTurns.add(session.id);
            }
          }
        }
        if (_connectionState is! ClientConnectionDisconnected) {
          _transitionConnection(
            ConnectionStateEvent.fail(
              reason: _connectionFailureReasonFor(error.code),
              message: error.message,
              cause: error.cause,
            ),
          );
        }
        if (wasReady || wasInitializing) {
          // Ответов на запросы оборванного соединения не будет: без этого
          // `sendPrompt` ждал бы вечно, а ход оставался `running` (design D2
          // change `add-connection-and-error-states`).
          _failPendingRequests(AcpConnectionLostException(error.message));
          _dropPendingApprovals('ACP connection was lost.');
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
    final generation = _generation;

    try {
      await _sendTracedMessage(
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
        requestId: pending.requestId.toJsonValue().toString(),
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

    // Соединение могло смениться, пока уходил ответ: карты уже очищены для
    // нового соединения, и устаревший id в них не возвращается.
    if (generation == _generation) {
      _pendingPermissionRequests.remove(approvalId);
      _handledPermissionRequests.add(approvalId);
    }
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
            requestId: requestId.toJsonValue().toString(),
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
    String? component,
    String? sessionId,
    String? requestId,
    String? toolCallId,
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
    while (_diagnostics.length > _maxDiagnostics) {
      _diagnostics.removeAt(0);
    }
    if (!_diagnosticController.isClosed) {
      _diagnosticController.add(entry);
    }

    for (final session in _sessions.values.toList(growable: false)) {
      _storeSession(
        session.copyWith(diagnostics: [...session.diagnostics, entry]),
      );
    }

    _logDiagnosticEntry(
      entry,
      component: component ?? _componentForSource(source),
      sessionId: sessionId,
      requestId: requestId,
      toolCallId: toolCallId,
    );
  }

  /// Emits [entry] (already redacted by [_recordDiagnostic] — reused as-is,
  /// not re-derived, so both `DiagnosticEntry` and this structured event
  /// come from a single redaction pass, see `design.md` Decision 3) through
  /// the structured Logger, tagged with layer ownership and correlation.
  void _logDiagnosticEntry(
    DiagnosticEntry entry, {
    required String component,
    String? sessionId,
    String? requestId,
    String? toolCallId,
  }) {
    final logger = _logger
        .bind({logComponentKey: component})
        .withCorrelation(
          connectionGeneration: _generation,
          sessionId: sessionId,
          requestId: requestId,
          toolCallId: toolCallId,
        );
    final logContext = {
      if (entry.source != null) 'source': entry.source,
      ...entry.context,
      if (entry.cause != null) 'cause': entry.cause,
    };

    switch (entry.severity) {
      case DiagnosticSeverity.debug:
        logger.debug(entry.message, context: logContext);
      case DiagnosticSeverity.info:
        logger.info(entry.message, context: logContext);
      case DiagnosticSeverity.warning:
        logger.warning(entry.message, context: logContext);
      case DiagnosticSeverity.error:
        logger.error(entry.message, context: logContext);
    }
  }

  /// Derives layer ownership from the existing `source` naming convention
  /// (`application.protocol` → protocol decode/encode failures) when the
  /// call site did not pass an explicit `component` — see `design.md`
  /// Decision "Логирование по слоям согласно ownership".
  String _componentForSource(String? source) {
    if (source == 'application.protocol') {
      return protocolComponent;
    }
    return clientComponent;
  }

  ApprovalRequestId _approvalRequestId(JsonRpcId requestId) {
    return ApprovalRequestId('permission-${requestId.toJsonValue()}');
  }

  /// Запись вызова для запроса одобрения; [known] — запись хода с тем же
  /// `toolCallId`. Риск считает общее правило `ApprovalPolicy` (review 6b,
  /// L-1): запрос без `kind` берёт вид известного вызова, а риск не ниже
  /// уже известного.
  ///
  /// [toolKindUnrecognized] (D9 change `tolerate-unknown-tool-kind`): вид в
  /// запросе был незнаком кодеку и сведён к `other`; метка берётся из [known]
  /// (без записи — `other`), а риск по-прежнему `max(риск записи, unknown)`
  /// из `kind: other` в DTO. Явный `other` агента признака не получает и
  /// перезаписывает вид.
  ToolCallRecord _toolCallRecordFromUpdate(
    ToolCallUpdate update, {
    ToolCallRecord? known,
    bool toolKindUnrecognized = false,
  }) {
    final riskLevel = ApprovalPolicy.classifyToolCallUpdateWithin(
      known,
      update,
    );
    return ToolCallRecord(
      id: update.toolCallId,
      title: update.title ?? update.toolCallId.value,
      kind: toolKindUnrecognized && known != null
          ? known.kind
          : update.kind ?? known?.kind ?? ToolKind.other,
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
      _logStaleEvent('operation_result', expectedGeneration);
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
  _PendingAcpRequest(this.method) {
    // Ответ может прийти, пока кадр запроса ещё отправляется: синхронный
    // транспорт доставляет его до того, как `_sendRequest` начнёт ждать
    // [future]. Без слушателя ошибка ответа стала бы необработанной; `ignore`
    // только снимает это, а ожидающий позже всё равно получает ошибку.
    _completer.future.ignore();
  }

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

/// `_meta.codelab.critical: true` запроса одобрения: так Dart-агент помечает
/// опасные команды (`AcpPermissionGate`). Только булево `true` — признак;
/// чужие значения игнорируются (forward compatibility `_meta`).
bool _isCritical(Map<String, Object?>? meta) {
  final codelab = meta?['codelab'];
  return codelab is Map && codelab['critical'] == true;
}

/// Классифицирует ошибку `session/prompt` для `PromptTurn.failure`
/// (spec `acp-protocol-client` «Типизированный сбой prompt turn»).
PromptFailure _promptFailureOf(Object error) => switch (error) {
  AcpConnectionLostException() => const PromptFailure.connectionLost(),
  AcpClientApplicationException(cause: final JsonRpcError cause) =>
    PromptFailure.fromJsonRpcError(cause),
  AcpClientApplicationException(:final message) => PromptFailure.unknown(
    message: message,
  ),
  _ => PromptFailure.unknown(message: '$error'),
};

/// Обновление сессии в буфере (реплей `session/load`, ранние обновления) вместе
/// с признаком «вид вызова был незнаком кодеку» (D9 change
/// `tolerate-unknown-tool-kind`): признак считается один раз по сырым params
/// при приёме и не теряется, пока обновление ждёт применения.
typedef _BufferedUpdate = ({SessionUpdate update, bool toolKindUnrecognized});

/// Причина массового завершения terminal-процессов (D15).
///
/// Почему enum, а не строка: закрытый набор значений, который попадает в
/// журнал как поле `reason` события `terminal_processes_killed`.
enum _TerminalKillReason {
  /// Разрыв или замена соединения.
  connectionClosed('connection_closed'),

  /// Закрытие ядра клиента ([AcpClientApplication.dispose]).
  dispose('dispose');

  const _TerminalKillReason(this.logName);

  /// Значение поля `reason` в журнале.
  final String logName;
}
