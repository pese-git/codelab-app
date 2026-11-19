import 'package:codelab_ui/codelab_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../workbench/application/ui_mappers.dart'
    show partialReasonTextOf, toolKindLabelOf;
import '../application/usage_budget.dart';
import '../application/usage_pane_data.dart';
import '../application/usage_step_label.dart';

/// Карточки панели Usage в модели `codelab_ui` (design.md change
/// `add-desktop-usage-pane`, D2 п. 2).
///
/// Почему здесь, а не в `codelab_ui`: кит ничего не знает о `UsagePaneData`
/// (`codelab_ui/AGENTS.md` §1); тон «неполная сумма» решает application
/// (`UsagePaneCard.approximate`), здесь он лишь переводится в `CodeLabTone`.
///
/// Тексты карточек (заголовок по `id`, вторая строка по значению) собираются
/// здесь по каталогу [l10n] (`add-desktop-localization`, D5 п. 4): значения
/// `application` языка не знают, а числа в них — формат ядра клиента (D8).
List<CodeLabUsageCard> usageCardsOf(
  UsagePaneData data,
  AppLocalizations l10n,
) => [
  for (final card in data.cards)
    CodeLabUsageCard(
      id: card.id,
      title: switch (card.kind) {
        UsageCardKind.input => l10n.usageCardInput,
        UsageCardKind.output => l10n.usageCardOutput,
        UsageCardKind.cost => l10n.usageCardCost,
        UsageCardKind.turns => l10n.usageCardTurns,
      },
      value: card.value,
      detail: switch (card.detail) {
        null => null,
        UsageCardCache(:final read, :final write) => l10n.usageDetailCache(
          read,
          write,
        ),
        UsageCardReasoning(:final count) => l10n.usageDetailReasoning(count),
        UsageCardPartialReasons(:final reasons) =>
          reasons.map((reason) => partialReasonTextOf(reason, l10n)).join(', '),
        UsageCardNoUsageYet() => l10n.usageDetailNoUsageYet,
        UsageCardPriceUnknown() => l10n.usageDetailPriceUnknown,
        UsageCardAverageSteps(:final average) => l10n.usageDetailAverageSteps(
          average,
        ),
      },
      tone: card.approximate ? CodeLabTone.warning : CodeLabTone.neutral,
    ),
];

/// Название шага журнала на языке [l10n]: вид вызова называется так же, как
/// строка ленты (`toolKindLabelOf`), заголовок вида `other` — от агента и не
/// переводится (D7).
String usageStepTitleText(UsageStepTitle title, AppLocalizations l10n) =>
    switch (title) {
      UsageStepReply() => l10n.usageStepReply,
      UsageStepToolCalls(:final count) => l10n.usageStepToolCalls(count),
      UsageStepCall(:final kind, :final label, :final detail, :final more) => [
        '${toolKindLabelOf(kind, label, l10n)} $detail'.trim(),
        if (more > 0) '+$more',
      ].join(' '),
    };

/// Подпись хода `N · “title”` (ru — `N · «title»`) или `N` без заголовка.
///
/// Почему здесь: типографские кавычки зависят от языка, а application отдаёт
/// только индекс и заголовок (D5 п. 2/4).
String usageTurnLabelText(int index, String? title, AppLocalizations l10n) =>
    title == null || title.isEmpty
    ? '$index'
    : l10n.usageTurnLabel(index, title);

/// Строки `Per turn` в модели кита: id шага — `<ход>-<индекс>` (ключ
/// `usage-step-<ход>-<индекс>`), модель шага — подсказка строки (D2 п. 4).
List<CodeLabUsageRow> usageTurnRowsOf(
  UsagePaneData data,
  AppLocalizations l10n,
) => [
  for (final turn in data.turns)
    CodeLabUsageRow(
      id: '${turn.index}',
      label: usageTurnLabelText(turn.index, turn.title, l10n),
      input: turn.input,
      output: turn.output,
      cost: turn.cost,
      running: turn.running,
      note: turn.subagentRuns == null
          ? null
          : l10n.usageTurnSubagents(turn.subagentRuns!),
      children: [
        for (final step in turn.steps)
          CodeLabUsageRow(
            id: '${step.turn}-${step.index}',
            label: l10n.usageStepLabel(
              step.index + 1,
              usageStepTitleText(step.title, l10n),
            ),
            input: step.input,
            output: step.output,
            cost: step.cost,
            hint: step.model,
          ),
      ],
    ),
];

