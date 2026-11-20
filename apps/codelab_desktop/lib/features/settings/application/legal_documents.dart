/// Вкладка страницы «Legal» (design.md change `add-app-legal-page`, D1, D2).
///
/// Почему enum: набор и порядок вкладок фиксирует §12.7.7а; страница и Cubit
/// адресуют вкладку значением, а не индексом.
///
/// Для чего: [slug] — часть ключей теста и идентификаторов документов
/// (`settings-legal-tab-<slug>`), [logName] — значение поля `tab` в событиях
/// журнала (D11, `snake_case`).
enum LegalTab {
  privacyPolicy('privacy-policy', 'privacy_policy'),
  termsOfUse('terms-of-use', 'terms_of_use'),
  license('license', 'license'),
  thirdPartyNotices('third-party-notices', 'third_party_notices');

  const LegalTab(this.slug, this.logName);

  final String slug;
  final String logName;
}

/// Путь ресурса документа вкладки [tab] для языка интерфейса [languageCode]
/// (D2).
///
/// Почему: документ не должен быть на другом языке, чем подписи вокруг него.
/// Язык — код действующей локали app, а не системы.
///
/// Как использовать: `ru` даёт `*.ru.md` для политики и условий, любой другой
/// код (в том числе пустой) — английские `PRIVACY.md` и `TERMS.md`. `LICENSE`
/// и `THIRD_PARTY_NOTICES.md` от языка не зависят. Функция чистая.
String legalAssetOf(LegalTab tab, String languageCode) {
  final ru = languageCode == 'ru';
  return switch (tab) {
    LegalTab.privacyPolicy =>
      ru ? 'assets/legal/PRIVACY.ru.md' : 'assets/legal/PRIVACY.md',
    LegalTab.termsOfUse =>
      ru ? 'assets/legal/TERMS.ru.md' : 'assets/legal/TERMS.md',
    LegalTab.license => 'assets/legal/LICENSE',
    LegalTab.thirdPartyNotices => 'assets/legal/THIRD_PARTY_NOTICES.md',
  };
}

/// Что делать со ссылкой внутри документа (D8).
sealed class LegalLink {
  const LegalLink();
}

/// Относительная ссылка на файл документа: переключает вкладку.
final class LegalLinkTab extends LegalLink {
  const LegalLinkTab(this.tab);

  final LegalTab tab;
}

/// Ссылка `https`: открывается через `ExternalLinkOpener`.
final class LegalLinkExternal extends LegalLink {
  const LegalLinkExternal(this.uri);

  final Uri uri;
}

/// Всё остальное: ссылка неактивна.
final class LegalLinkNone extends LegalLink {
  const LegalLinkNone();
}

const _documentFiles = <String, LegalTab>{
  'PRIVACY.md': LegalTab.privacyPolicy,
  'PRIVACY.ru.md': LegalTab.privacyPolicy,
  'TERMS.md': LegalTab.termsOfUse,
  'TERMS.ru.md': LegalTab.termsOfUse,
  'LICENSE': LegalTab.license,
  'THIRD_PARTY_NOTICES.md': LegalTab.thirdPartyNotices,
};

/// Политика ссылок документов страницы «Legal» (D8).
///
/// Почему относительные ссылки: документы читают и на GitHub, где
/// `TERMS.md` → `LICENSE` работает как обычная ссылка; в app та же ссылка
/// переключает вкладку. Язык показа остаётся языком интерфейса, даже если
/// ссылка указывает на файл другого языка.
///
/// Как использовать: `canOpenLink` разметки — `legalLinkOf(uri)` не
/// [LegalLinkNone]. Имя файла берётся после `./` и без якоря; пути с
/// каталогами (`docs/…`, `../…`, `/…`), `http:`, `mailto:`, `file:` и файлы
/// вне набора неактивны.
LegalLink legalLinkOf(Uri uri) {
  if (uri.scheme == 'https' && uri.host.isNotEmpty) {
    return LegalLinkExternal(uri);
  }
  if (uri.hasScheme || uri.hasAuthority) {
    return const LegalLinkNone();
  }
  var path = uri.path;
  if (path.startsWith('./')) {
    path = path.substring(2);
  }
  final tab = _documentFiles[path];
  return tab == null ? const LegalLinkNone() : LegalLinkTab(tab);
}
