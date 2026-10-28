// Композер TUI (tasks 2.3 change `add-cli-tui`; spec codelab-tui «Композер
// TUI», «Вставка в TUI»; §12.2.11, TUI-3; design.md, D8).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  ComposerState typed(String text) => const ComposerState().insert(text);

  test('typing and moving the cursor', () {
    final composer = typed('helo').moveLeft().insert('l');

    expect(composer.text, 'hello');
    expect(composer.column, 4);
    expect(composer.moveHome().column, 0);
    expect(composer.moveHome().moveEnd().column, 5);
  });

  test('deleting', () {
    expect(typed('abc').deleteBackward().text, 'ab');
    expect(typed('abc').moveHome().deleteForward().text, 'bc');
    expect(typed('abc').moveLeft().deleteToStart().text, 'c');
    expect(typed('ab').clear().isEmpty, isTrue);
  });

  test('a new line and a two-dimensional cursor', () {
    final composer = typed('ab').newline().insert('cd');

    expect(composer.lines, ['ab', 'cd']);
    expect((composer.row, composer.column), (1, 2));
    final up = composer.up();
    expect((up.row, up.column), (0, 2));
    expect(
      composer.deleteBackward().deleteBackward().deleteBackward().text,
      'ab',
    );
  });

  test('submit returns the text, clears and records the history', () {
    final (next, text) = typed('hi').newline().insert('there').submit();

    expect(text, 'hi\nthere');
    expect(next.isEmpty, isTrue);
    expect(next.history, ['hi\nthere']);
  });

  test('an empty submit sends nothing', () {
    final (next, text) = const ComposerState().insert('  ').submit();

    expect(text, isNull);
    expect(next.history, isEmpty);
  });

  test('a backslash before Enter is a new line', () {
    final (next, text) = typed(r'one\').submit();

    expect(text, isNull);
    expect(next.lines, ['one', '']);
  });

  test('history goes back on the first line and forward on the last', () {
    var composer = const ComposerState(history: ['first', 'second']);

    composer = composer.up();
    expect(composer.text, 'second');
    composer = composer.up();
    expect(composer.text, 'first');
    composer = composer.down();
    expect(composer.text, 'second');
    composer = composer.down();
    expect(composer.text, '');
  });

  test('paste inserts the whole text at the cursor, normalized (TUI-3)', () {
    final composer = typed('[]').moveLeft().paste('a\r\nb\rc\x1b[2J\td');

    expect(composer.text, '[a\nb\nc[2J\td]');
    expect(composer.lines, hasLength(3));
  });
}
