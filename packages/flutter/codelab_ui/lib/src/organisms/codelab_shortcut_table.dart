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

  /// Строки группы в порядке показа; группа без строк вызывающим не
  /// передаётся (при поиске пустые группы скрываются целиком, D8).
  final List<CodeLabShortcutTableRow> rows;
}

/// Таблица «Action · Shortcut · Where» с группами, только для чтения.
///
/// Почему отдельный виджет и состояние: см. описание библиотеки; состояние
/// нужно ради `ScrollController` горизонтальной прокрутки, которую таблица
/// включает сама в узком теле (D9).
///
/// Для чего и как использовать: страница «Keyboard» передаёт три подписи
/// шапки и группы со строками; ключи групп и строк задаёт вызывающий.
class CodeLabShortcutTable extends StatefulWidget {
  const CodeLabShortcutTable({
    required this.actionHeader,
    required this.shortcutHeader,
    required this.whereHeader,
    required this.groups,
    super.key,
  });

  /// Подпись колонки «Action» на языке интерфейса. Три подписи шапки
  /// приходят от app: кит текстов страницы не знает и не переводит их (D5).
  final String actionHeader;

  /// Подпись колонки «Shortcut» (клавиши).
  final String shortcutHeader;

  /// Подпись колонки «Where» (где сочетание действует).
  final String whereHeader;

  /// Группы по порядку: заголовок и готовые строки. Отбор, порядок и тексты
  /// решает app, таблица только раскладывает их (AGENTS кита §2).
  final List<CodeLabShortcutTableGroup> groups;

  /// Минимальная ширина таблицы: уже неё включается горизонтальная
  /// прокрутка.
  ///
  /// Почему 380: при минимальном окне app (800 px) тело страницы — окно минус
  /// навигация настроек (около 320 px) и поля 2 × 40, то есть около 400 px, и
  /// все три колонки должны быть видны без прокрутки: «Action» и «Where»
  /// гибкие и переносят текст, колонка клавиш занимает ширину самой широкой
  /// строки (D9; ручная проверка на macOS). Прокрутка нужна только для
  /// действительно узкой области (уже 380 px).
  static const minWidth = 380.0;

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

  Widget _table(BuildContext context, double shortcutWidth) {
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
            shortcutWidth,
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
                    shortcutWidth,
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

  /// Три колонки: действие и место делят остаток 3:2, клавиши — ширина
  /// самой широкой строки ([shortcutWidth]), чтобы плашки не переносились и
  /// не сжимались.
  Widget _cells(
    double shortcutWidth,
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
            width: shortcutWidth,
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
    // Колонка клавиш — по самой широкой строке при текущих шрифтах.
    var shortcutWidth = 0.0;
    for (final group in widget.groups) {
      for (final row in group.rows) {
        final width = CodeLabKeycaps.widthOf(context, row.combos);
        if (width > shortcutWidth) shortcutWidth = width;
      }
    }
    shortcutWidth = shortcutWidth.ceilToDouble() + 2;
    const minWidth = CodeLabShortcutTable.minWidth;
    // Строки только для чтения: ни одной остановки обхода Tab (D9).
    return ExcludeFocus(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= minWidth) {
            return _table(context, shortcutWidth);
          }
          return Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: minWidth,
                child: _table(context, shortcutWidth),
              ),
            ),
          );
        },
      ),
    );
  }
}
