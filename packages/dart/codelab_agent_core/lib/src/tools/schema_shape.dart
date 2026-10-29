/// Форма ключевых слов схемы инструмента (`agent-core-architecture` §6.3.2;
/// design.md change `add-agent-mcp-client`, D7).
///
/// Почему отдельным файлом: правило формы одно на валидатор аргументов и на
/// регистрацию MCP-инструментов, но `validator.dart` во внутренний API не
/// входит (`public_api_test`), а эта проверка нужна другому пакету.
library;

/// Нарушения формы ключевых слов одного узла схемы, без рекурсии: тексты вида
/// `"required" must be a list of strings`. Не бросает.
List<String> schemaNodeProblems(Map<Object?, Object?> schema) {
  final problems = <String>[];
  void bad(String keyword, String expected) =>
      problems.add('"$keyword" must be $expected');
  if (schema.containsKey('type')) {
    final type = schema['type'];
    if (type is! String && !(type is List && type.every((t) => t is String))) {
      bad('type', 'a string or a list of strings');
    }
  }
  if (schema.containsKey('required')) {
    final names = schema['required'];
    if (names is! List || !names.every((n) => n is String)) {
      bad('required', 'a list of strings');
    }
  }
  if (schema.containsKey('properties') && schema['properties'] is! Map) {
    bad('properties', 'an object');
  }
  if (schema.containsKey('enum') && schema['enum'] is! List) {
    bad('enum', 'a list');
  }
  return problems;
}

/// Предельная глубина вложенности схемы в [schemaKeywordViolations]; корень —
/// глубина 0.
const maxSchemaDepth = 32;

/// Полная проверка формы ключевых слов `type`, `required`, `properties`,
/// `enum` по всему дереву схемы (`properties.*` и `items`-объекты); пустой
/// список — схема пригодна.
///
/// Почему: схему присылает недоверенный сервер (MCP, D7), и кривое слово лучше
/// отклонить при регистрации инструмента, чем получать ошибку валидации на
/// каждом вызове. Одно правило формы на ядро и MCP-пакет — вместо двух
/// списков, которые расходились бы. Булева схема свойства и `items`, не
/// являющийся объектом, допустимы (валидатор их игнорирует). Глубже
/// [maxSchemaDepth] — нарушение.
///
/// Как использовать: `McpTool.create` при пустом результате регистрирует
/// инструмент. Не бросает.
List<String> schemaKeywordViolations(
  Map<Object?, Object?> schema, [
  int depth = 0,
]) {
  if (depth > maxSchemaDepth) {
    return ['schema is nested deeper than $maxSchemaDepth levels'];
  }
  final out = schemaNodeProblems(schema);
  final properties = schema['properties'];
  if (properties is Map) {
    for (final property in properties.values) {
      if (property is Map) {
        out.addAll(schemaKeywordViolations(property, depth + 1));
      }
    }
  }
  if (schema['items'] case final Map<Object?, Object?> items) {
    out.addAll(schemaKeywordViolations(items, depth + 1));
  }
  return out;
}
