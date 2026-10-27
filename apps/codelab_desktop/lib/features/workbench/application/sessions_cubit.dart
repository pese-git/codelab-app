import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, SessionStatusView, WorkspaceState, describeFailure;
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_ui/codelab_ui.dart';

import 'active_session_cubit.dart';
import 'connection_cubit.dart';
import 'settings_cubit.dart';
import 'shell_part.dart';
import 'ui_mappers.dart';

/// Список сессий и выбранная сессия.
final class SessionsState {
  const SessionsState({
    this.sessions = const [],
    this.activeSessionId,
    this.currentSessionLabel = 'No active session',
    this.currentSessionDetail = 'Create a session after connecting.',
    this.hasMoreSessions = false,
  });

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
  }) : _application = application,
       _workspace = workspace,
       _diagnostics = diagnostics,
       _connection = connection,
       _settings = settings,
       _activeSession = activeSession,
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
  Future<void> createSession() async {
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
      final handle = await _workspace.newSession(
        cwd: _settings.projectDirectory,
      );
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
  void selectSession(String sessionId) {
    final cwd = _availableCwd[sessionId];
    if (cwd != null && _application.sessionById(SessionId(sessionId)) == null) {
      unawaited(_loadAndSelect(sessionId, cwd));
      return;
    }
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
    selectSession(sessionId);
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
            ),
    );
  }

  static SessionsState _activated(
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
  );
}
