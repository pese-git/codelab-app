import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/src/project/frontmatter.dart';
import 'package:test/test.dart';

/// Одна попытка починки YAML frontmatter навыка (agent-skills «Формат
/// SKILL.md и мягкая проверка», сценарии «Двоеточие без кавычек»,
/// «Починка сохраняет обратную косую и кавычки», «Совсем нечитаемый YAML»;
/// design.md change `add-agent-skills`, D4).
///
/// Фиксируемый API: `readMarkdownFile(text, path:, scope:, repairYaml: true)`
/// (по умолчанию `false`: шаблоны и определения агентов остаются строгими) и
/// `MarkdownRead.repaired` — «разбор удался после починки»; диагностику
/// `yaml_repaired` по признаку даёт ядро, не хост.
void main() {
  const path = '/h/skills/pdf/SKILL.md';

  MarkdownRead read(String text, {bool repair = true}) => readMarkdownFile(
    text,
    path: path,
    scope: ExtensionScope.user,
    repairYaml: repair,
  );

  group('a value with ": " without quotes', () {
    test('scenario "Двоеточие без кавычек": repaired, value intact', () {
      final r = read(
        '---\nname: pdf\n'
        'description: Use this skill when: the user asks about PDFs\n'
        '---\nBody\n',
      );

      expect(r.diagnostics, isEmpty);
      expect(r.repaired, isTrue);
      expect(r.file!.frontmatter!.values, {
        'name': 'pdf',
        'description': 'Use this skill when: the user asks about PDFs',
      });
      expect(r.file!.body, 'Body\n');
    });

    test('scenario "Починка сохраняет обратную косую и кавычки": C:\\temp, '
        '" and \' stay as they are', () {
      final r = read(
        '---\n'
        'description: Use when: files are under C:\\temp and named "it\'s"\n'
        '---\nBody',
      );

      expect(r.repaired, isTrue);
      expect(
        r.file!.frontmatter!.values['description'],
        'Use when: files are under C:\\temp and named "it\'s"',
      );
    });

    test('a single quote is doubled inside the single-quoted string', () {
      final r = read("---\ndescription: It's: fine\n---\n");

      expect(r.repaired, isTrue);
      expect(r.file!.frontmatter!.values['description'], "It's: fine");
    });

    test('positions stay in the coordinates of the original file', () {
      final r = read('---\nname: pdf\ndescription: a: b\nlicense: MIT\n---\n');

      final tree = r.file!.frontmatter!;
      expect(tree.positions['license'], const ConfigPosition(4, 1));
      expect(tree.positions['description']!.line, 3);
      expect(r.file!.bodyLine, 6);
    });

    test('several broken lines are repaired by the same single attempt', () {
      final r = read(
        '---\ndescription: a: b\ncompatibility: needs: git\nname: x\n---\n',
      );

      expect(r.repaired, isTrue);
      expect(r.file!.frontmatter!.values, {
        'description': 'a: b',
        'compatibility': 'needs: git',
        'name': 'x',
      });
    });
  });

  group('what repair does not touch', () {
    test('a valid frontmatter is not repaired', () {
      final r = read('---\nname: pdf\ndescription: Plain text\n---\nB');

      expect(r.repaired, isFalse);
      expect(r.diagnostics, isEmpty);
    });

    test('an already quoted value keeps its content', () {
      final r = read(
        '---\ndescription: a: b\ntitle: "x: y"\nnote: \'p: q\'\n---\n',
      );

      expect(r.repaired, isTrue);
      expect(r.file!.frontmatter!.values, {
        'description': 'a: b',
        'title': 'x: y',
        'note': 'p: q',
      });
    });

    test('a nested structure is not rewritten: a broken value inside a map '
        'stays an error', () {
      final r = read('---\nname: pdf\nmetadata:\n  note: a: b\n---\nBody');

      expect(r.file, isNull);
      expect(r.repaired, isFalse);
      expect(r.diagnostics.single.level, DiagnosticLevel.error);
      expect(r.diagnostics.single.line, 4);
    });

    test('block scalars and lists are left as they are', () {
      final r = read(
        '---\ndescription: x: y\nmetadata:\n  codelab-operative: |\n'
        '    Line: one\n    Line two\ntags:\n  - a\n  - b\n---\n',
      );

      expect(r.repaired, isTrue);
      final values = r.file!.frontmatter!.values;
      expect(values['description'], 'x: y');
      expect(values['tags'], ['a', 'b']);
      expect(
        (values['metadata']! as Map)['codelab-operative'],
        'Line: one\nLine two\n',
      );
    });
  });

  group('failure', () {
    test('scenario "Совсем нечитаемый YAML": an unclosed flow sequence is an '
        'error with the position in the original file', () {
      final r = read('---\nname: pdf\ntags: [a, b\n---\nBody');

      expect(r.file, isNull);
      expect(r.repaired, isFalse);
      final d = r.diagnostics.single;
      expect(d.level, DiagnosticLevel.error);
      expect(d.path, path);
      expect(d.line, isNotNull);
      expect(d.line, greaterThanOrEqualTo(3));
      expect(d.column, isNotNull);
    });

    test('repair is attempted once: a file still broken after it is an '
        'error even if another line was repaired', () {
      final r = read('---\ndescription: a: b\ntags: [a, b\n---\n');

      expect(r.file, isNull);
      expect(r.diagnostics.single.level, DiagnosticLevel.error);
      expect(r.diagnostics.single.line, 3);
    });

    test('the message has no fragment of the file', () {
      final r = read('---\nname: sk-test-secret-value: [\n---\nBody');

      expect(r.file, isNull);
      expect(
        [for (final d in r.diagnostics) d.message].join('\n'),
        isNot(contains('sk-test-secret')),
      );
    });
  });

  group('without repairYaml (templates and agent definitions)', () {
    test('the same text stays a syntax error, repaired is false', () {
      final r = read(
        '---\ndescription: Use when: the user asks\n---\nBody',
        repair: false,
      );

      expect(r.file, isNull);
      expect(r.repaired, isFalse);
      expect(r.diagnostics.single.level, DiagnosticLevel.error);
      expect(r.diagnostics.single.line, 2);
    });

    test('the default is strict', () {
      final r = readMarkdownFile(
        '---\ndescription: Use when: the user asks\n---\nBody',
        path: path,
        scope: ExtensionScope.user,
      );

      expect(r.file, isNull);
    });
  });
}
