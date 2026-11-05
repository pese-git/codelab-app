import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show DirectoryExists, WorkingDirectoryProvider;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        AcpClientBackend,
        ClientWorkspace,
        ConfigTransportResolver,
        ConnectionProfile,
        ProfileSecretSource,
        RecentProjectsStore,
        SecretSource,
        SessionStatusView,
        WorkspaceDiagnostic;
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart'
    show StdioAcpAgentProfile;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/connection_preferences.dart';
import '../../../core/platform/dock_layout_store.dart';
import '../../../core/platform/project_folder_picker.dart';
import '../../settings/application/default_profile_resolver.dart';
import 'active_session_cubit.dart';
import 'connection_cubit.dart';
import 'layout_cubit.dart';
import 'sessions_cubit.dart';
import 'settings_cubit.dart';
import 'shell_part.dart';
import 'shell_state.dart';
import 'transcript_view_cubit.dart';
import 'ui_mappers.dart' show paletteCatalogOf;

export 'connection_cubit.dart'
    show CodeLabStdioTransportFactory, CodeLabWebSocketTransportFactory;
export 'layout_cubit.dart'
    show
        kDockMaxWidth,
        kDockMinWidth,
        kSessionsPaneMaxWidth,
        kSessionsPaneMinWidth;
export 'shell_state.dart';
export 'ui_mappers.dart'
    show
        CodeLabInspectorCategory,
        CodeLabInspectorDetail,
        CodeLabInspectorEntry;

/// Пять частей рабочего места и их общие пакет изменений и журнал.
///
/// Почему: части зависят друг от друга (сессии — от подключения, проекта и
/// показываемой сессии) и должны создаваться в одном порядке — после
/// `ClientWorkspace`, чтобы рабочее пространство раньше частей подписалось
/// на `sessionChanges` (design D6 change `extract-acp-client-kit`).
///
/// Для чего: одна точка сборки частей для графа cherrypick и для
/// `CodeLabShellCubit`, созданного без графа (`widget_test.dart`).
///
/// Как использовать: [CodeLabShellParts.build]; закрывает части фасад —
/// на этом change он их единственный потребитель (design D10).
/// [initialProfile] — профиль окна до первого подключения; с
/// [defaultProfiles] его заменяет профиль по умолчанию (D5, change
/// `add-app-settings-shell`), [preferences] включает «Connect on start»,
/// [eventLogger] получает событие `connection.connect_on_start` (D17).
final class CodeLabShellParts {
  CodeLabShellParts._({
    required this.changes,
    required this.diagnostics,
    required this.connection,
    required this.sessions,
    required this.activeSession,
    required this.settings,
    required this.layout,
    required this.transcriptView,
  });

  factory CodeLabShellParts.build({
    required ConnectionProfile initialProfile,
    required AcpClientApplication application,
    required ClientWorkspace workspace,
    required WorkingDirectoryProvider workingDirectoryProvider,
    required ProjectFolderPicker projectFolderPicker,
    required RecentProjectsStore recentProjectsStore,
    DirectoryExists? directoryExists,
    DockLayoutStore? dockLayoutStore,
    DefaultProfileResolver? defaultProfiles,
    ConnectionPreferences? preferences,
    Logger? logger,
    Logger? eventLogger,
    ProfileSecretSource? tokenSecrets,
  }) {
    final changes = ShellChanges();
    final diagnostics = ShellDiagnostics(logger: logger);
    final settings = SettingsCubit(
      changes: changes,
      workspace: workspace,
      diagnostics: diagnostics,
      workingDirectoryProvider: workingDirectoryProvider,
      projectFolderPicker: projectFolderPicker,
      recentProjectsStore: recentProjectsStore,
      directoryExists: directoryExists,
    );
    final activeSession = ActiveSessionCubit(
      changes: changes,
      workspace: workspace,
      diagnostics: diagnostics,
    );
    final connection = ConnectionCubit(
      changes: changes,
      initialProfile: initialProfile,
      workspace: workspace,
      diagnostics: diagnostics,
      settings: settings,
      activeSession: activeSession,
      defaultProfiles: defaultProfiles,
      preferences: preferences,
      eventLogger: eventLogger,
      tokenSecrets: tokenSecrets,
    );
    return CodeLabShellParts._(
      changes: changes,
      diagnostics: diagnostics,
      connection: connection,
      sessions: SessionsCubit(
        changes: changes,
        application: application,
        workspace: workspace,
        diagnostics: diagnostics,
        connection: connection,
        settings: settings,
        activeSession: activeSession,
      ),
      activeSession: activeSession,
      settings: settings,
      layout: LayoutCubit(
        changes: changes,
        dockLayoutStore: dockLayoutStore,
        diagnostics: diagnostics,
      ),
      transcriptView: TranscriptViewCubit(changes: changes),
    );
  }

