/// Поиск по таблице сочетаний страницы «Keyboard» (change
/// `add-app-keyboard-page`; D6, D8).
///
/// Почему: отбор строк — чистая функция без виджетов и `BuildContext`, её
/// проще проверять отдельно от страницы (из кита нужен только тип записи
/// каталога), а страница собирает записи из каталога и ARB заново
/// в каждом `build`, поэтому смена языка пересобирает их без подписки.
///
/// Для чего: `KeyboardShortcutEntry` — запись каталога с готовыми текстами
/// действия (язык интерфейса и английский) и нотациями клавиш;
/// `filterKeyboardShortcuts` — подстрока без регистра и пробелов по краям
/// по действию и по клавише. По «Where» поиск не идёт (D8): иначе запрос
/// `composer` выдавал бы половину таблицы.
///
/// Как использовать: `filterKeyboardShortcuts(entries, query)` возвращает
/// записи в исходном порядке; пустой запрос — все записи.
library;

import 'package:codelab_ui/codelab_ui.dart' show CodeLabShortcut;

/// Запись для поиска: запись каталога и тексты, по которым её находят.
final class KeyboardShortcutEntry {
  const KeyboardShortcutEntry({
    required this.shortcut,
    required this.action,
    required this.englishAction,
    required this.notations,
  });

  final CodeLabShortcut shortcut;

  /// Текст «Action» на языке интерфейса.
  final String action;

  /// Английский текст «Action» (его знают из документации).
  final String englishAction;

  /// Нотации клавиш всех комбинаций записи: символы macOS, слова Windows и
  /// Linux, слова macOS — независимо от платформы app.
  final List<String> notations;
}

/// Отбирает [entries] по [query]: подстрока без учёта регистра и пробелов по
/// краям в тексте действия (язык интерфейса и английский) или в нотации
/// клавиш. Для клавиш из запроса и из нотации удаляются пробелы и `+`, поэтому
/// `ctrl shift e` и `Ctrl+Shift+E` равны (D8). Порядок записей сохраняется.
List<KeyboardShortcutEntry> filterKeyboardShortcuts(
  List<KeyboardShortcutEntry> entries,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return entries;
  }
  final keyNeedle = _keyForm(needle);
  return [
    for (final entry in entries)
      if (entry.action.toLowerCase().contains(needle) ||
          entry.englishAction.toLowerCase().contains(needle) ||
          // Запрос из одних пробелов и плюсов даёт пустую форму и совпал бы
          // со всем; такой запрос ничего не ищет по клавишам.
          (keyNeedle.isNotEmpty &&
              entry.notations.any(
                (notation) => _keyForm(notation).contains(keyNeedle),
              )))
        entry,
  ];
}

/// Нотация без пробелов и `+` в нижнем регистре.
String _keyForm(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[\s+]'), '');
