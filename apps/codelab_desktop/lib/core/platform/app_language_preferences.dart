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
/// Почему отдельный порт: язык — настройка app, а не профиля и не агента, поэтому
/// `config.yaml` и `profiles.json` не трогаются (add-desktop-localization, D2;
/// образец — `ConnectionPreferences`).
///
/// Как использовать: `load` читает значение до `runApp`; `save(system)`
/// удаляет ключ. Ошибки хранилища порт не скрывает — вызывающий
/// (`AppLanguageCubit`) выставляет `saveFailed`.
abstract interface class AppLanguagePreferences {
  Future<AppLanguagePreference> load();

  Future<void> save(AppLanguagePreference preference);
}

/// [AppLanguagePreferences] в `shared_preferences` под ключом
/// [kAppLanguageKey].
///
/// Незнакомое сохранённое значение читается как `system` и НЕ
/// перезаписывается: данные пользователя не портятся молча (`AGENTS.md` §2).
final class SharedPreferencesAppLanguagePreferences
    implements AppLanguagePreferences {
  const SharedPreferencesAppLanguagePreferences();

  @override
  Future<AppLanguagePreference> load() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(kAppLanguageKey)) {
      'en' => AppLanguagePreference.en,
      'ru' => AppLanguagePreference.ru,
      _ => AppLanguagePreference.system,
    };
  }

  @override
  Future<void> save(AppLanguagePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    switch (preference) {
      case AppLanguagePreference.system:
        await prefs.remove(kAppLanguageKey);
      case AppLanguagePreference.en:
        await prefs.setString(kAppLanguageKey, 'en');
      case AppLanguagePreference.ru:
        await prefs.setString(kAppLanguageKey, 'ru');
    }
  }
}
