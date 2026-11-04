import 'package:shared_preferences/shared_preferences.dart';

/// Хранилище последней открытой страницы настроек.
///
/// Почему: пользователь ожидает вернуться на ту же страницу (spec
/// app-settings «Переход в настройки и обратно»). Потребитель один —
/// `NavigationCubit`, поэтому порт лежит рядом с ним, а не в `lib/core/`
/// (`layers-and-dependencies.md` §14; design.md change
/// `add-app-settings-shell`, D2).
///
/// Для чего: порт `NavigationCubit`; реализация по умолчанию —
/// [SharedPreferencesSettingsPageStore].
///
/// Как использовать: [load] перед открытием настроек (`null` — страница не
/// сохранена), [save] после выбора страницы. Значение — `SettingsPage.slug`;
/// разбор и проверку видимости делает `NavigationCubit`. Ошибки порт не
/// скрывает: Cubit пишет предупреждение и продолжает работу.
abstract interface class SettingsPageStore {
  Future<String?> load();

  Future<void> save(String page);
}

const _kLastPageKey = 'codelab.settings.last_page';

/// [SettingsPageStore] в `shared_preferences` под ключом
/// `codelab.settings.last_page`, по образцу `SharedPreferencesDockLayoutStore`.
final class SharedPreferencesSettingsPageStore implements SettingsPageStore {
  const SharedPreferencesSettingsPageStore();

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastPageKey);
  }

  @override
  Future<void> save(String page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastPageKey, page);
  }
}
