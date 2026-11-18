import 'package:codelab_ui/codelab_ui.dart';

import '../application/usage_budget.dart';
import '../application/usage_pane_data.dart';

/// Карточки панели Usage в модели `codelab_ui` (design.md change
/// `add-desktop-usage-pane`, D2 п. 2).
///
/// Почему здесь, а не в `codelab_ui`: кит ничего не знает о `UsagePaneData`
/// (`codelab_ui/AGENTS.md` §1); тон «неполная сумма» решает application
/// (`UsagePaneCard.approximate`), здесь он лишь переводится в `CodeLabTone`.
List<CodeLabUsageCard> usageCardsOf(UsagePaneData data) => [
  for (final card in data.cards)
    CodeLabUsageCard(
      id: card.id,
      title: card.title,
      value: card.value,
      detail: card.detail,
      tone: card.approximate ? CodeLabTone.warning : CodeLabTone.neutral,
    ),
];

/// Строки `Per turn` в модели кита: id шага — `<ход>-<индекс>` (ключ
/// `usage-step-<ход>-<индекс>`), модель шага — подсказка строки (D2 п. 4).
List<CodeLabUsageRow> usageTurnRowsOf(UsagePaneData data) => [
  for (final turn in data.turns)
    CodeLabUsageRow(
      id: '${turn.index}',
      label: turn.label,
      input: turn.input,
      output: turn.output,
      cost: turn.cost,
      running: turn.running,
      note: turn.subagents,
      children: [
        for (final step in turn.steps)
          CodeLabUsageRow(
            id: '${step.turn}-${step.index}',
            label: step.label,
            input: step.input,
            output: step.output,
            cost: step.cost,
            hint: step.model,
          ),
      ],
    ),
];

/// Строки `Per model`, включая `Subagents` и `Summaries` (D2 п. 5).
List<CodeLabUsageRow> usageModelRowsOf(UsagePaneData data) => [
  for (final model in data.models)
    CodeLabUsageRow(
      id: model.label,
      label: model.label,
      input: model.input,
      output: model.output,
      cost: model.cost,
      note: model.detail,
    ),
];

/// Блок `Turn budget` в модели кита на момент [now] (D9): тон переводится в
/// `CodeLabTone`, Time пересчитывает `usageBudgetRowsAt`. `null` — блока нет.
///
/// Почему здесь: кит не знает `UsageBudgetData` (`codelab_ui/AGENTS.md` §1);
/// решения (тон, заголовок, тик) приняты в application, здесь только перевод.
CodeLabUsageBudget? usageBudgetViewOf(
  UsagePaneData data, {
  required DateTime now,
}) {
  final budget = data.budget;
  if (budget == null) return null;
  return CodeLabUsageBudget(
    title: budget.title,
    rows: [
      for (final row in usageBudgetRowsAt(budget, now: now))
        CodeLabUsageBudgetRow(
          id: row.id,
          label: row.label,
          value: row.value,
          fill: row.fill,
          tone: switch (row.tone) {
            UsageBudgetTone.neutral => CodeLabTone.neutral,
            UsageBudgetTone.warning => CodeLabTone.warning,
            UsageBudgetTone.danger => CodeLabTone.danger,
          },
          hint: row.hint,
          note: row.note,
        ),
    ],
    footnote: usageBudgetFootnote,
  );
}
