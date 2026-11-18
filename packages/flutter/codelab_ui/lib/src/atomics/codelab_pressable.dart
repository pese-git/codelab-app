import 'package:fluent_ui/fluent_ui.dart';

/// Нажимаемая область без кнопки Fluent: курсор-рука, наведение, фокус
/// клавиатуры, Enter и Space.
///
/// Почему: кнопка Fluent сбрасывает нажатие по таймеру в 100 мс, а строкам
/// таблицы и строке статуса нужна вся область клика с произвольной вёрсткой
/// внутри (design.md change `add-desktop-usage-pane`, D6; та же схема у
/// строк панели Agents). Для чего: единое поведение клика и клавиатуры без
/// логики — вызывающий решает, что значит нажатие.
///
/// Как использовать: [onPressed] `null` — область не реагирует, не берёт
/// фокус и не меняет курсор. [builder] получает признаки наведения и
/// фокуса. Не экспортируется барелем: внутренняя деталь кита.
class CodeLabPressable extends StatefulWidget {
  const CodeLabPressable({required this.builder, this.onPressed, super.key});

  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, bool hovered, bool focused)
  builder;

  @override
  State<CodeLabPressable> createState() => _CodeLabPressableState();
}

class _CodeLabPressableState extends State<CodeLabPressable> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed;
    return FocusableActionDetector(
      enabled: onPressed != null,
      mouseCursor: onPressed == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        // Вся область, включая промежутки между детьми, — часть цели клика.
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: widget.builder(context, _hovered, _focused),
      ),
    );
  }
}
