import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../atomics/atomics.dart';
import 'codelab_code_highlighter.dart';
import 'codelab_code_theme.dart';
import 'codelab_markdown_row.dart';
import 'escape_for_display.dart';
import 'codelab_markdown_stats.dart';

/// Блок кода в ответе агента: подпись языка, «Copy», код моноширинно.
///
/// Почему: встроенный блок пакета `gpt_markdown` берёт цвета и значки из
/// Material и в тёмной теме Fluent остаётся светлым; к тому же при
/// копировании выделения подпись языка прилипает к коду (прототип
/// `add-desktop-markdown`, факты 6 и 7; D4).
///
/// Для чего: единый блок кода ленты. Подпись и кнопка лежат внутри
/// `SelectionContainer.disabled`, поэтому выделение ответа содержит только
/// код. «Copy» кладёт в буфер исходный код без ограды. Незакрытый блок
/// ([closed] == false) рисуется тем же моноширинным текстом без кнопки:
/// копировать недописанный код нечего (DSK-6). Закрытый блок подсвечивается
/// по языку ограды палитрой [CodeLabCodeTheme] (D4, DSK-19): код в пределах
/// синхронного порога токенизируется в `initState` (в первом build уже с
/// цветом, без перерисовки), больший — в фоне через [CodeLabCodeHighlighter]
/// (до результата без цвета, затем одна перерисовка), а результат после
/// размонтирования или смены кода отбрасывается (A4, DSK-5, DSK-6).
///
/// Как использовать: строится только builder'ом `CodeLabMarkdownConfig` —
/// конструктор требует модель строки, снаружи `rendering/` блок не создаётся
/// (класс экспортирован ради `find.byType` в тестах).
/// [row] — модель строки: из неё `State` берёт id и порядковый номер блока в
/// ответе при монтировании и хранит его до размонтирования; из них
/// складывается ключ кнопки `code-copy-<id>-<номер>`.
class CodeLabCodeBlock extends StatefulWidget {
  const CodeLabCodeBlock({
    required this.row,
    required this.language,
    required this.code,
    required this.closed,
    required this.highlighter,
    super.key,
  });

  /// Ключ кнопки «Copy» блока [index] в строке [id].
  static ValueKey<String> copyKey(String id, int index) =>
      ValueKey('code-copy-$id-$index');

  final CodeLabMarkdownRowModel row;

  /// Язык из info-строки ограды; пустая строка — язык не указан.
  final String language;
  final String code;
  final bool closed;

  /// Подсветка кода; общая с конфигурацией markdown.
  final CodeLabCodeHighlighter highlighter;

  @override
  State<CodeLabCodeBlock> createState() => _CodeLabCodeBlockState();
}

class _CodeLabCodeBlockState extends State<CodeLabCodeBlock> {
  late final String _id = widget.row.id;
  late final int _index;

  String get _statsKey => '$_id-$_index';

  @override
  void initState() {
    super.initState();
    _index = widget.row.claim(widget.language, widget.code, widget.closed);
    assert(CodeLabMarkdownStats.noteCodeBlockMount(_statsKey));
    _resolveHighlight();
  }

  /// Токены подсветки текущего кода; `null` — код без цвета.
  List<CodeLabCodeToken>? _tokens;

  /// Для какого кода идёт фоновая токенизация: ответ на другой код или после
  /// размонтирования отбрасывается.
  String? _pendingFor;

