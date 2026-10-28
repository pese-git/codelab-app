/// Что делает выбор пункта пикера.
///
/// [run] — исполнить строку пункта командой (`/model m2`); [insert] —
/// подставить её в строку ввода (дополнение Tab).
enum PickerAction { run, insert }

/// Пункт пикера: [label] — строка списка, [line] — строка команды для него.
final class PickerItem {
  const PickerItem({required this.label, required this.line});

  final String label;
  final String line;

  @override
  bool operator ==(Object other) =>
      other is PickerItem && other.label == label && other.line == line;

  @override
  int get hashCode => Object.hash(label, line);

  @override
  String toString() => 'PickerItem($label, $line)';
}

/// Список вариантов, из которого команда без аргумента просит выбрать.
///
/// Почему: `/model`, `/mode`, `/sessions` без аргумента в REPL печатают
/// список, а в TUI открывают пикер; описание выбора — общее, а `repl/` не
/// должен зависеть от `tui/` (design.md change `add-cli-tui`, D10).
///
/// Для чего: [title] — заголовок списка (может не быть), [items] — пункты,
/// [current] — индекс текущего значения (на нём курсор пикера и `*` в
/// REPL), [action] — что делает выбор.
///
/// Как использовать: команда строит спецификацию и вызывает
/// `ReplContext.pick`; REPL печатает список, TUI открывает пикер и по Enter
/// исполняет `items[i].line` той же командой.
final class PickerSpec {
  const PickerSpec({
    this.title,
    required this.items,
    this.current,
    this.action = PickerAction.run,
  });

  final String? title;
  final List<PickerItem> items;
  final int? current;
  final PickerAction action;

  @override
  bool operator ==(Object other) =>
      other is PickerSpec &&
      other.title == title &&
      other.current == current &&
      other.action == action &&
      other.items.length == items.length &&
      [
        for (var i = 0; i < items.length; i++) other.items[i] == items[i],
      ].every((same) => same);

  @override
  int get hashCode =>
      Object.hash(title, current, action, Object.hashAll(items));

  @override
  String toString() => 'PickerSpec($title, $items, current: $current)';
}
