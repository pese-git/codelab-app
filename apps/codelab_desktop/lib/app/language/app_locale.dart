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
/// .instance.locales)`. `system` даёт `ru`, если `languageCode` первого языка
/// системы `ru`, иначе `en` (Q5 (а)); остальные языки списка и регион не
/// учитываются. Смена языка ОС при `system` применяется при следующем
/// старте app или при повторном выборе `System` (D2, spec «Язык интерфейса
/// app»).
Locale resolveAppLocale(
  AppLanguagePreference preference,
  List<Locale> systemLocales,
) {
  return switch (preference) {
    AppLanguagePreference.en => const Locale('en'),
    AppLanguagePreference.ru => const Locale('ru'),
    AppLanguagePreference.system =>
      systemLocales.isNotEmpty && systemLocales.first.languageCode == 'ru'
          ? const Locale('ru')
          : const Locale('en'),
  };
}
