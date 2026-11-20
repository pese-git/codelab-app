/// Каталог пользовательских тем на `dart:io` (spec `client-themes`,
/// «Каталог пользовательских тем», «Импорт файла темы»).
///
/// Почему: ядро клиента web-безопасно и файлов не читает; общий формат
/// `<home>/themes/<name>.json` для app и CLI читает и пишет этот адаптер
/// (design.md change `add-app-appearance-page`, D2, D9).
///
/// Как использовать: composition root создаёт `IoThemeLibrary(home:)` с
/// `resolveCodelabHome`; хост зовёт [list] и [import]. Исключений
/// перечисления нет: сбой чтения — запись с ошибкой, сбой импорта —
/// `ThemeImportFailed`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:path/path.dart' as p;

import '../stores/json_file.dart';

/// Реализация [ThemeLibrary] на файлах `<home>/themes/*.json`.
///
/// Почему и как использовать — см. описание библиотеки; создаётся один раз в
/// composition root, состояния между вызовами не держит.
final class IoThemeLibrary implements ThemeLibrary {
  /// [home] — `$CODELAB_HOME`; темы лежат в `<home>/themes`.
  IoThemeLibrary({required this.home});

  final String home;

  String get _themesDir => p.join(home, 'themes');

  @override
  Future<List<ThemeEntry>> list() async {
    final dir = Directory(_themesDir);
    final List<FileSystemEntity> children;
    try {
      if (!await dir.exists()) return const [];
      children = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return const [];
    }
    final entries = <ThemeEntry>[];
    for (final child in children) {
      final base = p.basename(child.path);
      // Только `*.json` прямо в каталоге: подкаталоги не обходятся.
      if (!base.endsWith('.json') || base.length == '.json'.length) continue;
      final name = base.substring(0, base.length - '.json'.length);
      entries.add(await _entryAt(name, child.path));
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  @override
  Future<ThemeEntry?> read(String name) async {
    // Путь строится только из имени по шаблону: `..` и разделители не пройдут.
    if (!isValidThemeName(name)) return null;
    final path = p.join(_themesDir, '$name.json');
    // Отсутствие файла — `null`, а не ошибка; битая ссылка и каталог —
    // существующая запись, которую не удалось прочитать.
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    return _entryAt(name, path);
  }

  /// Запись каталога по пути файла: текст либо причина, по которой его нет.
  Future<ThemeEntry> _entryAt(String name, String path) async {
    final bytes = await _readBounded(path);
    if (bytes == null) {
      return ThemeEntry.failed(name, ThemeReadError.unreadable);
    }
    if (bytes.length > themeFileMaxBytes) {
      return ThemeEntry.failed(name, ThemeReadError.tooLarge);
    }
    try {
      return ThemeEntry.read(name, utf8.decode(bytes));
    } on FormatException {
      return ThemeEntry.failed(name, ThemeReadError.notUtf8);
    }
  }

  @override
  Future<ThemeImportResult> import(
    String sourcePath, {
    bool replace = false,
  }) async {
    final bytes = await _readBounded(sourcePath);
    if (bytes == null) return const ThemeImportFailed();
    // `null` вместо имени файла: источник может называться как угодно (D9).
    final parsed = ThemeFile.parseBytes(null, bytes);
    if (parsed is ThemeRejected) return ThemeImportInvalid(parsed.issue);
    // Путь назначения строится только из проверенного `name` (шаблон
    // `[a-z0-9-]{1,32}`): ни имя источника, ни разделители в него не попадут.
    final name = (parsed as ThemeLoaded).theme.name;
    final target = p.join(_themesDir, '$name.json');

    final existing = await _readBounded(target);
    if (existing != null && _sameBytes(existing, bytes)) {
      return ThemeImportUnchanged(name);
    }
    final exists = existing != null || await _entityExists(target);
    if (exists && !replace) return ThemeImportNeedsReplace(name);
    try {
      await writeBytesAtomically(target, bytes);
    } on FileSystemException {
      return const ThemeImportFailed();
    }
    return exists ? ThemeImportReplaced(name) : ThemeImportImported(name);
  }

  Future<bool> _entityExists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Читает не больше `themeFileMaxBytes + 1` байт; сбой открытия или чтения —
  /// `null`. Лишний байт отличает «ровно предел» от «больше предела», а файл
  /// без конца (`/dev/zero`) не читается целиком.
  Future<Uint8List?> _readBounded(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final builder = BytesBuilder(copy: false);
      const limit = themeFileMaxBytes + 1;
      while (builder.length < limit) {
        final chunk = await file.read(limit - builder.length);
        if (chunk.isEmpty) break;
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on FileSystemException {
      return null;
    } finally {
      await file?.close();
    }
  }
}
