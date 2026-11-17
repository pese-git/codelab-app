// Дополнительные невидимые символы `escapeForDisplay` (ревью итерации 3 change
// `add-app-skills-page`): теги Unicode, невидимые операторы, мягкий перенос и
// заполнители Hangul не должны прятать часть недоверенного текста. Существующие
// тесты функции остаются стражем прежнего поведения.

import 'package:codelab_ui/src/rendering/escape_for_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String hex(int rune) => '\\u${rune.toRadixString(16).padLeft(4, '0')}';

  group('escapeForDisplay — расширенные невидимые символы', () {
    final cases = <String, List<int>>{
      'теги Unicode U+E0000–E007F': [0xE0000, 0xE0041, 0xE007F],
      'невидимые операторы U+2060–U+2064': [
        0x2060,
        0x2061,
        0x2062,
        0x2063,
        0x2064,
      ],
      'мягкий перенос U+00AD': [0x00AD],
      'монгольский разделитель U+180E': [0x180E],
      'комбинируемый соединитель U+034F': [0x034F],
      'заполнители Hangul U+115F, U+1160, U+3164': [0x115F, 0x1160, 0x3164],
    };
    cases.forEach((name, runes) {
      test(name, () {
        for (final rune in runes) {
          expect(
            escapeForDisplay('a${String.fromCharCode(rune)}b'),
            'a${hex(rune)}b',
            reason: rune.toRadixString(16),
          );
        }
      });
    });

    test('обычные символы и соседи диапазонов остаются', () {
      expect(escapeForDisplay('Привет 😀 a-b'), 'Привет 😀 a-b');
      for (final rune in [0x00AC, 0x205F, 0xE0080, 0x1161, 0x3165]) {
        final text = 'a${String.fromCharCode(rune)}b';
        expect(escapeForDisplay(text), text);
      }
    });
  });
}
