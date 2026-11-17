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
        BudgetCost,
        SessionStatusView,
        SessionView,
        TurnBudgetView,
        formatUsageMoney,
        formatUsageTokens;

/// Тон полосы строки бюджета: `warning` при `used·5 ≥ limit·4`, `danger` при
/// `used ≥ limit` (в целых, D9). Решает application, не виджет.
enum UsageBudgetTone { neutral, warning, danger }

/// Пояснение под блоком (`usage-budget-note`).
const usageBudgetFootnote =
    'When a limit is hit, the turn stops at the next step boundary.';

/// Строка блока: Steps, Tokens, Cost или Time (`usage-budget-<id>`).
final class UsageBudgetRow {
  const UsageBudgetRow({
    required this.id,
    required this.label,
    required this.value,
    required this.fill,
    this.tone = UsageBudgetTone.neutral,
    this.hint,
    this.note,
  });

  /// `steps`, `tokens`, `cost` или `time` — суффикс ключа.
  final String id;

  /// `Steps`, `Tokens`, `Cost` или `Time`.
  final String label;

  /// Готовая подпись `<израсходовано> / <лимит>`: `3 / 50`, `92.0k / 200.0k`.
  final String value;

  /// Доля заполнения полосы в диапазоне 0..1: больше 100 % ограничено 1,
  /// лимит 0 даёт 1, Cost без `used` — 0.
  final double fill;
  final UsageBudgetTone tone;

  /// Подсказка строки (Tokens: `input + output, including subagents`, R2).
  final String? hint;

  /// Строка под подписью (Cost без цены: `not checked: price unknown`, R8).
  final String? note;
}

/// Исходные числа Time для пересчёта на момент `now` (D9, «Время между
/// снимками»).
final class UsageBudgetTime {
  const UsageBudgetTime({
    required this.usedMs,
    required this.limitMs,
    required this.receivedAt,
  });

  final int usedMs;
  final int limitMs;

  /// Момент применения снимка по часам рабочего пространства.
  final DateTime receivedAt;
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

  /// `This turn` или `Last turn` (Q11 (а)).
  final String title;

  /// Строки Steps, Tokens, Cost — только присутствующие, в этом порядке.
  final List<UsageBudgetRow> rows;

  /// Time; `null` — в `budget` нет `duration`.
  final UsageBudgetTime? time;

  /// Таймер нужен: сессия `running`, одобрений нет, `budget` не итоговый и
  /// есть `duration`. Он же включает добавку `now − receivedAt` к Time.
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
  required String id,
  required String label,
  required String value,
  required int used,
  required int limit,
  String? hint,
}) => UsageBudgetRow(
  id: id,
  label: label,
  value: value,
  fill: _fillOf(used, limit),
  tone: _toneOf(used, limit),
  hint: hint,
);

UsageBudgetRow _costRowOf(BudgetCost cost) {
  final used = cost.used;
  final limitText = formatUsageMoney(cost.limit);
  if (used == null) {
    // Цена модели неизвестна: лимит не проверяется (R8) — не `$0.00`, а `—`.
    return UsageBudgetRow(
      id: 'cost',
      label: 'Cost',
      value: '— / $limitText',
      fill: 0,
      note: 'not checked: price unknown',
    );
  }
  return _rowOf(
    id: 'cost',
    label: 'Cost',
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
  final steps = budget.steps;
  final tokens = budget.tokens;
  final cost = budget.cost;
  final duration = budget.duration;
  return UsageBudgetData(
    title: active && !budget.ended ? 'This turn' : 'Last turn',
    rows: [
      if (steps != null)
        _rowOf(
          id: 'steps',
          label: 'Steps',
          value: '${steps.used} / ${steps.limit}',
          used: steps.used,
          limit: steps.limit,
        ),
      if (tokens != null)
        _rowOf(
          id: 'tokens',
          label: 'Tokens',
          value:
              '${formatUsageTokens(tokens.used)} / '
              '${formatUsageTokens(tokens.limit)}',
          used: tokens.used,
          limit: tokens.limit,
          hint: 'input + output, including subagents',
        ),
      if (cost != null) _costRowOf(cost),
    ],
    time: duration == null
        ? null
        : UsageBudgetTime(
            usedMs: duration.usedMs,
            limitMs: duration.limitMs,
            receivedAt: budget.receivedAt,
          ),
    ticking:
        status == SessionStatusView.running &&
        view.pendingApprovals.isEmpty &&
        !budget.ended &&
        duration != null,
  );
}

/// Наибольшее значение int64 (литерал, а не `1 << 63`: тот уходит в минус).
const _maxInt = 0x7fffffffffffffff;

/// Строки блока в порядке Steps, Tokens, Cost, Time на момент [now]: Time —
/// `usedMs + (now − receivedAt)`, если [UsageBudgetData.ticking] (отрицательная
/// разность — ноль), иначе `usedMs`. Чистая: часы приходят аргументом.
List<UsageBudgetRow> usageBudgetRowsAt(
  UsageBudgetData budget, {
  required DateTime now,
}) {
  final time = budget.time;
  if (time == null) return budget.rows;
  var used = time.usedMs;
  if (budget.ticking) {
    final elapsed = now.difference(time.receivedAt).inMilliseconds;
    // Насыщающее сложение: usedMs с провода может быть около 2^63−1.
    if (elapsed > 0) {
      used = used > _maxInt - elapsed ? _maxInt : used + elapsed;
    }
  }
  return [
    ...budget.rows,
    _rowOf(
      id: 'time',
      label: 'Time',
      value:
          '${formatUsageDuration(used)} / '
          '${formatUsageDuration(time.limitMs)}',
      used: used,
      limit: time.limitMs,
    ),
  ];
}
