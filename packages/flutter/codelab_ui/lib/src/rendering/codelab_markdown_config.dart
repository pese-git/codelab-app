import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'codelab_code_block.dart';
import 'codelab_code_highlighter.dart';
import 'codelab_markdown_row.dart';
import 'codelab_markdown_scope.dart';
import 'codelab_markdown_stats.dart';
import 'codelab_markdown_media.dart';

/// Тема и builder'ы отрисовки markdown, созданные один раз на тему Fluent.
///
/// Почему: пакет `gpt_markdown` кеширует виджеты закрытых сегментов, только
/// если тема, стиль и builder'ы — те же объекты между сборками (сравнение по
/// identity). Новая конфигурация на каждой сборке замедляет разбор в 3–4 раза
/// и перестраивает все закрытые блоки (прототип, факт 2; DSK-3, D3).
///
/// Для чего: собирает `GptMarkdownThemeData` из ролей `FluentTheme` (без
/// `Theme.of` Material и литералов цветов, DSK-19) и держит builder'ы
/// полями: блок кода, заголовки, флажки задач, изображения, ссылки (D4–D7).
/// HTML выключен (`html: false`, D7), формулы только `\(…\)`, `\[…\]` (D9).
///
/// Как использовать: панель ленты хранит одну конфигурацию в `State` и
/// пересоздаёт её при смене `FluentThemeData`; `CodeLabMarkdown` без
/// переданной конфигурации делает то же сам. Политику ссылок и изображений
/// builder'ы читают из `CodeLabMarkdownScope` через `context` — её смена
/// конфигурацию не пересоздаёт (D2).
class CodeLabMarkdownConfig {
  CodeLabMarkdownConfig(this.theme, {CodeLabCodeHighlighter? highlighter})
    : style = (theme.typography.body ?? const TextStyle()).copyWith(
        color: theme.resources.textFillColorPrimary,
      ),
      gptTheme = _gptThemeOf(theme),
      highlighter = highlighter ?? CodeLabCodeHighlighter.shared,
      codeBuilder = _codeBuilderOf(
        highlighter ?? CodeLabCodeHighlighter.shared,
      ),
      headingBuilder = _buildHeading,
      checkboxBuilder = _buildCheckbox,
      imageBuilder = _buildImage,
      inlineLinkBuilder = _buildLink;

  /// Тема Fluent, для которой собрана конфигурация.
  final FluentThemeData theme;

  /// Базовый стиль текста ответа.
  final TextStyle style;

  /// Подсветка блоков кода; по умолчанию общий экземпляр с одним LRU на
  /// ленту (D4).
  final CodeLabCodeHighlighter highlighter;

  /// Тема пакета из ролей Fluent.
  final GptMarkdownThemeData gptTheme;

  final CodeBlockBuilder codeBuilder;
  final HeadingBuilder headingBuilder;
  final CheckboxBuilder checkboxBuilder;
  final ImageBuilder imageBuilder;
  final InlineLinkBuilder inlineLinkBuilder;

  static GptMarkdownThemeData _gptThemeOf(FluentThemeData t) {
    final r = t.resources;
    final ty = t.typography;
    final text = r.textFillColorPrimary;
    TextStyle heading(TextStyle? s) =>
        (s ?? const TextStyle()).copyWith(color: text);
    final accent = t.accentColor.defaultBrushFor(t.brightness);
    return GptMarkdownThemeData(
      brightness: t.brightness,
      h1: heading(ty.title),
      h2: heading(ty.subtitle),
      h3: heading(ty.bodyLarge),
      h4: heading(ty.bodyStrong),
      h5: heading(ty.bodyStrong),
      h6: heading(ty.body),
      linkColor: accent,
      linkHoverColor: accent,
      hrLineColor: r.dividerStrokeColorDefault,
      highlightColor: r.cardBackgroundFillColorSecondary,
      autoAddDividerLineAfterH1: false,
      inlineCode: InlineCodeStyle(
        color: text,
        backgroundColor: r.cardBackgroundFillColorSecondary,
      ),
      styleSheet: GptMarkdownStyleSheet(
        link: LinkStyle(color: accent),
        blockQuote: BlockQuoteStyle(barColor: r.controlStrokeColorDefault),
        table: TableStyle(
          borderColor: r.dividerStrokeColorDefault,
          headerBackground: r.cardBackgroundFillColorSecondary,
        ),
      ),
    );
  }

  /// Блок кода: подпись, «Copy», подсвеченный код (D4). Builder создаётся
  /// один раз на конфигурацию и замыкает её подсветку (D3).
  static CodeBlockBuilder _codeBuilderOf(CodeLabCodeHighlighter highlighter) =>
      (context, name, code, closed) {
        final row = CodeLabMarkdownRowScope.of(context);
        return CodeLabCodeBlock(
          row: row,
          language: name,
          code: code,
          closed: closed,
          highlighter: highlighter,
        );
      };

