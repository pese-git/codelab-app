// Неизменяемое поле ввода `LineField` и `applyFieldKey` (задача 4.8a change
// `add-provider-setup-ui`; design.md D15, D17; решение D14 о вставке
// нескольких строк и пределе длины).

import 'dart:convert';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/setup_fakes.dart' show leakMarker;

LineField type(LineField field, String text) =>
    applyFieldKey(field, TextKey(text)).$1;

LineField press(LineField field, Key key) =>
    applyFieldKey(field, SpecialKey(key)).$1;

void main() {
  const secret = LineField(hidden: true);

  test('маска: «*» по числу рун, значение не показано', () {
    final field = type(secret, leakMarker);

    expect(field.shown, '*' * leakMarker.length);
    expect(field.text, leakMarker);
    expect(field.toString(), isNot(contains(leakMarker)));
  });

  test('руны, а не байты', () {
    expect(type(secret, 'ключ🙂').shown, '*****');
  });

  test('Ctrl+R показывает и прячет, Ctrl+U очищает, показ остаётся', () {
    var field = type(secret, 'abc');
    field = press(field, Key.ctrlR);
    expect(field.shown, 'abc');

    field = press(field, Key.ctrlU);

    expect(field.text, isEmpty);
    expect(field.revealed, isTrue);
    expect(press(field, Key.ctrlR).revealed, isFalse);
  });

  test('Ctrl+R у обычного поля игнорируется', () {
    final (field, key) = applyFieldKey(
      const LineField(),
      const SpecialKey(Key.ctrlR),
    );

    expect(key, LineKey.ignored);
    expect(field.revealed, isFalse);
  });

  test('Backspace удаляет руну и считает байты', () {
    var field = type(secret, 'aй🙂');
    expect(field.bytes, 1 + 2 + 4);

    field = press(press(field, Key.backspace), Key.backspace);

    expect(field.text, 'a');
    expect(field.bytes, 1);
    expect(press(const LineField(), Key.backspace).text, isEmpty);
  });

  test('Enter, Ctrl+C, Esc и Ctrl+D дают submit и cancel', () {
    expect(
      applyFieldKey(secret, const SpecialKey(Key.enter)).$2,
      LineKey.submit,
    );
    for (final key in [Key.ctrlC, Key.escape, Key.ctrlD]) {
      expect(applyFieldKey(secret, SpecialKey(key)).$2, LineKey.cancel);
    }
  });

  group('отказ значения скрытого поля (D14)', () {
    test('вставка с переводом строки', () {
      for (final text in ['a\nb', 'a\rb']) {
        final (field, key) = applyFieldKey(secret, TextKey(text));

        expect(key, LineKey.multiline, reason: text);
        expect(field.rejected, isTrue);
      }
    });

    test('Ctrl+J, Alt+Enter и Shift+Enter внутри ключа', () {
      for (final key in [Key.ctrlJ, Key.altEnter, Key.shiftEnter]) {
        expect(applyFieldKey(secret, SpecialKey(key)).$2, LineKey.multiline);
      }
    });

    test('значение длиннее maxKeyBytes', () {
      final (field, key) = applyFieldKey(
        secret,
        TextKey('a' * (maxKeyBytes + 1)),
      );

      expect(key, LineKey.multiline);
      expect(field.rejected, isTrue);
      expect(utf8.encode(field.text).length, lessThanOrEqualTo(maxKeyBytes));
    });

    test('cleared() снимает отказ', () {
      expect(type(secret, 'a\nb').cleared().rejected, isFalse);
    });

    test('у обычного поля перевод строки не отказ: символ вырезан', () {
      final (field, key) = applyFieldKey(
        const LineField(),
        const TextKey('a\nb'),
      );

      expect(key, LineKey.edited);
      expect(field.text, 'ab');
    });
  });

  test('управляющие символы вырезаны, в том числе ESC и C1', () {
    final field = type(const LineField(), 'a\x1b]52;c;AA\x07b\x7f\x85c');

    expect(field.text, 'a]52;c;AAbc');
  });

  test('LineField.initial вырезает управляющие и считает байты', () {
    final field = LineField.initial('https://\x1b[2Jx.test/é');

    expect(field.text, 'https://[2Jx.test/é');
    expect(field.bytes, utf8.encode(field.text).length);
  });

  test('поле неизменяемо: исходное не меняется', () {
    final first = type(secret, 'abc');
    final second = type(first, 'def');

    expect(first.text, 'abc');
    expect(second.text, 'abcdef');
  });
}
