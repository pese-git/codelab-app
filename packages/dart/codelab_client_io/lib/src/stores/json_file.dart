import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

/// Записывает [value] в [path] через уникальный временный файл и
/// переименование, чтобы сбой посреди записи не оставил полфайла.
///
/// Почему: `profiles.json` общий у app и CLI (design.md change
/// `add-app-settings-shell`, D7); с общим `<file>.tmp` две одновременные
/// записи писали бы в один файл и переименование отдало бы смесь. Имя
/// содержит pid и случайный суффикс, поэтому каждый писатель работает со
/// своим файлом, а `rename` в том же каталоге атомарен: итог — запись
/// последнего писателя целиком. При сбое временный файл удаляется.
Future<void> writeJsonObject(String path, Map<String, Object?> value) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final suffix = _random.nextInt(1 << 32).toRadixString(36);
  final temporary = File('$path.$pid.$suffix.tmp');
  try {
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
    );
    await temporary.rename(path);
  } on Object {
    try {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    } on FileSystemException {
      // Очистка best-effort: исходная ошибка записи важнее.
    }
    rethrow;
  }
}

final _random = Random.secure();
