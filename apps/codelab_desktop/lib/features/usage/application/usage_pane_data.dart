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

/// Вторая строка карточки в виде значения: текст собирает presentation по
/// каталогу (`add-desktop-localization`, D5 п. 4: `application` без языка).
///
/// Почему закрытая иерархия: у строки пять видов с разными аргументами;
/// числа в аргументах — уже отформатированный текст kit (D8), его presentation
/// подставляет как есть.
sealed class UsageCardDetail {
  const UsageCardDetail();
}

/// `cache read <read> · write <write>` под карточкой `input`.
final class UsageCardCache extends UsageCardDetail {
  const UsageCardCache({required this.read, required this.write});

  final String read;
  final String write;

  @override
  bool operator ==(Object other) =>
      other is UsageCardCache && other.read == read && other.write == write;

  @override
  int get hashCode => Object.hash(UsageCardCache, read, write);
}

/// `reasoning <count>` под карточкой `output`.
final class UsageCardReasoning extends UsageCardDetail {
  const UsageCardReasoning(this.count);

  final String count;

  @override
  bool operator ==(Object other) =>
      other is UsageCardReasoning && other.count == count;

  @override
  int get hashCode => Object.hash(UsageCardReasoning, count);
}

/// Причины неполноты суммы стоимости (`partial`) в порядке `UsagePartial`.
final class UsageCardPartialReasons extends UsageCardDetail {
  const UsageCardPartialReasons(this.reasons);

  final List<UsagePartial> reasons;

  @override
  bool operator ==(Object other) =>
      other is UsageCardPartialReasons && _sameReasons(other.reasons, reasons);

  /// Поэлементное сравнение: `application` остаётся без Flutter (сторож), а
  /// `listEquals` живёт в `package:flutter/foundation.dart`.
  static bool _sameReasons(List<UsagePartial> a, List<UsagePartial> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(UsageCardPartialReasons, Object.hashAll(reasons));
}

/// Расхода ещё нет: сессия без ходов (D8 change `fix-usage-pane-live-cards`).
final class UsageCardNoUsageYet extends UsageCardDetail {
  const UsageCardNoUsageYet();

  @override
  bool operator ==(Object other) => other is UsageCardNoUsageYet;

  @override
  int get hashCode => (UsageCardNoUsageYet).hashCode;
}

/// Цена модели неизвестна: стоимость не посчитана.
final class UsageCardPriceUnknown extends UsageCardDetail {
  const UsageCardPriceUnknown();

  @override
  bool operator ==(Object other) => other is UsageCardPriceUnknown;

  @override
  int get hashCode => (UsageCardPriceUnknown).hashCode;
}

/// `avg <average> steps per turn` под карточкой `turns`; [average] —
/// десятичное число (`1.5`).
final class UsageCardAverageSteps extends UsageCardDetail {
  const UsageCardAverageSteps(this.average);

  final String average;

  @override
  bool operator ==(Object other) =>
      other is UsageCardAverageSteps && other.average == average;

  @override
  int get hashCode => Object.hash(UsageCardAverageSteps, average);
}

/// Вид карточки сводки: заголовок выбирается по нему исчерпывающим `switch`
/// в presentation.
enum UsageCardKind { input, output, cost, turns }

/// Карточка сводки панели (`usage-card-<id>`; D2 п. 2).
///
/// Поля заданы тестами `usage_pane_data_test.dart`; [approximate] — тон
/// предупреждения: решение «неполная сумма» принимает application, а не
/// виджет (`codelab_ui/AGENTS.md` §2). Заголовок карточки — текст app по [id],
/// его собирает presentation по каталогу.
final class UsagePaneCard {
  const UsagePaneCard({
    required this.kind,
    required this.value,
    this.detail,
    this.approximate = false,
  });

  final UsageCardKind kind;

  /// `input`, `output`, `cost` или `turns` — суффикс ключа карточки.
  String get id => kind.name;

  /// Готовое значение (формат kit): `950`, `~$2.26`, `—`.
  final String value;

  /// Вторая строка карточки; `null` — её нет.
  final UsageCardDetail? detail;

  /// Сумма неполна (есть причины `partial`): карточка в тоне `warning`.
  final bool approximate;
}

/// Строка шага в раскрытом ходе (`usage-step-<turn>-<index>`; D2 п. 4, D4).
final class UsagePaneStep {
  const UsagePaneStep({
    required this.turn,
    required this.index,
    required this.title,
    required this.input,
    required this.output,
    required this.cost,
    this.model,
  });

