/// Проверка утечек секретов в каталоге отчётов перед публикацией артефакта.
///
/// Почему: отчёты прогонов уходят в артефакты CI на 90 дней
/// (`switch-default-agent-to-dart`, D7, D16). Проверять утечку надо в
/// окружении того джоба, который отчёт породил, и до `upload-artifact`:
/// только там значения секретов этого джоба известны.
///
/// Для чего: шаг `ci.yml` запускает этот тест после `melos run` и грузит
/// артефакт только при зелёном результате. Правила поиска — `findSecretLeaks`.
///
/// Как использовать: `CODELAB_REPORT_LEAKS_DIR=<каталог> fvm dart test
/// packages/dart/codelab_architecture_tests/test/report_leaks_test.dart`.
/// Без переменной тест пропускается; нет каталога — нет отчётов, утечки нет.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/parity/reports.dart';

void main() {
  final dir = Platform.environment['CODELAB_REPORT_LEAKS_DIR'];
  test(
    'report directory contains no secrets',
    () {
      final warnings = <String>[];
      final leaks = findSecretLeaks(
        resultsDir: Directory(dir!),
        environment: Platform.environment,
        warnings: warnings,
      );
      for (final warning in warnings) {
        // Маркер в отчёте CI не блокирует публикацию, но виден в логе (D16).
        // ignore: avoid_print
        print(warning);
      }
      expect(leaks, isEmpty);
    },
    skip: dir == null || dir.isEmpty
        ? 'CODELAB_REPORT_LEAKS_DIR is not set: CI checks reports before upload'
        : false,
  );
}
