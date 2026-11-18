import 'package:shared_preferences/shared_preferences.dart';

/// Ключ `shared_preferences`: язык интерфейса app (`en`/`ru`; для `system`
/// ключа нет).
const kAppLanguageKey = 'codelab.app.language';

/// Выбор языка интерфейса пользователем.
///
/// `system` — «язык системы»: явного выбора нет, язык выводит
/// `resolveAppLocale` (`add-desktop-localization`, D2).
enum AppLanguagePreference { system, en, ru }

/// Порт хранения выбранного языка интерфейса.
///
/// ЗАГЛУШКА красного теста задачи 1.1: реализация — задача 1.2
/// (`add-desktop-localization`, D2).
abstract interface class AppLanguagePreferences {
  Future<AppLanguagePreference> load();

  Future<void> save(AppLanguagePreference preference);
}

/// [AppLanguagePreferences] в `shared_preferences` (заглушка до задачи 1.2).
final class SharedPreferencesAppLanguagePreferences
    implements AppLanguagePreferences {
  const SharedPreferencesAppLanguagePreferences();

  @override
  Future<AppLanguagePreference> load() async {
    // Заглушка: чтобы тест падал по делу, а не по компиляции.
    await SharedPreferences.getInstance();
    throw UnimplementedError('add-desktop-localization 1.2');
  }

  @override
  Future<void> save(AppLanguagePreference preference) async {
    throw UnimplementedError('add-desktop-localization 1.2');
  }
}