/// Строки `Per model`, включая `Subagents` и `Summaries` (D2 п. 5). Названия
/// групп и подписи их счётчиков — тексты app по каталогу [l10n]; у моделей
/// название — данные агента.
List<CodeLabUsageRow> usageModelRowsOf(
  UsagePaneData data,
  AppLocalizations l10n,
) => [
  for (final model in data.models)
    () {
      final label = switch (model.kind) {
        UsageModelKind.model => model.label,
        UsageModelKind.subagents => l10n.usageModelSubagents,
        UsageModelKind.summaries => l10n.usageModelSummaries,
      };
      return CodeLabUsageRow(
        // Идентификатор строки — английский: от языка интерфейса не зависит
        // (ключи тестов и состояние раскрытия).
        id: switch (model.kind) {
          UsageModelKind.model => model.label,
          UsageModelKind.subagents => 'Subagents',
          UsageModelKind.summaries => 'Summaries',
        },
        label: label,
        input: model.input,
        output: model.output,
        cost: model.cost,
        note: switch (model.kind) {
          UsageModelKind.model => null,
          UsageModelKind.subagents => l10n.usageModelRuns(model.count ?? 0),
          UsageModelKind.summaries => '${model.count ?? 0}',
        },
      );
    }(),
];

/// Блок `Turn budget` в модели кита на момент [now] (D9): тон переводится в
/// `CodeLabTone`, Time пересчитывает `usageBudgetRowsAt`. `null` — блока нет.
///
/// Почему здесь: кит не знает `UsageBudgetData` (`codelab_ui/AGENTS.md` §1);
/// решения (тон, заголовок, тик) приняты в application, здесь только перевод.
CodeLabUsageBudget? usageBudgetViewOf(
  UsagePaneData data, {
  required DateTime now,
  required AppLocalizations l10n,
}) {
  final budget = data.budget;
  if (budget == null) return null;
  return CodeLabUsageBudget(
    title: switch (budget.title) {
      UsageBudgetTitle.thisTurn => l10n.usageBudgetThisTurn,
      UsageBudgetTitle.lastTurn => l10n.usageBudgetLastTurn,
    },
    rows: [
      for (final row in usageBudgetRowsAt(budget, now: now))
        CodeLabUsageBudgetRow(
          id: row.id,
          label: switch (row.kind) {
            UsageBudgetRowKind.steps => l10n.usageBudgetSteps,
            UsageBudgetRowKind.tokens => l10n.usageBudgetTokens,
            UsageBudgetRowKind.cost => l10n.usageCardCost,
            UsageBudgetRowKind.time => l10n.usageBudgetTime,
          },
          value: row.value,
          fill: row.fill,
          tone: switch (row.tone) {
            UsageBudgetTone.neutral => CodeLabTone.neutral,
            UsageBudgetTone.warning => CodeLabTone.warning,
            UsageBudgetTone.danger => CodeLabTone.danger,
          },
          hint: row.kind == UsageBudgetRowKind.tokens
              ? l10n.usageBudgetTokensHint
              : null,
          note: row.priceUnknown ? l10n.usageBudgetCostNote : null,
        ),
    ],
    footnote: l10n.usageBudgetFootnote,
  );
}

/// Строка состояния журнала на языке [l10n]: `Ledger: up to date · 12
/// records`. Склейка частей через « · » — нейтральный разделитель; число
/// записей склоняется ICU `plural` (D8).
String? usageLedgerStatusOf(UsageLedgerLine? line, AppLocalizations l10n) {
  if (line == null) return null;
  final head = switch (line.kind) {
    UsageLedgerLineKind.upToDate => l10n.usageLedgerUpToDate,
    UsageLedgerLineKind.rebuilt => [
      l10n.usageLedgerRebuilt,
      if (line.reason case final reason?) l10n.usageLedgerReason(reason),
    ].join(' '),
    UsageLedgerLineKind.inMemory => l10n.usageLedgerInMemory,
    UsageLedgerLineKind.notSaved => l10n.usageLedgerNotSaved,
  };
  final records = line.records;
  return records == null ? head : '$head · ${l10n.usageLedgerRecords(records)}';
}

/// Подсказка строки состояния журнала: причина штатного обновления кэша.
String? usageLedgerHintOf(UsageLedgerLine? line, AppLocalizations l10n) =>
    line?.refreshReason == null
    ? null
    : l10n.usageLedgerRefreshedHint(line!.refreshReason!);
