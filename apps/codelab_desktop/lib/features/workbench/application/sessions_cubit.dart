import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, SessionStatusView, WorkspaceState, describeFailure;
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_ui/codelab_ui.dart';

import 'active_session_cubit.dart';
import 'connection_cubit.dart';
import 'project_paths.dart';
import 'settings_cubit.dart';
import 'shell_part.dart';
import 'ui_mappers.dart';

/// Сессия в корне диска, ожидающая подтверждения открытия (D24): её id и
/// нормализованный `cwd` для текста диалога.
typedef PendingRootSession = ({String sessionId, String cwd});

/// Список сессий и выбранная сессия.
final class SessionsState {
  const SessionsState({
    this.sessions = const [],
    this.activeSessionId,
    this.currentSessionLabel = 'No active session',
    this.currentSessionDetail = 'Create a session after connecting.',
    this.hasMoreSessions = false,
    this.pendingRootSession,
  });

  /// Сессия `notLoaded`, чей `cwd` — корень диска, ждёт подтверждения
  /// пользователя; `null` — подтверждения нет (D24). Решение «ждать» принимает
  /// `SessionsCubit`, виджет только показывает диалог и возвращает ответ.
  final PendingRootSession? pendingRootSession;

  /// Строки сайдбара: открытые сессии, последняя изменившаяся первой, затем
  /// неоткрытые сессии агента (`notLoaded`) в порядке агента.
  final List<CodeLabSessionListItem> sessions;

  /// У агента есть следующая страница сессий.
  final bool hasMoreSessions;
  final String? activeSessionId;
  final String currentSessionLabel;
  final String currentSessionDetail;
}

/// Список сессий в сайдбаре и выбор показываемой сессии.
///
/// Почему: создание и выбор сессии — `ClientWorkspace.newSession` и
/// `activate` kit; в app остаётся отображение в `CodeLabSessionListItem` и
/// решение, какую сессию показывать (таблица переноса `09-10`, строка
/// «Сессии»; design D10 change `extract-acp-client-kit`).
///
/// Для чего: единственный подписчик `sessionChanges` среди частей.
/// Строка сайдбара обновляется для любой сессии — ход фоновой сессии виден
/// без переключения на неё; лента и остальное показываемой сессии
/// пересчитываются только для неё (add-multi-session-concurrency/design.md,
/// Decisions).
///
/// Строки открытых сессий строятся из снимков `AcpSession`, как раньше:
/// статус «ждёт одобрения» есть только там, а `SessionStatusView` kit
/// объединяет его с ходом. Из `WorkspaceState` берутся неоткрытые сессии
/// агента, признак `detached` и наличие следующей страницы (design D7 change
/// `add-session-list-and-reload`). Выбор неоткрытой сессии сначала загружает
/// её через `ClientWorkspace.loadSession`.
///
/// Как использовать: создаётся после [ActiveSessionCubit],
/// [ConnectionCubit] и [SettingsCubit] (`CodeLabShellParts`) и после
/// `ClientWorkspace`: рабочее пространство подписано на `sessionChanges`
/// раньше, поэтому `SessionView` kit к обработчику уже обновлён (design D6).
/// Изменение списка и показываемой сессии — один пакет [ShellChanges].
final class SessionsCubit extends ShellPartCubit<SessionsState> {
  SessionsCubit({
    required super.changes,
    required AcpClientApplication application,
    required ClientWorkspace workspace,
    required ShellDiagnostics diagnostics,
    required ConnectionCubit connection,
    required SettingsCubit settings,
    required ActiveSessionCubit activeSession,
    Logger? eventLogger,
  }) : _application = application,
       _workspace = workspace,
       _diagnostics = diagnostics,
       _connection = connection,
       _settings = settings,
       _activeSession = activeSession,
       _eventLogger = eventLogger,
       super(const SessionsState()) {
    _sessionSubscription = _application.sessionChanges.listen(
      _handleSessionChange,
    );
    _workspaceSubscription = _workspace.state.listen(_handleWorkspaceState);
  }