  /// Номер хода журнала (с 1).
  final int turn;

  /// Индекс шага журнала (с 0).
  final int index;

  /// Название шага: вызов, `reply` или число вызовов. Текст для экрана
  /// собирает presentation (`step <index + 1> · <title>`), английский текст
  /// для CSV — [UsageStepTitle.englishText].
  final UsageStepTitle title;
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
    this.subagentRuns,
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

  /// Число запусков субагентов хода (`subagents · N runs` на экране);
  /// `null` — субагентов у хода нет.
  final int? subagentRuns;
}

/// Вид строки таблицы `Per model`: модель, группа `Subagents` или `Summaries`.
enum UsageModelKind { model, subagents, summaries }

/// Строка таблицы `Per model` (`usage-model-<n>`; D2 п. 5), включая строки
/// `Subagents` и `Summaries`.
final class UsagePaneModel {
  const UsagePaneModel({
    required this.label,
    required this.input,
    required this.output,
    required this.cost,
    this.kind = UsageModelKind.model,
    this.count,
  });

  /// `<provider> / <id>` у модели; у групп — пусто: их название собирает
  /// presentation по [kind] (`add-desktop-localization`, D5 п. 4).
  final String label;
  final String input;
  final String output;
  final String cost;
  final UsageModelKind kind;

  /// Число запусков у `Subagents`, число сводок у `Summaries`; у модели —
  /// `null`.
  final int? count;
}

/// Состояние журнала для строки `usage-ledger-status`: значение, из которого
/// presentation собирает строку и подсказку (D7 change
/// `fix-usage-pane-live-cards`; `add-desktop-localization`, D5 п. 4).
enum UsageLedgerLineKind { upToDate, rebuilt, inMemory, notSaved }

/// Строка состояния журнала в виде значения.
final class UsageLedgerLine {
  const UsageLedgerLine(
    this.kind, {
    this.records,
    this.reason,
    this.refreshReason,
  });

  final UsageLedgerLineKind kind;

  /// Число записей журнала; `null` — не сообщено.
  final int? records;

  /// Причина пересборки (`rebuilt`) — значение провода, не переводится.
  final String? reason;

  /// Причина штатной пересборки кэша (`stale`, `missing`) для подсказки
  /// строки: журнал показан как `upToDate`, причина — только в подсказке.
  final String? refreshReason;

  @override
  bool operator ==(Object other) =>
      other is UsageLedgerLine &&
      other.kind == kind &&
      other.records == records &&
      other.reason == reason &&
      other.refreshReason == refreshReason;

  @override
  int get hashCode => Object.hash(kind, records, reason, refreshReason);
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
    this.ledgerLine,
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

  /// Состояние журнала для строки `usage-ledger-status`; `null` — нечего
  /// показывать. Строку и подсказку (причина штатной пересборки кэша, D7
  /// change `fix-usage-pane-live-cards`) собирает presentation.
  final UsageLedgerLine? ledgerLine;

