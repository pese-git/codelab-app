import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/env/bounded_env.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:codelab_agent_core/src/tools/misuse.dart';
import 'package:codelab_agent_core/src/tools/plan_service.dart';
import 'package:codelab_agent_core/src/tools/registry.dart';
import 'package:codelab_agent_core/testing.dart';

const session = SessionId('sess-1');

/// An executor over a bounded [MemoryExecutionEnv] that records events.
final class ExecutorHarness {
  ExecutorHarness._(
    this.env,
    this.registry,
    this.executor,
    this.clock,
    this.plan,
  );

  static Future<ExecutorHarness> create(
    List<AgentTool> tools, {
    MemoryExecutionEnv? memory,
    ExecutionEnv? base,
  }) async {
    final clock = FakeClock();
    base ??= memory ?? MemoryExecutionEnv(cwd: '/proj', clock: clock);
    final env = await BoundedEnv.wrap(base, base.cwd);
    final registry = ToolRegistry();
    tools.forEach(registry.register);
    final plan = PlanService();
    final executor = ToolCallExecutor(
      registry: registry,
      env: env,
      services: ToolServices(
        clock: clock,
        logger: RecordingLogger(),
        plan: plan,
      ),
    );
    final h = ExecutorHarness._(env, registry, executor, clock, plan);
    // План публикуется в ту же запись событий, что и события вызова.
    plan.publish = (entries) =>
        h.events.add(PlanUpdated(session, entries: entries));
    return h;
  }

  final ExecutionEnv env;
  final ToolRegistry registry;
  final ToolCallExecutor executor;
  final FakeClock clock;
  final PlanService plan;
  final events = <AgentEvent>[];

  ToolInvocation invocation({
    CancelToken? cancel,
    List<String>? stepTools,
    List<BeforeToolCallHook> before = const [],
    List<AfterToolCallHook> after = const [],
    bool supportsImages = false,
    MisuseBreaker? misuse,
  }) => ToolInvocation(
    sessionId: session,
    cancel: cancel ?? CancelToken.none,
    stepTools: stepTools ?? [for (final t in registry.tools) t.name],
    emit: events.add,
    beforeToolCall: before,
    afterToolCall: after,
    supportsImages: supportsImages,
    misuse: misuse,
  );

  Future<ToolExecutionOutcome> run(
    String name,
    Map<String, Object?> args, {
    String id = 'call_1',
    ToolInvocation? invocation,
  }) async {
    final handle = await executor.announce(
      ToolCall(id: id, name: name, arguments: args),
      invocation ?? this.invocation(),
    );
    return executor.complete(handle);
  }
}

String textOf(ToolExecutionOutcome outcome) => outcome.message.content
    .whereType<TextContent>()
    .map((b) => b.text)
    .join('\n');
