// Граничные случаи разбора и свёртки отчётов (design.md change
// `switch-default-agent-to-dart`, D5, D16; задачи 1.2, 1.4, 1.6, 1.8).
// Каждая группа закрывает конкретную мутацию кода `test/support/parity/` или
// замечание ревью; имя группы говорит, какую.

import 'dart:convert';

import 'package:test/test.dart';

import 'evidence.dart';
import 'allowed_skips.dart';
import 'matrix_parser.dart';
import 'parity_test_kit.dart';
import 'verdict.dart';

late Tree _repo;
late Tree _results;

MatrixRow _row(String id, String criterion) =>
    MatrixRow(id: id, line: 1, criterion: criterion);

/// [roles] `null` — поле `roles` не записано: по `fixture.dart` это обе роли.
void _fixture(String id, {List<String>? roles = const ['agent']}) => _repo.put(
  'packages/dart/codelab_acp_testing/fixtures/acp/$id.json',
  jsonEncode({'roles': ?roles}),
);

List<EvidenceVerdict> _verdicts(
  String criterion, {
  String? appResultsDir,
  List<AllowedSkip> allowed = const [],
}) => computeVerdicts(
  rows: [_row('H-04', criterion)],
  repoRoot: _repo.path,
  resultsDir: _results.path,
  appResultsDir: appResultsDir,
  allowedSkips: allowed,
);

const _agentRun = 'dart/codelab_agent_acp.conformance.json';

