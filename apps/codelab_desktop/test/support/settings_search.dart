import 'dart:convert';
import 'dart:io';

import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/application/settings_search_index.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_titles.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';

/// Суффикс идентификатора `settingsSearchKeywords<Page>` в каталогах ARB
/// (решение пользователя 2026-11-19, `add-app-general-page` D15): тот же, что у
/// `settingsPage<Page>Title`.
String settingsKeywordsSuffixOf(SettingsPage page) => switch (page) {
  SettingsPage.connection => 'Connection',
  SettingsPage.providers => 'Providers',
  SettingsPage.mcpServers => 'McpServers',
  SettingsPage.agentsAndModes => 'AgentsAndModes',
  SettingsPage.permissionsAndTools => 'PermissionsAndTools',
  SettingsPage.redaction => 'Redaction',
  SettingsPage.skillsAndExtensions => 'SkillsAndExtensions',
  SettingsPage.codeAndWeb => 'CodeAndWeb',
  SettingsPage.general => 'General',
  SettingsPage.appearance => 'Appearance',
  SettingsPage.keyboard => 'Keyboard',
  SettingsPage.legal => 'Legal',
};

/// Сообщение с ключевыми словами страницы в каталоге [locale] (`en`/`ru`) как
/// строка из ARB; `null` — сообщения нет.
///
/// Почему читаются файлы, а не геттеры: тесты не должны зависеть от
/// сгенерированного кода и проверяют сам каталог (`l10n:check` сверяет код с
/// ARB отдельно).
String? settingsKeywordsMessageOf(String locale, SettingsPage page) {
  final json =
      jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;
  return json['settingsSearchKeywords${settingsKeywordsSuffixOf(page)}']
      as String?;
}

/// Слова страницы из каталога [locale], разбитые по запятой и обрезанные;
/// пусто, если сообщения нет.
List<String> settingsKeywordsOf(String locale, SettingsPage page) => [
  for (final word in (settingsKeywordsMessageOf(locale, page) ?? '').split(','))
    word.trim(),
];

/// Поиск настроек так, как его ведёт оболочка: заголовок и слова на языке
/// интерфейса [locale] и английские (`en` по умолчанию — язык тестов).
///
/// Почему слова из ARB: ключевые слова страниц живут в каталогах (решение
/// пользователя 2026-11-19), а не в `SettingsSearchIndex`; при английском
/// интерфейсе русские слова страницу не находят.
List<SettingsPage> searchSettings(
  Iterable<SettingsPage> visible,
  String query, {
  String locale = 'en',
}) => SettingsSearchIndex.search(
  visible,
  query,
  titlesOf: (page) => [
    settingsPageTitleOf(AppLocalizationsEn(), page),
    if (locale == 'ru') settingsPageTitleOf(AppLocalizationsRu(), page),
  ],
  localizedKeywordsOf: (page) => [
    ...settingsKeywordsOf('en', page),
    if (locale == 'ru') ...settingsKeywordsOf('ru', page),
  ],
);
