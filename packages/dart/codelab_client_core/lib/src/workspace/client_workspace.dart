import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import '../backend/agent_backend.dart';
import '../connection/connection_profile.dart';
import '../connection/connection_view.dart';
import '../connection/transport_resolver.dart';
import '../diagnostics/diagnostics.dart';
import '../queue/prompt_queue.dart';
import '../session/session_views.dart';
import '../transcript/transcript_projector.dart';
import 'client_workspace_exception.dart';
import 'workspace_state.dart';

/// Рабочее пространство клиента ACP: одно соединение с агентом и его сессии.
///
/// Почему: подключение, переподключение и сессии раньше жили в Flutter-Cubit
/// app, и CLI не мог их переиспользовать (`09-10`, этап 5). Kit держит эту
/// логику на чистом Dart, а хосты только отображают [WorkspaceState].
///
/// Для чего: владелец состояния соединения и списка сессий; публикует
/// [state] при каждом изменении и выдаёт [SessionHandle] для работы с
/// сессией.
///
/// Как использовать: composition root создаёт `ClientWorkspace(backend:
/// AcpClientBackend(application), resolvers: [...])`; затем [connect] →
/// [newSession] / [activate]; [dispose] при закрытии хоста. Ошибки
/// транспорта и агента уходят вызывающему исключениями `codelab_client_acp`
/// после публикации `ConnectionFailed`; отказы самого kit —
/// [ClientWorkspaceException].
abstract interface class ClientWorkspace {
  factory ClientWorkspace({
    required AgentBackend backend,
    required List<TransportResolver> resolvers,
  }) = DefaultClientWorkspace;

  WorkspaceState get current;

  /// Изменения [current]; доставляются синхронно, чтобы хост видел переход
  /// соединения сразу после события транспорта.
  Stream<WorkspaceState> get state;

  /// Подключается к агенту [profile]; [projectDirectory] — папка проекта,
  /// `cwd` новых сессий и, если профиль просит, процесса агента.
  Future<void> connect(
    ConnectionProfile profile, {
    required String projectDirectory,
  });

  /// Одна попытка переподключения без `session/load` (design D4).
  ///
  /// [profile] и [projectDirectory] заменяют текущие, если переданы: хост
  /// мог изменить форму подключения после [connect].
  Future<void> reconnect({
    ConnectionProfile? profile,
    String? projectDirectory,
  });

  /// Создаёт сессию в [cwd] (по умолчанию — папка проекта) и делает её
  /// активной.
  Future<SessionHandle> newSession({String? cwd});

  SessionHandle? session(SessionId id);

  /// Делает сессию [id] активной; неизвестный id игнорируется.
  void activate(SessionId id);

  /// Исходы ходов всех сессий — и отправленных хостом, и ушедших из
  /// очереди сами; доставляются синхронно.
  Stream<PromptOutcome> get promptOutcomes;

  /// Диагностика событий, которыми владеет kit: исходы ходов, отмена,
  /// ответы на одобрения, опции, неожиданная потеря соединения. Уже без
  /// секретов; доставляется синхронно, после публикации состояния.
  Stream<WorkspaceDiagnostic> get diagnostics;

  /// Отписывается от бэкенда и закрывает потоки; бэкенд закрывает его
  /// владелец.
  Future<void> dispose();
}

/// Сессия рабочего пространства.
///
/// Почему: хосту нужен объект сессии, а не id и выборка из общего списка.
///
/// Для чего: текущее [SessionView] и его изменения, отправка промптов с
/// очередью, отмена хода, ответы на одобрения и опции конфигурации.
/// [current] обновляется синхронно с изменением сессии в ядре клиента, до
/// остальных подписчиков `sessionChanges`, подписанных позже рабочего
/// пространства (design D6).
///
/// Как использовать: [send] — свободная сессия отправляет `session/prompt`
/// сразу, занятая (`SessionView.status` — `running` или `cancelling`) ставит
/// промпт в [queue]. Future [send] завершается после конца хода и слива
/// очереди сессии, которую этот ход освободил, — как прежний
/// `CodeLabShellCubit.submitPrompt`.
abstract interface class SessionHandle {
  SessionId get id;

  String get cwd;

  SessionView get current;

  Stream<SessionView> get view;

  PromptQueue get queue;

  Future<PromptOutcome> send(String text);

  /// Отправляет `session/cancel`; ход остаётся `cancelling`, пока агент не
  /// ответит на его `session/prompt` (fix-prompt-cancel-tool-calls/design.md,
  /// D2). Ошибки — исключения `codelab_client_acp`.
  Future<PromptTurn> cancel();

