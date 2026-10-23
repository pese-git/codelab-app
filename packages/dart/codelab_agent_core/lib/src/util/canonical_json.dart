import 'dart:convert';

/// Canonical JSON (`agent-core-architecture` §6.3.7): object keys sorted by
/// UTF-16 code units on every level, no whitespace, strings and numbers as
/// `jsonEncode` writes them (`5` and `5.0` differ). Keys of the misuse
/// breaker and `permissionPattern` of MCP tools (§7.5).
String canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  final Map<Object?, Object?> map => {
    for (final key in (map.keys.map((k) => '$k').toList()..sort()))
      key: _sorted(map[key]),
  },
  final List<Object?> list => [for (final item in list) _sorted(item)],
  _ => value,
};
