import 'package:codelab_client_core/codelab_client_core.dart'
    show SessionView, UsageLedgerView;

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
/// Заглушка задачи 1.4 (красные тесты): поля заданы тестами
/// `usage_pane_data_test.dart`, реализация — задача 1.5.
final class UsagePaneCard {
  const UsagePaneCard({
    required this.id,
    required this.title,
    required this.value,
    this.detail,
  });

  /// `input`, `output`, `cost` или `turns` — суффикс ключа карточки.
  final String id;
  final String title;

  /// Готовое значение (формат kit): `950`, `~$2.26`, `—`.
  final String value;

  /// Вторая строка карточки; `null` — её нет.
  final String? detail;
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
///
/// Заглушка задачи 1.4: поля заданы красными тестами, реализация — 1.5.
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
  final bool canRebuild;
  final bool canExport;
}

/// Доступна ли панель Usage для [view] (таблица D10). `null` — сессии нет.
///
/// Заглушка задачи 1.4.
bool usageAvailableOf(SessionView? view) => throw UnimplementedError();

/// Данные панели Usage из `SessionView` сессии в фокусе (D1, D2, D4, D10).
///
/// [cwd] — папка сессии: подписи шагов строятся по правилу строки ленты.
/// `null` вместо [view] или недоступная панель дают [UsagePaneData.empty].
///
/// Заглушка задачи 1.4.
UsagePaneData usagePaneDataOf(SessionView? view, {required String cwd}) =>
    throw UnimplementedError();