void main() {
  setUp(() {
    _repo = Tree('parity_edge_repo_');
    _results = Tree('parity_edge_results_');
  });
  tearDown(() {
    _repo.dispose();
    _results.dispose();
  });

  group('пропуск без причины: имя теста как запасной признак', () {
    const note = '[skipped: the embedded agent runs files locally]';

    EvidenceStatus run(String embeddedName) {
      _repo.put('apps/codelab_desktop/integration_test/f_test.dart');
      final app = Tree('parity_edge_app_')
        ..put('app/dart-agent/f_test.dart.json', jsonReport(const [T('flow')]))
        ..put(
          'app/embedded/f_test.dart.json',
          jsonReport([T(embeddedName, skip: '')]),
        );
      addTearDown(app.dispose);
      return _verdicts(
        '`app:f_test.dart`',
        appResultsDir: app.path,
        allowed: [
          AllowedSkip(
            RegExp(r'.* \[skipped: the embedded agent runs files locally\]'),
            'spec',
            onName: true,
          ),
        ],
      ).single.status;
    }

    test('заметка из allowedSkips в имени — строку не открывает', () {
      expect(run('flow $note'), EvidenceStatus.pass);
    });

    test('без совпадения с allowedSkips — skipped', () {
      expect(run('flow'), EvidenceStatus.skipped);
    });
  });

  group('шаблон acp/*: берётся худший статус части', () {
    void fixtures() {
      _fixture('a');
      _fixture('b');
    }

    test('pass и failed — failed', () {
      fixtures();
      _results.put(
        _agentRun,
        jsonReport([
          const T('acp/a'),
          const T('acp/b', result: 'failure'),
        ], success: false),
      );
      expect(_verdicts('`acp/*`').single.status, EvidenceStatus.failed);
    });

    test('failed раньше pass — тоже failed', () {
      fixtures();
      _results.put(
        _agentRun,
        jsonReport([
          const T('acp/a', result: 'failure'),
          const T('acp/b'),
        ], success: false),
      );
      expect(_verdicts('`acp/*`').single.status, EvidenceStatus.failed);
    });

    test('pass и not-run — not-run, в любом порядке', () {
      fixtures();
      _results.put(_agentRun, jsonReport(const [T('acp/a')]));
      expect(_verdicts('`acp/*`').single.status, EvidenceStatus.notRun);
      _results.put(_agentRun, jsonReport(const [T('acp/b')]));
      expect(_verdicts('`acp/*`').single.status, EvidenceStatus.notRun);
    });

    test('все части pass — pass', () {
      fixtures();
      _results.put(_agentRun, jsonReport(const [T('acp/a'), T('acp/b')]));
      expect(_verdicts('`acp/*`').single.status, EvidenceStatus.pass);
    });
  });

  group('шаблон app:* берёт худший статус файлов', () {
    test('pass и failed — failed', () {
      _repo
        ..put('apps/codelab_desktop/integration_test/a_test.dart')
        ..put('apps/codelab_desktop/integration_test/b_test.dart');
      final app = Tree('parity_edge_app_')
        ..put('app/dart-agent/a_test.dart.json', jsonReport(const [T('a')]))
        ..put(
          'app/dart-agent/b_test.dart.json',
          jsonReport(const [T('b', result: 'failure')], success: false),
        );
      addTearDown(app.dispose);
      expect(
        _verdicts('`app:*`', appResultsDir: app.path).single.status,
        EvidenceStatus.failed,
      );
    });
  });

  group('фикстуры корпуса: какие входят в acp/*', () {
    test('фикстура только с ролью client в acp/* не входит', () {
      _fixture('a');
      _fixture('c', roles: const ['client']);
      _results.put(_agentRun, jsonReport(const [T('acp/a')]));
      expect(_verdicts('`acp/*`').single.status, EvidenceStatus.pass);
      expect(agentFixtureIds(_repo.path), ['a']);
    });

    test('служебный файл с «_» не фикстура', () {
      _fixture('a');
      _fixture('_schema_like');
      _results.put(_agentRun, jsonReport(const [T('acp/a')]));
      expect(agentFixtureIds(_repo.path), ['a']);
      expect(_verdicts('`acp/*`').single.status, EvidenceStatus.pass);
    });
  });

  group('граница пути набора в отчёте', () {
    const file = 'packages/dart/codelab_agent_core/test/a_test.dart';

    EvidenceStatus run(String suite) {
      _repo.put(file);
      _results.put(
        'dart/codelab_agent_core.json',
        jsonReport([T('t', suite: suite)]),
      );
      return _verdicts('`$file`').single.status;
    }

    test('путь на границе каталога совпадает', () {
      expect(run('/work/$file'), EvidenceStatus.pass);
    });

    test('чужой префикс без границы каталога не совпадает', () {
      expect(run('/work/x$file'), EvidenceStatus.notRun);
    });
  });

  group('итог: предупреждение о перезапуске', () {
    List<String> render(int attempt) {
      _results.put('meta.json', '{"run_attempt":$attempt}');
      return renderVerdictReport(resultsDir: _results.path, verdicts: const []);
    }

    bool warns(List<String> l) => l.any((x) => x.contains('rerun attempt'));

    test('попытка 1 — нет, 2 и 3 — есть', () {
      expect(warns(render(1)), isFalse);
      expect(warns(render(2)), isTrue);
      expect(warns(render(3)), isTrue);
    });
  });

  group('имя вызова test/group', () {
    test('mytest(...) и subgroup(...) не засчитываются', () {
      _repo.put(
        'packages/dart/codelab_agent_core/test/a_test.dart',
        "void main() { mytest('core/x', () {}); subgroup('core/y', () {}); "
            "my_group('core/z', () {}); }",
      );
      final report = checkEvidenceExists(
        rows: [_row('C-01', '`core/x`, `core/y`, `core/z`')],
        repoRoot: _repo.path,
      );
      expect(report.failures, [
        'C-01 core/x missing',
        'C-01 core/y missing',
        'C-01 core/z missing',
      ]);
    });
  });

  group('ограждённый блок в матрице', () {
    test('таблица внутри ``` не даёт строк Must', () {
      const h =
          '| ID | Возможность | Целевое поведение | Приоритет | Этап | '
          'Как видно клиенту | Критерий приёмки | Py / app |';
      final doc = [
        '## 3. Матрица',
        '### 3.1. Группа',
        h,
        '|---|---|---|---|---|---|---|---|',
        '| L-01 | c | g | Must | 1 | — | `acp/a` | есть |',
        '```',
        h,
        '|---|---|---|---|---|---|---|---|',
        '| L-02 | c | g | Must | 1 | — | `acp/b` | есть |',
        '```',
        '## 7. Сводка',
        '| Этап | Must | Should | Must-строки |',
        '|---|---|---|---|',
        '| **Итого** | **1** | **0** | — |',
        '',
      ].join('\n');
      expect(parseMatrix(doc).mustRows.map((r) => r.id), ['L-01']);
    });
  });

  group('фикстура без поля roles играет обе роли (fixture.dart)', () {
    test('входит в acp/* и в agentFixtureIds', () {
      _fixture('a', roles: null);
      _fixture('c', roles: const ['client']);
      expect(agentFixtureIds(_repo.path), ['a']);
      _results.put(_agentRun, jsonReport(const [T('acp/a')]));
      expect(_verdicts('`acp/*`').single.status, EvidenceStatus.pass);
    });

    test('и открывает acp/*, если её тест не прошёл', () {
      _fixture('a', roles: null);
      _results.put(_agentRun, jsonReport(const [T('acp/other')]));
      expect(_verdicts('`acp/*`').single.status, EvidenceStatus.notRun);
    });
  });

  group('неполный и упавший отчёт обязательного источника', () {
    const header =
        '{"type":"suite","suite":{"id":0,"platform":"vm","path":"test/a_test.dart"}}\n'
        '{"type":"testStart","test":{"id":1,"name":"acp/a","suiteID":0,'
        '"groupIDs":[],"metadata":{"skip":false,"skipReason":null}}}\n';
    const done =
        '{"type":"testDone","testID":1,"result":"success","skipped":false,'
        '"hidden":false}\n';

    EvidenceStatus run(String report, {String? reason}) {
      _fixture('a');
      _results.put(_agentRun, report);
      final v = _verdicts('`acp/a`').single;
      if (reason != null) expect(v.reason, contains(reason));
      return v.status;
    }

    test('оборванный отчёт без события done — failed', () {
      expect(
        run('$header$done', reason: 'report incomplete'),
        EvidenceStatus.failed,
      );
    });

    test('error после testDone делает тест упавшим', () {
      const late =
          '{"type":"error","testID":1,"error":"late","stackTrace":"",'
          '"isFailure":false}\n';
      expect(
        run('$header$done$late{"type":"done","success":true}\n'),
        EvidenceStatus.failed,
      );
    });

    test('отчёт без done, где упал чужой тест, а acp/a прошёл — failed', () {
      _fixture('a');
      _results.put(
        _agentRun,
        '$header$done'
        '{"type":"testStart","test":{"id":2,"name":"other","suiteID":0,'
        '"groupIDs":[],"metadata":{"skip":false,"skipReason":null}}}\n'
        '{"type":"testDone","testID":2,"result":"failure","skipped":false,'
        '"hidden":false}\n',
      );
      final v = _verdicts('`acp/a`').single;
      expect(v.status, EvidenceStatus.failed);
      expect(v.reason, 'report incomplete');
    });

    test('done.success == false без объясняющего теста — failed', () {
      expect(
        run(
          '$header$done{"type":"done","success":false}\n',
          reason: 'suite reported failure',
        ),
        EvidenceStatus.failed,
      );
    });

    test('done.success == false при упавшем другом тесте не винит acp/a', () {
      _fixture('a');
      _results.put(
        _agentRun,
        jsonReport([
          const T('acp/a'),
          const T('other', result: 'failure'),
        ], success: false),
      );
      expect(_verdicts('`acp/a`').single.status, EvidenceStatus.pass);
    });

    test('не загрузившийся набор conformance — failed', () {
      _fixture('a');
      _results.put(
        _agentRun,
        jsonReport(
          const [T('acp/a')],
          success: false,
          failedLoads: const [
            'packages/dart/codelab_agent_acp/test/conformance_test.dart',
          ],
        ),
      );
      expect(_verdicts('`acp/a`').single.status, EvidenceStatus.failed);
    });

    test('падение набора клиентского корпуса — failed', () {
      _fixture('a');
      _results
        ..put(_agentRun, jsonReport(const [T('acp/a')]))
        ..put(
          'dart/codelab_client_acp.conformance.json',
          jsonReport(
            const [],
            success: false,
            failedLoads: const [
              'packages/dart/codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart',
            ],
          ),
        );
      expect(_verdicts('`acp/a`').single.status, EvidenceStatus.failed);
    });
  });

  group('allowedSkips настоящего перечня', () {
    // Точные строки причин из кода тестов и драйверов: перечень
    // сверяется полным совпадением, подстрока чужой причины не проходит.
    bool allowed(String text, {bool name = false}) =>
        allowedSkips.any((a) => a.onName == name && a.matches(text));

    test('причины из кода драйверов и тестов совпадают', () {
      for (final reason in const [
        // agent_connector.dart: setup.mcp.
        'setup.mcp cannot be passed to the agent process',
        // agent_connector.dart: встроенный агент.
        'embedded: setup.config cannot be played by the embedded agent',
        'embedded: setup.sessions, setup.web cannot be played by the '
            'embedded agent',
        'embedded: setup.profile "x" cannot be played by the embedded agent',
        // agent_conformance.dart: транспортные фикстуры.
        'acp/ws-auth-bearer-required has setup.transport: the transport '
            'driver plays it against the binary process',
        'acp/stdio-framing-large-line has setup.transport: the transport '
            'driver of codelab-agent plays it against the binary process',
        // agent_conformance.dart, client_conformance.dart: роли.
        'acp/tool-kind-unknown-tolerated has roles [client] without "agent"',
        'acp/session-list-cwd-filter has roles [agent] without "client"',
        // cli e2e_agent.dart: встроенный агент в profiles.json.
        'the embedded agent is built in and cannot be stored in profiles.json',
      ]) {
        expect(allowed(reason), isTrue, reason: reason);
      }
    });

    test('заметки app в имени теста совпадают (пропуск без причины)', () {
      for (final name in const [
        'fs flow [skipped: the embedded agent runs files and commands '
            'locally, not through ACP fs/* and terminal/*]',
        'stdio flow [skipped: the embedded agent starts no stdio child '
            'process]',
      ]) {
        expect(allowed(name, name: true), isTrue, reason: name);
        expect(allowed(name), isFalse, reason: 'не как причина: $name');
      }
    });

    test('произвольная и чужая причина не разрешены', () {
      for (final reason in const [
        'flaky on CI',
        'TODO setup.mcp cannot be passed to the agent process',
        'setup.mcp cannot be passed to the agent process, retry later',
        'x has setup.transport: the transport driver plays it; also broken\n'
            'acp/y has roles [client] without "agent"',
        'the embedded agent is built in and cannot be stored in profiles.json'
            ' (todo)',
      ]) {
        expect(allowed(reason), isFalse, reason: reason);
      }
    });
  });

  group('meta.json отчётов app по режимам', () {
    test('итог печатает app/<режим>/meta.json', () {
      _results.put('meta.json', '{"run_attempt":1}');
      final app = Tree('parity_edge_app_')
        ..put('app/dart-agent/meta.json', '{"commit":"abc"}')
        ..put('app/embedded/meta.json', '{"commit":"def"}');
      addTearDown(app.dispose);
      final lines = renderVerdictReport(
        resultsDir: _results.path,
        verdicts: const [],
        appResultsDir: app.path,
      );
      expect(lines, contains('app dart-agent: {"commit":"abc"}'));
      expect(lines, contains('app embedded: {"commit":"def"}'));
    });
  });
}
