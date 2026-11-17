import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Что показывает просмотр файла (закрытая иерархия).
///
/// Почему: просмотр не должен показать содержимое двоичного или слишком
/// большого файла, поэтому у такого состояния текста просто нет (D4 change
/// `add-file-preview-and-tree`). Виджет не читает файлы и не решает, что
/// «двоичное»: это делает `ProjectFiles` kit, а хост переводит его ответ в
/// одно из состояний.
///
/// Как использовать: хост строит значение фабриками; классы вариантов публичны,
/// чтобы тесты хоста могли проверить, что именно он собрал.
/// [CodeLabFilePreviewContent.text] несёт текст,
/// [CodeLabFilePreviewContent.binary] и [CodeLabFilePreviewContent.tooLarge] —
/// готовую подпись размера («24 KB», «3 MB»), [CodeLabFilePreviewContent.failed]
/// — готовый текст ошибки. Подписи и тексты форматирует хост.
sealed class CodeLabFilePreviewContent {
  const CodeLabFilePreviewContent();

  /// Файл читается.
  const factory CodeLabFilePreviewContent.loading() = CodeLabFilePreviewLoading;

  /// Текст файла как есть.
  const factory CodeLabFilePreviewContent.text(String text) =
      CodeLabFilePreviewText;

  /// Двоичный файл размером [sizeLabel].
  const factory CodeLabFilePreviewContent.binary(String sizeLabel) =
      CodeLabFilePreviewBinary;

  /// Файл больше лимита просмотра, размер — [sizeLabel].
  const factory CodeLabFilePreviewContent.tooLarge(String sizeLabel) =
      CodeLabFilePreviewTooLarge;

  /// Чтение не удалось; [message] показывается как есть.
  const factory CodeLabFilePreviewContent.failed(String message) =
      CodeLabFilePreviewFailed;
}

/// Файл читается.
final class CodeLabFilePreviewLoading extends CodeLabFilePreviewContent {
  const CodeLabFilePreviewLoading();
}

/// Текст файла.
final class CodeLabFilePreviewText extends CodeLabFilePreviewContent {
  const CodeLabFilePreviewText(this.text);
  final String text;
}

/// Двоичный файл.
final class CodeLabFilePreviewBinary extends CodeLabFilePreviewContent {
  const CodeLabFilePreviewBinary(this.sizeLabel);
  final String sizeLabel;
}

/// Файл больше лимита.
final class CodeLabFilePreviewTooLarge extends CodeLabFilePreviewContent {
  const CodeLabFilePreviewTooLarge(this.sizeLabel);
  final String sizeLabel;
}

/// Чтение не удалось.
final class CodeLabFilePreviewFailed extends CodeLabFilePreviewContent {
  const CodeLabFilePreviewFailed(this.message);
  final String message;
}

/// Просмотр файла только для чтения: путь, «Copy path», предупреждение о
/// секретах и текст с номерами строк (артборд `Files`, UX-15).
///
/// Почему: Q5 — в первой версии текст моноширинный и без подсветки
/// (подсветка появится вместе с `add-desktop-markdown`, D4); Q3 — файл с
/// секретами показывается как есть, но с предупреждением; Q14 — над текстом
/// относительный путь и «Copy path».
///
/// Для чего: только вёрстка. Строки виртуализированы (`ListView.builder` с
/// фиксированной высотой), текст выделяется мышью, редактирования и записи
/// нет. Копирование в буфер обмена делает хост: виджет отдаёт [onCopyPath]
/// только [relativePath] (никогда содержимое или абсолютный путь).
///
/// Как использовать: [content] — состояние просмотра; [maybeSecret] включает
/// `InfoBar` `file-preview-secret-warning`; [highlightLine] (с 1) подсвечивает
/// строку и прокручивает к ней (нужен «Open file» итерации 5), без него
/// просмотр начинается с первой строки.
class CodeLabFilePreview extends StatefulWidget {
  const CodeLabFilePreview({
    required this.relativePath,
    required this.content,
    this.maybeSecret = false,
    this.highlightLine,
    this.onCopyPath,
    super.key,
  });

  /// Высота строки текста.
  static const lineExtent = 18.0;

  /// Сколько строк контекста оставляется над подсвеченной строкой.
  static const _contextLines = 3;

  final String relativePath;
  final CodeLabFilePreviewContent content;
  final bool maybeSecret;
  final int? highlightLine;
  final ValueChanged<String>? onCopyPath;

  @override
  State<CodeLabFilePreview> createState() => _CodeLabFilePreviewState();
}

class _CodeLabFilePreviewState extends State<CodeLabFilePreview> {
  late ScrollController _scroll = ScrollController(
    initialScrollOffset: _offsetFor(widget.highlightLine),
  );
  List<String> _lines = const [];