  /// Отвечает на одобрение [approval] этой сессии вариантом [option]
  /// (отказ — тоже вариант: в ACP нет отдельного «отклонить»). Одобрение
  /// другой сессии отклоняет ядро клиента (PERM-003,
  /// `docs/architecture/permissions.md`).
  Future<ApprovalRequest> respond(
    ApprovalRequestId approval,
    PermissionOptionId option,
  );

  /// Отправляет `session/set_config_option`; пока запрос в полёте,
  /// `SessionView.configOptionInFlight` — [configId], а повторный вызов —
  /// no-op. Показываемое значение приходит из ответа агента, а не
  /// выставляется заранее. Ошибка — диагностика и исключение вызывающему.
  Future<void> setConfigOption(String configId, String valueId);
}

/// Реализация [ClientWorkspace] по умолчанию.
final class DefaultClientWorkspace implements ClientWorkspace {
  DefaultClientWorkspace({
    required AgentBackend backend,
    required List<TransportResolver> resolvers,
  }) : _backend = backend,
       _resolvers = List.unmodifiable(resolvers) {
    _connectionSubscription = backend.connectionStates.listen(
      _handleConnectionState,
    );
    _sessionSubscription = backend.sessionChanges.listen(_handleSession);
  }

  final AgentBackend _backend;
  final List<TransportResolver> _resolvers;
  final _states = StreamController<WorkspaceState>.broadcast(sync: true);
  final _outcomes = StreamController<PromptOutcome>.broadcast(sync: true);
  final _diagnostics = StreamController<WorkspaceDiagnostic>.broadcast(
    sync: true,
  );

  /// Счётчик id элементов очереди: общий для всех сессий, чтобы id не
  /// повторялись в пределах рабочего пространства.
  var _nextQueuedPromptId = 0;
  final _handles = <SessionId, _SessionHandle>{};

  /// Порядок списка сессий: от новой к старой.
  final _order = <SessionId>[];

  late final StreamSubscription<ClientConnectionState> _connectionSubscription;
  late final StreamSubscription<AcpSession> _sessionSubscription;
  var _current = const WorkspaceState();

  /// Какой переход ведёт явный вызов: промежуточные состояния ядра
  /// (`disconnected`, `connecting`, `initializing`) при переподключении
  /// остаются `Reconnecting`, а не мигают `Connecting`.
  _Transition _transition = _Transition.none;

  @override
  WorkspaceState get current => _current;

  @override
  Stream<WorkspaceState> get state => _states.stream;

  @override
  Stream<PromptOutcome> get promptOutcomes => _outcomes.stream;

  @override
  Stream<WorkspaceDiagnostic> get diagnostics => _diagnostics.stream;

  @override
  Future<void> connect(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    final resolver = _resolverFor(profile);
    if (resolver == null) {
      throw _rejectUnsupported(profile, projectDirectory);
    }

    _publish(
      _current.copyWith(
        connection: const ConnectionView.connecting(),
        profile: profile,
        projectDirectory: projectDirectory,
      ),
    );
    _transition = _Transition.connecting;
    try {
      final transport = await resolver.open(
        profile,
        projectDirectory: projectDirectory,
      );
      final connectionState = await _backend.connect(transport);
      _publishConnection(_viewFor(connectionState));
    } on Object catch (error) {
      _publishFailure(error);
      rethrow;
    } finally {
      _transition = _Transition.none;
    }
  }

  @override
  Future<void> reconnect({
    ConnectionProfile? profile,
    String? projectDirectory,
  }) async {
    final target = profile ?? _current.profile;
    final directory = projectDirectory ?? _current.projectDirectory;
    if (target == null || directory == null) {
      throw const ClientWorkspaceException(
        'Connect an agent before reconnecting.',
      );
    }
    final resolver = _resolverFor(target);
    if (resolver == null) {
      throw _rejectUnsupported(target, directory);
    }

    _publish(
      _current.copyWith(
        connection: const ConnectionView.reconnecting(attempt: 1),
        profile: target,
        projectDirectory: directory,
      ),
    );
    _transition = _Transition.reconnecting;
    try {
      final connectionState = await _backend.reconnect(
        ReconnectCommand(
          transportFactory: () =>
              resolver.open(target, projectDirectory: directory),
        ),
      );
      _publishConnection(_viewFor(connectionState));
    } on Object catch (error) {
      _publishFailure(error);
      rethrow;
    } finally {
      _transition = _Transition.none;
    }
  }