  final ShellChanges changes;
  final ShellDiagnostics diagnostics;
  final ConnectionCubit connection;
  final SessionsCubit sessions;
  final ActiveSessionCubit activeSession;
  final SettingsCubit settings;
  final LayoutCubit layout;
  final TranscriptViewCubit transcriptView;

  Future<void> close() async {
    await sessions.close();
    await connection.close();
    await activeSession.close();
    await settings.close();
    await layout.close();
    await transcriptView.close();
  }
}

/// Фасад рабочего места CodeLab над пятью Cubit-ами и `ClientWorkspace`.
///
/// Почему: логика клиента перенесена в `codelab_client_core`, а состояние
/// рабочего места разделено на `ConnectionCubit`, `SessionsCubit`,
/// `ActiveSessionCubit`, `SettingsCubit` и `LayoutCubit` (change
/// `extract-acp-client-kit`, design D10). Виджеты, интеграционные и
/// характеризационные тесты по-прежнему читают [CodeLabShellState]; фасад
/// сохраняет эту поверхность до перевода тестов после этапа 9.
///
/// Для чего: собирает [CodeLabShellState] из частей — одно состояние на
/// каждый пакет изменений частей ([ShellChanges]) — и делегирует им
/// публичные методы; сам пишет в журнал только диагностику kit.
///
/// Как использовать: граф cherrypick (`app_scope.dart`) передаёт
/// [workspace], [secrets] и [parts]; [profile] ему не нужен — начальный
/// профиль уже в [parts]. Без [parts] [profile] обязателен. Без них Cubit строит рабочее
/// пространство и части сам поверх [application] и фабрик транспорта: так
/// его создают тесты `widget_test.dart`. Параметры use case-ов
/// `codelab_client_acp` (`createSessionUseCase`, `sendPromptUseCase` и другие)
/// не используются; они остаются, пока эти тесты создают Cubit напрямую.
final class CodeLabShellCubit extends Cubit<CodeLabShellState> {
  factory CodeLabShellCubit({
    StdioAcpAgentProfile? profile,
    required AcpClientApplication application,
    CreateSession? createSessionUseCase,
    SendPrompt? sendPromptUseCase,
    CancelTurn? cancelTurnUseCase,
    Reconnect? reconnectUseCase,
    RespondToPermission? respondToPermissionUseCase,
    SetSessionConfigOption? setSessionConfigOptionUseCase,
    CodeLabStdioTransportFactory? stdioTransportFactory,
    CodeLabWebSocketTransportFactory? webSocketTransportFactory,
    ClientWorkspace? workspace,
    SecretSource? secrets,
    CodeLabShellParts? parts,
    required WorkingDirectoryProvider workingDirectoryProvider,
    required ProjectFolderPicker projectFolderPicker,
    required RecentProjectsStore recentProjectsStore,
    DirectoryExists? directoryExists,
    DockLayoutStore? dockLayoutStore,
    Logger? logger,
  }) {
    // Без графа токена из окружения нет: ссылки `env:` дают подключение без
    // токена (тесты передают свой источник).
    final secretSource = secrets ?? const ProfileSecretSource({});
    final clientWorkspace =
        workspace ??
        ClientWorkspace(
          backend: AcpClientBackend(application),
          resolvers: [
            ConfigTransportResolver(
              stdio: stdioTransportFactory,
              webSocket: webSocketTransportFactory,
              secrets: secretSource,
            ),
          ],
        );
    return CodeLabShellCubit._(
      workspace: clientWorkspace,
      ownsWorkspace: workspace == null,
      parts:
          parts ??
          CodeLabShellParts.build(
            initialProfile: stdioConnectionProfileOf(
              profile ??
                  (throw ArgumentError.notNull(
                    'profile (required without parts)',
                  )),
            ),
            application: application,
            workspace: clientWorkspace,
            workingDirectoryProvider: workingDirectoryProvider,
            projectFolderPicker: projectFolderPicker,
            recentProjectsStore: recentProjectsStore,
            directoryExists: directoryExists,
            dockLayoutStore: dockLayoutStore,
            logger: logger,
          ),
    );
  }

