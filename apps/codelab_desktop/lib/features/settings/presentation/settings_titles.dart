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

/// Ключевые слова поиска страницы на языке [l10n]: сообщение
/// `settingsSearchKeywords<Page>`, разбитое по запятой, с обрезанными
/// пробелами и без пустых слов (`add-app-general-page`, D15; D5 п. 8
/// `add-desktop-localization`).
///
/// Почему отдельная функция: `gen-l10n` даёт типизированные геттеры без
/// динамического доступа по имени, поэтому соответствие страницы и сообщения
/// — исчерпывающий `switch`. Страницы, которых нет в сборке (у них нет
/// сообщения), слов не имеют: сообщение появляется вместе со страницей.
///
/// Как использовать: оболочка настроек передаёт слова языка интерфейса и
/// английские (`AppLocalizationsEn`) в `SettingsSearchIndex.search`.
List<String> settingsPageKeywordsOf(AppLocalizations l10n, SettingsPage page) {
  final message = switch (page) {
    SettingsPage.connection => l10n.settingsSearchKeywordsConnection,
    SettingsPage.providers => l10n.settingsSearchKeywordsProviders,
    SettingsPage.mcpServers => l10n.settingsSearchKeywordsMcpServers,
    SettingsPage.agentsAndModes => l10n.settingsSearchKeywordsAgentsAndModes,
    SettingsPage.skillsAndExtensions =>
      l10n.settingsSearchKeywordsSkillsAndExtensions,
    SettingsPage.general => l10n.settingsSearchKeywordsGeneral,
    SettingsPage.appearance => l10n.settingsSearchKeywordsAppearance,
    SettingsPage.keyboard => l10n.settingsSearchKeywordsKeyboard,
    SettingsPage.permissionsAndTools ||
    SettingsPage.redaction ||
    SettingsPage.codeAndWeb => '',
  };
  return [
    for (final word in message.split(','))
      if (word.trim().isNotEmpty) word.trim(),
  ];
}

/// Заголовок группы страниц настроек на языке [l10n] (см.
/// [settingsPageTitleOf]).
String settingsGroupTitleOf(AppLocalizations l10n, SettingsGroup group) =>
    switch (group) {
      SettingsGroup.agent => l10n.settingsGroupAgent,
      SettingsGroup.app => l10n.settingsGroupApp,
    };
