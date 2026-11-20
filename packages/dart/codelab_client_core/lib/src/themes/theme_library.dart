/// Порт каталога пользовательских тем `<home>/themes` (spec `client-themes`,
/// «Каталог пользовательских тем», «Импорт файла темы»).
///
/// Почему: каталог тем читает `dart:io`-адаптер, а ядро клиента и виджеты
/// файловой системы не касаются; порт даёт хостам и тестам один контракт.
///
/// Как использовать: хост получает [ThemeLibrary] из composition root
/// (`IoThemeLibrary` в `codelab_client_io`), в тестах — [InMemoryThemeLibrary].
library;

import 'theme_file.dart';
import 'theme_issue.dart';

/// Почему файл не прочитан.
enum ThemeReadError { tooLarge, notUtf8, unreadable }

/// Запись каталога: либо [text], либо [error].
final class ThemeEntry {
  const ThemeEntry.read(this.name, String this.text) : error = null;
  const ThemeEntry.failed(this.name, ThemeReadError this.error) : text = null;

  /// Имя файла без `.json`.
  final String name;
  final String? text;
  final ThemeReadError? error;
}

sealed class ThemeImportResult {
  const ThemeImportResult();
}

final class ThemeImportImported extends ThemeImportResult {
  const ThemeImportImported(this.name);
  final String name;
}

final class ThemeImportReplaced extends ThemeImportResult {
  const ThemeImportReplaced(this.name);
  final String name;
}

final class ThemeImportUnchanged extends ThemeImportResult {
  const ThemeImportUnchanged(this.name);
  final String name;
}

final class ThemeImportNeedsReplace extends ThemeImportResult {
  const ThemeImportNeedsReplace(this.name);
  final String name;
}

final class ThemeImportInvalid extends ThemeImportResult {
  const ThemeImportInvalid(this.issue);
  final ThemeIssue issue;
}

final class ThemeImportFailed extends ThemeImportResult {
  const ThemeImportFailed();
}

abstract interface class ThemeLibrary {
  /// Записи по алфавиту имени; нет каталога — пустой список.
  Future<List<ThemeEntry>> list();

  /// Импорт файла [sourcePath]; [replace] подтверждает замену.
  Future<ThemeImportResult> import(String sourcePath, {bool replace = false});
}

/// Реализация в памяти для тестов и двойников хоста.
///
/// [themes] — имя → текст; [broken] — имя → причина; [sources] — путь
/// источника → текст файла для [import].
final class InMemoryThemeLibrary implements ThemeLibrary {
  InMemoryThemeLibrary({
    Map<String, String>? themes,
    Map<String, ThemeReadError>? broken,
    Map<String, String>? sources,
  }) : files = {...?themes},
       broken = {...?broken},
       sources = {...?sources};

  /// Текущее содержимое каталога: имя → текст.
  final Map<String, String> files;
  final Map<String, ThemeReadError> broken;
  final Map<String, String> sources;

  @override
  Future<List<ThemeEntry>> list() async {
    final entries = [
      for (final e in files.entries) ThemeEntry.read(e.key, e.value),
      for (final e in broken.entries)
        if (!files.containsKey(e.key)) ThemeEntry.failed(e.key, e.value),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  @override
  Future<ThemeImportResult> import(
    String sourcePath, {
    bool replace = false,
  }) async {
    final text = sources[sourcePath];
    if (text == null) return const ThemeImportFailed();
    // Без сверки с именем источника: импортируют файл с любым именем (D9).
    final parsed = ThemeFile.parse(null, text);
    if (parsed is ThemeRejected) return ThemeImportInvalid(parsed.issue);
    final name = (parsed as ThemeLoaded).theme.name;
    final existing = files[name];
    if (existing == null) {
      files[name] = text;
      broken.remove(name);
      return ThemeImportImported(name);
    }
    if (existing == text) return ThemeImportUnchanged(name);
    if (!replace) return ThemeImportNeedsReplace(name);
    files[name] = text;
    return ThemeImportReplaced(name);
  }
}
