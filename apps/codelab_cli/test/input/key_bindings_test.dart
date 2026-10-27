// Таблица клавиш (tasks 6.3; spec codelab-cli «Редактор строки и клавиши»;
// §12.2.11, TUI-7; design.md change `add-codelab-cli`, D5).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  final keys = KeyBindings.mvp;

  KeyAction? editing(Key key) => keys.actionFor(key, running: false);
  KeyAction? running(Key key) => keys.actionFor(key, running: true);

  test('the MVP table', () {
    expect(editing(Key.enter), KeyAction.submit);
    expect(running(Key.enter), KeyAction.submit);
    for (final key in [Key.altEnter, Key.ctrlJ]) {
      expect(editing(key), KeyAction.newline, reason: '$key');
    }
    expect(running(Key.escape), KeyAction.cancelTurn);
    expect(running(Key.ctrlC), KeyAction.cancelTurn);
    expect(editing(Key.escape), KeyAction.clearLine);
    expect(editing(Key.ctrlC), KeyAction.interrupt);
    expect(editing(Key.ctrlD), KeyAction.exit);
    expect(editing(Key.up), KeyAction.historyPrevious);
    expect(editing(Key.down), KeyAction.historyNext);
    expect(editing(Key.tab), KeyAction.complete);
    expect(editing(Key.ctrlL), KeyAction.clearScreen);
    expect(running(Key.ctrlL), KeyAction.clearScreen);
    expect(editing(Key.left), KeyAction.moveLeft);
    expect(editing(Key.right), KeyAction.moveRight);
    expect(editing(Key.home), KeyAction.moveHome);
    expect(editing(Key.ctrlA), KeyAction.moveHome);
    expect(editing(Key.end), KeyAction.moveEnd);
    expect(editing(Key.ctrlE), KeyAction.moveEnd);
    expect(editing(Key.backspace), KeyAction.deleteBackward);
    expect(editing(Key.delete), KeyAction.deleteForward);
    expect(editing(Key.ctrlU), KeyAction.deleteToStart);
  });

  test('/help keys is built from the table', () {
    final help = keys.helpLines().join('\n');

    for (final binding in keys.bindings) {
      expect(help, contains(binding.key.label), reason: '${binding.key}');
      expect(
        help,
        contains(binding.action.description),
        reason: '${binding.action}',
      );
    }
  });

  test('one key bound to two actions in one scope is an error', () {
    expect(
      () => KeyBindings(const [
        KeyBinding(KeyScope.editing, Key.escape, KeyAction.clearLine),
        KeyBinding(KeyScope.editing, Key.escape, KeyAction.exit),
      ]),
      throwsA(isA<KeyBindingConflict>()),
    );
  });

  test('a scope-specific binding overrides the any-scope one', () {
    final table = KeyBindings(const [
      KeyBinding(KeyScope.any, Key.escape, KeyAction.clearLine),
      KeyBinding(KeyScope.running, Key.escape, KeyAction.cancelTurn),
    ]);

    expect(table.actionFor(Key.escape, running: false), KeyAction.clearLine);
    expect(table.actionFor(Key.escape, running: true), KeyAction.cancelTurn);
  });

  test('two keys for one action are fine', () {
    expect(
      () => KeyBindings(const [
        KeyBinding(KeyScope.any, Key.home, KeyAction.moveHome),
        KeyBinding(KeyScope.any, Key.ctrlA, KeyAction.moveHome),
      ]),
      returnsNormally,
    );
  });
}
