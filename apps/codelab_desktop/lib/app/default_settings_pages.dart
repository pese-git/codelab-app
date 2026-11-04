import 'navigation/settings_page.dart';

/// Страницы настроек, видимые в рабочей сборке.
///
/// Почему: набор зависит от сборки и поэтому задаётся composition root, а не
/// оболочкой (design.md change `add-app-settings-shell`, D3).
///
/// Для чего: источник по умолчанию для `createCodeLabRootScope`; тесты
/// подставляют свой набор через `settingsPages:`.
///
/// Как использовать: в итерации 1 набор пуст — страницы появятся вместе со
/// своими телами («Connection» — итерация 2, Migration Plan п. 2). Пока набор
/// пуст, «Settings» и Cmd/Ctrl+, открывают прежний `ConnectionSetupDialog`.
/// Страница из набора ДОЛЖНА иметь построитель в `settingsPageBuilders`.
const defaultSettingsPages = SettingsPages(available: {});
