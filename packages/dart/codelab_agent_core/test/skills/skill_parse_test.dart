import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'skills_support.dart';

/// Разбор и мягкая проверка `SKILL.md` ядром (agent-skills «Формат SKILL.md и
/// мягкая проверка», все сценарии; design.md change `add-agent-skills`, D4;
/// решения Q11, Q14, Q19, Q20, Q32).
///
/// Фиксируемый API: `parseSkills(SkillFiles, SkillsConfig, {PolicyRules})`
/// → `SkillCatalog {skills, diagnostics}`; `SkillFile`, `SkillFiles`,
/// `SkillDefinition {name, description, argumentHint, userInvocable,
/// disableModelInvocation, compatibility, operative, body, dir, scope}`.
void main() {
  const skillPath = '/home/.codelab/skills';

  group('a valid skill', () {
    test('takes name, description and the trimmed body', () {
      final catalog = parse([
        skillFile(
          'notes',
          frontmatter: {
            'name': 'notes',
            'description': 'Takes notes',
            'argument-hint': '<topic>',
          },
          body: '\n\n  Write them down.\r\nSecond line.  \n\n',
        ),
      ]);

      final s = catalog.skills.single;
      expect(s.name, 'notes');
      expect(s.description, 'Takes notes');
      expect(s.argumentHint, '<topic>');
      expect(s.userInvocable, isTrue);
      expect(s.disableModelInvocation, isFalse);
      expect(s.compatibility, isNull);
      expect(s.operative, isEmpty);
      // Обрезанная форма тела: пробелы по краям сняты, `\r\n` -> `\n`
      // (D4, «Обрезка тела»).
      expect(s.body, 'Write them down.\nSecond line.');
      expect(s.dir, '$skillPath/notes');
      expect(s.scope, ExtensionScope.user);
      expect(catalog.diagnostics, isEmpty);
    });

    test('known spec fields give no diagnostic (scenario "Известные поля '
        'без диагностики")', () {
      final catalog = parse([
        validSkill(
          'tools',
          extra: {
            'license': 'MIT',
            'compatibility': 'Requires git',
            'metadata': {'author': 'me', 'version': '1.0'},
            'allowed-tools': 'Bash(git:*) Read',
            'user-invocable': true,
            'disable-model-invocation': false,
            'argument-hint': '[x]',
          },
        ),
      ]);

      expect(catalog.skills.single.compatibility, 'Requires git');
      expect(catalog.diagnostics, isEmpty);
    });
  });

  group('lenient checks: the skill is loaded with a warning', () {
    test('scenario "Свой корень, мягкая проверка": unknown_key with its line, '
        'invalid_name, name_mismatch; loaded as "notes-"', () {
      final catalog = parse([
        skillFile(
          'notes',
          frontmatter: {
            'name': 'notes-',
            'description': 'Notes',
            'color': 'red',
          },
          positions: {'color': const ConfigPosition(4, 1)},
        ),
      ]);

      expect(catalog.skills.single.name, 'notes-');
      expect(
        codes(catalog),
        unorderedEquals(['unknown_key', 'invalid_name', 'name_mismatch']),
      );
      for (final d in catalog.diagnostics) {
        expect(d.level, DiagnosticLevel.warning, reason: d.code);
        expect(d.path, '$skillPath/notes/SKILL.md');
      }
      final unknown = withCode(catalog, 'unknown_key').single;
      expect(unknown.line, 4);
      // Имя ключа во фрагмент файла не входит (D4: фиксированные тексты).
      expect(unknown.message, isNot(contains('color')));
    });

    test('the same lenient rules apply in project roots', () {
      final catalog = parse([
        skillFile(
          'notes',
          root: '/repo/.codelab/skills',
          scope: ExtensionScope.project,
          frontmatter: {'name': 'Notes', 'description': 'Notes'},
        ),
      ]);

      expect(catalog.skills.single.name, 'Notes');
      expect(codes(catalog), contains('invalid_name'));
    });

    test('a name that breaks the spec rule only (uppercase, 65 chars, '
        'double dash): warning invalid_name, loaded', () {
      for (final name in ['Notes', 'a' * 65, 'my--skill']) {
        final catalog = parse([
          skillFile(name, frontmatter: {'name': name, 'description': 'D'}),
        ]);

        expect(catalog.skills.single.name, name, reason: name);
        expect(codes(catalog), ['invalid_name'], reason: name);
        expect(catalog.diagnostics.single.level, DiagnosticLevel.warning);
      }
    });

    test('no name: warning missing_name, the directory name is used', () {
      final catalog = parse([
        skillFile('pdf', frontmatter: {'description': 'PDFs'}),
      ]);

      expect(catalog.skills.single.name, 'pdf');
      expect(codes(catalog), ['missing_name']);
      expect(catalog.diagnostics.single.level, DiagnosticLevel.warning);
    });

    test('a name that differs from the directory: name_mismatch, the name '
        'from the field wins', () {
      final catalog = parse([
        skillFile(
          'dir-name',
          frontmatter: {'name': 'other', 'description': 'D'},
        ),
      ]);

      expect(catalog.skills.single.name, 'other');
      expect(codes(catalog), ['name_mismatch']);
    });

    test('scenario "Длинное описание": 1500 chars -> warning, loaded', () {
      final catalog = parse([
        skillFile(
          'long',
          frontmatter: {'name': 'long', 'description': 'x' * 1500},
        ),
      ]);

      expect(catalog.skills.single.description, hasLength(1500));
      final d = catalog.diagnostics.single;
      expect(d.level, DiagnosticLevel.warning);
      expect(d.code, 'invalid_value');
      expect(
        d.message,
        '"description" is longer than 1024 characters; the catalog shows the '
        'first 1024',
      );
    });

    test('a description of exactly 1024 chars gives no warning', () {
      final catalog = parse([
        skillFile(
          'edge',
          frontmatter: {'name': 'edge', 'description': 'x' * 1024},
        ),
      ]);

      expect(catalog.diagnostics, isEmpty);
    });

    test('scenario "Пустое тело": warning empty_body, loaded', () {
      final catalog = parse([
        skillFile(
          'empty',
          frontmatter: {'name': 'empty', 'description': 'D'},
          body: ' \r\n\n ',
        ),
      ]);

      expect(catalog.skills.single.body, isEmpty);
      expect(codes(catalog), ['empty_body']);
      expect(catalog.diagnostics.single.level, DiagnosticLevel.warning);
    });

    test('argument-hint of a wrong type or length -> warning, no hint', () {
      for (final hint in [5, '', 'h' * 81]) {
        final catalog = parse([
          validSkill('hinted', extra: {'argument-hint': hint}),
        ]);

        expect(catalog.skills.single.argumentHint, isNull, reason: '$hint');
        expect(catalog.diagnostics.single.level, DiagnosticLevel.warning);
        expect(catalog.diagnostics.single.code, 'invalid_value');
        expect(catalog.diagnostics.single.message, contains('"argument-hint"'));
      }
    });

    test('user-invocable and disable-model-invocation of a wrong type -> '
        'warning each, defaults', () {
      final catalog = parse([
        validSkill(
          'flags',
          extra: {'user-invocable': 'yes', 'disable-model-invocation': 1},
        ),
      ]);

      final s = catalog.skills.single;
      expect(s.userInvocable, isTrue);
      expect(s.disableModelInvocation, isFalse);
      expect(catalog.diagnostics, hasLength(2));
      expect(
        catalog.diagnostics.map((d) => d.level),
        everyElement(DiagnosticLevel.warning),
      );
    });

    test('flags set correctly are applied', () {
      final catalog = parse([
        validSkill(
          'flags',
          extra: {'user-invocable': false, 'disable-model-invocation': true},
        ),
      ]);

      final s = catalog.skills.single;
      expect(s.userInvocable, isFalse);
      expect(s.disableModelInvocation, isTrue);
      expect(catalog.diagnostics, isEmpty);
    });

    test('yaml_repaired: the host flag becomes a warning, the skill is '
        'loaded (scenario "Двоеточие без кавычек")', () {
      final catalog = parse([
        skillFile(
          'pdf',
          repaired: true,
          frontmatter: {
            'name': 'pdf',
            'description': 'Use this skill when: the user asks about PDFs',
          },
        ),
      ]);

      expect(
        catalog.skills.single.description,
        'Use this skill when: the user asks about PDFs',
      );
      final d = catalog.diagnostics.single;
      expect(d.code, 'yaml_repaired');
      expect(d.level, DiagnosticLevel.warning);
    });
  });

  group('compatibility', () {
    test('longer than 500 chars: warning, cut to 500', () {
      final catalog = parse([
        validSkill('compat', extra: {'compatibility': 'c' * 600}),
      ]);

      expect(catalog.skills.single.compatibility, 'c' * 500);
      expect(catalog.diagnostics.single.level, DiagnosticLevel.warning);
    });

    test('exactly 500 chars: no warning', () {
      final catalog = parse([
        validSkill('compat', extra: {'compatibility': 'c' * 500}),
      ]);

      expect(catalog.skills.single.compatibility, hasLength(500));
      expect(catalog.diagnostics, isEmpty);
    });

    test('empty or blank: warning, treated as absent (no attribute)', () {
      for (final value in ['', '   ']) {
        final catalog = parse([
          validSkill('compat', extra: {'compatibility': value}),
        ]);

        expect(catalog.skills.single.compatibility, isNull, reason: "'$value'");
        expect(catalog.diagnostics.single.level, DiagnosticLevel.warning);
      }
    });
  });

  group('metadata.codelab-operative (Q32)', () {
    ExtensionDiagnostic only(SkillCatalog c) => c.diagnostics.single;

    test('scenario "Закреплённые строки в metadata": one rule per non-empty '
        'line, an empty line skipped, info not_applied', () {
      final catalog = parse([
        validSkill(
          'ops',
          extra: {
            'metadata': {
              'codelab-operative':
                  'Never invent PR numbers.\n\n  Write in English.  \n',
            },
          },
        ),
      ]);

      expect(catalog.skills.single.operative, [
        'Never invent PR numbers.',
        'Write in English.',
      ]);
      expect(only(catalog).code, 'not_applied');
      expect(only(catalog).level, DiagnosticLevel.info);
    });

    test('16 rules of 512 chars are valid', () {
      final lines = [for (var i = 0; i < 16; i++) 'r' * 512];
      final catalog = parse([
        validSkill(
          'ops',
          extra: {
            'metadata': {'codelab-operative': lines.join('\n')},
          },
        ),
      ]);

      expect(catalog.skills.single.operative, lines);
      expect(only(catalog).code, 'not_applied');
    });

    test('17 rules: warning, no rules, no not_applied', () {
      final catalog = parse([
        validSkill(
          'ops',
          extra: {
            'metadata': {
              'codelab-operative': [
                for (var i = 0; i < 17; i++) 'rule $i',
              ].join('\n'),
            },
          },
        ),
      ]);

      expect(catalog.skills.single.operative, isEmpty);
      expect(only(catalog).level, DiagnosticLevel.warning);
    });

    test('a rule longer than 512 chars: warning, no rules', () {
      final catalog = parse([
        validSkill(
          'ops',
          extra: {
            'metadata': {'codelab-operative': 'r' * 513},
          },
        ),
      ]);

      expect(catalog.skills.single.operative, isEmpty);
      expect(only(catalog).level, DiagnosticLevel.warning);
    });

    test('a non-string value: warning, no rules', () {
      final catalog = parse([
        validSkill(
          'ops',
          extra: {
            'metadata': {
              'codelab-operative': ['a', 'b'],
            },
          },
        ),
      ]);

      expect(catalog.skills.single.operative, isEmpty);
      expect(only(catalog).level, DiagnosticLevel.warning);
    });

    test('other metadata keys are ignored without diagnostics', () {
      final catalog = parse([
        validSkill(
          'ops',
          extra: {
            'metadata': {
              'author': 'me',
              'tags': ['a'],
            },
          },
        ),
      ]);

      expect(catalog.skills.single.operative, isEmpty);
      expect(catalog.diagnostics, isEmpty);
    });

    test('a top-level "operative" is an ordinary unknown_key', () {
      final catalog = parse([
        validSkill('ops', extra: {'operative': 'Do it.'}),
      ]);

      expect(catalog.skills.single.operative, isEmpty);
      expect(only(catalog).code, 'unknown_key');
      expect(only(catalog).level, DiagnosticLevel.warning);
    });
  });

  group('a skipped skill', () {
    ExtensionDiagnostic errorOf(SkillCatalog c) {
      expect(c.skills, isEmpty);
      return c.diagnostics.singleWhere((d) => d.level == DiagnosticLevel.error);
    }

    test('scenario "Без описания": error missing_description', () {
      final catalog = parse([
        skillFile('nodesc', frontmatter: {'name': 'nodesc'}),
      ]);

      expect(errorOf(catalog).code, 'missing_description');
      expect(errorOf(catalog).path, '$skillPath/nodesc/SKILL.md');
    });

    test('a description empty after collapsing whitespace and \\r', () {
      for (final d in ['', '   ', ' \r\n \t ']) {
        final catalog = parse([
          skillFile('blank', frontmatter: {'name': 'blank', 'description': d}),
        ]);

        expect(errorOf(catalog).code, 'missing_description', reason: '"$d"');
      }
    });

    test('scenario "Нелатинское имя": error invalid_name names the allowed '
        'characters', () {
      final catalog = parse([
        skillFile('otchet', frontmatter: {'name': 'отчёт', 'description': 'D'}),
      ]);

      final e = errorOf(catalog);
      expect(e.code, 'invalid_name');
      expect(e.message, contains('Latin'));
      expect(e.message, contains('digits'));
      expect(e.message, contains('-'));
      expect(e.message, contains('_'));
    });

    test('a name that cannot be a command: leading dash, space, colon, '
        'longer than 128', () {
      for (final name in ['-x', 'a b', 'a:b', 'a' * 129]) {
        final catalog = parse([
          skillFile('dir', frontmatter: {'name': name, 'description': 'D'}),
        ]);

        expect(catalog.skills, isEmpty, reason: "'$name'");
        expect(
          catalog.diagnostics.any(
            (d) => d.level == DiagnosticLevel.error && d.code == 'invalid_name',
          ),
          isTrue,
          reason: "'$name'",
        );
      }
    });

    test('names allowed by the command grammar but not by the spec are only '
        'a warning: A_b, 128 chars', () {
      for (final name in ['A_b', 'a' * 128]) {
        final catalog = parse([
          skillFile(name, frontmatter: {'name': name, 'description': 'D'}),
        ]);

        expect(catalog.skills.single.name, name, reason: name);
      }
    });

    test('no frontmatter at all: skipped with an error', () {
      final catalog = parse([skillFile('plain', frontmatter: null)]);

      expect(catalog.skills, isEmpty);
      final d = catalog.diagnostics.single;
      expect(d.level, DiagnosticLevel.error);
      expect(d.code, 'missing_frontmatter');
      expect(
        d.message,
        'SKILL.md has no YAML frontmatter; the skill is skipped',
      );
    });

    test('one error on the first reason: no warnings for a skipped skill '
        '(D16)', () {
      final catalog = parse([
        skillFile(
          'multi',
          frontmatter: {'name': 'Bad Name', 'color': 'red', 'license': 5},
          body: '',
        ),
      ]);

      expect(catalog.skills, isEmpty);
      expect(codes(catalog), ['invalid_name']);
      expect(catalog.diagnostics.single.level, DiagnosticLevel.error);
    });

    test('scenario "Совсем нечитаемый YAML": the host error is carried over '
        'with line and column', () {
      final catalog = parse([
        skillFile(
          'broken',
          frontmatter: null,
          parseErrors: const [
            ExtensionDiagnostic(
              path: '$skillPath/broken/SKILL.md',
              level: DiagnosticLevel.error,
              code: 'syntax',
              message: 'flow sequence is not closed',
              line: 2,
              column: 7,
            ),
          ],
        ),
      ]);

      final e = errorOf(catalog);
      expect(e.code, 'syntax');
      expect(e.line, 2);
      expect(e.column, 7);
    });

    test('scenario "Большое тело": 50 KiB is loaded, 70 KiB is too_large', () {
      final ok = parse([validSkill('big', body: 'a' * (50 * 1024))]);
      final tooBig = parse([validSkill('huge', body: 'a' * (70 * 1024))]);

      expect(ok.skills.single.body, hasLength(50 * 1024));
      expect(ok.diagnostics, isEmpty);
      expect(errorOf(tooBig).code, 'too_large');
    });

    test('the limit is 64 KiB of the trimmed body, in UTF-8 bytes', () {
      final edge = parse([
        validSkill('edge', body: '\n\n${'a' * (64 * 1024)}\n\n'),
      ]);
      // 32769 символов по 2 байта = 65538 байт > 64 КиБ.
      final multibyte = parse([
        validSkill('wide', body: 'я' * (32 * 1024 + 1)),
      ]);

      expect(edge.skills.single.body, hasLength(64 * 1024));
      expect(errorOf(multibyte).code, 'too_large');
    });

    test('an error of one skill does not stop the others', () {
      final catalog = parse([
        skillFile('bad', frontmatter: {'name': 'bad'}),
        validSkill('good'),
      ]);

      expect([for (final s in catalog.skills) s.name], ['good']);
      expect(codes(catalog), ['missing_description']);
    });

    test('diagnostics are fixed texts without fragments of the file', () {
      final catalog = parse([
        skillFile(
          'leaky',
          frontmatter: {
            'name': 'leaky',
            'description': 'D',
            'sk-secret-key': 'v',
            'argument-hint': 'sk-secret-hint-${"x" * 100}',
          },
          body: '',
        ),
      ]);

      expect(catalog.diagnostics, isNotEmpty);
      expect(
        [for (final d in catalog.diagnostics) d.message].join('\n'),
        isNot(contains('sk-secret')),
      );
    });
  });

  group('order and positions of diagnostics (D16)', () {
    test('yaml_repaired first, then the fields in the order of the file '
        'keys, empty_body last', () {
      final catalog = parse([
        skillFile(
          'ord',
          repaired: true,
          frontmatter: {
            'description': 'D',
            'color': 'red',
            'argument-hint': 5,
            'name': 'ord',
          },
          positions: {
            'description': const ConfigPosition(2, 1),
            'color': const ConfigPosition(3, 1),
            'argument-hint': const ConfigPosition(4, 1),
          },
          body: '',
        ),
      ]);

      expect(codes(catalog), [
        'yaml_repaired',
        'unknown_key',
        'invalid_value',
        'empty_body',
      ]);
      expect(catalog.diagnostics[1].line, 3);
      expect(catalog.diagnostics[2].line, 4);
      // `empty_body` указывает на строку начала тела; yaml_repaired — без строки.
      expect(catalog.diagnostics.last.line, 5);
      expect(catalog.diagnostics.first.line, isNull);
    });

    test('too_large points at the body line', () {
      final catalog = parse([validSkill('huge', body: 'a' * (70 * 1024))]);

      final d = catalog.diagnostics.single;
      expect(d.line, 5);
      expect(
        d.message,
        'the skill body is larger than 64 KiB; the skill is skipped',
      );
    });

    test('fixed texts of the main codes', () {
      final catalog = parse([
        skillFile(
          'dir',
          repaired: true,
          frontmatter: {'name': 'Other', 'description': 'D', 'x': 1},
        ),
      ]);

      final byCode = {for (final d in catalog.diagnostics) d.code: d.message};
      expect(
        byCode['yaml_repaired'],
        'the frontmatter was parsed after quoting values that contain ": "; '
        'check the values',
      );
      expect(
        byCode['unknown_key'],
        'unknown frontmatter key; the skill is loaded',
      );
      expect(
        byCode['name_mismatch'],
        'the skill name differs from its directory name; the name from the '
        'frontmatter is used',
      );
      expect(
        byCode['invalid_name'],
        'the skill name should be lowercase Latin letters, digits and single '
        'hyphens, at most 64 characters (Agent Skills)',
      );
    });

    test('companions are carried into the definition', () {
      final catalog = parse([
        skillFile(
          'comp',
          frontmatter: {'name': 'comp', 'description': 'D'},
          companions: ['scripts/x.py', 'template.md'],
          companionsTruncated: true,
        ),
      ]);

      final s = catalog.skills.single;
      expect(s.companions, ['scripts/x.py', 'template.md']);
      expect(s.companionsTruncated, isTrue);
      expect(s.path, '/home/.codelab/skills/comp/SKILL.md');
      expect(catalog.skill('comp'), same(s));
      expect(catalog.skill('none'), isNull);
    });
  });
}