  @override
  void didUpdateWidget(CodeLabCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language ||
        oldWidget.closed != widget.closed) {
      _resolveHighlight();
    }
  }

  /// Подбирает подсветку для текущего кода. Незакрытый блок остаётся без
  /// цвета (DSK-6), подсветка запускается только после закрытия ограды.
  void _resolveHighlight() {
    _pendingFor = null;
    _tokens = null;
    if (!widget.closed) return;
    final highlighter = widget.highlighter;
    final language = widget.language;
    final code = widget.code;
    switch (highlighter.modeFor(language, code)) {
      case CodeLabHighlightMode.none:
        return;
      case CodeLabHighlightMode.sync:
        _tokens = highlighter.highlightSync(language, code);
      case CodeLabHighlightMode.background:
        final cached = highlighter.cached(language, code);
        if (cached != null) {
          _tokens = cached;
          return;
        }
        _pendingFor = code;
        unawaited(
          highlighter.highlightInBackground(language, code).then((tokens) {
            if (!mounted || _pendingFor != code || widget.code != code) return;
            setState(() {
              _pendingFor = null;
              _tokens = tokens;
            });
          }),
        );
    }
  }

  @override
  void dispose() {
    _pendingFor = null;
    widget.row.release(_index);
    super.dispose();
  }

  /// Копирует код. Сбой буфера не теряется (`AGENTS.md` §12): уходит в
  /// `FlutterError`, без текста кода.
  void _copy() {
    unawaited(
      Clipboard.setData(ClipboardData(text: widget.code)).catchError((
        Object error,
        StackTrace stack,
      ) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'codelab_ui',
            context: ErrorDescription('while copying a code block'),
          ),
        );
      }),
    );
  }

  /// Подпись языка: управляющие и невидимые символы экранированы (D5, R4),
  /// длина не больше 32 символов — язык приходит из недоверенного текста.
  static String _displayLanguage(String language) {
    final escaped = escapeForDisplay(language.trim());
    final runes = escaped.runes.toList();
    if (runes.length <= 32) return escaped;
    return '${String.fromCharCodes(runes.take(31))}…';
  }

  /// Код как `TextSpan`: участки между токенами — обычным цветом, токены —
  /// цветом своего класса. Смещения вне кода (чужой кеш, сбой) отбрасываются.
  TextSpan _codeSpan(TextStyle? base, CodeLabCodeTheme palette) {
    final style = base?.copyWith(color: palette.plain);
    final tokens = _tokens;
    final code = widget.code;
    if (tokens == null || tokens.isEmpty) {
      return TextSpan(text: code, style: style);
    }
    final children = <TextSpan>[];
    var offset = 0;
    for (final token in tokens) {
      // Токены из чужого кеша или другого токенизатора не доверяются: вне
      // кода и внутри суррогатной пары они отбрасываются.
      if (token.start < offset ||
          token.end > code.length ||
          snapToCodePoint(code, token.start) != token.start ||
          snapToCodePoint(code, token.end) != token.end) {
        continue;
      }
      if (token.start > offset) {
        children.add(
          TextSpan(text: code.substring(offset, token.start), style: style),
        );
      }
      children.add(
        TextSpan(
          text: code.substring(token.start, token.end),
          style: style?.copyWith(color: palette.colorOf(token.tokenClass)),
        ),
      );
      offset = token.end;
    }
    if (offset < code.length) {
      children.add(TextSpan(text: code.substring(offset), style: style));
    }
    // Полный стиль на каждом листе: родительский `TextSpan` без текста
    // читатели дерева (тесты, доступность) могут не посетить.
    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.closed) {
      assert(CodeLabMarkdownStats.noteCodeBlockBuild(_statsKey));
    }
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final palette = CodeLabCodeTheme.of(theme);
    final language = _displayLanguage(widget.language);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: resources.cardStrokeColorDefault),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (language.isNotEmpty || widget.closed)
              // Подпись и «Copy» не входят в выделение ответа (D4, факт 7).
              SelectionContainer.disabled(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4, top: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: language.isEmpty
                            ? const SizedBox.shrink()
                            : CodeLabText(
                                language,
                                role: CodeLabTextRole.caption,
                                color: resources.textFillColorSecondary,
                              ),
                      ),
                      if (widget.closed)
                        CodeLabButton(
                          key: CodeLabCodeBlock.copyKey(_id, _index),
                          label: 'Copy',
                          icon: FluentIcons.copy,
                          emphasis: CodeLabButtonEmphasis.subtle,
                          onPressed: _copy,
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Text.rich(
                _codeSpan(
                  CodeLabText.styleOf(context, CodeLabTextRole.mono),
                  palette,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