  CodeLabShellCubit._({
    required ClientWorkspace workspace,
    required bool ownsWorkspace,
    required CodeLabShellParts parts,
  }) : _workspace = workspace,
       _ownsWorkspace = ownsWorkspace,
       _parts = parts,
       super(_compose(parts)) {
    _parts.changes.listen(() => emit(_compose(_parts)));
    _diagnosticSubscription = _workspace.diagnostics.listen(
      _handleKitDiagnostic,
    );
  }

  final ClientWorkspace _workspace;

  /// Рабочее пространство создал сам Cubit (без графа cherrypick) — тогда он
  /// и закрывает его в [close].
  final bool _ownsWorkspace;
  final CodeLabShellParts _parts;
  late final StreamSubscription<WorkspaceDiagnostic> _diagnosticSubscription;

  ConnectionCubit get _connection => _parts.connection;
  SessionsCubit get _sessions => _parts.sessions;
  ActiveSessionCubit get _activeSession => _parts.activeSession;
  SettingsCubit get _settings => _parts.settings;
  LayoutCubit get _layout => _parts.layout;

  Future<void> selectProject(String path) => _settings.selectProject(path);

  Future<void> browseForProject() => _settings.browseForProject();

  /// Подключает окно к [profile], а без него — к профилю окна (до первого
  /// подключения — к профилю по умолчанию).
  Future<void> connect([ConnectionProfile? profile]) =>
      _connection.connect(profile);

  Future<void> reconnect() => _connection.reconnect();

  /// «Connect on start» (D8): app зовёт его после первого кадра; один раз.
  Future<void> connectOnStart() => _connection.connectOnStart();

  void resizeSessionsPane(double width) => _layout.resizeSessionsPane(width);

  void resizeDock(double width) => _layout.resizeDock(width);

  void toggleSidebarCollapsed() => _layout.toggleSidebarCollapsed();

  void toggleSidebarOverlay() => _layout.toggleSidebarOverlay();

  void closeSidebarOverlay() => _layout.closeSidebarOverlay();

  void togglePane(ToolPane pane) => _layout.togglePane(pane);

  /// Запоминает ручное раскрытие строки ленты активной сессии
  /// (`CodeLabTranscriptPanel.onExpansionChanged`, design D3 change
  /// `redesign-transcript-rows`); без активной сессии — no-op.
  void setTranscriptRowExpanded(String rowId, bool expanded) {
    final sessionId = _parts.activeSession.state.sessionId;
    if (sessionId == null) {
      return;
    }
    _parts.transcriptView.setExpanded(
      sessionId: sessionId,
      rowId: rowId,
      expanded: expanded,
    );
  }

  void openPane(ToolPane pane) => _layout.openPane(pane);

  void selectPane(ToolPane pane) => _layout.selectPane(pane);

  void closePane(ToolPane pane) => _layout.closePane(pane);

  void dismissDockOverlay() => _layout.dismissDockOverlay();

  Future<void> createSession() => _sessions.createSession();