  /// Заголовок: содержимое пакета как есть. Builder нужен ради счётчика
  /// `headingBuilds` (D13: «заголовок строится один раз»), а не ради линии h1 —
  /// линию отключает `autoAddDividerLineAfterH1: false` в теме.
  static Widget _buildHeading(
    BuildContext context,
    int level,
    Widget content,
    HeadingStyle style,
  ) {
    assert(CodeLabMarkdownStats.noteHeadingBuild(_plainTextOf(content)));
    return content;
  }

  /// Флажок списка задач — Fluent `Checkbox` только для чтения. Встроенный
  /// флажок пакета без Material-предка падает (issue #154, D4).
  static Widget _buildCheckbox(
    BuildContext context,
    bool checked,
    Widget content,
    CheckboxStyle style,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IgnorePointer(
        child: Checkbox(
          checked: checked,
          onChanged: null,
          semanticLabel: checked ? 'Task done' : 'Task open',
        ),
      ),
      const SizedBox(width: 8),
      Flexible(child: content),
    ],
  );

  /// Изображение: заглушка, а загрузка — только по клику «Show image» и по
  /// политике app. Без этого builder'а пакет сам грузит PNG и SVG по сети, а
  /// `<img>` из HTML идёт туда же (D6, факт 3).
  static Widget _buildImage(
    BuildContext context,
    String imageUrl,
    double? width,
    double? height,
  ) => CodeLabImagePlaceholder(url: imageUrl);

  /// Ссылка (D5): активна, только если app (через `CodeLabMarkdownScope`)
  /// разрешил адрес; иначе — обычный текст без recognizer, курсора, акцента и
  /// подчёркивания, чтобы неактивная ссылка не выглядела кликабельной. Адрес
  /// берётся из `details.url`, а не из текста ссылки (`onLinkTap` пакета даёт
  /// только текст — прототип, факт 4).
  ///
  /// Политика читается без подписки (`getInheritedWidgetOfExactType`): смена
  /// scope не должна перестраивать закрытые сегменты пакета (DSK-3, D3).
  static InlineSpan _buildLink(LinkBuildDetails details) {
    final base = details.config.style ?? const TextStyle();
    final uri = Uri.tryParse(details.url);
    final scope = details.context
        .getInheritedWidgetOfExactType<CodeLabMarkdownScope>();
    if (uri == null || scope == null || !scope.canOpenLink(uri)) {
      return TextSpan(
        style: base,
        children: [
          for (final span in details.labelSpans)
            _restyle(span, color: base.color, decoration: TextDecoration.none),
        ],
      );
    }
    final accent = details.linkStyle.color ?? base.color;
    final row = CodeLabMarkdownRowScope.of(details.context);
    final recognizer = row.recognizerFor(
      details.url,
      () => scope.onOpenLink(uri),
    );
    // Обычные `TextSpan` с recognizer, а не `WidgetSpan`: подпись переносится по
    // строкам вместе с абзацем и выделяется. Подсказка — оверлей хоста.
    return TextSpan(
      style: base.copyWith(
        color: accent,
        decoration: TextDecoration.underline,
        decorationColor: accent,
      ),
      children: [
        for (final span in details.labelSpans)
          _restyle(
            span,
            color: accent,
            decoration: TextDecoration.underline,
            link: (
              recognizer: recognizer,
              onEnter: (event) => row.showTooltip(details.url, event.position),
              onExit: (_) => row.hideTooltip(),
            ),
          ),
      ],
    );
  }

  /// Копия [span] с цветом и оформлением ссылки вместо стиля пакета; виджеты
  /// внутри ссылки, например изображение, остаются.
  static InlineSpan _restyle(
    InlineSpan span, {
    required Color? color,
    required TextDecoration decoration,
    _LinkHandlers? link,
  }) {
    if (span is! TextSpan) return span;
    final hasText = (span.text ?? '').isNotEmpty;
    return TextSpan(
      text: span.text,
      // Распознаватель и курсор у каждого листа с текстом: на `children`
      // родительский `recognizer` не распространяется.
      recognizer: hasText ? link?.recognizer : null,
      mouseCursor: hasText && link != null ? SystemMouseCursors.click : null,
      onEnter: hasText ? link?.onEnter : null,
      onExit: hasText ? link?.onExit : null,
      children: span.children
          ?.map(
            (c) =>
                _restyle(c, color: color, decoration: decoration, link: link),
          )
          .toList(),
      style: span.style?.copyWith(
        color: color,
        decoration: decoration,
        decorationColor: color,
      ),
    );
  }
}

/// Обработчики листа активной ссылки: клик и подсказка по наведению.
typedef _LinkHandlers = ({
  TapGestureRecognizer recognizer,
  void Function(PointerEnterEvent) onEnter,
  void Function(PointerExitEvent) onExit,
});

/// Видимый текст заголовка из виджета, который отдаёт пакет.
String _plainTextOf(Widget content) => switch (content) {
  Text(:final data?) => data,
  Text(:final textSpan?) => textSpan.toPlainText(),
  RichText(:final text) => text.toPlainText(),
  _ => '',
};
