import '../env/execution_env.dart';
import '../llm/model_ref.dart';
import '../loop/turn_budget.dart';
import '../permissions/gate.dart';
import '../permissions/modes.dart';
import '../permissions/policy.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import '../util/logger.dart';

/// Everything external the host passes to the core (`agent-core-architecture`
/// §10.3); later stages add services.
final class AgentCoreServices {
  const AgentCoreServices({
    required this.baseEnv,
    required this.logger,
    required this.clock,
    required this.ids,
    this.gate,
  });

  /// Local | ACP client | memory (tests).
  final ExecutionEnv baseEnv;

  /// `null` → `interactiveApproval` is off.
  final PermissionGate? gate;
  final Logger logger;
  final Clock clock;
  final IdGenerator ids;
}

/// The permissions part of the configuration.
final class PermissionsConfig {
  const PermissionsConfig({
    this.mode,
    this.modeOverride,
    this.rules = const PolicyRules(),
  });

  /// Replaces the default mode of the profile (§10.5).
  final ModeId? mode;

  /// `autopilot` and other launch-flag modes (design.md of
  /// `add-agent-core-permission-policy`, D3).
  final PermissionMode? modeOverride;
  final PolicyRules rules;
}

/// The validated configuration of the core; loading from files arrives at
/// stages 4 and 8 (design.md, D12).
final class CoreConfig {
  const CoreConfig({
    required this.defaultModel,
    this.permissions = const PermissionsConfig(),
    this.budget = const TurnBudget(),
  });

  final ModelRef defaultModel;
  final PermissionsConfig permissions;
  final TurnBudget budget;
}
