// Тесты задачи 4.4 change `add-desktop-localization`: `messageSpans` не путает
// числа в тексте перевода с метками подставленных значений и держит порядок
// значений, который задаёт перевод.

import 'package:codelab_desktop/features/settings/presentation/message_spans.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

String _plain(List<InlineSpan> spans) =>
    spans.map((s) => (s as TextSpan).text).join('|');

void main() {
  const a = TextSpan(text: 'A');
  const b = TextSpan(text: 'B');

  test('числа в тексте сообщения остаются текстом', () {
    final spans = messageSpans(
      (m) => 'Ключи в ${m[0]} (режим 0600), ждать 30 с, потом ${m[1]} 1',
      [a, b],
    );

    expect(_plain(spans), 'Ключи в |A| (режим 0600), ждать 30 с, потом |B| 1');
  });

  test('порядок значений задаёт перевод: ru-порядок отличается от en', () {
    final en = messageSpans((m) => 'Saved to ${m[0]} as ${m[1]}', [a, b]);
    final ru = messageSpans((m) => 'Доступен как ${m[1]} в ${m[0]}', [a, b]);

    expect(_plain(en), 'Saved to |A| as |B');
    expect(_plain(ru), 'Доступен как |B| в |A');
  });

  test('значение, которого нет в переводе, пропадает без ошибки', () {
    expect(_plain(messageSpans((m) => 'Только ${m[0]}', [a, b])), 'Только |A');
  });

  test('значений больше десяти: метки не склеиваются', () {
    final values = [for (var i = 0; i < 12; i++) TextSpan(text: 'v$i')];
    final spans = messageSpans((m) => '${m[1]}${m[10]}${m[11]}', values);

    expect(_plain(spans), 'v1|v10|v11');
  });

  test('метка вне диапазона values — обычный текст, не RangeError', () {
    final spans = messageSpans((m) => '${m[0]} и \uE0009\uE001', [a]);

    expect(_plain(spans), 'A| и |9');
  });
}
