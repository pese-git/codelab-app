import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../rendering/escape_for_display.dart';

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
    this.secondary,
    this.tags = const [],
    this.untrusted = false,
  });

  /// Текст ячейки (при [tone] — подпись индикатора).
  final String text;

  /// Тон индикатора состояния; `null` — обычный текст.
  final CodeLabStatusTone? tone;

  /// Моноширинная роль (имена, сообщения об ошибках).
  final bool mono;

  /// Вторичный цвет (прочерк «нет значения»).
  final bool muted;

  /// Вторая строка приглушённым цветом (описание навыка под именем).
  ///
  /// Почему: страница «Skills & extensions» (change `add-app-skills-page`,
  /// D12) показывает имя и описание в одной колонке. Строка ограничена двумя
  /// строками, полный текст — в подсказке; `null` — второй строки нет.
  final String? secondary;

  /// Теги после основного текста («Overrides user skill», «1 warning»).
  final List<CodeLabStatusTableTag> tags;

  /// Текст ячейки пришёл из файла и недоверен (D12, `AGENTS.md` §10).
  ///
  /// Для чего: управляющие, невидимые и bidi-символы ([text], [secondary] и
  /// подсказка) становятся видимыми `\uXXXX`; текст — только простой, без
  /// markdown и ссылок. По умолчанию `false`: ячейки MCP servers прежние.
  final bool untrusted;
}

/// Тег ячейки [CodeLabStatusTable]: подпись и тон `CodeLabBadge`.
///
/// Почему модель: тон выбирает вызывающий (виджет смысла данных не знает).
class CodeLabStatusTableTag {
  const CodeLabStatusTableTag(
    this.label, {
    this.tone = CodeLabTone.neutral,
    this.tooltip,
  });

  /// Подсказка тега (например, текст предупреждения со ссылкой на файл).
  ///
  /// При `untrusted` ячейки показывается через `escapeForDisplay`.
  final String? tooltip;

  /// Подпись тега.
  final String label;

  /// Тон тега.
  final CodeLabTone tone;
}

/// Переключатель строки [CodeLabStatusTable] вместо кнопки действия.
///
/// Как использовать: [onChanged] получает новое значение; `null` — переключатель
/// неактивен, а [tooltip] объясняет причину (D12). [label] — подпись для
/// чтения с экрана. Решение о записи принимает владелец, не виджет.
class CodeLabStatusTableToggle {
  const CodeLabStatusTableToggle({
    required this.value,
    required this.onChanged,
    required this.label,
    this.tooltip,
    this.key,
  });

  /// Текущее значение.
  final bool value;

  /// Смена значения; `null` — переключатель неактивен.
  final ValueChanged<bool>? onChanged;

  /// Подпись для чтения с экрана.
  final String label;

  /// Подсказка (причина неактивности).
  final String? tooltip;

  /// Ключ переключателя (для тестов владельца).
  final Key? key;
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
  const CodeLabStatusTableRow({
    required this.cells,
    this.action,
    this.toggle,
    this.key,
  }) : assert(
         toggle == null || action == null,
         'У строки либо действие, либо переключатель',
       );

  /// Ячейки по порядку колонок.
  final List<CodeLabStatusTableCell> cells;

  /// Действие строки; `null` — колонка действий пуста.
  final CodeLabStatusTableAction? action;

  /// Переключатель строки; занимает колонку действий вместо [action].
  final CodeLabStatusTableToggle? toggle;

  /// Ключ виджета строки (для тестов владельца).
  final Key? key;
}

/// Таблица состояния с колонками и действием или переключателем строки.
///
/// Почему: панель «Agent status» страницы «MCP servers» (артборд `Mcp`,
/// `ListView (table)`) показывает `SERVER · STATE · TOOLS · LAST ERROR` и
/// «Reconnect» в строке; таблиц в `codelab_ui` не было (design.md change
/// `add-provider-setup-ui`, D19).
///
/// Второе употребление — таблица навыков страницы «Skills & extensions»
/// (change `add-app-skills-page`, D12): вторая строка и теги ячейки,
/// переключатель вместо действия, веса колонок, экранирование недоверенного
/// текста; без новых параметров вёрстка прежняя.
///
/// Для чего: только вёрстка. По умолчанию колонки равны, [columnFlex] задаёт
/// веса; ячейки всех строк стоят под заголовками. Последняя колонка — действие
/// строки или переключатель (не оба сразу) без видимого заголовка (подпись
/// [actionsLabel] — для чтения с экрана). Бизнес-логики и знания о MCP или
/// навыках нет.
///
/// Как использовать: `CodeLabStatusTable(columns: [...], rows: [...])`;
/// число ячеек строки равно числу колонок, длина [columnFlex] — тоже
/// (`assert` конструктора), веса положительны (`assert` в `build`).
class CodeLabStatusTable extends StatelessWidget {
  const CodeLabStatusTable({
    required this.columns,
    required this.rows,
    this.actionsLabel = 'Actions',
    this.columnFlex,
    super.key,
  }) : assert(
         columnFlex == null || columnFlex.length == columns.length,
         'columnFlex must match columns',
       );

