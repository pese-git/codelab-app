import 'package:shared_preferences/shared_preferences.dart';

/// Ключ `shared_preferences`: оформление app одним JSON-документом
/// (`add-app-appearance-page`, D5).
const kAppAppearanceKey = 'codelab.app.appearance';

/// Режим оформления: фиксированный светлый, фиксированный тёмный или режим
/// системы.
enum AppearanceMode { light, dark, system }

/// Выбор оформления пользователем: режим, темы двух режимов, системный акцент.
///
/// ЗАГЛУШКА для красных тестов 4.1/4.5 (change `add-app-appearance-page`):
/// только форма данных; чтение и запись документа — задача 4.2.
final class AppAppearanceSettings {
  const AppAppearanceSettings({
    this.mode = AppearanceMode.system,
    this.lightTheme = 'light',
    this.darkTheme = 'dark',
    this.systemAccent = false,
  });

  final AppearanceMode mode;
  final String lightTheme;
  final String darkTheme;
  final bool systemAccent;

  AppAppearanceSettings copyWith({
    AppearanceMode? mode,
    String? lightTheme,
    String? darkTheme,
    bool? systemAccent,
  }) => AppAppearanceSettings(
    mode: mode ?? this.mode,
    lightTheme: lightTheme ?? this.lightTheme,
    darkTheme: darkTheme ?? this.darkTheme,
    systemAccent: systemAccent ?? this.systemAccent,
  );

  @override
  bool operator ==(Object other) =>
      other is AppAppearanceSettings &&
      other.mode == mode &&
      other.lightTheme == lightTheme &&
      other.darkTheme == darkTheme &&
      other.systemAccent == systemAccent;

  @override
  int get hashCode => Object.hash(mode, lightTheme, darkTheme, systemAccent);

  @override
  String toString() =>
      'AppAppearanceSettings($mode, $lightTheme, $darkTheme, $systemAccent)';
}

/// Результат чтения: значения и диагностика (D5).
final class AppAppearanceLoad {
  const AppAppearanceLoad(
    this.settings, {
    this.storedValueInvalid = false,
    this.readFailure,
  });

  final AppAppearanceSettings settings;
  final bool storedValueInvalid;
  final String? readFailure;
}

/// Порт хранения оформления (D5).
abstract interface class AppAppearancePreferences {
  Future<AppAppearanceLoad> load();

  Future<void> save(AppAppearanceSettings settings);
}

/// ЗАГЛУШКА: всегда значения по умолчанию, запись не делает (задача 4.2).
final class SharedPreferencesAppAppearancePreferences
    implements AppAppearancePreferences {
  const SharedPreferencesAppAppearancePreferences({
    Future<SharedPreferences> Function() open = SharedPreferences.getInstance,
  });

  @override
  Future<AppAppearanceLoad> load() async =>
      const AppAppearanceLoad(AppAppearanceSettings());

  @override
  Future<void> save(AppAppearanceSettings settings) async {}
}
