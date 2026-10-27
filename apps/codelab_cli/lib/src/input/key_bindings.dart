import 'key_decoder.dart';

/// Действие REPL, к которому привязывается клавиша.
///
/// [description] — текст `/help keys`; таблица — единственный источник
/// подписей (§12.2.11, TUI-7).
enum KeyAction {
  submit('send the prompt; while a turn runs, queue it'),
  newline('insert a new line'),
  cancelTurn('cancel the running turn'),
  clearLine('clear the input line'),
  interrupt('clear the input line; press again within 1s to exit'),
  exit('exit on an empty line'),
  historyPrevious('previous prompt from the history'),
  historyNext('next prompt from the history'),
  complete('complete a /command'),
  clearScreen('clear the screen'),
  moveLeft('move the cursor left'),
  moveRight('move the cursor right'),
  moveHome('move to the start of the line'),
  moveEnd('move to the end of the line'),
  deleteBackward('delete the character before the cursor'),
  deleteForward('delete the character under the cursor'),
  deleteToStart('delete to the start of the line');

  const KeyAction(this.description);

  final String description;
}

/// Область действия привязки: [running] — идёт ход, [editing] — хода нет,
/// [any] — всегда, если более узкой привязки нет.
enum KeyScope { any, editing, running }

final class KeyBinding {
  const KeyBinding(this.scope, this.key, this.action);

  final KeyScope scope;
  final Key key;
  final KeyAction action;
}

/// Одна клавиша одной области привязана к двум действиям.
final class KeyBindingConflict implements Exception {
  const KeyBindingConflict(this.scope, this.key, this.first, this.second);

  final KeyScope scope;
  final Key key;
  final KeyAction first;
  final KeyAction second;

  @override
  String toString() =>
      'KeyBindingConflict: ${key.label} in ${scope.name} is bound to both '
      '${first.name} and ${second.name}';
}

/// Таблица клавиш REPL.
///
/// Почему: обработка клавиш, подсказки и `/help keys` должны строиться из
/// одного места, иначе подсказка разойдётся с поведением; конфликт двух
/// действий на одной клавише ловится при построении (spec codelab-cli
/// «Редактор строки и клавиши»; §12.2.11, TUI-7; design.md change
/// `add-codelab-cli`, D5).
///
/// Как использовать: REPL берёт [mvp] и спрашивает [actionFor] на каждую
/// клавишу; `/help keys` печатает [helpLines]. Ctrl+Enter, Shift+Enter,
/// bracketed paste и секция `keys` из `cli.yaml` добавятся сюда после MVP.
final class KeyBindings {
  KeyBindings(List<KeyBinding> bindings)
    : bindings = List.unmodifiable(bindings) {
    for (final binding in bindings) {
      final slot = (binding.scope, binding.key);
      final existing = _table[slot];
      if (existing != null && existing != binding.action) {
        throw KeyBindingConflict(
          binding.scope,
          binding.key,
          existing,
          binding.action,
        );
      }
      _table[slot] = binding.action;
    }
  }

  /// Таблица MVP (§9.11 «Клавиши»).
  static final mvp = KeyBindings(const [
    KeyBinding(KeyScope.any, Key.enter, KeyAction.submit),
    KeyBinding(KeyScope.any, Key.altEnter, KeyAction.newline),
    KeyBinding(KeyScope.any, Key.ctrlJ, KeyAction.newline),
    KeyBinding(KeyScope.running, Key.escape, KeyAction.cancelTurn),
    KeyBinding(KeyScope.running, Key.ctrlC, KeyAction.cancelTurn),
    KeyBinding(KeyScope.editing, Key.escape, KeyAction.clearLine),
    KeyBinding(KeyScope.editing, Key.ctrlC, KeyAction.interrupt),
    KeyBinding(KeyScope.any, Key.ctrlD, KeyAction.exit),
    KeyBinding(KeyScope.any, Key.up, KeyAction.historyPrevious),
    KeyBinding(KeyScope.any, Key.down, KeyAction.historyNext),
    KeyBinding(KeyScope.any, Key.tab, KeyAction.complete),
    KeyBinding(KeyScope.any, Key.ctrlL, KeyAction.clearScreen),
    KeyBinding(KeyScope.any, Key.left, KeyAction.moveLeft),
    KeyBinding(KeyScope.any, Key.right, KeyAction.moveRight),
    KeyBinding(KeyScope.any, Key.home, KeyAction.moveHome),
    KeyBinding(KeyScope.any, Key.ctrlA, KeyAction.moveHome),
    KeyBinding(KeyScope.any, Key.end, KeyAction.moveEnd),
    KeyBinding(KeyScope.any, Key.ctrlE, KeyAction.moveEnd),
    KeyBinding(KeyScope.any, Key.backspace, KeyAction.deleteBackward),
    KeyBinding(KeyScope.any, Key.delete, KeyAction.deleteForward),
    KeyBinding(KeyScope.any, Key.ctrlU, KeyAction.deleteToStart),
  ]);

  final List<KeyBinding> bindings;
  final _table = <(KeyScope, Key), KeyAction>{};

  /// Действие клавиши [key]: привязка текущей области ([running] — идёт
  /// ход), иначе привязка [KeyScope.any]; `null` — клавиша ничего не делает.
  KeyAction? actionFor(Key key, {required bool running}) =>
      _table[(running ? KeyScope.running : KeyScope.editing, key)] ??
      _table[(KeyScope.any, key)];

  /// Строки `/help keys`: клавиша, когда действует, и что делает.
  List<String> helpLines() {
    final width = bindings
        .map((b) => b.key.label.length)
        .reduce((a, b) => a > b ? a : b);
    return [
      for (final binding in bindings)
        '${binding.key.label.padRight(width)}  '
            '${switch (binding.scope) {
              KeyScope.any => '',
              KeyScope.editing => '(no turn) ',
              KeyScope.running => '(during a turn) ',
            }}'
            '${binding.action.description}',
    ];
  }
}
