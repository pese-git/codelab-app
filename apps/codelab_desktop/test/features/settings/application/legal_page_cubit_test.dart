// `LegalPageCubit` (задача 2.5 change `add-app-legal-page`; spec app-settings
// «Страница «Legal»…»; design.md D7, D8, D10, D11).
//
// Реализация — задача 2.7: `features/settings/application/legal_ports.dart`,
// `legal_page_state.dart`, `legal_page_cubit.dart`. Порты — двойники:
// `LegalPorts(readAsset, packageLicenses, externalLinks, logger)`; ресурс
// читается по пути (`legalAssetOf`), реестр лицензий — одним вызовом.
//
// Состояние адресуется ресурсом, а не порядком запросов (D7): ответ порта для
// прежнего языка заполняет кэш, но не попадает на экран. Запрос поиска в
// журнал не пишется никогда (D11).

import 'dart:async';

import 'package:codelab_desktop/core/platform/external_link_opener.dart';
import 'package:codelab_desktop/features/settings/application/legal_documents.dart';
import 'package:codelab_desktop/features/settings/application/legal_page_cubit.dart';
import 'package:codelab_desktop/features/settings/application/legal_page_state.dart';
import 'package:codelab_desktop/features/settings/application/legal_ports.dart';
import 'package:codelab_desktop/features/settings/application/package_license_search.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_logger.dart';

const _privacyEn = 'assets/legal/PRIVACY.md';
const _privacyRu = 'assets/legal/PRIVACY.ru.md';
const _termsRu = 'assets/legal/TERMS.ru.md';

/// Секрет запроса: не должен встретиться в журнале (D11).
const _marker = 'marker-query-7f3a';

final class _Opener implements ExternalLinkOpener {
  final opened = <Uri>[];
  ExternalLinkOutcome outcome = ExternalLinkOutcome.opened;

  @override
  Future<ExternalLinkOutcome> open(Uri uri) async {
    opened.add(uri);
    return outcome;
  }
}

