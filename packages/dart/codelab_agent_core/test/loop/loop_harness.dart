import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/env/bounded_env.dart';
import 'package:codelab_agent_core/src/loop/agent_loop.dart';
import 'package:codelab_agent_core/src/loop/loop_config.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:codelab_agent_core/src/tools/registry.dart';
import 'package:codelab_agent_core/testing.dart';

import '../support/models.dart';

const session = SessionId('sess-1');
final time = DateTime.utc(2026);

UserMessage user(String text) =>
    UserMessage([TextContent(text)], timestamp: time);

Map<String, Object?> script(List<Map<String, Object?>> steps) => {
  'steps': steps,
};

Map<String, Object?> textStep(String text) => {
  'reply': [
    {'text': text},
  ],
};

Map<String, Object?> callStep(
  List<(String id, String name, Map<String, Object?> args)> calls,
) => {
  'reply': [
    for (final (id, name, args) in calls)
      {
        'toolCall': {'id': id, 'name': name, 'arguments': args},
      },
  ],
};

/// Everything a loop test needs: the scripted model, tools over a bounded
/// memory env, and a config.
final class LoopHarness {
  LoopHarness._(this.clock, this.env, this.tools, this.executor, this.stream);

  static Future<LoopHarness> create({
    List<AgentTool> tools = const [],
    StreamFunction? stream,
    Map<String, Object?>? llm,
  }) async {
    final clock = FakeClock();
    final memory = MemoryExecutionEnv(cwd: '/proj', clock: clock);
    final env = await BoundedEnv.wrap(memory, '/proj');
    final registry = ToolRegistry();
    tools.forEach(registry.register);
    final executor = ToolCallExecutor(
      registry: registry,
      env: env,
      services: ToolServices(clock: clock, logger: RecordingLogger()),
    );
    final scripted = llm == null
        ? null
        : ScriptedStreamFunction.fromJson(llm, clock: clock);
    final h = LoopHarness._(
      clock,
      memory,
      tools,
      executor,
      stream ?? scripted!.call,
    );
    h.scripted = scripted;
    return h;
  }

  final FakeClock clock;
  final MemoryExecutionEnv env;
  final List<AgentTool> tools;
  final ToolCallExecutor executor;
  final StreamFunction stream;
  ScriptedStreamFunction? scripted;
  final events = <AgentEvent>[];

  AgentLoopConfig config({
    TurnBudget budget = const TurnBudget(),
    TransformContextHook? transformContext,
    List<BeforeToolCallHook> beforeToolCall = const [],
    List<AfterToolCallHook> afterToolCall = const [],
    PrepareNextStepHook? prepareNextStep,
  }) => AgentLoopConfig(
    sessionId: session,
    model: testModel,
    stream: stream,
    executor: executor,
    clock: clock,
    ids: SequentialIdGenerator(prefix: 'turn-'),
    budget: budget,
    transformContext: transformContext,
    beforeToolCall: beforeToolCall,
    afterToolCall: afterToolCall,
    prepareNextStep: prepareNextStep,
  );

  Future<List<Message>> run(
    List<Message> prompts, {
    List<Message> history = const [],
    AgentLoopConfig? config,
    CancelToken? cancel,
  }) => runAgentLoop(
    prompts: prompts,
    context: LoopContext(
      systemPrompt: 'You are CodeLab.',
      messages: history,
      tools: tools,
    ),
    config: config ?? this.config(),
    emit: events.add,
    cancel: cancel ?? CancelToken.none,
  );

  List<String> get trace => [for (final e in events) describe(e)];
}

String _role(Message m) => switch (m) {
  UserMessage() => 'user',
  AssistantMessage(:final stopReason) => 'assistant ${stopReason.name}',
  ToolResultMessage(:final toolCallId) => 'toolResult $toolCallId',
};

/// A short stable description of an event for sequence assertions.
String describe(AgentEvent e) => switch (e) {
  TurnStarted() => 'TurnStarted',
  StepStarted(:final stepIndex) => 'StepStarted($stepIndex)',
  ModelRequested() => 'ModelRequested',
  MessageStarted(:final message) =>
    'MessageStarted(${_role(message).split(' ').first}'
        '${message is ToolResultMessage ? ' ${message.toolCallId}' : ''})',
  MessageDelta(:final delta) => 'MessageDelta($delta)',
  ThoughtDelta(:final delta) => 'ThoughtDelta($delta)',
  MessageEnded(:final message) => 'MessageEnded(${_role(message)})',
  ToolCallStarted(:final toolCallId) => 'ToolCallStarted($toolCallId)',
  ToolCallProgress(:final toolCallId) => 'ToolCallProgress($toolCallId)',
  ToolCallFinished(:final toolCallId, :final outcome) =>
    'ToolCallFinished($toolCallId ${outcome.name})',
  ToolPairingRepaired() => 'ToolPairingRepaired',
  StepEnded(:final result) => 'StepEnded(${result.stepIndex})',
  PlanUpdated() => 'PlanUpdated',
  ModeChanged(:final mode) => 'ModeChanged(${mode.value})',
  AgentError(:final cls, :final errorClass) =>
    'AgentError(${cls.name}${errorClass == null ? '' : ' ${errorClass.name}'})',
  TurnEnded(:final reason, :final budgetExceeded) =>
    'TurnEnded(${reason.name}${budgetExceeded == null ? '' : ' ${budgetExceeded.name}'})',
};
