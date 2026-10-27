// Редактор строки (tasks 6.3; spec codelab-cli «Редактор строки и клавиши»;
// design.md change `add-codelab-cli`, D5).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  late LineEditor editor;

  setUp(() => editor = LineEditor(History(const [])));

  test('insert and delete work on whole characters, not UTF-16 units', () {
    editor.insert('aй🙂');
    expect(editor.cursor, 3);

    editor.deleteBackward();
    expect(editor.text, 'aй');

    editor
      ..moveLeft()
      ..deleteForward();
    expect(editor.text, 'a');
    expect(editor.cursor, 1);
  });

  test('the cursor moves and text is inserted at it', () {
    editor
      ..insert('ac')
      ..moveLeft()
      ..insert('b');
    expect(editor.text, 'abc');
    expect(editor.cursor, 2);

    editor.moveHome();
    expect(editor.cursor, 0);
    editor.moveLeft();
    expect(editor.cursor, 0);
    editor.moveEnd();
    expect(editor.cursor, 3);
    editor.moveRight();
    expect(editor.cursor, 3);
  });

  test('deleteToStart removes the text before the cursor', () {
    editor
      ..insert('hello world')
      ..moveLeft()
      ..moveLeft()
      ..deleteToStart();

    expect(editor.text, 'ld');
    expect(editor.cursor, 0);
  });

  test('a new line goes into the buffer, Home and End stay on the '
      'line', () {
    editor
      ..insert('one')
      ..insertNewline()
      ..insert('two');
    expect(editor.text, 'one\ntwo');

    editor.moveHome();
    expect(editor.cursor, 4);
    editor
      ..moveLeft()
      ..moveHome();
    expect(editor.cursor, 0);
    editor.moveEnd();
    expect(editor.cursor, 3);
  });

  test('submit returns the text, clears the buffer and records '
      'history', () {
    editor.insert('first');

    expect(editor.submit(), 'first');
    expect(editor.text, isEmpty);
    expect(editor.history.entries, ['first']);
  });

  test('a backslash at the end turns Enter into a new line', () {
    editor.insert(r'one\');

    expect(editor.submit(), isNull);
    expect(editor.text, 'one\n');

    editor.insert('two');
    expect(editor.submit(), 'one\ntwo');
  });

  test('a blank submit returns an empty string and is not recorded', () {
    editor.insert('  ');

    expect(editor.submit(), '');
    expect(editor.history.entries, isEmpty);
  });

  test('history goes back and forward and keeps the draft', () {
    editor = LineEditor(History(['one', 'two']));
    editor.insert('dra');

    editor.historyPrevious();
    expect(editor.text, 'two');
    expect(editor.cursor, 3);
    editor.historyPrevious();
    expect(editor.text, 'one');
    editor.historyPrevious();
    expect(editor.text, 'one');

    editor.historyNext();
    expect(editor.text, 'two');
    editor.historyNext();
    expect(editor.text, 'dra');
  });

  test('clear empties the buffer', () {
    editor
      ..insert('abc')
      ..clear();

    expect(editor.text, isEmpty);
    expect(editor.isEmpty, isTrue);
  });
}
