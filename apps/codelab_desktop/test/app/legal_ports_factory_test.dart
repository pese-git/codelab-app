// Сборка реестра лицензий для вкладки «Third-party notices» (задача 2.6 change
// `add-app-legal-page`; spec app-settings «Страница «Legal»: вкладка
// «Third-party notices»», сценарии «Пакет из записи с двумя именами», «Сбой
// реестра лицензий»; design.md D5, D10).
//
// Реализация — задача 2.7: `lib/app/legal_ports_factory.dart`
// (`buildLegalPorts`, `collectPackageLicenses`) — единственное место
// `rootBundle` и `LicenseRegistry` страницы. Сборщик принимает поток, а не
// читает `LicenseRegistry` сам: тест подставляет свой.

import 'dart:async';

import 'package:codelab_desktop/app/legal_ports_factory.dart';
import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('collectPackageLicenses', () {
    test('запись с двумя пакетами относится к каждому', () async {
      final result = await collectPackageLicenses(
        Stream.fromIterable([
          const LicenseEntryWithLineBreaks(['alpha', 'beta'], 'shared text'),
        ]),
      );

      expect(result.failed, isFalse);
      expect([for (final p in result.packages) p.name], ['alpha', 'beta']);
      expect(result.packages[0].licenses, ['shared text']);
      expect(result.packages[1].licenses, ['shared text']);
    });

    test('несколько записей одного пакета складываются по порядку', () async {
      final result = await collectPackageLicenses(
        Stream.fromIterable([
          const LicenseEntryWithLineBreaks(['alpha'], 'first'),
          const LicenseEntryWithLineBreaks(['alpha'], 'second'),
        ]),
      );

      expect(result.packages, hasLength(1));
      expect(result.packages.single.licenses, ['first', 'second']);
    });

    test('пакеты идут по имени', () async {
      final result = await collectPackageLicenses(
        Stream.fromIterable([
          const LicenseEntryWithLineBreaks(['zeta'], 'z'),
          const LicenseEntryWithLineBreaks(['alpha'], 'a'),
          const LicenseEntryWithLineBreaks(['mid'], 'm'),
        ]),
      );

      expect(
        [for (final p in result.packages) p.name],
        ['alpha', 'mid', 'zeta'],
      );
    });

    test('пустой реестр — пустой список без сбоя', () async {
      final result = await collectPackageLicenses(
        const Stream<LicenseEntry>.empty(),
      );

      expect(result.packages, isEmpty);
      expect(result.failed, isFalse);
    });

    test(
      'ошибка потока даёт собранное и failed: true, без исключения',
      () async {
        Stream<LicenseEntry> broken() async* {
          yield const LicenseEntryWithLineBreaks(['alpha'], 'ok');
          throw StateError('registry broken');
        }

        final result = await collectPackageLicenses(broken());

        expect(result.failed, isTrue);
        expect([for (final p in result.packages) p.name], ['alpha']);
      },
    );
  });
}
