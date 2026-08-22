import 'package:acp_transports/acp_transports.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

final class CodeLabShellState {
  const CodeLabShellState({
    required this.connectionStatus,
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
}

final class CodeLabShellCubit extends Cubit<CodeLabShellState> {
  CodeLabShellCubit({required StdioAcpAgentProfile profile})
    : super(CodeLabShellState.initial(profile: profile));

  void connect() => _recordPendingAction('Connect is wired in task 7.2.');

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
    final nextEntry = AcpDebugLogEntry(
      id: 'pending-${state.diagnostics.length + 1}',
      severity: AcpDebugLogSeverity.info,
      source: 'presentation',
      message: message,
    );

    emit(state.copyWith(diagnostics: [...state.diagnostics, nextEntry]));
  }
}
