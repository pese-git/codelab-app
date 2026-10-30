import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';

/// Проверка определений агентов ядром (agent-definitions «Формат определения и
/// проверка», «Каталоги определений агентов и доверие»; design.md change
/// `add-agent-project-files`, D3, D10; CFG-6, R-15).
void main() {
  final catalog = FixedModelCatalog([testModel]);

  /// Файл определения, каким его отдаёт хост: frontmatter уже разобран.
  MarkdownFile md(
    String file, {
    String body = 'You review code.',
    Map<String, Object?>? frontmatter = const {
      'name': 'reviewer',
      'description': 'Reviews changes',
    },
    Map<String, ConfigPosition> positions = const {},
    ExtensionScope scope = ExtensionScope.user,
    String dir = '/home/.codelab/agents',
  }) => MarkdownFile(
    path: '$dir/$file.md',
    scope: scope,
    body: body,
    bodyLine: 5,
    frontmatter: frontmatter == null
        ? null
        : ConfigTree(
            kind: ConfigLayerKind.user,
            source: '$dir/$file.md',
            values: frontmatter,
            positions: positions,
          ),
  );

  AgentParseResult parse(List<MarkdownFile> files) =>
      parseAgentDefinitions(files, models: catalog);

  List<String> codes(AgentParseResult r) => [
    for (final d in r.diagnostics) d.code,
  ];

  group('a valid definition', () {
    test('takes all fields from the frontmatter', () {
      final result = parse([
        md(
          'reviewer',
          body: 'Be strict.',
          frontmatter: {
            'name': 'reviewer',
            'description': 'Reviews changes',
            'model': 'test/model-1',
            'mode': 'plan',
            'tools': ['read', 'search', 'mcp__github__*'],
            'scope': 'session',
          },
        ),
      ]);

      final a = result.agents.single;
      expect(a.name, 'reviewer');
      expect(a.description, 'Reviews changes');
      expect(a.prompt, 'Be strict.');
      expect(a.model?.id, 'model-1');
      expect(a.mode, ModeId.plan);
      expect(a.tools, ['read', 'search', 'mcp__github__*']);
      expect(a.scope, AgentScope.session);
      expect(a.source, '/home/.codelab/agents/reviewer.md');
      expect(result.diagnostics, isEmpty);
    });

    test('optional fields default: scope both, the rest null', () {
      final a = parse([md('reviewer')]).agents.single;

      expect(a.scope, AgentScope.both);
      expect(a.model, isNull);
      expect(a.mode, isNull);
      expect(a.tools, isNull);
    });

    test('an empty tools list is allowed and allows nothing', () {
      final a = parse([
        md(
          'reviewer',
          frontmatter: {
            'name': 'reviewer',
            'description': 'd',
            'tools': <Object?>[],
          },
        ),
      ]).agents.single;

      expect(a.tools, isEmpty);
      expect(a.allowsTool('read'), isFalse);
    });

    test('tool patterns match by name and by prefix', () {
      final a = parse([
        md(
          'reviewer',
          frontmatter: {
            'name': 'reviewer',
            'description': 'd',
            'tools': ['read', 'mcp__github__*'],
          },
        ),
      ]).agents.single;

      expect(a.allowsTool('read'), isTrue);
      expect(a.allowsTool('reader'), isFalse);
      expect(a.allowsTool('mcp__github__create_issue'), isTrue);
      expect(a.allowsTool('mcp__gitlab__x'), isFalse);
    });

    test('without tools every tool is allowed', () {
      final a = parse([md('reviewer')]).agents.single;

      expect(a.allowsTool('anything'), isTrue);
    });

    test('definitions come in the byte order of names', () {
      final result = parse([
        md('b', frontmatter: {'name': 'b-agent', 'description': 'd'}),
        md('a', frontmatter: {'name': 'a-agent', 'description': 'd'}),
      ]);

      expect([for (final a in result.agents) a.name], ['a-agent', 'b-agent']);
    });
  });

  group('errors', () {
    void expectSkipped(
      String title,
      MarkdownFile file,
      String code, {
      ConfigPosition? at,
    }) {
      test(title, () {
        final result = parse([file]);

        expect(result.agents, isEmpty);
        final d = result.diagnostics.single;
        expect(d.code, code);
        expect(d.level, DiagnosticLevel.error);
        expect(d.path, file.path);
        if (at != null) {
          expect([d.line, d.column], [at.line, at.column]);
        }
      });
    }

    expectSkipped(
      'an unknown key',
      md(
        'a',
        frontmatter: {'name': 'a', 'description': 'd', 'color': 'red'},
        positions: {'color': const ConfigPosition(4, 1)},
      ),
      'unknown_key',
      at: const ConfigPosition(4, 1),
    );
    expectSkipped(
      'an empty body',
      md('a', body: '  \n', frontmatter: {'name': 'a', 'description': 'd'}),
      'empty_body',
    );
    expectSkipped(
      'a body over 32 KiB',
      md(
        'a',
        body: 'x' * (32 * 1024 + 1),
        frontmatter: {'name': 'a', 'description': 'd'},
      ),
      'too_large',
    );
    expectSkipped(
      'a name with a capital letter',
      md(
        'a',
        frontmatter: {'name': 'Reviewer', 'description': 'd'},
        positions: {'name': const ConfigPosition(2, 1)},
      ),
      'invalid_value',
      at: const ConfigPosition(2, 1),
    );
    expectSkipped(
      'the reserved name default',
      md('a', frontmatter: {'name': 'default', 'description': 'd'}),
      'invalid_value',
    );
    expectSkipped(
      'a name longer than 48 characters',
      md('a', frontmatter: {'name': 'a' * 49, 'description': 'd'}),
      'invalid_value',
    );
    expectSkipped(
      'no name',
      md('a', frontmatter: {'description': 'd'}),
      'invalid_value',
    );
    expectSkipped(
      'no description',
      md('a', frontmatter: {'name': 'a'}),
      'invalid_value',
    );
    expectSkipped(
      'a description over 200 characters',
      md('a', frontmatter: {'name': 'a', 'description': 'd' * 201}),
      'invalid_value',
    );
    expectSkipped(
      'no frontmatter at all',
      md('a', frontmatter: null),
      'invalid_value',
    );
    expectSkipped(
      'mode autopilot (CFG-4)',
      md(
        'a',
        frontmatter: {'name': 'a', 'description': 'd', 'mode': 'autopilot'},
        positions: {'mode': const ConfigPosition(3, 1)},
      ),
      'invalid_value',
      at: const ConfigPosition(3, 1),
    );
    expectSkipped(
      'a mode synonym',
      md('a', frontmatter: {'name': 'a', 'description': 'd', 'mode': 'code'}),
      'invalid_value',
    );
    expectSkipped(
      'a model outside the catalog',
      md(
        'a',
        frontmatter: {'name': 'a', 'description': 'd', 'model': 'x/unknown'},
      ),
      'invalid_value',
    );
    expectSkipped(
      'a star in the middle of a tool pattern',
      md(
        'a',
        frontmatter: {
          'name': 'a',
          'description': 'd',
          'tools': ['re*d'],
        },
      ),
      'invalid_value',
    );
    expectSkipped(
      'a tool that is not a string',
      md(
        'a',
        frontmatter: {
          'name': 'a',
          'description': 'd',
          'tools': [1],
        },
      ),
      'invalid_value',
    );
    expectSkipped(
      'tools that is not a list',
      md('a', frontmatter: {'name': 'a', 'description': 'd', 'tools': 'read'}),
      'invalid_value',
    );
    expectSkipped(
      'an unknown scope',
      md('a', frontmatter: {'name': 'a', 'description': 'd', 'scope': 'all'}),
      'invalid_value',
    );

    test('every problem of a file is reported, one file does not stop '
        'the others', () {
      final result = parse([
        md(
          'bad',
          frontmatter: {
            'name': 'Bad',
            'description': 'd',
            'color': 'red',
            'mode': 'autopilot',
          },
        ),
        md('good', frontmatter: {'name': 'good', 'description': 'd'}),
      ]);

      expect([for (final a in result.agents) a.name], ['good']);
      expect(
        codes(result),
        unorderedEquals(['invalid_value', 'unknown_key', 'invalid_value']),
      );
    });

    test('messages never contain values from the file', () {
      final result = parse([
        md(
          'a',
          frontmatter: {
            'name': 'sk-test-secret',
            'description': 'd',
            'mode': 'sk-test-secret',
            'color': 'sk-test-secret',
          },
        ),
      ]);

      for (final d in result.diagnostics) {
        expect(d.message, isNot(contains('sk-test-secret')));
      }
    });
  });

  group('names', () {
    test('two files with one name in one directory are both skipped, each '
        'diagnostic names both paths', () {
      final result = parse([
        md('one', frontmatter: {'name': 'twin', 'description': 'd'}),
        md('two', frontmatter: {'name': 'twin', 'description': 'd'}),
      ]);

      expect(result.agents, isEmpty);
      expect(codes(result), ['duplicate', 'duplicate']);
      for (final d in result.diagnostics) {
        expect(d.level, DiagnosticLevel.error);
        expect(d.message, contains('/home/.codelab/agents/one.md'));
        expect(d.message, contains('/home/.codelab/agents/two.md'));
      }
    });

    test('a project definition replaces the user one of the same name, '
        'whatever the input order', () {
      final user = md(
        'reviewer',
        frontmatter: {'name': 'reviewer', 'description': 'from user'},
      );
      final project = md(
        'reviewer',
        frontmatter: {'name': 'reviewer', 'description': 'from project'},
        scope: ExtensionScope.project,
        dir: '/repo/.codelab/agents',
      );

      for (final files in [
        [user, project],
        [project, user],
      ]) {
        final result = parse(files);

        expect(result.agents.single.description, 'from project');
        final d = result.diagnostics.single;
        expect(d.code, 'shadowed');
        expect(d.level, DiagnosticLevel.info);
        expect(d.path, user.path);
      }
    });

    test('a user definition survives an invalid project one of its name', () {
      final result = parse([
        md('reviewer'),
        md(
          'reviewer',
          frontmatter: {'name': 'reviewer', 'description': 'd', 'color': 'x'},
          scope: ExtensionScope.project,
          dir: '/repo/.codelab/agents',
        ),
      ]);

      expect(result.agents.single.source, '/home/.codelab/agents/reviewer.md');
      expect(codes(result), ['unknown_key']);
    });
  });

  test('scope subagent is loaded but absent from the session list', () {
    final result = parse([
      md(
        'task',
        frontmatter: {
          'name': 'task-only',
          'description': 'd',
          'scope': 'subagent',
        },
      ),
      md('both', frontmatter: {'name': 'both-agent', 'description': 'd'}),
    ]);

    expect(
      [for (final a in result.agents) a.name],
      ['both-agent', 'task-only'],
    );
    expect([for (final a in result.sessionAgents) a.name], ['both-agent']);
    expect(result.diagnostics, isEmpty);
  });
}