  @override
  Future<SessionHandle> newSession({String? cwd}) async {
    final directory = _current.projectDirectory;
    if (_current.connection is! Connected || directory == null) {
      throw const ClientWorkspaceException(
        'Connect an agent before creating a session.',
      );
    }

    final session = await _backend.createSession(
      CreateSessionCommand(cwd: cwd ?? directory),
    );
    final handle = _track(session);
    _publish(
      _current.copyWith(sessions: _summaries(), activeSessionId: session.id),
    );
    return handle;
  }

  @override
  SessionHandle? session(SessionId id) => _handles[id];

  @override
  void activate(SessionId id) {
    if (!_handles.containsKey(id) || _current.activeSessionId == id) {
      return;
    }
    _publish(_current.copyWith(activeSessionId: id));
  }

  @override
  Future<void> dispose() async {
    await _connectionSubscription.cancel();
    await _sessionSubscription.cancel();
    for (final handle in _handles.values) {
      await handle.close();
    }
    await _states.close();
    await _outcomes.close();
    await _diagnostics.close();
  }

  TransportResolver? _resolverFor(ConnectionProfile profile) {
    for (final resolver in _resolvers) {
      if (resolver.supports(profile)) {
        return resolver;
      }
    }
    return null;
  }

  /// Публикует сбой профиля без резолвера и возвращает исключение для
  /// вызывающего; транспорт не открывается.
  UnsupportedConnectionProfileException _rejectUnsupported(
    ConnectionProfile profile,
    String projectDirectory,
  ) {
    final error = UnsupportedConnectionProfileException(profile);
    _publish(
      _current.copyWith(
        connection: ConnectionView.failed(
          reason: ConnectionFailureReason.startFailed,
          message: error.message,
        ),
        profile: profile,
        projectDirectory: projectDirectory,
      ),
    );
    return error;
  }

  void _handleConnectionState(ClientConnectionState connectionState) {
    final wasConnected = _current.connection is Connected;
    final view = _viewFor(connectionState);
    _publishConnection(view);
    // Сбой явного connect/reconnect сообщает вызывающий; здесь — только
    // неожиданная потеря установленного соединения.
    if (view is ConnectionFailed &&
        wasConnected &&
        _transition == _Transition.none) {
      _report(
        WorkspaceDiagnostic(
          severity: DiagnosticSeverity.error,
          source: 'transport',
          message: 'Connection to ACP agent lost: ${view.message}',
        ),
      );
    }
  }

  /// Публикует диагностику после редакции секретов.
  void _report(WorkspaceDiagnostic diagnostic) {
    if (_diagnostics.isClosed) {
      return;
    }
    _diagnostics.add(
      WorkspaceDiagnostic(
        severity: diagnostic.severity,
        source: diagnostic.source,
        message: _redactor.redactText(diagnostic.message),
      ),
    );
  }

  void _handleSession(AcpSession session) {
    final previous = _handles[session.id]?.current.status;
    final status = _track(session).current.status;
    if (previous != status) {
      _publish(_current.copyWith(sessions: _summaries()));
    }
  }

  /// Регистрирует сессию, если она новая, и возвращает её handle.
  _SessionHandle _track(AcpSession session) {
    final existing = _handles[session.id];
    if (existing != null) {
      existing.update(session);
      return existing;
    }
    final handle = _SessionHandle(
      session,
      backend: _backend,
      nextQueuedPromptId: () => 'queued-${_nextQueuedPromptId++}',
      onOutcome: (outcome) {
        if (!_outcomes.isClosed) {
          _outcomes.add(outcome);
        }
      },
      onDiagnostic: _report,
    );
    _handles[session.id] = handle;
    _order.insert(0, session.id);
    return handle;
  }

  List<SessionSummaryView> _summaries() => [
    for (final id in _order)
      SessionSummaryView(
        id: id,
        cwd: _handles[id]!.cwd,
        status: _handles[id]!.current.status,
      ),
  ];

  ConnectionView _viewFor(ClientConnectionState connectionState) {
    final reconnecting = _transition == _Transition.reconnecting;
    return switch (connectionState) {
      ClientConnectionReady() => const ConnectionView.connected(),
      ClientConnectionFailed(:final reason, :final message) =>
        ConnectionView.failed(reason: reason, message: message),
      ClientConnectionDisconnected() ||
      ClientConnectionConnecting() ||
      ClientConnectionInitializing() when reconnecting => _current.connection,
      ClientConnectionDisconnected()
          when _transition == _Transition.connecting =>
        _current.connection,
      ClientConnectionDisconnected() => const ConnectionView.disconnected(),
      ClientConnectionConnecting() ||
      ClientConnectionInitializing() => const ConnectionView.connecting(),
    };
  }

