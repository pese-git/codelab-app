/// Порт выбора файла темы в системном диалоге (`add-app-appearance-page`, D9).
///
/// Почему порт: системный диалог — нативный API (`AGENTS.md` §11); Cubit
/// страницы «Appearance» не вызывает плагин `file_selector`, а тест подставляет
/// двойник (правило сторожа: `package:file_selector/` — только
/// `lib/core/platform/`, D1).
///
/// Для чего: «Import JSON…» открывает диалог выбора ОДНОГО файла `.json`;
/// отмена диалога — `null`, состояние страницы при этом не меняется.
///
/// Как использовать: привязан в composition root
/// (`createCodeLabRootScope(themeFilePicker:)`); вызывается по нажатию
/// пользователя. Возвращает абсолютный путь выбранного файла — его читает
/// `ThemeLibrary.import`, а не страница.
///
/// ЗАГЛУШКА для красных тестов 5.3/5.5: только порт; адаптер на
/// `file_selector` — задача 5.4.
abstract interface class ThemeFilePicker {
  /// Путь выбранного файла или `null`, если пользователь закрыл диалог.
  Future<String?> pickThemeFile();
}
