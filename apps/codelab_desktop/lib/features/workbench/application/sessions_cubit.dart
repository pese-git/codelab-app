import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, describeFailure;
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
  });

  /// Строки сайдбара, последняя изменившаяся сессия первой.
  final List<CodeLabSessionListItem> sessions;
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
  }

  final AcpClientApplication _application;
  final ClientWorkspace _workspace;
  final ShellDiagnostics _diagnostics;
  final ConnectionCubit _connection;
  final SettingsCubit _settings;
  final ActiveSessionCubit _activeSession;
  late final StreamSubscription<AcpSession> _sessionSubscription;

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
            currentSessionLabel: selected?.title ?? 'Session $sessionId',
            currentSessionDetail: selected?.subtitle ?? sessionId,
          ),
        );
        _activeSession.showMissing(sessionId);
        return;
      }
      final item = sessionListItemOf(session);
      emit(_activated(item, session, sessions: state.sessions));
      _activeSession.show(session);
    });
  }

  @override
  Future<void> close() async {
    await _sessionSubscription.cancel();
    return super.close();
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
    final sessions = [
      item,
      ...state.sessions.where((other) => other.id != item.id),
    ];
    emit(
      activate
          ? _activated(item, session, sessions: sessions)
          : SessionsState(
              sessions: sessions,
              activeSessionId: state.activeSessionId,
              currentSessionLabel: state.currentSessionLabel,
              currentSessionDetail: state.currentSessionDetail,
            ),
    );
  }

  static SessionsState _activated(
    CodeLabSessionListItem item,
    AcpSession session, {
    required List<CodeLabSessionListItem> sessions,
  }) => SessionsState(
    sessions: sessions,
    activeSessionId: item.id,
    currentSessionLabel: item.title,
    currentSessionDetail: item.subtitle ?? session.id.value,
  );
}
