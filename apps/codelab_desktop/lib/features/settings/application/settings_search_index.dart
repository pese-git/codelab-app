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
/// titlesOf: …)`;
/// совпадение — по подстроке без учёта регистра с заголовком страницы или её
/// ключевыми словами. Пустой запрос возвращает все страницы. Ключевые слова
/// новой страницы добавляются в [keywords] вместе со страницей — на английском
/// и на русском (решение пользователя 2026-11-18, `add-desktop-localization`,
/// D5 п. 8).
final class SettingsSearchIndex {
  const SettingsSearchIndex._();

  /// Статические ключевые слова строк страницы: английские и русские сразу.
  ///
  /// Почему оба языка в одном списке: страница находится по слову на любом из
  /// двух языков, независимо от языка интерфейса, — как по заголовку (D5
  /// п. 8). Английские слова — термины из документации и `codelab config`,
  /// русские — по глоссарию `docs/architecture/l10n-glossary.md`
  /// («токен», «ключ API», «навык», «субагент»). Поиск идёт по подстроке без
  /// учёта регистра.
  static const keywords = <SettingsPage, List<String>>{
    SettingsPage.connection: [
      'profile',
      'stdio',
      'websocket',
      'token',
      'restart',
      'профиль',
      'токен',
      'перезапуск',
    ],
    SettingsPage.providers: [
      'provider',
      'model',
      'api key',
      'key storage',
      'base url',
      'провайдер',
      'модель',
      'ключ api',
      'хранилище ключей',
      'базовый url',
    ],
    SettingsPage.mcpServers: [
      'mcp',
      'server',
      'tools',
      'headers',
      'сервер',
      'инструменты',
      'заголовки',
    ],
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
      'режим',
      'разрешение',
      'план',
      'рассуждение',
      'определение',
      'субагент',
    ],
    SettingsPage.skillsAndExtensions: [
      'skill',
      'agents.md',
      'context',
      'template',
      'prompt',
      'extension',
      'навык',
      'контекст',
      'шаблон',
      'промпт',
      'расширение',
    ],
  };

  /// [titlesOf] даёт заголовки страницы, по которым ищем: на текущем языке
  /// (то, что видит пользователь) и английский (его знают из документации и
  /// `codelab config`) — `add-desktop-localization`, D5, п. 8. Ключевые слова
  /// ([keywords]) на двух языках и от языка интерфейса не зависят.
  static List<SettingsPage> search(
    Iterable<SettingsPage> visible,
    String query, {
    required Iterable<String> Function(SettingsPage page) titlesOf,
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return visible.toList();
    }
    return [
      for (final page in visible)
        if (titlesOf(
              page,
            ).any((title) => title.toLowerCase().contains(needle)) ||
            (keywords[page] ?? const []).any(
              (word) => word.toLowerCase().contains(needle),
            ))
          page,
    ];
  }
}
