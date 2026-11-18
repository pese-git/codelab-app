/// Группа страниц настроек в навигации.
///
/// Группы и их порядок фиксированы `dart-agent-and-clients` §12.4.9; заголовок
/// группы показывается, только если в ней есть видимая страница (SETUP-17).
/// Текст заголовка зависит от языка и берётся функцией presentation
/// `settingsGroupTitleOf` (`add-desktop-localization`, D5, п. 8).
enum SettingsGroup { agent, app }

/// Страницы настроек codelab-app в фиксированном порядке §12.4.9.
///
/// Почему enum всех одиннадцати страниц, хотя в сборке видны не все: порядок,
/// группа, заголовок и ключ теста — свойства страницы, а не сборки; набор
/// видимых страниц отдельно задаёт [SettingsPages] composition root
/// (design.md change `add-app-settings-shell`, D3).
///
/// Для чего: единый список для навигации, `NavigationCubit` и хранения
/// последней страницы. Порядок значений — порядок показа: навигация идёт по
/// [values], а не по порядку регистрации.
///
/// Как использовать: новая страница добавляется в [SettingsPages.available]
/// composition root и в таблицу построителей `settingsPageBuilders`;
/// значение enum и порядок не меняются.
enum SettingsPage {
  connection(SettingsGroup.agent, 'connection'),
  providers(SettingsGroup.agent, 'providers'),
  mcpServers(SettingsGroup.agent, 'mcp-servers'),
  agentsAndModes(SettingsGroup.agent, 'agents-and-modes'),
  permissionsAndTools(SettingsGroup.agent, 'permissions-and-tools'),
  redaction(SettingsGroup.agent, 'redaction'),
  skillsAndExtensions(SettingsGroup.agent, 'skills-and-extensions'),
  codeAndWeb(SettingsGroup.agent, 'code-and-web'),
  general(SettingsGroup.app, 'general'),
  appearance(SettingsGroup.app, 'appearance'),
  keyboard(SettingsGroup.app, 'keyboard');

  const SettingsPage(this.group, this.slug);

  /// Группа навигации, под заголовком которой стоит страница.
  final SettingsGroup group;

  /// Имя в kebab-case: суффикс ключа теста и значение
  /// `codelab.settings.last_page`.
  final String slug;

  /// Ключ теста пункта навигации: `settings-nav-<slug>`.
  String get navKey => 'settings-nav-$slug';

  /// Страница по сохранённому [slug] или `null` для неизвестного значения.
  static SettingsPage? fromSlug(String? slug) {
    for (final page in values) {
      if (page.slug == slug) {
        return page;
      }
    }
    return null;
  }
}

/// Набор страниц настроек, видимых в этой сборке.
///
/// Почему: страница без содержимого скрывается, а не показывается пустой
/// (SETUP-17), и набор зависит от сборки, поэтому его задаёт composition root
/// (`lib/app/`), а не оболочка (design.md change `add-app-settings-shell`,
/// D3).
///
/// Для чего: единственный источник ответа «видна ли страница» для
/// `NavigationCubit` и экрана настроек.
///
/// Как использовать: `SettingsPages(available: {SettingsPage.connection})`;
/// каждая страница из [available] ДОЛЖНА иметь построитель в
/// `settingsPageBuilders` (проверяет тест).
final class SettingsPages {
  const SettingsPages({required this.available});

  /// Страницы, у которых в этой сборке есть тело; остальные скрыты.
  final Set<SettingsPage> available;

  /// Видимые страницы в порядке показа (порядок [SettingsPage.values]).
  List<SettingsPage> get visible => [
    for (final page in SettingsPage.values)
      if (available.contains(page)) page,
  ];

  bool get isEmpty => available.isEmpty;

  bool isVisible(SettingsPage page) => available.contains(page);
}
