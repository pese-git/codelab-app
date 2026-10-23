import '../cancel/cancel_token.dart';
import '../env/execution_env.dart';
import '../llm/messages.dart';
import '../llm/model_ref.dart';
import '../llm/usage.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../loop/turn_budget.dart';
import '../permissions/gate.dart';
import '../permissions/modes.dart';
import '../util/logger.dart';

/// The public API of a session (`agent-core-architecture` §5.6, the part of
/// stage 2 — design.md, D4). Later stages add members without changing
/// these.
abstract interface class AgentSession {
  SessionId get id;

  /// Broadcast; a late subscriber gets the events of the current turn from
  /// its start.
  Stream<AgentEvent> get events;

  ModeId get mode;

  /// Runs a turn; a second call during a turn is a [StateError] (LOOP-10).
  Future<TurnResult> prompt(List<ContentBlock> content, {CancelToken? cancel});

  Future<void> cancel();

  /// Applies from the next tool call; emits [ModeChanged].
  Future<void> setMode(ModeId mode);
}

/// The fields of `TurnEnded`.
final class TurnResult {
  const TurnResult({
    required this.reason,
    required this.usage,
    this.budgetExceeded,
    this.held,
  });

  final TurnEndReason reason;
  final Usage usage;
  final BudgetLimit? budgetExceeded;
  final String? held;
}

/// Ports of one session; each falls back to `AgentCoreServices`.
final class SessionHostPorts {
  const SessionHostPorts({this.env, this.gate, this.logger});

  final ExecutionEnv? env;
  final PermissionGate? gate;
  final Logger? logger;
}

final class SessionSpec {
  SessionSpec({
    required this.cwd,
    this.mode,
    this.model,
    this.ports = const SessionHostPorts(),
    List<BeforeToolCallHook> extraBeforeToolCall = const [],
    List<AfterToolCallHook> extraAfterToolCall = const [],
  }) : extraBeforeToolCall = List.unmodifiable(extraBeforeToolCall),
       extraAfterToolCall = List.unmodifiable(extraAfterToolCall);

  /// The absolute root of the session.
  final String cwd;

  /// `null` — the configuration, then the profile (§10.5).
  final ModeId? mode;

  /// `null` — the default model of the configuration.
  final ModelRef? model;
  final SessionHostPorts ports;

  /// Host hooks; they go last in `beforeToolCall` (§10.7, step 6).
  final List<BeforeToolCallHook> extraBeforeToolCall;

  /// Host hooks; they go first in `afterToolCall`.
  final List<AfterToolCallHook> extraAfterToolCall;
}

final class SessionSummary {
  const SessionSummary({required this.id, required this.cwd});

  final SessionId id;
  final String cwd;
}
