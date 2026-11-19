/// Данные блока `Turn budget` панели Usage (design.md change
/// `add-desktop-usage-pane`, D9, решения пользователя Q5 (а), Q11 (а);
/// agent-workbench-ui «Бюджет хода в панели Usage»).
///
/// Почему отдельный файл: блок питается от `SessionView.usage.budget`, а не
/// от журнала, и у него своё время жизни — Time меняется каждую секунду, пока
/// идёт ход, тогда как остальная панель обновляется по снимкам.
///
/// Для чего: готовые тексты и тон Steps, Tokens, Cost; исходные числа Time и
/// признак тика. Виджет `WorkbenchUsagePane` зовёт [usageBudgetRowsAt] в
/// `build`, а таймер включает по [UsageBudgetData.ticking].
///
/// Как использовать: [usageBudgetDataOf] зовёт `usagePaneDataOf`; `build`
/// виджета вызывает [usageBudgetRowsAt] с часами из `WorkbenchUsagePane.clock`.
library;

import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ApprovalWaitView,
        BudgetCost,
        SessionStatusView,
        SessionView,
        TurnBudgetView,
        formatUsageMoney,
        formatUsageTokens;

/// Тон полосы строки бюджета: `warning` при `used·5 ≥ limit·4`, `danger` при
/// `used ≥ limit` (в целых, D9). Решает application, не виджет.
enum UsageBudgetTone { neutral, warning, danger }

/// Заголовок блока: идущий ход или последний завершённый. Решение «какой»
/// принимает application (Q11 (а)), а текст («This turn» / «Last turn»)
/// собирает presentation по каталогу (`add-desktop-localization`, D5 п. 4).
enum UsageBudgetTitle { thisTurn, lastTurn }

/// Вид строки бюджета: подпись и подсказка выбираются по нему
/// исчерпывающим `switch` в presentation (`add-desktop-localization`, D5 п. 4).
enum UsageBudgetRowKind { steps, tokens, cost, time }

/// Строка блока: Steps, Tokens, Cost или Time (`usage-budget-<id>`).
///
/// Подпись, подсказка строки Tokens и пометка Cost без цены — тексты app; они
/// определяются по [id] и [priceUnknown] и собираются presentation по
/// каталогу (`add-desktop-localization`, D5 п. 4).
final class UsageBudgetRow {
  const UsageBudgetRow({
    required this.kind,
    required this.value,
    required this.fill,
    this.tone = UsageBudgetTone.neutral,
    this.priceUnknown = false,
  });

  final UsageBudgetRowKind kind;

  /// `steps`, `tokens`, `cost` или `time` — суффикс ключа строки.
  String get id => kind.name;

  /// Готовая подпись `<израсходовано> / <лимит>`: `3 / 50`, `92.0k / 200.0k`.
  final String value;

  /// Доля заполнения полосы в диапазоне 0..1: больше 100 % ограничено 1,
  /// лимит 0 даёт 1, Cost без `used` — 0.
  final double fill;
  final UsageBudgetTone tone;

  /// Cost без цены модели: лимит не проверяется (R8), под подписью пометка.
  final bool priceUnknown;
}

/// Исходные числа Time для пересчёта на момент `now` (D9 change
/// `add-desktop-usage-pane`, «Время между снимками»; D4 change
/// `fix-usage-pane-live-cards`).
final class UsageBudgetTime {
  const UsageBudgetTime({
    required this.usedMs,
    required this.limitMs,
    required this.receivedAt,
    this.waits = const [],
    this.live = false,
  });

  final int usedMs;
  final int limitMs;

  /// Момент применения снимка по часам рабочего пространства.
  final DateTime receivedAt;

  /// Ожидания одобрений корня текущего хода (`SessionView.approvalWaits`):
  /// их объединение вычитается из времени между снимками, потому что цикл
  /// агента на ожидании часы хода не считает (D4, Q2 (б)). Ожидание без
  /// `resolvedAt` идёт до `now`.
  final List<ApprovalWaitView> waits;

  /// Бюджет живой: сессия `running` или `cancelling`, итогового снимка нет.
  /// Только тогда Time растёт между снимками; иначе это `usedMs` как есть.
  final bool live;
}

