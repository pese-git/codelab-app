// Строка кадра TUI: ширина графем и сброс атрибутов (tasks 2.1 change
// `add-cli-tui`; spec codelab-tui «Кадр TUI»; §12.2.11, TUI-9; design.md,
// D5, D14 пункт 8).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

const _reset = '\x1b[0m';

void main() {
  test('display width counts double-width and zero-width characters', () {
    expect(displayWidth('abc'), 3);
    expect(displayWidth('中文'), 4);
    expect(displayWidth('😀'), 2);
    expect(displayWidth('é'), 1);
    expect(displayWidth('👨‍👩‍👧'), 2);
    expect(displayWidth('\x1b[2mdim\x1b[0m'), 3);
  });

  test('fitLine keeps a short line and ends it with a reset', () {
    expect(fitLine('hello', 10), 'hello$_reset');
    expect(fitLine('\x1b[2mhi', 10), '\x1b[2mhi$_reset');
  });

  test('fitLine cuts an ASCII line to the width', () {
    final line = fitLine('a' * 30, 10);

    expect(displayWidth(line), 10);
    expect(line, endsWith(_reset));
  });

  test('fitLine keeps one spare column when the line has wide or '
      'zero-width characters', () {
    for (final text in ['中' * 20, '😀' * 20, 'é' * 20]) {
      expect(
        displayWidth(fitLine(text, 10)),
        lessThanOrEqualTo(9),
        reason: text,
      );
    }
  });

  test('fitLine never splits a double-width character', () {
    final line = fitLine('a${'中' * 10}', 6);

    expect(line.replaceAll(_reset, ''), 'a中中');
  });

  test('without color fitLine adds no reset', () {
    expect(fitLine('hello', 10, color: false), 'hello');
  });

  test('wrapLine breaks at spaces and hard-breaks long words', () {
    expect(wrapLine('one two three', 8), ['one two', 'three']);
    expect(wrapLine('abcdefghij', 4), ['abcd', 'efgh', 'ij']);
    expect(wrapLine('中文中文中文', 5), ['中文', '中文', '中文']);
    expect(wrapLine('', 5), ['']);
  });
}
