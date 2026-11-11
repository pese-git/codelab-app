import 'package:fluent_ui/fluent_ui.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../atomics/atomics.dart';
import 'codelab_markdown_config.dart';
import 'codelab_markdown_nesting.dart';
import 'codelab_markdown_row.dart';

/// Ответ агента как markdown в теме Fluent.
///
/// Почему: SMK-07 — лента показывала сырые `**`, обратные кавычки и ограды.
/// Разбор берёт пакет `gpt_markdown`, а не свой парсер (решение пользователя
/// 2026-11-11, D1); пакет живёт только в `rendering/` (D2).
///
/// Для чего: рисует текст [text] строки [id] без Material-предка. Закрытые
/// блоки пакет строит один раз за стрим, перестраивается только хвост
/// (DSK-3, D3); незакрытая ограда в хвосте — моноширинный текст без
/// подсветки (DSK-6). Ответ оборачивается в `SelectableRegion` (D8): текст
/// выделяется мышью в пределах ответа, подписи языка в выделение не входят.
///
/// Как использовать: `CodeLabMarkdown(id: row.id, text: row.text,
/// streaming: row.streaming)`. [config] передаёт панель ленты, чтобы
/// конфигурация жила в её `State`; без неё виджет создаёт свою по теме.
/// Политика ссылок и изображений приходит из `CodeLabMarkdownScope`.
class CodeLabMarkdown extends StatefulWidget {
  const CodeLabMarkdown({
    required this.id,
    required this.text,
    this.streaming = false,
    this.config,
    super.key,
  });

  /// Id строки ленты: из него строятся ключи `code-copy-<id>-<n>`.
  final String id;
  final String text;

  /// Ответ ещё стримится (последний элемент идущего хода).
  final bool streaming;
  final CodeLabMarkdownConfig? config;

  @override
  State<CodeLabMarkdown> createState() => _CodeLabMarkdownState();
}

class _CodeLabMarkdownState extends State<CodeLabMarkdown> {
  final _row = CodeLabMarkdownRowModel();
  // Ответ не должен быть остановкой Tab: фокус нужен области выделения
  // только для Cmd/Ctrl+C и мыши.
  final _focusNode = FocusNode(
    debugLabel: 'CodeLabMarkdown selection',
    skipTraversal: true,
  );
  CodeLabMarkdownConfig? _own;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  CodeLabMarkdownConfig _configFor(FluentThemeData theme) {
    final given = widget.config;
    if (given != null) return given;
    final own = _own;
    if (own != null && own.theme == theme) return own;
    return _own = CodeLabMarkdownConfig(theme);
  }

  @override
  Widget build(BuildContext context) {
    // Слишком глубокая вложенность разбор пакета не переживает (D14): ответ
    // показывается исходным текстом без markdown.
    if (markdownNestingDepth(widget.text) > kMaxMarkdownNestingDepth) {
      return _PlainFallback(text: widget.text);
    }
    final config = _configFor(FluentTheme.of(context));
    _row.update(id: widget.id, blocks: scanFencedBlocks(widget.text));
    // `SelectableRegion` из widgets, а не `SelectionArea`: `SelectionArea` и
    // его контекстное меню принадлежат Material, а кит работает без
    // Material-предка (D4, D10). Меню поэтому своё, на Fluent.
    return SelectableRegion(
      focusNode: _focusNode,
      selectionControls: _noHandles,
      contextMenuBuilder: _buildContextMenu,
      child: CodeLabMarkdownRowScope(
        model: _row,
        child: GptMarkdownTheme(
          gptThemeData: config.gptTheme,
          child: GptMarkdown(
            widget.text,
            style: config.style,
            isStreaming: widget.streaming,
            // D3, D7, D9: явные значения вместо умолчаний пакета.
            animation: GptMarkdownAnimation.none,
            useDollarSignsForLatex: false,
            html: false,
            codeBuilder: config.codeBuilder,
            headingBuilder: config.headingBuilder,
            checkboxBuilder: config.checkboxBuilder,
            imageBuilder: config.imageBuilder,
            inlineLinkBuilder: config.inlineLinkBuilder,
          ),
        ),
      ),
    );
  }
}

/// Управление выделением без ручек: мышь на desktop их не показывает.
///
/// Почему не `emptyTextSelectionControls`: `SelectableRegion` вызывает
/// `contextMenuBuilder` только для объектов с миксином
/// `TextSelectionHandleControls`;
/// остальные получили бы устаревший `buildToolbar`, то есть меню Material.
class _NoHandleSelectionControls extends TextSelectionControls
    with TextSelectionHandleControls {
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) => const SizedBox.shrink();

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      Offset.zero;

  @override
  Size getHandleSize(double textLineHeight) => Size.zero;
}

final _noHandles = _NoHandleSelectionControls();

/// Контекстное меню выделения: «Copy» и «Select all» на Fluent.
///
/// Почему: стандартное меню `SelectionArea` — Material (см. `build`).
/// `closeAfterClick: false`, потому что Fluent закрывал бы пункт через
/// `Navigator.pop`, а меню живёт в оверлее выделения, не в маршруте.
Widget _buildContextMenu(BuildContext context, SelectableRegionState state) {
  // Меню прижимается к границам оверлея: у правого и нижнего краёв окна оно
  // иначе выходило бы за экран.
  return CustomSingleChildLayout(
    delegate: _MenuLayout(state.contextMenuAnchors.primaryAnchor),
    // `MenuFlyout` требует `MenuInfoProvider` из дерева `Flyout`, а наше
    // меню живёт в оверлее выделения; поэтому тот же `FlyoutContent`, а
    // пункты — `MenuFlyoutItem.build`.
    child: FlyoutContent(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.copy),
              text: const Text('Copy'),
              closeAfterClick: false,
              onPressed: state.copyEnabled
                  ? () {
                      // Публичного способа скопировать выделение без
                      // меню платформы нет.
                      // ignore: deprecated_member_use
                      state.copySelection(SelectionChangedCause.toolbar);
                      state.hideToolbar();
                    }
                  : null,
            ).build(context),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.select_all),
              text: const Text('Select all'),
              closeAfterClick: false,
              onPressed: state.selectAllEnabled
                  ? () {
                      state.selectAll(SelectionChangedCause.toolbar);
                      state.hideToolbar();
                    }
                  : null,
            ).build(context),
          ],
        ),
      ),
    ),
  );
}

/// Раскладка меню: левый верхний угол в точке клика, но целиком в границах
/// оверлея.
class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout(this.anchor);

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    anchor.dx.clamp(0.0, (size.width - childSize.width).clamp(0.0, size.width)),
    anchor.dy.clamp(
      0.0,
      (size.height - childSize.height).clamp(0.0, size.height),
    ),
  );

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) => anchor != oldDelegate.anchor;
}

/// Запасной вид слишком глубоко вложенного ответа: текст как есть и пометка.
///
/// Почему и для чего: см. [kMaxMarkdownNestingDepth]; пользователь видит весь
/// ответ, а не пустую ленту или падение.
class _PlainFallback extends StatelessWidget {
  const _PlainFallback({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CodeLabMonospaceBlock(text),
      const SizedBox(height: 4),
      CodeLabText(
        'Shown as plain text: nesting is too deep.',
        role: CodeLabTextRole.caption,
        color: FluentTheme.of(context).resources.textFillColorSecondary,
      ),
    ],
  );
}
