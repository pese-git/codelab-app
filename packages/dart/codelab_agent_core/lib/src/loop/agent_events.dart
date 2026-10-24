import '../llm/errors.dart';
import '../llm/messages.dart';
import '../llm/model_ref.dart';
import '../llm/usage.dart';
import '../permissions/modes.dart';
import '../tools/agent_tool.dart';
import '../tools/pairing.dart';
import 'loop_config.dart';
import 'turn_budget.dart';

/// Events of a turn (`agent-core-architecture` §5.3): a closed hierarchy;
/// later stages add branches without changing these. The loop waits for
/// every emit (LOOP-2), and [TurnEnded] is the last event of a turn,
/// emitted exactly once (LOOP-1).

extension type const SessionId(String value) {}

extension type const TurnId(String value) {}

sealed class AgentEvent {
  const AgentEvent(this.sessionId);

  final SessionId sessionId;
}

/// The first event of a turn.
final class TurnStarted extends AgentEvent {
  TurnStarted(
    super.sessionId, {
    required this.turnId,
    required List<Message> input,
  }) : input = List.unmodifiable(input);

  final TurnId turnId;
  final List<Message> input;
}

/// Before every model request; [stepIndex] starts at 0.
final class StepStarted extends AgentEvent {
  const StepStarted(super.sessionId, {required this.stepIndex});

  final int stepIndex;
}

/// Right before the `StreamFunction` call (diagnostics).
final class ModelRequested extends AgentEvent {
  const ModelRequested(
    super.sessionId, {
    required this.model,
    required this.estimatedTokens,
    required this.messageCount,
  });

  final ModelRef model;

  /// 0 while the core has no estimate (stage 3).
  final int estimatedTokens;
  final int messageCount;
}

/// A message entered the transcript: a prompt, the first snapshot of an
/// answer, a tool result or a service message of the loop.
final class MessageStarted extends AgentEvent {
  const MessageStarted(super.sessionId, {required this.message, this.origin});

  final Message message;

  /// A service message of the loop (§5.4.1); `null` — a prompt or an
  /// answer.
  final MessageOrigin? origin;
}

final class MessageDelta extends AgentEvent {
  const MessageDelta(
    super.sessionId, {
    required this.delta,
    required this.partial,
  });

  final String delta;
  final AssistantMessage partial;
}

final class ThoughtDelta extends AgentEvent {
  const ThoughtDelta(
    super.sessionId, {
    required this.delta,
    required this.partial,
  });

  final String delta;
  final AssistantMessage partial;
}

/// The message is complete — the save point of the host.
final class MessageEnded extends AgentEvent {
  const MessageEnded(super.sessionId, {required this.message});

  final Message message;
}

/// A call entered the single execution point.
final class ToolCallStarted extends AgentEvent {
  ToolCallStarted(
    super.sessionId, {
    required this.toolCallId,
    required this.tool,
    required this.kind,
    required this.title,
    required Map<String, Object?> input,
    List<Location> locations = const [],
  }) : input = Map.unmodifiable(input),
       locations = List.unmodifiable(locations);

  final String toolCallId, tool, title;
  final ToolKind kind;

  /// Arguments as the model sent them.
  final Map<String, Object?> input;
  final List<Location> locations;
}

/// A partial result through `onUpdate` or `onTerminal`.
final class ToolCallProgress extends AgentEvent {
  ToolCallProgress(
    super.sessionId, {
    required this.toolCallId,
    required List<ToolCallContent> content,
  }) : content = List.unmodifiable(content);

  final String toolCallId;
  final List<ToolCallContent> content;
}

final class ToolCallFinished extends AgentEvent {
  ToolCallFinished(
    super.sessionId, {
    required this.toolCallId,
    required this.outcome,
    required List<ContentBlock> content,
    List<FileDiff> diffs = const [],
    this.interrupted = false,
  }) : content = List.unmodifiable(content),
       diffs = List.unmodifiable(diffs);

  final String toolCallId;
  final ToolOutcome outcome;
  final List<ContentBlock> content;

  /// One per changed file; empty — no edits.
  final List<FileDiff> diffs;

