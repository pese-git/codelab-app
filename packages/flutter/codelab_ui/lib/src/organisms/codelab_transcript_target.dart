import 'package:fluent_ui/fluent_ui.dart';

// Внутренний файл организмов (не экспортируется из `organisms.dart`): ключи и
// рамка подсветки цели показа в ленте (D49 Т7, spec agent-workbench-ui
// «Панель Agents v1», «Show in transcript»).

/// Ключ цели показа внутри строки ленты: вложенная строка `agent`, блок
/// одобрения потомка. Строка верхнего уровня адресуется своим `rowKey`.
ValueKey<String> transcriptTargetKey(String id) =>
    ValueKey('transcript-target-$id');

/// Ключ накладки подсветки: есть, пока цель подсвечена (около 1,5 с).
ValueKey<String> transcriptHighlightKey(String id) =>
    ValueKey('transcript-highlight-$id');

/// Рамка цели показа: ключ цели и короткая подсветка поверх содержимого.
///
/// Почему накладка в `Stack`, а не `DecoratedBox` вокруг [child]: рамка
/// остаётся в дереве всегда, и включение подсветки не пересоздаёт элемент
/// содержимого (иначе строка потеряла бы своё `State`, например «Show full
/// command»), а раскладка содержимого не меняется (`StackFit.passthrough`).
///
/// Как использовать: лента и строка вызова оборачивают в неё то, что может
/// быть целью; [keyed] выставляет `transcriptTargetKey(id)` (строка верхнего
/// уровня и так имеет свой `rowKey`), [highlighted] включает накладку.
class TranscriptTargetFrame extends StatelessWidget {
  const TranscriptTargetFrame({
    required this.id,
    required this.highlighted,
    required this.child,
    this.keyed = true,
    super.key,
  });

  final String id;
  final bool highlighted;
  final bool keyed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final stack = Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        child,
        if (highlighted)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: transcriptHighlightKey(id),
                decoration: BoxDecoration(
                  color: theme.accentColor.withAlpha(
                    theme.brightness == Brightness.dark ? 56 : 34,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
      ],
    );
    return keyed
        ? KeyedSubtree(key: transcriptTargetKey(id), child: stack)
        : stack;
  }
}
