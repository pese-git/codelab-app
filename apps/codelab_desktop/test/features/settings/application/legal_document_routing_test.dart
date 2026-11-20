// Выбор ресурса документа по языку и политика ссылок внутри документов
// (задача 2.3 change `add-app-legal-page`; spec app-settings «Страница
// «Legal»: документы на языке интерфейса» и «…ссылки внутри документов»;
// design.md D2, D8).
//
// Реализация — задача 2.4: `features/settings/application/
// legal_documents.dart` (`LegalTab`, `legalAssetOf`, `LegalLink`,
// `legalLinkOf`). Обе функции чистые: язык — код действующей локали app, а не
// системы; относительные ссылки работают и на GitHub, и в app.

import 'package:codelab_desktop/features/settings/application/legal_documents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegalTab', () {
    test('slug для ключей теста', () {
      expect(
        {for (final t in LegalTab.values) t: t.slug},
        {
          LegalTab.privacyPolicy: 'privacy-policy',
          LegalTab.termsOfUse: 'terms-of-use',
          LegalTab.license: 'license',
          LegalTab.thirdPartyNotices: 'third-party-notices',
        },
      );
    });

    test('logName для журнала', () {
      expect(
        {for (final t in LegalTab.values) t: t.logName},
        {
          LegalTab.privacyPolicy: 'privacy_policy',
          LegalTab.termsOfUse: 'terms_of_use',
          LegalTab.license: 'license',
          LegalTab.thirdPartyNotices: 'third_party_notices',
        },
      );
    });

    test('порядок вкладок по §12.7.7а', () {
      expect(LegalTab.values, [
        LegalTab.privacyPolicy,
        LegalTab.termsOfUse,
        LegalTab.license,
        LegalTab.thirdPartyNotices,
      ]);
    });
  });

  group('legalAssetOf', () {
    test('ru даёт русские редакции политики и условий', () {
      expect(
        legalAssetOf(LegalTab.privacyPolicy, 'ru'),
        'assets/legal/PRIVACY.ru.md',
      );
      expect(
        legalAssetOf(LegalTab.termsOfUse, 'ru'),
        'assets/legal/TERMS.ru.md',
      );
    });

    test('en даёт английские редакции', () {
      expect(
        legalAssetOf(LegalTab.privacyPolicy, 'en'),
        'assets/legal/PRIVACY.md',
      );
      expect(legalAssetOf(LegalTab.termsOfUse, 'en'), 'assets/legal/TERMS.md');
    });

    test('другие языки и пустой код — английские', () {
      for (final code in ['de', 'fr', 'zh', '']) {
        expect(
          legalAssetOf(LegalTab.privacyPolicy, code),
          'assets/legal/PRIVACY.md',
          reason: 'код «$code»',
        );
        expect(
          legalAssetOf(LegalTab.termsOfUse, code),
          'assets/legal/TERMS.md',
          reason: 'код «$code»',
        );
      }
    });

    test('LICENSE и реестр от языка не зависят', () {
      for (final code in ['en', 'ru', 'de', '']) {
        expect(
          legalAssetOf(LegalTab.license, code),
          'assets/legal/LICENSE',
          reason: 'код «$code»',
        );
        expect(
          legalAssetOf(LegalTab.thirdPartyNotices, code),
          'assets/legal/THIRD_PARTY_NOTICES.md',
          reason: 'код «$code»',
        );
      }
    });
  });

  group('legalLinkOf', () {
    Matcher tab(LegalTab expected) =>
        isA<LegalLinkTab>().having((l) => l.tab, 'tab', expected);

    test('имя файла документа — переход на вкладку', () {
      expect(legalLinkOf(Uri.parse('TERMS.md')), tab(LegalTab.termsOfUse));
      expect(legalLinkOf(Uri.parse('PRIVACY.md')), tab(LegalTab.privacyPolicy));
      expect(legalLinkOf(Uri.parse('TERMS.ru.md')), tab(LegalTab.termsOfUse));
      expect(legalLinkOf(Uri.parse('LICENSE')), tab(LegalTab.license));
      expect(
        legalLinkOf(Uri.parse('THIRD_PARTY_NOTICES.md')),
        tab(LegalTab.thirdPartyNotices),
      );
    });

    test('префикс ./ и якорь отбрасываются', () {
      expect(legalLinkOf(Uri.parse('./LICENSE#x')), tab(LegalTab.license));
      expect(
        legalLinkOf(Uri.parse('./PRIVACY.md#network-requests')),
        tab(LegalTab.privacyPolicy),
      );
    });

    test('русская редакция — вкладка политики, язык не меняется', () {
      expect(
        legalLinkOf(Uri.parse('PRIVACY.ru.md')),
        tab(LegalTab.privacyPolicy),
      );
    });

    test('https — внешняя ссылка с тем же адресом', () {
      final uri = Uri.parse('https://example.com/privacy');

      expect(
        legalLinkOf(uri),
        isA<LegalLinkExternal>().having((l) => l.uri, 'uri', uri),
      );
    });

    test('остальное неактивно', () {
      for (final raw in [
        'http://example.com',
        'mailto:a@example.com',
        'file:///etc/passwd',
        'SECURITY.md',
        'CHANGELOG.md',
        '../PRIVACY.md',
        'docs/PRIVACY.md',
        '/PRIVACY.md',
        '#section',
      ]) {
        expect(legalLinkOf(Uri.parse(raw)), isA<LegalLinkNone>(), reason: raw);
      }
    });
  });
}
