import 'dart:ui';

import 'package:codelab_desktop/core/platform/app_language_preferences.dart';

/// Разрешает язык интерфейса по выбору пользователя и языкам системы.
///
/// Почему чистая функция: правило «явный выбор сильнее системы» должно
/// проверяться без Flutter и хранилища (add-desktop-localization, D2).
///
/// Для чего: единственное место, где `AppLanguagePreference` превращается в
/// `Locale` — для `main` до `runApp` и для `AppLanguageCubit`.
///
/// Как использовать: `resolveAppLocale(preference, PlatformDispatcher
/// .instance.locales)`. До итерации 6 (D2, D12) `system` всегда даёт `en`,
/// чтобы `develop` оставался рабочим, пока русские тексты не завершены;
/// затем `system` даёт `ru`, если `languageCode` первого языка системы `ru`.
Locale resolveAppLocale(
  AppLanguagePreference preference,
  List<Locale> systemLocales,
) {
  return switch (preference) {
    AppLanguagePreference.en => const Locale('en'),
    AppLanguagePreference.ru => const Locale('ru'),
    // TODO(add-desktop-localization, итерация 6): ru при первом языке ru.
    AppLanguagePreference.system => const Locale('en'),
  };
}
