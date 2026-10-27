// Вырезание управляющих символов из текста сессии (tasks 5.3, раньше — для
// строк headless в stderr; spec codelab-cli «Поверхности вывода»; TUI-11).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  test('ESC and the rest of C0 are removed, newline is kept', () {
    expect(
      sanitizeTerminalText('a\x1b[31mred\x1b[0m\x07b\nc\r'),
      'a[31mred[0mb\nc',
    );
  });

  test('DEL and C1 are removed', () {
    expect(sanitizeTerminalText('x\x7fy\u009bz\u0085w'), 'xyzw');
  });

  test('a tab expands to spaces', () {
    expect(sanitizeTerminalText('a\tb'), 'a    b');
  });

  test('printable text and non-ASCII letters stay', () {
    expect(sanitizeTerminalText('Читать «файл» ✓ 🙂'), 'Читать «файл» ✓ 🙂');
  });
}
