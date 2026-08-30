import 'dart:async';
import 'dart:convert';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/working_directory_provider.dart';

typedef CodeLabStdioTransportFactory =
    AcpTransport Function(StdioAcpTransportConfig config);

enum CodeLabTransportType {
  stdio(label: 'stdio'),
  webSocket(label: 'WebSocket');

  const CodeLabTransportType({required this.label});

  final String label;
}

final class CodeLabShellState {
  const CodeLabShellState({
    required this.connectionStatus,
    required this.transportType,
    required this.stdioProfileName,
    required this.stdioCommand,
    required this.stdioArgs,
    required this.stdioCwd,
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
    required this.diagnostics,
    required this.viewMode,
    required this.isPromptEnabled,
    required this.isPromptSubmitting,
    required this.canCancel,
    this.pendingApproval,
    this.isRespondingToApproval = false,
    this.isCommandPaletteOpen = false,
    this.isInspectorVisibleInNarrowLayout = false,
    this.agentCommands = const [],
    this.composerDraft = '',
    this.configOptions = const [],
    this.isRespondingToConfigOption = false,
  });

  factory CodeLabShellState.initial({required StdioAcpAgentProfile profile}) =>
      CodeLabShellState(
        connectionStatus: AcpConnectionStatus.disconnected,
        transportType: CodeLabTransportType.stdio,
        stdioProfileName: profile.name,
        stdioCommand: profile.command,
        stdioArgs: profile.args.join(' '),
        stdioCwd: profile.cwd ?? '',
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
        diagnostics: const [
          AcpDebugLogEntry(
            id: 'bootstrap',
            severity: AcpDebugLogSeverity.info,
            source: 'app',
            message: 'Shell bootstrapped. Connection wiring starts in 7.2.',
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
  final String stdioCwd;
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
  final List<AcpDebugLogEntry> diagnostics;
  final AcpViewMode viewMode;
  final bool isPromptEnabled;
  final bool isPromptSubmitting;
  final bool canCancel;
  final CodeLabPendingApproval? pendingApproval;
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

  /// The active session's `SessionConfigOption`s (e.g. model/mode selectors
  /// the agent advertised), replaced wholesale on every new
  /// `config_option_update` and cleared/restored on session switch/creation
  /// — same "later update replaces the list" pattern as [agentCommands].
  final List<SessionConfigOption> configOptions;

  /// Guards against a second `session/set_config_option` request firing
  /// while one is already in flight, mirroring [isRespondingToApproval].
  final bool isRespondingToConfigOption;

  CodeLabShellState copyWith({
    AcpConnectionStatus? connectionStatus,
    CodeLabTransportType? transportType,
    String? stdioProfileName,
    String? stdioCommand,
    String? stdioArgs,
    String? stdioCwd,
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
    List<AcpDebugLogEntry>? diagnostics,
    AcpViewMode? viewMode,
    bool? isPromptEnabled,
    bool? isPromptSubmitting,
    bool? canCancel,
    Object? pendingApproval = _unsetPendingApproval,
    bool? isRespondingToApproval,
    bool? isCommandPaletteOpen,
    bool? isInspectorVisibleInNarrowLayout,
    List<AcpCommandAction>? agentCommands,
    String? composerDraft,
    List<SessionConfigOption>? configOptions,
    bool? isRespondingToConfigOption,
  }) {
    return CodeLabShellState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      transportType: transportType ?? this.transportType,
      stdioProfileName: stdioProfileName ?? this.stdioProfileName,
      stdioCommand: stdioCommand ?? this.stdioCommand,
      stdioArgs: stdioArgs ?? this.stdioArgs,
      stdioCwd: stdioCwd ?? this.stdioCwd,
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
      diagnostics: diagnostics ?? this.diagnostics,
      viewMode: viewMode ?? this.viewMode,
      isPromptEnabled: isPromptEnabled ?? this.isPromptEnabled,
      isPromptSubmitting: isPromptSubmitting ?? this.isPromptSubmitting,
      canCancel: canCancel ?? this.canCancel,
      pendingApproval: identical(pendingApproval, _unsetPendingApproval)
          ? this.pendingApproval
          : pendingApproval as CodeLabPendingApproval?,
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
    );
  }

  CodeLabShellState withTransportProjection({
    CodeLabTransportType? transportType,
    String? stdioProfileName,
    String? stdioCommand,
    String? stdioArgs,
    String? stdioCwd,
    String? stdioEnv,
    String? webSocketEndpoint,
    String? webSocketToken,
  }) {
    final next = copyWith(
      transportType: transportType,
      stdioProfileName: stdioProfileName,
      stdioCommand: stdioCommand,
      stdioArgs: stdioArgs,
      stdioCwd: stdioCwd,
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

  String get selectedDiagnosticSummary => switch (transportType) {
    CodeLabTransportType.stdio =>
      'stdio ${selectedConnectionDetail.trim()}'.trim(),
    CodeLabTransportType.webSocket =>
      'WebSocket endpoint=$webSocketEndpoint token=${webSocketToken.isEmpty ? 'empty' : 'set'}',
  };
}

/// Sentinel used by [CodeLabShellState.copyWith] to distinguish "leave
/// pendingApproval unchanged" from "explicitly set pendingApproval to null"
/// (a plain `T?` parameter can't represent that distinction).
const Object _unsetPendingApproval = Object();

/// Presentation-ready projection of the single approval request the user
/// should currently act on. Derived exclusively from [AcpSession.activeTurn]
/// in [CodeLabShellCubit._handleSessionChange]; never mutated locally so it
/// always reflects the authoritative session state (see PERM-003/PERM-004 in
/// docs/architecture/permissions.md).
final class CodeLabPendingApproval {
  const CodeLabPendingApproval({
    required this.approvalId,
    required this.sessionId,
    required this.title,
    required this.risk,
    required this.options,
    this.command,
    this.cwd,
  });

  final ApprovalRequestId approvalId;
  final SessionId sessionId;
  final String title;
  final AcpApprovalRisk risk;
  final List<AcpApprovalOption> options;
  final String? command;
  final String? cwd;
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

final class CodeLabShellCubit extends Cubit<CodeLabShellState> {
  CodeLabShellCubit({
    required StdioAcpAgentProfile profile,
    required AcpClientApplication application,
    required CreateSession createSessionUseCase,
    required SendPrompt sendPromptUseCase,
    required CancelTurn cancelTurnUseCase,
    required Reconnect reconnectUseCase,
    required RespondToPermission respondToPermissionUseCase,
    required SetSessionConfigOption setSessionConfigOptionUseCase,
    required CodeLabStdioTransportFactory stdioTransportFactory,
    required WorkingDirectoryProvider workingDirectoryProvider,
  }) : _application = application,
       _createSessionUseCase = createSessionUseCase,
       _sendPromptUseCase = sendPromptUseCase,
       _cancelTurnUseCase = cancelTurnUseCase,
       _reconnectUseCase = reconnectUseCase,
       _respondToPermissionUseCase = respondToPermissionUseCase,
       _setSessionConfigOptionUseCase = setSessionConfigOptionUseCase,
       _stdioTransportFactory = stdioTransportFactory,
       _workingDirectoryProvider = workingDirectoryProvider,
       super(CodeLabShellState.initial(profile: profile)) {
    _sessionSubscription = _application.sessionChanges.listen(
      _handleSessionChange,
    );
    _diagnosticSubscription = _application.diagnosticChanges.listen(
      _handleApplicationDiagnostic,
    );
  }

  final AcpClientApplication _application;
  final CreateSession _createSessionUseCase;
  final SendPrompt _sendPromptUseCase;
  final CancelTurn _cancelTurnUseCase;
  final Reconnect _reconnectUseCase;
  final RespondToPermission _respondToPermissionUseCase;
  final SetSessionConfigOption _setSessionConfigOptionUseCase;
  final CodeLabStdioTransportFactory _stdioTransportFactory;
  final WorkingDirectoryProvider _workingDirectoryProvider;
  final _redactor = const SecretRedactor();
  late final StreamSubscription<AcpSession> _sessionSubscription;
  late final StreamSubscription<DiagnosticEntry> _diagnosticSubscription;

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

  void updateStdioCwd(String value) {
    emit(state.withTransportProjection(stdioCwd: value));
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

  Future<void> connect() async {
    if (state.transportType == CodeLabTransportType.webSocket) {
      _recordPendingAction(
        'WebSocket connect is deferred: ${state.selectedDiagnosticSummary}.',
      );
      return;
    }

    final config = _stdioConfigFromState();
    if (config == null) {
      _recordDiagnostic(
        'Stdio command is required before connecting.',
        severity: AcpDebugLogSeverity.error,
        source: 'transport',
      );
      emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
      return;
    }

    emit(state.copyWith(connectionStatus: AcpConnectionStatus.connecting));
    _recordDiagnostic(
      'Starting stdio ACP agent: ${state.selectedConnectionDetail}.',
      source: 'transport',
    );

    try {
      final transport = _stdioTransportFactory(config);
      final connectionState = await _application.connect(transport);
      emit(
        state.copyWith(
          connectionStatus: _connectionStatusForConnection(connectionState),
        ),
      );
      _recordDiagnostic(
        'Stdio ACP agent started: ${state.selectedConnectionDetail}.',
        source: 'transport',
      );
    } on UnsupportedProtocolVersionException catch (error) {
      emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
      _recordDiagnostic(
        'Incompatible ACP agent: ${error.message}',
        severity: AcpDebugLogSeverity.error,
        source: 'transport',
      );
    } on Object catch (error) {
      emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
      _recordDiagnostic(
        'Failed to start stdio ACP agent: $error',
        severity: AcpDebugLogSeverity.error,
        source: 'transport',
      );
    }
  }

  Future<void> reconnect() async {
    if (state.transportType == CodeLabTransportType.webSocket) {
      _recordPendingAction(
        'WebSocket reconnect is deferred: ${state.selectedDiagnosticSummary}.',
      );
      return;
    }

    final config = _stdioConfigFromState();
    if (config == null) {
      _recordDiagnostic(
        'Stdio command is required before reconnecting.',
        severity: AcpDebugLogSeverity.error,
        source: 'transport',
      );
      emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
      return;
    }

    emit(state.copyWith(connectionStatus: AcpConnectionStatus.reconnecting));
    _recordDiagnostic(
      'Reconnecting stdio ACP agent: ${state.selectedConnectionDetail}.',
      source: 'transport',
    );

    final result = await _reconnectUseCase(
      ReconnectCommand(
        transportFactory: () async => _stdioTransportFactory(config),
      ),
    ).run();
    result.match(
      (failure) {
        emit(state.copyWith(connectionStatus: AcpConnectionStatus.failed));
        _recordDiagnostic(
          'Failed to reconnect stdio ACP agent: ${_failureMessage(failure)}',
          severity: AcpDebugLogSeverity.error,
          source: 'transport',
        );
      },
      (connectionState) {
        emit(
          state.copyWith(
            connectionStatus: _connectionStatusForConnection(connectionState),
          ),
        );
        _recordDiagnostic(
          'Stdio ACP agent reconnected: ${state.selectedConnectionDetail}.',
          source: 'transport',
        );
      },
    );
  }

  void editProfile() =>
      _recordPendingAction('Transport profile editing is wired in task 7.2.');

  Future<void> createSession() async {
    if (state.connectionStatus != AcpConnectionStatus.connected) {
      _recordDiagnostic(
        'Connect an ACP agent before creating a session.',
        severity: AcpDebugLogSeverity.warning,
        source: 'session',
      );
      return;
    }

    _recordDiagnostic('Creating ACP session.', source: 'session');

    final result = await _createSessionUseCase(
      CreateSessionCommand(cwd: _selectedCwd),
    ).run();

    result.match(
      (failure) => _recordDiagnostic(
        'Failed to create ACP session: ${_failureMessage(failure)}',
        severity: AcpDebugLogSeverity.error,
        source: 'session',
      ),
      (session) {
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
            pendingApproval: null,
            agentCommands: _agentCommandsFor(session),
            configOptions: _configOptionsFor(session),
          ),
        );
        _recordDiagnostic(
          'Created ACP session ${session.id.value}.',
          source: 'session',
        );
      },
    );
  }

  /// Switches the active session and reloads all of its per-session state
  /// (transcript, inspector, pending approval, agent commands) from the
  /// application's live snapshot — without this, the previously active
  /// session's transcript/inspector/approval would remain visible until the
  /// newly selected session happened to emit its own `session/update`.
  void selectSession(String sessionId) {
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
          pendingApproval: null,
          agentCommands: const [],
          configOptions: const [],
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
        pendingApproval: _pendingApprovalFor(session),
        agentCommands: _agentCommandsFor(session),
        configOptions: _configOptionsFor(session),
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
        severity: AcpDebugLogSeverity.warning,
        source: 'prompt',
      );
      return;
    }

    final userEntry = AcpTranscriptEntry(
      id: 'prompt-${state.transcriptEntries.length + 1}',
      kind: AcpTranscriptEntryKind.user,
      title: 'You',
      body: text,
    );
    emit(
      state.copyWith(
        transcriptEntries: [...state.transcriptEntries, userEntry],
        isPromptSubmitting: true,
        canCancel: true,
      ),
    );

    final result = await _sendPromptUseCase(
      SendPromptCommand(
        sessionId: SessionId(sessionId),
        prompt: [ContentBlock.text(text: text)],
      ),
    ).run();

    result.match(
      (failure) {
        final message = 'Failed to send prompt: ${_failureMessage(failure)}';
        emit(
          state.copyWith(
            transcriptEntries: [
              ...state.transcriptEntries,
              AcpTranscriptEntry(
                id: 'prompt-error-${state.transcriptEntries.length + 1}',
                kind: AcpTranscriptEntryKind.diagnostic,
                title: 'Prompt failed',
                body: message,
              ),
            ],
            isPromptSubmitting: false,
            canCancel: false,
          ),
        );
        _recordDiagnostic(
          message,
          severity: AcpDebugLogSeverity.error,
          source: 'prompt',
        );
      },
      (turn) {
        final agentEntries = _agentTranscriptEntries(
          turn,
          baseIndex: state.transcriptEntries.length,
        );
        emit(
          state.copyWith(
            transcriptEntries: [...state.transcriptEntries, ...agentEntries],
            inspectorEntries: _inspectorEntriesForTurn(turn),
            isPromptSubmitting: false,
            canCancel: false,
          ),
        );
        _recordDiagnostic(
          'Prompt completed with stopReason ${turn.stopReason?.name ?? 'unknown'}.',
          source: 'prompt',
        );
      },
    );
  }

  Future<void> cancelTurn() async {
    final sessionId = state.activeSessionId;
    if (sessionId == null) {
      _recordDiagnostic(
        'Select a session before cancelling a prompt turn.',
        severity: AcpDebugLogSeverity.warning,
        source: 'prompt',
      );
      return;
    }

    emit(state.copyWith(canCancel: false));
    final result = await _cancelTurnUseCase(
      CancelTurnCommand(sessionId: SessionId(sessionId)),
    ).run();

    result.match(
      (failure) {
        emit(state.copyWith(isPromptSubmitting: false, canCancel: false));
        _recordDiagnostic(
          'Failed to cancel prompt turn: ${_failureMessage(failure)}',
          severity: AcpDebugLogSeverity.error,
          source: 'prompt',
        );
      },
      (turn) {
        emit(
          state.copyWith(
            inspectorEntries: _inspectorEntriesForTurn(turn),
            isPromptSubmitting: false,
            canCancel: false,
          ),
        );
        _recordDiagnostic(
          'Cancelled prompt turn ${turn.id.value}.',
          source: 'prompt',
        );
      },
    );
  }

  /// Responds to [state.pendingApproval] by selecting [optionId] (one of the
  /// agent-supplied options, including reject-kind options — ACP has no
  /// separate "reject" verb, rejecting is just selecting a reject_once /
  /// reject_always option). Correlates strictly to the currently displayed
  /// approval request (never "whatever the active turn currently is") so a
  /// stale/late tap can never resolve a different tool call — see PERM-003
  /// in docs/architecture/permissions.md.
  Future<void> respondToApproval(String optionId) async {
    final approval = state.pendingApproval;
    if (approval == null || state.isRespondingToApproval) {
      return;
    }

    emit(state.copyWith(isRespondingToApproval: true));
    final result = await _respondToPermissionUseCase(
      RespondToPermissionCommand.selected(
        sessionId: approval.sessionId,
        approvalId: approval.approvalId,
        optionId: PermissionOptionId(optionId),
      ),
    ).run();

    // Do not touch `pendingApproval` here in either branch: the resolution
    // (or the fact that it is still pending, e.g. after a stale/failed
    // response) is always re-derived from the next `sessionChanges` event in
    // `_handleSessionChange`, which stays the single source of truth.
    result.match(
      (failure) {
        emit(state.copyWith(isRespondingToApproval: false));
        _recordDiagnostic(
          'Failed to respond to approval request: ${_failureMessage(failure)}',
          severity: AcpDebugLogSeverity.error,
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

    result.match(
      (failure) {
        emit(state.copyWith(isRespondingToConfigOption: false));
        _recordDiagnostic(
          'Failed to set config option $configId: ${_failureMessage(failure)}',
          severity: AcpDebugLogSeverity.error,
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

  void clearDiagnostics() {
    emit(state.copyWith(diagnostics: const []));
  }

  @override
  Future<void> close() async {
    await _sessionSubscription.cancel();
    await _diagnosticSubscription.cancel();
    return super.close();
  }

  void _recordPendingAction(String message) {
    _recordDiagnostic(message, source: 'presentation');
  }

  void _recordDiagnostic(
    String message, {
    AcpDebugLogSeverity severity = AcpDebugLogSeverity.info,
    String? source,
  }) {
    final nextEntry = AcpDebugLogEntry(
      id: 'pending-${state.diagnostics.length + 1}',
      severity: severity,
      source: source,
      message: _redactor.redactText(message),
    );

    emit(state.copyWith(diagnostics: [...state.diagnostics, nextEntry]));
  }

  void _handleSessionChange(AcpSession session) {
    if (state.activeSessionId != null &&
        state.activeSessionId != session.id.value) {
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
        inspectorEntries: _inspectorEntriesForSession(session),
        pendingApproval: _pendingApprovalFor(session),
        agentCommands: _agentCommandsFor(session),
        configOptions: _configOptionsFor(session),
      ),
    );
  }

  /// Derives the current `SessionConfigOption` list from
  /// [AcpSession.configOptions] — kept in sync via `SessionStateMachine.
  /// _applyUpdate`'s `ConfigOptionUpdate` handling (session-scoped, same
  /// pattern as `AvailableCommandsUpdate`/[_agentCommandsFor]).
  List<SessionConfigOption> _configOptionsFor(AcpSession session) {
    return session.configOptions ?? const [];
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

  void _handleApplicationDiagnostic(DiagnosticEntry diagnostic) {
    _recordDiagnostic(
      diagnostic.message,
      severity: _debugSeverity(diagnostic.severity),
      source: diagnostic.source ?? 'application',
    );
  }

  /// Derives the single approval the user should currently act on from the
  /// active turn. If several approvals are pending concurrently (allowed by
  /// the domain model but not expected in normal ACP flows), they are
  /// surfaced one at a time, oldest first (FIFO) — the next one appears
  /// automatically once the current one resolves, since this is recomputed
  /// from scratch on every `sessionChanges` event.
  CodeLabPendingApproval? _pendingApprovalFor(AcpSession session) {
    final turn = session.activeTurn;
    if (turn == null) {
      return null;
    }

    final pending =
        turn.approvals.values
            .where((approval) => approval.status == ApprovalStatus.pending)
            .toList()
          ..sort((a, b) {
            final aTime = a.requestedAt;
            final bTime = b.requestedAt;
            if (aTime == null || bTime == null) {
              return 0;
            }
            return aTime.compareTo(bTime);
          });
    final next = pending.firstOrNull;
    if (next == null) {
      return null;
    }

    return CodeLabPendingApproval(
      approvalId: next.id,
      sessionId: session.id,
      title: next.toolCall.title,
      risk: _approvalRisk(next.riskLevel),
      options: next.options.map(_approvalOption).toList(),
      command: _commandFromToolCall(next.toolCall),
      cwd: session.cwd,
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
        tone: switch (option.kind) {
          PermissionOptionKind.allowOnce ||
          PermissionOptionKind.allowAlways => AcpTone.success,
          PermissionOptionKind.rejectOnce ||
          PermissionOptionKind.rejectAlways => AcpTone.danger,
        },
      );

  String? _commandFromToolCall(ToolCallRecord toolCall) {
    final command = toolCall.rawInput?['command'];
    return command is String && command.trim().isNotEmpty ? command : null;
  }

  StdioAcpTransportConfig? _stdioConfigFromState() {
    final command = state.stdioCommand.trim();
    if (command.isEmpty) {
      return null;
    }

    return StdioAcpTransportConfig(
      command: command,
      args: _splitShellWords(state.stdioArgs),
      cwd: state.stdioCwd.trim().isEmpty ? null : state.stdioCwd.trim(),
      env: _parseEnv(state.stdioEnv),
    );
  }

  String get _selectedCwd {
    final cwd = state.stdioCwd.trim();
    return cwd.isEmpty ? _workingDirectoryProvider.currentPath : cwd;
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
        SessionLifecycleStatus.runningTurn => AcpSessionStatus.running,
        SessionLifecycleStatus.awaitingApproval =>
          AcpSessionStatus.awaitingApproval,
        SessionLifecycleStatus.failed => AcpSessionStatus.failed,
      };

  String _failureMessage(AcpClientApplicationFailure failure) =>
      switch (failure) {
        AcpClientTransportFailure(:final message) ||
        AcpClientProtocolFailure(:final message) ||
        AcpClientStateRejectedFailure(:final message) ||
        AcpClientMissingSessionFailure(:final message) ||
        AcpClientUnexpectedFailure(:final message) => message,
      };

  List<AcpTranscriptEntry> _agentTranscriptEntries(
    PromptTurn turn, {
    required int baseIndex,
  }) {
    final entries = <AcpTranscriptEntry>[];
    for (final update in turn.updates) {
      final content = switch (update) {
        AgentMessageChunk(:final content) => content,
        AgentThoughtChunk(:final content) => content,
        _ => null,
      };
      final text = switch (content) {
        TextContent(:final text) => text,
        _ => null,
      };
      if (text == null || text.trim().isEmpty) {
        continue;
      }

      entries.add(
        AcpTranscriptEntry(
          id: 'agent-${baseIndex + entries.length + 1}',
          kind: AcpTranscriptEntryKind.agent,
          title: 'Agent',
          body: text.trim(),
        ),
      );
    }

    if (entries.isNotEmpty || !turn.isTerminal) {
      return entries;
    }

    return [
      AcpTranscriptEntry(
        id: 'agent-${baseIndex + 1}',
        kind: AcpTranscriptEntryKind.agent,
        title: 'Agent',
        body:
            'Completed with stopReason ${turn.stopReason?.name ?? 'unknown'}.',
      ),
    ];
  }

  /// Reconstructs the full transcript for [session] from `session.turns` —
  /// used when switching to a session that isn't the one incrementally
  /// tracked in `state.transcriptEntries` (see [selectSession]). Mirrors the
  /// incremental logic in [submitPrompt]/[_agentTranscriptEntries], but
  /// rebuilt from domain history instead of appended live.
  List<AcpTranscriptEntry> _transcriptEntriesForSession(AcpSession session) {
    final entries = <AcpTranscriptEntry>[];
    for (final turn in session.turns) {
      final promptText = _textFrom(turn.prompt);
      if (promptText != null && promptText.isNotEmpty) {
        entries.add(
          AcpTranscriptEntry(
            id: 'prompt-${entries.length + 1}',
            kind: AcpTranscriptEntryKind.user,
            title: 'You',
            body: promptText,
          ),
        );
      }

      entries.addAll(_agentTranscriptEntries(turn, baseIndex: entries.length));

      if (turn.status == PromptTurnStatus.failed &&
          turn.failureMessage != null) {
        entries.add(
          AcpTranscriptEntry(
            id: 'prompt-error-${entries.length + 1}',
            kind: AcpTranscriptEntryKind.diagnostic,
            title: 'Prompt failed',
            body: 'Failed to send prompt: ${turn.failureMessage}',
          ),
        );
      }
    }

    return entries;
  }

  String? _textFrom(List<ContentBlock> blocks) {
    final text = blocks
        .whereType<TextContent>()
        .map((block) => block.text)
        .where((text) => text.trim().isNotEmpty)
        .join('\n');
    return text.isEmpty ? null : text;
  }

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

  AcpDebugLogSeverity _debugSeverity(DiagnosticSeverity severity) {
    return switch (severity) {
      DiagnosticSeverity.debug => AcpDebugLogSeverity.debug,
      DiagnosticSeverity.info => AcpDebugLogSeverity.info,
      DiagnosticSeverity.warning => AcpDebugLogSeverity.warning,
      DiagnosticSeverity.error => AcpDebugLogSeverity.error,
    };
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

  AcpConnectionStatus _connectionStatusForConnection(
    ClientConnectionState connectionState,
  ) => switch (connectionState) {
    ClientConnectionDisconnected() => AcpConnectionStatus.disconnected,
    ClientConnectionConnecting() ||
    ClientConnectionInitializing() => AcpConnectionStatus.connecting,
    ClientConnectionReady() => AcpConnectionStatus.connected,
    ClientConnectionFailed() => AcpConnectionStatus.failed,
  };
}
