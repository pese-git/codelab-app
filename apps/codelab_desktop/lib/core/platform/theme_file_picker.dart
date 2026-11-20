import 'package:file_selector/file_selector.dart';

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
abstract interface class ThemeFilePicker {
  /// Путь выбранного файла или `null`, если пользователь закрыл диалог.
  Future<String?> pickThemeFile();
}

/// Настоящий адаптер на `file_selector` (`openFile`, тип `json`).
///
/// Почему не фильтр по содержимому: диалог только предлагает `.json`; файл
/// недоверен, его размер, кодировку и формат проверяет `ThemeLibrary.import`
/// (spec client-themes «Импорт файла темы»).
final class FileSelectorThemeFilePicker implements ThemeFilePicker {
  const FileSelectorThemeFilePicker();

  static const _json = XTypeGroup(
    label: 'JSON',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  @override
  Future<String?> pickThemeFile() async {
    final file = await openFile(acceptedTypeGroups: const [_json]);
    return file?.path;
  }
}
