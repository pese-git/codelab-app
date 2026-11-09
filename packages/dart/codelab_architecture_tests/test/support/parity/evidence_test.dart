// Модульный тест доказательств строк матрицы на временном дереве (задача 1.3
// change `switch-default-agent-to-dart`; testing-quality «Проверка доказательств
// матрицы целей»; design.md, D3–D4). Свой корень репозитория во временном
// каталоге: настоящая матрица и настоящие тесты не нужны.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'evidence.dart';
import 'matrix_parser.dart';

late Directory _root;

void _write(String relative, [String content = '']) {
  final file = File(p.join(_root.path, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void _fixture(String id) =>
    _write('packages/dart/codelab_acp_testing/fixtures/acp/$id.json', '{}');

MatrixRow _row(String id, String criterion) =>
    MatrixRow(id: id, line: 1, criterion: criterion);

ExistenceReport _check(
  List<MatrixRow> rows, {
  List<KnownGap> knownGaps = const [],
}) =>
    checkEvidenceExists(rows: rows, repoRoot: _root.path, knownGaps: knownGaps);

void main() {
  setUp(() {
    _root = Directory.systemTemp.createTempSync('parity_evidence_');
  });
  tearDown(() => _root.deleteSync(recursive: true));

  group('извлечение доказательств из ячейки', () {
    test('берёт все виды, пропускает чужие фрагменты и повтор', () {
      final evidence = extractEvidence(
        'закрыто change x: `acp/a`, `cli/b`, `core/c`, '
        '`app:fs_flow_test.dart`, '
        '`packages/dart/codelab_agent_core/test/w_test.dart`, '
        '`apps/codelab_cli/test/y_test.dart`, `acp/*`, `app:*`, '
        '`acp/a` (повтор), `--flag`, `kind: think`, `AgentRuntime`',
      );

      expect(evidence.map((e) => (e.kind, e.label)), [
        (EvidenceKind.acp, 'acp/a'),
        (EvidenceKind.cli, 'cli/b'),
        (EvidenceKind.core, 'core/c'),
        (EvidenceKind.app, 'app:fs_flow_test.dart'),
        (
          EvidenceKind.testFile,
          'packages/dart/codelab_agent_core/test/w_test.dart',
        ),
        (EvidenceKind.testFile, 'apps/codelab_cli/test/y_test.dart'),
        (EvidenceKind.allAcp, 'acp/*'),
        (EvidenceKind.allApp, 'app:*'),
      ]);
    });

    test('ячейка без доказательств даёт пустой список', () {
      expect(extractEvidence('нет; спецификация — §9.2'), isEmpty);
    });
  });

  group('существование доказательств', () {
    test('Нет файла фикстуры: R-08 acp/slash-help missing', () {
      final report = _check([_row('R-08', '`acp/slash-help`')]);

      expect(report.failures, ['R-08 acp/slash-help missing']);
    });

    test('фикстура на месте — проверка проходит', () {
      _fixture('slash-help');

      final report = _check([_row('R-08', '`acp/slash-help`')]);

      expect(report.failures, isEmpty);
      expect(report.knownGapLines, isEmpty);
    });

    test('строка Must без единого доказательства — missing', () {
      final report = _check([_row('R-01', 'закрыто change x')]);

      expect(report.failures, hasLength(1));
      expect(
        report.failures.single,
        allOf(startsWith('R-01'), contains('missing')),
      );
    });

    test('app:<файл> и путь файла теста ищутся по файловой системе', () {
      _write('apps/codelab_desktop/integration_test/fs_flow_test.dart');
      _write('packages/dart/codelab_agent_core/test/w_test.dart');

      final report = _check([
        _row(
          'T-01',
          '`app:fs_flow_test.dart`, `app:gone_test.dart`, '
              '`packages/dart/codelab_agent_core/test/w_test.dart`, '
              '`packages/dart/codelab_agent_core/test/gone_test.dart`',
        ),
      ]);

      expect(report.failures, [
        'T-01 app:gone_test.dart missing',
        'T-01 packages/dart/codelab_agent_core/test/gone_test.dart missing',
      ]);
    });

    test('строка закрыта, только если закрыто каждое доказательство', () {
      _fixture('a');

      final report = _check([_row('R-02', '`acp/a`, `acp/b`')]);

      expect(report.failures, ['R-02 acp/b missing']);
    });
  });

  group('cli/<id> и core/<id>: поиск по первому литералу test( и group(', () {
    void cli(String source) =>
        _write('apps/codelab_cli/test/e2e/flow_test.dart', source);

    test('находит test( и group( с id в начале литерала', () {
      cli('''
void main() {
  test('cli/plain', () {});
  test("cli/colon: details", () {});
  test('cli/spaced details', () {});
  group('cli/grouped', () {});
  test(
    'cli/multiline: a',
    () {},
  );
}
''');

      final report = _check([
        _row(
          'U-01',
          '`cli/plain`, `cli/colon`, `cli/spaced`, `cli/grouped`, '
              '`cli/multiline`',
        ),
      ]);

      expect(report.failures, isEmpty);
    });

    test('литерал, разбитый на соседние, склеивается', () {
      cli('''
void main() {
  test('cli/long-' 'name: tail', () {});
}
''');

      expect(_check([_row('U-02', '`cli/long-name`')]).failures, isEmpty);
    });

    test('Id только в комментарии: core/x — missing', () {
      _write('packages/dart/codelab_agent_core/test/a_test.dart', '''
// core/x
/// core/x в doc-комментарии
void main() {
  test('other', () {
    // core/x
  });
}
''');

      final report = _check([_row('C-01', '`core/x`')]);

      expect(report.failures, ['C-01 core/x missing']);
    });

    test('id не в первом литерале и чужое продолжение id не считаются', () {
      cli('''
void main() {
  test('other', () { print('cli/inner'); });
  test('cli/prefix-longer', () {});
  test('cli/with_suffix', () {});
}
''');

      final report = _check([
        _row('U-03', '`cli/inner`, `cli/prefix`, `cli/with`'),
      ]);

      expect(report.failures, [
        'U-03 cli/inner missing',
        'U-03 cli/prefix missing',
        'U-03 cli/with missing',
      ]);
    });

    test(
      'core/<id> ищется в тестах всех пакетов агента и apps/codelab_agent',
      () {
        const dirs = [
          'packages/dart/codelab_agent_core/test',
          'packages/dart/codelab_agent_io/test',
          'packages/dart/codelab_agent_acp/test',
          'packages/dart/codelab_agent_mcp/test',
          'packages/dart/codelab_embedded/test',
          'apps/codelab_agent/test',
        ];
        for (final (i, dir) in dirs.indexed) {
          _write(
            '$dir/nested/t_test.dart',
            "void main() { test('core/n$i', () {}); }",
          );
        }

        final report = _check([
          _row(
            'C-02',
            [for (var i = 0; i < dirs.length; i++) '`core/n$i`'].join(', '),
          ),
        ]);

        expect(report.failures, isEmpty);
      },
    );

    test('cli/<id> не ищется вне apps/codelab_cli/test/e2e', () {
      _write(
        'apps/codelab_cli/test/unit_test.dart',
        "void main() { test('cli/elsewhere', () {}); }",
      );

      final report = _check([_row('U-04', '`cli/elsewhere`')]);

      expect(report.failures, ['U-04 cli/elsewhere missing']);
    });
  });

  // Задача 2.16 (D3, уточнение 2026-11-10): id засчитывается, только если он
  // начинает полное имя теста в отчёте, то есть первый литерал `test(` или
  // `group(` не вложен в другой `group(`. Иначе полное имя начинается с имени
  // внешней группы, и тест в статусе получает `not-run` (E-01).
  group('id во вложенном test( или group( не засчитывается (D3)', () {
    void core(String source) =>
        _write('packages/dart/codelab_agent_core/test/a_test.dart', source);

    test('Id во вложенном тесте: test внутри чужого group — missing', () {
      core('''
void main() {
  group('other', () {
    test('core/x: nested', () {});
  });
}
''');

      expect(_check([_row('C-01', '`core/x`')]).failures, [
        'C-01 core/x missing',
      ]);
    });

    test('Id во внешней группе: group на верхнем уровне main — существует', () {
      core('''
void main() {
  group('core/x', () {
    test('y', () {});
    test('z', () {});
  });
}
''');

      expect(_check([_row('C-01', '`core/x`')]).failures, isEmpty);
    });

    test('вложенная группа внутри группы с id — существует: полное имя '
        'начинается с id', () {
      core('''
void main() {
  group('core/x', () {
    group('inner', () {
      test('y', () {});
    });
  });
}
''');

      expect(_check([_row('C-01', '`core/x`')]).failures, isEmpty);
    });

    test('вложенный group с id внутри чужой группы — missing', () {
      core('''
void main() {
  group('other', () {
    group('core/x', () {
      test('y', () {});
    });
  });
}
''');

      expect(_check([_row('C-01', '`core/x`')]).failures, [
        'C-01 core/x missing',
      ]);
    });

    test('test на верхнем уровне main — существует, в том числе в цикле for '
        'и в локальной функции main', () {
      core('''
void main() {
  test('core/x', () {});
  for (final n in [1, 2]) {
    test('core/y: \$n', () {});
  }
  void local() {
    test('core/z', () {});
  }
  local();
}
''');

      expect(
        _check([_row('C-01', '`core/x`, `core/y`, `core/z`')]).failures,
        isEmpty,
      );
    });

    test('вложенный и верхний уровень вместе: засчитывается верхний', () {
      core('''
void main() {
  group('other', () {
    test('core/x: nested', () {});
  });
  test('core/x: top level', () {});
}
''');

      expect(_check([_row('C-01', '`core/x`')]).failures, isEmpty);
    });

    test('cli/<id> подчиняется тому же правилу', () {
      _write('apps/codelab_cli/test/e2e/flow_test.dart', '''
void main() {
  group('other', () {
    test('cli/x: nested', () {});
  });
}
''');

      expect(_check([_row('U-01', '`cli/x`')]).failures, [
        'U-01 cli/x missing',
      ]);
    });
  });

  group('храповик knownGaps', () {
    const gap = KnownGap('R-08', 'acp/slash-help', '2.1');

    test('Известный пробел: проходит и печатает known gap', () {
      final report = _check(
        [_row('R-08', '`acp/slash-help`')],
        knownGaps: [gap],
      );

      expect(report.failures, isEmpty);
      expect(report.knownGapLines, [
        allOf(startsWith('known gap: R-08 acp/slash-help'), contains('2.1')),
      ]);
    });

    test('Устаревшая запись knownGaps: фикстура есть — тест падает', () {
      _fixture('slash-help');

      final report = _check(
        [_row('R-08', '`acp/slash-help`')],
        knownGaps: [gap],
      );

      expect(report.failures, [
        startsWith('stale known gap: R-08 acp/slash-help'),
      ]);
      expect(report.knownGapLines, isEmpty);
    });

    test('пробел вне списка по-прежнему роняет проверку', () {
      final report = _check(
        [_row('R-08', '`acp/slash-help`, `acp/slash-mode-plan`')],
        knownGaps: [gap],
      );

      expect(report.failures, ['R-08 acp/slash-mode-plan missing']);
      expect(report.knownGapLines, hasLength(1));
    });
  });
}
