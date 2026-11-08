import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Ячейка строки [CodeLabStatusTable].
///
/// Почему модель, а не `Widget`: таблица не знает о MCP, но ячейки бывают
/// трёх видов артборда `Mcp` — моноширинное имя, тег состояния и приглушённый
/// прочерк; значения и колбэки проще проверять, чем готовые виджеты.
///
/// Как использовать: [tone] задан — ячейка рисуется `CodeLabStatusIndicator`
/// с подписью [text]; [mono] — роль `mono`; [muted] — вторичный цвет.
class CodeLabStatusTableCell {
  const CodeLabStatusTableCell(
    this.text, {
    this.tone,
    this.mono = false,
    this.muted = false,
  });

  /// Текст ячейки (при [tone] — подпись индикатора).
  final String text;

  /// Тон индикатора состояния; `null` — обычный текст.
  final CodeLabStatusTone? tone;

  /// Моноширинная роль (имена, сообщения об ошибках).
  final bool mono;

  /// Вторичный цвет (прочерк «нет значения»).
  final bool muted;
}

/// Действие строки [CodeLabStatusTable] (кнопка «Reconnect» артборда).
///
/// [onPressed] `null` — кнопка неактивна; [key] нужен владельцу для тестов.
class CodeLabStatusTableAction {
  const CodeLabStatusTableAction({
    required this.label,
    required this.onPressed,
    this.key,
  });

  /// Подпись кнопки.
  final String label;

  /// Нажатие; `null` — кнопка неактивна.
  final VoidCallback? onPressed;

  /// Ключ кнопки (для тестов владельца).
  final Key? key;
}

/// Строка [CodeLabStatusTable]: [cells] по числу колонок и необязательное
/// [action]; у строки без действия колонка действий остаётся пустой.
class CodeLabStatusTableRow {
  const CodeLabStatusTableRow({required this.cells, this.action, this.key});

  /// Ячейки по порядку колонок.
  final List<CodeLabStatusTableCell> cells;

  /// Действие строки; `null` — колонка действий пуста.
  final CodeLabStatusTableAction? action;

  /// Ключ виджета строки (для тестов владельца).
  final Key? key;
}

/// Таблица состояния с колонками и действием строки.
///
/// Почему: панель «Agent status» страницы «MCP servers» (артборд `Mcp`,
/// `ListView (table)`) показывает `SERVER · STATE · TOOLS · LAST ERROR` и
/// «Reconnect» в строке; таблиц в `codelab_ui` не было (design.md change
/// `add-provider-setup-ui`, D19).
///
/// Для чего: только вёрстка. Колонки одинаковой ширины выравнивают ячейки
/// всех строк под заголовками; последняя колонка действий без видимого
/// заголовка (подпись [actionsLabel] — для чтения с экрана). Бизнес-логики и
/// знания о MCP нет.
///
/// Как использовать: `CodeLabStatusTable(columns: [...], rows: [...])`;
/// число ячеек строки равно числу колонок.
class CodeLabStatusTable extends StatelessWidget {
  const CodeLabStatusTable({
    required this.columns,
    required this.rows,
    this.actionsLabel = 'Actions',
    super.key,
  });

  /// Заголовки колонок (без колонки действий).
  final List<String> columns;

  /// Строки таблицы.
  final List<CodeLabStatusTableRow> rows;

  /// Скрытая подпись колонки действий для чтения с экрана.
  final String actionsLabel;

  static const _actionWidth = 120.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final secondary = theme.resources.textFillColorSecondary;
    final stroke = theme.resources.cardStrokeColorDefault;
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono)!;
    final body = CodeLabText.styleOf(context, CodeLabTextRole.body)!;

    Widget cell(CodeLabStatusTableCell cell) {
      if (cell.tone case final tone?) {
        return CodeLabStatusIndicator(label: cell.text, tone: tone);
      }
      var style = cell.mono ? mono : body;
      if (cell.muted) {
        style = style.copyWith(color: secondary);
      }
      return Text(cell.text, style: style);
    }

    Widget line(List<Widget> cells, Widget actions, {Border? border}) =>
        DecoratedBox(
          decoration: BoxDecoration(border: border),
          child: Padding(
            padding: _padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (final child in cells) Expanded(child: child),
                SizedBox(width: _actionWidth, child: actions),
              ],
            ),
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(color: stroke),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line([
            for (final title in columns)
              Text(
                title,
                style: mono.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ], Semantics(label: actionsLabel, child: const SizedBox(height: 18))),
          for (final row in rows)
            KeyedSubtree(
              key: row.key,
              child: line(
                [for (final item in row.cells) cell(item)],
                row.action == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerRight,
                        child: CodeLabButton(
                          key: row.action!.key,
                          label: row.action!.label,
                          onPressed: row.action!.onPressed,
                          emphasis: CodeLabButtonEmphasis.subtle,
                        ),
                      ),
                border: Border(top: BorderSide(color: stroke)),
              ),
            ),
        ],
      ),
    );
  }
}
