import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Карточка сводки панели Usage (`usage-card-<id>`; design.md change
/// `add-desktop-usage-pane`, D2 п. 2).
///
/// Почему готовые строки: форматирует числа и «~» клиентский слой, виджет
/// ничего не считает (`codelab_ui/AGENTS.md` §2). Для чего: Input, Output,
/// Cost, Turns · steps. Как использовать: app строит карточки из данных
/// панели; [tone] отличный от нейтрального рисуется плашкой.
class CodeLabUsageCard {
  const CodeLabUsageCard({
    required this.id,
    required this.title,
    required this.value,
    this.detail,
    this.tone = CodeLabTone.neutral,
  });

  /// Суффикс ключа: `usage-card-<id>`.
  final String id;
  final String title;
  final String value;

  /// Вторая строка карточки; `null` — её нет.
  final String? detail;
  final CodeLabTone tone;
}

/// Строка таблицы панели Usage: ход, шаг или модель (D2 п. 4–5).
///
/// Почему одна модель на три таблицы: у них одни столбцы (Input, Output,
/// Cost), различается только ключ и вложенность. Как использовать: [id] —
/// суффикс ключа (`usage-turn-<id>`, `usage-step-<id>`); [children] — шаги
/// хода, раскрываются по клику на строку.
class CodeLabUsageRow {
  const CodeLabUsageRow({
    required this.id,
    required this.label,
    required this.input,
    required this.output,
    required this.cost,
    this.running = false,
    this.hint,
    this.children = const [],
    this.note,
  });

  final String id;
  final String label;
  final String input;
  final String output;
  final String cost;

  /// Ход идёт: рядом с подписью пометка `running`.
  final bool running;

  /// Подсказка строки (модель шага); `null` — подсказки нет.
  final String? hint;
  final List<CodeLabUsageRow> children;

  /// Строка под подписью (`subagents · N runs`, `N runs`); `null` — нет.
  final String? note;
}

/// Заметка панели с необязательным действием (`usage-note`, `usage-retry`).
class CodeLabUsageNote {
  const CodeLabUsageNote({required this.text, this.hint, this.retryLabel});

  final String text;

  /// Подсказка заметки (код ошибки); `null` — нет.
  final String? hint;

  /// Подпись действия `Retry`; `null` — действия нет.
  final String? retryLabel;
}

/// Панель Usage дока: шапка, карточки, таблицы `Per turn` и `Per model`
/// (экран 17; D1, D2).
///
/// Почему: расход сессии нужен рядом с лентой, а `codelab_ui` не должен знать
/// ни журнал агента, ни kit. Для чего: только отображение готовых данных и
/// сообщение о нажатиях; раскрытие хода — временное состояние просмотра.
/// Как использовать: слот `ToolPane.usage` дока; app (`WorkbenchUsagePane`)
/// передаёт карточки, строки и колбэки. Ключи: `usage-rebuild`,
/// `usage-export`, `usage-ledger-status`, `usage-card-<id>`,
/// `usage-turn-<id>`, `usage-step-<id>`, `usage-model-<n>`, `usage-retry`,
/// `usage-note`, `usage-progress`.
///
/// Заглушка задачи 1.6 (красные тесты `codelab_usage_pane_test.dart`):
/// реализация — задача 1.7.
class CodeLabUsagePane extends StatefulWidget {
  const CodeLabUsagePane({
    required this.title,
    this.cards = const [],
    this.statusLine,
    this.turns = const [],
    this.models = const [],
    this.loading = false,
    this.refreshing = false,
    this.notes = const [],
    this.showRebuild = false,
    this.showExport = false,
    this.onRebuild,
    this.onExport,
    this.onRetry,
    super.key,
  });

  /// Заголовок шапки (`This session`).
  final String title;
  final List<CodeLabUsageCard> cards;

  /// Строка состояния журнала (`usage-ledger-status`); `null` — нет.
  final String? statusLine;

  /// Строки `Per turn` в порядке показа (от нового к старому).
  final List<CodeLabUsageRow> turns;

  /// Строки `Per model` в порядке показа.
  final List<CodeLabUsageRow> models;

  /// Журнала для показа ещё нет: вместо таблиц индикатор (`usage-progress`).
  final bool loading;

  /// Журнал обновляется при уже показанных данных: индикатор в шапке.
  final bool refreshing;
  final List<CodeLabUsageNote> notes;

  /// Кнопка `Rebuild from log` есть; без [onRebuild] она недоступна.
  final bool showRebuild;

  /// Кнопка `Export CSV` есть; без [onExport] она недоступна.
  final bool showExport;
  final VoidCallback? onRebuild;
  final VoidCallback? onExport;
  final VoidCallback? onRetry;

  @override
  State<CodeLabUsagePane> createState() => _CodeLabUsagePaneState();
}

class _CodeLabUsagePaneState extends State<CodeLabUsagePane> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
