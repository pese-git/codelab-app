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

/// Почему файл темы не прочитан.
///
/// Почему: сбой одного файла не должен ломать перечисление каталога, а
/// клиент показывает причину своим текстом.
///
/// Как использовать: приходит в [ThemeEntry.error]; `tooLarge` — файл больше
/// `themeFileMaxBytes`, `notUtf8` — не UTF-8, `unreadable` — каталог, битая
/// ссылка или иной сбой чтения.
enum ThemeReadError { tooLarge, notUtf8, unreadable }

/// Запись каталога тем: прочитанный текст файла либо причина, по которой
/// его нет.
///
/// Почему: ядро не читает файлы, а хосту нужен единый вид записи и для
/// хорошего файла, и для испорченного (ошибка перечисления не бросается).
///
/// Как использовать: ровно одно из [text] и [error] не `null`. Текст разбирает
/// `ThemeFile.parse('$name.json', text)`; для записи с [error] хост показывает
/// причину и берёт запасную тему.
final class ThemeEntry {
  const ThemeEntry.read(this.name, String this.text) : error = null;
  const ThemeEntry.failed(this.name, ThemeReadError this.error) : text = null;

  /// Имя файла без `.json`.
  final String name;

  /// Текст файла; `null`, если чтение не удалось.
  final String? text;

  /// Причина неудачи; `null`, если [text] прочитан.
  final ThemeReadError? error;
}

/// Каталог тем не читается: перечисление невозможно (spec app-settings,
/// «Каталог тем не читается»).
///
/// Почему: «каталога нет» (пустой список) и «каталог есть, но недоступен»
/// (`themes` — файл, нет прав) — разные состояния; смешав их, страница
/// показала бы пустой каталог вместо ошибки.
///
/// Как использовать: бросает [ThemeLibrary.list]; хост ловит и показывает
/// сообщение по [failure] на своём языке. Путь и текст ОС сюда намеренно не
/// кладутся: исключение попадает в журнал, а пути содержат имя пользователя
/// (`AGENTS.md` §16).
final class ThemeCatalogException implements Exception {
  const ThemeCatalogException(this.failure);

  final ThemeCatalogFailure failure;

  @override
  String toString() => 'ThemeCatalogException(${failure.name})';
}

/// Причина, по которой каталог тем не читается.
enum ThemeCatalogFailure {
  /// `<home>/themes` существует, но не каталог.
  notADirectory,

  /// Каталог не удалось перечислить (нет прав, сбой ввода-вывода).
  unreadable,
}

/// Исход импорта файла темы (spec `client-themes`, «Импорт файла темы»).
///
/// Почему: у импорта шесть различимых исходов, и страница по-разному
/// реагирует на каждый (запрос замены, ошибка разбора, сбой записи);
/// закрытая иерархия не даёт пропустить случай.
///
/// Как использовать: `switch` по вариантам; запись состоялась только у
/// [ThemeImportImported] и [ThemeImportReplaced].
sealed class ThemeImportResult {
  const ThemeImportResult();
}

/// Новая тема записана в каталог под именем [name] из файла.
final class ThemeImportImported extends ThemeImportResult {
  const ThemeImportImported(this.name);
  final String name;
}

/// Существующая тема [name] заменена после подтверждения (`replace: true`).
final class ThemeImportReplaced extends ThemeImportResult {
  const ThemeImportReplaced(this.name);
  final String name;
}

/// Тема [name] уже есть с тем же содержимым: запись не выполнялась.
final class ThemeImportUnchanged extends ThemeImportResult {
  const ThemeImportUnchanged(this.name);
  final String name;
}

/// Тема [name] уже есть с другим содержимым: ничего не записано, страница
/// спрашивает подтверждение и повторяет импорт с `replace: true`.
final class ThemeImportNeedsReplace extends ThemeImportResult {
  const ThemeImportNeedsReplace(this.name);
  final String name;
}

/// Файл не прошёл разбор ([issue] — ошибка, не предупреждение): в каталог
/// ничего не копируется.
final class ThemeImportInvalid extends ThemeImportResult {
  const ThemeImportInvalid(this.issue);
  final ThemeIssue issue;
}

