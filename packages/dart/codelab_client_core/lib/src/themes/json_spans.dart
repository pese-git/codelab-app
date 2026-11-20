/// Читатель JSON с позициями ключей и значений (design.md change
/// `add-app-appearance-page`, D3).
///
/// ЗАГЛУШКА красного теста 1.1: поведение появится в задаче 1.2.
library;

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
  Object? toValue() => throw UnimplementedError('json_spans: задача 1.2');
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
}

final class JsonArrayNode extends JsonNode {
  const JsonArrayNode(super.start, this.items);

  final List<JsonNode> items;
}

/// Строка, число, `true`/`false` или `null`.
final class JsonScalarNode extends JsonNode {
  const JsonScalarNode(super.start, this.value);

  final Object? value;
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
JsonNode parseJsonSpans(String text) =>
    throw UnimplementedError('json_spans: задача 1.2');

/// Переводит смещение в UTF-16 в строку и колонку (с 1).
JsonPosition positionAtOffset(String text, int offset) =>
    throw UnimplementedError('json_spans: задача 1.2');
