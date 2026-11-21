import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/codelab_pressable.dart';
import '../atomics/codelab_text.dart';

/// Вкладка [CodeLabSelectorBar]: значение, подпись и ключ теста.
class CodeLabSelectorItem<T> {
  const CodeLabSelectorItem({
    required this.value,
    required this.label,
    this.key,
  });

  final T value;
  final String label;

  /// Ключ теста вкладки; задаёт вызывающий, кит своих ключей не вводит.
  final Key? key;
}

/// Полоса вкладок-переключателя разделов с подчёркиванием выбранной.
///
/// Почему: `CodeLabSegmentedControl` сжимает подписи с многоточием, а в теле
/// 400 px окна (минимум 800 px) «Политика конфиденциальности» обрезалась бы;
/// Fluent `TabView` — вкладки документов браузерного типа (закрытие,
/// перетаскивание), а не переключатель разделов (design.md change
/// `add-app-legal-page`, D6). Такие же вкладки нужны артбордам «Legal»
/// смартфона и планшета.
///
/// Для чего: чистый вид без логики. Что выбрано, решает вызывающий
/// ([value]); повторное нажатие на выбранную вкладку [onChanged] не вызывает.
/// Подписи не обрезаются: вкладки идут в ряд и, если не помещаются,
/// прокручиваются по горизонтали. Семантика: контейнер с [semanticLabel], у
/// каждой вкладки `button` и `selected`. Фокус и Enter/Space — через
/// `CodeLabPressable`. Цвета — из `FluentTheme`.
///
/// Как использовать: `CodeLabSelectorBar(items: …, value: tab,
/// onChanged: cubit.selectTab, semanticLabel: 'Legal documents')`. Ширина
/// родителя должна быть ограниченной, иначе прокручивать нечего.
class CodeLabSelectorBar<T> extends StatelessWidget {
  const CodeLabSelectorBar({
    required this.items,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final List<CodeLabSelectorItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: resources.dividerStrokeColorDefault),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                _SelectorTab<T>(
                  item: item,
                  selected: item.value == value,
                  onPressed: () {
                    if (item.value != value) {
                      onChanged(item.value);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectorTab<T> extends StatelessWidget {
  const _SelectorTab({
    required this.item,
    required this.selected,
    required this.onPressed,
  });

  final CodeLabSelectorItem<T> item;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    return Semantics(
      // Ключ — на узле семантики, чтобы тест видел состояние «выбрана».
      key: item.key,
      button: true,
      selected: selected,
      child: CodeLabPressable(
        // Выбранная вкладка тоже фокусируема: клавиатурный обход не должен
        // перескакивать через неё.
        onPressed: onPressed,
        builder: (context, hovered, focused) => DecoratedBox(
          decoration: BoxDecoration(
            color: hovered ? resources.subtleFillColorSecondary : null,
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected
                    ? theme.accentColor.defaultBrushFor(theme.brightness)
                    : (focused
                          ? resources.focusStrokeColorOuter
                          : const Color(0x00000000)),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: CodeLabText(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              color: selected
                  ? resources.textFillColorPrimary
                  : resources.textFillColorSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