  Future<void> loadMoreSessions() => _sessions.loadMoreSessions();

  void selectSession(String sessionId) => _sessions.selectSession(sessionId);

  /// Активирует сессию, только если она открыта в этом запуске (есть
  /// `SessionHandle`); `false` — сессии нет, активная не меняется.
  ///
  /// Для чего: возврат из настроек (`NavigationCubit.back`, design.md change
  /// `add-app-settings-shell`, D2) не должен выбирать закрытую или ещё не
  /// загруженную сессию.
  bool selectSessionIfOpen(String sessionId) {
    if (_workspace.session(SessionId(sessionId)) == null) {
      return false;
    }
    selectSession(sessionId);
    return true;
  }

  /// Сессии с ожидающим запросом разрешения в порядке списка kit.
  ///
  /// Почему здесь: признак берётся из `SessionView.pendingApprovals` — тех
  /// самых одобрений, что рисует лента, — а не из отдельного источника
  /// (design.md change `add-app-settings-shell`, D2, «Ожидающее одобрение»).
  /// Для чего: InfoBar экрана настроек. Значение читается при каждом
  /// состоянии фасада; подписки на сессии оно не заводит.
  List<String> get sessionIdsWithPendingApproval {
    // После потери соединения запрос остаётся в `SessionView`, но отвечать на
    // него уже некому: InfoBar не должен звать к мёртвому запросу (spec
    // app-settings «Ожидающее одобрение видно из настроек»).
    if (_connection.state.connectionStatus !=
        CodeLabConnectionStatus.connected) {
      return const [];
    }
    return [
      for (final summary in _workspace.current.sessions)
        // `detached`: сессию не загрузили после reconnect, её запрос — от
        // прежнего соединения, отвечать на него некому.
        if (summary.status != SessionStatusView.detached &&
            (_workspace
                    .session(summary.id)
                    ?.current
                    .pendingApprovals
                    .isNotEmpty ??
                false))
          summary.id.value,
    ];
  }

  /// Сессия, к которой ведёт «Back to session»: активная, если у неё есть
  /// запрос, иначе первая в порядке сайдбара; `null` — запросов нет.
  String? get sessionIdForPendingApproval {
    final ids = sessionIdsWithPendingApproval;
    if (ids.isEmpty) {
      return null;
    }
    final active = _workspace.current.activeSessionId?.value;
    return ids.contains(active) ? active : ids.first;
  }

  Future<void> submitPrompt(String prompt) =>
      _activeSession.submitPrompt(prompt);

  void editQueuedPrompt(String id) => _activeSession.editQueuedPrompt(id);

  void deleteQueuedPrompt(String id) => _activeSession.deleteQueuedPrompt(id);

  Future<void> sendQueuedPromptNow(String id) =>
      _activeSession.sendQueuedPromptNow(id);

  void clearQueuedPrompts() => _activeSession.clearQueuedPrompts();

  Future<void> cancelTurn() => _activeSession.cancelTurn();

  /// Ответ на конкретное одобрение — см.
  /// [ActiveSessionCubit.respondToApproval] (PERM-003).
  Future<void> respondToApproval({
    required ApprovalRequestId approvalId,
    required SessionId sessionId,
    required String optionId,
  }) => _activeSession.respondToApproval(
    approvalId: approvalId,
    sessionId: sessionId,
    optionId: optionId,
  );

  Future<void> setSessionConfigOption(String configId, String value) =>
      _activeSession.setSessionConfigOption(configId, value);

  void openCommandPalette() => _layout.openCommandPalette();

  void closeCommandPalette() => _layout.closeCommandPalette();

