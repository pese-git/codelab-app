import 'dart:convert';
import 'dart:io';

/// Читает JSON-объект из [path]; нет файла — `null`.
///
/// Битый файл — `FormatException`: хранилище не подменяет испорченные данные
/// пустым списком молча, решение за вызывающим.
Future<Map<String, Object?>?> readJsonObject(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  return decoded;
}

/// Записывает [value] в [path] через временный файл и переименование, чтобы
/// сбой посреди записи не оставил полфайла.
Future<void> writeJsonObject(String path, Map<String, Object?> value) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final temporary = File('$path.tmp');
  await temporary.writeAsString(
    const JsonEncoder.withIndent('  ').convert(value),
  );
  await temporary.rename(path);
}
