import 'dart:ui';

import '../../core/platform/app_language_preferences.dart';
import 'app_locale.dart';

/// Начальный язык, который `main` передаёт в composition root.
///
/// Почему отдельный тип: шов несёт только решение (`preference`, `locale`) и
/// диагностику чтения. Каталог `AppLocalizations` по нему строит сам Cubit, а
/// событие о незнакомом значении или сбое чтения пишет модуль после настройки
/// журнала (`add-desktop-localization`, D2, D13).
///
/// Как использовать: `AppLanguageStart.fromLoad(await prefs.load(), locales)`
/// в `main`; без шва composition root берёт [AppLanguageStart.fallback].
final class AppLanguageStart {
  const AppLanguageStart({
    required this.preference,
    required this.locale,
    this.storedValueInvalid = false,
    this.readFailure,
  });

  /// Результат чтения и языки системы → начальный язык.
  factory AppLanguageStart.fromLoad(
    AppLanguageLoad load,
    List<Locale> systemLocales,
  ) => AppLanguageStart(
    preference: load.preference,
    locale: resolveAppLocale(load.preference, systemLocales),
    storedValueInvalid: load.storedValueInvalid,
    readFailure: load.readFailure,
  );

  /// Умолчание без предпочтения: `system` и английский.
  static const fallback = AppLanguageStart(
    preference: AppLanguagePreference.system,
    locale: Locale('en'),
  );

  final AppLanguagePreference preference;
  final Locale locale;

  /// В хранилище незнакомое или нестроковое значение (D13).
  final bool storedValueInvalid;

  /// Имя типа ошибки чтения хранилища; `null` — чтение прошло.
  final String? readFailure;
}
