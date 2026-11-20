import 'package:codelab_client_core/codelab_client_core.dart';

import '../../core/platform/app_appearance_preferences.dart';
import '../../core/platform/system_accent_source.dart';

/// Какие темы режимов заменены встроенными, потому что файл не загрузился.
enum AppearanceFallback { none, light, dark, both }

/// Начальное оформление, которое `main` передаёт в composition root (D13).
///
/// ЗАГЛУШКА для красных тестов 4.5/4.7 (`add-app-appearance-page`): форма
/// шва; чтение файлов и ограничение времени — задачи 4.6 и 4.8.
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

  /// Читает файлы тем двух режимов через [library] (не дольше [fileTimeout]
  /// на чтение) и собирает шов. ЗАГЛУШКА: возвращает значения по умолчанию.
  static Future<AppAppearanceStart> resolve({
    required AppAppearanceLoad load,
    required ThemeLibrary library,
    SystemAccentSource? accentSource,
    Duration fileTimeout = const Duration(seconds: 1),
  }) async => AppAppearanceStart.defaults;

  final AppAppearanceSettings settings;

  /// Загруженная пользовательская тема светлого режима; `null` — выбрана
  /// встроенная или файл не загрузился.
  final ThemeLoaded? lightTheme;
  final ThemeLoaded? darkTheme;

  /// Порт системного акцента сообщил поддержку при старте.
  final bool systemAccentSupported;

  /// ARGB системного акцента, прочитанный при старте.
  final int? systemAccent;

  final bool storedValueInvalid;
  final String? readFailure;

  /// Какие режимы вернулись к встроенным темам из-за ошибки файла.
  AppearanceFallback get fallback => AppearanceFallback.none;
}
