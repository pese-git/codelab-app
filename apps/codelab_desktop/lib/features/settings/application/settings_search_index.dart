import '../../../app/navigation/settings_page.dart';

/// Поиск «Find a setting» по страницам настроек.
///
/// Почему: пользователь ищет строку («token», «restart»), а не страницу;
/// заголовка страницы мало (design.md change `add-app-settings-shell`, D3).
///
/// Для чего: чистая функция отбора страниц для навигации. Нечёткого поиска и
/// поиска по значениям настроек нет.
///
/// Как использовать: `SettingsSearchIndex.search(visiblePages, query)`;
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
      'connect on start',
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
  };

  static List<SettingsPage> search(
    Iterable<SettingsPage> visible,
    String query,
  ) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return visible.toList();
    }
    return [
      for (final page in visible)
        if (page.title.toLowerCase().contains(needle) ||
            (keywords[page] ?? const []).any(
              (word) => word.toLowerCase().contains(needle),
            ))
          page,
    ];
  }
}
