import '../../../app/navigation/settings_page.dart';
import '../../../l10n/app_localizations.dart';

/// Заголовок страницы настроек на языке [l10n].
///
/// Почему функция presentation, а не поле enum: `SettingsPage` лежит в
/// `lib/app/navigation` без Flutter и без языка, а заголовок зависит от
/// каталога (`add-desktop-localization`, D5, п. 8). `slug` и `navKey` остаются
/// в enum — они не зависят от языка.
///
/// Как использовать: `settingsPageTitleOf(context.l10n, page)`; `switch`
/// исчерпывающий, поэтому новая страница не компилируется без заголовка.
String settingsPageTitleOf(
  AppLocalizations l10n,
  SettingsPage page,
) => switch (page) {
  SettingsPage.connection => l10n.settingsPageConnectionTitle,
  SettingsPage.providers => l10n.settingsPageProvidersTitle,
  SettingsPage.mcpServers => l10n.settingsPageMcpServersTitle,
  SettingsPage.agentsAndModes => l10n.settingsPageAgentsAndModesTitle,
  SettingsPage.permissionsAndTools => l10n.settingsPagePermissionsAndToolsTitle,
  SettingsPage.redaction => l10n.settingsPageRedactionTitle,
  SettingsPage.skillsAndExtensions => l10n.settingsPageSkillsAndExtensionsTitle,
  SettingsPage.codeAndWeb => l10n.settingsPageCodeAndWebTitle,
  SettingsPage.general => l10n.settingsPageGeneralTitle,
  SettingsPage.appearance => l10n.settingsPageAppearanceTitle,
  SettingsPage.keyboard => l10n.settingsPageKeyboardTitle,
};

/// Заголовок группы страниц настроек на языке [l10n] (см.
/// [settingsPageTitleOf]).
String settingsGroupTitleOf(AppLocalizations l10n, SettingsGroup group) =>
    switch (group) {
      SettingsGroup.agent => l10n.settingsGroupAgent,
      SettingsGroup.app => l10n.settingsGroupApp,
    };
