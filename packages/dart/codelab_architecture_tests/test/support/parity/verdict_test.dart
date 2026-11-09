// Модульный тест свёртки статусов доказательств на временных деревьях и
// отчётах (задача 1.5 change `switch-default-agent-to-dart`; testing-quality
// «Проверка доказательств матрицы целей»; design.md, D4–D6, D9).
//
// Допущение (проверить при реализации 1.6): `appResultsDir` — корень отчётов
// app, внутри `app/<режим>/<файл>.json`, как у `CODELAB_TEST_REPORT_DIR`.

import 'dart:convert';

import 'package:test/test.dart';

import 'matrix_parser.dart';
import 'parity_test_kit.dart';
import 'verdict.dart';

const _mcpSkip = 'setup.mcp cannot be passed to the agent process';

const _allowed = [
  AllowedSkip(
    'setup.mcp cannot be passed to the agent process',
    'cli-scenario-driver: пропуск фикстуры с setup.mcp',
  ),
];

late Tree _repo;
late Tree _results;

MatrixRow _row(String id, String criterion) =>
    MatrixRow(id: id, line: 1, criterion: criterion);

void _fixture(String id, [String body = '{}']) =>
    _repo.put('packages/dart/codelab_acp_testing/fixtures/acp/$id.json', body);

void _cliTest(String name) => _repo.put(
  'apps/codelab_cli/test/e2e/flow_test.dart',
  "void main() { test('$name', () {}); }",
);

List<EvidenceVerdict> _verdicts(
  List<MatrixRow> rows, {
  String? appResultsDir,
  List<AllowedSkip> allowed = _allowed,
}) => computeVerdicts(
  rows: rows,
  repoRoot: _repo.path,
  resultsDir: _results.path,
  appResultsDir: appResultsDir,
  allowedSkips: allowed,
);

EvidenceVerdict _single(List<EvidenceVerdict> v) {
  expect(v, hasLength(1));
  return v.single;
}

