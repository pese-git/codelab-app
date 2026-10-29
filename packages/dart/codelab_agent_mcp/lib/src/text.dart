/// Обрезает [text] до [limit] рун Unicode (не кодовых единиц UTF-16).
///
/// Почему: строки сервера (имена инструментов, методы, причины) попадают в
/// логи, и их длина ограничена (design.md change `add-agent-mcp-client`, D13).
/// Как использовать: `truncateRunes(value, 64)`; короткая строка возвращается
/// как есть.
String truncateRunes(String text, int limit) {
  final runes = text.runes;
  return runes.length > limit ? String.fromCharCodes(runes.take(limit)) : text;
}
