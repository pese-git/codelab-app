import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../atomics/atomics.dart';

/// Вид строки дерева файлов.
///
/// Почему: дерево рисует разные записи по-разному, а решать, какая запись
/// чем является, должен хост (виджет не знает файловой системы, `AGENTS.md`
/// пакета, §2).
///
/// Для чего: [directory] и [file] можно раскрыть и открыть; [outsideLink] —
/// ссылка с целью вне корня (↗), [other] — битая ссылка, сокет или канал: обе
/// показываются, но не раскрываются и не открываются (Q2, D3 change
/// `add-file-preview-and-tree`); [more] — строка «… N more» усечённой папки,
/// [error] — строка ошибки чтения папки. Две последние — просто текст.
enum CodeLabFileTreeRowKind { directory, file, outsideLink, other, more, error }

/// Одна строка плоского списка дерева файлов.
///
/// Почему плоская: дерево виртуализировано (`ListView.builder`), а список
/// строк по раскрытым папкам строит `ProjectFilesCubit` чистой функцией (D1,
/// D6). Виджет не хранит ни раскрытых папок, ни выбора.
///
/// Как использовать: [relativePath] — POSIX-путь от корня, он же ключ строки
/// `file-tree-row-<relativePath>` и должен быть уникален в списке (хост даёт
/// синтетические пути `<папка>/#more` и `<папка>/#error`); [name] — готовая
/// подпись (у [CodeLabFileTreeRowKind.more] и [CodeLabFileTreeRowKind.error]
/// — весь текст); [depth] задаёт отступ; [expanded] выбирает значок
/// раскрытой папки; [loading] показывает индикатор чтения папки.
@immutable
class CodeLabFileTreeRowData {
  const CodeLabFileTreeRowData({
    required this.relativePath,
    required this.name,
    required this.kind,
    this.depth = 0,
    this.expanded = false,
    this.loading = false,
  });

  final String relativePath;
  final String name;
  final CodeLabFileTreeRowKind kind;
  final int depth;
  final bool expanded;
  final bool loading;
}

/// Виртуализированное дерево файлов проекта (артборд `Files`, UX-15, UX-16).
///
/// Почему: десятки тысяч строк не должны строиться разом, а клавиатура
/// должна работать как в проводнике (`workspace-file-browser` «Ленивое
/// перечисление папок»). Решения «что раскрыть, что открыть» принимает хост
/// (`ProjectFilesPane`), здесь только вёрстка, фокус и клавиши.
///
/// Для чего: рисует [rows] с высотой строки [rowExtent]; щелчок и Enter по
/// папке вызывают [onToggleDirectory], по файлу — [onOpenFile]; → раскрывает
/// свёрнутую папку, ← сворачивает раскрытую (оба — через
/// [onToggleDirectory]), ↑/↓ двигают фокус. Ссылка наружу, «прочее», «… N
/// more» и строка ошибки никаких колбэков не вызывают.
///
/// Как использовать: передать готовые [rows] и [selectedPath] (выбранный
/// файл). Перестраивать при каждом новом списке; фокус строки переживает
/// обновление, пока индекс в границах списка.
class CodeLabFileTree extends StatefulWidget {
  const CodeLabFileTree({
    required this.rows,
    this.selectedPath,
    this.onToggleDirectory,
    this.onOpenFile,
    this.autofocus = false,
    super.key,
  });

  /// Высота строки (D13).
  static const rowExtent = 24.0;

  static ValueKey<String> rowKey(String relativePath) =>
      ValueKey('file-tree-row-$relativePath');

  final List<CodeLabFileTreeRowData> rows;
  final String? selectedPath;
  final ValueChanged<CodeLabFileTreeRowData>? onToggleDirectory;
  final ValueChanged<CodeLabFileTreeRowData>? onOpenFile;
  final bool autofocus;

  @override
  State<CodeLabFileTree> createState() => _CodeLabFileTreeState();
}

class _CodeLabFileTreeState extends State<CodeLabFileTree> {
  final _focusNode = FocusNode(debugLabel: 'file-tree');
  final _scroll = ScrollController();
  int _focused = 0;