/// Блок `Turn budget` в данных панели (`UsagePaneData.budget`; `null` — блока
/// нет).
final class UsageBudgetData {
  const UsageBudgetData({
    required this.title,
    required this.rows,
    required this.ticking,
    this.time,
  });

  /// Идущий или последний завершённый ход (Q11 (а)).
  final UsageBudgetTitle title;

  /// Строки Steps, Tokens, Cost — только присутствующие, в этом порядке.
  final List<UsageBudgetRow> rows;

  /// Time; `null` — в `budget` нет `duration`.
  final UsageBudgetTime? time;

  /// Таймер нужен: бюджет живой (`running` или `cancelling`, не итоговый),
  /// есть `duration` и нет ожидающего одобрения корня. При ожидании корня
  /// Time стоит, поэтому таймер не нужен; одобрение потомка тик не
  /// останавливает (D4, Q4 (а)). Он же включает добавку к Time.
  final bool ticking;
}

/// Секунды вниз в `m:ss` и `h:mm:ss` от часа: `90000` → `1:30`,
/// `3600000` → `1:00:00`. Отрицательное значение считается нулём.
///
/// Почему здесь, а не в kit: время бюджета больше никто не показывает, а
/// новый публичный API ради одного потребителя не нужен (D9, `AGENTS.md` §13).
String formatUsageDuration(int ms) {
  final seconds = ms <= 0 ? 0 : ms ~/ 1000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$rest';
  }
  return '$minutes:$rest';
}

/// Тон по доле `used / limit` в целых, без `double` (D9): `used·5 ≥ limit·4` —
/// `warning`, `used ≥ limit` — `danger`. Лимит 0 даёт `danger` (0 ≥ 0).
///
/// Умножение заменено эквивалентом `used ≥ limit − limit ~/ 5`
/// (`ceil(4·L/5) = L − ⌊L/5⌋`): числа с провода бывают около 2^63, и
/// `used * 5` переполнило бы int64 (`usageCount` принимает любой int ≥ 0).
UsageBudgetTone _toneOf(int used, int limit) {
  if (used >= limit) return UsageBudgetTone.danger;
  if (used >= limit - limit ~/ 5) return UsageBudgetTone.warning;
  return UsageBudgetTone.neutral;
}

/// Доля заполнения полосы 0..1: больше 100 % ограничено, лимит 0 — полная.
double _fillOf(int used, int limit) {
  if (limit <= 0 || used >= limit) return 1;
  return used <= 0 ? 0 : used / limit;
}

UsageBudgetRow _rowOf({
  required UsageBudgetRowKind kind,
  required String value,
  required int used,
  required int limit,
}) => UsageBudgetRow(
  kind: kind,
  value: value,
  fill: _fillOf(used, limit),
  tone: _toneOf(used, limit),
);

UsageBudgetRow _costRowOf(BudgetCost cost) {
  final used = cost.used;
  final limitText = formatUsageMoney(cost.limit);
  if (used == null) {
    // Цена модели неизвестна: лимит не проверяется (R8) — не `$0.00`, а `—`.
    return UsageBudgetRow(
      kind: UsageBudgetRowKind.cost,
      value: '— / $limitText',
      fill: 0,
      priceUnknown: true,
    );
  }
  return _rowOf(
    kind: UsageBudgetRowKind.cost,
    value: '${formatUsageMoney(used)} / $limitText',
    used: used.micros,
    limit: cost.limit.micros,
  );
}