  /// Карточки сводки: все четыре из одного агрегата — свежего из журнала и
  /// живых снимков (D1 того же change).
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

/// «Расхода ещё нет»: ни шагов, ни токенов, ни цены, ни причин неполноты
/// (D8, Q6 (а) change `fix-usage-pane-live-cards`).
///
/// Почему: у пустой сессии на проводе нет `cost`, и `price unknown` называл бы
/// модель безценной, хотя ходов просто не было. `$0.00` тоже нельзя: клиент не
/// знает ни валюты, ни того, есть ли у модели цены (DSK-11, VIEW-6).
bool _noUsageYet(UsageTotals total) {
  final tokens = total.tokens;
  return total.steps == 0 &&
      total.cost == null &&
      total.partial.isEmpty &&
      tokens.input == 0 &&
      tokens.output == 0 &&
      tokens.cacheRead == 0 &&
      tokens.cacheWrite == 0 &&
      (tokens.reasoning ?? 0) == 0;
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
      if (partial.contains(reason)) reason,
  ];
  return [
    UsagePaneCard(
      kind: UsageCardKind.input,
      value: inputValue,
      detail: UsageCardCache(
        read: formatUsageTokens(tokens.cacheRead),
        write: formatUsageTokens(tokens.cacheWrite),
      ),
      approximate: inputApprox,
    ),
    UsagePaneCard(
      kind: UsageCardKind.output,
      value: outputValue,
      detail: reasoning == null
          ? null
          : UsageCardReasoning(formatUsageTokens(reasoning)),
      approximate: outputApprox,
    ),
    UsagePaneCard(
      kind: UsageCardKind.cost,
      value: total.cost == null
          ? _unknown
          : '${usageCostPartial(partial) ? '~' : ''}'
                '${formatUsageMoney(total.cost!)}',
      detail: reasons.isNotEmpty
          ? UsageCardPartialReasons(reasons)
          : (total.cost == null
                ? (_noUsageYet(total)
                      ? const UsageCardNoUsageYet()
                      : const UsageCardPriceUnknown())
                : null),
      approximate: total.cost != null && usageCostPartial(partial),
    ),
    UsagePaneCard(
      kind: UsageCardKind.turns,
      value: turnCount == null
          ? '${total.steps}'
          : '$turnCount · ${total.steps}',
      detail: turnCount == null || turnCount <= 0
          ? null
          : UsageCardAverageSteps(_averageOf(total.steps, turnCount)),
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
        return UsagePaneStep(
          turn: turn.index,
          index: step.index,
          title: labeler.labelOf(step),
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
    subagentRuns: turn.subagents?.count,
  );
}

UsagePaneModel _groupOf(UsageModelKind kind, UsageLedgerGroup group) =>
    UsagePaneModel(
      label: '',
      kind: kind,
      input: _inputOf(group.tokens, group.partial),
      output: _outputOf(group.tokens, group.partial),
      cost: _costOf(group.tokens, group.cost, group.partial),
      count: group.count,
    );

/// Причины пересборки, которые при `rebuilt` считаются штатным обновлением
/// ленивого кэша `usage.json` (D3 change `add-usage-ledger`), а не сбоем.
const _routineRebuildReasons = {'stale', 'missing'};

/// Состояние журнала для строки состояния и подсказки (D7, Q5 (а)).
///
/// `stale` и `missing` — путь ленивого кэша: после пересборки файл свеж, и
/// пользователь видит то же, что при `upToDate`; причина уходит в
/// [UsageLedgerLine.refreshReason] (подсказка). `invalid`, `explicit` и
/// незнакомая причина видны в строке: это битый файл или действие
/// пользователя («Rebuild from log»).
UsageLedgerLine? _statusOf(UsageLedgerView ledger) {
  final records = ledger.records;
  final reason = ledger.reason;
  return switch (ledger.status) {
    UsageLedgerStatus.upToDate => UsageLedgerLine(
      UsageLedgerLineKind.upToDate,
      records: records,
    ),
    UsageLedgerStatus.rebuilt when _routineRebuildReasons.contains(reason) =>
      UsageLedgerLine(
        UsageLedgerLineKind.upToDate,
        records: records,
        refreshReason: reason,
      ),
    UsageLedgerStatus.rebuilt => UsageLedgerLine(
      UsageLedgerLineKind.rebuilt,
      records: records,
      reason: reason,
    ),
    UsageLedgerStatus.inMemory => const UsageLedgerLine(
      UsageLedgerLineKind.inMemory,
    ),
    UsageLedgerStatus.notSaved => const UsageLedgerLine(
      UsageLedgerLineKind.notSaved,
    ),
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
  // D1 (Q1 (в)): карточки целиком из одного свежего агрегата. Журнал свеж,
  // если не отстаёт от снимков по `seq` (признак D3 change
  // `add-desktop-usage-pane`); отставший журнал уступает живым снимкам, а при
  // их отсутствии (`awaiting`, пустая сессия) остаётся единственным
  // источником. Журнал и снимок не складываются (R8 change `add-usage-ledger`).
  final ledgerFresh = ledger != null && ledger.seq >= view.usage.lastSeq;
  final cards = ledger != null && (ledgerFresh || session == null)
      ? _cardsOf(ledger.total, turnCount: ledger.turnCount)
      : session != null
      ? _cardsOf(session, turnCount: session.turns)
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
        _groupOf(UsageModelKind.subagents, group),
      if (ledger.summaries case final group?)
        _groupOf(UsageModelKind.summaries, group),
    ];
  }
  final status = ledger == null ? null : _statusOf(ledger);
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
    ledgerLine: status,
    cards: cards,
    turns: turns,
    models: models,
    budget: usageBudgetDataOf(view),
    canRebuild: ledgerAvailable && state is! UsageLedgerLoading,
    canExport: ledger != null,
  );
}
