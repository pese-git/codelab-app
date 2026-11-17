import 'package:codelab_client_core/codelab_client_core.dart'
    show
        Money,
        SessionView,
        TokenCounts,
        UsageLedgerFailed,
        UsageLedgerGroup,
        UsageLedgerIdle,
        UsageLedgerLoaded,
        UsageLedgerLoading,
        UsageLedgerStatus,
        UsageLedgerTurn,
        UsageLedgerUnavailable,
        UsageLedgerView,
        UsagePartial,
        UsageSupport,
        UsageTotals,
        formatUsageMoney,
        formatUsageTokens,
        usageCostPartial,
        usageInputTokens,
        usageTokensPartial;

import 'usage_budget.dart';
import 'usage_step_label.dart';

/// Заметка под шапкой панели Usage (design.md change `add-desktop-usage-pane`,
/// D2 п. 6, D10).
///
/// Почему enum, а не строка: тексты заметок — часть модели отображения, а
/// набор заметок конечен и проверяется тестами.
enum UsagePaneNotice {
  /// Заметки нет.
  none,

  /// Сбой загрузки журнала: `Couldn't load usage history.` и `Retry`.
  ledgerFailed,

  /// Агент не объявил `usageLedger`: `This agent does not provide usage
  /// history.`
  noLedger,
}

/// Карточка сводки панели (`usage-card-<id>`; D2 п. 2).
///
/// Поля заданы тестами `usage_pane_data_test.dart`; [approximate] — тон
/// предупреждения: решение «неполная сумма» принимает application, а не
/// виджет (`codelab_ui/AGENTS.md` §2).
final class UsagePaneCard {
  const UsagePaneCard({
    required this.id,
    required this.title,
    required this.value,
    this.detail,
    this.approximate = false,
  });

  /// `input`, `output`, `cost` или `turns` — суффикс ключа карточки.
  final String id;
  final String title;

  /// Готовое значение (формат kit): `950`, `~$2.26`, `—`.
  final String value;

  /// Вторая строка карточки; `null` — её нет.
  final String? detail;

  /// Сумма неполна (есть причины `partial`): карточка в тоне `warning`.
  final bool approximate;
}

/// Строка шага в раскрытом ходе (`usage-step-<turn>-<index>`; D2 п. 4, D4).
final class UsagePaneStep {
  const UsagePaneStep({
    required this.turn,
    required this.index,
    required this.title,
    required this.label,
    required this.input,
    required this.output,
    required this.cost,
    this.model,
  });

  /// Номер хода журнала (с 1).
  final int turn;

  /// Индекс шага журнала (с 0).
  final int index;

  /// Подпись шага без префикса (`Read lib/a.dart`, `reply`) — её берёт CSV.
  final String title;

  /// `step <index + 1> · <title>`.
  final String label;
  final String input;
  final String output;
  final String cost;

  /// Модель шага — подсказка строки; `null` — агент её не прислал.
  final String? model;
}

/// Строка хода в таблице `Per turn` (`usage-turn-<index>`; D2 п. 4).
final class UsagePaneTurn {
  const UsagePaneTurn({
    required this.index,
    required this.label,
    required this.running,
    required this.input,
    required this.output,
    required this.cost,
    this.steps = const [],
    this.subagents,
  });

  /// Номер хода журнала (с 1).
  final int index;

  /// `N · “<title>”` или `N`.
  final String label;
  final bool running;
  final String input;
  final String output;
  final String cost;
  final List<UsagePaneStep> steps;

  /// `subagents · N runs`; `null` — субагентов у хода нет.
  final String? subagents;
}

/// Строка таблицы `Per model` (`usage-model-<n>`; D2 п. 5), включая строки
/// `Subagents` и `Summaries`.
final class UsagePaneModel {
  const UsagePaneModel({
    required this.label,
    required this.input,
    required this.output,
    required this.cost,
    this.detail,
  });

  /// `<provider> / <id>`, `Subagents` или `Summaries`.
  final String label;
  final String input;
  final String output;
  final String cost;

