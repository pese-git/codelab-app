import 'package:codelab_client_core/codelab_client_core.dart'
    show CommandCatalog;
import 'package:codelab_ui/codelab_ui.dart';

import 'connection_cubit.dart';
import 'ui_mappers.dart';

/// Состояние рабочего места в прежней форме — то, что читают виджеты,
/// интеграционные и характеризационные тесты.
///
/// Почему: на время change `extract-acp-client-kit` поверхность
/// `CodeLabShellCubit` не меняется (`09-10`, «Что остаётся неизменным»), хотя
/// состояние теперь принадлежит пяти Cubit-ам (design D10).
///
/// Для чего: снимок, который фасад собирает из частей после каждого их
/// изменения; сам ничего не вычисляет, кроме производных подписей.
///
/// Как использовать: только читать `CodeLabShellCubit.state`; меняется
/// состояние методами фасада. Удаляется вместе с фасадом после этапа 9.
final class CodeLabShellState {
  const CodeLabShellState({
    required this.connectionStatus,
    required this.transportType,
    required this.stdioProfileName,
    required this.stdioCommand,
    required this.stdioArgs,
    required this.stdioEnv,
    required this.webSocketEndpoint,
    required this.webSocketToken,
    required this.transportLabel,
    required this.profileLabel,
    required this.connectionDetail,
    this.connectionMessage,
    required this.currentSessionLabel,
    required this.currentSessionDetail,
    required this.sessions,
    required this.activeSessionId,
    required this.transcriptRows,
    this.transcriptExpansion = const {},
    this.turnState,
    required this.inspectorEntries,
    required this.viewMode,
    required this.isPromptEnabled,
    required this.isPromptSubmitting,
    required this.canCancel,
    required this.isRespondingToApproval,
    required this.isCommandPaletteOpen,
    this.sidebarCollapsed = false,
    this.sidebarOverlayOpen = false,
    this.openPanes = const [],
    this.activePane,
    this.dockOverlayOpen = false,
    this.sessionMode,
    required this.agentCommands,
    required this.commandCatalog,
    required this.composerDraft,
    this.composerDraftRevision = 0,
    required this.configOptions,
    required this.isRespondingToConfigOption,
    required this.sessionsPaneWidth,
    this.dockWidth = 360,
    required this.selectedProjectPath,
    required this.runAgentFromProjectDirectory,
    required this.recentProjects,
    this.hasMoreSessions = false,
    required this.currentPlan,
    required this.queuedPrompts,
  });

  // Подключение — `ConnectionCubit`.
  final CodeLabConnectionStatus connectionStatus;
  final CodeLabTransportType transportType;
  final String stdioProfileName;
  final String stdioCommand;
  final String stdioArgs;
  final String stdioEnv;
  final String webSocketEndpoint;
  final String webSocketToken;
  final String transportLabel;
  final String profileLabel;
  final String connectionDetail;

  /// Причина потери соединения или неудачного подключения для баннера над
  /// лентой (design D6 change `add-connection-and-error-states`).
  final String? connectionMessage;

  // Список и выбор сессий — `SessionsCubit`.
  final String currentSessionLabel;
  final String currentSessionDetail;
  final List<CodeLabSessionListItem> sessions;
  final String? activeSessionId;

  // Показываемая сессия — `ActiveSessionCubit`.
  final List<CodeLabTranscriptRow> transcriptRows;

  /// Ручное раскрытие строк ленты активной сессии — `TranscriptViewCubit`.
  final Map<String, bool> transcriptExpansion;

  /// Чип состояния хода в шапке; `null` — сессия свободна.
  final CodeLabTurnState? turnState;
  final List<CodeLabInspectorEntry> inspectorEntries;
  final bool isPromptSubmitting;
  final bool canCancel;
  final bool isRespondingToApproval;

  /// Команды, объявленные агентом (`available_commands_update`); каждое
  /// обновление заменяет список целиком.
  final List<CodeLabCommandAction> agentCommands;

