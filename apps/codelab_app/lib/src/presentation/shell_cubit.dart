import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    required this.sessions,
    required this.activeSessionId,
    required this.transcriptEntries,
    required this.diagnostics,
    required this.viewMode,
    required this.isPromptEnabled,
    required this.isPromptSubmitting,
    required this.canCancel,
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
        sessions: const [],
        activeSessionId: null,
        transcriptEntries: const [],
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
  final List<AcpSessionListItem> sessions;
  final String? activeSessionId;
  final List<AcpTranscriptEntry> transcriptEntries;
  final List<AcpDebugLogEntry> diagnostics;
  final AcpViewMode viewMode;
  final bool isPromptEnabled;
  final bool isPromptSubmitting;
  final bool canCancel;

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
    List<AcpSessionListItem>? sessions,
    String? activeSessionId,
    List<AcpTranscriptEntry>? transcriptEntries,
    List<AcpDebugLogEntry>? diagnostics,
    AcpViewMode? viewMode,
    bool? isPromptEnabled,
    bool? isPromptSubmitting,
    bool? canCancel,
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
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      transcriptEntries: transcriptEntries ?? this.transcriptEntries,
      diagnostics: diagnostics ?? this.diagnostics,
      viewMode: viewMode ?? this.viewMode,
      isPromptEnabled: isPromptEnabled ?? this.isPromptEnabled,
      isPromptSubmitting: isPromptSubmitting ?? this.isPromptSubmitting,
      canCancel: canCancel ?? this.canCancel,
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

final class CodeLabShellCubit extends Cubit<CodeLabShellState> {
  CodeLabShellCubit({
    required StdioAcpAgentProfile profile,
    required AcpClientApplication application,
    required CodeLabStdioTransportFactory stdioTransportFactory,
  }) : _application = application,
       _stdioTransportFactory = stdioTransportFactory,
       super(CodeLabShellState.initial(profile: profile));

  final AcpClientApplication _application;
  final CodeLabStdioTransportFactory _stdioTransportFactory;

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
        'WebSocket connect is deferred to task 7.7: ${state.selectedDiagnosticSummary}.',
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
      final transportState = await _application.connect(transport);
      emit(
        state.copyWith(
          connectionStatus: _connectionStatusForTransport(transportState),
        ),
      );
      _recordDiagnostic(
        'Stdio ACP agent started: ${state.selectedConnectionDetail}.',
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

  void reconnect() => _recordPendingAction('Reconnect is wired in task 7.7.');

  void editProfile() =>
      _recordPendingAction('Transport profile editing is wired in task 7.2.');

  void createSession() =>
      _recordPendingAction('Session creation is wired in task 7.4.');

  void selectSession(String sessionId) {
    emit(state.copyWith(activeSessionId: sessionId));
  }

  void submitPrompt(String prompt) {
    _recordPendingAction('Prompt sending is wired in task 7.5.');
  }

  void cancelTurn() =>
      _recordPendingAction('Cancellation is wired in task 7.7.');

  void openCommandPalette() =>
      _recordPendingAction('Command palette execution is wired after shell.');

  void clearDiagnostics() {
    emit(state.copyWith(diagnostics: const []));
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
      message: message,
    );

    emit(state.copyWith(diagnostics: [...state.diagnostics, nextEntry]));
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

  AcpConnectionStatus _connectionStatusForTransport(
    AcpTransportState transportState,
  ) => switch (transportState) {
    AcpTransportState.idle => AcpConnectionStatus.idle,
    AcpTransportState.connecting => AcpConnectionStatus.connecting,
    AcpTransportState.connected => AcpConnectionStatus.connected,
    AcpTransportState.closing ||
    AcpTransportState.closed => AcpConnectionStatus.disconnected,
    AcpTransportState.failed => AcpConnectionStatus.failed,
  };
}