void main() {
  setUp(() {
    _repo = Tree('parity_repo_');
    _results = Tree('parity_results_');
  });
  tearDown(() {
    _repo.dispose();
    _results.dispose();
  });

  group('acp/<id>', () {
    test('pass: пройден в агентском прогоне корпуса', () {
      _fixture('x');
      _results.put(
        'dart/codelab_agent_acp.conformance.json',
        jsonReport(const [T('acp/x')]),
      );

      final v = _single(_verdicts([_row('R-01', '`acp/x`')]));

      expect(v.status, EvidenceStatus.pass);
    });

    test('обязательный источник — и dart/<пакет>.json, если нет '
        '*.conformance.json (ночной test уже гоняет те же файлы)', () {
      _fixture('x');
      _results.put(
        'dart/codelab_agent_acp.json',
        jsonReport(const [T('acp/x')]),
      );

      expect(
        _single(_verdicts([_row('R-01', '`acp/x`')])).status,
        EvidenceStatus.pass,
      );
    });

    test('фикстура с setup.transport проверяется по codelab_agent.json', () {
      _fixture(
        'ws',
        jsonEncode({
          'setup': {'transport': 'ws'},
        }),
      );
      _results.put('dart/codelab_agent.json', jsonReport(const [T('acp/ws')]));

      expect(
        _single(_verdicts([_row('R-12', '`acp/ws`')])).status,
        EvidenceStatus.pass,
      );
    });

    test('Падение в дополнительном источнике: failed, источник — '
        'scenario-embedded.xml', () {
      _fixture('x');
      _results
        ..put(
          'dart/codelab_agent_acp.conformance.json',
          jsonReport(const [T('acp/x')]),
        )
        ..put(
          'scenario-embedded.xml',
          junitReport(const [J('acp/x', failure: 'frame 3 differs')]),
        );

      final v = _single(_verdicts([_row('R-01', '`acp/x`')]));

      expect(v.status, EvidenceStatus.failed);
      expect(v.source, 'scenario-embedded.xml');
    });

    test('падение в клиентском корпусе — тоже failed', () {
      _fixture('x');
      _results
        ..put(
          'dart/codelab_agent_acp.conformance.json',
          jsonReport(const [T('acp/x')]),
        )
        ..put(
          'dart/codelab_client_acp.conformance.json',
          jsonReport(const [T('acp/x', result: 'failure')], success: false),
        );

      expect(
        _single(_verdicts([_row('R-01', '`acp/x`')])).status,
        EvidenceStatus.failed,
      );
    });

    test('Пропуск по спецификации в дополнительном источнике: pass', () {
      _fixture('mcp-stdio-tool-call');
      _results
        ..put(
          'dart/codelab_agent_acp.conformance.json',
          jsonReport(const [T('acp/mcp-stdio-tool-call')]),
        )
        ..put(
          'scenario-embedded.xml',
          junitReport(const [J('acp/mcp-stdio-tool-call', skipped: _mcpSkip)]),
        );

      final v = _single(_verdicts([_row('E-02', '`acp/mcp-stdio-tool-call`')]));

      expect(v.status, EvidenceStatus.pass);
    });

    test(
      'пропуск в дополнительном источнике с неизвестной причиной: skipped',
      () {
        _fixture('x');
        _results
          ..put(
            'dart/codelab_agent_acp.conformance.json',
            jsonReport(const [T('acp/x')]),
          )
          ..put(
            'scenario-embedded.xml',
            junitReport(const [J('acp/x', skipped: 'flaky on CI')]),
          );

        final v = _single(_verdicts([_row('R-01', '`acp/x`')]));

        expect(v.status, EvidenceStatus.skipped);
        expect(v.source, 'scenario-embedded.xml');
        expect(v.reason, 'flaky on CI');
      },
    );

    test('пропуск в обязательном источнике открывает строку, даже с '
        'разрешённой причиной', () {
      _fixture('x');
      _results.put(
        'dart/codelab_agent_acp.conformance.json',
        jsonReport(const [T('acp/x', skip: _mcpSkip)]),
      );

      final v = _single(_verdicts([_row('R-01', '`acp/x`')]));

      expect(v.status, EvidenceStatus.skipped);
      expect(v.reason, _mcpSkip);
    });

    test('нет ни одного теста в обязательном источнике: not-run', () {
      _fixture('x');
      _results.put(
        'dart/codelab_agent_acp.conformance.json',
        jsonReport(const [T('acp/other')]),
      );

      expect(
        _single(_verdicts([_row('R-01', '`acp/x`')])).status,
        EvidenceStatus.notRun,
      );
    });
  });

  group('cli/<id>', () {
    test('Тест scripted-only в режиме dart: нет в cli-dart.json — not-run', () {
      _cliTest('cli/x');
      _results.put('cli-dart.json', jsonReport(const [T('cli/other')]));

      final v = _single(_verdicts([_row('U-03', '`cli/x`')]));

      expect(v.status, EvidenceStatus.notRun);
    });

    test('нет файла cli-dart.json вовсе — not-run', () {
      _cliTest('cli/x');

      expect(
        _single(_verdicts([_row('U-03', '`cli/x`')])).status,
        EvidenceStatus.notRun,
      );
    });

    test('несколько тестов id: достаточно одного pass, если нет skipped и '
        'failed', () {
      _cliTest('cli/x');
      _results.put(
        'cli-dart.json',
        jsonReport(const [T('cli/x: a'), T('cli/x: b'), T('cli/xy: c')]),
      );

      expect(
        _single(_verdicts([_row('H-01', '`cli/x`')])).status,
        EvidenceStatus.pass,
      );
    });

    test('один из тестов id пропущен в обязательном источнике: skipped', () {
      _cliTest('cli/x');
      _results.put(
        'cli-dart.json',
        jsonReport(const [T('cli/x: a'), T('cli/x: b', skip: 'later')]),
      );

      expect(
        _single(_verdicts([_row('H-01', '`cli/x`')])).status,
        EvidenceStatus.skipped,
      );
    });

    test('тест чужого id с общим префиксом (cli/xy) не принадлежит cli/x', () {
      _cliTest('cli/x');
      _results.put('cli-dart.json', jsonReport(const [T('cli/xy')]));

      expect(
        _single(_verdicts([_row('H-01', '`cli/x`')])).status,
        EvidenceStatus.notRun,
      );
    });

    test('упавший в cli-embedded.json — failed при pass в cli-dart.json', () {
      _cliTest('cli/x');
      _results
        ..put('cli-dart.json', jsonReport(const [T('cli/x')]))
        ..put(
          'cli-embedded.json',
          jsonReport(const [T('cli/x', result: 'failure')], success: false),
        );

      final v = _single(_verdicts([_row('H-01', '`cli/x`')]));

      expect(v.status, EvidenceStatus.failed);
      expect(v.source, 'cli-embedded.json');
    });
  });

  group('core/<id> и путь файла теста', () {
    const testPath = 'packages/dart/codelab_agent_core/test/a_test.dart';

    void coreTest() => _repo.put(
      testPath,
      "void main() { test('core/x', () {}); test('core/y', () {}); }",
    );

    test('core/<id> берётся из dart/<пакет>.json пакета, где найден тест', () {
      coreTest();
      _results.put(
        'dart/codelab_agent_core.json',
        jsonReport(const [T('core/x')]),
      );

      expect(
        _single(_verdicts([_row('C-01', '`core/x`')])).status,
        EvidenceStatus.pass,
      );
    });

    test(
      'ночной test пишет и Dart-пакеты в flutter/ — читаются оба каталога',
      () {
        coreTest();
        _results.put(
          'flutter/codelab_agent_core.json',
          jsonReport(const [T('core/x')]),
        );

        expect(
          _single(_verdicts([_row('C-01', '`core/x`')])).status,
          EvidenceStatus.pass,
        );
      },
    );

    test('набор не загрузился: failed', () {
      coreTest();
      _results.put(
        'dart/codelab_agent_core.json',
        jsonReport(
          const [T('core/other')],
          success: false,
          failedLoads: const [
            '/work/packages/dart/codelab_agent_core/test/a_test.dart',
          ],
        ),
      );

      expect(
        _single(_verdicts([_row('C-01', '`core/x`')])).status,
        EvidenceStatus.failed,
      );
    });

    test('путь файла теста: pass, если все тесты файла прошли', () {
      coreTest();
      _results.put(
        'dart/codelab_agent_core.json',
        jsonReport(const [
          T('one', suite: '/work/$testPath'),
          T('two', suite: '/work/$testPath'),
          T(
            'foreign',
            suite: '/work/packages/dart/codelab_agent_core/test/b_test.dart',
          ),
        ]),
      );

      expect(
        _single(_verdicts([_row('L-06', '`$testPath`')])).status,
        EvidenceStatus.pass,
      );
    });

    test('путь файла теста: один упавший тест файла — failed', () {
      coreTest();
      _results.put(
        'dart/codelab_agent_core.json',
        jsonReport(const [
          T('one', suite: '/work/$testPath'),
          T('two', result: 'failure', suite: '/work/$testPath'),
        ], success: false),
      );

      expect(
        _single(_verdicts([_row('L-06', '`$testPath`')])).status,
        EvidenceStatus.failed,
      );
    });

    test('путь файла теста: в отчёте нет тестов файла — not-run', () {
      coreTest();
      _results.put('dart/codelab_agent_core.json', jsonReport(const [T('x')]));

      expect(
        _single(_verdicts([_row('L-06', '`$testPath`')])).status,
        EvidenceStatus.notRun,
      );
    });
  });

  group('missing и deferred', () {
    test('доказательство не существует: missing, отчёты не смотрятся', () {
      _results.put(
        'dart/codelab_agent_acp.conformance.json',
        jsonReport(const [T('acp/gone')]),
      );

      expect(
        _single(_verdicts([_row('R-08', '`acp/gone`')])).status,
        EvidenceStatus.missing,
      );
    });

    test('строка Must без единого доказательства: missing', () {
      expect(
        _single(_verdicts([_row('R-09', 'закрыто change x')])).status,
        EvidenceStatus.missing,
      );
    });

    test('Отчёты app не переданы: app:<файл> — deferred', () {
      _repo.put('apps/codelab_desktop/integration_test/fs_flow_test.dart');

      final v = _single(_verdicts([_row('T-01', '`app:fs_flow_test.dart`')]));

      expect(v.status, EvidenceStatus.deferred);
    });

    test('с отчётами app: pass в app/dart-agent/<файл>.json', () {
      _repo.put('apps/codelab_desktop/integration_test/fs_flow_test.dart');
      final app = Tree('parity_app_')
        ..put(
          'app/dart-agent/fs_flow_test.dart.json',
          jsonReport(const [T('fs flow')]),
        );
      addTearDown(app.dispose);

      final v = _single(
        _verdicts([
          _row('T-01', '`app:fs_flow_test.dart`'),
        ], appResultsDir: app.path),
      );

      expect(v.status, EvidenceStatus.pass);
    });

    test('с отчётами app: пропуск во встроенном режиме без причины в '
        'allowedSkips — skipped', () {
      _repo.put('apps/codelab_desktop/integration_test/fs_flow_test.dart');
      final app = Tree('parity_app_')
        ..put(
          'app/dart-agent/fs_flow_test.dart.json',
          jsonReport(const [T('fs flow')]),
        )
        ..put(
          'app/embedded/fs_flow_test.dart.json',
          jsonReport(const [T('fs flow', skip: 'unknown reason')]),
        );
      addTearDown(app.dispose);

      final v = _single(
        _verdicts([
          _row('T-01', '`app:fs_flow_test.dart`'),
        ], appResultsDir: app.path),
      );

      expect(v.status, EvidenceStatus.skipped);
    });
  });

  group('итог', () {
    List<EvidenceVerdict> two() => const [
      EvidenceVerdict(
        rowId: 'R-09',
        evidence: 'acp/b',
        status: EvidenceStatus.notRun,
      ),
      EvidenceVerdict(
        rowId: 'R-02',
        evidence: 'acp/a',
        status: EvidenceStatus.failed,
        source: 'scenario-embedded.xml',
        reason: 'frame 3 differs',
      ),
    ];

    test('строка итога: строка, доказательство, статус, источник, причина', () {
      expect(
        two().last.toLine(),
        'R-02 acp/a failed scenario-embedded.xml frame 3 differs',
      );
      expect(two().first.toLine(), 'R-09 acp/b not-run');
    });

    test('сортировка по id строки, первой строкой — meta.json', () {
      const meta = '{"commit":"abc","run_attempt":1}';
      _results.put('meta.json', meta);

      final lines = renderVerdictReport(
        resultsDir: _results.path,
        verdicts: two(),
      );

      expect(lines.first, meta);
      expect(lines.skip(1), [
        'R-02 acp/a failed scenario-embedded.xml frame 3 differs',
        'R-09 acp/b not-run',
      ]);
    });

    test('run_attempt > 1 добавляет предупреждение о перезапуске', () {
      _results.put('meta.json', '{"commit":"abc","run_attempt":2}');

      final lines = renderVerdictReport(
        resultsDir: _results.path,
        verdicts: two(),
      );

      expect(
        lines.any(
          (l) =>
              l.contains('rerun attempt: does not count for the three nights'),
        ),
        isTrue,
      );
    });

    test('run_attempt 1 — без предупреждения', () {
      _results.put('meta.json', '{"commit":"abc","run_attempt":1}');

      final lines = renderVerdictReport(
        resultsDir: _results.path,
        verdicts: two(),
      );

      expect(lines.any((l) => l.contains('rerun attempt')), isFalse);
    });

    test('Каталог отчётов без meta.json: ошибка про meta.json', () {
      expect(
        () => renderVerdictReport(resultsDir: _results.path, verdicts: two()),
        throwsA(predicate((e) => e.toString().contains('meta.json'))),
      );
    });
  });

  group('группа статуса', () {
    test('Без отчётов: пропуск с причиной, если переменной нет', () {
      expect(
        statusGroupSkipReason(const {}),
        'CODELAB_PARITY_RESULTS is not set: status is checked by the nightly '
        'parity job',
      );
    });

    test('переменная задана — группа не пропускается', () {
      expect(
        statusGroupSkipReason(const {
          'CODELAB_PARITY_RESULTS': 'parity-results',
        }),
        isNull,
      );
    });
  });
}
