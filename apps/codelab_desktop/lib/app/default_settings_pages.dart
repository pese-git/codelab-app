import 'navigation/settings_page.dart';

/// Страницы настроек, видимые в рабочей сборке.
///
/// Почему: набор зависит от сборки и поэтому задаётся composition root, а не
/// оболочкой (design.md change `add-app-settings-shell`, D3).
///
/// Для чего: источник по умолчанию для `createCodeLabRootScope`; тесты
/// подставляют свой набор через `settingsPages:`.
///
/// Как использовать: итерация 2 добавила «Connection» (Migration Plan, п. 3);
/// следующие страницы появятся вместе со своими телами. Страница из набора
/// ДОЛЖНА иметь построитель в `settingsPageBuilders`.
const defaultSettingsPages = SettingsPages(
  available: {SettingsPage.connection},
);