  /// `N runs` у `Subagents`, `N` у `Summaries`; у модели — `null`.
  final String? detail;
}

/// Неизменяемый снимок панели Usage для сессии в фокусе (D1, D2, D10).
///
/// Почему: панель показывает готовые тексты, а числа форматирует kit
/// (`usage_format.dart`); `codelab_ui` ничего не считает. Для чего: единый
/// вход виджета и CSV (`buildUsageCsv`). Как использовать: собирает
/// `usagePaneDataOf` в `ActiveSessionCubit._onView`, виджеты только читают.
final class UsagePaneData {
  const UsagePaneData({
    this.available = false,
    this.ledgerAvailable = false,
    this.busy = false,
    this.ledger,
    this.notice = UsagePaneNotice.none,
    this.failureHint,
    this.statusLine,
    this.cards = const [],
    this.turns = const [],
    this.models = const [],
    this.budget,
    this.canRebuild = false,
    this.canExport = false,
  });

  /// Панель недоступна: нет сессии, либо агент не объявил ни `usage`, ни
  /// `usageLedger` (D10).
  static const empty = UsagePaneData();

  /// Панель предлагается для сессии (D10).
  final bool available;

  /// Агент объявил `usageLedger`.
  final bool ledgerAvailable;

  /// Журнал `idle` или `loading`: до ответа показывается индикатор.
  final bool busy;

  /// Журнал для показа: `loaded` либо прежний при `loading` и `failed`.
  final UsageLedgerView? ledger;
  final UsagePaneNotice notice;

  /// Код ошибки журнала для подсказки заметки (`-32603`); `null` — не сбой.
  final String? failureHint;

  /// Строка состояния журнала (`usage-ledger-status`); `null` — нечего
  /// показывать.
  final String? statusLine;
  final List<UsagePaneCard> cards;

  /// Ходы от нового к старому.
  final List<UsagePaneTurn> turns;
  final List<UsagePaneModel> models;

  /// Блок `Turn budget` (D9); `null` — блока нет. Источник — `usage.budget`,
  /// а не журнал, поэтому блок есть и у агента без журнала (D10).
  final UsageBudgetData? budget;
  final bool canRebuild;
  final bool canExport;
}

/// Доступна ли панель Usage для [view] (таблица D10). `null` — сессии нет.
///
/// Почему отдельная функция: предикат нужен и без полного снимка панели
/// (док, палитра, строка статуса), а решает его application, не виджет.
bool usageAvailableOf(SessionView? view) =>
    view != null &&
    (view.usageLedger is! UsageLedgerUnavailable ||
        view.usage.support != UsageSupport.unknown);

/// Тексты причин неполноты — те же, что в подсказке строки статуса (A7).
const _partialTexts = {
  UsagePartial.noUsage: 'agent sent no usage for some steps',
  UsagePartial.noPrice: 'price unknown for some steps',
  UsagePartial.beforeLoad: 'before the session was loaded',
};

/// Строка агрегата без usage: счётчики нулевые и агент не прислал usage.
///
/// Нули тут не факт, а отсутствие данных, поэтому панель показывает `—`, а
/// CSV — пустые ячейки (DSK-11, VIEW-6).
bool usageRowSilent(TokenCounts tokens, Set<UsagePartial> partial) =>
    partial.contains(UsagePartial.noUsage) &&
    tokens.input == 0 &&
    tokens.output == 0 &&
    tokens.cacheRead == 0 &&
    tokens.cacheWrite == 0;

String _inputOf(TokenCounts tokens, Set<UsagePartial> partial) {
  if (usageRowSilent(tokens, partial)) return _unknown;
  final text = formatUsageTokens(usageInputTokens(tokens));
  return usageTokensPartial(partial) ? '~$text' : text;
}

String _outputOf(TokenCounts tokens, Set<UsagePartial> partial) {
  if (usageRowSilent(tokens, partial)) return _unknown;
  final text = formatUsageTokens(tokens.output);
  return usageTokensPartial(partial) ? '~$text' : text;
}

