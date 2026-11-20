import 'dart:async';

import 'dart:ui' show Brightness;

import 'package:codelab_client_core/codelab_client_core.dart';

import '../../core/platform/app_appearance_preferences.dart';
import '../../core/platform/system_accent_source.dart';
import 'built_in_themes.dart';

/// Какие режимы показывают встроенную тему вместо выбранной пользовательской,
/// потому что её файл не загрузился (spec app-settings «Режим оформления и
/// темы режимов»).
enum AppearanceFallback { none, light, dark, both }

/// Почему тема режима не загрузилась при старте (D12): код для события
/// `appearance.theme_invalid` — код разбора (`invalidJson`, …), `missing`,
/// `tooLarge`, `notUtf8`, `unreadable` или `wrongMode` (база темы относится к
/// другому режиму); у проблем без позиции [line] и [column] равны 0. Имя темы
/// сюда не входит: оно выбрано пользователем и бывает личным.
final class AppearanceThemeProblem {
  const AppearanceThemeProblem(this.code, {this.line = 0, this.column = 0});

  final String code;
  final int line;
  final int column;
}

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
    this.themeProblems = const [],
  });

  /// Умолчание без сохранённого выбора: `Match system`, `light`, `dark`.
  static const defaults = AppAppearanceStart();

  /// Читает файлы тем двух режимов и системный акцент и собирает шов.
  ///
  /// Каждый файл читается через [ThemeLibrary.read] с ограничением
  /// [fileTimeout] (1 с по умолчанию): не прочитанный вовремя, не
  /// разобранный и не существующий файл — как не загрузившийся (режим
  /// показывает встроенную тему, выбор не меняется). Встроенные темы файлов не
  /// читают. Пользовательская тема, база которой относится к другому режиму,
  /// тоже не загрузилась (`wrongMode`): имя в документе сохраняется и
  /// документ не помечается повреждённым. Метод не бросает: ошибки чтения — это «не загрузилась».
  ///
  /// [accentSource] — порт, у которого `supported` уже известен после его
  /// старта; его первое чтение тоже ограничено [fileTimeout].
  static Future<AppAppearanceStart> resolve({
    required AppAppearanceLoad load,
    required ThemeLibrary library,
    SystemAccentSource? accentSource,
    Duration fileTimeout = const Duration(seconds: 1),
  }) async {
    final settings = load.settings;

    /// Файл темы [id] режима [brightness]: тема или причина, почему её нет.
    Future<({ThemeLoaded? theme, AppearanceThemeProblem? problem})> read(
      String id,
      Brightness brightness,
    ) async {
      if (kBuiltInThemeIds.contains(id)) return (theme: null, problem: null);
      try {
        final entry = await library.read(id).timeout(fileTimeout);
        if (entry == null) {
          return (
            theme: null,
            problem: const AppearanceThemeProblem('missing'),
          );
        }
        final text = entry.text;
        if (text == null) {
          return (
            theme: null,
            problem: AppearanceThemeProblem(entry.error?.name ?? 'unreadable'),
          );
        }
        switch (ThemeFile.parse('$id.json', text)) {
          case ThemeRejected(:final issue):
            return (
              theme: null,
              problem: AppearanceThemeProblem(
                issue.code.name,
                line: issue.line,
                column: issue.column,
              ),
            );
          case ThemeLoaded loaded:
            // База пользовательской темы относится к другому режиму: тема не
            // загрузилась для этого режима, а имя в документе сохраняется
            // (spec app-settings «Хранение оформления»).
            final light = loaded.theme.base == ThemeBase.light;
            if (light != (brightness == Brightness.light)) {
              return (
                theme: null,
                problem: const AppearanceThemeProblem('wrongMode'),
              );
            }
            return (theme: loaded, problem: null);
        }
      } on Object {
        // Таймаут и исключение порта одинаково дают встроенную тему режима;
        // текст исключения в журнал не идёт.
        return (
          theme: null,
          problem: const AppearanceThemeProblem('unreadable'),
        );
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
      read(settings.lightTheme, Brightness.light),
      read(settings.darkTheme, Brightness.dark),
    ]);
    final supported = accentSource?.supported ?? false;
    return AppAppearanceStart(
      settings: settings,
      lightTheme: results[0].theme,
      darkTheme: results[1].theme,
      systemAccentSupported: supported,
      systemAccent: supported ? await readAccent(accentSource!) : null,
      storedValueInvalid: load.storedValueInvalid,
      readFailure: load.readFailure,
      themeProblems: [
        for (final result in results)
          if (result.problem != null) result.problem!,
      ],
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

  /// Причины, по которым выбранные пользовательские темы не загрузились.
  final List<AppearanceThemeProblem> themeProblems;

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