/// Подтверждение замены отклонено: `name` в файле теперь не тот, что
/// показывали пользователю ([name] — новое имя из файла). Ничего не записано.
///
/// Почему: между проверкой («нужна замена» для `expectedName`) и подтверждением
/// источник мог измениться, и замена затёрла бы другую тему.
final class ThemeImportSourceChanged extends ThemeImportResult {
  const ThemeImportSourceChanged(this.name);
  final String name;
}

/// Источник не прочитан или запись не удалась. Деталей нет намеренно: пути и
/// тексты ОС не должны попадать в состояние и журнал.
final class ThemeImportFailed extends ThemeImportResult {
  const ThemeImportFailed();
}

/// Порт каталога пользовательских тем.
///
/// Почему: границу с файловой системой держит адаптер (`IoThemeLibrary`), а
/// ядро и Cubit-ы работают с портом и двойником в тестах.
///
/// Как использовать: [list] — для страницы оформления, [read] — для старта
/// (по файлу на режим), [import] — для «Import JSON…». Методы не бросают
/// исключений ввода-вывода: сбой — запись с ошибкой или `ThemeImportFailed`.
abstract interface class ThemeLibrary {
  /// Записи по алфавиту имени; нет каталога — пустой список (каталог при
  /// чтении не создаётся). Каталог есть, но не читается (`themes` — файл, нет
  /// прав) — [ThemeCatalogException], а не пустой список.
  Future<List<ThemeEntry>> list();

  /// Читает одну тему по имени (старт app читает файлы двух режимов с
  /// ограничением по времени на каждый файл, design.md D13). `null` — файла
  /// нет или [name] не по шаблону `[a-z0-9-]{1,32}` (файловая система при
  /// этом не трогается). Ошибки чтения — запись с `error`, как в [list].
  Future<ThemeEntry?> read(String name);

  /// Импорт файла [sourcePath] (D9): разбор без сверки имени источника, запись
  /// байт в байт под `name` из файла. [replace] подтверждает замену
  /// существующей темы с другим содержимым.
  ///
  /// [expectedName] — имя, для которого пользователь подтвердил замену (из
  /// `ThemeImportNeedsReplace`). При `replace: true` и другом `name` в файле
  /// результат — [ThemeImportSourceChanged], запись не выполняется. Без
  /// [replace] параметр не учитывается.
  Future<ThemeImportResult> import(
    String sourcePath, {
    bool replace = false,
    String? expectedName,
  });
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

  /// Текущее содержимое каталога: имя → текст; тесты читают его для проверок.
  final Map<String, String> files;

  /// Записи, которые «не читаются»: имя → причина.
  final Map<String, ThemeReadError> broken;

  /// Файлы-источники импорта: путь → текст.
  final Map<String, String> sources;

  /// Смоделированный сбой каталога: пока не `null`, [list] бросает
  /// [ThemeCatalogException] с этой причиной.
  ThemeCatalogFailure? catalogFailure;

  @override
  Future<List<ThemeEntry>> list() async {
    final failure = catalogFailure;
    if (failure != null) throw ThemeCatalogException(failure);
    final entries = [
      for (final e in files.entries) ThemeEntry.read(e.key, e.value),
      for (final e in broken.entries)
        if (!files.containsKey(e.key)) ThemeEntry.failed(e.key, e.value),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  @override
  Future<ThemeEntry?> read(String name) async {
    if (!isValidThemeName(name)) return null;
    final text = files[name];
    if (text != null) return ThemeEntry.read(name, text);
    final error = broken[name];
    return error == null ? null : ThemeEntry.failed(name, error);
  }

  @override
  Future<ThemeImportResult> import(
    String sourcePath, {
    bool replace = false,
    String? expectedName,
  }) async {
    final text = sources[sourcePath];
    if (text == null) return const ThemeImportFailed();
    // Без сверки с именем источника: импортируют файл с любым именем (D9).
    final parsed = ThemeFile.parse(null, text);
    if (parsed is ThemeRejected) return ThemeImportInvalid(parsed.issue);
    final name = (parsed as ThemeLoaded).theme.name;
    final existing = files[name];
    // Подтверждение относится к теме, которую показывали пользователю: если
    // источник изменился и `name` другой, замена затёрла бы чужую тему.
    if (replace && expectedName != null && expectedName != name) {
      return ThemeImportSourceChanged(name);
    }
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
