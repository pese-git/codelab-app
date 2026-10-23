import '../cancel/cancel_token.dart';
import '../loop/loop_config.dart';
import '../tools/agent_tool.dart';
import '../util/logger.dart';
import 'gate.dart';
import 'modes.dart';
import 'pattern.dart';

/// The permission policy of a session (`agent-core-architecture` §7.4): the
/// first `beforeToolCall` hook of every session (PERM-1). A denial is data
/// for the model, the turn goes on (PERM-7).

final class PolicyRules {
  const PolicyRules({
    this.toolPolicies = const {},
    this.denyPatterns = const {},
  });

  /// `permissions.tools` of the configuration.
  final Map<String, ToolPolicy> toolPolicies;

  /// Explicit denials of the configuration.
  final Set<PermissionKey> denyPatterns;
}

sealed class PolicyOutcome {
  const PolicyOutcome();
}

final class Allowed extends PolicyOutcome {
  const Allowed(this.rule);

  final String rule;
}

final class Denied extends PolicyOutcome {
  const Denied(this.reason);

  final String reason;
}

/// A critical pattern of a command (§7.6); `null` — none.
typedef CriticalFinder =
    String? Function(AgentTool tool, Map<String, Object?> args);

String? _noCritical(AgentTool tool, Map<String, Object?> args) => null;

final class PermissionPolicy {
  PermissionPolicy({
    required this.mode,
    this.modeOverride,
    this.gate,
    this.rules = const PolicyRules(),
    PermissionDecisionStore? decisions,
    required this.logger,
    this.findCritical = _noCritical,
  }) : decisions = decisions ?? PermissionDecisionStore();

  /// The mode of the session; a change applies to the next call.
  ModeId mode;

  /// Overrides the mode of the session (`autopilot` from a launch flag).
  final PermissionMode? modeOverride;
  final PermissionGate? gate;
  final PolicyRules rules;
  final PermissionDecisionStore decisions;
  final Logger logger;

  /// Critical patterns arrive in iteration 2 of the change (§7.6).
  final CriticalFinder findCritical;

  final _turnAllow = <String>{};
  final _turnDeny = <String>{};

  PermissionMode get effectiveMode => modeOverride ?? mode.permissionMode;

  /// Grants by tool name for the current turn only.
  void grantForTurn({
    Set<String> allow = const {},
    Set<String> deny = const {},
  }) {
    _turnAllow.addAll(allow);
    _turnDeny.addAll(deny);
  }

  /// Called at the start of every `prompt()` (PERM-8).
  void clearTurnGrants() {
    _turnAllow.clear();
    _turnDeny.clear();
  }

  /// The hook of the policy; [lookup] finds the tool of a call.
  BeforeToolCallHook asHook(
    AgentTool? Function(String name) lookup,
  ) => (call, args, ctx) async {
    final tool = lookup(call.name);
    if (tool == null) {
      return null;
    }
    return switch (await decide(tool, args, ctx)) {
      Allowed() => null,
      Denied(:final reason) => Block(
        'Permission denied for ${tool.name}: $reason. Do not retry the same '
        'call; choose another approach or ask the user.',
      ),
    };
  };

  Future<PolicyOutcome> decide(
    AgentTool tool,
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final outcome = await _decide(tool, args, ctx);
    if (outcome case Denied(:final reason)) {
      logger.log(
        LogLevel.info,
        'permission.denied',
        fields: {
          'tool_call_id': ctx.toolCallId,
          'tool': tool.name,
          'reason': reason,
        },
      );
    }
    return outcome;
  }

  Future<PolicyOutcome> _decide(
    AgentTool tool,
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final key = PermissionKey(
      tool.name,
      tool.permissionPattern(args, ctx.env.cwd),
    );
    final policy = rules.toolPolicies[tool.name];
    final tier = tool.tierOf(args);
    if (policy == ToolPolicy.deny || rules.denyPatterns.contains(key)) {
      return const Denied('denied by configuration');
    }
    if (decisions.rejectAlways.contains(key)) {
      return const Denied('previously rejected by the user');
    }
    if (_turnDeny.contains(tool.name)) {
      return const Denied('not allowed in this turn');
    }
    if (modeOverride == null && mode.deniedTiers.contains(tier)) {
      return const Denied('plan mode: changes are not allowed');
    }
    final effective = effectiveMode;
    if (findCritical(tool, args) case final label?) {
      if (effective == PermissionMode.autopilot) {
        return Denied('critical command blocked in autopilot: $label');
      }
      return _ask(
        tool,
        args,
        ctx,
        key,
        reason: 'critical command: $label',
        allowAlways: false,
      );
    }
    switch (policy) {
      case ToolPolicy.allow:
        return const Allowed('tool policy');
      case ToolPolicy.ask:
        return _ask(tool, args, ctx, key);
      case ToolPolicy.deny || null:
        break;
    }
    if (_turnAllow.contains(tool.name)) {
      return const Allowed('turn grant');
    }
    if (decisions.allowAlways.contains(key)) {
      return const Allowed('always allowed');
    }
    return switch (tierDecision(effective, tier)) {
      TierDecision.allow => const Allowed('mode'),
      TierDecision.ask => _ask(tool, args, ctx, key),
      TierDecision.deny => const Denied(
        'network access needs approval and autopilot has no approver',
      ),
    };
  }

  Future<PolicyOutcome> _ask(
    AgentTool tool,
    Map<String, Object?> args,
    ToolContext ctx,
    PermissionKey key, {
    String? reason,
    bool allowAlways = true,
  }) async {
    final gate = this.gate;
    if (gate == null) {
      return const Denied('no approval interface is available');
    }
    final offered = allowAlways && tool.offersAllowAlways(args);
    ToolPresentation presentation;
    try {
      presentation = await tool.present(args, ctx);
    } on Object {
      presentation = ToolPresentation(title: tool.name);
    }
    logger.log(
      LogLevel.debug,
      'permission.asked',
      fields: {
        'tool_call_id': ctx.toolCallId,
        'tool': tool.name,
        'tier': tool.tierOf(args).name,
        'critical': reason != null,
      },
    );
    final clock = ctx.services.clock;
    final started = clock.now();
    PermissionDecision decision;
    try {
      decision = await raceCancel(
        gate.request(
          PermissionRequest(
            toolCallId: ctx.toolCallId,
            tool: tool.name,
            kind: tool.kindOf(args),
            tier: tool.tierOf(args),
            title: presentation.title,
            rawInput: args,
            locations: presentation.locations,
            diffs: presentation.diffs,
            reason: reason,
            allowAlwaysOffered: offered,
          ),
          ctx.cancel,
        ),
        ctx.cancel,
      );
    } on CancelledException {
      decision = PermissionDecision.cancelled;
    } finally {
      ctx.services.approvalWait.add(clock.now().difference(started));
    }
    logger.log(
      LogLevel.debug,
      'permission.decided',
      fields: {'tool_call_id': ctx.toolCallId, 'decision': decision.name},
    );
    switch (decision) {
      case PermissionDecision.allowOnce:
        return const Allowed('user');
      case PermissionDecision.allowAlways:
        if (offered) {
          decisions.allowAlways.add(key);
        }
        return const Allowed('user');
      case PermissionDecision.rejectOnce:
        return const Denied('rejected by the user');
      case PermissionDecision.rejectAlways:
        decisions.rejectAlways.add(key);
        return const Denied('rejected by the user');
      case PermissionDecision.cancelled:
        return const Denied('permission request was cancelled');
    }
  }
}
