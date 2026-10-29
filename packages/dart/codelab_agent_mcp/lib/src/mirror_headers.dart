import 'dart:convert';

/// Свойство `inputSchema`, помеченное `x-mcp-header`: имя заголовка и путь
/// к значению в аргументах вызова.
final class MirroredParam {
  const MirroredParam(this.header, this.path);

  /// Часть имени `Mcp-Param-<header>`.
  final String header;

  /// Цепочка ключей `properties` от корня схемы.
  final List<String> path;
}

// Допустимые типы помеченных свойств (`streamable-http.md`, «Schema
// Extension»): `number` и непримитивы запрещены.
const _primitiveTypes = {'string', 'integer', 'boolean'};

final _tchar = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

/// Разбирает `x-mcp-header` в [inputSchema] по ограничениям
/// `basic/transports/streamable-http.md` («Custom Headers from Tool
/// Parameters», «Schema Extension»; design.md change
/// `add-agent-mcp-client`, D5 шаг 4, D10).
///
/// Почему отдельная функция: HTTP-клиент MUST исключить из `tools/list`
/// инструмент с нарушением (одно битое описание не мешает остальным), а для
/// валидного — зеркалить значения в заголовки; обе задачи читают схему
/// одним обходом.
///
/// Возвращает `null`, если описание нарушает ограничения: пустое имя, не
/// `1*tchar`, повтор без учёта регистра, тип не `string`/`integer`/`boolean`,
/// аннотация вне цепочки `properties` (в `items`, `oneOf`, `$ref`...) или на
/// корне. Схема без аннотаций (в том числе не-объект) даёт пустой список.
List<MirroredParam>? parseMirroredParams(Object? inputSchema) {
  final params = <MirroredParam>[];
  final seen = <String>{};
  var valid = true;

  // Аннотация вне цепочки `properties` делает описание недопустимым.
  // Ключ `x-mcp-header` с объектом внутри — свойство с таким именем, а не
  // аннотация.
  void scanUnreachable(Object? node) {
    if (node is Map) {
      for (final MapEntry(:key, :value) in node.entries) {
        if (key == 'x-mcp-header' && value is! Map) {
          valid = false;
        } else {
          scanUnreachable(value);
        }
      }
    } else if (node is List) {
      node.forEach(scanUnreachable);
    }
  }

  void walk(Object? node, List<String> path) {
    if (node is! Map) {
      return;
    }
    for (final MapEntry(:key, :value) in node.entries) {
      if (key == 'x-mcp-header') {
        if (path.isEmpty ||
            value is! String ||
            !_tchar.hasMatch(value) ||
            !seen.add(value.toLowerCase()) ||
            !_primitiveTypes.contains(node['type'])) {
          valid = false;
        } else {
          params.add(MirroredParam(value, path));
        }
      } else if (key == 'properties' && value is Map) {
        for (final MapEntry(key: name, value: sub) in value.entries) {
          walk(sub, [...path, '$name']);
        }
      } else {
        scanUnreachable(value);
      }
    }
  }

  walk(inputSchema, const []);
  return valid ? params : null;
}

/// Строковое значение для заголовка или `null`, если заголовка нет.
///
/// `string` как есть, `integer` десятичной записью, `boolean` — `true` /
/// `false`; отсутствие значения, `null` и значение другого типа заголовка не
/// дают (`streamable-http.md`, «Value Encoding»).
String? mirroredValue(Object? arguments, List<String> path) {
  Object? value = arguments;
  for (final key in path) {
    value = value is Map ? value[key] : null;
  }
  return switch (value) {
    final String s => s,
    final int i => '$i',
    final bool b => '$b',
    _ => null,
  };
}

final _safeAscii = RegExp(r'^[\x20-\x7E]*$');

/// Кодирует значение для `Mcp-Name` и `Mcp-Param-*`: вне видимого ASCII,
/// с пробелами по краям или похожее на маркер `=?base64?…?=` — Base64 от
/// UTF-8 в маркере (`streamable-http.md`, «Value Encoding»).
String encodeHeaderValue(String value) {
  final plain =
      _safeAscii.hasMatch(value) &&
      value == value.trim() &&
      !(value.startsWith('=?base64?') && value.endsWith('?='));
  return plain ? value : '=?base64?${base64.encode(utf8.encode(value))}?=';
}