  final AcpClientApplication _application;
  final ClientWorkspace _workspace;
  final ShellDiagnostics _diagnostics;
  final ConnectionCubit _connection;
  final SettingsCubit _settings;
  final ActiveSessionCubit _activeSession;
  final Logger? _eventLogger;

  /// Источник истины для [SessionsState.pendingRootSession]: каждый `emit`
  /// списка переносит его в новое состояние.
  PendingRootSession? _pendingRoot;
  late final StreamSubscription<AcpSession> _sessionSubscription;
  late final StreamSubscription<WorkspaceState> _workspaceSubscription;

  /// Строки открытых сессий, последняя изменившаяся первой.
  var _open = const <CodeLabSessionListItem>[];

  /// Неоткрытые сессии агента и их `cwd` для `session/load`.
  var _available = const <CodeLabSessionListItem>[];
  var _availableCwd = const <String, String>{};

  /// Открытые сессии, которые новое соединение не знает.
  var _detached = const <String>{};
  var _hasMore = false;

  /// Отпечаток данных из `WorkspaceState`, которые показывает сайдбар:
  /// изменения статусов открытых сессий сюда не входят, и на них второго
  /// состояния после `sessionChanges` не будет.
  String _workspaceRows = '';

  /// Создаёт сессию в папке проекта и сразу показывает её.
  ///
  /// Проект проверяется раньше соединения: без проекта нет папки для `cwd`,
  /// поэтому вместо сессии открывается выбор папки, как «Open folder…», и
  /// агенту ничего не шлётся (agent-workbench-ui «New session без проекта
  /// открывает выбор папки», D5). Выбранная папка становится проектом, а
  /// сессию создаёт повторное «New session». Папка читается один раз и
  /// уходит в `session/new` (D3).
  Future<void> createSession() async {
    // Та же функция ожидания, что у Connect (D3): сессия в первые
    // миллисекунды после старта не должна открывать выбор папки, пока
    // проект восстанавливается.
    final project = _settings.projectRestoreFinished
        ? _settings.projectDirectory
        : await _settings.awaitProject();
    if (isClosed) return;
    if (project == null) {
      _diagnostics.record(
        'Open a project to start a session: choose a folder.',
        source: 'session',
      );
      await _settings.browseForProject();
      return;
    }
    if (_connection.state.connectionStatus !=
        CodeLabConnectionStatus.connected) {
      _diagnostics.record(
        'Connect an ACP agent before creating a session.',
        severity: DiagnosticSeverity.warning,
        source: 'session',
      );
      return;
    }

    _diagnostics.record('Creating ACP session.', source: 'session');

    final AcpSession? session;
    try {
      final handle = await _workspace.newSession(cwd: project);
      if (isClosed) return;
      session = _application.sessionById(handle.id);
    } on Object catch (error) {
      if (isClosed) return;
      _diagnostics.record(
        'Failed to create ACP session: ${describeFailure(error)}',
        severity: DiagnosticSeverity.error,
        source: 'session',
      );
      return;
    }
    if (session == null) {
      return;
    }

    batch(() {
      _showFirst(session!, activate: true);
      _activeSession.showCreated(session);
    });
    _diagnostics.record(
      'Created ACP session ${session.id.value}.',
      source: 'session',
    );
  }

  /// Переключает показываемую сессию и сразу перечитывает всё её состояние
  /// из живого снимка — иначе до её следующего `session/update` была бы
  /// видна лента прежней сессии.
  void selectSession(String sessionId) => _select(sessionId, byUser: true);

