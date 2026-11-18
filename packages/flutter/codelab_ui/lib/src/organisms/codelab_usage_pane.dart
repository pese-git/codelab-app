import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../atomics/atomics.dart';
import '../atomics/codelab_pressable.dart';
import '../l10n/strings.dart';
import '../rendering/escape_for_display.dart';

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

/// Строка блока `Turn budget`: полоса и подпись одного лимита хода
/// (`usage-budget-<id>`; design.md change `add-desktop-usage-pane`, D9).
///
/// Почему готовые значения: «израсходовано / лимит», тон по доле и доля
/// заполнения считает application (`UsagePaneData.budget`); виджет только
/// рисует (`codelab_ui/AGENTS.md` §2).
///
/// Для чего: Steps, Tokens, Cost, Time. Как использовать: [id] — суффикс
/// ключа (`steps`, `tokens`, `cost`, `time`); [fill] — доля заполнения
/// полосы, виджет ограничивает её диапазоном 0..1; [tone] выше нейтрального
/// рисуется плашкой вокруг [value]; [hint] — подсказка строки; [note] —
/// строка под подписью (`not checked: price unknown`).
class CodeLabUsageBudgetRow {
  const CodeLabUsageBudgetRow({
    required this.id,
    required this.label,
    required this.value,
    required this.fill,
    this.tone = CodeLabTone.neutral,
    this.hint,
    this.note,
  });

  final String id;
  final String label;
  final String value;
  final double fill;
  final CodeLabTone tone;
  final String? hint;
  final String? note;
}

/// Блок `Turn budget` панели Usage: заголовок, строки лимитов и пояснение
/// под ними (`usage-budget`; D9).
///
/// Почему отдельная модель: заголовок `This turn` / `Last turn` и набор строк
/// решает application по статусу сессии и признаку «итог хода» (Q11 (а)).
/// Как использовать: передаётся в [CodeLabUsagePane.budget]; `null` — блока
/// нет. Блок стоит между карточками и `Per turn`.
class CodeLabUsageBudget {
  const CodeLabUsageBudget({
    required this.title,
    required this.rows,
    required this.footnote,
  });

  final String title;
  final List<CodeLabUsageBudgetRow> rows;

  /// Пояснение под блоком (`usage-budget-note`).
  final String footnote;
}

