/// Проверка доказательств строк Must матрицы целей агента.
///
/// Почему: этап 9 («Паритет и переключение») закрывается, только когда у
/// каждой строки Must `docs/architecture/proposals/agent-parity-goals.md`
/// есть доказательство, которое существует и проходит (change
/// `switch-default-agent-to-dart`, D2–D6). Вручную сверять 77 строк с
/// фикстурами и тестами нельзя: переименование ломает матрицу молча.
///
/// Для чего: две группы. `matrix evidence exists` идёт в каждом прогоне
/// сторожа и ловит переименования; `matrix evidence passed` читает машинные
/// отчёты ночного прогона CI (`CODELAB_PARITY_RESULTS`) и считает статус
/// каждого доказательства (D5). Логика — в `test/support/parity/`, её
/// модульные тесты рядом и не зависят от настоящей матрицы.
///
/// Как использовать: `fvm dart run melos run guard` — только существование.
/// Статус: `CODELAB_PARITY_RESULTS=<каталог parity-results> fvm dart test
/// packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart`;
/// с `CODELAB_PARITY_APP_RESULTS=<каталог отчётов app>` проверяются и
/// доказательства `app:` (иначе они `deferred`, D9).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/parity/allowed_skips.dart';
import 'support/parity/evidence.dart';
import 'support/parity/matrix_parser.dart';
import 'support/parity/reports.dart';
import 'support/parity/verdict.dart';
import 'support/repo_root.dart';

void main() {
  final root = repoRoot();
  final matrixFile = File(
    p.join(root, 'docs/architecture/proposals/agent-parity-goals.md'),
  );

  group('matrix evidence exists', () {
    test('the matrix parses and the Must rows match the summary of §7', () {
      final matrix = parseMatrix(matrixFile.readAsStringSync());
      expect(matrix.mustRows, hasLength(matrix.summaryMust));
    });

    test('every Must row has existing evidence', () {
      final matrix = parseMatrix(matrixFile.readAsStringSync());
      final report = checkEvidenceExists(rows: matrix.mustRows, repoRoot: root);

      expect(
        report.failures,
        isEmpty,
        reason:
            'A matrix row names evidence that does not exist '
            '(design.md change switch-default-agent-to-dart, D3–D4). '
            'Restore the name or fix the matrix row.',
      );
    });
  });

  final resultsDir = Platform.environment['CODELAB_PARITY_RESULTS'];
  final appEnv = Platform.environment['CODELAB_PARITY_APP_RESULTS'];
  final appResultsDir = appEnv == null || appEnv.isEmpty ? null : appEnv;
  group(
    'matrix evidence passed',
    skip: statusGroupSkipReason(Platform.environment),
    () {
      test('every Must row has passing evidence in the reports', () {
        final dir = Directory(resultsDir!);
        if (!dir.existsSync()) {
          fail(
            'CODELAB_PARITY_RESULTS points to a missing directory: $resultsDir',
          );
        }
        final parsed = parseMatrix(matrixFile.readAsStringSync());
        final verdicts = computeVerdicts(
          rows: parsed.mustRows,
          repoRoot: root,
          resultsDir: dir.path,
          appResultsDir: appResultsDir,
          allowedSkips: allowedSkips,
        );
        final lines = renderVerdictReport(
          resultsDir: dir.path,
          verdicts: verdicts,
          appResultsDir: appResultsDir,
        );

        // Итог печатается всегда: по одному запуску видно, что открыто (D16);
        // CI строит из этих строк Step Summary.
        // ignore: avoid_print
        print(lines.join('\n'));
        final open = verdicts.where(
          (v) =>
              v.status != EvidenceStatus.pass &&
              v.status != EvidenceStatus.deferred,
        );
        expect(
          open.map((v) => v.toLine()),
          isEmpty,
          reason:
              'Evidence of Must rows is not closed (D5).\n${lines.join('\n')}',
        );
      });

      test('reports contain no secrets and no user home paths', () {
        final warnings = <String>[];
        // D16: сообщения называют файл и причину, но не значение. Отчёты app
        // дополнительно проверяются на пути домашнего каталога (D9).
        final leaks = [
          ...findSecretLeaks(
            resultsDir: Directory(resultsDir!),
            environment: Platform.environment,
            warnings: warnings,
          ),
          if (appResultsDir != null)
            ...findSecretLeaks(
              resultsDir: Directory(appResultsDir),
              environment: Platform.environment,
              checkHomePaths: true,
            ),
        ];
        for (final warning in warnings) {
          // Маркер в отчёте CI не блокирует (D16), но должен быть виден.
          // ignore: avoid_print
          print(warning);
        }
        expect(leaks, isEmpty);
      });
    },
  );
}