/// Данные блока из бюджета и состояния сессии; `null` — блока нет (D9, Q5).
///
/// Решение «This turn / Last turn» и «тикать ли» принимает application
/// (Q11 (а)): виджет только следует [UsageBudgetData.ticking].
UsageBudgetData? usageBudgetDataOf(SessionView view) {
  final TurnBudgetView? budget = view.usage.budget;
  if (budget == null) return null;
  final status = view.status;
  final active =
      status == SessionStatusView.running ||
      status == SessionStatusView.cancelling;
  // Живой бюджет: Time считается между снимками (D4). `cancelling` тоже
  // живой: цикл считает время до `TurnEnded`.
  final live = active && !budget.ended;
  final steps = budget.steps;
  final tokens = budget.tokens;
  final cost = budget.cost;
  final duration = budget.duration;
  return UsageBudgetData(
    title: live ? UsageBudgetTitle.thisTurn : UsageBudgetTitle.lastTurn,
    rows: [
      if (steps != null)
        _rowOf(
          kind: UsageBudgetRowKind.steps,
          value: '${steps.used} / ${steps.limit}',
          used: steps.used,
          limit: steps.limit,
        ),
      if (tokens != null)
        _rowOf(
          kind: UsageBudgetRowKind.tokens,
          value:
              '${formatUsageTokens(tokens.used)} / '
              '${formatUsageTokens(tokens.limit)}',
          used: tokens.used,
          limit: tokens.limit,
        ),
      if (cost != null) _costRowOf(cost),
    ],
    time: duration == null
        ? null
        : UsageBudgetTime(
            usedMs: duration.usedMs,
            limitMs: duration.limitMs,
            receivedAt: budget.receivedAt,
            waits: view.approvalWaits,
            live: live,
          ),
    ticking:
        live &&
        duration != null &&
        !view.approvalWaits.any((wait) => wait.resolvedAt == null),
  );
}

/// Наибольшее значение int64 (литерал, а не `1 << 63`: тот уходит в минус).
const _maxInt = 0x7fffffffffffffff;

/// Миллисекунды, которые объединение ожиданий [waits] занимает на отрезке
/// `(receivedAt, now]`. Пересекающиеся интервалы считаются один раз — как в
/// ядре после D6; открытое ожидание идёт до [now]. Целочисленно, без `double`.
int _waitedMs(
  List<ApprovalWaitView> waits,
  DateTime receivedAt,
  DateTime now,
  int elapsed,
) {
  final spans = <(int, int)>[];
  for (final wait in waits) {
    final start = wait.requestedAt.difference(receivedAt).inMilliseconds;
    final end = (wait.resolvedAt ?? now).difference(receivedAt).inMilliseconds;
    // Обрезка по границам отрезка: ожидание до `receivedAt` уже учтено в
    // `usedMs` снимка, после `now` — ещё не наступило.
    final from = start < 0 ? 0 : start;
    final to = end > elapsed ? elapsed : end;
    if (to > from) spans.add((from, to));
  }
  spans.sort((a, b) => a.$1.compareTo(b.$1));
  var total = 0;
  var coveredTo = 0;
  for (final (from, to) in spans) {
    final begin = from > coveredTo ? from : coveredTo;
    if (to > begin) {
      total += to - begin;
      coveredTo = to;
    }
  }
  return total;
}

/// Строки блока в порядке Steps, Tokens, Cost, Time на момент [now].
///
/// Time живого бюджета — `usedMs + max(0, (now − receivedAt) − |W ∩
/// (receivedAt, now]|)`, где `W` — объединение ожиданий одобрений корня
/// (D4 change `fix-usage-pane-live-cards`): пока одобрение ждёт, Time стоит, а
/// после ответа не прыгает вперёд на время ожидания. Не живой бюджет —
/// `usedMs`. Чистая: часы приходят аргументом.
List<UsageBudgetRow> usageBudgetRowsAt(
  UsageBudgetData budget, {
  required DateTime now,
}) {
  final time = budget.time;
  if (time == null) return budget.rows;
  var used = time.usedMs;
  if (time.live) {
    final elapsed = now.difference(time.receivedAt).inMilliseconds;
    if (elapsed > 0) {
      final add =
          elapsed - _waitedMs(time.waits, time.receivedAt, now, elapsed);
      // Насыщающее сложение: usedMs с провода может быть около 2^63−1.
      if (add > 0) used = used > _maxInt - add ? _maxInt : used + add;
    }
  }
  return [
    ...budget.rows,
    _rowOf(
      kind: UsageBudgetRowKind.time,
      value:
          '${formatUsageDuration(used)} / '
          '${formatUsageDuration(time.limitMs)}',
      used: used,
      limit: time.limitMs,
    ),
  ];
}
