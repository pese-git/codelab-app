// Версия сборки и адрес заметок о выпуске (задача 5.3 change
// `add-app-general-page`; design.md D11, D14; spec app-settings «Раздел
// «About» страницы «General»»).
//
// Реализация — задача 5.4 change `add-app-general-page`.
//
// Почему сверка с файлами, а не со вторым значением в коде: `package_info_plus`
// в стек не добавляется (AGENTS.md §4), поэтому версия — константа, и тест
// не даёт ей разойтись с `pubspec.yaml`; адрес заметок не должен разойтись с
// адресом репозитория сайта.

import 'dart:io';

import 'package:codelab_desktop/app/build_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('codelabDesktopVersion равна version из pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^\s+#]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'в pubspec.yaml нет поля version');
    expect(
      codelabDesktopVersion,
      match!.group(1),
      reason: 'обновите lib/app/build_version.dart вместе с pubspec.yaml',
    );
  });

  test('kCodeLabReleaseNotesUrl ведёт на CHANGELOG.md репозитория сайта', () {
    final config = File('../../site/src/site.config.ts').readAsStringSync();
    final repo = RegExp(
      r"export const repoUrl = '([^']+)'",
    ).firstMatch(config)?.group(1);

    expect(repo, isNotNull, reason: 'в site.config.ts нет repoUrl');
    expect(kCodeLabReleaseNotesUrl, startsWith('$repo/'));
    expect(kCodeLabReleaseNotesUrl, endsWith('/CHANGELOG.md'));
    expect(kCodeLabReleaseNotesUrl, '$repo/blob/master/CHANGELOG.md');
  });

  test('адрес заметок — https без параметров', () {
    final uri = Uri.parse(kCodeLabReleaseNotesUrl);

    expect(uri.scheme, 'https');
    expect(uri.hasQuery, isFalse);
    expect(uri.hasFragment, isFalse);
  });
}
