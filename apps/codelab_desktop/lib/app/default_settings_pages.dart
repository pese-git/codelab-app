import 'navigation/settings_page.dart';

/// Страницы настроек, видимые в рабочей сборке.
///
/// Почему: набор зависит от сборки и поэтому задаётся composition root, а не
/// оболочкой (design.md change `add-app-settings-shell`, D3).
///
/// Для чего: источник по умолчанию для `createCodeLabRootScope`; тесты
/// подставляют свой набор через `settingsPages:`.
///
/// Как использовать: change `add-app-settings-shell` добавил «Connection»,
/// change `add-provider-setup-ui` — «Providers» (итерация 2) и «MCP servers»
/// (итерация 5; Migration Plan, п. 2; SETUP-17), change
/// `add-settings-agents-modes` — «Agents & modes» (итерация 1, D9), change
/// `add-app-skills-page` — «Skills & extensions» (итерация 4, только чтение),
/// `add-desktop-localization` — «General» с выбором языка (итерация 1, D2),
/// `add-app-appearance-page` — «Appearance» (итерация 5, D14),
/// `add-app-keyboard-page` — «Keyboard» (итерация 3, только чтение; у неё нет
/// ключей конфигурации, её содержимое — каталог сочетаний сборки, поэтому
/// SETUP-17 её не скрывает, D7), `add-app-legal-page` — «Legal» (всегда: её
/// содержимое задают ресурсы сборки, а не конфигурация, D1); следующие
/// страницы появятся вместе со своими телами.
/// Страница из набора ДОЛЖНА иметь построитель в `settingsPageBuilders`.
const defaultSettingsPages = SettingsPages(
  available: {
    SettingsPage.connection,
    SettingsPage.providers,
    SettingsPage.mcpServers,
    SettingsPage.agentsAndModes,
    SettingsPage.skillsAndExtensions,
    SettingsPage.general,
    SettingsPage.appearance,
    SettingsPage.keyboard,
    SettingsPage.legal,
  },
);