  /// Каталог палитры: команды app и агента активной сессии с правилами kit
  /// (change `add-command-palette-agent-commands`, D2–D4).
  final CommandCatalog commandCatalog;

  /// Текст для композера после выбора команды агента (`/{name} `) или
  /// возврата промпта из очереди.
  final String composerDraft;

  /// Номер черновика для `CodeLabPromptComposer.draftRevision`.
  final int composerDraftRevision;
  final List<CodeLabConfigOption> configOptions;
  final bool isRespondingToConfigOption;

  /// План сессии; `null` — секция плана скрыта.
  final List<CodeLabPlanEntry>? currentPlan;

  /// Промпты, ждущие освобождения показываемой сессии, по порядку; агент их
  /// не видит до отправки (add-prompt-queue/design.md, Non-Goals).
  final List<CodeLabQueuedPrompt> queuedPrompts;

  // Раскладка — `LayoutCubit`; режим ленты и доступность композера пока
  // постоянны.
  final CodeLabViewMode viewMode;
  final bool isPromptEnabled;
  final bool isCommandPaletteOpen;
  final bool sidebarCollapsed;
  final bool sidebarOverlayOpen;

  /// Открытые панели дока и активная (change `redesign-workbench-shell`, D5).
  final List<ToolPane> openPanes;
  final ToolPane? activePane;
  final bool dockOverlayOpen;

  /// Режим активной сессии для чипа шапки; `null` — чипа нет.
  final String? sessionMode;
  final double sessionsPaneWidth;
  final double dockWidth;

  // Проект — `SettingsCubit`.
  final String? selectedProjectPath;
  final bool runAgentFromProjectDirectory;
  final List<CodeLabRecentProject> recentProjects;

  /// У агента есть следующая страница сессий — сайдбар показывает
  /// `Load more sessions` (design D7 change `add-session-list-and-reload`).
  final bool hasMoreSessions;

  /// Отличает «не передан» от «явно `null`» для [currentPlan] в [copyWith].
  static const Object _unset = Object();

