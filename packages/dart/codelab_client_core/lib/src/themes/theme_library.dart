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
  /// чтении не создаётся).
  Future<List<ThemeEntry>> list();

  /// Читает одну тему по имени (старт app читает файлы двух режимов с
  /// ограничением по времени на каждый файл, design.md D13). `null` — файла
  /// нет или [name] не по шаблону `[a-z0-9-]{1,32}` (файловая система при
  /// этом не трогается). Ошибки чтения — запись с `error`, как в [list].
  Future<ThemeEntry?> read(String name);

  /// Импорт файла [sourcePath] (D9): разбор без сверки имени источника, запись
  /// байт в байт под `name` из файла. [replace] подтверждает замену
  /// существующей темы с другим содержимым.
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

  /// Текущее содержимое каталога: имя → текст; тесты читают его для проверок.
  final Map<String, String> files;

  /// Записи, которые «не читаются»: имя → причина.
  final Map<String, ThemeReadError> broken;

  /// Файлы-источники импорта: путь → текст.
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
