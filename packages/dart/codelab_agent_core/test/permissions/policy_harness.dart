import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/permissions/policy.dart';
import 'package:codelab_agent_core/testing.dart';

import '../tools/executor_harness.dart';
import '../tools/fake_tools.dart';

/// Tools of every tier for the policy tests.
List<AgentTool> tieredTools() => [
  FakeTool('r', tier: ToolTier.read),
  FakeTool('w', tier: ToolTier.write),
  FakeTool('n', tier: ToolTier.network),
  FakeTool('x', tier: ToolTier.exec),
];

/// A policy over an executor harness: [run] executes a call through the
/// policy hook.
final class PolicyHarness {
  PolicyHarness._(this.h, this.policy, this.logger);

  static Future<PolicyHarness> create({
    List<AgentTool>? tools,
    ModeId mode = ModeId.standard,
    PermissionMode? modeOverride,
    PermissionGate? gate,
    PolicyRules rules = const PolicyRules(),
    MemoryExecutionEnv? memory,
  }) async {
    final h = await ExecutorHarness.create(
      tools ?? tieredTools(),
      memory: memory,
    );
    return wrap(
      h,
      mode: mode,
      modeOverride: modeOverride,
      gate: gate,
      rules: rules,
    );
  }

  /// A policy over an existing harness.
  static Future<PolicyHarness> wrap(
    ExecutorHarness h, {
    ModeId mode = ModeId.standard,
    PermissionMode? modeOverride,
    PermissionGate? gate,
    PolicyRules rules = const PolicyRules(),
  }) async {
    final logger = RecordingLogger();
    final policy = PermissionPolicy(
      mode: mode,
      modeOverride: modeOverride,
      gate: gate,
      rules: rules,
      logger: logger,
    );
    return PolicyHarness._(h, policy, logger);
  }

  final ExecutorHarness h;
  final PermissionPolicy policy;
  final RecordingLogger logger;

  Future<ToolExecutionOutcome> run(
    String tool,
    Map<String, Object?> args, {
    String id = 'call_1',
    CancelToken? cancel,
  }) => h.run(
    tool,
    args,
    id: id,
    invocation: h.invocation(
      cancel: cancel,
      before: [policy.asHook(h.registry.lookup)],
    ),
  );
}

String deniedText(String tool, String reason) =>
    'Permission denied for $tool: $reason. Do not retry the same call; '
    'choose another approach or ask the user.';