void main() {
  late RecordingLogger logger;
  late _Opener opener;
  late List<String> reads;
  late int collections;

  /// Ответ порта чтения: по умолчанию — текст «text of <путь>»; тест
  /// подменяет для ручного управления порядком ответов.
  late Future<String> Function(String asset) readAsset;
  late Future<CollectedLicenses> Function() packageLicenses;

  LegalPageCubit make() {
    final cubit = LegalPageCubit(
      ports: LegalPorts(
        readAsset: (asset) {
          reads.add(asset);
          return readAsset(asset);
        },
        packageLicenses: () {
          collections++;
          return packageLicenses();
        },
        externalLinks: opener,
        logger: logger,
      ),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Iterable<Map<String, Object?>> events(String name) =>
      logger.entries.where((e) => e['event'] == name);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    logger = RecordingLogger();
    opener = _Opener();
    reads = [];
    collections = 0;
    readAsset = (asset) async => 'text of $asset';
    packageLicenses = () async => (
      packages: [
        const PackageLicense(name: 'flutter', licenses: ['BSD']),
        const PackageLicense(name: 'http', licenses: ['BSD']),
      ],
      failed: false,
    );
  });

  group('open', () {
    test('null и en: «Privacy policy», читается только PRIVACY.md', () async {
      final cubit = make();

      await cubit.open(null, 'en');

      expect(cubit.state.tab, LegalTab.privacyPolicy);
      expect(cubit.state.shownAsset, 'assets/legal/PRIVACY.md');
      expect(reads, ['assets/legal/PRIVACY.md']);
      expect(
        cubit.state.documents['assets/legal/PRIVACY.md'],
        const DocumentLoaded('text of assets/legal/PRIVACY.md'),
      );
    });

    test('термы на ru читают TERMS.ru.md', () async {
      final cubit = make();

      await cubit.open(LegalTab.termsOfUse, 'ru');

      expect(cubit.state.tab, LegalTab.termsOfUse);
      expect(reads, [_termsRu]);
    });

    test('до ответа порта документ — Loading', () async {
      final gate = Completer<String>();
      readAsset = (_) => gate.future;
      final cubit = make();

      unawaited(cubit.open(null, 'en'));
      await settle();

      expect(
        cubit.state.documents[cubit.state.shownAsset],
        isA<DocumentLoading>(),
      );
      gate.complete('x');
      await settle();
      expect(
        cubit.state.documents[cubit.state.shownAsset],
        const DocumentLoaded('x'),
      );
    });

    test('реестр лицензий не запрашивается, пока вкладка не открыта', () async {
      final cubit = make();

      await cubit.open(null, 'en');

      expect(cubit.state.packages, isA<PackagesNotRequested>());
      expect(collections, 0);
    });
  });

  group('документ читается один раз на ресурс', () {
    test('возврат на вкладку не читает ресурс повторно', () async {
      final cubit = make();
      await cubit.open(null, 'en');

      await cubit.selectTab(LegalTab.termsOfUse);
      await cubit.selectTab(LegalTab.privacyPolicy);
      await cubit.selectTab(LegalTab.termsOfUse);

      expect(reads, ['assets/legal/PRIVACY.md', 'assets/legal/TERMS.md']);
    });
  });

  group('setLanguage', () {
    test('сохраняет вкладку и запрос, показывает *.ru.md', () async {
      final cubit = make();
      await cubit.open(LegalTab.thirdPartyNotices, 'en');
      cubit.setQuery('flut');
      await cubit.selectTab(LegalTab.privacyPolicy);

      await cubit.setLanguage('ru');

      expect(cubit.state.tab, LegalTab.privacyPolicy);
      expect(cubit.state.query, 'flut');
      expect(cubit.state.languageCode, 'ru');
      expect(cubit.state.shownAsset, _privacyRu);
      expect(
        cubit.state.documents[_privacyRu],
        const DocumentLoaded('text of $_privacyRu'),
      );
    });

    test('тот же язык ничего не перечитывает', () async {
      final cubit = make();
      await cubit.open(null, 'ru');

      await cubit.setLanguage('ru');

      expect(reads, [_privacyRu]);
    });

    test('поздний ответ для en после setLanguage(ru) не меняет показанный '
        'документ', () async {
      final lateEn = Completer<String>();
      readAsset = (asset) =>
          asset == _privacyEn ? lateEn.future : Future.value('text of $asset');
      final cubit = make();

      unawaited(cubit.open(null, 'en'));
      await settle();
      await cubit.setLanguage('ru');
      lateEn.complete('late en text');
      await settle();

      expect(cubit.state.shownAsset, _privacyRu);
      expect(
        cubit.state.documents[cubit.state.shownAsset],
        const DocumentLoaded('text of $_privacyRu'),
      );
    });
  });

  group('close', () {
    test(
      'результат после close() не выпускает состояний и не бросает',
      () async {
        final gate = Completer<String>();
        readAsset = (_) => gate.future;
        final cubit = LegalPageCubit(
          ports: LegalPorts(
            readAsset: (asset) => readAsset(asset),
            packageLicenses: () async =>
                (packages: const <PackageLicense>[], failed: false),
            externalLinks: opener,
            logger: logger,
          ),
        );
        unawaited(cubit.open(null, 'en'));
        await settle();
        final emitted = <LegalPageState>[];
        final sub = cubit.stream.listen(emitted.add);

        await cubit.close();
        gate.complete('late');
        await settle();
        await sub.cancel();

        expect(emitted, isEmpty);
        expect(events('legal.document_load_failed'), isEmpty);
      },
    );
  });

  group('сбой чтения', () {
    test('даёт Failed и событие с tab и error_type, без пути', () async {
      readAsset = (_) => Future.error(StateError('/secret/path/PRIVACY.md'));
      final cubit = make();

      await cubit.open(null, 'en');

      expect(
        cubit.state.documents[cubit.state.shownAsset],
        isA<DocumentFailed>(),
      );
      final failed = events('legal.document_load_failed').single;
      expect(failed['tab'], 'privacy_policy');
      expect(failed['error_type'], 'StateError');
      expect(failed['level'], 'warning');
      expect(failed.toString(), isNot(contains('/secret/path')));
      expect(failed.toString(), isNot(contains('PRIVACY.md')));
    });

    test('сбой не прячет вкладки: можно открыть другую', () async {
      readAsset = (asset) => asset == _privacyEn
          ? Future.error(StateError('x'))
          : Future.value('ok');
      final cubit = make();
      await cubit.open(null, 'en');

      await cubit.selectTab(LegalTab.termsOfUse);

      expect(
        cubit.state.documents[cubit.state.shownAsset],
        const DocumentLoaded('ok'),
      );
    });
  });

  group('реестр лицензий', () {
    test(
      'собирается один раз, при первой вкладке «Third-party notices»',
      () async {
        final cubit = make();
        await cubit.open(null, 'en');

        await cubit.selectTab(LegalTab.thirdPartyNotices);
        await cubit.selectTab(LegalTab.license);
        await cubit.selectTab(LegalTab.thirdPartyNotices);

        expect(collections, 1);
        final packages = cubit.state.packages;
        expect(packages, isA<PackagesCollected>());
        expect((packages as PackagesCollected).list, hasLength(2));
        expect(packages.failed, isFalse);
      },
    );

    test(
      'событие legal.licenses_collected: packages и failed, один раз',
      () async {
        packageLicenses = () async => (
          packages: [
            const PackageLicense(name: 'a', licenses: ['x']),
          ],
          failed: true,
        );
        final cubit = make();

        await cubit.open(LegalTab.thirdPartyNotices, 'en');
        await cubit.selectTab(LegalTab.license);
        await cubit.selectTab(LegalTab.thirdPartyNotices);

        final collected = events('legal.licenses_collected').single;
        expect(collected['packages'], 1);
        expect(collected['failed'], isTrue);
        expect(collected['level'], 'info');
      },
    );

    test(
      'пока реестр собирается — Collecting, затем поиск пересчитывается',
      () async {
        final gate = Completer<CollectedLicenses>();
        packageLicenses = () => gate.future;
        final cubit = make();
        await cubit.open(LegalTab.thirdPartyNotices, 'en');

        cubit.setQuery('flut');
        expect(cubit.state.packages, isA<PackagesCollecting>());
        expect(cubit.state.query, 'flut');

        gate.complete((
          packages: [
            const PackageLicense(name: 'flutter', licenses: ['BSD']),
            const PackageLicense(name: 'http', licenses: ['BSD']),
          ],
          failed: false,
        ));
        await settle();

        expect(cubit.state.search.total, 2);
        expect(
          [for (final h in cubit.state.search.hits) h.package.name],
          ['flutter'],
        );
      },
    );
  });

  group('поиск', () {
    test('setQuery и clearQuery пересчитывают search', () async {
      final cubit = make();
      await cubit.open(LegalTab.thirdPartyNotices, 'en');

      cubit.setQuery('HTTP');
      expect(cubit.state.query, 'HTTP');
      expect(cubit.state.search.hits, hasLength(1));
      expect(cubit.state.search.total, 2);

      cubit.clearQuery();
      expect(cubit.state.query, isEmpty);
      expect(cubit.state.search.hits, hasLength(2));
    });

    test('запрос не пишется в журнал: ни setQuery, ни clearQuery', () async {
      final cubit = make();
      await cubit.open(LegalTab.thirdPartyNotices, 'en');
      final before = logger.entries.length;

      cubit.setQuery(_marker);
      cubit.setQuery('${_marker}x');
      cubit.clearQuery();

      expect(logger.entries.length, before);
      expect(logger.entries.toString(), isNot(contains(_marker)));
    });
  });

  group('selectTab и журнал', () {
    test('legal.tab_selected с tab и source, уровень debug', () async {
      final cubit = make();
      await cubit.open(null, 'en');

      await cubit.selectTab(LegalTab.termsOfUse);

      final selected = events('legal.tab_selected').last;
      expect(selected['tab'], 'terms_of_use');
      expect(selected['source'], 'tab');
      expect(selected['level'], 'debug');
    });

    test('повторный выбор той же вкладки не меняет состояние', () async {
      final cubit = make();
      await cubit.open(null, 'en');
      final emitted = <LegalPageState>[];
      final sub = cubit.stream.listen(emitted.add);

      await cubit.selectTab(LegalTab.privacyPolicy);
      await settle();
      await sub.cancel();

      expect(emitted, isEmpty);
    });
  });

  group('onDocumentLink', () {
    test('LICENSE выбирает вкладку «License», source link', () async {
      final cubit = make();
      await cubit.open(LegalTab.termsOfUse, 'en');

      await cubit.onDocumentLink(Uri.parse('LICENSE'));

      expect(cubit.state.tab, LegalTab.license);
      expect(opener.opened, isEmpty);
      final selected = events('legal.tab_selected').last;
      expect(selected['source'], 'link');
      final link = events('legal.link_opened').single;
      expect(link['target'], 'tab');
    });

    test('https вызывает порт открытия ссылок', () async {
      final cubit = make();
      await cubit.open(null, 'en');

      await cubit.onDocumentLink(Uri.parse('https://example.com/p'));

      expect(opener.opened, [Uri.parse('https://example.com/p')]);
      expect(cubit.state.note, isNull);
      final link = events('legal.link_opened').single;
      expect(link['target'], 'external');
      expect(link['outcome'], 'opened');
      expect(link.toString(), isNot(contains('example.com')));
    });

    test(
      'исход failed даёт заметку linkFailed, без адреса в журнале',
      () async {
        opener.outcome = ExternalLinkOutcome.failed;
        final cubit = make();
        await cubit.open(null, 'en');

        await cubit.onDocumentLink(Uri.parse('https://example.com/p'));

        expect(cubit.state.note, LegalNote.linkFailed);
        expect(logger.entries.toString(), isNot(contains('example.com')));
      },
    );

    test('исход rejectedScheme тоже даёт linkFailed', () async {
      opener.outcome = ExternalLinkOutcome.rejectedScheme;
      final cubit = make();
      await cubit.open(null, 'en');

      await cubit.onDocumentLink(Uri.parse('https://example.com/p'));

      expect(cubit.state.note, LegalNote.linkFailed);
    });

    test('неактивная ссылка ничего не делает', () async {
      final cubit = make();
      await cubit.open(null, 'en');
      final before = cubit.state;

      await cubit.onDocumentLink(Uri.parse('mailto:a@example.com'));

      expect(cubit.state, before);
      expect(opener.opened, isEmpty);
    });

    test('смена вкладки сбрасывает заметку', () async {
      opener.outcome = ExternalLinkOutcome.failed;
      final cubit = make();
      await cubit.open(null, 'en');
      await cubit.onDocumentLink(Uri.parse('https://example.com/p'));

      await cubit.selectTab(LegalTab.termsOfUse);

      expect(cubit.state.note, isNull);
    });
  });
}
