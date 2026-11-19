/// Таблица сочетаний «Action · Shortcut · Where» с группами.
///
/// Почему: `CodeLabStatusTable` не знает строк-заголовков групп, а ячейки у
/// него — текст или тег; расширять его ради одной страницы значит смешать две
/// таблицы с разной семантикой (change `add-app-keyboard-page`, D6).
///
/// Для чего: шапка колонок и группы с заголовками; строки приходят готовыми
/// от app (тексты, отбор и порядок), таблица только раскладывает их (AGENTS
/// кита §2). Для чтения с экрана заголовок группы — `header`, строка читается
/// как «действие, клавиши, где»; строки только для чтения и не фокусируются,
/// чтобы Tab не останавливался на каждой из них (D9).
///
/// Как использовать: передать три подписи шапки и список
/// [CodeLabShortcutTableGroup]. Ключи групп и строк задаёт вызывающий. Если
/// ширины меньше минимальной, таблица прокручивается по горизонтали внутри
/// своего блока: текст действия и места переносится, плашки нет (D9).
library;

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Строка таблицы: готовые тексты и комбинации.
class CodeLabShortcutTableRow {
  const CodeLabShortcutTableRow({
    required this.key,
    required this.action,
    required this.combos,
    required this.where,
  });

  /// Ключ строки (`settings-keyboard-row-<id>`).
  final Key key;

  /// Текст действия на языке интерфейса.
  final String action;

  /// Комбинации строки; несколько — альтернативы.
  final List<CodeLabKeyCombo> combos;

  /// Текст «Where» на языке интерфейса.
  final String where;
}

/// Группа строк с заголовком.
class CodeLabShortcutTableGroup {
  const CodeLabShortcutTableGroup({
    required this.key,
    required this.title,
    required this.rows,
  });

  /// Ключ заголовка группы (`settings-keyboard-group-<группа>`).
  final Key key;

  /// Текст заголовка на языке интерфейса.
  final String title;

  final List<CodeLabShortcutTableRow> rows;
}

class CodeLabShortcutTable extends StatefulWidget {
  const CodeLabShortcutTable({
    required this.actionHeader,
    required this.shortcutHeader,
    required this.whereHeader,
    required this.groups,
    super.key,
  });

  final String actionHeader;
  final String shortcutHeader;
  final String whereHeader;
  final List<CodeLabShortcutTableGroup> groups;

  /// Минимальная ширина таблицы: уже неё включается горизонтальная прокрутка.
  static const minWidth = 780.0;

  /// Ширина колонки клавиш: самая широкая строка (`Ctrl Alt Backspace`)
  /// помещается без переноса.
  static const _shortcutWidth = 260.0;

  @override
  State<CodeLabShortcutTable> createState() => _CodeLabShortcutTableState();
}

class _CodeLabShortcutTableState extends State<CodeLabShortcutTable> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _table(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final divider = BorderSide(color: resources.dividerStrokeColorDefault);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: resources.dividerStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cells(
            context,
            CodeLabText(widget.actionHeader, role: CodeLabTextRole.strong),
            CodeLabText(widget.shortcutHeader, role: CodeLabTextRole.strong),
            CodeLabText(widget.whereHeader, role: CodeLabTextRole.strong),
          ),
          for (final group in widget.groups) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: resources.subtleFillColorSecondary,
                border: Border(top: divider),
              ),
              child: Semantics(
                key: group.key,
                header: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: CodeLabText(
                      group.title,
                      role: CodeLabTextRole.caption,
                      color: resources.textFillColorSecondary,
                    ),
                  ),
                ),
              ),
            ),
            for (final row in group.rows)
              DecoratedBox(
                decoration: BoxDecoration(border: Border(top: divider)),
                child: Semantics(
                  key: row.key,
                  container: true,
                  label: [
                    row.action,
                    CodeLabKeycaps.labelOf(context, row.combos),
                    row.where,
                  ].join(', '),
                  excludeSemantics: true,
                  child: _cells(
                    context,
                    CodeLabText(row.action),
                    CodeLabKeycaps(combos: row.combos),
                    CodeLabText(
                      row.where,
                      role: CodeLabTextRole.caption,
                      color: resources.textFillColorSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Три колонки: действие и место делят остаток 3:2, клавиши — фиксированная
  /// ширина, чтобы плашки не переносились.
  Widget _cells(
    BuildContext context,
    Widget action,
    Widget shortcut,
    Widget where,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: action),
          const SizedBox(width: 12),
          SizedBox(
            width: CodeLabShortcutTable._shortcutWidth,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: shortcut,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: where),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Строки только для чтения: ни одной остановки обхода Tab (D9).
    return ExcludeFocus(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= CodeLabShortcutTable.minWidth) {
            return _table(context);
          }
          return Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: CodeLabShortcutTable.minWidth,
                child: _table(context),
              ),
            ),
          );
        },
      ),
    );
  }
}
