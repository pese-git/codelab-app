/// Группа страниц настроек в навигации.
///
/// Группы и их порядок фиксированы `dart-agent-and-clients` §12.4.9; заголовок
/// группы показывается, только если в ней есть видимая страница (SETUP-17).
enum SettingsGroup {
  agent('Agent'),
  app('App');

  const SettingsGroup(this.title);

  /// Заголовок группы в навигации.
  final String title;
}

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
  connection(SettingsGroup.agent, 'Connection', 'connection'),
  providers(SettingsGroup.agent, 'Providers', 'providers'),
  mcpServers(SettingsGroup.agent, 'MCP servers', 'mcp-servers'),
  agentsAndModes(SettingsGroup.agent, 'Agents & modes', 'agents-and-modes'),
  permissionsAndTools(
    SettingsGroup.agent,
    'Permissions & tools',
    'permissions-and-tools',
  ),
  redaction(SettingsGroup.agent, 'Redaction', 'redaction'),
  skillsAndExtensions(
    SettingsGroup.agent,
    'Skills & extensions',
    'skills-and-extensions',
  ),
  codeAndWeb(SettingsGroup.agent, 'Code & web', 'code-and-web'),
  general(SettingsGroup.app, 'General', 'general'),
  appearance(SettingsGroup.app, 'Appearance', 'appearance'),
  keyboard(SettingsGroup.app, 'Keyboard', 'keyboard');

  const SettingsPage(this.group, this.title, this.slug);

  /// Группа навигации, под заголовком которой стоит страница.
  final SettingsGroup group;

  /// Заголовок пункта навигации и страницы.
  final String title;

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
