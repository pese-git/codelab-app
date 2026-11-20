// Лицензия и сторонние уведомления в сборке app (задача 5.3 change
// `add-app-general-page`; spec licensing-and-attribution «Лицензия и сторонние
// уведомления в сборке app», сценарии «Копия разошлась с корнем» и «Строка
// лицензии из ресурса»; design.md D13).
//
// Реализация — задача 5.4 change `add-app-general-page`.
//
// Задача 1.3 change `add-app-legal-page` (design.md D4; spec
// licensing-and-attribution, сценарии «Русская редакция разошлась с корнем»,
// «Ресурс не объявлен»): таблица `pairs` расширена до шести файлов — к
// `LICENSE` и реестру добавлены четыре правовых документа; тест проверяет
// объявление каждого ресурса в `pubspec.yaml` и что каждый файл каталога
// объявлен. Реализация — задача 1.4.
//
// Flutter не принимает ресурсы вне каталога пакета, поэтому app держит копии
// корневых файлов; тест не даёт им разойтись (образец — `.fvmrc` и
// `.fvm/fvm_config.json`). Сообщение называет файл.

import 'dart:io';

import 'package:codelab_desktop/features/settings/application/license_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pairs = {
    'LICENSE': '../../LICENSE',
    'THIRD_PARTY_NOTICES.md': '../../THIRD_PARTY_NOTICES.md',
    'PRIVACY.md': '../../PRIVACY.md',
    'PRIVACY.ru.md': '../../PRIVACY.ru.md',
    'TERMS.md': '../../TERMS.md',
    'TERMS.ru.md': '../../TERMS.ru.md',
  };

  group('копии корневых файлов', () {
    pairs.forEach((name, root) {
      test('assets/legal/$name побайтно равен корневому $name', () {
        final copy = File('assets/legal/$name');
        expect(
          copy.existsSync(),
          isTrue,
          reason: 'нет ресурса apps/codelab_desktop/assets/legal/$name',
        );

        expect(
          copy.readAsBytesSync(),
          File(root).readAsBytesSync(),
          reason:
              'apps/codelab_desktop/assets/legal/$name разошёлся с корневым '
              '$name: скопируйте корневой файл',
        );
      });
    });

    pairs.forEach((name, _) {
      test('pubspec.yaml объявляет ресурс assets/legal/$name', () {
        final pubspec = File('pubspec.yaml').readAsStringSync();

        expect(
          pubspec,
          contains('assets/legal/$name'),
          reason: 'pubspec.yaml не объявляет ресурс assets/legal/$name',
        );
      });
    });

    test('каждый файл каталога assets/legal/ объявлен в pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final files = Directory('assets/legal')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();

      expect(files, isNotEmpty);
      for (final name in files) {
        expect(
          pubspec,
          contains('assets/legal/$name'),
          reason:
              'assets/legal/$name лежит в каталоге, но не объявлен в '
              'pubspec.yaml: он молча пропадёт из сборки',
        );
      }
    });
  });

  // Диалог «Third-party notices» показывает только раздел `## Записи` (D13,
  // решение пользователя 2026-11-19): без этого заголовка реестр в диалоге
  // пришлось бы показывать целиком.
  group('реестр без раздела записей', () {
    for (final path in [
      '../../THIRD_PARTY_NOTICES.md',
      'assets/legal/THIRD_PARTY_NOTICES.md',
    ]) {
      test('в $path ровно один заголовок `## Записи`', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: path);

        final headings = [
          for (final line in file.readAsLinesSync())
            if (line.trimRight() == '## Записи') line,
        ];

        expect(
          headings,
          hasLength(1),
          reason: 'в $path нет единственного заголовка `## Записи`',
        );
      });
    }
  });

  group('строка лицензии из ресурса', () {
    test('имя и строка авторского права из текста LICENSE', () {
      const text =
          'MIT License\n\nCopyright (c) 2026 Alice Example\n\nPermission is '
          'hereby granted, free of charge.\n';

      final summary = licenseSummaryOf(text);

      expect(summary.name, 'MIT');
      expect(summary.copyright, 'Copyright (c) 2026 Alice Example');
    });

    test('для ресурса сборки равна третьей строке assets/legal/LICENSE', () {
      final asset = File('assets/legal/LICENSE');
      expect(asset.existsSync(), isTrue, reason: 'нет assets/legal/LICENSE');
      final lines = asset.readAsLinesSync();

      final summary = licenseSummaryOf(asset.readAsStringSync());

      expect(summary.name, 'MIT');
      expect(summary.copyright, lines[2]);
      expect(summary.copyright, startsWith('Copyright (c)'));
    });

    test('текст без строки Copyright даёт пустое авторское право, а не '
        'исключение', () {
      final summary = licenseSummaryOf('Some License\n\nNo owner here.\n');

      expect(summary.copyright, isEmpty);
    });
  });
}
