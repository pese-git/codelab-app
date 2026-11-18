import '../../../app/navigation/settings_page.dart';

/// Поиск «Find a setting» по страницам настроек.
///
/// Почему: пользователь ищет строку («token», «restart»), а не страницу;
/// заголовка страницы мало (design.md change `add-app-settings-shell`, D3).
///
/// Для чего: чистая функция отбора страниц для навигации. Нечёткого поиска и
/// поиска по значениям настроек нет.
///
/// Как использовать: `SettingsSearchIndex.search(visiblePages, query,
/// titleOf: …)`;
/// совпадение — по подстроке без учёта регистра с заголовком страницы или её
/// ключевыми словами. Пустой запрос возвращает все страницы. Ключевые слова
/// новой страницы добавляются в [keywords] вместе со страницей.
final class SettingsSearchIndex {
  const SettingsSearchIndex._();

  /// Статические ключевые слова строк страницы.
  static const keywords = <SettingsPage, List<String>>{
    SettingsPage.connection: [
      'profile',
      'stdio',
      'websocket',
      'token',
      'restart',
    ],
    SettingsPage.providers: [
      'provider',
      'model',
      'api key',
      'key storage',
      'base url',
    ],
    SettingsPage.mcpServers: ['mcp', 'server', 'tools', 'headers'],
    SettingsPage.agentsAndModes: [
      'mode',
      'permission',
      'bypass',
      'plan',
      'effort',
      'reasoning',
      'agent',
      'definition',
      'subagent',
    ],
    SettingsPage.skillsAndExtensions: [
      'skill',
      'agents.md',
      'context',
      'template',
      'prompt',
      'extension',
    ],
  };

  /// [titleOf] даёт заголовок страницы на текущем языке: поиск идёт по тому,
  /// что видит пользователь (`add-desktop-localization`, D5, п. 8); ключевые
  /// слова — английские и от языка не зависят.
  static List<SettingsPage> search(
    Iterable<SettingsPage> visible,
    String query, {
    required String Function(SettingsPage page) titleOf,
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return visible.toList();
    }
    return [
      for (final page in visible)
        if (titleOf(page).toLowerCase().contains(needle) ||
            (keywords[page] ?? const []).any(
              (word) => word.toLowerCase().contains(needle),
            ))
          page,
    ];
  }
}