/// Панель Usage дока: шапка, карточки, таблицы `Per turn` и `Per model`
/// (экран 17; D1, D2).
///
/// Почему: расход сессии нужен рядом с лентой, а `codelab_ui` не должен знать
/// ни журнал агента, ни kit. Для чего: только отображение готовых данных и
/// сообщение о нажатиях; раскрытие хода — временное состояние просмотра
/// (`codelab_ui/AGENTS.md` §2). Тон карточек, тексты (`~$2.26`, `—`,
/// `Couldn't load usage history.`) и подписи приходят готовыми.
/// Как использовать: слот `ToolPane.usage` дока; app (`WorkbenchUsagePane`)
/// передаёт карточки, строки и колбэки. Высота панели — по содержимому:
/// прокрутку даёт вызывающий. Ключи: `usage-rebuild`, `usage-export`,
/// `usage-ledger-status` (с необязательной подсказкой `statusHint`),
/// `usage-card-<id>`, `usage-turn-<id>`, `usage-step-<id>`, `usage-model-<n>`, `usage-retry`, `usage-note`,
/// `usage-progress`, блок бюджета — `usage-budget`, `usage-budget-title`,
/// `usage-budget-<id>`, `usage-budget-note`.
class CodeLabUsagePane extends StatefulWidget {
  const CodeLabUsagePane({
    required this.title,
    this.cards = const [],
    this.statusLine,
    this.statusHint,
    this.turns = const [],
    this.models = const [],
    this.budget,
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

  /// Подсказка строки состояния (`Tooltip`); `null` — подсказки нет.
  ///
  /// Почему: штатное обновление ленивого кэша журнала показывается как
  /// `up to date`, а причина остаётся рядом (`fix-usage-pane-live-cards`, D7).
  /// Текст приходит готовым и проходит `escapeForDisplay`: причина — строка
  /// агента. Без [statusLine] не используется.
  final String? statusHint;

  /// Строки `Per turn` в порядке показа (от нового к старому).
  final List<CodeLabUsageRow> turns;

  /// Строки `Per model` в порядке показа.
  final List<CodeLabUsageRow> models;

  /// Блок `Turn budget` между карточками и `Per turn`; `null` — блока нет
  /// (D9).
  final CodeLabUsageBudget? budget;

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
  /// Раскрытые ходы: id строки. Живёт, пока открыта панель; между запусками
  /// не хранится (D2 п. 4).
  final Set<String> _expanded = {};

  void _toggle(String id) => setState(
    () => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id),
  );

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final strings = codeLabStringsOf(context);
    final progress = widget.loading || widget.refreshing;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: CodeLabText(
                  widget.title,
                  role: CodeLabTextRole.strong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (progress)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CodeLabProgressIndicator(
                    key: const ValueKey('usage-progress'),
                    size: 14,
                    semanticLabel: strings.codeLabUsageLoading,
                  ),
                ),
            ],
          ),
          if (widget.showRebuild || widget.showExport)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (widget.showRebuild)
                    CodeLabButton(
                      key: const ValueKey('usage-rebuild'),
                      label: strings.codeLabUsageRebuild,
                      onPressed: widget.onRebuild,
                    ),
                  if (widget.showExport)
                    CodeLabButton(
                      key: const ValueKey('usage-export'),
                      label: strings.codeLabUsageExportCsv,
                      onPressed: widget.onExport,
                    ),
                ],
              ),
            ),
          if (widget.statusLine case final line?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _withHint(
                widget.statusHint,
                CodeLabText(
                  escapeForDisplay(line),
                  key: const ValueKey('usage-ledger-status'),
                  role: CodeLabTextRole.caption,
                ),
              ),
            ),
          for (final (index, note) in widget.notes.indexed)
            _NoteView(
              key: ValueKey(index == 0 ? 'usage-note' : 'usage-note-$index'),
              note: note,
              onRetry: widget.onRetry,
            ),
          if (widget.cards.isNotEmpty) _CardGrid(cards: widget.cards),
          if (widget.budget case final budget?) _BudgetView(budget: budget),
          if (widget.turns.isNotEmpty)
            _Table(
              title: strings.codeLabUsagePerTurn,
              rows: widget.turns,
              children: [
                for (final turn in widget.turns)
                  _TurnView(
                    row: turn,
                    expanded: _expanded.contains(turn.id),
                    onToggle: () => _toggle(turn.id),
                  ),
              ],
            ),
          if (widget.models.isNotEmpty)
            _Table(
              title: strings.codeLabUsagePerModel,
              rows: widget.models,
              children: [
                for (final (index, model) in widget.models.indexed)
                  _RowCells(
                    key: ValueKey('usage-model-$index'),
                    row: model,
                    indent: 0,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Блок `Turn budget`: заголовок, полосы лимитов и пояснение (D9).
///
/// Раскладка, не логика: полосе из данных остаётся только ограничить долю
/// диапазоном 0..1. Ключи: `usage-budget`, `usage-budget-title`,
/// `usage-budget-<id>` (+ `-track`, `-fill`), `usage-budget-note`.
class _BudgetView extends StatelessWidget {
  const _BudgetView({required this.budget});

  final CodeLabUsageBudget budget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('usage-budget'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeLabText(
            escapeForDisplay(budget.title),
            key: const ValueKey('usage-budget-title'),
            role: CodeLabTextRole.strong,
          ),
          for (final row in budget.rows) _BudgetRowView(row: row),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CodeLabText(
              escapeForDisplay(budget.footnote),
              key: const ValueKey('usage-budget-note'),
              role: CodeLabTextRole.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetRowView extends StatelessWidget {
  const _BudgetRowView({required this.row});

  final CodeLabUsageBudgetRow row;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Данные могут прислать долю вне диапазона (больше 100 %, NaN): полоса
    // не должна выходить за дорожку и ронять раскладку.
    final fill = row.fill.isNaN ? 0.0 : row.fill.clamp(0.0, 1.0);
    final barColor = switch (row.tone) {
      CodeLabTone.danger => Colors.red,
      CodeLabTone.warning => Colors.orange,
      _ => theme.accentColor,
    };
    final value = escapeForDisplay(row.value);
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CodeLabText(
                escapeForDisplay(row.label),
                role: CodeLabTextRole.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (row.tone == CodeLabTone.neutral)
              CodeLabText(value, role: CodeLabTextRole.body, maxLines: 1)
            else
              CodeLabBadge(label: value, tone: row.tone),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          key: ValueKey('usage-budget-${row.id}-track'),
          height: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.resources.controlStrongFillColorDefault.withValues(
                alpha: 0.25,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fill,
                heightFactor: 1,
                child: DecoratedBox(
                  key: ValueKey('usage-budget-${row.id}-fill'),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (row.note case final note?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: CodeLabText(
              escapeForDisplay(note),
              role: CodeLabTextRole.caption,
            ),
          ),
      ],
    );
    if (row.hint case final hint?) {
      content = Tooltip(message: escapeForDisplay(hint), child: content);
    }
    return Padding(
      key: ValueKey('usage-budget-${row.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: content,
    );
  }
}

/// Карточки сводки по две в ряд: на ширине дока 400 px четыре в ряд не
/// помещаются (D1).
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards});

  final List<CodeLabUsageCard> cards;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 12 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _CardView(card: cards[i])),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < cards.length
                    ? _CardView(card: cards[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card});

  final CodeLabUsageCard card;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return DecoratedBox(
      key: ValueKey('usage-card-${card.id}'),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CodeLabText(card.title, role: CodeLabTextRole.caption),
            const SizedBox(height: 4),
            if (card.tone == CodeLabTone.neutral)
              CodeLabText(card.value, role: CodeLabTextRole.subtitle)
            else
              CodeLabBadge(label: card.value, tone: card.tone),
            if (card.detail case final detail?)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: CodeLabText(detail, role: CodeLabTextRole.caption),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteView extends StatelessWidget {
  const _NoteView({required this.note, required this.onRetry, super.key});

  final CodeLabUsageNote note;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = CodeLabText(escapeForDisplay(note.text));
    final hint = note.hint;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: hint == null
                ? text
                : Tooltip(message: escapeForDisplay(hint), child: text),
          ),
          if (note.retryLabel case final label?)
            CodeLabButton(
              key: const ValueKey('usage-retry'),
              label: label,
              emphasis: CodeLabButtonEmphasis.subtle,
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}

/// Ширины трёх числовых столбцов таблицы, общие для шапки и всех строк.
///
/// Почему: фиксированные 64 px резали `$0.00058` до `$0.0005` — пользователь
/// видел неверную сумму. Ширина берётся по самому широкому значению таблицы,
/// поэтому значение не обрезается, а столбцы выровнены между строками и шапкой.
class _ColumnWidths extends InheritedWidget {
  const _ColumnWidths({required this.widths, required super.child});

  /// Ширины Input, Output, Cost.
  final List<double> widths;

  static List<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ColumnWidths>()!.widths;

  @override
  bool updateShouldNotify(_ColumnWidths old) => !listEquals(widths, old.widths);
}

/// Зазор между числовыми столбцами.
const double _columnGap = 12;

/// Измеряет значения столбцов таблицы тем же стилем, которым они рисуются.
///
/// Раскладка, а не логика приложения: считаются только размеры готовых строк.
/// Шаги хода учитываются всегда, раскрыт ход или нет, чтобы столбцы не
/// «прыгали» при раскрытии.
List<double> _measureColumns(BuildContext context, List<CodeLabUsageRow> rows) {
  final scaler = MediaQuery.textScalerOf(context);
  final body = CodeLabText.styleOf(context, CodeLabTextRole.body);
  final caption = CodeLabText.styleOf(context, CodeLabTextRole.caption);
  double measure(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final widths = [
    for (final header in _columnTitles(context)) measure(header, caption),
  ];
  void visit(CodeLabUsageRow row, TextStyle? style) {
    final values = [row.input, row.output, row.cost];
    for (var i = 0; i < 3; i++) {
      final width = measure(values[i], style);
      if (width > widths[i]) widths[i] = width;
    }
    for (final child in row.children) {
      visit(child, caption);
    }
  }

  for (final row in rows) {
    visit(row, body);
  }
  // Запас в долю пикселя: округление раскладки не должно переносить значение.
  return [for (final w in widths) w.ceilToDouble() + 1 + _columnGap];
}

/// Заголовки числовых столбцов таблиц Usage на языке интерфейса: Input,
/// Output, Cost. Одна функция на измерение ширины и на отрисовку, чтобы
/// столбец вмещал именно показанный заголовок (русский длиннее, D8).
List<String> _columnTitles(BuildContext context) {
  final strings = codeLabStringsOf(context);
  return [
    strings.codeLabUsageColumnInput,
    strings.codeLabUsageColumnOutput,
    strings.codeLabUsageColumnCost,
  ];
}

/// Таблица с заголовком секции и подписями столбцов.
class _Table extends StatelessWidget {
  const _Table({
    required this.title,
    required this.rows,
    required this.children,
  });

  final String title;

  /// Данные строк — для измерения ширины столбцов.
  final List<CodeLabUsageRow> rows;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final widths = _measureColumns(context, rows);
    return _ColumnWidths(
      widths: widths,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: CodeLabText(title, role: CodeLabTextRole.strong),
                ),
                for (final (i, column) in _columnTitles(context).indexed)
                  SizedBox(
                    width: widths[i],
                    child: CodeLabText(
                      column,
                      role: CodeLabTextRole.caption,
                      maxLines: 1,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Строка хода: раскрывается до шагов по клику, Enter и Space.
class _TurnView extends StatelessWidget {
  const _TurnView({
    required this.row,
    required this.expanded,
    required this.onToggle,
  });

  final CodeLabUsageRow row;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final expandable = row.children.isNotEmpty;
    // Раскрытый ход: строка `subagents · N runs` идёт после шагов (D2 п. 4
    // change `add-desktop-usage-pane`) — это итог хода, а не подпись к нему.
    final noteAfterSteps = expanded && expandable && row.note != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RowCells(
          key: ValueKey('usage-turn-${row.id}'),
          row: row,
          showNote: !noteAfterSteps,
          indent: 0,
          onPressed: expandable ? onToggle : null,
          chevron: expandable
              ? (expanded
                    ? FluentIcons.chevron_down_small
                    : FluentIcons.chevron_right_small)
              : null,
        ),
        if (expanded)
          for (final step in row.children)
            _RowCells(
              key: ValueKey('usage-step-${step.id}'),
              row: step,
              indent: 20,
              caption: true,
            ),
        if (noteAfterSteps)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2, bottom: 4),
            child: CodeLabText(
              escapeForDisplay(row.note!),
              role: CodeLabTextRole.caption,
            ),
          ),
      ],
    );
  }
}

/// Одна строка таблицы: подпись, необязательная пометка и три столбца.
class _RowCells extends StatelessWidget {
  const _RowCells({
    required this.row,
    required this.indent,
    this.onPressed,
    this.chevron,
    this.caption = false,
    this.showNote = true,
    super.key,
  });

  final CodeLabUsageRow row;

  /// `false` — строку [CodeLabUsageRow.note] рисует хозяин (ход после шагов).
  final bool showNote;
  final double indent;
  final VoidCallback? onPressed;
  final IconData? chevron;
  final bool caption;

  @override
  Widget build(BuildContext context) {
    final role = caption ? CodeLabTextRole.caption : CodeLabTextRole.body;
    final widths = _ColumnWidths.of(context);
    final label = CodeLabText(
      escapeForDisplay(row.label),
      role: role,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    Widget content = Padding(
      padding: EdgeInsets.fromLTRB(indent, 4, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (chevron != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4, top: 3),
                  child: Icon(chevron, size: 10),
                ),
              Expanded(child: label),
              if (row.running)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: CodeLabBadge(
                    label: codeLabStringsOf(context).codeLabUsageRunning,
                    tone: CodeLabTone.accent,
                  ),
                ),
              for (final (i, value) in [
                row.input,
                row.output,
                row.cost,
              ].indexed)
                SizedBox(
                  width: widths[i],
                  child: CodeLabText(value, role: role, maxLines: 1),
                ),
            ],
          ),
          if (showNote && row.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: CodeLabText(
                escapeForDisplay(row.note!),
                role: CodeLabTextRole.caption,
              ),
            ),
        ],
      ),
    );
    if (row.hint case final hint?) {
      content = Tooltip(message: escapeForDisplay(hint), child: content);
    }
    if (onPressed == null) {
      return content;
    }
    return CodeLabPressable(
      onPressed: onPressed,
      builder: (context, hovered, focused) => DecoratedBox(
        decoration: BoxDecoration(
          color: hovered || focused
              ? FluentTheme.of(context).resources.subtleFillColorSecondary
              : null,
        ),
        child: content,
      ),
    );
  }
}

/// Оборачивает [child] в `Tooltip`, если подсказка есть (D7); текст проходит
/// `escapeForDisplay`, как остальные подсказки панели.
Widget _withHint(String? hint, Widget child) => hint == null
    ? child
    : Tooltip(message: escapeForDisplay(hint), child: child);