String _costOf(TokenCounts tokens, Money? cost, Set<UsagePartial> partial) {
  if (cost == null || usageRowSilent(tokens, partial)) return _unknown;
  final text = formatUsageMoney(cost);
  return usageCostPartial(partial) ? '~$text' : text;
}

const _unknown = '—';

/// Средние шаги на ход: десятые считаются в целых, половина вверх (D2 п. 2).
String _averageOf(int steps, int turns) {
  final tenths = (steps * 20 + turns) ~/ (turns * 2);
  return '${tenths ~/ 10}.${tenths % 10}';
}

List<UsagePaneCard> _cardsOf(UsageTotals total, {required int? turnCount}) {
  final tokens = total.tokens;
  final partial = total.partial;
  // «Немая» карточка (`—`) предупреждающей плашки не получает: тон
  // предупреждает о неполной сумме, а у «—» суммы нет вовсе (D2 п. 2; причина
  // видна в `detail`).
  final inputValue = _inputOf(tokens, partial);
  final outputValue = _outputOf(tokens, partial);
  final inputApprox = usageTokensPartial(partial) && inputValue != _unknown;
  final outputApprox = usageTokensPartial(partial) && outputValue != _unknown;
  final reasoning = tokens.reasoning;
  final reasons = [
    for (final reason in UsagePartial.values)
      if (partial.contains(reason)) _partialTexts[reason]!,
  ];
  return [
    UsagePaneCard(
      id: 'input',
      title: 'Input',
      value: inputValue,
      detail:
          'cache read ${formatUsageTokens(tokens.cacheRead)} · '
          'write ${formatUsageTokens(tokens.cacheWrite)}',
      approximate: inputApprox,
    ),
    UsagePaneCard(
      id: 'output',
      title: 'Output',
      value: outputValue,
      detail: reasoning == null
          ? null
          : 'reasoning ${formatUsageTokens(reasoning)}',
      approximate: outputApprox,
    ),
    UsagePaneCard(
      id: 'cost',
      title: 'Cost',
      value: total.cost == null
          ? _unknown
          : '${usageCostPartial(partial) ? '~' : ''}'
                '${formatUsageMoney(total.cost!)}',
      detail: reasons.isNotEmpty
          ? reasons.join(', ')
          : (total.cost == null ? 'price unknown' : null),
      approximate: total.cost != null && usageCostPartial(partial),
    ),
    UsagePaneCard(
      id: 'turns',
      title: 'Turns · steps',
      value: turnCount == null
          ? '${total.steps}'
          : '$turnCount · ${total.steps}',
      detail: turnCount == null || turnCount <= 0
          ? null
          : 'avg ${_averageOf(total.steps, turnCount)} steps per turn',
    ),
  ];
}

String _modelLabelOf(String model) {
  final slash = model.indexOf('/');
  return slash < 0
      ? model
      : '${model.substring(0, slash)} / ${model.substring(slash + 1)}';
}

UsagePaneTurn _turnOf(UsageLedgerTurn turn, UsageStepLabeler labeler) {
  final total = turn.total;
  final title = turn.title;
  final steps = [
    for (final step in turn.steps)
      () {
        final text = labeler.labelOf(step);
        return UsagePaneStep(
          turn: turn.index,
          index: step.index,
          title: text,
          label: 'step ${step.index + 1} · $text',
          input: _inputOf(step.tokens, step.partial),
          output: _outputOf(step.tokens, step.partial),
          cost: _costOf(step.tokens, step.cost, step.partial),
          model: step.model,
        );
      }(),
  ];
  return UsagePaneTurn(
    index: turn.index,
    label: title == null || title.isEmpty
        ? '${turn.index}'
        : '${turn.index} · “$title”',
    running: turn.running,
    input: _inputOf(total.tokens, total.partial),
    output: _outputOf(total.tokens, total.partial),
    cost: _costOf(total.tokens, total.cost, total.partial),
    steps: steps,
    subagents: turn.subagents == null
        ? null
        : 'subagents · ${turn.subagents!.count} runs',
  );
}

