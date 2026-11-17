import 'package:shared_preferences/shared_preferences.dart';

/// Ключ `shared_preferences`: id профиля по умолчанию.
const kConnectionDefaultProfileKey = 'codelab.connection.default_profile';

/// Настройки подключения, которые живут в `shared_preferences`, а не в
/// `profiles.json`.
///
/// Почему отдельный порт: выбор профиля по умолчанию — настройка app, а не
/// профиля. В `profiles.json` его писать нельзя: он изменил бы формат
/// `version: 1`, общий с CLI (design.md change `add-app-settings-shell`, D5).
/// «Connect on start» удалён (`require-project-folder`, D19): ключ
/// `codelab.connection.connect_on_start` больше не читается и не пишется.
///
/// Для чего: потребители — страница «Connection» (`ConnectionSettingsCubit`),
/// рабочее место (`ConnectionCubit`: профиль до первого старта) и
/// composition root; поэтому порт лежит в
/// `lib/core/platform/`, а не рядом с одним из них
/// (`layers-and-dependencies.md` §14).
///
/// Как использовать: порт не скрывает ошибок хранилища — вызывающий пишет
/// предупреждение и продолжает с умолчанием. Значение по умолчанию: профиль —
/// `null` (встроенный агент).
abstract interface class ConnectionPreferences {
  /// Сохранённый id профиля по умолчанию; `null` — выбора нет.
  Future<String?> loadDefaultProfileId();

  /// Сохраняет [id]; `null` удаляет ключ (встроенный агент по умолчанию).
  Future<void> saveDefaultProfileId(String? id);
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
}
