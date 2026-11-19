import '../../../app/navigation/settings_page.dart';

/// Поиск «Find a setting» по страницам настроек.
///
/// Почему: пользователь ищет строку («token», «restart»), а не страницу;
/// заголовка страницы мало (design.md change `add-app-settings-shell`, D3).
/// Ключевые слова лежат не в коде, а в каталогах ARB
/// (`settingsSearchKeywords<Page>`, решение пользователя 2026-11-19; change
/// `add-app-general-page`, D15; заменяет D5 п. 8 `add-desktop-localization` в
/// редакции 2026-11-18): слова переводятся вместе с остальными текстами
/// страницы и проверяются `l10n:check`, а не живут вторым словарём в коде.
///
/// Для чего: чистая функция отбора страниц для навигации. Нечёткого поиска и
/// поиска по значениям настроек нет. Совпадение — по подстроке без учёта
/// регистра с заголовком страницы или с её ключевым словом.
///
/// Как использовать: `SettingsSearchIndex.search(visiblePages, query,
/// titlesOf: …, localizedKeywordsOf: …)`. Оба аргумента — функции страницы:
/// [titlesOf] даёт заголовок на языке интерфейса и английский (его знают из
/// документации и `codelab config`), [localizedKeywordsOf] — ключевые слова на
/// языке интерфейса и английские. Слова другого языка, кроме английского,
/// страницу не находят: на английском интерфейсе русские слова ничего не
/// дают. Слова разбирает вызывающий (`settingsPageKeywordsOf`: по запятой, trim,
/// без пустых). Пустой запрос возвращает все страницы. Ключевые слова новой
/// страницы добавляются сообщением `settingsSearchKeywords<Page>` в оба
/// каталога.
final class SettingsSearchIndex {
  const SettingsSearchIndex._();

  static List<SettingsPage> search(
    Iterable<SettingsPage> visible,
    String query, {
    required Iterable<String> Function(SettingsPage page) titlesOf,
    required Iterable<String> Function(SettingsPage page) localizedKeywordsOf,
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return visible.toList();
    }
    return [
      for (final page in visible)
        if ([
          ...titlesOf(page),
          ...localizedKeywordsOf(page),
        ].any((text) => text.toLowerCase().contains(needle)))
          page,
    ];
  }
}
