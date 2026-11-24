import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'prompt_failure.dart';

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

  /// `session/cancel` was sent; the turn still accepts its updates until the
  /// agent answers its `session/prompt` (05-Prompt Turn.md#cancellation).
  cancelling,
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

    /// Лимит, из-за которого агент остановил ход при `max_turn_requests`
    /// (`_meta.codelab.budgetExceeded` ответа `session/prompt`): открытое
    /// множество строк — `steps`, `tokens`, `cost`, `duration`, `deadline` и
    /// будущие. `null` — причины нет (сторонний агент, другой `stopReason`,
    /// значение не строка). Change `add-usage-extension`, D10, D21 Т3.
    String? budgetExceeded,
    @Default([]) List<SessionUpdate> updates,
    @Default({}) Map<ToolCallId, ToolCallRecord> toolCalls,
    @Default({}) Map<ApprovalRequestId, ApprovalRequest> approvals,
    String? failureMessage,

    /// Типизированная причина сбоя хода; заполнена вместе с
    /// [failureMessage] (design D2 change `add-connection-and-error-states`).
    PromptFailure? failure,
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

/// Уровень риска вызова инструмента для политики одобрений.
///
/// Почему [unknown]: вид `ToolKind.other` (и отсутствующий вид), смена режима
/// `ToolKind.switchMode` и незнакомый вид (кодек сводит его к `other`) ничего
/// не гарантируют — так агент помечает, например, MCP-инструменты, а их
/// аннотации недоверенные; считать такой вызов «только чтением» нельзя
/// (design.md `add-provider-setup-ui` D27, Q32; `tolerate-unknown-tool-kind`
/// D5, D9; AGENTS.md §10).
///
/// Для чего: [unknown] по рангу между [readOnly] и [localWrite]
/// (`ApprovalPolicy.max`), а решение об одобрении принимают агент и
/// пользователь (клиент риск лишь классифицирует). Хосты показывают его отдельной
/// меткой («unknown risk»).
enum ApprovalRiskLevel {
  readOnly,
  unknown,
  localWrite,
  network,
  shell,
  destructive,
}

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

    /// Без классификации вид неизвестен — как у `kind` по умолчанию (`other`):
    /// безопасное значение по умолчанию требует явного одобрения (D27).
    @Default(ApprovalRiskLevel.unknown) ApprovalRiskLevel riskLevel,

    /// Агент пометил запрос `_meta.codelab.critical: true` (в запросе или
    /// в его `toolCall`): опасная команда, которую headless-политика
    /// `allow-all` не разрешает (design.md change `add-codelab-cli`, D9).
    @Default(false) bool critical,

    /// `_meta.codelab.subagent` `toolCall` запроса: спрашивает потомок, а не
    /// корень (D8, D43 п. 1). Хранится отдельно от
    /// `ToolCallRecord.subagentMeta`: тот же ключ в кадре вызова `agent`
    /// описывает сам вызов, и слияние сделало бы `exec` потомка «вызовом
    /// agent». Значения не проверяются (терпимый разбор — в
    /// `codelab_client_core`); `null` — запрос корня или стороннего агента.
    Map<String, Object?>? subagentRequester,
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

    /// Согласовано с `kind` по умолчанию (`other`) и `_riskForKind` (D27).
    @Default(ApprovalRiskLevel.unknown) ApprovalRiskLevel riskLevel,
    @Default([]) List<ToolCallContent> content,
    @Default([]) List<ToolCallLocation> locations,
    Map<String, Object?>? rawInput,
    Map<String, Object?>? rawOutput,

    /// The call was unfinished when the client sent `session/cancel`. ACP
    /// has no `cancelled` tool call status, so such a call is kept as
    /// [ToolCallStatus.failed] with this flag set.
    @Default(false) bool cancelledByClient,
    DateTime? startedAt,
    DateTime? completedAt,

    /// `_meta.codelab.subagent` вызова `agent`, накопленный по кадрам: первый
    /// `tool_call` даёт `{id, type}`, финальное обновление — `summary` или
    /// `failure` (design.md change `add-subagents-and-tasks`, D24, D28).
    /// Значения не проверяются: терпимый разбор — у kit
    /// (`codelab_client_core`); `null` — вызов без признака (сторонний агент).
    Map<String, Object?>? subagentMeta,

    /// `_meta.codelab.outcome` последнего кадра, где он был: признак агента,
    /// как закончился неуспешный вызов (`cancelled`, `rejected`,
    /// `interrupted`, неизвестное). Снимается итоговым `completed`; поздний
    /// кадр без признака его не стирает (spec acp-client-kit «Отмена по
    /// признаку агента», design.md D41 п. 1). Значение не проверяется:
    /// терпимый разбор — у kit.
    String? outcome,

    /// `_meta.codelab.parentToolCallId` кадров `tool_call`/`tool_call_update` —
    /// id вызова родителя на проводе (design.md change
    /// `add-subagents-and-tasks`, D21, D47 Т9); `null` — вызов корня.
    /// Поздний кадр без поля родителя не стирает его (как `outcome`).
    String? parentToolCallId,
  }) = _ToolCallRecord;

  factory ToolCallRecord.fromToolCall(
    ToolCall toolCall, {
    ApprovalRiskLevel riskLevel = ApprovalRiskLevel.unknown,
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
      subagentMeta: subagentMetaOf(toolCall.meta),
      outcome: toolCall.status == ToolCallStatus.completed
          ? null
          : outcomeOf(toolCall.meta),
      parentToolCallId: parentToolCallIdOf(toolCall.meta),
    );
  }
}

