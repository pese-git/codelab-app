import 'dart:async';
import 'dart:convert';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_client_kit/acp_client_kit.dart'
    show
        AcpClientBackend,
        AgentTextItem,
        ApprovalStateView,
        ClientWorkspace,
        ClientWorkspaceException,
        ConfigTransportResolver,
        Connected,
        ConnectionFailed,
        ConnectionProfile,
        ConnectionView,
        Connecting,
        Disconnected,
        InMemorySecretSource,
        NoticeItem,
        NoticeKind,
        PendingApprovalView,
        Reconnecting,
        ResolvedApprovalView,
        ThoughtItem,
        ToolCallItem,
        ToolCallStatusView,
        TranscriptItem,
        UserItem,
        WorkspaceState;
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/project_folder_picker.dart';
import '../../../core/platform/recent_projects_store.dart';
import '../../../core/platform/working_directory_provider.dart';

typedef CodeLabStdioTransportFactory =
    AcpTransport Function(StdioAcpTransportConfig config);

typedef CodeLabWebSocketTransportFactory =
    AcpTransport Function(WebSocketAcpTransportConfig config);

/// Resizable-panel width bounds — CodeLab-specific, not baked into the
/// reusable `acp_ui` layout/handle primitives (see
/// openspec/changes/add-resizable-panels/design.md).
const kSessionsPaneMinWidth = 220.0;
const kSessionsPaneMaxWidth = 480.0;
const kInspectorPaneMinWidth = 260.0;
const kInspectorPaneMaxWidth = 520.0;

enum CodeLabTransportType {
  stdio(label: 'stdio'),
  webSocket(label: 'WebSocket');

  const CodeLabTransportType({required this.label});

  final String label;
}

/// Selects which [Logger] method [CodeLabShellCubit._recordDiagnostic]
/// calls — a local concept, not a UI type (see
/// `replace-debug-log-panel-with-fluent/design.md`, Decision 5: this cubit
/// no longer keeps a displayable diagnostics list of its own).
enum _DiagnosticSeverity { debug, info, warning, error }

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
    required this.currentSessionLabel,
    required this.currentSessionDetail,
    required this.sessions,
    required this.activeSessionId,
    required this.transcriptEntries,
    required this.inspectorEntries,
    required this.viewMode,
    required this.isPromptEnabled,
    required this.isPromptSubmitting,
    required this.canCancel,
    this.isRespondingToApproval = false,
    this.isCommandPaletteOpen = false,
    this.isInspectorVisibleInNarrowLayout = false,
    this.agentCommands = const [],
    this.composerDraft = '',
    this.configOptions = const [],
    this.isRespondingToConfigOption = false,
    this.sessionsPaneWidth = 280,
    this.inspectorPaneWidth = 320,
    this.selectedProjectPath,
    this.runAgentFromProjectDirectory = true,
    this.recentProjects = const [],
    this.currentPlan,
    this.queuedPrompts = const [],
  });

  factory CodeLabShellState.initial({required StdioAcpAgentProfile profile}) =>
      CodeLabShellState(
        connectionStatus: AcpConnectionStatus.disconnected,
        transportType: CodeLabTransportType.stdio,
        stdioProfileName: profile.name,
        stdioCommand: profile.command,
        stdioArgs: profile.args.join(' '),
        stdioEnv: profile.env.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('\n'),
        webSocketEndpoint: 'ws://localhost:8765/acp',
        webSocketToken: '',
        transportLabel: 'stdio',
        profileLabel: profile.name,
        connectionDetail: '${profile.command} ${profile.args.join(' ')}',
        currentSessionLabel: 'No active session',
        currentSessionDetail: 'Create a session after connecting.',
        sessions: const [],
        activeSessionId: null,
        transcriptEntries: const [],
        inspectorEntries: const [
          CodeLabInspectorEntry(
            id: 'inspector-empty',
            category: CodeLabInspectorCategory.protocol,
            title: 'Protocol log',
            summary: 'Connect and start a session to inspect ACP activity.',
          ),
        ],
        viewMode: AcpViewMode.normal,
        isPromptEnabled: true,
        isPromptSubmitting: false,
        canCancel: false,
      );

  final AcpConnectionStatus connectionStatus;
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
  final String currentSessionLabel;
  final String currentSessionDetail;
  final List<AcpSessionListItem> sessions;
  final String? activeSessionId;
  final List<AcpTranscriptEntry> transcriptEntries;
  final List<CodeLabInspectorEntry> inspectorEntries;
  final AcpViewMode viewMode;
  final bool isPromptEnabled;
  final bool isPromptSubmitting;
  final bool canCancel;
  final bool isRespondingToApproval;
  final bool isCommandPaletteOpen;
  final bool isInspectorVisibleInNarrowLayout;

  /// Commands the active agent declared via `SessionUpdate.availableCommandsUpdate`,
  /// replaced wholesale on every new update and cleared on session switch/loss.
  final List<AcpCommandAction> agentCommands;

  /// Text pushed into the prompt composer as a result of selecting an
  /// agent-declared command from the palette (`/{name} `). Consumed by
  /// [AcpPromptComposer.initialPrompt], which only re-applies it when the
  /// value actually changes, so it is safe to leave set between emits.
  final String composerDraft;

  /// The active session's config options (e.g. model/mode selectors the
  /// agent advertised), mapped to the `acp_ui`-facing [AcpConfigOption] and
  /// replaced wholesale on every new `config_option_update` and
  /// cleared/restored on session switch/creation — same "later update
  /// replaces the list" pattern as [agentCommands].
  final List<AcpConfigOption> configOptions;

  /// Guards against a second `session/set_config_option` request firing
  /// while one is already in flight, mirroring [isRespondingToApproval].
  final bool isRespondingToConfigOption;

  /// Widths the user has dragged the sessions/inspector pane dividers to
  /// (desktop layout), clamped to [kSessionsPaneMinWidth]/
  /// [kSessionsPaneMaxWidth] and [kInspectorPaneMinWidth]/
  /// [kInspectorPaneMaxWidth] respectively. Survive widget rebuilds within
  /// this run, not persisted across app restarts (see
  /// add-resizable-panels/design.md Open Questions).
  final double sessionsPaneWidth;
  final double inspectorPaneWidth;

  /// The working directory ("project") selected via "Open Project" —
  /// independent of [transportType], applied to the next session created
  /// (`session/new`'s `cwd`) for both stdio and WebSocket. `null` means no
  /// project has been explicitly selected yet, in which case
  /// [CodeLabShellCubit.createSession] falls back to
  /// `WorkingDirectoryProvider.currentPath`, as it always has. See
  /// add-open-project-picker/design.md, Decision 1.
  final String? selectedProjectPath;

  /// Whether a stdio agent process is spawned with [selectedProjectPath] as
  /// its OS-level working directory (`Process.start(workingDirectory:)`).
  /// Defaults to `true` so the pre-existing implicit "spawn cwd == project"
  /// behavior is preserved without any user action; turning it off decouples
  /// spawn cwd from the selected project without un-selecting the project
  /// itself. Stdio-only — has no effect over WebSocket. See design.md,
  /// Decision 2.
  final bool runAgentFromProjectDirectory;

  /// Recently opened projects, most-recently-opened first — reloaded from
  /// [RecentProjectsStore] on cubit construction and after every
  /// [CodeLabShellCubit.selectProject], so it survives app restarts. See
  /// design.md, Decision 4.
  final List<AcpRecentProject> recentProjects;

  /// The active session's plan, from the latest `SessionUpdate.plan` seen
  /// across its turns (last one wins — see design.md, Decisions), mapped
  /// straight to the `acp_ui`-facing [AcpPlanEntry] (already
  /// presentation-safe, same reasoning as [configOptions]/[agentCommands] —
  /// no separate app-level DTO). `null` means no plan update has arrived
  /// yet for this session, or the user dismissed it via
  /// [CodeLabShellCubit.dismissPlan] — either way, [AcpActivityBar]'s Plan
  /// section is hidden.
  final List<AcpPlanEntry>? currentPlan;

  /// Prompts submitted while the active session couldn't accept a new turn
  /// (a turn is running, or an approval is pending) — held here instead of
  /// being sent, in FIFO order. Never a protocol concept — the agent never
  /// sees an entry until [CodeLabShellCubit] actually dispatches it (either
  /// via auto-drain once the session frees up, or [CodeLabShellCubit.
  /// sendQueuedPromptNow]). Per-session, like [currentPlan] and
  /// `transcriptEntries`: this always mirrors the active session's own
  /// queue (backed by [CodeLabShellCubit]'s private per-session map), so
  /// switching sessions swaps in that session's queue rather than losing or
  /// mixing them — see add-prompt-queue/design.md, Non-Goals and Risks.
  final List<AcpQueuedPrompt> queuedPrompts;

  /// Distinguishes "not passed" from "explicitly set to null" for
  /// [currentPlan] in [copyWith] — an ordinary `T? param` parameter can't
  /// tell those apart (`param ?? this.currentPlan` would keep the old plan
  /// forever), and [CodeLabShellCubit.dismissPlan] and switching to a
  /// session without a plan both need to actually clear it.
  static const Object _unset = Object();

  CodeLabShellState copyWith({
    AcpConnectionStatus? connectionStatus,
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
    String? currentSessionLabel,
    String? currentSessionDetail,
    List<AcpSessionListItem>? sessions,
    String? activeSessionId,
    List<AcpTranscriptEntry>? transcriptEntries,
    List<CodeLabInspectorEntry>? inspectorEntries,
    AcpViewMode? viewMode,
    bool? isPromptEnabled,
    bool? isPromptSubmitting,
    bool? canCancel,
    bool? isRespondingToApproval,
    bool? isCommandPaletteOpen,
    bool? isInspectorVisibleInNarrowLayout,
    List<AcpCommandAction>? agentCommands,
    String? composerDraft,
    List<AcpConfigOption>? configOptions,
    bool? isRespondingToConfigOption,
    double? sessionsPaneWidth,
    double? inspectorPaneWidth,
    String? selectedProjectPath,
    bool? runAgentFromProjectDirectory,
    List<AcpRecentProject>? recentProjects,
    Object? currentPlan = _unset,
    List<AcpQueuedPrompt>? queuedPrompts,
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
      currentSessionLabel: currentSessionLabel ?? this.currentSessionLabel,
      currentSessionDetail: currentSessionDetail ?? this.currentSessionDetail,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      transcriptEntries: transcriptEntries ?? this.transcriptEntries,
      inspectorEntries: inspectorEntries ?? this.inspectorEntries,
      viewMode: viewMode ?? this.viewMode,
      isPromptEnabled: isPromptEnabled ?? this.isPromptEnabled,
      isPromptSubmitting: isPromptSubmitting ?? this.isPromptSubmitting,
      canCancel: canCancel ?? this.canCancel,
      isRespondingToApproval:
          isRespondingToApproval ?? this.isRespondingToApproval,
      isCommandPaletteOpen: isCommandPaletteOpen ?? this.isCommandPaletteOpen,
      isInspectorVisibleInNarrowLayout:
          isInspectorVisibleInNarrowLayout ??
          this.isInspectorVisibleInNarrowLayout,
      agentCommands: agentCommands ?? this.agentCommands,
      composerDraft: composerDraft ?? this.composerDraft,
      configOptions: configOptions ?? this.configOptions,
      isRespondingToConfigOption:
          isRespondingToConfigOption ?? this.isRespondingToConfigOption,
      sessionsPaneWidth: sessionsPaneWidth ?? this.sessionsPaneWidth,
      inspectorPaneWidth: inspectorPaneWidth ?? this.inspectorPaneWidth,
      selectedProjectPath: selectedProjectPath ?? this.selectedProjectPath,
      runAgentFromProjectDirectory:
          runAgentFromProjectDirectory ?? this.runAgentFromProjectDirectory,
      recentProjects: recentProjects ?? this.recentProjects,
      currentPlan: identical(currentPlan, _unset)
          ? this.currentPlan
          : currentPlan as List<AcpPlanEntry>?,
      queuedPrompts: queuedPrompts ?? this.queuedPrompts,
    );
  }

  CodeLabShellState withTransportProjection({
    CodeLabTransportType? transportType,
    String? stdioProfileName,
    String? stdioCommand,
    String? stdioArgs,
    String? stdioEnv,
    String? webSocketEndpoint,
    String? webSocketToken,
  }) {
    final next = copyWith(
      transportType: transportType,
      stdioProfileName: stdioProfileName,
      stdioCommand: stdioCommand,
      stdioArgs: stdioArgs,
      stdioEnv: stdioEnv,
      webSocketEndpoint: webSocketEndpoint,
      webSocketToken: webSocketToken,
    );

    return next.copyWith(
      transportLabel: next.transportType.label,
      profileLabel: next.selectedProfileLabel,
      connectionDetail: next.selectedConnectionDetail,
    );
  }

  /// The full command palette list: the six client-native commands followed
  /// by whatever the active agent has declared, in that order — the
  /// client-native set is never removed or replaced by agent commands.
  List<AcpCommandAction> get paletteActions => [
    ...AcpCommandAction.defaults,
    ...agentCommands,
  ];

  String get selectedProfileLabel => switch (transportType) {
    CodeLabTransportType.stdio => stdioProfileName,
    CodeLabTransportType.webSocket => 'Remote ACP Agent',
  };

  String get selectedConnectionDetail => switch (transportType) {
    CodeLabTransportType.stdio => [
      stdioCommand,
      stdioArgs,
    ].where((part) => part.trim().isNotEmpty).join(' '),
    CodeLabTransportType.webSocket => webSocketEndpoint,
  };
}