  /// [byUser] — действие пользователя: только оно снимает открытый вопрос D24
  /// (D17). Завершение ранее начатой загрузки ([_loadAndSelect]) его не
  /// снимает: иначе поздний ответ агента отменил бы вопрос ложным `cancel`.
  void _select(String sessionId, {required bool byUser}) {
    final cwd = _availableCwd[sessionId];
    if (cwd != null && _application.sessionById(SessionId(sessionId)) == null) {
      if (isFilesystemRoot(cwd)) {
        _askAboutRootSession(sessionId, cwd);
        return;
      }
      if (byUser) _dropRootQuestion('cancel');
      unawaited(_loadAndSelect(sessionId, cwd));
      return;
    }
    if (byUser) _dropRootQuestion('cancel');
    _workspace.activate(SessionId(sessionId));
    final session = _application.sessionById(SessionId(sessionId));
    batch(() {
      if (session == null) {
        final selected = state.sessions
            .where((item) => item.id == sessionId)
            .firstOrNull;
        emit(
          SessionsState(
            sessions: state.sessions,
            activeSessionId: sessionId,
            currentSessionLabel: selected?.title ?? untitledSessionTitle,
            currentSessionDetail: selected?.subtitle ?? sessionId,
            hasMoreSessions: _hasMore,
            pendingRootSession: _pendingRoot,
          ),
        );
        _activeSession.showMissing(sessionId);
        return;
      }
      final item = sessionListItemOf(session);
      emit(_activated(item, session, sessions: _rows(), hasMore: _hasMore));
      _activeSession.show(session);
    });
  }

  /// Подтверждение D24: открыть сессию в корне диска.
  ///
  /// Почему здесь: решение «эта сессия опасна» принимает `SessionsCubit`, а
  /// не виджет (§10). Виджет показывает диалог по
  /// [SessionsState.pendingRootSession] и только возвращает ответ. Загрузка
  /// идёт с исходным `cwd` строки, текст диалога — с нормализованным.
  void confirmRootSession() {
    final pending = _pendingRoot;
    if (pending == null) {
      return;
    }
    final cwd = _availableCwd[pending.sessionId];
    if (cwd == null) {
      // Строка исчезла между показом и ответом: грузить нечего, а `open`
      // пишется только при фактической загрузке.
      _dropRootQuestion('cancel');
      return;
    }
    _dropRootQuestion('open');
    unawaited(_loadAndSelect(pending.sessionId, cwd));
  }

  /// Отказ D24: фокус и статус строки не меняются, агенту ничего не шлётся.
  void cancelRootSession() => _dropRootQuestion('cancel');

  /// Ставит вопрос «Open anyway?» для [sessionId] (D24). Повторный выбор той
  /// же сессии при открытом вопросе игнорируется, выбор другой корневой
  /// сессии закрывает прежний вопрос как отказ.
  void _askAboutRootSession(String sessionId, String cwd) {
    if (_pendingRoot?.sessionId == sessionId) {
      return;
    }
    _dropRootQuestion('cancel', notify: false);
    _pendingRoot = (sessionId: sessionId, cwd: normalizedPath(cwd));
    emit(_withPendingRoot());
  }

  /// Снимает вопрос D24 с решением [decision] (`open` или `cancel`). Событие
  /// несёт только решение, без пути (AGENTS.md §16).
  void _dropRootQuestion(String decision, {bool notify = true}) {
    if (_pendingRoot == null) {
      return;
    }
    final sessionId = _pendingRoot!.sessionId;
    _pendingRoot = null;
    // Без пути (AGENTS.md §16): id сессии связывает решение с сессией.
    _eventLogger?.info(
      'session.root_open',
      context: {'decision': decision, 'session_id': sessionId},
    );
    if (notify) {
      emit(_withPendingRoot());
    }
  }

  SessionsState _withPendingRoot() => SessionsState(
    sessions: state.sessions,
    activeSessionId: state.activeSessionId,
    currentSessionLabel: state.currentSessionLabel,
    currentSessionDetail: state.currentSessionDetail,
    hasMoreSessions: state.hasMoreSessions,
    pendingRootSession: _pendingRoot,
  );

  /// Следующая страница сессий агента.
  Future<void> loadMoreSessions() => _workspace.loadMoreSessions();

  @override
  Future<void> close() async {
    await _sessionSubscription.cancel();
    await _workspaceSubscription.cancel();
    return super.close();
  }

  /// Загружает сессию агента и показывает её; ошибку загрузки kit уже
  /// записал в журнал, выбранная сессия тогда не меняется.
  Future<void> _loadAndSelect(String sessionId, String cwd) async {
    _diagnostics.record('Loading ACP session $sessionId.', source: 'session');
    try {
      await _workspace.loadSession(SessionId(sessionId), cwd: cwd);
    } on Object {
      return;
    }
    if (isClosed) return;
    _select(sessionId, byUser: false);
  }