  /// Заголовки колонок (без колонки действий).
  final List<String> columns;

  /// Строки таблицы.
  final List<CodeLabStatusTableRow> rows;

  /// Скрытая подпись колонки действий для чтения с экрана.
  final String actionsLabel;

  /// Веса ширины колонок (без колонки действий); `null` — все равны 1.
  ///
  /// Почему: при равных колонках на узкой странице (~400 pt) заголовок
  /// «LAST ERROR» обрезался, хотя «TOOLS» оставлял пустое место. Широкой
  /// колонке — самой длинной по значениям — владелец даёт больший вес, как
  /// авто-ширина колонок в артборде `Mcp`. Длина равна числу [columns],
  /// веса положительны. Страница «Skills & extensions» задаёт веса так же
  /// (change `add-app-skills-page`, D12).
  final List<int>? columnFlex;

  static const _actionWidth = 120.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  @override
  Widget build(BuildContext context) {
    // Длину проверяет конструктор; положительность — здесь: `every` нельзя
    // вычислить в `assert` константного конструктора.
    assert(
      columnFlex == null || columnFlex!.every((f) => f > 0),
      'columnFlex: веса положительны',
    );
    final theme = FluentTheme.of(context);
    final secondary = theme.resources.textFillColorSecondary;
    final stroke = theme.resources.cardStrokeColorDefault;
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono)!;
    final body = CodeLabText.styleOf(context, CodeLabTextRole.body)!;

    Widget tagWidget(CodeLabStatusTableTag tag, bool untrusted) {
      Widget badge = CodeLabBadge(
        label: untrusted ? escapeForDisplay(tag.label) : tag.label,
        tone: tag.tone,
      );
      if (tag.tooltip case final message?) {
        badge = Tooltip(
          message: untrusted ? escapeForDisplay(message) : message,
          child: badge,
        );
      }
      return badge;
    }

    Widget cell(CodeLabStatusTableCell cell) {
      String shown(String value) =>
          cell.untrusted ? escapeForDisplay(value) : value;
      if (cell.tone case final tone?) {
        return CodeLabStatusIndicator(label: shown(cell.text), tone: tone);
      }
      var style = cell.mono ? mono : body;
      if (cell.muted) {
        style = style.copyWith(color: secondary);
      }
      final text = Text(shown(cell.text), style: style);
      final second = cell.secondary;
      if (second == null && cell.tags.isEmpty) return text;
      final head = cell.tags.isEmpty
          ? text
          : Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                text,
                for (final tag in cell.tags) tagWidget(tag, cell.untrusted),
              ],
            );
      if (second == null) return head;
      final shownSecond = shown(second);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          head,
          Tooltip(
            message: shownSecond,
            child: Text(
              shownSecond,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: body.copyWith(color: secondary),
            ),
          ),
        ],
      );
    }

    Widget toggle(CodeLabStatusTableToggle toggle) {
      Widget control = ToggleSwitch(
        key: toggle.key,
        checked: toggle.value,
        onChanged: toggle.onChanged,
        semanticLabel: escapeForDisplay(toggle.label),
      );
      if (toggle.tooltip case final message?) {
        control = Tooltip(message: escapeForDisplay(message), child: control);
      }
      return Align(alignment: Alignment.centerRight, child: control);
    }

    Widget line(List<Widget> cells, Widget actions, {Border? border}) =>
        DecoratedBox(
          decoration: BoxDecoration(border: border),
          child: Padding(
            padding: _padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < cells.length; i++)
                  Expanded(flex: columnFlex?[i] ?? 1, child: cells[i]),
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
              // Заголовок не переносится по пробелу («LAST / ERROR»). Ширину
              // колонок подбирает владелец через [columnFlex]; многоточие с
              // подсказкой — запасной вариант для совсем узкой колонки, где
              // и по весам заголовок не помещается. Длинные значения ячеек не обрезаем,
              // они переносятся.
              Tooltip(
                message: title,
                child: Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: mono.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ], Semantics(label: actionsLabel, child: const SizedBox(height: 18))),
          for (final row in rows)
            KeyedSubtree(
              key: row.key,
              child: line(
                [for (final item in row.cells) cell(item)],
                row.toggle != null
                    ? toggle(row.toggle!)
                    : row.action == null
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