  /// Выполняет выбранную команду палитры одинаково для любого способа её
  /// открыть (`Ctrl/Cmd+K` или `/` в композере, wire-command-palette/
  /// design.md).
  ///
  /// Недоступные команды клиента (`/plan`, `/permissions`, `/compact`)
  /// оставляют палитру открытой и ничего не делают — пользователю не
  /// сообщается о действии, которого не было. Команды агента здесь только
  /// закрывают палитру: протокольного метода у них нет, текст в композер
  /// вставляет [insertAgentCommand].
  void selectCommand(CodeLabCommandAction action) {
    if (!action.isAvailable) {
      return;
    }

    switch (action.id) {
      case 'new':
        unawaited(createSession());
      case 'reconnect':
        unawaited(reconnect());
      case 'logs':
        // Протокол и debug log теперь — панель Protocol дока (change
        // `redesign-workbench-shell`, D5).
        _layout.openPane(ToolPane.protocol);
      default:
        break;
    }

    closeCommandPalette();
  }

  /// Выбор команды агента: `AvailableCommand` в ACP не вызывается, поэтому в
  /// композер вставляется `/{name} ` — пользователь дописывает и отправляет
  /// обычный промпт.
  void insertAgentCommand(CodeLabCommandAction action) {
    _activeSession.setComposerDraft('${action.slashCommand} ');
    closeCommandPalette();
  }

  void dismissPlan() => _activeSession.dismissPlan();

  @override
  Future<void> close() async {
    _parts.changes.listen(null);
    await _diagnosticSubscription.cancel();
    await _parts.close();
    if (_ownsWorkspace) {
      await _workspace.dispose();
    }
    return super.close();
  }

  /// Диагностика событий kit — та же запись в структурный журнал, что
  /// раньше делал сам Cubit (design D9).
  void _handleKitDiagnostic(WorkspaceDiagnostic diagnostic) =>
      _parts.diagnostics.record(
        diagnostic.message,
        severity: diagnostic.severity,
        source: diagnostic.source,
      );

  static CodeLabShellState _compose(CodeLabShellParts parts) {
    final connection = parts.connection.state;
    final sessions = parts.sessions.state;
    final active = parts.activeSession.state;
    final settings = parts.settings.state;
    final layout = parts.layout.state;
    final transcriptView = parts.transcriptView.state;
    return CodeLabShellState(
      connectionStatus: connection.connectionStatus,
      transportLabel: connection.transportLabel,
      profileLabel: connection.selectedProfileLabel,
      connectionDetail: connection.selectedConnectionDetail,
      connectionMessage: connection.connectionMessage,
      currentSessionLabel: sessions.currentSessionLabel,
      currentSessionDetail: sessions.currentSessionDetail,
      sessions: sessions.sessions,
      activeSessionId: sessions.activeSessionId,
      transcriptRows: active.transcriptRows,
      transcriptExpansion: transcriptView.overridesFor(active.sessionId),
      turnState: active.turnState,
      inspectorEntries: active.inspectorEntries,
      viewMode: CodeLabViewMode.normal,
      isPromptEnabled: true,
      isPromptSubmitting: active.isPromptSubmitting,
      canCancel: active.canCancel,
      isRespondingToApproval: active.isRespondingToApproval,
      isCommandPaletteOpen: layout.isCommandPaletteOpen,
      sidebarCollapsed: layout.sidebarCollapsed,
      sidebarOverlayOpen: layout.sidebarOverlayOpen,
      openPanes: layout.openPanes,
      activePane: layout.activePane,
      dockOverlayOpen: layout.dockOverlayOpen,
      sessionMode: active.sessionMode,
      agentCommands: active.agentCommands,
      commandCatalog: paletteCatalogOf(active.agentCommandViews),
      composerDraft: active.composerDraft,
      composerDraftRevision: active.composerDraftRevision,
      configOptions: active.configOptions,
      isRespondingToConfigOption: active.isRespondingToConfigOption,
      sessionsPaneWidth: layout.sessionsPaneWidth,
      dockWidth: layout.dockWidth,
      selectedProjectPath: settings.selectedProjectPath,
      recentProjects: settings.recentProjects,
      hasMoreSessions: sessions.hasMoreSessions,
      currentPlan: active.currentPlan,
      queuedPrompts: active.queuedPrompts,
    );
  }
}
