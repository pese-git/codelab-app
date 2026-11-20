import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ключ `shared_preferences`: оформление app одним JSON-документом
/// (`add-app-appearance-page`, D5).
const kAppAppearanceKey = 'codelab.app.appearance';

/// Режим оформления: фиксированный светлый, фиксированный тёмный или режим
/// системы.
enum AppearanceMode { light, dark, system }

/// Выбор оформления пользователем: режим, темы двух режимов, системный акцент.
///
/// Почему отдельный тип: четыре поля читаются и пишутся одним JSON-документом
/// (D5), а `AppAppearanceCubit` публикует их как единое состояние выбора.
///
/// Для чего: неизменяемое значение с умолчаниями без сохранённого выбора —
/// `Match system`, темы `light` и `dark`, системный акцент выключен (Q3, Q5).
///
/// Как использовать: порт [AppAppearancePreferences] возвращает его в
/// [AppAppearanceLoad] и принимает в `save`; `copyWith` меняет одно поле.
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

/// [AppAppearancePreferences] в `shared_preferences` под ключом
/// [kAppAppearanceKey] (D5; spec app-settings «Хранение оформления»).
///
/// Почему один документ: данные одного concern хранятся одним ключом с
/// версией формата (`platform-integration.md` §28). Незнакомое значение поля
/// читается как значение по умолчанию этого поля и НЕ перезаписывается до
/// явного выбора пользователя (`AGENTS.md` §2): `load` ничего не пишет.
///
/// Для чего: порт читается в `main` до `runApp` и не бросает — сбой хранилища
/// даёт умолчания и [AppAppearanceLoad.readFailure] (имя типа, без текста: в
/// нём бывают пути).
///
/// Как использовать: `const SharedPreferencesAppAppearancePreferences()`;
/// [open] — шов тестов. Ошибки записи порт не скрывает: их показывает
/// `AppAppearanceCubit` (`saveFailed`).
final class SharedPreferencesAppAppearancePreferences
    implements AppAppearancePreferences {
  const SharedPreferencesAppAppearancePreferences({
    Future<SharedPreferences> Function() open = SharedPreferences.getInstance,
  }) : _open = open;

  final Future<SharedPreferences> Function() _open;

  /// Формат имени темы: как у имён файлов каталога тем (spec client-themes).
  static final _name = RegExp(r'^[a-z0-9-]{1,32}$');

  @override
  Future<AppAppearanceLoad> load() async {
    final Object? value;
    try {
      final prefs = await _open();
      // `get`, а не `getString`: нестроковое значение не должно бросать
      // `TypeError` и ронять запуск.
      value = prefs.get(kAppAppearanceKey);
    } on Object catch (error) {
      return AppAppearanceLoad(
        const AppAppearanceSettings(),
        readFailure: error.runtimeType.toString(),
      );
    }
    if (value == null) return const AppAppearanceLoad(AppAppearanceSettings());
    return _parse(value);
  }

  static AppAppearanceLoad _parse(Object value) {
    const invalid = AppAppearanceLoad(
      AppAppearanceSettings(),
      storedValueInvalid: true,
    );
    if (value is! String) return invalid;
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return invalid;
    }
    if (decoded is! Map<String, Object?>) return invalid;
    final document = decoded;
    final version = document['version'];
    if (version != null && version != 1) return invalid;

    var bad = false;
    T field<T>(String key, T fallback, T? Function(Object value) read) {
      if (!document.containsKey(key)) return fallback;
      final raw = document[key];
      final parsed = raw == null ? null : read(raw);
      if (parsed == null) {
        bad = true;
        return fallback;
      }
      return parsed;
    }

    const defaults = AppAppearanceSettings();
    final mode = field<AppearanceMode>(
      'mode',
      defaults.mode,
      (v) => AppearanceMode.values.where((m) => m.name == v).firstOrNull,
    );
    // Тема чужого режима в поле режима — незнакомое значение (D5): `dark` и
    // `high-contrast` светлыми не бывают, `light` тёмной тоже.
    final light = field<String>(
      'light_theme',
      defaults.lightTheme,
      (v) =>
          v is String &&
              _name.hasMatch(v) &&
              v != 'dark' &&
              v != 'high-contrast'
          ? v
          : null,
    );
    final dark = field<String>(
      'dark_theme',
      defaults.darkTheme,
      (v) => v is String && _name.hasMatch(v) && v != 'light' ? v : null,
    );
    final accent = field<bool>(
      'system_accent',
      defaults.systemAccent,
      (v) => v is bool ? v : null,
    );
    return AppAppearanceLoad(
      AppAppearanceSettings(
        mode: mode,
        lightTheme: light,
        darkTheme: dark,
        systemAccent: accent,
      ),
      storedValueInvalid: bad,
    );
  }

  @override
  Future<void> save(AppAppearanceSettings settings) async {
    final prefs = await _open();
    await prefs.setString(
      kAppAppearanceKey,
      jsonEncode({
        'version': 1,
        'mode': settings.mode.name,
        'light_theme': settings.lightTheme,
        'dark_theme': settings.darkTheme,
        'system_accent': settings.systemAccent,
      }),
    );
  }
}