  @override
  void dispose() {
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int get _focusedIndex =>
      widget.rows.isEmpty ? -1 : _focused.clamp(0, widget.rows.length - 1);

  void _activate(CodeLabFileTreeRowData row) {
    switch (row.kind) {
      case CodeLabFileTreeRowKind.directory:
        widget.onToggleDirectory?.call(row);
      case CodeLabFileTreeRowKind.file:
        widget.onOpenFile?.call(row);
      case CodeLabFileTreeRowKind.outsideLink ||
          CodeLabFileTreeRowKind.other ||
          CodeLabFileTreeRowKind.more ||
          CodeLabFileTreeRowKind.error:
        break;
    }
  }

  void _moveFocus(int delta) {
    if (widget.rows.isEmpty) {
      return;
    }
    final next = (_focusedIndex + delta).clamp(0, widget.rows.length - 1);
    setState(() => _focused = next);
    _scrollIntoView(next);
  }

  void _scrollIntoView(int index) {
    if (!_scroll.hasClients) {
      return;
    }
    final top = index * CodeLabFileTree.rowExtent;
    final bottom = top + CodeLabFileTree.rowExtent;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(bottom - position.viewportDimension);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || widget.rows.isEmpty) {
      return KeyEventResult.ignored;
    }
    final row = widget.rows[_focusedIndex];
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _activate(row);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (row.kind == CodeLabFileTreeRowKind.directory && !row.expanded) {
        widget.onToggleDirectory?.call(row);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (row.kind == CodeLabFileTreeRowKind.directory && row.expanded) {
        widget.onToggleDirectory?.call(row);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final focusedIndex = _focusedIndex;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, _) => ListView.builder(
          controller: _scroll,
          itemExtent: CodeLabFileTree.rowExtent,
          itemCount: widget.rows.length,
          itemBuilder: (context, index) {
            final row = widget.rows[index];
            return _FileTreeRow(
              key: CodeLabFileTree.rowKey(row.relativePath),
              row: row,
              selected: row.relativePath == widget.selectedPath,
              focused: _focusNode.hasFocus && index == focusedIndex,
              onTap: () {
                setState(() => _focused = index);
                _focusNode.requestFocus();
                _activate(row);
              },
            );
          },
        ),
      ),
    );
  }
}

class _FileTreeRow extends StatelessWidget {
  const _FileTreeRow({
    required this.row,
    required this.selected,
    required this.focused,
    required this.onTap,
    super.key,
  });

  final CodeLabFileTreeRowData row;
  final bool selected;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final muted = resources.textFillColorSecondary;
    final background = selected
        ? resources.subtleFillColorSecondary
        : focused
        ? resources.subtleFillColorTertiary
        : null;
    final indent = 8.0 + row.depth * 16;

    final content = switch (row.kind) {
      CodeLabFileTreeRowKind.more || CodeLabFileTreeRowKind.error => [
        Expanded(
          child: CodeLabText(
            row.name,
            role: CodeLabTextRole.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            color: row.kind == CodeLabFileTreeRowKind.error
                ? Colors.warningPrimaryColor
                : muted,
          ),
        ),
      ],
      _ => [
        Icon(_iconOf(row), size: 14, color: _iconColorOf(row, theme, muted)),
        const SizedBox(width: 6),
        Flexible(
          child: CodeLabText(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            color:
                row.kind == CodeLabFileTreeRowKind.outsideLink ||
                    row.kind == CodeLabFileTreeRowKind.other
                ? muted
                : null,
          ),
        ),
        if (row.kind == CodeLabFileTreeRowKind.outsideLink) ...[
          const SizedBox(width: 6),
          // Смысл не передаётся только значком: рядом подпись артборда.
          Text(
            '↗',
            key: ValueKey('file-tree-outside-${row.relativePath}'),
            style: TextStyle(color: muted),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: CodeLabText(
              'outside, not opened',
              role: CodeLabTextRole.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              color: muted,
            ),
          ),
        ],
        if (row.loading) ...[
          const SizedBox(width: 6),
          const CodeLabProgressIndicator(size: 12),
        ],
      ],
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(color: background),
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: 8),
          child: Row(
            children: [
              if (selected)
                SizedBox.shrink(
                  key: ValueKey('file-tree-selected-${row.relativePath}'),
                ),
              ...content,
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconOf(CodeLabFileTreeRowData row) => switch (row.kind) {
    CodeLabFileTreeRowKind.directory =>
      row.expanded ? FluentIcons.open_folder_horizontal : FluentIcons.folder,
    _ => FluentIcons.page,
  };

  static Color _iconColorOf(
    CodeLabFileTreeRowData row,
    FluentThemeData theme,
    Color muted,
  ) => switch (row.kind) {
    CodeLabFileTreeRowKind.directory => theme.accentColor,
    _ => muted,
  };
}
