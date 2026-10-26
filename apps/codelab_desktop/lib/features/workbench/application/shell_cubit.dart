import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show WorkingDirectoryProvider;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        AcpClientBackend,
        ClientWorkspace,
        ConfigTransportResolver,
        InMemorySecretSource,
        RecentProjectsStore,
        WorkspaceDiagnostic;
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart'
    show StdioAcpAgentProfile;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/project_folder_picker.dart';
import 'active_session_cubit.dart';
import 'connection_cubit.dart';
import 'layout_cubit.dart';
import 'sessions_cubit.dart';
import 'settings_cubit.dart';
import 'shell_part.dart';
import 'shell_state.dart';

export 'connection_cubit.dart'
    show
        CodeLabStdioTransportFactory,
        CodeLabTransportType,
        CodeLabWebSocketTransportFactory;
export 'layout_cubit.dart'
    show
        kInspectorPaneMaxWidth,
        kInspectorPaneMinWidth,
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
final class CodeLabShellParts {
  CodeLabShellParts._({
    required this.changes,
    required this.diagnostics,
    required this.connection,
    required this.sessions,
    required this.activeSession,
    required this.settings,
    required this.layout,
  });

  factory CodeLabShellParts.build({
    required StdioAcpAgentProfile profile,
    required AcpClientApplication application,
    required ClientWorkspace workspace,
    required InMemorySecretSource secrets,
    required WorkingDirectoryProvider workingDirectoryProvider,
    required ProjectFolderPicker projectFolderPicker,
    required RecentProjectsStore recentProjectsStore,
    Logger? logger,
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
    );
    final activeSession = ActiveSessionCubit(
      changes: changes,
      workspace: workspace,
      diagnostics: diagnostics,
    );
    final connection = ConnectionCubit(
      changes: changes,
      profile: profile,
      workspace: workspace,
      secrets: secrets,
      diagnostics: diagnostics,
      settings: settings,
      activeSession: activeSession,
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
      layout: LayoutCubit(changes: changes),
    );
  }

  final ShellChanges changes;
  final ShellDiagnostics diagnostics;
  final ConnectionCubit connection;
  final SessionsCubit sessions;
  final ActiveSessionCubit activeSession;
  final SettingsCubit settings;
  final LayoutCubit layout;

  Future<void> close() async {
    await sessions.close();
    await connection.close();
    await activeSession.close();
    await settings.close();
    await layout.close();
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
/// [workspace], [secrets] и [parts]. Без них Cubit строит рабочее
/// пространство и части сам поверх [application] и фабрик транспорта: так
/// его создают тесты `widget_test.dart`. Параметры use case-ов
/// `codelab_client_acp` (`createSessionUseCase`, `sendPromptUseCase` и другие)
/// не используются; они остаются, пока эти тесты создают Cubit напрямую.
final class CodeLabShellCubit extends Cubit<CodeLabShellState> {
  factory CodeLabShellCubit({
    required StdioAcpAgentProfile profile,
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
    InMemorySecretSource? secrets,
    CodeLabShellParts? parts,
    required WorkingDirectoryProvider workingDirectoryProvider,
    required ProjectFolderPicker projectFolderPicker,
    required RecentProjectsStore recentProjectsStore,
    Logger? logger,
  }) {
    final secretSource = secrets ?? InMemorySecretSource();
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
            profile: profile,
            application: application,
            workspace: clientWorkspace,
            secrets: secretSource,
            workingDirectoryProvider: workingDirectoryProvider,
            projectFolderPicker: projectFolderPicker,
            recentProjectsStore: recentProjectsStore,
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

  void selectTransport(CodeLabTransportType transportType) =>
      _connection.selectTransport(transportType);

  void updateStdioProfileName(String value) =>
      _connection.updateStdioProfileName(value);

  void updateStdioCommand(String value) =>
      _connection.updateStdioCommand(value);

  void updateStdioArgs(String value) => _connection.updateStdioArgs(value);

  void updateStdioEnv(String value) => _connection.updateStdioEnv(value);

  void updateWebSocketEndpoint(String value) =>
      _connection.updateWebSocketEndpoint(value);

  void updateWebSocketToken(String value) =>
      _connection.updateWebSocketToken(value);

  Future<void> selectProject(String path) => _settings.selectProject(path);

  Future<void> browseForProject() => _settings.browseForProject();

  void toggleRunAgentFromProjectDirectory(bool value) =>
      _settings.toggleRunAgentFromProjectDirectory(value);

  Future<void> connect() => _connection.connect();

  Future<void> reconnect() => _connection.reconnect();

  void resizeSessionsPane(double width) => _layout.resizeSessionsPane(width);

  void resizeInspectorPane(double width) => _layout.resizeInspectorPane(width);

  Future<void> createSession() => _sessions.createSession();

  void selectSession(String sessionId) => _sessions.selectSession(sessionId);

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
        _layout.showInspectorInNarrowLayout();
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
    return CodeLabShellState(
      connectionStatus: connection.connectionStatus,
      transportType: connection.transportType,
      stdioProfileName: connection.stdioProfileName,
      stdioCommand: connection.stdioCommand,
      stdioArgs: connection.stdioArgs,
      stdioEnv: connection.stdioEnv,
      webSocketEndpoint: connection.webSocketEndpoint,
      webSocketToken: connection.webSocketToken,
      transportLabel: connection.transportType.label,
      profileLabel: connection.selectedProfileLabel,
      connectionDetail: connection.selectedConnectionDetail,
      currentSessionLabel: sessions.currentSessionLabel,
      currentSessionDetail: sessions.currentSessionDetail,
      sessions: sessions.sessions,
      activeSessionId: sessions.activeSessionId,
      transcriptEntries: active.transcriptEntries,
      inspectorEntries: active.inspectorEntries,
      viewMode: CodeLabViewMode.normal,
      isPromptEnabled: true,
      isPromptSubmitting: active.isPromptSubmitting,
      canCancel: active.canCancel,
      isRespondingToApproval: active.isRespondingToApproval,
      isCommandPaletteOpen: layout.isCommandPaletteOpen,
      isInspectorVisibleInNarrowLayout: layout.isInspectorVisibleInNarrowLayout,
      agentCommands: active.agentCommands,
      composerDraft: active.composerDraft,
      configOptions: active.configOptions,
      isRespondingToConfigOption: active.isRespondingToConfigOption,
      sessionsPaneWidth: layout.sessionsPaneWidth,
      inspectorPaneWidth: layout.inspectorPaneWidth,
      selectedProjectPath: settings.selectedProjectPath,
      runAgentFromProjectDirectory: settings.runAgentFromProjectDirectory,
      recentProjects: settings.recentProjects,
      currentPlan: active.currentPlan,
      queuedPrompts: active.queuedPrompts,
    );
  }
}
