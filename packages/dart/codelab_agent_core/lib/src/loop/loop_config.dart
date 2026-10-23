import 'dart:async';

import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../llm/model_ref.dart';
import '../llm/stream_function.dart';
import '../llm/usage.dart';
import '../tools/agent_tool.dart';
import '../tools/executor.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import 'agent_events.dart';
import 'turn_budget.dart';

/// Configuration and hooks of a turn (`agent-core-architecture` §5.2).

/// The loop awaits every emit (LOOP-2).
typedef AgentEventSink = FutureOr<void> Function(AgentEvent event);

/// Before every model request; changes only the payload (LOOP-7).
typedef TransformContextHook =
    Future<List<Message>> Function(List<Message> messages, CancelToken cancel);

/// After validation, before execution; the first [Block] stops the chain.
/// The first hook is always the permission check (PERM-1).
typedef BeforeToolCallHook =
    Future<Block?> Function(
      ToolCall call,
      Map<String, Object?> args,
      ToolContext ctx,
    );

/// After execution, before `ToolCallFinished`; overrides by field.
typedef AfterToolCallHook =
    Future<ResultOverride?> Function(
      ToolCall call,
      ToolExecutionResult result,
      bool isError,
    );

/// After `StepEnded`: replace the context or the model of the next step.
typedef PrepareNextStepHook = Future<StepUpdate?> Function(StepResult step);

final class Block {
  const Block(this.reason, {this.outcome = ToolOutcome.rejected});

  /// The text of the error result for the model.
  final String reason;
  final ToolOutcome outcome;
}

final class ResultOverride {
  const ResultOverride({this.content, this.isError});

  final List<ContentBlock>? content;
  final bool? isError;
}

final class StepUpdate {
  const StepUpdate({this.context, this.model});

  final LoopContext? context;
  final ModelRef? model;
}

final class StepResult {
  StepResult({
    required this.stepIndex,
    required this.response,
    required List<ToolResultMessage> results,
    required this.usage,
  }) : results = List.unmodifiable(results);

  final int stepIndex;
  final AssistantMessage response;

  /// In the order of the calls of [response].
  final List<ToolResultMessage> results;
  final Usage usage;
}

final class LoopContext {
  LoopContext({
    required this.systemPrompt,
    required List<Message> messages,
    required List<AgentTool> tools,
  }) : messages = List.unmodifiable(messages),
       tools = List.unmodifiable(tools);

  final String systemPrompt;
  final List<Message> messages;

  /// Schemas of a step are `tools.map(toSchema)`.
  final List<AgentTool> tools;
}

final class AgentLoopConfig {
  AgentLoopConfig({
    required this.sessionId,
    required this.model,
    required this.stream,
    required this.executor,
    required this.clock,
    required this.ids,
    this.budget = const TurnBudget(),
    this.transformContext,
    List<BeforeToolCallHook> beforeToolCall = const [],
    List<AfterToolCallHook> afterToolCall = const [],
    this.prepareNextStep,
  }) : beforeToolCall = List.unmodifiable(beforeToolCall),
       afterToolCall = List.unmodifiable(afterToolCall);

  final SessionId sessionId;
  final ModelRef model;
  final StreamFunction stream;

  /// The single execution point (§6.3.1).
  final ToolExecutor executor;
  final Clock clock;
  final IdGenerator ids;
  final TurnBudget budget;
  final TransformContextHook? transformContext;

  /// `[0]` is always the permission check (PERM-1).
  final List<BeforeToolCallHook> beforeToolCall;
  final List<AfterToolCallHook> afterToolCall;
  final PrepareNextStepHook? prepareNextStep;

  AgentLoopConfig copyWith({ModelRef? model}) => AgentLoopConfig(
    sessionId: sessionId,
    model: model ?? this.model,
    stream: stream,
    executor: executor,
    clock: clock,
    ids: ids,
    budget: budget,
    transformContext: transformContext,
    beforeToolCall: beforeToolCall,
    afterToolCall: afterToolCall,
    prepareNextStep: prepareNextStep,
  );
}