  @override
  void initState() {
    super.initState();
    _lines = _linesOf(widget.content);
  }

  @override
  void didUpdateWidget(CodeLabFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameText =
        identical(oldWidget.content, widget.content) ||
        (oldWidget.content is CodeLabFilePreviewText &&
            widget.content is CodeLabFilePreviewText &&
            (oldWidget.content as CodeLabFilePreviewText).text ==
                (widget.content as CodeLabFilePreviewText).text);
    if (!sameText) {
      _lines = _linesOf(widget.content);
    }
    // Другой файл или другая строка — новое положение прокрутки; тот же
    // текст и та же строка (перестроение при обновлении состояния) позицию
    // пользователя не сбрасывает.
    if (!sameText ||
        oldWidget.relativePath != widget.relativePath ||
        oldWidget.highlightLine != widget.highlightLine) {
      _scroll.dispose();
      _scroll = ScrollController(
        initialScrollOffset: _offsetFor(widget.highlightLine),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static double _offsetFor(int? line) {
    if (line == null || line <= 1) {
      return 0;
    }
    final above = line - 1 - CodeLabFilePreview._contextLines;
    return above <= 0 ? 0 : above * CodeLabFilePreview.lineExtent;
  }

  /// Строки текста без пустого хвоста после последнего перевода строки и без
  /// `\r` Windows-окончаний.
  static List<String> _linesOf(CodeLabFilePreviewContent content) {
    if (content is! CodeLabFilePreviewText) {
      return const [];
    }
    final lines = content.text.split('\n');
    if (lines.length > 1 && lines.last.isEmpty) {
      lines.removeLast();
    }
    return [
      for (final line in lines)
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('file-preview'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PathRow(
            relativePath: widget.relativePath,
            onCopyPath: widget.onCopyPath,
          ),
          if (widget.maybeSecret)
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: _SecretWarning(),
            ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = FluentTheme.of(context);
    final muted = theme.resources.textFillColorSecondary;
    switch (widget.content) {
      case CodeLabFilePreviewLoading():
        return const Center(child: CodeLabProgressIndicator());
      case CodeLabFilePreviewBinary(:final sizeLabel):
        return _Notice('Binary file ($sizeLabel)', color: muted);
      case CodeLabFilePreviewTooLarge(:final sizeLabel):
        return _Notice('File too large to preview ($sizeLabel)', color: muted);
      case CodeLabFilePreviewFailed(:final message):
        return _Notice(message, color: Colors.warningPrimaryColor);
      case CodeLabFilePreviewText():
        break;
    }
    final gutter = '${_lines.length}'.length;
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    final highlight = theme.accentColor.withValues(alpha: 0.18);
    final line = widget.highlightLine;
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        itemExtent: CodeLabFilePreview.lineExtent,
        itemCount: _lines.length,
        itemBuilder: (context, index) {
          final number = index + 1;
          final isHighlighted = number == line;
          final row = Row(
            children: [
              SizedBox(
                width: 12.0 + gutter * 8,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '$number',
                    textAlign: TextAlign.right,
                    style: mono?.copyWith(color: muted),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _lines[index],
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: mono,
                ),
              ),
            ],
          );
          return SizedBox(
            key: ValueKey('file-preview-line-$number'),
            child: isHighlighted
                ? DecoratedBox(
                    key: const ValueKey('file-preview-highlighted-line'),
                    decoration: BoxDecoration(color: highlight),
                    child: row,
                  )
                : row,
          );
        },
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.relativePath, required this.onCopyPath});

  final String relativePath;
  final ValueChanged<String>? onCopyPath;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: KeyedSubtree(
              key: const ValueKey('file-preview-path'),
              child: CodeLabText(
                relativePath,
                role: CodeLabTextRole.mono,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (onCopyPath != null)
            CodeLabButton(
              key: const ValueKey('file-preview-copy-path'),
              label: 'Copy path',
              icon: FluentIcons.copy,
              emphasis: CodeLabButtonEmphasis.subtle,
              onPressed: () => onCopyPath!(relativePath),
            ),
        ],
      ),
    );
  }
}

class _SecretWarning extends StatelessWidget {
  const _SecretWarning();

  @override
  Widget build(BuildContext context) {
    return const KeyedSubtree(
      key: ValueKey('file-preview-secret-warning'),
      child: InfoBar(
        title: Text('This file may contain secrets.'),
        severity: InfoBarSeverity.warning,
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Align(
        alignment: Alignment.topLeft,
        child: CodeLabText(text, color: color),
      ),
    );
  }
}
