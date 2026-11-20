/// Читатель JSON с позициями ключей и значений (design.md change
/// `add-app-appearance-page`, D3).
///
/// Почему: `jsonDecode` не даёт позиций ключей и молча схлопывает повторы
/// ключей, а предупреждение темы требует `строка:колонка` и `duplicateKey`.
///
/// Для чего: `ThemeFile.parse` строит по дереву проблемы с позициями; значения
/// берутся из того же текста и совпадают с `jsonDecode` (проверяет тест).
///
/// Как использовать: [parseJsonSpans] на тексте до 64 КиБ. Грамматику
/// проверяет `jsonDecode` (его `FormatException.offset` переводится в позицию
/// через [positionAtOffset]), поэтому сканер идёт только по корректному JSON.
library;

import 'dart:convert';

/// Предел вложенности контейнеров (D3): глубже — [JsonDepthException].
const jsonSpansMaxDepth = 32;

/// Позиция в тексте: строка и колонка с 1, колонка — в code units UTF-16.
final class JsonPosition {
  const JsonPosition(this.line, this.column);

  final int line;
  final int column;
}

/// Узел дерева JSON с позицией начала.
sealed class JsonNode {
  const JsonNode(this.start);

  final JsonPosition start;

  /// Значение узла в виде `jsonDecode` (повтор ключа — последнее значение).
  Object? toValue();
}

/// Член объекта: ключ с позицией и значение. Повторы ключей сохраняются.
final class JsonMember {
  const JsonMember(this.key, this.keyStart, this.value);

  final String key;
  final JsonPosition keyStart;
  final JsonNode value;
}

final class JsonObjectNode extends JsonNode {
  const JsonObjectNode(super.start, this.members);

  /// Все члены в порядке следования в тексте, включая повторы ключей.
  final List<JsonMember> members;

  @override
  Object? toValue() => {for (final m in members) m.key: m.value.toValue()};
}

final class JsonArrayNode extends JsonNode {
  const JsonArrayNode(super.start, this.items);

  final List<JsonNode> items;

  @override
  Object? toValue() => [for (final i in items) i.toValue()];
}

/// Строка, число, `true`/`false` или `null`.
final class JsonScalarNode extends JsonNode {
  const JsonScalarNode(super.start, this.value);

  final Object? value;

  @override
  Object? toValue() => value;
}

/// Вложенность контейнеров больше [jsonSpansMaxDepth].
final class JsonDepthException implements Exception {
  const JsonDepthException(this.start);

  final JsonPosition start;
}

/// Строит дерево [JsonNode] с позициями.
///
/// Некорректный JSON — `FormatException` с `offset` (как у `jsonDecode`);
/// глубина больше [jsonSpansMaxDepth] — [JsonDepthException].
JsonNode parseJsonSpans(String text) {
  // Сначала грамматика: сканеру ниже достаточно разбирать корректный JSON.
  jsonDecode(text);
  return _Scanner(text).parse();
}

/// Переводит смещение в UTF-16 в строку и колонку (с 1).
///
/// Строка считается по `\n` (CRLF — один перевод), колонка — в code units.
JsonPosition positionAtOffset(String text, int offset) {
  var line = 1;
  var lineStart = 0;
  final end = offset < text.length ? offset : text.length;
  for (var i = 0; i < end; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      line++;
      lineStart = i + 1;
    }
  }
  return JsonPosition(line, offset - lineStart + 1);
}

final class _Scanner {
  _Scanner(this._text) {
    _lineStarts.add(0);
    for (var i = 0; i < _text.length; i++) {
      if (_text.codeUnitAt(i) == 0x0A) _lineStarts.add(i + 1);
    }
  }

  final String _text;
  final _lineStarts = <int>[];
  var _i = 0;

  JsonPosition _at(int offset) {
    // Двоичный поиск последней строки, начавшейся не позже offset.
    var lo = 0;
    var hi = _lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return JsonPosition(lo + 1, offset - _lineStarts[lo] + 1);
  }

  void _skipWs() {
    while (_i < _text.length) {
      final c = _text.codeUnitAt(_i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        _i++;
      } else {
        break;
      }
    }
  }

  JsonNode parse() {
    _skipWs();
    return _value(1);
  }

  JsonNode _value(int depth) {
    final start = _at(_i);
    final c = _text.codeUnitAt(_i);
    if (c == 0x7B) return _object(depth, start);
    if (c == 0x5B) return _array(depth, start);
    if (c == 0x22) return JsonScalarNode(start, _string());
    // Число, true, false, null: до разделителя.
    final from = _i;
    while (_i < _text.length) {
      final u = _text.codeUnitAt(_i);
      if (u == 0x2C ||
          u == 0x7D ||
          u == 0x5D ||
          u == 0x20 ||
          u == 0x09 ||
          u == 0x0A ||
          u == 0x0D) {
        break;
      }
      _i++;
    }
    return JsonScalarNode(start, jsonDecode(_text.substring(from, _i)));
  }

  /// Читает строковый литерал и возвращает его значение.
  String _string() {
    final from = _i;
    _i++; // открывающая кавычка
    while (_text.codeUnitAt(_i) != 0x22) {
      _i += _text.codeUnitAt(_i) == 0x5C ? 2 : 1;
    }
    _i++;
    return jsonDecode(_text.substring(from, _i)) as String;
  }

  JsonNode _object(int depth, JsonPosition start) {
    if (depth > jsonSpansMaxDepth) throw JsonDepthException(start);
    _i++;
    final members = <JsonMember>[];
    _skipWs();
    if (_text.codeUnitAt(_i) == 0x7D) {
      _i++;
      return JsonObjectNode(start, members);
    }
    while (true) {
      _skipWs();
      final keyStart = _at(_i);
      final key = _string();
      _skipWs();
      _i++; // двоеточие
      _skipWs();
      members.add(JsonMember(key, keyStart, _value(depth + 1)));
      _skipWs();
      if (_text.codeUnitAt(_i++) == 0x7D) break;
    }
    return JsonObjectNode(start, members);
  }

  JsonNode _array(int depth, JsonPosition start) {
    if (depth > jsonSpansMaxDepth) throw JsonDepthException(start);
    _i++;
    final items = <JsonNode>[];
    _skipWs();
    if (_text.codeUnitAt(_i) == 0x5D) {
      _i++;
      return JsonArrayNode(start, items);
    }
    while (true) {
      _skipWs();
      items.add(_value(depth + 1));
      _skipWs();
      if (_text.codeUnitAt(_i++) == 0x5D) break;
    }
    return JsonArrayNode(start, items);
  }
}