enum CodeLabInspectorCategory { approval, toolCall, protocol, diagnostic }

final class CodeLabInspectorEntry {
  const CodeLabInspectorEntry({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    this.risk,
    this.status,
    this.details = const [],
    this.rawInput,
    this.rawOutput,
  });

  final String id;
  final CodeLabInspectorCategory category;
  final String title;
  final String summary;
  final String? risk;
  final String? status;
  final List<CodeLabInspectorDetail> details;
  final String? rawInput;
  final String? rawOutput;
}

final class CodeLabInspectorDetail {
  const CodeLabInspectorDetail({required this.label, required this.value});

  final String label;
  final String value;
}

/// Фасад рабочего места CodeLab над `ClientWorkspace` из `acp_client_kit`.
///
/// Почему: логика клиента переносится из этого Cubit в kit по частям
/// (change `extract-acp-client-kit`, design D12), а виджеты, интеграционные
/// и характеризационные тесты читают прежний [CodeLabShellState]. Фасад
/// сохраняет эту поверхность на время переноса.
///
/// Для чего: подключение, переподключение, создание и выбор сессии идут
/// через [ClientWorkspace]; промпты, отмена, одобрения и опции — пока через
/// use case-ы `acp_client_core`, до своих итераций.
///
/// Как использовать: граф cherrypick (`app_scope.dart`) передаёт
/// [workspace] и [secrets] — тот же `InMemorySecretSource`, что у резолвера
/// WebSocket. Без них Cubit строит рабочее пространство сам поверх
/// [application] и фабрик транспорта: так его по-прежнему создают тесты
/// `widget_test.dart`. Параметры `createSessionUseCase` и
/// `reconnectUseCase` не используются после переноса подключения и сессий в
/// kit; они остаются, пока эти тесты создают Cubit напрямую, и удаляются
/// вместе с фасадом после этапа 9 (`09-10`, «Что остаётся неизменным»).
final class CodeLabShellCubit extends Cubit<CodeLabShellState> {
  CodeLabShellCubit({
    required StdioAcpAgentProfile profile,
    required AcpClientApplication application,
    CreateSession? createSessionUseCase,
    required SendPrompt sendPromptUseCase,
    required CancelTurn cancelTurnUseCase,
    Reconnect? reconnectUseCase,
    required RespondToPermission respondToPermissionUseCase,
    required SetSessionConfigOption setSessionConfigOptionUseCase,
    CodeLabStdioTransportFactory? stdioTransportFactory,
    CodeLabWebSocketTransportFactory? webSocketTransportFactory,
    ClientWorkspace? workspace,
    InMemorySecretSource? secrets,
    required WorkingDirectoryProvider workingDirectoryProvider,
    required ProjectFolderPicker projectFolderPicker,
    required RecentProjectsStore recentProjectsStore,
    Logger? logger,
  }) : this._(
         profile: profile,
         application: application,
         sendPromptUseCase: sendPromptUseCase,
         cancelTurnUseCase: cancelTurnUseCase,
         respondToPermissionUseCase: respondToPermissionUseCase,
         setSessionConfigOptionUseCase: setSessionConfigOptionUseCase,
         secrets: secrets ?? InMemorySecretSource(),
         workspace: workspace,
         stdioTransportFactory: stdioTransportFactory,
         webSocketTransportFactory: webSocketTransportFactory,
         workingDirectoryProvider: workingDirectoryProvider,
         projectFolderPicker: projectFolderPicker,
         recentProjectsStore: recentProjectsStore,
         logger: logger,
       );

  CodeLabShellCubit._({
    required StdioAcpAgentProfile profile,
    required AcpClientApplication application,
    required SendPrompt sendPromptUseCase,
    required CancelTurn cancelTurnUseCase,
    required RespondToPermission respondToPermissionUseCase,
    required SetSessionConfigOption setSessionConfigOptionUseCase,
    required InMemorySecretSource secrets,
    required ClientWorkspace? workspace,
    required CodeLabStdioTransportFactory? stdioTransportFactory,
    required CodeLabWebSocketTransportFactory? webSocketTransportFactory,
    required WorkingDirectoryProvider workingDirectoryProvider,
    required ProjectFolderPicker projectFolderPicker,
    required RecentProjectsStore recentProjectsStore,
    Logger? logger,
  }) : _application = application,
       _sendPromptUseCase = sendPromptUseCase,
       _cancelTurnUseCase = cancelTurnUseCase,
       _respondToPermissionUseCase = respondToPermissionUseCase,
       _setSessionConfigOptionUseCase = setSessionConfigOptionUseCase,
       _secrets = secrets,
       _ownsWorkspace = workspace == null,
       _workspace =
           workspace ??
           ClientWorkspace(
             backend: AcpClientBackend(application),
             resolvers: [
               ConfigTransportResolver(
                 stdio: stdioTransportFactory,
                 webSocket: webSocketTransportFactory,
                 secrets: secrets,
               ),
             ],
           ),
       _workingDirectoryProvider = workingDirectoryProvider,
       _projectFolderPicker = projectFolderPicker,
       _recentProjectsStore = recentProjectsStore,
       _logger = (logger ?? StructuredLogLogger('codelab_app.shell')).bind({
         logCategoryKey: applicationLogCategory,
         logComponentKey: presentationComponent,
       }),
       super(CodeLabShellState.initial(profile: profile)) {
    _sessionSubscription = _application.sessionChanges.listen(
      _handleSessionChange,
    );
    _workspaceSubscription = _workspace.state.listen(_handleWorkspaceChange);
    unawaited(_loadRecentProjects());
  }

