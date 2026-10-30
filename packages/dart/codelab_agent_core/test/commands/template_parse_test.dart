import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Проверка шаблонов команд ядром (agent-slash-commands «Формат шаблона и
/// проверка», «Резервные имена команд», «Список команд сессии»; design.md
/// change `add-agent-project-files`, D3, D7).
void main() {
  /// Файл шаблона, каким его отдаёт хост: frontmatter уже разобран.
  MarkdownFile md(
    String name, {
    String body = 'Do the thing.',
    Map<String, Object?>? frontmatter,
    Map<String, ConfigPosition> positions = const {},
    ExtensionScope scope = ExtensionScope.user,
    String dir = '/home/.codelab/prompts',
  }) => MarkdownFile(
    path: '$dir/$name.md',
    scope: scope,
    body: body,
    bodyLine: frontmatter == null ? 1 : 4,
    frontmatter: frontmatter == null
        ? null
        : ConfigTree(
            kind: ConfigLayerKind.user,
            source: '$dir/$name.md',
            values: frontmatter,
            positions: positions,
          ),
  );

  TemplateParseResult parse(List<MarkdownFile> files) =>
      parseCommandTemplates(files);

  List<String> codes(TemplateParseResult r) => [
    for (final d in r.diagnostics) d.code,
  ];

  group('a valid template', () {
    test('takes the name from the file name and the fields from the '
        'frontmatter', () {
      final result = parse([
        md(
          'review',
          body: 'Review it.',
          frontmatter: {
            'description': 'Code review',
            'argument-hint': '<path>',
          },
        ),
      ]);

      final t = result.templates.single;
      expect(t.name, 'review');
      expect(t.description, 'Code review');
      expect(t.argumentHint, '<path>');
      expect(t.body, 'Review it.');
      expect(t.scope, ExtensionScope.user);
      expect(result.diagnostics, isEmpty);
    });

    test('has no frontmatter requirement', () {
      final result = parse([md('plain', body: 'Hello')]);

      expect(result.templates.single.argumentHint, isNull);
      expect(result.diagnostics, isEmpty);
    });

    test('takes the description from the first non-empty body line', () {
      final result = parse([md('t', body: '\n  \n  First line  \nSecond\n')]);

      expect(result.templates.single.description, 'First line');
    });

    test('cuts the description taken from the body at 200 characters', () {
      final result = parse([md('t', body: 'x' * 300)]);

      expect(result.templates.single.description, 'x' * 200);
    });

    test('accepts a body of exactly 32 KiB', () {
      final result = parse([md('t', body: 'a' * 32768)]);

      expect(result.templates, hasLength(1));
    });
  });

  group('frontmatter keys', () {
    test('an unknown key is an error and the file is skipped', () {
      final result = parse([
        md(
          'review',
          frontmatter: {'description': 'ok', 'model': 'x'},
          positions: {'model': const ConfigPosition(3, 1)},
        ),
      ]);

      expect(result.templates, isEmpty);
      final d = result.diagnostics.single;
      expect(d.code, 'unknown_key');
      expect(d.level, DiagnosticLevel.error);
      expect(d.path, '/home/.codelab/prompts/review.md');
      expect([d.line, d.column], [3, 1]);
    });

    test('a diagnostic message does not repeat the key value', () {
      final result = parse([
        md('review', frontmatter: {'sk-test-secret': 'v'}),
      ]);

      // Имя ключа задаёт автор файла, поэтому в логи оно не идёт (D14).
      expect(result.diagnostics.single.message, isNot(contains('sk-test')));
    });

    test('description must be a string of 1 to 200 characters', () {
      final result = parse([
        md('a', frontmatter: {'description': ''}),
        md('b', frontmatter: {'description': 'x' * 201}),
        md('c', frontmatter: {'description': 5}),
        md('d', frontmatter: {'description': 'x' * 200}),
      ]);

      expect([for (final t in result.templates) t.name], ['d']);
      expect(codes(result), [
        'invalid_value',
        'invalid_value',
        'invalid_value',
      ]);
    });

    test('argument-hint must be a string of 1 to 80 characters', () {
      final result = parse([
        md('a', frontmatter: {'argument-hint': ''}),
        md('b', frontmatter: {'argument-hint': 'x' * 81}),
        md('c', frontmatter: {'argument-hint': true}),
        md('d', frontmatter: {'argument-hint': 'x' * 80}),
      ]);

      expect([for (final t in result.templates) t.name], ['d']);
      expect(codes(result), [
        'invalid_value',
        'invalid_value',
        'invalid_value',
      ]);
    });
  });

  group('the body', () {
    test('an empty body is an error', () {
      final result = parse([md('t', body: ' \n\t\n')]);

      expect(result.templates, isEmpty);
      expect(result.diagnostics.single.code, 'empty_body');
      expect(result.diagnostics.single.level, DiagnosticLevel.error);
    });

    test('33 KiB is too large', () {
      final result = parse([md('t', body: 'a' * (33 * 1024))]);

      expect(result.templates, isEmpty);
      expect(result.diagnostics.single.code, 'too_large');
    });

    test('the limit counts UTF-8 bytes, not characters', () {
      // 16385 символов по 2 байта = 32770 байт.
      final result = parse([md('t', body: 'я' * 16385)]);

      expect(codes(result), ['too_large']);
    });
  });

  group('names', () {
    test('a name outside ^[a-z0-9][a-z0-9-]{0,63}\$ is a warning', () {
      final result = parse([
        md('Review'),
        md('my_cmd'),
        md('-x'),
        md('a' * 65),
        md('ok-1'),
      ]);

      expect([for (final t in result.templates) t.name], ['ok-1']);
      expect(codes(result), [
        'invalid_name',
        'invalid_name',
        'invalid_name',
        'invalid_name',
      ]);
      expect(
        result.diagnostics.every((d) => d.level == DiagnosticLevel.warning),
        isTrue,
      );
    });

    test('every builtin command name and skill are reserved (SKL-7)', () {
      const names = [
        'compact',
        'mode',
        'model',
        'status',
        'usage',
        'redact',
        'config',
        'mcp',
        'rename',
        'branches',
        'branch',
        'rewind',
        'fork',
        'label',
        'approve',
        'timer',
        'memory',
        'tasks',
        'help',
        'skill',
      ];
      expect(reservedCommandNames, containsAll(names));
      expect(reservedCommandNames, hasLength(names.length));

      final result = parse([for (final n in names) md(n)]);

      expect(result.templates, isEmpty);
      expect(codes(result), everyElement('reserved_name'));
      expect(result.diagnostics, hasLength(names.length));
      expect(
        result.diagnostics.every((d) => d.level == DiagnosticLevel.warning),
        isTrue,
      );
    });

    test('help.md does not load and names its path', () {
      final result = parse([md('help')]);

      expect(result.templates, isEmpty);
      expect(result.diagnostics.single.path, '/home/.codelab/prompts/help.md');
    });
  });

  group('project over user', () {
    final user = md('review', body: 'user body');
    final project = md(
      'review',
      body: 'project body',
      scope: ExtensionScope.project,
      dir: '/repo/.codelab/prompts',
    );

    for (final order in [
      [user, project],
      [project, user],
    ]) {
      test('the project template wins whatever the input order', () {
        final result = parse(order);

        expect(result.templates.single.body, 'project body');
        expect(result.templates.single.scope, ExtensionScope.project);
        final d = result.diagnostics.single;
        expect(d.code, 'shadowed');
        expect(d.level, DiagnosticLevel.info);
        expect(d.path, '/home/.codelab/prompts/review.md');
      });
    }

    test('an invalid project template does not shadow the user one', () {
      final result = parse([
        user,
        md(
          'review',
          body: '',
          scope: ExtensionScope.project,
          dir: '/repo/.codelab/prompts',
        ),
      ]);

      expect(result.templates.single.body, 'user body');
      expect(codes(result), ['empty_body']);
    });
  });

  group('the command list', () {
    test('is sorted by name and carries the description and the source', () {
      final result = parse([
        md('zeta', body: 'Z'),
        md('alpha', body: 'A', frontmatter: {'description': 'Alpha'}),
        md('b2', body: 'B'),
      ]);

      final commands = availableCommands(result.templates);

      expect([for (final c in commands) c.name], ['alpha', 'b2', 'zeta']);
      expect(commands.first.description, 'Alpha');
      expect(
        commands.every((c) => c.source == SlashCommandSource.template),
        isTrue,
      );
    });

    test('inputHint: argument-hint, else "arguments" for placeholders, else '
        'null', () {
      final commands = availableCommands(
        parse([
          md('hinted', body: 'x', frontmatter: {'argument-hint': '<file>'}),
          md('dollar-one', body: 'Review \$1'),
          md('all', body: 'Do \$ARGUMENTS'),
          md('none', body: 'No placeholders'),
          md('escaped', body: 'Costs \$\$1 and \$ARGUMENT and \$0'),
        ]).templates,
      );

      String? hint(String name) =>
          commands.singleWhere((c) => c.name == name).inputHint;
      expect(hint('hinted'), '<file>');
      expect(hint('dollar-one'), 'arguments');
      expect(hint('all'), 'arguments');
      expect(hint('none'), isNull);
      expect(hint('escaped'), isNull);
    });
  });
}