  /// Ошибка явного подключения: если ядро уже опубликовало сбой, он
  /// остаётся; иначе (резолвер не открыл транспорт) — сбой запуска.
  void _publishFailure(Object error) {
    if (_current.connection is ConnectionFailed) {
      return;
    }
    _publishConnection(
      ConnectionView.failed(
        reason: ConnectionFailureReason.startFailed,
        message: switch (error) {
          AcpClientApplicationException(:final message) ||
          AcpTransportException(:final message) ||
          ClientWorkspaceException(:final message) => message,
          _ => '$error',
        },
      ),
    );
  }

  void _publishConnection(ConnectionView connection) {
    if (connection == _current.connection) {
      return;
    }
    _publish(_current.copyWith(connection: connection));
  }

  void _publish(WorkspaceState next) {
    if (next == _current) {
      return;
    }
    _current = next;
    if (!_states.isClosed) {
      _states.add(next);
    }
  }
}

enum _Transition { none, connecting, reconnecting }

const _redactor = SecretRedactor();

final class _SessionHandle implements SessionHandle, PromptQueue {
  _SessionHandle(
    AcpSession session, {
    required AgentBackend backend,
    required String Function() nextQueuedPromptId,
    required void Function(PromptOutcome outcome) onOutcome,
    required void Function(WorkspaceDiagnostic diagnostic) onDiagnostic,
  }) : id = session.id,
       cwd = session.cwd,
       _session = session,
       _backend = backend,
       _nextQueuedPromptId = nextQueuedPromptId,
       _onOutcome = onOutcome,
       _onDiagnostic = onDiagnostic {
    _projector.apply(session);
    _current = _sessionFields(
      const SessionView(revision: 0, status: SessionStatusView.idle),
      session,
    );
  }

  @override
  final SessionId id;

  @override
  final String cwd;

  final AgentBackend _backend;
  final String Function() _nextQueuedPromptId;
  final void Function(PromptOutcome outcome) _onOutcome;
  final void Function(WorkspaceDiagnostic diagnostic) _onDiagnostic;
  final _views = StreamController<SessionView>.broadcast(sync: true);
  final _projector = TranscriptProjector();
  late SessionView _current;
  AcpSession _session;

  @override
  SessionView get current => _current;

  @override
  Stream<SessionView> get view => _views.stream;

  @override
  PromptQueue get queue => this;

  @override
  List<QueuedPrompt> get items => _current.queue;

  /// Занята ли сессия: идёт ход (в том числе с ожидающими одобрениями) или
  /// отмена ждёт ответа агента (design D4).
  bool get _isBusy => switch (_current.status) {
    SessionStatusView.running || SessionStatusView.cancelling => true,
    SessionStatusView.idle || SessionStatusView.failed => false,
  };

  @override
  Future<PromptOutcome> send(String text) async {
    if (_isBusy) {
      final item = QueuedPrompt(id: _nextQueuedPromptId(), text: text);
      _setQueue([..._current.queue, item]);
      return PromptQueued(id, item);
    }
    return _dispatch(text);
  }

  @override
  Future<PromptTurn> cancel() async {
    try {
      final turn = await _backend.cancelTurn(CancelTurnCommand(sessionId: id));
      _info('prompt', 'Cancelled prompt turn ${turn.id.value}.');
      return turn;
    } on Object catch (error) {
      _error(
        'prompt',
        'Failed to cancel prompt turn: ${describeFailure(error)}',
      );
      rethrow;
    }
  }

  @override
  Future<ApprovalRequest> respond(
    ApprovalRequestId approval,
    PermissionOptionId option,
  ) async {
    try {
      final resolved = await _backend.respondToPermission(
        RespondToPermissionCommand.selected(
          sessionId: id,
          approvalId: approval,
          optionId: option,
        ),
      );
      _info(
        'approval',
        'Resolved approval ${resolved.id.value} (${resolved.status.name}).',
      );
      return resolved;
    } on Object catch (error) {
      _error(
        'approval',
        'Failed to respond to approval request: ${describeFailure(error)}',
      );
      rethrow;
    }
  }

