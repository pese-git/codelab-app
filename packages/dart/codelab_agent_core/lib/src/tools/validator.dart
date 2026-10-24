import 'dart:convert';

import '../util/result.dart';

/// Validation and coercion of tool arguments (`agent-core-architecture`
/// §6.3.2). The supported subset is `type` (a string or a list, `"null"`
/// included), `properties`, `required`, `items`, `enum` and `default`;
/// other keywords stay in the schema for the model and are ignored, extra
/// arguments pass as is. A mismatched type is coerced by the table of
/// §6.3.2 when the meaning is unambiguous (`"42"` → 42).
///
/// Returns the coerced arguments or every violation as `<path>: <text>`.
Result<Map<String, Object?>, List<String>> validateArguments(
  Map<String, Object?> schema,
  Map<String, Object?> args,
) {
  final violations = <String>[];
  final value = _validateObject(schema, args, '', violations);
  return violations.isEmpty ? Ok(value) : Err(violations);
}

/// The error text for the model.
String formatInvalidArguments(
  String tool,
  List<String> violations,
  Map<String, Object?> received,
) => [
  'Invalid arguments for tool "$tool":',
  for (final v in violations) '  - $v',
  'Received arguments: ${jsonEncode(received)}',
].join('\n');

const _missing = Object();

Map<String, Object?> _validateObject(
  Map<String, Object?> schema,
  Map<String, Object?> value,
  String path,
  List<String> violations,
) {
  final properties = schema['properties'] is Map<String, Object?>
      ? schema['properties']! as Map<String, Object?>
      : const <String, Object?>{};
  final required = {
    for (final name in schema['required'] as List<Object?>? ?? const [])
      '$name',
  };
  final out = <String, Object?>{...value};
  for (final MapEntry(key: name, value: raw) in properties.entries) {
    if (raw is! Map<String, Object?>) {
      continue;
    }
    final propertyPath = path.isEmpty ? name : '$path.$name';
    final present = value.containsKey(name);
    final current = present ? value[name] : _missing;
    if (current == null && _types(raw).contains('null')) {
      continue;
    }
    if (current == _missing || current == null) {
      if (raw.containsKey('default')) {
        out[name] = raw['default'];
      } else if (required.contains(name)) {
        out.remove(name);
        violations.add('$propertyPath: missing required property');
      } else {
        out.remove(name);
      }
      continue;
    }
    out[name] = _validate(raw, current, propertyPath, violations);
  }
  return out;
}

List<String> _types(Map<String, Object?> schema) => switch (schema['type']) {
  final String type => [type],
  final List<Object?> types => [for (final t in types) '$t'],
  _ => const [],
};

Object? _validate(
  Map<String, Object?> schema,
  Object? value,
  String path,
  List<String> violations,
) {
  final types = _types(schema);
  var result = value;
  if (types.isNotEmpty && !types.any((t) => _matches(t, value))) {
    Object? coerced = _missing;
    for (final type in types) {
      coerced = _coerce(type, value);
      if (coerced != _missing) {
        break;
      }
    }
    if (coerced == _missing) {
      violations.add(
        '$path: expected ${types.join(' or ')}, got ${_describe(value)}',
      );
      return value;
    }
    result = coerced;
  }
  if (result is Map<String, Object?> && _hasType(types, 'object')) {
    result = _validateObject(schema, result, path, violations);
  } else if (result is List<Object?> &&
      schema['items'] is Map<String, Object?>) {
    final items = schema['items']! as Map<String, Object?>;
    result = [
      for (final (i, item) in result.indexed)
        _validate(items, item, '$path[$i]', violations),
    ];
  }
  if (schema['enum'] case final List<Object?> allowed
      when !allowed.contains(result)) {
    violations.add(
      '$path: must be one of ${jsonEncode(allowed)}, got ${jsonEncode(result)}',
    );
  }
  return result;
}

bool _hasType(List<String> types, String type) =>
    types.isEmpty || types.contains(type);

bool _matches(String type, Object? value) => switch (type) {
  'integer' => value is int,
  'number' => value is num,
  'string' => value is String,
  'boolean' => value is bool,
  'array' => value is List,
  'object' => value is Map,
  'null' => value == null,
  _ => true,
};

Object? _coerce(String type, Object? value) {
  switch (type) {
    case 'integer':
      if (value is String) {
        return int.tryParse(value.trim()) ?? _missing;
      }
      if (value is double && value == value.truncateToDouble()) {
        return value.toInt();
      }
    case 'number':
      if (value is String) {
        return double.tryParse(value.trim()) ?? _missing;
      }
    case 'boolean':
      if (value is String) {
        return switch (value.toLowerCase()) {
          'true' => true,
          'false' => false,
          _ => _missing,
        };
      }
      if (value == 1) {
        return true;
      }
      if (value == 0) {
        return false;
      }
    case 'string':
      if (value is num || value is bool) {
        return '$value';
      }
    case 'array':
      if (value is String) {
        final parsed = _tryJson(value);
        if (parsed is List) {
          return parsed;
        }
      }
      if (value is! List) {
        return [value];
      }
    case 'object':
      if (value is String) {
        final parsed = _tryJson(value);
        if (parsed is Map<String, Object?>) {
          return parsed;
        }
      }
  }
  return _missing;
}

Object? _tryJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

String _describe(Object? value) => switch (value) {
  null => 'null',
  String() => 'string ${jsonEncode(value)}',
  int() => 'integer $value',
  double() => 'number $value',
  bool() => 'boolean $value',
  List() => 'array ${jsonEncode(value)}',
  Map() => 'object ${jsonEncode(value)}',
  _ => '$value',
};