  final AcpClientApplication _application;

  /// Monotonic, never reused within this cubit's lifetime — unlike an
  /// index into [CodeLabShellState.queuedPrompts], safe to keep identifying
  /// a queued prompt across edits/deletes that shift other items' indices.
  int _nextQueuedPromptId = 0;

  /// Per-session backing store for [CodeLabShellState.queuedPrompts] —
  /// keyed by session id, never sent to the agent (see add-prompt-queue/
  /// design.md, Non-Goals: queued prompts belong to the session that was
  /// active when they were queued, and stay out of sight — not lost —
  /// until that session is active again). [CodeLabShellState.queuedPrompts]
  /// always mirrors `this[state.activeSessionId]`; [selectSession] and
  /// [createSession] re-derive it the same way they already do for
  /// [CodeLabShellState.currentPlan]/`transcriptEntries`.
  final Map<String, List<AcpQueuedPrompt>> _queuedPromptsBySession = {};
  final SendPrompt _sendPromptUseCase;
  final CancelTurn _cancelTurnUseCase;
  final RespondToPermission _respondToPermissionUseCase;
  final SetSessionConfigOption _setSessionConfigOptionUseCase;
  final ClientWorkspace _workspace;

  /// Рабочее пространство создал сам Cubit (без графа cherrypick) — тогда он
  /// и закрывает его в [close].
  final bool _ownsWorkspace;

  /// Значение токена WebSocket из формы; профиль ссылается на него по
  /// [_webSocketTokenRef] (design D8).
  final InMemorySecretSource _secrets;
  final WorkingDirectoryProvider _workingDirectoryProvider;
  final ProjectFolderPicker _projectFolderPicker;
  final RecentProjectsStore _recentProjectsStore;
  final Logger _logger;
  final _redactor = const SecretRedactor();

  /// Подписка на изменения сессий ядра клиента. Открывается после
  /// подписки [_workspace]: широковещательный синхронный поток доставляет
  /// события в порядке подписки, поэтому `SessionView` kit к вызову
  /// [_handleSessionChange] уже обновлён.
  late final StreamSubscription<AcpSession> _sessionSubscription;
  late final StreamSubscription<WorkspaceState> _workspaceSubscription;

  /// Ссылка на токен WebSocket в [_secrets].
  static const _webSocketTokenRef = 'codelab_app.websocket.token';

  void selectTransport(CodeLabTransportType transportType) {
    emit(state.withTransportProjection(transportType: transportType));
  }

  void updateStdioProfileName(String value) {
    emit(state.withTransportProjection(stdioProfileName: value));
  }

  void updateStdioCommand(String value) {
    emit(state.withTransportProjection(stdioCommand: value));
  }

  void updateStdioArgs(String value) {
    emit(state.withTransportProjection(stdioArgs: value));
  }

  void updateStdioEnv(String value) {
    emit(state.withTransportProjection(stdioEnv: value));
  }

  void updateWebSocketEndpoint(String value) {
    emit(state.withTransportProjection(webSocketEndpoint: value));
  }

  void updateWebSocketToken(String value) {
    emit(state.withTransportProjection(webSocketToken: value));
  }

  /// Selects [path] as the current project — applied to the next session
  /// created, independent of [CodeLabShellState.transportType] (see
  /// add-open-project-picker/design.md, Decision 1). Also records it via
  /// [RecentProjectsStore] and refreshes [CodeLabShellState.recentProjects],
  /// so the "Open Project" picker reflects the new entry immediately rather
  /// than waiting for the next app start.
  Future<void> selectProject(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }

    emit(state.copyWith(selectedProjectPath: trimmed));
    _recordDiagnostic('Selected project: $trimmed.', source: 'project');

