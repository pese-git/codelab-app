// Чтение строк первого запуска и ключа флаговой формы (ревью 4a, п. 3;
// design.md change `add-provider-setup-ui`, D15, D16, D17).
//
// Опережающий ввод — `y⏎<ключ>⏎` одним куском — не должен ни рисовать ключ
// открытым текстом в старой строке, ни падать (`Future already completed`),
// ни переноситься в следующее поле.

import 'dart:convert';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_cli/src/setup/prompt_line.dart';
import 'package:test/test.dart';

import '../support/fake_terminal.dart';
import '../support/setup_fakes.dart';

void main() {
  late FakeTerminal terminal;
  late PromptReader reader;

  setUp(() {
    terminal = FakeTerminal();
    reader = PromptReader(terminal);
  });
  tearDown(() => reader.close());

  test('хвост куска после Enter отбрасывается, ключ не печатается и в '
      'следующее поле не попадает', () async {
    final first = reader.read('Store? [Y/n] ');
    terminal.press(utf8.encode('y\r${leakMarker}XX\r'));
    expect(await first, 'y');
    await pumpEventQueue();

    final hidden = reader.read('? API key › ', hidden: true);
    terminal.press(utf8.encode('real\r'));

    expect(await hidden, 'real');
    expect(terminal.text, isNot(contains(leakMarker)));
    expect(terminal.text, isNot(contains('real')));
  });

  test('Enter без вопроса и повторный Enter игнорируются', () async {
    final first = reader.read('Q? ');
    terminal.press(utf8.encode('a\r\r\r'));

    expect(await first, 'a');
    await pumpEventQueue();
    expect(terminal.rawEnabled, isTrue);
  });

  test('Ctrl+C даёт null', () async {
    final first = reader.read('Q? ', hidden: true);
    terminal.type('secret');
    terminal.press(keyCtrlC);

    expect(await first, isNull);
    expect(terminal.text, isNot(contains('secret')));
  });

  group('скрытое поле отклоняет не-один-ряд и слишком длинное (D14)', () {
    test('несколько строк одним куском: исключение без значения, поле '
        'спрашивается снова', () async {
      final first = reader.read('? API key › ', hidden: true);
      terminal.press(utf8.encode('${leakMarker}A\r${leakMarker}B\r'));

      await expectLater(first, throwsA(isA<KeyInputRejected>()));
      expect(terminal.text, isNot(contains(leakMarker)));

      final again = reader.read('? API key › ', hidden: true);
      terminal.press(utf8.encode('good\r'));
      expect(await again, 'good');
    });

    test('перевод строки внутри значения (LF) тоже отклоняется', () async {
      final first = reader.read('? API key › ', hidden: true);
      terminal.press(utf8.encode('abc\ndef\r'));

      await expectLater(first, throwsA(isA<KeyInputRejected>()));
    });

    test('значение длиннее предела отклоняется', () async {
      final first = reader.read('? API key › ', hidden: true);
      terminal.press(utf8.encode('${'a' * (maxKeyBytes + 1)}\r'));

      await expectLater(first, throwsA(isA<KeyInputRejected>()));
    });

    test('одна строка с Enter принимается', () async {
      final first = reader.read('? API key › ', hidden: true);
      terminal.press(utf8.encode('$leakMarker\r'));

      expect(await first, leakMarker);
    });
  });
}
