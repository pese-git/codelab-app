import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import '../backend/agent_backend.dart';
import '../connection/connection_profile.dart';
import '../connection/connection_view.dart';
import '../connection/transport_resolver.dart';
import '../diagnostics/diagnostics.dart';
import '../queue/prompt_queue.dart';
import '../restore/workspace_restorer.dart';
import '../restore/workspace_snapshot.dart';
import '../session/session_views.dart';
import '../transcript/transcript_item.dart';
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
  /// [snapshots] включает восстановление после перезапуска хоста
  /// ([restoreProject], design D6 change `add-session-list-and-reload`).
  factory ClientWorkspace({
    required AgentBackend backend,
    required List<TransportResolver> resolvers,
    WorkspaceSnapshotStore? snapshots,
  }) = DefaultClientWorkspace;

  WorkspaceState get current;

  /// Изменения [current]; доставляются синхронно, чтобы хост видел переход
  /// соединения сразу после события транспорта.
  Stream<WorkspaceState> get state;

  /// Подключается к агенту [profile]; [projectDirectory] — папка проекта,
  /// `cwd` новых сессий и, если профиль просит, процесса агента. Агенту со
  /// `sessionCapabilities.list` после `initialize` отправляется первый
  /// `session/list` проекта — `Future` завершается после него; сбой списка
  /// — диагностика, а не ошибка подключения (design D3 change
  /// `add-session-list-and-reload`).
  Future<void> connect(
    ConnectionProfile profile, {
    required String projectDirectory,
  });

  /// Одна попытка переподключения, без повторов (design D4).
  ///
  /// После неё открытые сессии загружаются заново через `session/load`,
  /// начиная с активной; агент без `loadSession` или ошибка загрузки —
  /// сессия [SessionStatusView.detached] с уведомлением в транскрипте. Пока
  /// идёт переподключение, сессии не отправляют промпты и не сливают
  /// очередь. Затем список сессий запрашивается заново, как после [connect]
  /// (design D5 change `add-session-list-and-reload`).
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

  /// Открывает сессию агента [id] через `session/load`: транскрипт строится
  /// из реплея с нуля, строка списка из [SessionStatusView.notLoaded]
  /// становится открытой. Сессию не активирует — это решает хост.
  ///
  /// Повторный вызов для той же сессии, пока загрузка в полёте, возвращает
  /// тот же `Future`. Без соединения или без `loadSession` у агента —
  /// [ClientWorkspaceException] без запроса к агенту; ошибка агента —
  /// диагностика и исключение вызывающему, строка остаётся `notLoaded`
  /// (design D4 change `add-session-list-and-reload`).
  Future<SessionHandle> loadSession(SessionId id, {required String cwd});

  /// Запрашивает следующую страницу `session/list`, если
  /// `WorkspaceState.hasMoreSessions`; повторный вызов, пока запрос в
  /// полёте, — no-op. Ошибка — диагностика, список остаётся прежним
  /// (design D3).
  Future<void> loadMoreSessions();

  /// Делает сессию [id] активной; неизвестный id игнорируется.
  void activate(SessionId id);

  /// Шаг 1 восстановления: читает снимок прошлого запуска и возвращает его
  /// проект — хост выбирает его до подключения. Вызывается один раз при
  /// старте хоста; до вызова снимок не пишется. Без хранилища снимка или
  /// без снимка — `null`; битый снимок — диагностика, снимок удаляется.
  ///
  /// Остальное восстановление идёт само при первом успешном [connect] в
  /// запуске: сессии снимка — в список, активная — через `session/load`;
  /// агент без `loadSession` или ошибка загрузки — новая сессия с
  /// уведомлением `NoticeKind.reconnected` (design D6).
  Future<String?> restoreProject();

  /// Выбирает папку проекта: `WorkspaceState.projectDirectory` и снимок.
  /// Следующие [connect] и [newSession] хост по-прежнему вызывает с папкой.
  void selectProject(String path);

  /// Дожидается записи снимка, начатой до вызова; без хранилища — сразу.
  Future<void> flushSnapshot();

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

  /// Повторяет последний сорвавшийся ход: его `prompt` уходит новым
  /// `session/prompt`, прежние ходы не меняются (design D4 change
  /// `add-connection-and-error-states`). Исход публикуется в
  /// `ClientWorkspace.promptOutcomes`, как у [send]. При ложном
  /// `SessionView.canRetry` — [ClientWorkspaceException] без запроса.
  Future<PromptOutcome> retry();

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
    WorkspaceSnapshotStore? snapshots,
  }) : _backend = backend,
       _resolvers = List.unmodifiable(resolvers) {
    if (snapshots != null) {
      _restorer = WorkspaceRestorer(snapshots, _RestoreHostAdapter(this));
    }
    _connectionSubscription = backend.connectionStates.listen(
      _handleConnectionState,
    );
    _sessionSubscription = backend.sessionChanges.listen(_handleSession);
  }

  final AgentBackend _backend;
  final List<TransportResolver> _resolvers;

  /// Восстановление и запись снимка; `null` — хранилища снимка нет.
  WorkspaceRestorer? _restorer;
  var _disposed = false;
  final _states = StreamController<WorkspaceState>.broadcast(sync: true);
  final _outcomes = StreamController<PromptOutcome>.broadcast(sync: true);
  final _diagnostics = StreamController<WorkspaceDiagnostic>.broadcast(
    sync: true,
  );

  /// Счётчик id элементов очереди: общий для всех сессий, чтобы id не
  /// повторялись в пределах рабочего пространства.
  var _nextQueuedPromptId = 0;
  final _handles = <SessionId, _SessionHandle>{};

  /// Порядок открытых сессий: от новой к старой.
  final _order = <SessionId>[];

  /// Ещё не открытые сессии агента из `session/list` в его порядке.
  final _listed = <SessionId, SessionInfo>{};

  /// `nextCursor` последней страницы; непрозрачен и наружу не отдаётся
  /// (`04-Session List.md`, «Pagination»).
  String? _nextCursor;
  Future<void>? _listing;

  /// Возможности агента из ответа `initialize` текущего соединения.
  AgentCapabilities _capabilities = const AgentCapabilities();

  final _loading = <SessionId, Future<SessionHandle>>{};

  /// Сессии, загружаемые через `session/load`: их следующий снимок из ядра —
  /// реплей, и проекция транскрипта строится заново (design D4).
  final _reloading = <SessionId>{};

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
      _capabilities = _capabilitiesOf(connectionState);
      _publishConnection(_viewFor(connectionState));
    } on Object catch (error) {
      _publishFailure(error);
      rethrow;
    } finally {
      _transition = _Transition.none;
    }
    await _listFirstPage();
    await _restorer?.restoreAfterConnect();
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
    // Ход, оборванный заменой транспорта, не должен слить очередь в новое
    // соединение раньше, чем сессия загружена в нём.
    for (final handle in _handles.values) {
      handle.suspend();
    }
    try {
      final connectionState = await _backend.reconnect(
        ReconnectCommand(
          transportFactory: () =>
              resolver.open(target, projectDirectory: directory),
        ),
      );
      _capabilities = _capabilitiesOf(connectionState);
      _publishConnection(_viewFor(connectionState));
    } on Object catch (error) {
      for (final handle in _handles.values) {
        handle.resume();
      }
      _publishFailure(error);
      rethrow;
    } finally {
      _transition = _Transition.none;
    }
    await _reattachSessions();
    await _listFirstPage();
  }

  /// Загружает открытые сессии в новом соединении, активную первой: её
  /// транскрипт пользователь видит сразу, а фоновые его не задерживают.
  Future<void> _reattachSessions() async {
    final active = _current.activeSessionId;
    final ids = [
      if (active != null && _handles.containsKey(active)) active,
      for (final id in _order)
        if (id != active) id,
    ];
    for (final id in ids) {
      final handle = _handles[id]!;
      if (!_capabilities.loadSession) {
        handle.detach('The agent cannot restore sessions after reconnecting.');
        continue;
      }
      try {
        await _load(id, handle.cwd);
        handle.resume();
      } on Object {
        handle.detach(
          'Session ${id.value} could not be restored after reconnecting.',
        );
      }
    }
    _publish(_current.copyWith(sessions: _summaries()));
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
  Future<SessionHandle> loadSession(SessionId id, {required String cwd}) {
    final inFlight = _loading[id];
    if (inFlight != null) {
      return inFlight;
    }
    if (_current.connection is! Connected) {
      return Future.error(
        const ClientWorkspaceException(
          'Connect an agent before loading a session.',
        ),
      );
    }
    if (!_capabilities.loadSession) {
      return Future.error(
        const ClientWorkspaceException('The ACP agent cannot load sessions.'),
      );
    }
    final loading = _load(id, cwd);
    _loading[id] = loading;
    return loading.whenComplete(() => _loading.remove(id));
  }

  Future<SessionHandle> _load(SessionId id, String cwd) async {
    _reloading.add(id);
    try {
      final session = await _backend.loadSession(
        LoadSessionCommand(sessionId: id, cwd: cwd),
      );
      // Строка `session/list` остаётся: из неё заголовок и время изменения,
      // а дубля нет — открытая сессия в [_summaries] вытесняет её.
      final handle = _track(session);
      _publish(_current.copyWith(sessions: _summaries()));
      return handle;
    } on Object catch (error) {
      _report(
        WorkspaceDiagnostic(
          severity: DiagnosticSeverity.error,
          source: 'session',
          message:
              'Failed to load ACP session ${id.value}: '
              '${describeFailure(error)}',
        ),
      );
      rethrow;
    } finally {
      _reloading.remove(id);
    }
  }

  @override
  Future<void> loadMoreSessions() async {
    final cursor = _nextCursor;
    if (cursor == null || _listing != null) {
      return;
    }
    await _list(cursor: cursor);
  }

  /// Первая страница списка после подключения: прежний список и курсор
  /// принадлежали старому соединению или проекту (design D3).
  Future<void> _listFirstPage() async {
    _listed.clear();
    _nextCursor = null;
    if (_capabilities.sessionCapabilities.list == null) {
      _publish(
        _current.copyWith(sessions: _summaries(), hasMoreSessions: false),
      );
      return;
    }
    await _list();
  }

  Future<void> _list({String? cursor}) {
    final listing = _fetchPage(cursor);
    _listing = listing;
    return listing.whenComplete(() => _listing = null);
  }

  Future<void> _fetchPage(String? cursor) async {
    try {
      final page = await _backend.listSessions(
        cwd: _current.projectDirectory,
        cursor: cursor,
      );
      for (final info in page.sessions) {
        _listed.putIfAbsent(info.sessionId, () => info);
      }
      _nextCursor = page.nextCursor;
    } on Object catch (error) {
      _report(
        WorkspaceDiagnostic(
          severity: DiagnosticSeverity.error,
          source: 'session',
          message: 'Failed to list ACP sessions: ${describeFailure(error)}',
        ),
      );
    }
    _publish(
      _current.copyWith(
        sessions: _summaries(),
        hasMoreSessions: _nextCursor != null,
      ),
    );
  }

  @override
  void activate(SessionId id) {
    if (!_handles.containsKey(id) || _current.activeSessionId == id) {
      return;
    }
    _publish(_current.copyWith(activeSessionId: id));
  }

  @override
  Future<String?> restoreProject() async => await _restorer?.readProject();

  @override
  void selectProject(String path) =>
      _publish(_current.copyWith(projectDirectory: path));

  @override
  Future<void> flushSnapshot() => _restorer?.flush() ?? Future<void>.value();

  /// Добавляет сессии снимка строками `notLoaded`, если их нет в списке.
  void _rememberSessions(List<SessionRef> sessions) {
    for (final session in sessions) {
      if (!_handles.containsKey(session.id)) {
        _listed.putIfAbsent(
          session.id,
          () => SessionInfo(sessionId: session.id, cwd: session.cwd),
        );
      }
    }
    _publish(_current.copyWith(sessions: _summaries()));
  }

  Future<SessionHandle> _newSessionWithNotice(String cwd, String text) async {
    final handle = await newSession(cwd: cwd);
    _handles[handle.id]!.notify(
      NoticeItem(
        id: '${handle.id.value}/reconnected',
        kind: NoticeKind.reconnected,
        text: text,
      ),
    );
    return handle;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    // Последняя запись снимка не теряется при закрытии хоста (design D6).
    await _restorer?.flush();
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
    // Сбой явного connect/reconnect сообщает вызывающий; здесь — только
    // неожиданная потеря установленного соединения. Она публикуется как
    // `ConnectionLost`, а не `ConnectionFailed` (design D1 change
    // `add-connection-and-error-states`).
    if (view is ConnectionFailed &&
        wasConnected &&
        _transition == _Transition.none) {
      _publishConnection(
        ConnectionView.lost(reason: view.reason, message: view.message),
      );
      _report(
        WorkspaceDiagnostic(
          severity: DiagnosticSeverity.error,
          source: 'transport',
          message: 'Connection to ACP agent lost: ${view.message}',
        ),
      );
      return;
    }
    _publishConnection(view);
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
    final previous = _handles[session.id];
    final previousStatus = previous?.current.status;
    final previousTitle = previous?.title;
    final handle = _track(session);
    if (previousStatus != handle.current.status ||
        previousTitle != handle.title) {
      _publish(_current.copyWith(sessions: _summaries()));
    }
  }

  /// Регистрирует сессию, если она новая, и возвращает её handle.
  _SessionHandle _track(AcpSession session) {
    final existing = _handles[session.id];
    final reloaded = _reloading.remove(session.id);
    if (existing != null) {
      if (reloaded) {
        existing.reload(session);
      } else {
        existing.update(session);
      }
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

  /// Строки списка: открытые сессии, затем неоткрытые из `session/list`;
  /// сессия, которая есть и там и там, показывается один раз — открытой.
  List<SessionSummaryView> _summaries() => [
    for (final id in _order)
      SessionSummaryView(
        id: id,
        cwd: _handles[id]!.cwd,
        status: _handles[id]!.current.status,
        title: _handles[id]!.title ?? _listed[id]?.title,
        updatedAt: _parseTime(_listed[id]?.updatedAt),
      ),
    for (final info in _listed.values)
      if (!_handles.containsKey(info.sessionId))
        SessionSummaryView(
          id: info.sessionId,
          cwd: info.cwd,
          status: SessionStatusView.notLoaded,
          title: info.title,
          updatedAt: _parseTime(info.updatedAt),
        ),
  ];

  static DateTime? _parseTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  static AgentCapabilities _capabilitiesOf(ClientConnectionState state) =>
      switch (state) {
        ClientConnectionReady(:final capabilities) => capabilities,
        _ => const AgentCapabilities(),
      };

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
    _restorer?.observe(next);
  }
}

/// [RestoreHost] поверх закрытых операций рабочего пространства.
final class _RestoreHostAdapter implements RestoreHost {
  _RestoreHostAdapter(this._workspace);

  final DefaultClientWorkspace _workspace;

  @override
  WorkspaceState get current => _workspace.current;

  @override
  AgentCapabilities get capabilities => _workspace._capabilities;

  @override
  void rememberSessions(List<SessionRef> sessions) =>
      _workspace._rememberSessions(sessions);

  @override
  Future<SessionHandle> loadSession(SessionId id, {required String cwd}) =>
      _workspace.loadSession(id, cwd: cwd);

  @override
  void activate(SessionId id) => _workspace.activate(id);

  @override
  Future<SessionHandle> newSessionWithNotice(String cwd, String notice) =>
      _workspace._newSessionWithNotice(cwd, notice);

  @override
  void report(WorkspaceDiagnostic diagnostic) => _workspace._report(diagnostic);
}

enum _Transition { none, connecting, reconnecting }

/// Связь открытой сессии с соединением агента.
enum _Link {
  /// Сессия работает в текущем соединении.
  attached,

  /// Идёт переподключение: сессия ждёт `session/load` в новом соединении.
  reattaching,

  /// Новое соединение сессию не знает.
  detached,
}

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

  /// Заголовок сессии в ядре клиента (`session_info_update`).
  String? get title => _session.title;

  @override
  Stream<SessionView> get view => _views.stream;

  @override
  PromptQueue get queue => this;

  @override
  List<QueuedPrompt> get items => _current.queue;

  /// Связь сессии с текущим соединением агента (design D5 change
  /// `add-session-list-and-reload`).
  _Link _link = _Link.attached;

  /// Уведомление о потере связи в конце транскрипта; только у
  /// [_Link.detached].
  NoticeItem? _notice;

  /// Занята ли сессия: идёт ход (в том числе с ожидающими одобрениями) или
  /// отмена ждёт ответа агента (design D4).
  bool get _isBusy => switch (_current.status) {
    SessionStatusView.running || SessionStatusView.cancelling => true,
    SessionStatusView.idle ||
    SessionStatusView.failed ||
    SessionStatusView.notLoaded ||
    SessionStatusView.detached => false,
  };

  /// Переподключение началось: промпты ставятся в очередь, она не сливается.
  void suspend() {
    if (_link == _Link.attached) {
      _link = _Link.reattaching;
    }
  }

  /// Сессия снова связана с агентом: очередь сливается, если сессия
  /// свободна.
  void resume() {
    _link = _Link.attached;
    _notice = null;
    unawaited(_drainIfFree());
  }

  /// Новое соединение не знает сессию: статус `detached` и уведомление
  /// [text] в конце транскрипта.
  void detach(String text) {
    _link = _Link.detached;
    notify(
      NoticeItem(
        id: '${id.value}/detached',
        kind: NoticeKind.detached,
        text: text,
      ),
    );
  }

  /// Добавляет [notice] в конец транскрипта, после элементов ходов.
  void notify(NoticeItem notice) {
    _notice = notice;
    _publish(
      _sessionFields(
        _current.copyWith(revision: _current.revision + 1),
        _session,
      ),
    );
  }

  @override
  Future<PromptOutcome> send(String text) async {
    if (_link == _Link.detached) {
      final error = ClientWorkspaceException(
        'Session ${id.value} is detached from the agent.',
      );
      final outcome = PromptFailed(id, error);
      _error('prompt', 'Failed to send prompt: ${describeFailure(error)}');
      _onOutcome(outcome);
      return outcome;
    }
    if (_isBusy || _link == _Link.reattaching) {
      final item = QueuedPrompt(id: _nextQueuedPromptId(), text: text);
      _setQueue([..._current.queue, item]);
      return PromptQueued(id, item);
    }
    return _dispatch([ContentBlock.text(text: text)]);
  }

  @override
  Future<PromptOutcome> retry() async {
    if (!_current.canRetry || _link != _Link.attached) {
      throw ClientWorkspaceException(
        'Session ${id.value} has no failed turn to retry.',
      );
    }
    return _dispatch(_session.turns.last.prompt);
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
    if (_isBusy || _link != _Link.attached) {
      return null;
    }
    final item = remove(itemId);
    if (item == null) {
      return null;
    }
    return _dispatch([ContentBlock.text(text: item.text)]);
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
  Future<PromptOutcome> _dispatch(List<ContentBlock> prompt) async {
    PromptOutcome outcome;
    try {
      final turn = await _backend.sendPrompt(
        SendPromptCommand(sessionId: id, prompt: prompt),
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
    if (_isBusy || _link != _Link.attached || _current.queue.isEmpty) {
      return;
    }
    final next = _current.queue.first;
    _setQueue(_current.queue.skip(1).toList());
    await _dispatch([ContentBlock.text(text: next.text)]);
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

  /// Снимок после `session/load`: проекция транскрипта строится заново,
  /// очередь и флаги представления сохраняются (design D4).
  void reload(AcpSession session) {
    _notice = null;
    _projector.reset();
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
  SessionView _sessionFields(SessionView view, AcpSession session) {
    final status = _link == _Link.detached
        ? SessionStatusView.detached
        : SessionStatusView.of(session.status);
    return view.copyWith(
      status: status,
      canRetry: _canRetry(session, status),
      transcript: switch (_notice) {
        null => _projector.items,
        final notice => List.unmodifiable([..._projector.items, notice]),
      },
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
  }

  /// Правила повтора — spec `acp-client-kit` «Повтор сорвавшегося хода».
  bool _canRetry(AcpSession session, SessionStatusView status) {
    if (_link != _Link.attached ||
        status == SessionStatusView.running ||
        status == SessionStatusView.cancelling ||
        session.turns.isEmpty) {
      return false;
    }
    final last = session.turns.last;
    if (last.status != PromptTurnStatus.failed) {
      return false;
    }
    return switch (last.failure) {
      ConnectionLostPromptFailure() => false,
      AgentPromptFailure(retryable: false) => false,
      _ => true,
    };
  }

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