  /// Копия с заменёнными полями — для тестов виджетов, которые показывают
  /// панели на подготовленном состоянии; фасад состояние так не меняет.
  CodeLabShellState copyWith({
    CodeLabConnectionStatus? connectionStatus,
    CodeLabTransportType? transportType,
    String? stdioProfileName,
    String? stdioCommand,
    String? stdioArgs,
    String? stdioEnv,
    String? webSocketEndpoint,
    String? webSocketToken,
    String? transportLabel,
    String? profileLabel,
    String? connectionDetail,
    Object? connectionMessage = _unset,
    String? currentSessionLabel,
    String? currentSessionDetail,
    List<CodeLabSessionListItem>? sessions,
    String? activeSessionId,
    List<CodeLabTranscriptRow>? transcriptRows,
    Map<String, bool>? transcriptExpansion,
    Object? turnState = _unset,
    List<CodeLabInspectorEntry>? inspectorEntries,
    CodeLabViewMode? viewMode,
    bool? isPromptEnabled,
    bool? isPromptSubmitting,
    bool? canCancel,
    bool? isRespondingToApproval,
    bool? isCommandPaletteOpen,
    bool? sidebarCollapsed,
    bool? sidebarOverlayOpen,
    List<ToolPane>? openPanes,
    Object? activePane = _unset,
    bool? dockOverlayOpen,
    Object? sessionMode = _unset,
    List<CodeLabCommandAction>? agentCommands,
    CommandCatalog? commandCatalog,
    String? composerDraft,
    int? composerDraftRevision,
    List<CodeLabConfigOption>? configOptions,
    bool? isRespondingToConfigOption,
    double? sessionsPaneWidth,
    double? dockWidth,
    String? selectedProjectPath,
    bool? runAgentFromProjectDirectory,
    List<CodeLabRecentProject>? recentProjects,
    bool? hasMoreSessions,
    Object? currentPlan = _unset,
    List<CodeLabQueuedPrompt>? queuedPrompts,
  }) {
    return CodeLabShellState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      transportType: transportType ?? this.transportType,
      stdioProfileName: stdioProfileName ?? this.stdioProfileName,
      stdioCommand: stdioCommand ?? this.stdioCommand,
      stdioArgs: stdioArgs ?? this.stdioArgs,
      stdioEnv: stdioEnv ?? this.stdioEnv,
      webSocketEndpoint: webSocketEndpoint ?? this.webSocketEndpoint,
      webSocketToken: webSocketToken ?? this.webSocketToken,
      transportLabel: transportLabel ?? this.transportLabel,
      profileLabel: profileLabel ?? this.profileLabel,
      connectionDetail: connectionDetail ?? this.connectionDetail,
      connectionMessage: identical(connectionMessage, _unset)
          ? this.connectionMessage
          : connectionMessage as String?,
      currentSessionLabel: currentSessionLabel ?? this.currentSessionLabel,
      currentSessionDetail: currentSessionDetail ?? this.currentSessionDetail,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      transcriptRows: transcriptRows ?? this.transcriptRows,
      transcriptExpansion: transcriptExpansion ?? this.transcriptExpansion,
      // `null` здесь — «сессия свободна», а не «не менять».
      turnState: identical(turnState, _unset)
          ? this.turnState
          : turnState as CodeLabTurnState?,
      inspectorEntries: inspectorEntries ?? this.inspectorEntries,
      viewMode: viewMode ?? this.viewMode,
      isPromptEnabled: isPromptEnabled ?? this.isPromptEnabled,
      isPromptSubmitting: isPromptSubmitting ?? this.isPromptSubmitting,
      canCancel: canCancel ?? this.canCancel,
      isRespondingToApproval:
          isRespondingToApproval ?? this.isRespondingToApproval,
      isCommandPaletteOpen: isCommandPaletteOpen ?? this.isCommandPaletteOpen,
      sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
      sidebarOverlayOpen: sidebarOverlayOpen ?? this.sidebarOverlayOpen,
      openPanes: openPanes ?? this.openPanes,
      activePane: identical(activePane, _unset)
          ? this.activePane
          : activePane as ToolPane?,
      dockOverlayOpen: dockOverlayOpen ?? this.dockOverlayOpen,
      sessionMode: identical(sessionMode, _unset)
          ? this.sessionMode
          : sessionMode as String?,
      agentCommands: agentCommands ?? this.agentCommands,
      commandCatalog: commandCatalog ?? this.commandCatalog,
      composerDraft: composerDraft ?? this.composerDraft,
      composerDraftRevision:
          composerDraftRevision ?? this.composerDraftRevision,
      configOptions: configOptions ?? this.configOptions,
      isRespondingToConfigOption:
          isRespondingToConfigOption ?? this.isRespondingToConfigOption,
      sessionsPaneWidth: sessionsPaneWidth ?? this.sessionsPaneWidth,
      dockWidth: dockWidth ?? this.dockWidth,
      selectedProjectPath: selectedProjectPath ?? this.selectedProjectPath,
      runAgentFromProjectDirectory:
          runAgentFromProjectDirectory ?? this.runAgentFromProjectDirectory,
      recentProjects: recentProjects ?? this.recentProjects,
      hasMoreSessions: hasMoreSessions ?? this.hasMoreSessions,
      currentPlan: identical(currentPlan, _unset)
          ? this.currentPlan
          : currentPlan as List<CodeLabPlanEntry>?,
      queuedPrompts: queuedPrompts ?? this.queuedPrompts,
    );
  }

  /// Полный список палитры: команды клиента, затем команды агента; команда
  /// агента вытесняет одноимённую недоступную команду клиента (D3).
  List<CodeLabCommandAction> get paletteActions =>
      paletteActionsOf(commandCatalog);

  /// Команды палитры под запрос пользователя, лучшие — первыми (D4); её
  /// получают палитра `Ctrl/Cmd+K` и inline-триггер композера.
  List<CodeLabCommandAction> searchPalette(String query) =>
      searchPaletteActions(commandCatalog, query);

  String get selectedProfileLabel => profileLabel;

  String get selectedConnectionDetail => connectionDetail;
}
