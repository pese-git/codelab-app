import 'package:codelab_client_core/codelab_client_core.dart'
    show CommandCatalog;
import 'package:codelab_ui/codelab_ui.dart';

import '../../usage/application/usage_pane_data.dart';
import 'agents_pane_data.dart';
import 'connection_cubit.dart' show ProviderSetupNotice, RestartConfirmation;
import 'sessions_cubit.dart' show PendingRootSession;
import 'ui_mappers.dart';

/// Заметка над лентой о сбое действия фасада (D5): типизированное разовое
/// сообщение, текст собирает presentation.
enum ShellLinkNote {
  /// Платформа отказала открыть ссылку из ответа агента.
  openFailed,
}

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
    required this.transportLabel,
    required this.profileLabel,
    required this.connectionDetail,
    this.connectionMessage,
    this.providerSetupNotice,
    this.connectionRepeat = 0,
    this.pendingRestart,
    required this.currentSessionLabel,
    required this.currentSessionDetail,
    required this.sessions,
    required this.activeSessionId,
    required this.transcriptRows,
    this.transcriptExpansion = const {},
    this.shownImages = const {},
    this.linkNote,
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
    this.projectFilesAvailable = false,
    this.agents = AgentsPaneData.empty,
    this.selectedAgentId,
    this.transcriptShowRequest,
    this.sessionMode,
    this.statusBar,
    this.usage = UsagePaneData.empty,
    required this.agentCommands,
    required this.commandCatalog,
    required this.composerDraft,
    this.composerDraftRevision = 0,
    required this.configOptions,
    required this.isRespondingToConfigOption,
    required this.sessionsPaneWidth,
    this.dockWidth = 360,
    required this.selectedProjectPath,
    required this.recentProjects,
    this.hasMoreSessions = false,
    this.pendingRootSession,
    this.sessionFolders = const {},
    required this.currentPlan,
    required this.queuedPrompts,
  });

  // Подключение — `ConnectionCubit`.
  final CodeLabConnectionStatus connectionStatus;
  final String transportLabel;
  final String profileLabel;
  final String connectionDetail;

  /// Причина потери соединения или неудачного подключения для баннера над
  /// лентой (design D6 change `add-connection-and-error-states`).
  final String? connectionMessage;

  /// Метка сбоя встроенного агента «не настроен провайдер»: баннер с «Add
  /// provider» вместо сырого текста проблем (change `add-provider-setup-ui`,
  /// D26); `null` — сбой другой.
  final ProviderSetupNotice? providerSetupNotice;

  /// Сколько раз подряд повторился тот же сбой старта (`Failed again (n)`,
  /// D13); `0` — сбой первый.
  final int connectionRepeat;

  /// Диалог «Restart agent» ждёт ответа (D22); `null` — не ждёт.
  final RestartConfirmation? pendingRestart;

  // Список и выбор сессий — `SessionsCubit`.
  final String currentSessionLabel;
  final String currentSessionDetail;
  final List<CodeLabSessionListItem> sessions;
  final String? activeSessionId;

  // Показываемая сессия — `ActiveSessionCubit`.
  final List<CodeLabTranscriptRow> transcriptRows;

  /// Ручное раскрытие строк ленты активной сессии — `TranscriptViewCubit`.
  final Map<String, bool> transcriptExpansion;

  /// Ключи `<rowId>#image:<url>` изображений, показанных пользователем в
  /// активной сессии: снимок `TranscriptViewCubit`, не отдельное хранилище
  /// (change `add-desktop-markdown`, D6).
  final Set<String> shownImages;

  /// Заметка для InfoBar над лентой после неудачного открытия ссылки (D5);
  /// `null` — заметки нет. Типизирована: текст собирает presentation по
  /// каталогу, а не фасад (`add-desktop-localization`, D5).
  final ShellLinkNote? linkNote;

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

  /// Панель Files предлагается: папка сессии на этой машине
  /// (`sessionFolderIsLocal` профиля окна) и хост привязал `ProjectFiles`.
  /// Решает application, а не виджет (design.md change
  /// `add-file-preview-and-tree`, D7).
  final bool projectFilesAvailable;

  /// Данные панели Agents сессии в фокусе (D33, D49 Т8).
  final AgentsPaneData agents;

  /// Панель Agents предлагается: у сессии в фокусе есть хотя бы одна строка
  /// субагента (D49 Т11). Объявление агента условием не является.
  bool get agentsAvailable => !agents.isEmpty;

  /// Выбранная строка панели Agents (`toolCallId`); `null` — не выбрана или
  /// строки с таким id в сессии уже нет (выбор не применяется, D49 Т8).
  final String? selectedAgentId;

  /// Разовый запрос показа строки ленты для сессии в фокусе (D49 Т7).
  final CodeLabTranscriptShowRequest? transcriptShowRequest;

  /// Режим активной сессии для чипа шапки; `null` — чипа нет.
  final String? sessionMode;

  /// Строка статуса под композером (D11); `null` — строки нет.
  final CodeLabSessionStatusData? statusBar;

  /// Данные панели Usage сессии в фокусе (change `add-desktop-usage-pane`,
  /// D1); собирает `ActiveSessionCubit`, виджеты только читают.
  final UsagePaneData usage;

  /// Панель Usage предлагается: у сессии в фокусе есть `usageLedger` или
  /// живые снимки `usage` (D10). Решает application, а не виджет.
  bool get usageAvailable => usage.available;
  final double sessionsPaneWidth;
  final double dockWidth;

  // Проект — `SettingsCubit`.
  final String? selectedProjectPath;
  final List<CodeLabRecentProject> recentProjects;

  /// У агента есть следующая страница сессий — сайдбар показывает
  /// `Load more sessions` (design D7 change `add-session-list-and-reload`).
  final bool hasMoreSessions;

  /// Сессия в корне диска ждёт подтверждения (D24): виджет показывает диалог
  /// `Open anyway?`; `null` — подтверждения нет.
  final PendingRootSession? pendingRootSession;

  /// Папка (`cwd`) каждой сессии по id — из `WorkspaceState`, не из подписи
  /// строки (Q23): сайдбар раскладывает по ним сессии разных папок.
  final Map<String, String> sessionFolders;

  /// Отличает «не передан» от «явно `null`» для [currentPlan] в [copyWith].
  static const Object _unset = Object();

  /// Копия с заменёнными полями — для тестов виджетов, которые показывают
  /// панели на подготовленном состоянии; фасад состояние так не меняет.
  CodeLabShellState copyWith({
    CodeLabConnectionStatus? connectionStatus,
    String? transportLabel,
    String? profileLabel,
    String? connectionDetail,
    Object? connectionMessage = _unset,
    Object? providerSetupNotice = _unset,
    int? connectionRepeat,
    Object? pendingRestart = _unset,
    String? currentSessionLabel,
    String? currentSessionDetail,
    List<CodeLabSessionListItem>? sessions,
    String? activeSessionId,
    List<CodeLabTranscriptRow>? transcriptRows,
    Map<String, bool>? transcriptExpansion,
    Set<String>? shownImages,
    Object? linkNote = _unset,
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
    bool? projectFilesAvailable,
    AgentsPaneData? agents,
    Object? selectedAgentId = _unset,
    Object? transcriptShowRequest = _unset,
    Object? sessionMode = _unset,
    Object? statusBar = _unset,
    UsagePaneData? usage,
    List<CodeLabCommandAction>? agentCommands,
    CommandCatalog? commandCatalog,
    String? composerDraft,
    int? composerDraftRevision,
    List<CodeLabConfigOption>? configOptions,
    bool? isRespondingToConfigOption,
    double? sessionsPaneWidth,
    double? dockWidth,
    String? selectedProjectPath,
    List<CodeLabRecentProject>? recentProjects,
    bool? hasMoreSessions,
    Object? pendingRootSession = _unset,
    Map<String, String>? sessionFolders,
    Object? currentPlan = _unset,
    List<CodeLabQueuedPrompt>? queuedPrompts,
  }) {
    return CodeLabShellState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      transportLabel: transportLabel ?? this.transportLabel,
      profileLabel: profileLabel ?? this.profileLabel,
      connectionDetail: connectionDetail ?? this.connectionDetail,
      connectionMessage: identical(connectionMessage, _unset)
          ? this.connectionMessage
          : connectionMessage as String?,
      providerSetupNotice: identical(providerSetupNotice, _unset)
          ? this.providerSetupNotice
          : providerSetupNotice as ProviderSetupNotice?,
      connectionRepeat: connectionRepeat ?? this.connectionRepeat,
      pendingRestart: identical(pendingRestart, _unset)
          ? this.pendingRestart
          : pendingRestart as RestartConfirmation?,
      currentSessionLabel: currentSessionLabel ?? this.currentSessionLabel,
      currentSessionDetail: currentSessionDetail ?? this.currentSessionDetail,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      transcriptRows: transcriptRows ?? this.transcriptRows,
      transcriptExpansion: transcriptExpansion ?? this.transcriptExpansion,
      shownImages: shownImages ?? this.shownImages,
      linkNote: identical(linkNote, _unset)
          ? this.linkNote
          : linkNote as ShellLinkNote?,
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
      projectFilesAvailable:
          projectFilesAvailable ?? this.projectFilesAvailable,
      agents: agents ?? this.agents,
      selectedAgentId: identical(selectedAgentId, _unset)
          ? this.selectedAgentId
          : selectedAgentId as String?,
      transcriptShowRequest: identical(transcriptShowRequest, _unset)
          ? this.transcriptShowRequest
          : transcriptShowRequest as CodeLabTranscriptShowRequest?,
      sessionMode: identical(sessionMode, _unset)
          ? this.sessionMode
          : sessionMode as String?,
      statusBar: identical(statusBar, _unset)
          ? this.statusBar
          : statusBar as CodeLabSessionStatusData?,
      usage: usage ?? this.usage,
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
      recentProjects: recentProjects ?? this.recentProjects,
      hasMoreSessions: hasMoreSessions ?? this.hasMoreSessions,
      sessionFolders: sessionFolders ?? this.sessionFolders,
      pendingRootSession: identical(pendingRootSession, _unset)
          ? this.pendingRootSession
          : pendingRootSession as PendingRootSession?,
      currentPlan: identical(currentPlan, _unset)
          ? this.currentPlan
          : currentPlan as List<CodeLabPlanEntry>?,
      queuedPrompts: queuedPrompts ?? this.queuedPrompts,
    );
  }

  /// Полный список палитры: команды клиента, затем команды агента; команда
  /// агента вытесняет одноимённую недоступную команду клиента (D3). Подписи
  /// команд хоста уже на языке каталога: пункт `reconnect` для локального
  /// агента называется «Restart agent» (Q24, D22) — это решает
  /// `paletteCatalogOf` по типу профиля (`add-desktop-localization`, D4).
  List<CodeLabCommandAction> get paletteActions =>
      paletteActionsOf(commandCatalog);

  /// Команды палитры под запрос пользователя, лучшие — первыми (D4); её
  /// получают палитра `Ctrl/Cmd+K` и inline-триггер композера.
  List<CodeLabCommandAction> searchPalette(String query) =>
      searchPaletteActions(commandCatalog, query);

  String get selectedProfileLabel => profileLabel;

  String get selectedConnectionDetail => connectionDetail;
}
