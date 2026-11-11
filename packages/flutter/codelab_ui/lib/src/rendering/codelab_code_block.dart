import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../atomics/atomics.dart';
import 'codelab_markdown_row.dart';
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
/// копировать недописанный код нечего (DSK-6). Подсветки пока нет — она
/// приходит в итерации 3 (D4).
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
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    if (widget.closed) {
      assert(CodeLabMarkdownStats.noteCodeBlockBuild(_statsKey));
    }
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final language = widget.language.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: resources.cardBackgroundFillColorSecondary,
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
              child: Text(
                widget.code,
                style: CodeLabText.styleOf(
                  context,
                  CodeLabTextRole.mono,
                )?.copyWith(color: resources.textFillColorPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
