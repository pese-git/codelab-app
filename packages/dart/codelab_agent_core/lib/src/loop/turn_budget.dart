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

/// Прогресс бюджета хода на границе шага (`agent-core-architecture` §5.2;
/// change `add-desktop-usage-pane`, D8).
///
/// Почему: клиент не может восстановить то, что проверяет цикл (usage
/// потомков, кэш, ожидание одобрения, модель без цен), поэтому цифры считает
/// сам цикл — и тем же значением решает остановку: [exceeded] — единственное
/// место сравнения с лимитами (LOOP-12), второго подсчёта нет.
///
/// Для чего: `StepEnded.budget` и `TurnEnded.budget` показывают, сколько
/// израсходовано относительно [limits]; адаптер решает, слать ли их клиенту.
///
/// Как использовать: создаёт только `AgentLoop`; читатели берут поля из
/// событий. [tokens] — `input + output` хода с потомками, без кэша; [cost] —
/// `null`, пока у модели нет цен (лимит стоимости тогда не проверяется);
/// [active] — время хода на часах хоста без ожидания одобрения.
final class BudgetProgress {
  const BudgetProgress({
    required this.limits,
    required this.steps,
    required this.tokens,
    required this.cost,
    required this.active,
  });

  /// Лимиты хода, по которым считалась проверка.
  final TurnBudget limits;

  /// Завершённые шаги хода (сравнивается с `limits.maxSteps`).
  final int steps;

  /// Токены `input + output` хода с потомками, без кэша.
  final int tokens;

  /// Стоимость хода; `null` — цен модели нет.
  final double? cost;

  /// Активное время хода без ожидания одобрения.
  final Duration active;

  /// Первый исчерпанный лимит или `null`. Порядок проверки — как в LOOP-12:
  /// шаги, токены, стоимость, время.
  BudgetLimit? get exceeded {
    if (steps >= limits.maxSteps) {
      return BudgetLimit.steps;
    }
    if (limits.maxTokens case final max? when tokens >= max) {
      return BudgetLimit.tokens;
    }
    if (limits.maxCost case final max? when cost != null && cost! >= max) {
      return BudgetLimit.cost;
    }
    if (limits.maxDuration case final max? when active >= max) {
      return BudgetLimit.duration;
    }
    return null;
  }
}
