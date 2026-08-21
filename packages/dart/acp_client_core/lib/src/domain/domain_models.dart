import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'domain_models.freezed.dart';

@freezed
sealed class PromptTurnId with _$PromptTurnId {
  const PromptTurnId._();

  const factory PromptTurnId(String value) = _PromptTurnId;
}

@freezed
sealed class ApprovalRequestId with _$ApprovalRequestId {
  const ApprovalRequestId._();

  const factory ApprovalRequestId(String value) = _ApprovalRequestId;
}

@freezed
sealed class DiagnosticEntryId with _$DiagnosticEntryId {
  const DiagnosticEntryId._();

  const factory DiagnosticEntryId(String value) = _DiagnosticEntryId;
}

enum ConnectionFailureReason {
  startFailed,
  sendFailed,
  receiveFailed,
  protocolViolation,
  unsupportedProtocolVersion,
  disconnected,
  closed,
  timeout,
  unknown,
}

@freezed
sealed class ClientConnectionState with _$ClientConnectionState {
  const factory ClientConnectionState.disconnected() =
      ClientConnectionDisconnected;

  const factory ClientConnectionState.connecting() = ClientConnectionConnecting;

  const factory ClientConnectionState.initializing() =
      ClientConnectionInitializing;

  const factory ClientConnectionState.ready({
    required ProtocolVersion protocolVersion,
    Implementation? agentInfo,
    @Default(AgentCapabilities()) AgentCapabilities capabilities,
  }) = ClientConnectionReady;

  const factory ClientConnectionState.failed({
    required ConnectionFailureReason reason,
    required String message,
    Object? cause,
  }) = ClientConnectionFailed;
}

enum PromptTurnStatus {
  pending,
  running,
  awaitingApproval,
  completed,
  failed,
  refused,
  maxed,
  cancelled,
}

@freezed
sealed class PromptTurn with _$PromptTurn {
  const PromptTurn._();

  const factory PromptTurn({
    required PromptTurnId id,
    required SessionId sessionId,
    required List<ContentBlock> prompt,
    @Default(PromptTurnStatus.pending) PromptTurnStatus status,
    StopReason? stopReason,
    @Default([]) List<SessionUpdate> updates,
    @Default({}) Map<ToolCallId, ToolCallRecord> toolCalls,
    @Default({}) Map<ApprovalRequestId, ApprovalRequest> approvals,
    String? failureMessage,
    DateTime? startedAt,
    DateTime? completedAt,
  }) = _PromptTurn;

  bool get isTerminal => switch (status) {
    PromptTurnStatus.completed ||
    PromptTurnStatus.failed ||
    PromptTurnStatus.refused ||
    PromptTurnStatus.maxed ||
    PromptTurnStatus.cancelled => true,
    _ => false,
  };
}

enum ApprovalRiskLevel { readOnly, localWrite, network, shell, destructive }

enum ApprovalStatus { pending, selected, cancelled }

@freezed
sealed class ApprovalRequest with _$ApprovalRequest {
  const ApprovalRequest._();

  const factory ApprovalRequest({
    required ApprovalRequestId id,
    required SessionId sessionId,
    required PromptTurnId turnId,
    required ToolCallRecord toolCall,
    required List<PermissionOption> options,
    @Default(ApprovalRiskLevel.readOnly) ApprovalRiskLevel riskLevel,
    @Default(ApprovalStatus.pending) ApprovalStatus status,
    PermissionOptionId? selectedOptionId,
    DateTime? requestedAt,
    DateTime? resolvedAt,
  }) = _ApprovalRequest;

  bool get isResolved => status != ApprovalStatus.pending;
}

@freezed
sealed class ToolCallRecord with _$ToolCallRecord {
  const ToolCallRecord._();

  const factory ToolCallRecord({
    required ToolCallId id,
    required String title,
    @Default(ToolKind.other) ToolKind kind,
    @Default(ToolCallStatus.pending) ToolCallStatus status,
    @Default(ApprovalRiskLevel.readOnly) ApprovalRiskLevel riskLevel,
    @Default([]) List<ToolCallContent> content,
    @Default([]) List<ToolCallLocation> locations,
    Map<String, Object?>? rawInput,
    Map<String, Object?>? rawOutput,
    DateTime? startedAt,
    DateTime? completedAt,
  }) = _ToolCallRecord;

  factory ToolCallRecord.fromToolCall(
    ToolCall toolCall, {
    ApprovalRiskLevel riskLevel = ApprovalRiskLevel.readOnly,
  }) {
    return ToolCallRecord(
      id: toolCall.toolCallId,
      title: toolCall.title,
      kind: toolCall.kind,
      status: toolCall.status,
      riskLevel: riskLevel,
      content: toolCall.content ?? const [],
      locations: toolCall.locations ?? const [],
      rawInput: toolCall.rawInput,
      rawOutput: toolCall.rawOutput,
    );
  }
}

enum SessionLifecycleStatus {
  idle,
  active,
  runningTurn,
  awaitingApproval,
  failed,
}

@freezed
sealed class AcpSession with _$AcpSession {
  const AcpSession._();

  const factory AcpSession({
    required SessionId id,
    required String cwd,
    String? title,
    @Default(SessionLifecycleStatus.idle) SessionLifecycleStatus status,
    @Default([]) List<PromptTurn> turns,
    @Default([]) List<DiagnosticEntry> diagnostics,
    SessionModeState? modes,
    List<SessionConfigOption>? configOptions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _AcpSession;

  PromptTurn? get activeTurn {
    for (final turn in turns.reversed) {
      if (!turn.isTerminal) {
        return turn;
      }
    }

    return null;
  }
}

enum DiagnosticSeverity { debug, info, warning, error }

@freezed
sealed class DiagnosticEntry with _$DiagnosticEntry {
  const DiagnosticEntry._();

  const factory DiagnosticEntry({
    required DiagnosticEntryId id,
    required String message,
    @Default(DiagnosticSeverity.info) DiagnosticSeverity severity,
    String? source,
    @Default({}) Map<String, Object?> context,
    Object? cause,
    DateTime? createdAt,
  }) = _DiagnosticEntry;
}