  void _handleWorkspaceState(WorkspaceState workspace) {
    final available = [
      for (final summary in workspace.sessions)
        if (summary.status == SessionStatusView.notLoaded) summary,
    ];
    final detached = {
      for (final summary in workspace.sessions)
        if (summary.status == SessionStatusView.detached) summary.id.value,
    };
    final rows = [
      for (final summary in available) '${summary.id.value}:${summary.title}',
      '|',
      ...detached,
      '|${workspace.hasMoreSessions}',
    ].join(',');
    if (rows == _workspaceRows) {
      return;
    }
    _workspaceRows = rows;
    _available = [
      for (final summary in available) sessionListItemOfSummary(summary),
    ];
    _availableCwd = {
      for (final summary in available) summary.id.value: summary.cwd,
    };
    // Строка сессии исчезла (потеря соединения, смена проекта): спрашивать
    // не о чем, вопрос снимается как отказ; `open` пишется только при
    // фактической загрузке (D24).
    if (_pendingRoot case final pending?
        when !_availableCwd.containsKey(pending.sessionId)) {
      _dropRootQuestion('cancel', notify: false);
    }
    final active = state.activeSessionId;
    // Уведомление `detached` меняет `SessionView` показываемой сессии без
    // нового снимка `AcpSession`, поэтому `sessionChanges` его не принесёт.
    final activeDetachChanged =
        active != null &&
        _detached.contains(active) != detached.contains(active);
    _detached = detached;
    _hasMore = workspace.hasMoreSessions;
    batch(() {
      emit(
        SessionsState(
          sessions: _rows(),
          activeSessionId: active,
          currentSessionLabel: state.currentSessionLabel,
          currentSessionDetail: state.currentSessionDetail,
          hasMoreSessions: _hasMore,
          pendingRootSession: _pendingRoot,
        ),
      );
      final session = activeDetachChanged
          ? _application.sessionById(SessionId(active))
          : null;
      if (session != null) {
        _activeSession.show(session);
      }
    });
  }

  /// Открытые строки (с `detached` из kit), затем неоткрытые, без повторов.
  List<CodeLabSessionListItem> _rows() {
    final openIds = {for (final row in _open) row.id};
    return [
      for (final row in _open)
        _detached.contains(row.id)
            ? CodeLabSessionListItem(
                id: row.id,
                title: row.title,
                status: CodeLabSessionStatus.detached,
                subtitle: row.subtitle,
                updatedLabel: row.updatedLabel,
              )
            : row,
      for (final row in _available)
        if (!openIds.contains(row.id)) row,
    ];
  }

  /// Изменение любой сессии: строка сайдбара — всегда; показываемая
  /// сессия — только если изменилась она (или ни одна ещё не показана).
  void _handleSessionChange(AcpSession session) {
    final isActive =
        state.activeSessionId == null ||
        state.activeSessionId == session.id.value;
    batch(() {
      _showFirst(session, activate: isActive);
      if (isActive) {
        _activeSession.show(session);
      }
    });
  }

  /// Поднимает строку [session] в начало списка; с [activate] — ещё и
  /// делает её показываемой.
  void _showFirst(AcpSession session, {required bool activate}) {
    final item = sessionListItemOf(session);
    _open = [item, ..._open.where((other) => other.id != item.id)];
    final sessions = _rows();
    emit(
      activate
          ? _activated(item, session, sessions: sessions, hasMore: _hasMore)
          : SessionsState(
              sessions: sessions,
              activeSessionId: state.activeSessionId,
              currentSessionLabel: state.currentSessionLabel,
              currentSessionDetail: state.currentSessionDetail,
              hasMoreSessions: _hasMore,
              pendingRootSession: _pendingRoot,
            ),
    );
  }

  SessionsState _activated(
    CodeLabSessionListItem item,
    AcpSession session, {
    required List<CodeLabSessionListItem> sessions,
    required bool hasMore,
  }) => SessionsState(
    sessions: sessions,
    activeSessionId: item.id,
    currentSessionLabel: item.title,
    currentSessionDetail: item.subtitle ?? session.id.value,
    hasMoreSessions: hasMore,
    pendingRootSession: _pendingRoot,
  );
}
