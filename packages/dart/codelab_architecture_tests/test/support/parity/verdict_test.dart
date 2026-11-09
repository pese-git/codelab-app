// Модульный тест свёртки статусов доказательств на временных деревьях и
// отчётах (задача 1.5 change `switch-default-agent-to-dart`; testing-quality
// «Проверка доказательств матрицы целей»; design.md, D4–D6, D9).
//
// Допущение (проверить при реализации 1.6): `appResultsDir` — корень отчётов
// app, внутри `app/<режим>/<файл>.json`, как у `CODELAB_TEST_REPORT_DIR`.

import 'dart:convert';

import 'package:test/test.dart';

import 'allowed_skips.dart' as real;
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

  // Задача 2.10 (решение Q4 (а), D3, D5): правило путей файлов тестов и
  // шаблонов на строках Must, которые закрываются без новых id. Ячейки
  // сокращены, но сохраняют структуру настоящих строк матрицы: пути в
  // обратных кавычках, названия тестов в «ёлочках», имена типов и флаги,
  // которые доказательствами не являются.
  group('правило путей и шаблонов на строках Must (Q4, задача 2.10)', () {
    const l06 = 'packages/dart/codelab_agent_core/test/llm/watchdog_test.dart';
    const t05 =
        'packages/dart/codelab_agent_core/test/tools/parallel_edit_test.dart';
    const p08Core =
        'packages/dart/codelab_agent_core/test/env/bounded_env_test.dart';
    const p08Io =
        'packages/dart/codelab_agent_io/test/local_execution_env_test.dart';
    const r17Core =
        'packages/dart/codelab_agent_core/test/testing/'
        'scripted_stream_function_test.dart';
    const r17Acp = 'packages/dart/codelab_agent_acp/test/conformance_test.dart';
    const r17App = 'apps/codelab_agent/test/llm_scripts_load_test.dart';
    const r23Inspector =
        'packages/dart/codelab_client_core/test/inspector/'
        'inspector_projection_test.dart';
    const r23Diagnostics =
        'packages/dart/codelab_client_core/test/diagnostics/'
        'diagnostics_test.dart';
    const r23Logging =
        'packages/dart/codelab_client_acp/test/structured_logging_test.dart';
    const h04Scenario =
        'apps/codelab_cli/test/scenario/test_scenario_command_test.dart';

    String col(String path) => '/work/$path';

    Map<String, EvidenceStatus> byEvidence(List<EvidenceVerdict> v) => {
      for (final e in v) e.evidence: e.status,
    };

    // Файл существует в дереве репозитория: доказательство-путь «есть».
    void files(Iterable<String> paths) {
      for (final path in paths) {
        _repo.put(path, 'void main() {}');
      }
    }

    group('одиночный путь (L-06, T-05)', () {
      final rows = {
        'L-06':
            '`$l06` («no headers within 30 s → timeout», «silence of 120 s '
            'after the first block → mid_stream_idle»); спецификация — '
            'agent-core-architecture §2.10.1',
        'T-05':
            '`$t05` (группа `PathLock` и параллельные правки одного пути); '
            'спецификация — agent-core-architecture §6.3.4',
      };
      final paths = {'L-06': l06, 'T-05': t05};

      for (final id in rows.keys) {
        test('$id: названия тестов и имена типов — не доказательства, путь '
            'один', () {
          files([paths[id]!]);
          _results.put(
            'dart/codelab_agent_core.json',
            jsonReport([T('one', suite: col(paths[id]!))]),
          );

          final v = _single(_verdicts([_row(id, rows[id]!)]));

          expect(v.evidence, paths[id]);
          expect(v.status, EvidenceStatus.pass);
        });

        test('$id: все тесты файла прошли, чужой файл пакета не мешает', () {
          files([paths[id]!]);
          _results.put(
            'dart/codelab_agent_core.json',
            jsonReport([
              T('one', suite: col(paths[id]!)),
              T('two', suite: col(paths[id]!)),
              T(
                'foreign',
                result: 'failure',
                suite: col(
                  'packages/dart/codelab_agent_core/test/other_test.dart',
                ),
              ),
            ], success: false),
          );

          expect(
            _single(_verdicts([_row(id, rows[id]!)])).status,
            EvidenceStatus.pass,
          );
        });

        test('$id: один упавший тест файла — failed', () {
          files([paths[id]!]);
          _results.put(
            'dart/codelab_agent_core.json',
            jsonReport([
              T('one', suite: col(paths[id]!)),
              T('two', result: 'failure', suite: col(paths[id]!)),
            ], success: false),
          );

          expect(
            _single(_verdicts([_row(id, rows[id]!)])).status,
            EvidenceStatus.failed,
          );
        });

        test('$id: пропущенный тест без причины из перечня — skipped', () {
          files([paths[id]!]);
          _results.put(
            'dart/codelab_agent_core.json',
            jsonReport([
              T('one', suite: col(paths[id]!)),
              T('two', skip: 'flaky on CI', suite: col(paths[id]!)),
            ]),
          );

          expect(
            _single(_verdicts([_row(id, rows[id]!)])).status,
            EvidenceStatus.skipped,
          );
        });

        test('$id: в отчёте пакета нет тестов файла — not-run', () {
          files([paths[id]!]);
          _results.put(
            'dart/codelab_agent_core.json',
            jsonReport(const [T('x', suite: '/work/test/a_test.dart')]),
          );

          expect(
            _single(_verdicts([_row(id, rows[id]!)])).status,
            EvidenceStatus.notRun,
          );
        });

        test('$id: файла нет — missing, отчёт не смотрится', () {
          _results.put(
            'dart/codelab_agent_core.json',
            jsonReport([T('one', suite: col(paths[id]!))]),
          );

          expect(
            _single(_verdicts([_row(id, rows[id]!)])).status,
            EvidenceStatus.missing,
          );
        });
      }
    });

    group('несколько путей в разных пакетах (P-08, R-17, R-23)', () {
      test('P-08: два пути в двух пакетах — два вердикта, каждый по отчёту '
          'своего пакета', () {
        files([p08Core, p08Io]);
        _results
          ..put(
            'dart/codelab_agent_core.json',
            jsonReport([T('rejects sibling', suite: col(p08Core))]),
          )
          ..put(
            'dart/codelab_agent_io.json',
            jsonReport([
              T('sibling is outside', suite: col(p08Io)),
              T('link out of the root', suite: col(p08Io)),
            ]),
          );

        final v = _verdicts([
          _row(
            'P-08',
            '`$p08Core` («rejects sibling directory with shared prefix» — '
                '`/proj_evil` при `cwd=/proj`), `$p08Io` («a sibling '
                'directory with a shared prefix is outside»); спецификация — '
                'agent-core-architecture §4.4',
          ),
        ]);

        expect(byEvidence(v), {
          p08Core: EvidenceStatus.pass,
          p08Io: EvidenceStatus.pass,
        });
      });

      test('P-08: упал тест второго пакета — failed только у его пути', () {
        files([p08Core, p08Io]);
        _results
          ..put(
            'dart/codelab_agent_core.json',
            jsonReport([T('rejects sibling', suite: col(p08Core))]),
          )
          ..put(
            'dart/codelab_agent_io.json',
            jsonReport([
              T('link out', result: 'failure', suite: col(p08Io)),
            ], success: false),
          );

        final v = _verdicts([_row('P-08', '`$p08Core`, `$p08Io`')]);

        expect(byEvidence(v), {
          p08Core: EvidenceStatus.pass,
          p08Io: EvidenceStatus.failed,
        });
      });

      test('R-17: три пути в трёх пакетах, включая apps/', () {
        files([r17Core, r17Acp, r17App]);
        _results
          ..put(
            'dart/codelab_agent_core.json',
            jsonReport([T('scripted', suite: col(r17Core))]),
          )
          ..put(
            'dart/codelab_agent_acp.json',
            jsonReport([T('acp/x', suite: col(r17Acp))]),
          )
          ..put(
            'dart/codelab_agent.json',
            jsonReport([T('load', suite: col(r17App))]),
          );

        final v = _verdicts([
          _row(
            'R-17',
            '`$r17Core`; conformance Dart-агента на корпусе фикстур идёт на '
                'scripted LLM (`$r17Acp`, dart-agent-and-clients §9.3); '
                '`$r17App`; перевод сценариев Python-агента в `llm.steps` — '
                'необязательно',
          ),
        ]);

        expect(byEvidence(v), {
          r17Core: EvidenceStatus.pass,
          r17Acp: EvidenceStatus.pass,
          r17App: EvidenceStatus.pass,
        });
      });

      test('R-17: apps/codelab_agent читается из отчёта codelab_agent.json, '
          'а не из пакета codelab_agent_acp', () {
        files([r17App]);
        _results.put(
          'dart/codelab_agent_acp.json',
          jsonReport([T('load', suite: col(r17App))]),
        );

        expect(
          _single(_verdicts([_row('R-17', '`$r17App`')])).status,
          EvidenceStatus.notRun,
        );
      });

      test('R-23: полный путь, дописанный задачей 0.3, и пути двух пакетов '
          'клиента', () {
        files([r23Inspector, r23Diagnostics, r23Logging]);
        _results
          ..put(
            'dart/codelab_client_core.json',
            jsonReport([
              T('projection', suite: col(r23Inspector)),
              T('masks tokens in the text', suite: col(r23Diagnostics)),
            ]),
          )
          ..put(
            'dart/codelab_client_acp.json',
            jsonReport([
              T(
                'masks secrets in structured log output',
                suite: col(r23Logging),
              ),
            ]),
          );

        final v = _verdicts([
          _row(
            'R-23',
            '`$r23Inspector`, `$r23Diagnostics` («masks tokens in the text», '
                '«formatRedactedJson … masks sensitive keys»), '
                '`$r23Logging` («masks secrets in structured log output»)',
          ),
        ]);

        expect(byEvidence(v), {
          r23Inspector: EvidenceStatus.pass,
          r23Diagnostics: EvidenceStatus.pass,
          r23Logging: EvidenceStatus.pass,
        });
      });

      test('R-23: нет отчёта пакета client_acp — not-run у его пути, '
          'остальные пути не затронуты', () {
        files([r23Inspector, r23Diagnostics, r23Logging]);
        _results.put(
          'dart/codelab_client_core.json',
          jsonReport([
            T('projection', suite: col(r23Inspector)),
            T('masks tokens', suite: col(r23Diagnostics)),
          ]),
        );

        final v = _verdicts([
          _row('R-23', '`$r23Inspector`, `$r23Diagnostics`, `$r23Logging`'),
        ]);

        expect(byEvidence(v), {
          r23Inspector: EvidenceStatus.pass,
          r23Diagnostics: EvidenceStatus.pass,
          r23Logging: EvidenceStatus.notRun,
        });
      });
    });

    group('шаблон acp/* (H-04)', () {
      const h04 =
          'прогон всех `acp/*` в CI против встроенного и внешнего агента; '
          '`$h04Scenario` (корпус против `FixtureReplayAgent`, испорченная '
          'фикстура — `FAIL` и код 1) и `codelab_agent_corpus_test.dart` '
          '(корпус против `codelab-agent`); встроенный — этап 7';

      void corpus() {
        _fixture(
          'a',
          jsonEncode({
            'roles': ['agent'],
          }),
        );
        _fixture('b');
        _fixture(
          'only-client',
          jsonEncode({
            'roles': ['client'],
          }),
        );
        files([h04Scenario]);
      }

      EvidenceVerdict pattern(List<EvidenceVerdict> v) =>
          v.singleWhere((e) => e.evidence == 'acp/*');

      test('учитываются фикстуры с ролью agent (без roles — обе роли); '
          'фикстура только client не требует теста', () {
        corpus();
        _results
          ..put(
            'dart/codelab_agent_acp.conformance.json',
            jsonReport(const [T('acp/a'), T('acp/b')]),
          )
          ..put(
            'dart/codelab_cli.json',
            jsonReport([T('replay', suite: col(h04Scenario))]),
          );

        final v = _verdicts([_row('H-04', h04)]);

        // Голое имя файла без каталога (`codelab_agent_corpus_test.dart`) —
        // описание, а не доказательство (D3): у строки их два.
        expect(byEvidence(v), {
          'acp/*': EvidenceStatus.pass,
          h04Scenario: EvidenceStatus.pass,
        });
      });

      test(
        'одна фикстура корпуса упала — шаблон failed, строка не зелёная',
        () {
          corpus();
          _results.put(
            'dart/codelab_agent_acp.conformance.json',
            jsonReport(const [
              T('acp/a'),
              T('acp/b', result: 'failure'),
            ], success: false),
          );

          final p = pattern(_verdicts([_row('H-04', h04)]));

          expect(p.status, EvidenceStatus.failed);
          expect(p.reason, contains('acp/b'));
        },
      );

      test('у одной фикстуры агента нет теста — шаблон not-run', () {
        corpus();
        _results.put(
          'dart/codelab_agent_acp.conformance.json',
          jsonReport(const [T('acp/a')]),
        );

        final p = pattern(_verdicts([_row('H-04', h04)]));

        expect(p.status, EvidenceStatus.notRun);
        expect(p.reason, contains('acp/b'));
      });

      test('пропуск фикстуры в агентском прогоне открывает шаблон', () {
        corpus();
        _results.put(
          'dart/codelab_agent_acp.conformance.json',
          jsonReport(const [T('acp/a'), T('acp/b', skip: 'unexpected skip')]),
        );

        expect(
          pattern(_verdicts([_row('H-04', h04)])).status,
          EvidenceStatus.skipped,
        );
      });

      test('пропуск в embedded по перечню шаблон не открывает (Q5)', () {
        corpus();
        _results
          ..put(
            'dart/codelab_agent_acp.conformance.json',
            jsonReport(const [T('acp/a'), T('acp/b')]),
          )
          ..put(
            'scenario-embedded.xml',
            junitReport(const [J('acp/a'), J('acp/b', skipped: _mcpSkip)]),
          );

        expect(
          pattern(_verdicts([_row('H-04', h04)])).status,
          EvidenceStatus.pass,
        );
      });

      test('в репозитории нет ни одной фикстуры с ролью agent — missing', () {
        _fixture(
          'only-client',
          jsonEncode({
            'roles': ['client'],
          }),
        );

        expect(
          pattern(_verdicts([_row('H-04', '`acp/*`')])).status,
          EvidenceStatus.missing,
        );
      });
    });

    group('шаблон app:* (D-04)', () {
      const d04 =
          'все `app:*` в режиме встроенного агента; режим встроенного '
          'агента — change `add-embedded-agent-mode` '
          '(`apps/codelab_desktop/test/app/app_scope_embedded_test.dart`)';

      void app() {
        _repo
          ..put('apps/codelab_desktop/integration_test/fs_flow_test.dart')
          ..put('apps/codelab_desktop/integration_test/chat_flow_test.dart')
          ..put('apps/codelab_desktop/test/app/app_scope_embedded_test.dart');
      }

      EvidenceVerdict pattern(List<EvidenceVerdict> v) =>
          v.singleWhere((e) => e.evidence == 'app:*');

      test('отчёты app не переданы — шаблон deferred', () {
        app();

        expect(
          pattern(_verdicts([_row('D-04', d04)])).status,
          EvidenceStatus.deferred,
        );
      });

      test('все интеграционные тесты прошли в dart-agent: pass', () {
        app();
        final dir = Tree('parity_app_')
          ..put(
            'app/dart-agent/fs_flow_test.dart.json',
            jsonReport(const [T('fs')]),
          )
          ..put(
            'app/dart-agent/chat_flow_test.dart.json',
            jsonReport(const [T('chat')]),
          );
        addTearDown(dir.dispose);

        expect(
          pattern(
            _verdicts([_row('D-04', d04)], appResultsDir: dir.path),
          ).status,
          EvidenceStatus.pass,
        );
      });

      test('нет отчёта одного файла — шаблон not-run', () {
        app();
        final dir = Tree('parity_app_')
          ..put(
            'app/dart-agent/fs_flow_test.dart.json',
            jsonReport(const [T('fs')]),
          );
        addTearDown(dir.dispose);

        expect(
          pattern(
            _verdicts([_row('D-04', d04)], appResultsDir: dir.path),
          ).status,
          EvidenceStatus.notRun,
        );
      });

      test('упал тест одного файла — шаблон failed', () {
        app();
        final dir = Tree('parity_app_')
          ..put(
            'app/dart-agent/fs_flow_test.dart.json',
            jsonReport(const [T('fs')]),
          )
          ..put(
            'app/dart-agent/chat_flow_test.dart.json',
            jsonReport(const [T('chat', result: 'failure')], success: false),
          );
        addTearDown(dir.dispose);

        expect(
          pattern(
            _verdicts([_row('D-04', d04)], appResultsDir: dir.path),
          ).status,
          EvidenceStatus.failed,
        );
      });

      test('пропуск во встроенном режиме по перечню шаблон не открывает', () {
        app();
        final dir = Tree('parity_app_')
          ..put(
            'app/dart-agent/fs_flow_test.dart.json',
            jsonReport(const [T('fs')]),
          )
          ..put(
            'app/embedded/fs_flow_test.dart.json',
            jsonReport(const [
              T(
                'fs',
                skip:
                    '[skipped: the embedded agent runs files and '
                    'commands locally]',
              ),
            ]),
          )
          ..put(
            'app/dart-agent/chat_flow_test.dart.json',
            jsonReport(const [T('chat')]),
          );
        addTearDown(dir.dispose);

        expect(
          pattern(
            _verdicts(
              [_row('D-04', d04)],
              appResultsDir: dir.path,
              allowed: real.allowedSkips,
            ),
          ).status,
          EvidenceStatus.pass,
        );
      });
    });
  });

  // Задача 2.14 (решение Q8, 2026-11-10): перечень `allowedSkips` применяется
  // и к доказательству-пути. R-17: `conformance_test.dart` агента пропускает
  // фикстуры с ролью только `client` — пропуск задан спецификацией корпуса
  // (acp-golden-fixtures «Агентский драйвер фикстур»).
  group('пропуск в доказательстве-пути (Q8, задача 2.14)', () {
    const path = 'packages/dart/codelab_agent_acp/test/conformance_test.dart';
    const suite = '/work/$path';
    const roleSkip =
        'acp/errors-unknown-session-update-tolerated has roles [client] '
        'without "agent"';

    void conformance(List<T> tests) {
      _repo.put(path, 'void main() {}');
      _results.put('dart/codelab_agent_acp.json', jsonReport(tests));
    }

    test('пропуск с причиной из allowedSkips — pass', () {
      conformance(const [
        T('acp/prompt-text-end-turn', suite: suite),
        T(
          'acp/errors-unknown-session-update-tolerated',
          skip: roleSkip,
          suite: suite,
        ),
      ]);

      final v = _single(
        _verdicts(
          [_row('R-17', '`$path`')],
          allowed: const [
            AllowedSkip(
              'has roles [client] without "agent"',
              'acp-golden-fixtures «Агентский драйвер фикстур»',
            ),
          ],
        ),
      );

      expect(v.status, EvidenceStatus.pass);
    });

    test('пропуск с причиной не из перечня — skipped, причина печатается', () {
      conformance(const [
        T('acp/prompt-text-end-turn', suite: suite),
        T('acp/prompt-streaming-text', skip: 'flaky on CI', suite: suite),
      ]);

      final v = _single(
        _verdicts(
          [_row('R-17', '`$path`')],
          allowed: const [
            AllowedSkip(
              'has roles [client] without "agent"',
              'acp-golden-fixtures «Агентский драйвер фикстур»',
            ),
          ],
        ),
      );

      expect(v.status, EvidenceStatus.skipped);
      expect(v.reason, 'flaky on CI');
    });

    test('пропуск без причины и пустой перечень — skipped', () {
      conformance(const [
        T('one', suite: suite),
        T('two', skip: '', suite: suite),
      ]);

      expect(
        _single(_verdicts([_row('R-17', '`$path`')], allowed: const [])).status,
        EvidenceStatus.skipped,
      );
    });

    test('допустимый и недопустимый пропуски в одном файле — skipped: '
        'перечень не прячет чужой пропуск', () {
      conformance(const [
        T('acp/x', skip: roleSkip, suite: suite),
        T('acp/y', skip: 'unknown reason', suite: suite),
      ]);

      expect(
        _single(_verdicts([_row('R-17', '`$path`')])).status,
        EvidenceStatus.skipped,
      );
    });

    test('допустимый пропуск не прячет упавший тест файла — failed', () {
      conformance(const [
        T('acp/x', skip: roleSkip, suite: suite),
        T('acp/y', result: 'failure', suite: suite),
      ]);

      expect(
        _single(_verdicts([_row('R-17', '`$path`')])).status,
        EvidenceStatus.failed,
      );
    });

    test('настоящий перечень: R-17-подобный случай '
        '(has roles [client] without "agent") — pass', () {
      conformance(const [
        T('acp/prompt-text-end-turn', suite: suite),
        T(
          'acp/errors-unknown-session-update-tolerated',
          skip: roleSkip,
          suite: suite,
        ),
        T(
          'acp/tool-kind-unknown-tolerated',
          skip:
              'acp/tool-kind-unknown-tolerated has roles [client] without '
              '"agent"',
          suite: suite,
        ),
        T('the factory still rejects an unknown config key', suite: suite),
      ]);

      final v = _single(
        _verdicts([_row('R-17', '`$path`')], allowed: real.allowedSkips),
      );

      expect(v.status, EvidenceStatus.pass);
    });

    test('настоящий перечень: транспортная фикстура и setup.mcp тоже '
        'допустимы, неизвестная причина — нет', () {
      conformance(const [
        T(
          'acp/stdio-framing-large-line',
          skip:
              'acp/stdio-framing-large-line has setup.transport: the '
              'transport driver plays it against the binary process',
          suite: suite,
        ),
        T('acp/y', skip: 'not implemented yet', suite: suite),
      ]);

      expect(
        _single(
          _verdicts([_row('R-17', '`$path`')], allowed: real.allowedSkips),
        ).status,
        EvidenceStatus.skipped,
      );
    });

    test('пропуск в обязательном источнике acp/<id> по-прежнему открывает '
        'строку, даже с причиной из перечня (Q5 (б))', () {
      _fixture('x');
      _results.put(
        'dart/codelab_agent_acp.conformance.json',
        jsonReport(const [T('acp/x', skip: roleSkip)]),
      );

      expect(
        _single(
          _verdicts([_row('R-17', '`acp/x`')], allowed: real.allowedSkips),
        ).status,
        EvidenceStatus.skipped,
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