UsagePaneModel _groupOf(String label, UsageLedgerGroup group, String detail) =>
    UsagePaneModel(
      label: label,
      input: _inputOf(group.tokens, group.partial),
      output: _outputOf(group.tokens, group.partial),
      cost: _costOf(group.tokens, group.cost, group.partial),
      detail: detail,
    );

String? _statusLineOf(UsageLedgerView ledger) {
  final records = ledger.records;
  final tail = records == null
      ? ''
      : ' · $records ${records == 1 ? 'record' : 'records'}';
  return switch (ledger.status) {
    UsageLedgerStatus.upToDate => 'Ledger: up to date$tail',
    UsageLedgerStatus.rebuilt =>
      'rebuilt from journal'
          '${ledger.reason == null ? '' : ' (${ledger.reason})'}$tail',
    UsageLedgerStatus.inMemory => 'in memory',
    UsageLedgerStatus.notSaved => 'not saved',
    null => null,
  };
}

/// Данные панели Usage из `SessionView` сессии в фокусе (D1, D2, D4, D10).
///
/// Почему: числа и таблицы считает агент (журнал) и kit (формат); здесь
/// только раскладка по карточкам и строкам с готовыми подписями — app ничего
/// не суммирует сам.
///
/// [cwd] — папка сессии: подписи шагов строятся по правилу строки ленты.
/// `null` вместо [view] или недоступная панель дают [UsagePaneData.empty].
UsagePaneData usagePaneDataOf(SessionView? view, {required String cwd}) {
  if (view == null || !usageAvailableOf(view)) {
    return UsagePaneData.empty;
  }
  final state = view.usageLedger;
  final ledgerAvailable = state is! UsageLedgerUnavailable;
  final (UsageLedgerView? ledger, bool busy) = switch (state) {
    UsageLedgerUnavailable() => (null, false),
    UsageLedgerIdle() => (null, true),
    UsageLedgerLoading(:final previous) => (previous, true),
    UsageLedgerLoaded(:final view) => (view, false),
    UsageLedgerFailed(:final previous) => (previous, false),
  };
  final failed = state is UsageLedgerFailed ? state.reason : null;
  final session = view.usage.session;
  final cards = ledger != null
      ? _cardsOf(ledger.total, turnCount: ledger.turnCount)
      : session != null
      ? _cardsOf(session, turnCount: null)
      : const <UsagePaneCard>[];

  var turns = const <UsagePaneTurn>[];
  var models = const <UsagePaneModel>[];
  if (ledger != null) {
    final labeler = UsageStepLabeler(view.transcript, cwd: cwd);
    turns = [for (final turn in ledger.turns.reversed) _turnOf(turn, labeler)];
    models = [
      for (final model in ledger.models)
        UsagePaneModel(
          label: _modelLabelOf(model.model),
          input: _inputOf(model.tokens, model.partial),
          output: _outputOf(model.tokens, model.partial),
          cost: _costOf(model.tokens, model.cost, model.partial),
        ),
      if (ledger.subagents case final group?)
        _groupOf('Subagents', group, '${group.count} runs'),
      if (ledger.summaries case final group?)
        _groupOf('Summaries', group, '${group.count}'),
    ];
  }
  return UsagePaneData(
    available: true,
    ledgerAvailable: ledgerAvailable,
    busy: busy,
    ledger: ledger,
    notice: failed != null
        ? UsagePaneNotice.ledgerFailed
        : (!ledgerAvailable ? UsagePaneNotice.noLedger : UsagePaneNotice.none),
    failureHint: failed == null
        ? null
        : (failed.code?.toString() ?? failed.kind.name),
    statusLine: ledger == null ? null : _statusLineOf(ledger),
    cards: cards,
    turns: turns,
    models: models,
    budget: usageBudgetDataOf(view),
    canRebuild: ledgerAvailable && state is! UsageLedgerLoading,
    canExport: ledger != null,
  );
}
