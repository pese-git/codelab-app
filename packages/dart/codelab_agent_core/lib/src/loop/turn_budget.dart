/// Limits of one turn (`agent-core-architecture` §5.2), checked only at a
/// step boundary: after `StepEnded` and before the next model request
/// (LOOP-12).
final class TurnBudget {
  const TurnBudget({
    this.maxSteps = 50,
    this.maxTokens,
    this.maxCost,
    this.maxDuration,
  });

  /// Model steps per turn (ACP `max_turn_requests`).
  final int maxSteps;

  /// Sum of input and output tokens of every step.
  final int? maxTokens;

  /// Cost by `ModelCost`; not checked while prices are unknown.
  final double? maxCost;

  /// Time of the turn on the host clock, without waiting for approval.
  final Duration? maxDuration;
}

/// The limit that stopped a turn; `deadline` is set after MVP (§17.12.5).
enum BudgetLimit { steps, tokens, cost, duration, deadline }

/// ЗАГЛУШКА задачи 2.1 (change `add-desktop-usage-pane`, D8): только для
/// компиляции красных тестов; реализацию и документацию даёт задача 2.2.
final class BudgetProgress {
  const BudgetProgress({
    required this.limits,
    required this.steps,
    required this.tokens,
    required this.cost,
    required this.active,
  });

  final TurnBudget limits;
  final int steps;
  final int tokens;
  final double? cost;
  final Duration active;
}
