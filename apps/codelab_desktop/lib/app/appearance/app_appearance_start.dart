import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart';

import '../../core/platform/app_appearance_preferences.dart';
import '../../core/platform/system_accent_source.dart';
import 'built_in_themes.dart';

/// Какие режимы показывают встроенную тему вместо выбранной пользовательской,
/// потому что её файл не загрузился (spec app-settings «Режим оформления и
/// темы режимов»).
enum AppearanceFallback { none, light, dark, both }

/// Начальное оформление, которое `main` передаёт в composition root
/// (design.md change `add-app-appearance-page`, D13).
///
/// Почему отдельный тип: журнал при чтении ещё не настроен
/// (`configureCodeLabLogging` — в root scope), поэтому шов несёт решение
/// (выбор, загруженные темы, акцент) и диагностику чтения, а события пишет
/// модуль после настройки журнала (`app.appearance_resolved`, как
/// `app.locale_resolved`). Первый кадр рисуется уже в итоговом оформлении, без
/// мигания темы: файлы после старта не дочитываются.
///
/// Как использовать: `await AppAppearanceStart.resolve(...)` в `main` до
/// `runApp`; без шва composition root берёт [defaults].
final class AppAppearanceStart {
  const AppAppearanceStart({
    this.settings = const AppAppearanceSettings(),
    this.lightTheme,
    this.darkTheme,
    this.systemAccentSupported = false,
    this.systemAccent,
    this.storedValueInvalid = false,
    this.readFailure,
  });

  /// Умолчание без сохранённого выбора: `Match system`, `light`, `dark`.
  static const defaults = AppAppearanceStart();

  /// Читает файлы тем двух режимов и системный акцент и собирает шов.
  ///
  /// Каждый файл читается через [ThemeLibrary.read] с ограничением
  /// [fileTimeout] (1 с по умолчанию): не прочитанный вовремя, не
  /// разобранный и не существующий файл — как не загрузившийся (режим
  /// показывает встроенную тему, выбор не меняется). Встроенные темы файлов не
  /// читают. Тема чужого режима в поле режима читается как умолчание поля
  /// (D5). Метод не бросает: ошибки чтения — это «не загрузилась».
  ///
  /// [accentSource] — порт, у которого `supported` уже известен после его
  /// старта; его первое чтение тоже ограничено [fileTimeout].
  static Future<AppAppearanceStart> resolve({
    required AppAppearanceLoad load,
    required ThemeLibrary library,
    SystemAccentSource? accentSource,
    Duration fileTimeout = const Duration(seconds: 1),
  }) async {
    var settings = load.settings;
    var invalid = load.storedValueInvalid;

    Future<ThemeLoaded?> read(String id) async {
      if (kBuiltInThemeIds.contains(id)) return null;
      try {
        final entry = await library.read(id).timeout(fileTimeout);
        final text = entry?.text;
        if (text == null) return null;
        final parsed = ThemeFile.parse('$id.json', text);
        return parsed is ThemeLoaded ? parsed : null;
      } on Object {
        // Причина не нужна: таймаут, ошибка чтения и ошибка разбора одинаково
        // дают встроенную тему режима; подробности покажет страница.
        return null;
      }
    }

    Future<int?> readAccent(SystemAccentSource source) async {
      try {
        return await source.read().timeout(fileTimeout);
      } on Object {
        return null;
      }
    }

    final results = await Future.wait([
      read(settings.lightTheme),
      read(settings.darkTheme),
    ]);
    var light = results[0];
    var dark = results[1];
    // Пользовательская тема чужого режима в поле режима — незнакомое значение.
    if (light != null && light.theme.base != ThemeBase.light) {
      light = null;
      settings = settings.copyWith(lightTheme: 'light');
      invalid = true;
    }
    if (dark != null && dark.theme.base == ThemeBase.light) {
      dark = null;
      settings = settings.copyWith(darkTheme: 'dark');
      invalid = true;
    }
    final supported = accentSource?.supported ?? false;
    return AppAppearanceStart(
      settings: settings,
      lightTheme: light,
      darkTheme: dark,
      systemAccentSupported: supported,
      systemAccent: supported ? await readAccent(accentSource!) : null,
      storedValueInvalid: invalid,
      readFailure: load.readFailure,
    );
  }

  final AppAppearanceSettings settings;

  /// Загруженная пользовательская тема светлого режима; `null` — выбрана
  /// встроенная или файл не загрузился.
  final ThemeLoaded? lightTheme;
  final ThemeLoaded? darkTheme;

  /// Порт системного акцента сообщил поддержку при старте.
  final bool systemAccentSupported;

  /// ARGB системного акцента, прочитанный при старте.
  final int? systemAccent;

  /// В хранилище незнакомое значение (поле или весь документ).
  final bool storedValueInvalid;

  /// Имя типа ошибки чтения хранилища; `null` — чтение прошло.
  final String? readFailure;

  /// Какие режимы вернулись к встроенным темам из-за ошибки файла.
  AppearanceFallback get fallback {
    final light =
        !kBuiltInThemeIds.contains(settings.lightTheme) && lightTheme == null;
    final dark =
        !kBuiltInThemeIds.contains(settings.darkTheme) && darkTheme == null;
    return switch ((light, dark)) {
      (true, true) => AppearanceFallback.both,
      (true, false) => AppearanceFallback.light,
      (false, true) => AppearanceFallback.dark,
      _ => AppearanceFallback.none,
    };
  }
}
