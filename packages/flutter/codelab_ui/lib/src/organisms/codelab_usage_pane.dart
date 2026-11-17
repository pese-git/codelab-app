import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../atomics/codelab_pressable.dart';
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

/// Панель Usage дока: шапка, карточки, таблицы `Per turn` и `Per model`
/// (экран 17; D1, D2).
///
/// Почему: расход сессии нужен рядом с лентой, а `codelab_ui` не должен знать
/// ни журнал агента, ни kit. Для чего: только отображение готовых данных и
/// сообщение о нажатиях; раскрытие хода — временное состояние просмотра
/// (`codelab_ui/AGENTS.md` §2). Тон карточек, тексты (`~$2.26`, `—`,
/// `Couldn't load usage history.`) и подписи приходят готовыми.
/// Как использовать: слот `ToolPane.usage` дока; app (`WorkbenchUsagePane`)
/// передаёт карточки, строки и колбэки. Высота панели — по содержимому: прокрутку
/// даёт вызывающий. Ключи: `usage-rebuild`, `usage-export`,
/// `usage-ledger-status`, `usage-card-<id>`, `usage-turn-<id>`,
/// `usage-step-<id>`, `usage-model-<n>`, `usage-retry`, `usage-note`,
/// `usage-progress`.
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
  /// Раскрытые ходы: id строки. Живёт, пока открыта панель; между запусками
  /// не хранится (D2 п. 4).
  final Set<String> _expanded = {};

  void _toggle(String id) => setState(
    () => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id),
  );

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
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
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: CodeLabProgressIndicator(
                    key: ValueKey('usage-progress'),
                    size: 14,
                    semanticLabel: 'Loading usage history',
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
                      label: 'Rebuild from log',
                      onPressed: widget.onRebuild,
                    ),
                  if (widget.showExport)
                    CodeLabButton(
                      key: const ValueKey('usage-export'),
                      label: 'Export CSV',
                      onPressed: widget.onExport,
                    ),
                ],
              ),
            ),
          if (widget.statusLine case final line?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CodeLabText(
                line,
                key: const ValueKey('usage-ledger-status'),
                role: CodeLabTextRole.caption,
              ),
            ),
          for (final (index, note) in widget.notes.indexed)
            _NoteView(
              key: ValueKey(index == 0 ? 'usage-note' : 'usage-note-$index'),
              note: note,
              onRetry: widget.onRetry,
            ),
          if (widget.cards.isNotEmpty) _CardGrid(cards: widget.cards),
          if (widget.turns.isNotEmpty)
            _Table(
              title: 'Per turn',
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
              title: 'Per model',
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

/// Таблица с заголовком секции и подписями столбцов.
class _Table extends StatelessWidget {
  const _Table({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: CodeLabText(title, role: CodeLabTextRole.strong)),
              for (final column in const ['Input', 'Output', 'Cost'])
                SizedBox(
                  width: _columnWidth,
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
    );
  }
}

const double _columnWidth = 64;

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
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: CodeLabBadge(
                    label: 'running',
                    tone: CodeLabTone.accent,
                  ),
                ),
              for (final value in [row.input, row.output, row.cost])
                SizedBox(
                  width: _columnWidth,
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
