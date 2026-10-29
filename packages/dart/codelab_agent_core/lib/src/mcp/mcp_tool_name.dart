import 'dart:convert';

import 'package:crypto/crypto.dart';

final _unsafe = RegExp(r'[^A-Za-z0-9_-]');

/// Предел длины имени инструмента у провайдеров LLM и в `ToolRegistry`
/// (`^[a-zA-Z0-9_-]{1,64}$`, §6.2).
const _maxNameLength = 64;
const _headLength = 56;

/// Имя MCP-инструмента для модели: `mcp__<server>__<tool>` (§6.4, D7).
///
/// Почему функция в ядре: имя нужно и коннектору (регистрация, коллизии), и
/// исполнителю (правило префикса `mcp__`), и промпту (строка `prefix`), а
/// ядро не зависит от пакета MCP. Имя детерминировано между запусками —
/// иначе кэш промптов провайдера и разрешения «всегда» (§7.5) ломались бы.
///
/// Как использовать: передать `name` сервера и исходное имя инструмента.
/// Символы вне `[A-Za-z0-9_-]` заменяются на `_`. Имя длиннее 64 символов
/// сокращается до первых 56 символов, `_` и 7 hex-символов SHA-256 от
/// UTF-8 *несокращённого и незаменённого* имени — поэтому `a.b` и `a_b`,
/// совпавшие после замены, различаются хэшем. Коллизии коротких имён после
/// замены (`get issue` и `get_issue`) вызывающий разрешает сам (D6).
String mcpToolName(String server, String tool) {
  final raw = 'mcp__${server}__$tool';
  final sanitized = raw.replaceAll(_unsafe, '_');
  if (sanitized.length <= _maxNameLength) {
    return sanitized;
  }
  final hash = sha256.convert(utf8.encode(raw)).toString().substring(0, 7);
  return '${sanitized.substring(0, _headLength)}_$hash';
}

/// Префикс имён инструментов сервера для секции промпта `mcp` (§11.5, D12):
/// `mcp__<имя после замены символов>__`.
String mcpServerPrefix(String server) =>
    'mcp__${server.replaceAll(_unsafe, '_')}__';

/// Имя принадлежит MCP-инструменту (правило ограды §6.3.6, P-16).
bool isMcpToolName(String name) => name.startsWith('mcp__');