    try {
      await _recentProjectsStore.record(trimmed);
      if (isClosed) return;
      await _loadRecentProjects();
    } on Object catch (error) {
      if (isClosed) return;
      _recordDiagnostic(
        'Failed to record recent project: $error',
        severity: _DiagnosticSeverity.warning,
        source: 'project',
      );
    }
  }

  /// Opens the native OS folder-selection dialog via [ProjectFolderPicker]
  /// and, if the user picks a folder, selects it the same way
  /// [selectProject] does. Does nothing if the dialog is dismissed without a
  /// selection.
  Future<void> browseForProject() async {
    final path = await _projectFolderPicker.pickFolder(
      initialDirectory: state.selectedProjectPath,
    );
    if (isClosed || path == null) {
      return;
    }
    await selectProject(path);
  }

  /// Stdio-only: whether the agent process is spawned with the selected
  /// project's directory as its OS-level working directory. See
  /// [CodeLabShellState.runAgentFromProjectDirectory].
  void toggleRunAgentFromProjectDirectory(bool value) {
    emit(state.copyWith(runAgentFromProjectDirectory: value));
  }

  Future<void> connect() async {
    final isWebSocket = state.transportType == CodeLabTransportType.webSocket;
    final profile = _profileFromState();
    if (profile == null) {
      _recordDiagnostic(
        isWebSocket
            ? 'WebSocket endpoint is required before connecting.'
            : 'Stdio command is required before connecting.',
        severity: _DiagnosticSeverity.error,
        source: 'transport',
      );
      emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
      return;
    }

    emit(state.copyWith(connectionStatus: AcpConnectionStatus.connecting));
    _recordDiagnostic(
      isWebSocket
          ? 'Connecting WebSocket ACP agent: ${state.selectedConnectionDetail}.'
          : 'Starting stdio ACP agent: ${state.selectedConnectionDetail}.',
      source: 'transport',
    );

    try {
      await _workspace.connect(profile, projectDirectory: _selectedProjectPath);
      emit(
        state.copyWith(
          connectionStatus: _connectionStatusFor(_workspace.current.connection),
        ),
      );
      _recordDiagnostic(
        isWebSocket
            ? 'WebSocket ACP agent connected: ${state.selectedConnectionDetail}.'
            : 'Stdio ACP agent started: ${state.selectedConnectionDetail}.',
        source: 'transport',
      );
    } on UnsupportedProtocolVersionException catch (error) {
      emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
      _recordDiagnostic(
        'Incompatible ACP agent: ${error.message}',
        severity: _DiagnosticSeverity.error,
        source: 'transport',
      );
    } on Object catch (error) {
      emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
      _recordDiagnostic(
        isWebSocket
            ? 'Failed to connect WebSocket ACP agent: $error'
            : 'Failed to start stdio ACP agent: $error',
        severity: _DiagnosticSeverity.error,
        source: 'transport',
      );
    }
  }

  /// Одна попытка переподключения через kit с профилем из текущей формы:
  /// пользователь мог изменить команду, адрес или проект после [connect]
  /// (design D4).
  Future<void> reconnect() async {
    final isWebSocket = state.transportType == CodeLabTransportType.webSocket;
    final profile = _profileFromState();
    if (profile == null) {
      _recordDiagnostic(
        isWebSocket
            ? 'WebSocket endpoint is required before reconnecting.'
            : 'Stdio command is required before reconnecting.',
        severity: _DiagnosticSeverity.error,
        source: 'transport',
      );
      emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
      return;
    }

    emit(state.copyWith(connectionStatus: AcpConnectionStatus.reconnecting));
    _recordDiagnostic(
      isWebSocket
          ? 'Reconnecting WebSocket ACP agent: ${state.selectedConnectionDetail}.'
          : 'Reconnecting stdio ACP agent: ${state.selectedConnectionDetail}.',
      source: 'transport',
    );

    try {
      await _workspace.reconnect(
        profile: profile,
        projectDirectory: _selectedProjectPath,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          connectionStatus: _connectionStatusFor(_workspace.current.connection),
        ),
      );
      _recordDiagnostic(
        isWebSocket
            ? 'WebSocket ACP agent reconnected: ${state.selectedConnectionDetail}.'
            : 'Stdio ACP agent reconnected: ${state.selectedConnectionDetail}.',
        source: 'transport',
      );
    } on Object catch (error) {
      if (isClosed) return;
      emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
      _recordDiagnostic(
        isWebSocket
            ? 'Failed to reconnect WebSocket ACP agent: ${_errorMessage(error)}'
            : 'Failed to reconnect stdio ACP agent: ${_errorMessage(error)}',
        severity: _DiagnosticSeverity.error,
        source: 'transport',
      );
    }
  }

  /// Commits a new sessions pane width (desktop layout resize), clamped to
  /// [kSessionsPaneMinWidth]/[kSessionsPaneMaxWidth]. Callers pass the final
  /// width once a resize drag ends — see `AcpWorkbenchLayout`'s
  /// `onSessionsPaneResizeEnd`.
  void resizeSessionsPane(double width) {
    emit(
      state.copyWith(
        sessionsPaneWidth: width.clamp(
          kSessionsPaneMinWidth,
          kSessionsPaneMaxWidth,
        ),
      ),
    );
  }

  /// Same as [resizeSessionsPane] for the inspector pane.
  void resizeInspectorPane(double width) {
    emit(
      state.copyWith(
        inspectorPaneWidth: width.clamp(
          kInspectorPaneMinWidth,
          kInspectorPaneMaxWidth,
        ),
      ),
    );
  }

  Future<void> createSession() async {
    if (state.connectionStatus != AcpConnectionStatus.connected) {
      _recordDiagnostic(
        'Connect an ACP agent before creating a session.',
        severity: _DiagnosticSeverity.warning,
        source: 'session',
      );
      return;
    }

    _recordDiagnostic('Creating ACP session.', source: 'session');

    final AcpSession? session;
    try {
      final handle = await _workspace.newSession(cwd: _selectedProjectPath);
      if (isClosed) return;
      session = _application.sessionById(handle.id);
    } on Object catch (error) {
      if (isClosed) return;
      _recordDiagnostic(
        'Failed to create ACP session: ${_errorMessage(error)}',
        severity: _DiagnosticSeverity.error,
        source: 'session',
      );
      return;
    }
    if (session == null) {
      return;
    }

    final sessionItem = _sessionListItem(session);
    final otherSessions = state.sessions
        .where((item) => item.id != sessionItem.id)
        .toList(growable: false);
    emit(
      state.copyWith(
        sessions: [sessionItem, ...otherSessions],
        activeSessionId: sessionItem.id,
        currentSessionLabel: sessionItem.title,
        currentSessionDetail: sessionItem.subtitle ?? session.id.value,
        transcriptEntries: const [],
        inspectorEntries: _inspectorEntriesForSession(session),
        agentCommands: _agentCommandsFor(session),
        configOptions: _configOptionsFor(session),
        currentPlan: _currentPlanForSession(session),
        queuedPrompts: _queueFor(sessionItem.id),
        isPromptSubmitting: false,
        canCancel: false,
      ),
    );
    _recordDiagnostic(
      'Created ACP session ${session.id.value}.',
      source: 'session',
    );
  }

  /// Switches the active session and reloads all of its per-session state
  /// (transcript, inspector, pending approval, agent commands,
  /// `isPromptSubmitting`/`canCancel`) from the application's live
  /// snapshot — without this, the previously active session's transcript/
  /// inspector/approval/busy state would remain visible until the newly
  /// selected session happened to emit its own `session/update`.
  void selectSession(String sessionId) {
    _workspace.activate(SessionId(sessionId));
    final session = _application.sessionById(SessionId(sessionId));
    if (session == null) {
      final selected = state.sessions
          .where((item) => item.id == sessionId)
          .firstOrNull;
      emit(
        state.copyWith(
          activeSessionId: sessionId,
          currentSessionLabel: selected?.title ?? 'Session $sessionId',
          currentSessionDetail: selected?.subtitle ?? sessionId,
          transcriptEntries: const [],
          inspectorEntries: const [],
          agentCommands: const [],
          configOptions: const [],
          currentPlan: null,
          queuedPrompts: _queueFor(sessionId),
          isPromptSubmitting: false,
          canCancel: false,
        ),
      );
      return;
    }

    final sessionItem = _sessionListItem(session);
    emit(
      state.copyWith(
        activeSessionId: sessionItem.id,
        currentSessionLabel: sessionItem.title,
        currentSessionDetail: sessionItem.subtitle ?? session.id.value,
        transcriptEntries: _transcriptEntriesForSession(session),
        inspectorEntries: _inspectorEntriesForSession(session),
        agentCommands: _agentCommandsFor(session),
        configOptions: _configOptionsFor(session),
        currentPlan: _currentPlanForSession(session),
        queuedPrompts: _queueFor(sessionItem.id),
        isPromptSubmitting: _isBusyLifecycleStatus(session.status),
        canCancel: _isCancellableLifecycleStatus(session.status),
      ),
    );
  }

  Future<void> submitPrompt(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty) {
      return;
    }

    final sessionId = state.activeSessionId;
    if (sessionId == null) {
      _recordDiagnostic(
        'Create or select a session before sending a prompt.',
        severity: _DiagnosticSeverity.warning,
        source: 'prompt',
      );
      return;
    }

    // Checked *before* attempting to send, not caught as a failure after —
    // `SessionStateMachine._startTurn` would reject this the same way, but
    // queuing here avoids the round trip and the "Prompt failed" diagnostic
    // for what is an expected, non-exceptional case. See
    // add-prompt-queue/design.md, Decisions.
    if (_isSessionBusy(sessionId)) {
      _setQueueFor(sessionId, [
        ..._queueFor(sessionId),
        AcpQueuedPrompt(id: _newQueuedPromptId(), content: text),
      ]);
      return;
    }

    await _dispatchPrompt(sessionId: sessionId, text: text);
  }

  /// The actual `session/prompt` round trip, shared by [submitPrompt]'s
  /// direct-send path, [sendQueuedPromptNow], and the queue's auto-drain —
  /// all three reach a real send exactly the way [submitPrompt] always has.
  ///
  /// Deliberately emits nothing itself for `transcriptEntries`,
  /// `inspectorEntries`, `isPromptSubmitting` or `canCancel`: the domain
  /// stores the running turn synchronously, before this `await` yields
  /// (`AcpClientApplication.sendPrompt`'s `_storeSession(runningSession)`),
  /// so `_handleSessionChange` already picks up the busy status, the
  /// reconstructed user entry (from `turn.prompt`) and every subsequent
  /// streamed/terminal update on its own `sessionChanges` events — for
  /// *whichever* session `sessionId` is, not necessarily the one still
  /// active by the time this future resolves. Emitting presentation state
  /// here directly would risk overwriting a *different*, now-active
  /// session's view — see add-multi-session-concurrency/design.md,
  /// Decisions.
  Future<void> _dispatchPrompt({
    required String sessionId,
    required String text,
  }) async {
    final result = await _sendPromptUseCase(
      SendPromptCommand(
        sessionId: SessionId(sessionId),
        prompt: [ContentBlock.text(text: text)],
      ),
    ).run();
    if (isClosed) return;

    result.match(
      (failure) {
        _recordDiagnostic(
          'Failed to send prompt: ${_failureMessage(failure)}',
          severity: _DiagnosticSeverity.error,
          source: 'prompt',
        );
      },
      (turn) {
        _recordDiagnostic(
          'Prompt completed with stopReason ${turn.stopReason?.name ?? 'unknown'}.',
          source: 'prompt',
        );
      },
    );
    await _drainQueueIfFree(sessionId);
  }

  /// Reads the queue belonging to [sessionId] — never `null`, an unseen
  /// session simply has no queued prompts yet.
  List<AcpQueuedPrompt> _queueFor(String sessionId) =>
      _queuedPromptsBySession[sessionId] ?? const [];

  /// Updates the queue belonging to [sessionId] and, only if it is the
  /// currently active session, mirrors it into
  /// [CodeLabShellState.queuedPrompts] so the UI reflects it immediately.
  /// A background session's queue is updated silently — see
  /// [_queuedPromptsBySession].
  void _setQueueFor(String sessionId, List<AcpQueuedPrompt> queue) {
    _queuedPromptsBySession[sessionId] = queue;
    if (state.activeSessionId == sessionId) {
      emit(state.copyWith(queuedPrompts: queue));
    }
  }

  /// Removes [id] from the active session's queue and places its text back
  /// into the prompt composer (via [CodeLabShellState.composerDraft]) for
  /// editing. Removed from the queue immediately, not on next send, so the
  /// text is never live in both places (queue and composer) at once — see
  /// add-prompt-queue/design.md, Decisions.
  void editQueuedPrompt(String id) {
    final sessionId = state.activeSessionId;
    if (sessionId == null) {
      return;
    }
    final queue = _queueFor(sessionId);
    final index = queue.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    final prompt = queue[index];
    final updated = [...queue]..removeAt(index);
    _queuedPromptsBySession[sessionId] = updated;
    emit(state.copyWith(queuedPrompts: updated, composerDraft: prompt.content));
  }

  void deleteQueuedPrompt(String id) {
    final sessionId = state.activeSessionId;
    if (sessionId == null) {
      return;
    }
    _setQueueFor(
      sessionId,
      _queueFor(
        sessionId,
      ).where((item) => item.id != id).toList(growable: false),
    );
  }

  /// Attempts to send [id] immediately, out of FIFO order. If the session
  /// is still busy at this exact instant — a race, e.g. an approval
  /// appeared between the button rendering and this call — [id] is left
  /// exactly where it already was in the queue and nothing else happens:
  /// an expected race, not an error (see add-prompt-queue/design.md,
  /// Decisions).
  Future<void> sendQueuedPromptNow(String id) async {
    final sessionId = state.activeSessionId;
    if (sessionId == null || _isSessionBusy(sessionId)) {
      return;
    }
    final queue = _queueFor(sessionId);
    final index = queue.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    final prompt = queue[index];
    _setQueueFor(sessionId, [...queue]..removeAt(index));
    await _dispatchPrompt(sessionId: sessionId, text: prompt.content);
  }

  void clearQueuedPrompts() {
    final sessionId = state.activeSessionId;
    if (sessionId == null) {
      return;
    }
    _setQueueFor(sessionId, const []);
  }

  /// Sends the oldest prompt queued for [sessionId] once *that session* is
  /// genuinely free — called after every point where [isPromptSubmitting]
  /// or [sessionId]'s own pending approval could have just cleared
  /// ([_dispatchPrompt], [cancelTurn], [respondToApproval]), always with
  /// the session the completed turn actually belonged to (not necessarily
  /// [CodeLabShellState.activeSessionId] any more, if the user switched
  /// sessions while it was in flight). Re-checks the full condition (not
  /// just the one signal that changed) each time, per add-prompt-queue/
  /// design.md, Decisions — recurses into [_dispatchPrompt] on success, so
  /// a free session drains the whole queue one send at a time, not just
  /// the first entry.
  Future<void> _drainQueueIfFree(String sessionId) async {
    if (_isSessionBusy(sessionId)) {
      return;
    }
    final queue = _queueFor(sessionId);
    if (queue.isEmpty) {
      return;
    }
    final next = queue.first;
    _setQueueFor(sessionId, queue.skip(1).toList());
    await _dispatchPrompt(sessionId: sessionId, text: next.content);
  }

  /// Whether [sessionId] can currently accept a new prompt turn — a pure
  /// read of that session's own domain status
  /// (`_application.sessionById(sessionId)?.status`), independent of which
  /// session is active or of any other session's state. `runningTurn`/
  /// `awaitingApproval`/`cancellingTurn` are busy (a cancelled turn holds the
  /// session until the agent answers its `session/prompt`, see
  /// fix-prompt-cancel-tool-calls/design.md, D2); `idle`/`active`/`failed`
  /// (including an unknown session) are free. This is also the single source
  /// [CodeLabShellState.isPromptSubmitting]/[CodeLabShellState.canCancel]
  /// for the active session are derived from, in [_handleSessionChange] and
  /// [selectSession] — see add-multi-session-concurrency/design.md,
  /// Decisions.
  bool _isSessionBusy(String sessionId) => _isBusyLifecycleStatus(
    _application.sessionById(SessionId(sessionId))?.status,
  );

  bool _isBusyLifecycleStatus(SessionLifecycleStatus? status) =>
      _isCancellableLifecycleStatus(status) ||
      status == SessionLifecycleStatus.cancellingTurn;

  /// Busy and not already cancelling: the cancel has been sent once.
  bool _isCancellableLifecycleStatus(SessionLifecycleStatus? status) =>
      status == SessionLifecycleStatus.runningTurn ||
      status == SessionLifecycleStatus.awaitingApproval;

  String _newQueuedPromptId() => 'queued-${_nextQueuedPromptId++}';

  Future<void> cancelTurn() async {
    final sessionId = state.activeSessionId;
    if (sessionId == null) {
      _recordDiagnostic(
        'Select a session before cancelling a prompt turn.',
        severity: _DiagnosticSeverity.warning,
        source: 'prompt',
      );
      return;
    }

    final result = await _cancelTurnUseCase(
      CancelTurnCommand(sessionId: SessionId(sessionId)),
    ).run();
    if (isClosed) return;

    // As in `_dispatchPrompt`, `isPromptSubmitting`/`canCancel`/
    // `inspectorEntries` are not touched here — the cancellation itself
    // updates the session's domain status, which `_handleSessionChange`
    // picks up on the resulting `sessionChanges` event for whichever
    // session this is, active or not.
    result.match(
      (failure) => _recordDiagnostic(
        'Failed to cancel prompt turn: ${_failureMessage(failure)}',
        severity: _DiagnosticSeverity.error,
        source: 'prompt',
      ),
      (turn) => _recordDiagnostic(
        'Cancelled prompt turn ${turn.id.value}.',
        source: 'prompt',
      ),
    );
    await _drainQueueIfFree(sessionId);
  }

  /// Responds to the approval identified by [approvalId] (in [sessionId]) by
  /// selecting [optionId] (one of the agent-supplied options, including
  /// reject-kind options — ACP has no separate "reject" verb, rejecting is
  /// just selecting a reject_once / reject_always option). Callers pass the
  /// identity of the specific approval they are resolving — each transcript
  /// entry's own `ApprovalRequest`, not a single global "current" approval —
  /// so a stale/late tap can never resolve a different tool call than the
  /// one the user actually acted on; see PERM-003 in
  /// docs/architecture/permissions.md.
  Future<void> respondToApproval({
    required ApprovalRequestId approvalId,
    required SessionId sessionId,
    required String optionId,
  }) async {
    if (state.isRespondingToApproval) {
      return;
    }

    emit(state.copyWith(isRespondingToApproval: true));
    final result = await _respondToPermissionUseCase(
      RespondToPermissionCommand.selected(
        sessionId: sessionId,
        approvalId: approvalId,
        optionId: PermissionOptionId(optionId),
      ),
    ).run();
    if (isClosed) return;

    // Do not touch `transcriptEntries` here in either branch: the resolution
    // (or the fact that it is still pending, e.g. after a stale/failed
    // response) is always re-derived from the next `sessionChanges` event in
    // `_handleSessionChange`, which stays the single source of truth.
    result.match(
      (failure) {
        emit(state.copyWith(isRespondingToApproval: false));
        _recordDiagnostic(
          'Failed to respond to approval request: ${_failureMessage(failure)}',
          severity: _DiagnosticSeverity.error,
          source: 'approval',
        );
      },
      (resolved) {
        emit(state.copyWith(isRespondingToApproval: false));
        _recordDiagnostic(
          'Resolved approval ${resolved.id.value} (${resolved.status.name}).',
          source: 'approval',
        );
      },
    );
    await _drainQueueIfFree(sessionId.value);
  }

  /// Sends the user's chosen [value] for [configId] to the agent via
  /// `session/set_config_option`. Guards against a second request firing
  /// for the same chip while one is already in flight — mirrors
  /// [respondToApproval]'s guard/re-derive pattern: the displayed
  /// `configOptions` is always re-derived from the next `sessionChanges`
  /// event in [_handleSessionChange], never set optimistically here.
  Future<void> setSessionConfigOption(String configId, String value) async {
    final sessionId = state.activeSessionId;
    if (sessionId == null || state.isRespondingToConfigOption) {
      return;
    }

    emit(state.copyWith(isRespondingToConfigOption: true));
    final result = await _setSessionConfigOptionUseCase(
      SetSessionConfigOptionCommand(
        sessionId: SessionId(sessionId),
        configId: SessionConfigId(configId),
        value: SessionConfigValueId(value),
      ),
    ).run();
    if (isClosed) return;

    result.match(
      (failure) {
        emit(state.copyWith(isRespondingToConfigOption: false));
        _recordDiagnostic(
          'Failed to set config option $configId: ${_failureMessage(failure)}',
          severity: _DiagnosticSeverity.error,
          source: 'session',
        );
      },
      (_) {
        emit(state.copyWith(isRespondingToConfigOption: false));
        _recordDiagnostic(
          'Set config option $configId to $value.',
          source: 'session',
        );
      },
    );
  }

  void openCommandPalette() => emit(state.copyWith(isCommandPaletteOpen: true));

  void closeCommandPalette() =>
      emit(state.copyWith(isCommandPaletteOpen: false));

  /// Dispatches a selected [AcpCommandAction] the same way regardless of
  /// which trigger opened the palette (`Ctrl/Cmd+K` or the inline `/`
  /// trigger in the composer) — see the "same handler" decision in
  /// wire-command-palette/design.md.
  ///
  /// Unavailable client-native commands (`/plan`, `/permissions`,
  /// `/compact`) leave the palette open and do nothing, so the user is
  /// never told an action completed when it did not. Agent-declared
  /// commands are never invoked as a protocol method — the caller is
  /// responsible for inserting `/{name} ` into the composer before calling
  /// this method; here they only close the palette.
  void selectCommand(AcpCommandAction action) {
    if (!action.isAvailable) {
      return;
    }

    switch (action.id) {
      case 'new':
        unawaited(createSession());
      case 'reconnect':
        unawaited(reconnect());
      case 'logs':
        emit(state.copyWith(isInspectorVisibleInNarrowLayout: true));
      default:
        break;
    }

    closeCommandPalette();
  }

  /// Handles selection of an agent-declared [AcpCommandAction]. Unlike
  /// [selectCommand], this never calls a use case: `AvailableCommand` has no
  /// "invoke" verb in ACP, so selecting one inserts `/{name} ` into the
  /// prompt composer (via [CodeLabShellState.composerDraft]) for the user to
  /// complete and submit as an ordinary prompt.
  void insertAgentCommand(AcpCommandAction action) {
    emit(state.copyWith(composerDraft: '${action.slashCommand} '));
    closeCommandPalette();
  }

  /// Clears the plan summary/checklist for the active session — a
  /// client-side "hide it" (`AcpActivityBar`'s Plan section, "✕ Clear"),
  /// not a protocol operation, so nothing is sent to the agent. A later
  /// `SessionUpdate.plan` for this session repopulates
  /// [CodeLabShellState.currentPlan] normally via [_handleSessionChange] —
  /// dismissing does not suppress future updates. See
  /// add-plan-progress-checklist/design.md, Decisions.
  void dismissPlan() {
    emit(state.copyWith(currentPlan: null));
  }

  @override
  Future<void> close() async {
    await _sessionSubscription.cancel();
    await _workspaceSubscription.cancel();
    if (_ownsWorkspace) {
      await _workspace.dispose();
    }
    return super.close();
  }

  /// Records a diagnostic through the structured [Logger] — the in-app log
  /// viewer's [LogBuffer] and console/file sinks are its only observers
  /// (`replace-debug-log-panel-with-fluent/design.md`, Decision 5); this
  /// cubit keeps no diagnostics list of its own. [source] identifies the
  /// originating area (`transport`, `session`, `project`, ...) under the
  /// `source` context key.
  void _recordDiagnostic(
    String message, {
    _DiagnosticSeverity severity = _DiagnosticSeverity.info,
    required String source,
  }) {
    final redactedMessage = _redactor.redactText(message);
    final logContext = {'source': source};
    switch (severity) {
      case _DiagnosticSeverity.debug:
        _logger.debug(redactedMessage, context: logContext);
      case _DiagnosticSeverity.info:
        _logger.info(redactedMessage, context: logContext);
      case _DiagnosticSeverity.warning:
        _logger.warning(redactedMessage, context: logContext);
      case _DiagnosticSeverity.error:
        _logger.error(redactedMessage, context: logContext);
    }
  }

  /// Reloads [CodeLabShellState.recentProjects] from [RecentProjectsStore],
  /// sorted most-recently-opened first — ordering is an application-layer
  /// concern (the store's own contract makes no ordering guarantee), so it
  /// is applied here, once, right before mapping to the `acp_ui`-facing
  /// [AcpRecentProject]. Called once at construction (so recents from a
  /// prior run are visible before the user ever opens the picker) and again
  /// after every [selectProject]. Failures are non-fatal — surfaced as a
  /// diagnostic, leaving the previous [CodeLabShellState.recentProjects] in
  /// place, since a corrupt/unavailable store must not block using the app.
  Future<void> _loadRecentProjects() async {
    try {
      final recents = await _recentProjectsStore.load();
      if (isClosed) return;
      final sorted = recents.toList()
        ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      emit(
        state.copyWith(
          recentProjects: sorted
              .map((entry) => AcpRecentProject(path: entry.path))
              .toList(growable: false),
        ),
      );
    } on Object catch (error) {
      if (isClosed) return;
      _recordDiagnostic(
        'Failed to load recent projects: $error',
        severity: _DiagnosticSeverity.warning,
        source: 'project',
      );
    }
  }

  /// Handles a `sessionChanges` event for *any* session, active or in the
  /// background. [state.sessions] (which feeds the sidebar's live status
  /// badge) is always refreshed for the changed session — a background
  /// session's turn progressing must not require switching to it first, see
  /// add-multi-session-concurrency/design.md, Decisions. Everything else
  /// (transcript, inspector, agent commands/config options, current plan,
  /// and the derived `isPromptSubmitting`/`canCancel`) is only recomputed
  /// when [session] is the active one — a background session's own updates
  /// must never overwrite what the user is currently looking at.
  void _handleSessionChange(AcpSession session) {
    final sessionItem = _sessionListItem(session);
    final otherSessions = state.sessions
        .where((item) => item.id != sessionItem.id)
        .toList(growable: false);
    final sessions = [sessionItem, ...otherSessions];

    final isActiveSession =
        state.activeSessionId == null ||
        state.activeSessionId == session.id.value;
    if (!isActiveSession) {
      emit(state.copyWith(sessions: sessions));
      return;
    }

    emit(
      state.copyWith(
        sessions: sessions,
        activeSessionId: sessionItem.id,
        currentSessionLabel: sessionItem.title,
        currentSessionDetail: sessionItem.subtitle ?? session.id.value,
        transcriptEntries: _transcriptEntriesForSession(session),
        inspectorEntries: _inspectorEntriesForSession(session),
        agentCommands: _agentCommandsFor(session),
        configOptions: _configOptionsFor(session),
        currentPlan: _currentPlanForSession(session),
        isPromptSubmitting: _isBusyLifecycleStatus(session.status),
        canCancel: _isCancellableLifecycleStatus(session.status),
      ),
    );
  }

  /// Derives the current config option list from [AcpSession.configOptions]
  /// — kept in sync via `SessionStateMachine._applyUpdate`'s
  /// `ConfigOptionUpdate` handling (session-scoped, same pattern as
  /// `AvailableCommandsUpdate`/[_agentCommandsFor]). Maps the protocol DTO
  /// to the `acp_ui`-facing [AcpConfigOption] here, at the application
  /// boundary — `acp_ui` has no dependency on `acp_protocol`.
  List<AcpConfigOption> _configOptionsFor(AcpSession session) {
    return (session.configOptions ?? const [])
        .map(_configOptionUiModel)
        .toList(growable: false);
  }

  AcpConfigOption _configOptionUiModel(SessionConfigOption option) {
    return switch (option) {
      SessionConfigSelect(
        :final id,
        :final name,
        :final currentValue,
        :final options,
        :final description,
      ) =>
        AcpConfigOption(
          id: id.value,
          name: name,
          currentValue: currentValue.value,
          description: description,
          values: options
              .map(
                (value) => AcpConfigOptionValue(
                  value: value.value.value,
                  name: value.name,
                  description: value.description,
                ),
              )
              .toList(growable: false),
        ),
    };
  }

  /// Derives the current agent-declared command list from
  /// [AcpSession.availableCommands], which the domain layer already keeps
  /// as "last `available_commands_update` wins" — see
  /// `SessionStateMachine._applyUpdate` in acp_client_core, which applies
  /// this update to the session itself (not a turn), since ACP allows
  /// agents to send it at any time, including before any prompt turn
  /// exists. Recomputed from scratch on every `sessionChanges` event, so
  /// switching to a session that has not (yet) declared any commands
  /// naturally yields an empty list.
  List<AcpCommandAction> _agentCommandsFor(AcpSession session) {
    return session.availableCommands
        .map(_agentCommandAction)
        .toList(growable: false);
  }

  /// Derives the active session's current plan from `session.turns` — the
  /// last `SessionUpdate.plan` seen across all of its turns wins (a plan
  /// sent in an earlier turn stays the current one into a later turn that
  /// hasn't sent its own), same "later update replaces the list" pattern as
  /// [_agentCommandsFor]/[_configOptionsFor] — except the "list" here is
  /// nullable: `null` means no `plan` update has arrived yet (or the user
  /// dismissed it, see [dismissPlan]), which is how
  /// [CodeLabShellState.currentPlan] signals "no plan section to show" —
  /// there's no equivalent empty-vs-absent distinction for
  /// `configOptions`/`agentCommands`, which just use an empty list.
  List<AcpPlanEntry>? _currentPlanForSession(AcpSession session) {
    List<PlanEntry>? latest;
    for (final turn in session.turns) {
      for (final update in turn.updates) {
        if (update case PlanUpdate(:final entries)) {
          latest = entries;
        }
      }
    }
    return latest?.map(_planEntryUiModel).toList(growable: false);
  }

  AcpPlanEntry _planEntryUiModel(PlanEntry entry) {
    return AcpPlanEntry(
      content: entry.content,
      status: switch (entry.status) {
        PlanEntryStatus.pending => AcpPlanEntryStatus.pending,
        PlanEntryStatus.inProgress => AcpPlanEntryStatus.inProgress,
        PlanEntryStatus.completed => AcpPlanEntryStatus.completed,
      },
      priority: switch (entry.priority) {
        PlanEntryPriority.high => AcpPlanEntryPriority.high,
        PlanEntryPriority.medium => AcpPlanEntryPriority.medium,
        PlanEntryPriority.low => AcpPlanEntryPriority.low,
      },
    );
  }

  AcpCommandAction _agentCommandAction(AvailableCommand command) {
    final hint = command.input?.hint;
    return AcpCommandAction(
      id: 'agent-${command.name}',
      label: command.name,
      slashCommand: '/${command.name}',
      description: command.description,
      icon: FluentIcons.robot,
      source: AcpCommandSource.agent,
      hint: hint == null || hint.isEmpty ? null : hint,
    );
  }

  /// Reacts only to a *spontaneous* connection loss — a transport failure
  /// that happened while nobody asked for one, i.e. `connectionStatus` was
  /// still `connected`. Explicit `connect()`/`reconnect()` already move
  /// `connectionStatus` to `connecting`/`reconnecting` before awaiting and
  /// fully own reporting their own outcome in their own catch/`result.match`
  /// blocks — this handler must stay silent for those, or every explicit
  /// failure would get a second, conflicting diagnostic entry from here.
  /// Неожиданный сбой соединения, пока Cubit считает его установленным:
  /// сбой явного [connect]/[reconnect] сообщают сами эти методы, поэтому
  /// здесь он не дублируется.
  void _handleWorkspaceChange(WorkspaceState workspace) {
    final connection = workspace.connection;
    if (connection is! ConnectionFailed) {
      return;
    }
    if (state.connectionStatus != AcpConnectionStatus.connected) {
      return;
    }

    emit(
      state.copyWith(
        connectionStatus: AcpConnectionStatus.failed,
        isPromptSubmitting: false,
        canCancel: false,
        isRespondingToApproval: false,
        isRespondingToConfigOption: false,
      ),
    );
    _recordDiagnostic(
      'Connection to ACP agent lost: ${connection.message}',
      severity: _DiagnosticSeverity.error,
      source: 'transport',
    );
  }

  AcpApprovalRisk _approvalRisk(ApprovalRiskLevel risk) => switch (risk) {
    ApprovalRiskLevel.readOnly => AcpApprovalRisk.readOnly,
    ApprovalRiskLevel.localWrite => AcpApprovalRisk.localWrite,
    ApprovalRiskLevel.network => AcpApprovalRisk.network,
    ApprovalRiskLevel.shell => AcpApprovalRisk.shell,
    ApprovalRiskLevel.destructive => AcpApprovalRisk.destructive,
  };

  AcpApprovalOption _approvalOption(PermissionOption option) =>
      AcpApprovalOption(
        id: option.optionId.value,
        label: option.name,
        kind: _approvalOptionKind(option.kind),
        tone: switch (option.kind) {
          PermissionOptionKind.allowOnce ||
          PermissionOptionKind.allowAlways => AcpTone.success,
          PermissionOptionKind.rejectOnce ||
          PermissionOptionKind.rejectAlways => AcpTone.danger,
        },
      );

  AcpApprovalOptionKind _approvalOptionKind(PermissionOptionKind kind) =>
      switch (kind) {
        PermissionOptionKind.allowOnce => AcpApprovalOptionKind.allowOnce,
        PermissionOptionKind.allowAlways => AcpApprovalOptionKind.allowAlways,
        PermissionOptionKind.rejectOnce => AcpApprovalOptionKind.rejectOnce,
        PermissionOptionKind.rejectAlways => AcpApprovalOptionKind.rejectAlways,
      };

  /// Профиль подключения из формы; `null` — форма не заполнена (нет
  /// команды stdio или корректного адреса WebSocket).
  ///
  /// Токен WebSocket кладётся в [_secrets], а профиль хранит только ссылку
  /// на него (design D8).
  ConnectionProfile? _profileFromState() {
    switch (state.transportType) {
      case CodeLabTransportType.stdio:
        final command = state.stdioCommand.trim();
        if (command.isEmpty) {
          return null;
        }
        return ConnectionProfile.stdio(
          id: 'codelab_app.stdio',
          label: state.selectedProfileLabel,
          command: command,
          args: _splitShellWords(state.stdioArgs),
          env: _parseEnv(state.stdioEnv),
          runInProjectDirectory: state.runAgentFromProjectDirectory,
        );
      case CodeLabTransportType.webSocket:
        final endpoint = state.webSocketEndpoint.trim();
        final uri = endpoint.isEmpty ? null : Uri.tryParse(endpoint);
        if (uri == null) {
          return null;
        }
        final token = state.webSocketToken.trim();
        _secrets.write(_webSocketTokenRef, token.isEmpty ? null : token);
        return ConnectionProfile.webSocket(
          id: 'codelab_app.websocket',
          label: state.selectedProfileLabel,
          uri: uri,
          tokenRef: token.isEmpty ? null : _webSocketTokenRef,
        );
    }
  }

  /// The project directory to use for a session/spawn `cwd` — the selected
  /// project if one exists, falling back to the CodeLab process's own
  /// current directory otherwise (unchanged fallback behavior — see
  /// add-open-project-picker/design.md, Goals).
  String get _selectedProjectPath {
    final selected = state.selectedProjectPath?.trim();
    return selected == null || selected.isEmpty
        ? _workingDirectoryProvider.currentPath
        : selected;
  }

  AcpSessionListItem _sessionListItem(AcpSession session) {
    final title = session.title?.trim().isNotEmpty == true
        ? session.title!.trim()
        : 'Session ${session.id.value}';
    return AcpSessionListItem(
      id: session.id.value,
      title: title,
      status: _sessionStatus(session.status),
      subtitle: session.cwd,
      updatedLabel: 'Active',
    );
  }

  AcpSessionStatus _sessionStatus(SessionLifecycleStatus status) =>
      switch (status) {
        SessionLifecycleStatus.idle ||
        SessionLifecycleStatus.active => AcpSessionStatus.idle,
        SessionLifecycleStatus.runningTurn ||
        SessionLifecycleStatus.cancellingTurn => AcpSessionStatus.running,
        SessionLifecycleStatus.awaitingApproval =>
          AcpSessionStatus.awaitingApproval,
        SessionLifecycleStatus.failed => AcpSessionStatus.failed,
      };

  /// Текст ошибки kit или ядра клиента для диагностики — тот же, что давал
  /// `_failureMessage` после use case-ов `acp_client_core` до переноса
  /// подключения и сессий в kit. Перенос в `describeFailure` kit — итерация 6
  /// (design D9).
  String _errorMessage(Object error) => switch (error) {
    AcpClientApplicationException(:final message) ||
    AcpTransportException(:final message) ||
    StateTransitionException(:final message) ||
    ClientWorkspaceException(:final message) => message,
    _ => error.toString(),
  };

  String _failureMessage(AcpClientApplicationFailure failure) =>
      switch (failure) {
        AcpClientTransportFailure(:final message) ||
        AcpClientProtocolFailure(:final message) ||
        AcpClientStateRejectedFailure(:final message) ||
        AcpClientMissingSessionFailure(:final message) ||
        AcpClientUnexpectedFailure(:final message) => message,
      };

  /// Транскрипт сессии из `acp_client_kit` в модели `acp_ui`.
  ///
  /// Проекцию строит kit (`TranscriptProjector`, design D5 change
  /// `extract-acp-client-kit`); здесь только отображение. `SessionView` kit
  /// уже обновлён к моменту вызова: рабочее пространство подписано на
  /// `sessionChanges` раньше Cubit (см. [_sessionSubscription]). Id записей —
  /// позиционные (`prompt-N`, `agent-N`, `tool-N`, `prompt-error-N`), как до
  /// переноса.
  List<AcpTranscriptEntry> _transcriptEntriesForSession(AcpSession session) {
    final transcript =
        _workspace.session(session.id)?.current.transcript ??
        const <TranscriptItem>[];
    return [
      for (final (index, item) in transcript.indexed)
        _transcriptEntry(item, index + 1, cwd: session.cwd),
    ];
  }

  AcpTranscriptEntry _transcriptEntry(
    TranscriptItem item,
    int position, {
    required String cwd,
  }) => switch (item) {
    UserItem(:final text) => AcpTranscriptEntry(
      id: 'prompt-$position',
      kind: AcpTranscriptEntryKind.user,
      title: 'You',
      body: text,
    ),
    AgentTextItem(:final text) ||
    ThoughtItem(:final text) ||
    NoticeItem(kind: NoticeKind.emptyTurn, :final text) => AcpTranscriptEntry(
      id: 'agent-$position',
      kind: AcpTranscriptEntryKind.agent,
      title: 'Agent',
      body: text,
    ),
    NoticeItem(kind: NoticeKind.error, :final text) => AcpTranscriptEntry(
      id: 'prompt-error-$position',
      kind: AcpTranscriptEntryKind.diagnostic,
      title: 'Prompt failed',
      body: text,
    ),
    ToolCallItem(:final title, :final details, :final approval) =>
      AcpTranscriptEntry(
        id: 'tool-$position',
        kind: AcpTranscriptEntryKind.toolCall,
        title: title,
        toolCall: details == null
            ? null
            : AcpToolCallSummary(
                name: details.kind.wireName,
                status: _toolCallStatus(details.status),
                detail: details.command,
              ),
        approval: _transcriptApproval(approval, cwd: cwd),
      ),
  };

  /// Одобрение встроено в запись вызова: ожидающее — интерактивное,
  /// решённое — компактная отметка (embed-approval-in-thread/design.md,
  /// Decisions 1–3).
  AcpTranscriptApproval? _transcriptApproval(
    ApprovalStateView? approval, {
    required String cwd,
  }) => switch (approval) {
    null => null,
    ResolvedApprovalView(:final label) => AcpTranscriptApproval.resolved(
      label: label,
    ),
    PendingApprovalView() => AcpTranscriptApproval.pending(
      risk: _approvalRisk(approval.risk),
      command: approval.command,
      cwd: cwd,
      rawInput: _prettyJson(approval.rawInput),
      options: approval.options.map(_approvalOption).toList(),
      enabled: !state.isRespondingToApproval,
      shortcutsEnabled: approval.focused,
      onOptionSelected: (optionId) => unawaited(
        respondToApproval(
          approvalId: approval.approvalId,
          sessionId: approval.sessionId,
          optionId: optionId,
        ),
      ),
    ),
  };

  AcpToolCallStatus _toolCallStatus(ToolCallStatusView status) =>
      switch (status) {
        ToolCallStatusView.queued => AcpToolCallStatus.queued,
        ToolCallStatusView.running => AcpToolCallStatus.running,
        ToolCallStatusView.succeeded => AcpToolCallStatus.succeeded,
        ToolCallStatusView.failed => AcpToolCallStatus.failed,
        ToolCallStatusView.cancelled => AcpToolCallStatus.cancelled,
      };

  List<CodeLabInspectorEntry> _inspectorEntriesForSession(AcpSession session) {
    final turn = session.turns.lastOrNull;
    if (turn == null) {
      return [
        CodeLabInspectorEntry(
          id: 'session-${session.id.value}',
          category: CodeLabInspectorCategory.protocol,
          title: 'Session ${session.id.value}',
          summary: 'Status ${session.status.name}',
          details: [
            CodeLabInspectorDetail(label: 'CWD', value: session.cwd),
            CodeLabInspectorDetail(label: 'Status', value: session.status.name),
          ],
        ),
      ];
    }

    return _inspectorEntriesForTurn(turn);
  }

  List<CodeLabInspectorEntry> _inspectorEntriesForTurn(PromptTurn turn) {
    final entries = <CodeLabInspectorEntry>[];

    for (final approval in turn.approvals.values) {
      entries.add(_approvalInspectorEntry(approval));
    }

    for (final toolCall in turn.toolCalls.values) {
      entries.add(_toolCallInspectorEntry(toolCall));
    }

    for (var index = 0; index < turn.updates.length; index += 1) {
      entries.add(_protocolInspectorEntry(turn.updates[index], index));
    }

    entries.add(
      CodeLabInspectorEntry(
        id: 'turn-${turn.id.value}',
        category: CodeLabInspectorCategory.protocol,
        title: 'Prompt turn ${turn.id.value}',
        summary: 'Status ${turn.status.name}',
        status: turn.stopReason?.wireName ?? turn.status.name,
        details: [
          CodeLabInspectorDetail(label: 'Session', value: turn.sessionId.value),
          CodeLabInspectorDetail(label: 'Status', value: turn.status.name),
          if (turn.stopReason != null)
            CodeLabInspectorDetail(
              label: 'Stop reason',
              value: turn.stopReason!.wireName,
            ),
          CodeLabInspectorDetail(
            label: 'Updates',
            value: turn.updates.length.toString(),
          ),
        ],
      ),
    );

    return entries;
  }

  CodeLabInspectorEntry _approvalInspectorEntry(ApprovalRequest approval) {
    final toolCall = approval.toolCall;
    return CodeLabInspectorEntry(
      id: 'approval-${approval.id.value}',
      category: CodeLabInspectorCategory.approval,
      title: 'Approval ${approval.id.value}',
      summary: toolCall.title,
      risk: approval.riskLevel.name,
      status: approval.status.name,
      details: [
        CodeLabInspectorDetail(label: 'Tool', value: toolCall.title),
        CodeLabInspectorDetail(label: 'Kind', value: toolCall.kind.wireName),
        CodeLabInspectorDetail(label: 'Status', value: approval.status.name),
        CodeLabInspectorDetail(
          label: 'Options',
          value: approval.options
              .map((option) => '${option.name} (${option.kind.wireName})')
              .join(', '),
        ),
        ..._toolCallContentDetails(toolCall.content),
        ..._toolCallLocationDetails(toolCall.locations),
      ],
      rawInput: _prettyJson(toolCall.rawInput),
      rawOutput: _prettyJson(toolCall.rawOutput),
    );
  }

  CodeLabInspectorEntry _toolCallInspectorEntry(ToolCallRecord toolCall) {
    return CodeLabInspectorEntry(
      id: 'tool-${toolCall.id.value}',
      category: CodeLabInspectorCategory.toolCall,
      title: toolCall.title,
      summary: toolCall.kind.wireName,
      risk: toolCall.riskLevel.name,
      status: toolCall.status.wireName,
      details: [
        CodeLabInspectorDetail(label: 'Tool call', value: toolCall.id.value),
        CodeLabInspectorDetail(label: 'Kind', value: toolCall.kind.wireName),
        CodeLabInspectorDetail(
          label: 'Status',
          value: toolCall.status.wireName,
        ),
        ..._toolCallContentDetails(toolCall.content),
        ..._toolCallLocationDetails(toolCall.locations),
      ],
      rawInput: _prettyJson(toolCall.rawInput),
      rawOutput: _prettyJson(toolCall.rawOutput),
    );
  }

  CodeLabInspectorEntry _protocolInspectorEntry(
    SessionUpdate update,
    int index,
  ) {
    return switch (update) {
      UserMessageChunk(:final content) => _contentInspectorEntry(
        id: 'update-$index',
        title: 'session/update user_message_chunk',
        content: content,
      ),
      AgentMessageChunk(:final content) => _contentInspectorEntry(
        id: 'update-$index',
        title: 'session/update agent_message_chunk',
        content: content,
      ),
      AgentThoughtChunk(:final content) => _contentInspectorEntry(
        id: 'update-$index',
        title: 'session/update agent_thought_chunk',
        content: content,
      ),
      ToolCallSessionUpdate(:final toolCall) => CodeLabInspectorEntry(
        id: 'update-$index',
        category: CodeLabInspectorCategory.protocol,
        title: 'session/update tool_call',
        summary: toolCall.title,
        details: [
          CodeLabInspectorDetail(
            label: 'Tool call',
            value: toolCall.toolCallId.value,
          ),
          CodeLabInspectorDetail(label: 'Kind', value: toolCall.kind.wireName),
          CodeLabInspectorDetail(
            label: 'Status',
            value: toolCall.status.wireName,
          ),
          ..._toolCallContentDetails(toolCall.content ?? const []),
          ..._toolCallLocationDetails(toolCall.locations ?? const []),
        ],
        rawInput: _prettyJson(toolCall.rawInput),
        rawOutput: _prettyJson(toolCall.rawOutput),
      ),
      ToolCallUpdateSessionUpdate(:final toolCallUpdate) =>
        CodeLabInspectorEntry(
          id: 'update-$index',
          category: CodeLabInspectorCategory.protocol,
          title: 'session/update tool_call_update',
          summary: toolCallUpdate.title ?? toolCallUpdate.toolCallId.value,
          details: [
            CodeLabInspectorDetail(
              label: 'Tool call',
              value: toolCallUpdate.toolCallId.value,
            ),
            if (toolCallUpdate.kind != null)
              CodeLabInspectorDetail(
                label: 'Kind',
                value: toolCallUpdate.kind!.wireName,
              ),
            if (toolCallUpdate.status != null)
              CodeLabInspectorDetail(
                label: 'Status',
                value: toolCallUpdate.status!.wireName,
              ),
            ..._toolCallContentDetails(toolCallUpdate.content ?? const []),
            ..._toolCallLocationDetails(toolCallUpdate.locations ?? const []),
          ],
          rawInput: _prettyJson(toolCallUpdate.rawInput),
          rawOutput: _prettyJson(toolCallUpdate.rawOutput),
        ),
      PlanUpdate(:final entries) => CodeLabInspectorEntry(
        id: 'update-$index',
        category: CodeLabInspectorCategory.protocol,
        title: 'session/update plan',
        summary: '${entries.length} entries',
        details: entries
            .map(
              (entry) => CodeLabInspectorDetail(
                label: entry.status.wireName,
                value: entry.content,
              ),
            )
            .toList(growable: false),
      ),
      AvailableCommandsUpdate(:final availableCommands) =>
        CodeLabInspectorEntry(
          id: 'update-$index',
          category: CodeLabInspectorCategory.protocol,
          title: 'session/update available_commands_update',
          summary: '${availableCommands.length} commands',
        ),
      CurrentModeUpdate(:final currentModeId) => CodeLabInspectorEntry(
        id: 'update-$index',
        category: CodeLabInspectorCategory.protocol,
        title: 'session/update current_mode_update',
        summary: currentModeId.value,
      ),
      ConfigOptionUpdate(:final configOptions) => CodeLabInspectorEntry(
        id: 'update-$index',
        category: CodeLabInspectorCategory.protocol,
        title: 'session/update config_option_update',
        summary: '${configOptions.length} options',
      ),
      SessionInfoUpdate(:final title) => CodeLabInspectorEntry(
        id: 'update-$index',
        category: CodeLabInspectorCategory.protocol,
        title: 'session/update session_info_update',
        summary: title ?? 'Session info updated',
      ),
    };
  }

  CodeLabInspectorEntry _contentInspectorEntry({
    required String id,
    required String title,
    required ContentBlock content,
  }) {
    return CodeLabInspectorEntry(
      id: id,
      category: CodeLabInspectorCategory.protocol,
      title: title,
      summary: _contentSummary(content),
    );
  }

  List<CodeLabInspectorDetail> _toolCallContentDetails(
    List<ToolCallContent> content,
  ) {
    return [
      for (final item in content)
        switch (item) {
          ToolCallDiff(:final diff) => CodeLabInspectorDetail(
            label: 'Diff',
            value: '${diff.path} (${diff.oldText == null ? 'new' : 'edit'})',
          ),
          ToolCallTerminal(:final terminalId) => CodeLabInspectorDetail(
            label: 'Terminal',
            value: terminalId,
          ),
          ToolCallContentBlock(:final content) => CodeLabInspectorDetail(
            label: 'Content',
            value: _contentSummary(content),
          ),
        },
    ];
  }

  List<CodeLabInspectorDetail> _toolCallLocationDetails(
    List<ToolCallLocation> locations,
  ) {
    return [
      for (final location in locations)
        CodeLabInspectorDetail(
          label: 'Location',
          value: location.line == null
              ? location.path
              : '${location.path}:${location.line}',
        ),
    ];
  }

  String _contentSummary(ContentBlock content) {
    return switch (content) {
      TextContent(:final text) => text,
      ImageContent(:final mimeType) => 'Image $mimeType',
      AudioContent(:final mimeType) => 'Audio $mimeType',
      ResourceLink(:final uri) => uri,
      EmbeddedResource(:final resource) => _prettyJson(resource.toJson())!,
    };
  }

  String? _prettyJson(Object? value) {
    if (value == null) {
      return null;
    }

    return const JsonEncoder.withIndent('  ').convert(_redactor.redact(value));
  }

  List<String> _splitShellWords(String value) => value
      .split(RegExp(r'\s+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  Map<String, String> _parseEnv(String value) {
    final env = <String, String>{};
    for (final line in value.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final separator = trimmed.indexOf('=');
      if (separator <= 0) {
        continue;
      }

      env[trimmed.substring(0, separator).trim()] = trimmed
          .substring(separator + 1)
          .trim();
    }
    return env;
  }

  AcpConnectionStatus _connectionStatusFor(ConnectionView connection) =>
      switch (connection) {
        Disconnected() => AcpConnectionStatus.disconnected,
        Connecting() => AcpConnectionStatus.connecting,
        Reconnecting() => AcpConnectionStatus.reconnecting,
        Connected() => AcpConnectionStatus.connected,
        ConnectionFailed() => AcpConnectionStatus.failed,
      };
}
