import 'package:codelab_ui/codelab_ui.dart';

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
