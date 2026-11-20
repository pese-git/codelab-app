// Красный тест 1.1 change `add-app-appearance-page`: читатель JSON с
// позициями (design.md D3). Реализация — задача 1.2.
import 'dart:convert';

import 'package:codelab_client_core/src/themes/json_spans.dart';
import 'package:test/test.dart';

JsonObjectNode _object(String text) => parseJsonSpans(text) as JsonObjectNode;

JsonMember _member(JsonObjectNode node, String key, {int index = 0}) =>
    node.members.where((m) => m.key == key).elementAt(index);

void _expectAt(JsonPosition p, int line, int column, {String? reason}) {
  expect(
    [p.line, p.column],
    [line, column],
    reason: reason ?? 'позиция строка:колонка',
  );
}

void main() {
  group('D3: позиции ключей и значений', () {
    test('вложенные объекты: строка и колонка с 1 для ключа и значения', () {
      const text =
          '{\n'
          '  "name": "acme",\n'
          '  "colors": {\n'
          '    "accent": "#b4a0ff",\n'
          '    "code": {\n'
          '      "keyword": "#ff79c6"\n'
          '    }\n'
          '  }\n'
          '}';
      final root = _object(text);
      _expectAt(root.start, 1, 1);

      final name = _member(root, 'name');
      _expectAt(name.keyStart, 2, 3);
      _expectAt(name.value.start, 2, 11);

      final colors = _member(root, 'colors');
      _expectAt(colors.keyStart, 3, 3);
      _expectAt(colors.value.start, 3, 13);

      final colorsNode = colors.value as JsonObjectNode;
      final accent = _member(colorsNode, 'accent');
      _expectAt(accent.keyStart, 4, 5);
      _expectAt(accent.value.start, 4, 15);

      final code = _member(colorsNode, 'code');
      _expectAt(code.keyStart, 5, 5);
      final keyword = _member(code.value as JsonObjectNode, 'keyword');
      _expectAt(keyword.keyStart, 6, 7);
      _expectAt(keyword.value.start, 6, 18);
    });

    test('CRLF — один перевод строки', () {
      const text = '{\r\n  "a": 1,\r\n  "b": 2\r\n}';
      final root = _object(text);
      _expectAt(_member(root, 'a').keyStart, 2, 3);
      _expectAt(_member(root, 'b').keyStart, 3, 3);
    });

    test('массивы: позиции элементов', () {
      const text = '{"a": [1, "x",\n  true]}';
      final array = _member(_object(text), 'a').value as JsonArrayNode;
      expect(array.items, hasLength(3));
      _expectAt(array.start, 1, 7);
      _expectAt(array.items[0].start, 1, 8);
      _expectAt(array.items[1].start, 1, 11);
      _expectAt(array.items[2].start, 2, 3);
    });

    test('колонка считается в code units UTF-16: суррогатная пара — две', () {
      // `{"a😀": 1, "b": 2}`: «😀» занимает две единицы, "b" — колонка 12.
      const text = '{"a\u{1F600}": 1, "b": 2}';
      final root = _object(text);
      _expectAt(_member(root, 'b').keyStart, 1, 12);
      expect(root.members.first.key, 'a\u{1F600}');
    });

    test('escape-последовательности занимают исходные символы', () {
      // В тексте `\u00e9`, `\n` и `\ud83d\ude00` — по 6, 2 и 12 символов.
      const text = r'{"k\u00e9\n\ud83d\ude00": "v\"w", "z": 2}';
      final root = _object(text);
      expect(root.members.first.key, 'k\u00e9\n\u{1F600}');
      expect((root.members.first.value as JsonScalarNode).value, 'v"w');
      // `{` + `"k\u00e9\n\ud83d\ude00"` (23) + `: ` + `"v\"w"` (6) + `, `.
      _expectAt(_member(root, 'z').keyStart, 1, 35);
    });
  });

  group('D3: повтор ключа в одном объекте', () {
    test('все вхождения сохраняются в порядке текста', () {
      const text = '{\n  "accent": "#111111",\n  "accent": "#222222"\n}';
      final root = _object(text);
      final repeats = root.members.where((m) => m.key == 'accent').toList();
      expect(repeats, hasLength(2));
      _expectAt(repeats[0].keyStart, 2, 3);
      _expectAt(repeats[1].keyStart, 3, 3);
      expect((repeats[0].value as JsonScalarNode).value, '#111111');
      expect((repeats[1].value as JsonScalarNode).value, '#222222');
    });

    test('toValue при повторе даёт последнее значение, как jsonDecode', () {
      const text = '{"a": 1, "a": 2, "o": {"x": 1, "x": 3}}';
      expect(parseJsonSpans(text).toValue(), jsonDecode(text));
      expect(parseJsonSpans(text).toValue(), {
        'a': 2,
        'o': {'x': 3},
      });
    });
  });

  group('D3: глубина вложенности', () {
    String nested(int depth) => '${'[' * depth}${']' * depth}';

    test('глубина $jsonSpansMaxDepth допустима', () {
      expect(() => parseJsonSpans(nested(jsonSpansMaxDepth)), returnsNormally);
    });

    test('глубина больше $jsonSpansMaxDepth — JsonDepthException', () {
      expect(
        () => parseJsonSpans(nested(jsonSpansMaxDepth + 1)),
        throwsA(isA<JsonDepthException>()),
      );
    });

    test('глубина считается и по объектам', () {
      final text =
          '${'{"a":' * (jsonSpansMaxDepth + 1)}1${'}' * (jsonSpansMaxDepth + 1)}';
      expect(() => parseJsonSpans(text), throwsA(isA<JsonDepthException>()));
    });
  });

  group('positionAtOffset', () {
    test('смещение переводится в строку и колонку с 1', () {
      const text = 'ab\ncd\r\nef';
      _expectAt(positionAtOffset(text, 0), 1, 1);
      _expectAt(positionAtOffset(text, 2), 1, 3);
      _expectAt(positionAtOffset(text, 3), 2, 1);
      _expectAt(positionAtOffset(text, 7), 3, 1);
      _expectAt(positionAtOffset(text, text.length), 3, 3);
    });
  });

  group('D3, R: значения дерева совпадают с jsonDecode', () {
    final corpus = <String>[
      '{}',
      '[]',
      '{"name": "acme"}',
      '{"a": [1, 2.5, -3e2, true, false, null, "s"]}',
      '{"a": {"b": {"c": [{"d": "e"}]}}}',
      '{"esc": "tab\\t nl\\n quote\\" slash\\\\ \\/ \\u00e9"}',
      '{"pair": "\\ud83d\\ude00", "raw": "\u{1F600}"}',
      '{"dup": 1, "dup": {"x": 1}, "dup": [3]}',
      '  \n\t{ "ws" :\r\n [ 1 , 2 ] }  \n',
      '{"unicode-ключ": "значение", "":"empty-key"}',
      '"scalar"',
      '12',
      'null',
      '{"big": 12345678901234567890, "neg": -0.5, "exp": 1E+2}',
    ];

    for (final text in corpus) {
      test(jsonEncode(text.length > 40 ? text.substring(0, 40) : text), () {
        expect(parseJsonSpans(text).toValue(), jsonDecode(text));
      });
    }
  });

  group('некорректный JSON', () {
    test('FormatException со смещением, как у jsonDecode', () {
      const text = '{"name": "acme"';
      Object? expected;
      try {
        jsonDecode(text);
      } on FormatException catch (e) {
        expected = e.offset;
      }
      expect(
        () => parseJsonSpans(text),
        throwsA(
          isA<FormatException>().having((e) => e.offset, 'offset', expected),
        ),
      );
    });
  });
}
