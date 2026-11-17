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
/// Заглушка задачи 3.3: типы и сигнатуры; тела функций — задача 3.4.
library;

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
String formatUsageDuration(int ms) => throw UnimplementedError();

/// Строки блока в порядке Steps, Tokens, Cost, Time на момент [now]: Time —
/// `usedMs + (now − receivedAt)`, если [UsageBudgetData.ticking] (отрицательная
/// разность — ноль), иначе `usedMs`. Чистая: часы приходят аргументом.
List<UsageBudgetRow> usageBudgetRowsAt(
  UsageBudgetData budget, {
  required DateTime now,
}) => throw UnimplementedError();