  @override
  Future<void> setConfigOption(String configId, String valueId) async {
    if (_current.configOptionInFlight != null) {
      return;
    }
    _publish(
      _current.copyWith(
        revision: _current.revision + 1,
        configOptionInFlight: configId,
      ),
    );
    try {
      await _backend.setSessionConfigOption(
        SetSessionConfigOptionCommand(
          sessionId: id,
          configId: SessionConfigId(configId),
          value: SessionConfigValueId(valueId),
        ),
      );
      _clearConfigOptionInFlight();
      _info('session', 'Set config option $configId to $valueId.');
    } on Object catch (error) {
      _clearConfigOptionInFlight();
      _error(
        'session',
        'Failed to set config option $configId: ${describeFailure(error)}',
      );
      rethrow;
    }
  }

  void _clearConfigOptionInFlight() => _publish(
    _current.copyWith(
      revision: _current.revision + 1,
      configOptionInFlight: null,
    ),
  );

  void _info(String source, String message) => _onDiagnostic(
    WorkspaceDiagnostic(
      severity: DiagnosticSeverity.info,
      source: source,
      message: message,
    ),
  );

  void _error(String source, String message) => _onDiagnostic(
    WorkspaceDiagnostic(
      severity: DiagnosticSeverity.error,
      source: source,
      message: message,
    ),
  );

  @override
  QueuedPrompt? remove(String itemId) {
    final item = _current.queue.where((q) => q.id == itemId).firstOrNull;
    if (item == null) {
      return null;
    }
    _setQueue([
      for (final queued in _current.queue)
        if (queued.id != itemId) queued,
    ]);
    return item;
  }

  @override
  Future<PromptOutcome?> sendNow(String itemId) async {
    if (_isBusy) {
      return null;
    }
    final item = remove(itemId);
    if (item == null) {
      return null;
    }
    return _dispatch(item.text);
  }

  @override
  void clear() {
    if (_current.queue.isNotEmpty) {
      _setQueue(const []);
    }
  }

  /// Один `session/prompt`: исход публикуется в
  /// `ClientWorkspace.promptOutcomes`, затем, если сессия освободилась,
  /// уходит первый элемент очереди — и так, пока очередь не опустеет.
  ///
  /// Слив проверяет условие заново после каждого хода, а не реагирует на
  /// событие статуса: отправка из обработчика синхронного `sessionChanges`
  /// вызвала бы вложенную публикацию в тот же поток.
  Future<PromptOutcome> _dispatch(String text) async {
    PromptOutcome outcome;
    try {
      final turn = await _backend.sendPrompt(
        SendPromptCommand(
          sessionId: id,
          prompt: [ContentBlock.text(text: text)],
        ),
      );
      outcome = PromptCompleted(id, turn);
      _info(
        'prompt',
        'Prompt completed with stopReason ${turn.stopReason?.name ?? 'unknown'}.',
      );
    } on Object catch (error) {
      outcome = PromptFailed(id, error);
      _error('prompt', 'Failed to send prompt: ${describeFailure(error)}');
    }
    _onOutcome(outcome);
    await _drainIfFree();
    return outcome;
  }

  Future<void> _drainIfFree() async {
    if (_isBusy || _current.queue.isEmpty) {
      return;
    }
    final next = _current.queue.first;
    _setQueue(_current.queue.skip(1).toList());
    await _dispatch(next.text);
  }

  /// Каждое изменение сессии в ядре — новое представление с `revision + 1`;
  /// повтор того же снимка (`identical`) — no-op.
  void update(AcpSession session) {
    if (identical(session, _session)) {
      return;
    }
    _session = session;
    _projector.apply(session);
    _publish(
      _sessionFields(
        _current.copyWith(revision: _current.revision + 1),
        session,
      ),
    );
  }

  /// Поля представления, которые выводятся из снимка сессии ядра.
  SessionView _sessionFields(SessionView view, AcpSession session) =>
      view.copyWith(
        status: SessionStatusView.of(session.status),
        transcript: _projector.items,
        configOptions: [
          for (final option in session.configOptions ?? const [])
            ConfigOptionView.of(option),
        ],
        agentCommands: [
          for (final command in session.availableCommands)
            AgentCommandView.of(command),
        ],
        pendingApprovals: pendingApprovalViews(session),
      );

  void _setQueue(List<QueuedPrompt> queue) => _publish(
    _current.copyWith(
      revision: _current.revision + 1,
      queue: List.unmodifiable(queue),
    ),
  );

  void _publish(SessionView next) {
    _current = next;
    if (!_views.isClosed) {
      _views.add(next);
    }
  }

  Future<void> close() => _views.close();
}
