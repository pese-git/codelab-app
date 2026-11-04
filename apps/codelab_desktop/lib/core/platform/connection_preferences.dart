import 'package:shared_preferences/shared_preferences.dart';

/// Ключ `shared_preferences`: id профиля по умолчанию.
const kConnectionDefaultProfileKey = 'codelab.connection.default_profile';

/// Ключ `shared_preferences`: «Connect on start».
const kConnectionConnectOnStartKey = 'codelab.connection.connect_on_start';

/// Настройки подключения, которые живут в `shared_preferences`, а не в
/// `profiles.json`.
///
/// Почему отдельный порт: выбор профиля по умолчанию и «Connect on start» —
/// настройки app, а не профиля. В `profiles.json` их писать нельзя: флаг в
/// файле изменил бы формат `version: 1`, общий с CLI (design.md change
/// `add-app-settings-shell`, D5, D8).
///
/// Для чего: потребители — страница «Connection» (`ConnectionSettingsCubit`),
/// рабочее место (`ConnectionCubit`: профиль до первого подключения,
/// «Connect on start») и composition root; поэтому порт лежит в
/// `lib/core/platform/`, а не рядом с одним из них
/// (`layers-and-dependencies.md` §14).
///
/// Как использовать: порт не скрывает ошибок хранилища — вызывающий пишет
/// предупреждение и продолжает с умолчанием. Значения по умолчанию: профиль —
/// `null` (встроенный агент), «Connect on start» — `false`.
abstract interface class ConnectionPreferences {
  /// Сохранённый id профиля по умолчанию; `null` — выбора нет.
  Future<String?> loadDefaultProfileId();

  /// Сохраняет [id]; `null` удаляет ключ (встроенный агент по умолчанию).
  Future<void> saveDefaultProfileId(String? id);

  Future<bool> loadConnectOnStart();

  Future<void> saveConnectOnStart(bool value);
}

/// [ConnectionPreferences] в `shared_preferences` под ключами
/// `codelab.connection.*`, по образцу `SharedPreferencesDockLayoutStore`.
final class SharedPreferencesConnectionPreferences
    implements ConnectionPreferences {
  const SharedPreferencesConnectionPreferences();

  @override
  Future<String?> loadDefaultProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kConnectionDefaultProfileKey);
  }

  @override
  Future<void> saveDefaultProfileId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(kConnectionDefaultProfileKey);
    } else {
      await prefs.setString(kConnectionDefaultProfileKey, id);
    }
  }

  @override
  Future<bool> loadConnectOnStart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kConnectionConnectOnStartKey) ?? false;
  }

  @override
  Future<void> saveConnectOnStart(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kConnectionConnectOnStartKey, value);
  }
}
