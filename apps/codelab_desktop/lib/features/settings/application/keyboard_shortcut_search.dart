/// Поиск по таблице сочетаний страницы «Keyboard» (заглушка сигнатур для
/// красных тестов 3.1 change `add-app-keyboard-page`; D6, D8).
///
/// Почему: отбор строк — чистая функция без Flutter, её проще проверять
/// отдельно от страницы.
///
/// Для чего: `KeyboardShortcutEntry` — запись каталога с готовыми текстами
/// действия (язык интерфейса и английский) и нотациями клавиш;
/// `filterKeyboardShortcuts` — подстрока без регистра и пробелов по краям
/// по действию и по клавише; для клавиши пробелы и `+` удаляются.
///
/// Как использовать: сейчас функция ничего не отбирает (заглушка); поведение —
/// задача 3.2.
library;

import 'package:codelab_ui/codelab_ui.dart';

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

/// Отбирает [entries] по [query]; заглушка возвращает пустой список.
List<KeyboardShortcutEntry> filterKeyboardShortcuts(
  List<KeyboardShortcutEntry> entries,
  String query,
) => const [];