/// `_meta.codelab.subagent` кадра вызова как есть; `null` при любой неверной
/// форме (терпимый разбор, D28: отказа обработки обновления нет).
Map<String, Object?>? subagentMetaOf(Map<String, Object?>? meta) {
  final codelab = meta?['codelab'];
  final subagent = codelab is Map ? codelab['subagent'] : null;
  return subagent is Map ? subagent.cast<String, Object?>() : null;
}

/// `_meta.codelab.outcome` кадра; `null` при отсутствии или неверной форме
/// (терпимый разбор, как у [subagentMetaOf]).
String? outcomeOf(Map<String, Object?>? meta) {
  final codelab = meta?['codelab'];
  final outcome = codelab is Map ? codelab['outcome'] : null;
  return outcome is String ? outcome : null;
}

/// `_meta.codelab.parentToolCallId` кадра; `null` при отсутствии, неверной
/// форме и пустой строке (терпимый разбор, D21: отказа обработки нет).
String? parentToolCallIdOf(Map<String, Object?>? meta) {
  final codelab = meta?['codelab'];
  final parent = codelab is Map ? codelab['parentToolCallId'] : null;
  return parent is String && parent.isNotEmpty ? parent : null;
}

/// Накладывает [update] на [current]: ключи новых кадров дополняют прежние,
/// а не стирают (признак первого кадра переживает финальное обновление).
Map<String, Object?>? mergeSubagentMeta(
  Map<String, Object?>? current,
  Map<String, Object?>? update,
) => update == null ? current : {...?current, ...update};

enum SessionLifecycleStatus {
  idle,
  active,
  runningTurn,
  awaitingApproval,

  /// The active turn is [PromptTurnStatus.cancelling]; no new turn starts
  /// until the agent answers the cancelled `session/prompt`.
  cancellingTurn,
  failed,
}

/// Снимок сессии: статус, ходы, режимы и опции.
///
/// Диагностики здесь нет намеренно: единственный (ограниченный) буфер —
/// `AcpClientApplication.diagnostics`; копия в сессии росла без предела и
/// шумела в `sessionChanges` (OBS-004, D3 change `align-cross-cutting-specs`).
///
/// Как использовать: снимок иммутабелен; создаёт и заменяет его только
/// `AcpClientApplication` через `SessionStateMachine` (переходы — события
/// машины, а не `copyWith` снаружи). Хосты читают его через
/// `AcpClientApplication.sessionById` и подписываются на `sessionChanges`;
/// диагностику берут из `AcpClientApplication.diagnostics`.
@freezed
sealed class AcpSession with _$AcpSession {
  const AcpSession._();

  const factory AcpSession({
    required SessionId id,
    required String cwd,
    String? title,
    @Default(SessionLifecycleStatus.idle) SessionLifecycleStatus status,
    @Default([]) List<PromptTurn> turns,
    SessionModeState? modes,
    List<SessionConfigOption>? configOptions,

    /// Commands the agent has declared via `SessionUpdate.availableCommandsUpdate`.
    /// Session-scoped rather than turn-scoped — per ACP
    /// (`docs/protocols/acp/protocol/14-Slash Commands.md`), agents may send this "at
    /// any time during a session", including before any prompt turn exists.
    @Default([]) List<AvailableCommand> availableCommands,
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