  /// Только у реплея: синтетический результат прерванного вызова (§8.8).
  /// Домен знает четыре исхода, а прерванный вызов показывается как
  /// `failed` с этим признаком — ACP-проекция этапа 4 ставит по нему
  /// `_meta.codelab.outcome: "interrupted"`.
  final bool interrupted;
}

/// The payload of a request needed a pairing repair (§6.3.3).
final class ToolPairingRepaired extends AgentEvent {
  const ToolPairingRepaired(super.sessionId, {required this.report});

  final PairingReport report;
}

final class StepEnded extends AgentEvent {
  const StepEnded(super.sessionId, {required this.result});

  final StepResult result;
}

enum PlanPriority { high, medium, low }

enum PlanStatus { pending, inProgress, completed }

final class PlanEntry {
  const PlanEntry({
    required this.content,
    required this.priority,
    required this.status,
  });

  final String content;
  final PlanPriority priority;
  final PlanStatus status;
}

/// `update_plan` replaced the plan.
final class PlanUpdated extends AgentEvent {
  PlanUpdated(super.sessionId, {required List<PlanEntry> entries})
    : entries = List.unmodifiable(entries);

  final List<PlanEntry> entries;
}

/// The mode of the session changed (level of `AgentSession`); it applies
/// from the next tool call.
final class ModeChanged extends AgentEvent {
  const ModeChanged(super.sessionId, {required this.mode});

  final ModeId mode;
}

enum AgentErrorClass { provider, fallback, compaction, hook, storage }

/// A failure or a retry: provider, fallback, compaction, hook, journal.
final class AgentError extends AgentEvent {
  const AgentError(
    super.sessionId, {
    required this.cls,
    required this.message,
    this.errorClass,
    this.retrying = false,
  });

  final AgentErrorClass cls;

  /// Only with [AgentErrorClass.provider].
  final LlmErrorClass? errorClass;
  final String message;
  final bool retrying;
}

/// Сжатие записано в журнал (§9.8): запись `compaction` пишется до
/// события, событие её подтверждает.
final class ContextCompacted extends AgentEvent {
  const ContextCompacted(
    super.sessionId, {
    required this.tokensBefore,
    required this.tokensAfter,
  });

  final int tokensBefore, tokensAfter;
}

/// Заголовок сессии записан в журнал (событие уровня `AgentSession`,
/// §8.3, §8.10).
///
/// Почему событие, а не только запись: ACP-проекция этапа 4 отправляет по
/// нему `session_info_update`, а клиенту не нужно читать журнал.
final class SessionTitleChanged extends AgentEvent {
  const SessionTitleChanged(
    super.sessionId, {
    required this.title,
    required this.updatedAt,
  });

  final String title;
  final DateTime updatedAt;
}

enum TurnEndReason { completed, maxTokens, refused, cancelled, failed }

/// The last event of a turn.
final class TurnEnded extends AgentEvent {
  const TurnEnded(
    super.sessionId, {
    required this.reason,
    required this.usage,
    this.budgetExceeded,
    this.held,
  });

  final TurnEndReason reason;

  /// Sum of the steps.
  final Usage usage;
  final BudgetLimit? budgetExceeded;

  /// The final-response hook held the answer (after MVP, §17.12.4).
  final String? held;
}

/// Domain outcome of a call; ACP has no `cancelled` and `rejected` — the
/// projection is in §13.
enum ToolOutcome { completed, failed, cancelled, rejected }

/// Who wrote a service message of the loop (§5.4.1).
sealed class MessageOrigin {
  const MessageOrigin();
}

enum LoopNudgeReason { emptyResponse, deadline }

/// A user message written by the loop, not by a human.
final class LoopNudgeOrigin extends MessageOrigin {
  const LoopNudgeOrigin(this.reason, this.attempt);

  final LoopNudgeReason reason;

  /// Number of the retry, from 1.
  final int attempt;
}

/// A synthetic assistant note of the loop.
final class LoopNoteOrigin extends MessageOrigin {
  const LoopNoteOrigin(this.reason);

  final LoopNudgeReason reason;
}
