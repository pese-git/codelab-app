import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'skills_support.dart';

/// Каталог навыков сессии (agent-skills «Каталог навыков сессии», сценарии
/// «Отключённый навык», «Навык, запрещённый правилом»; «Конфигурация
/// навыков»; design.md change `add-agent-skills`, D2, D10, D11).
///
/// Фиксируемый API: `SkillCatalog.skills` (отсортирован по имени, байтово),
/// `SkillCatalog.modelVisible`, `SkillCatalog.diagnostics`;
/// `parseSkills(files, settings, rules:)` — чистая функция.
void main() {
  List<String> names(Iterable<SkillDefinition> skills) => [
    for (final s in skills) s.name,
  ];

  group('order', () {
    test(
      'skills are sorted by name, bytewise (uppercase before lowercase)',
      () {
        final catalog = parse([
          validSkill('beta'),
          validSkill('alpha'),
          validSkill('Zeta'),
        ]);

        expect(names(catalog.skills), ['Zeta', 'alpha', 'beta']);
      },
    );

    test('the same input gives the same catalog', () {
      final files = [validSkill('b'), validSkill('a')];

      final first = parse(files);
      final second = parse(files);

      expect(names(first.skills), names(second.skills));
      expect(codes(first), codes(second));
    });
  });

  group('skills.disabled', () {
    test('scenario "Отключённый навык": a disabled skill is in neither the '
        'catalog nor the commands, info for it', () {
      final catalog = parse([
        validSkill('pdf'),
        validSkill('notes'),
      ], settings: const SkillsConfig(disabled: ['pdf']));

      expect(names(catalog.skills), ['notes']);
      expect(names(catalog.modelVisible), ['notes']);
      expect(catalog.skills.where((s) => s.userInvocable).map((s) => s.name), [
        'notes',
      ]);
      final d = catalog.diagnostics.single;
      expect(d.level, DiagnosticLevel.info);
      expect(d.path, '/home/.codelab/skills/pdf/SKILL.md');
    });

    test('a disabled name is compared with the loaded name, not the '
        'directory', () {
      final catalog = parse([
        skillFile('dir', frontmatter: {'name': 'pdf', 'description': 'D'}),
      ], settings: const SkillsConfig(disabled: ['pdf']));

      expect(catalog.skills, isEmpty);
    });
  });

  group('skills.max_skills', () {
    test('the surplus in priority order is dropped with limit_exceeded', () {
      // Порядок списка — порядок приоритета (D10): корень 0, затем корень 1.
      final catalog = parse([
        validSkill('b', rootIndex: 0),
        validSkill('a', rootIndex: 0),
        validSkill('c', rootIndex: 1),
      ], settings: const SkillsConfig(maxSkills: 2));

      expect(names(catalog.skills), ['a', 'b']);
      // Одна запись с путём первого отброшенного (D16).
      final dropped = withCode(catalog, 'limit_exceeded').single;
      expect(dropped.level, DiagnosticLevel.warning);
      expect(dropped.path, '/home/.codelab/skills/c/SKILL.md');
    });

    test('exactly max_skills skills: no warning', () {
      final catalog = parse([
        validSkill('a'),
        validSkill('b'),
      ], settings: const SkillsConfig(maxSkills: 2));

      expect(names(catalog.skills), ['a', 'b']);
      expect(withCode(catalog, 'limit_exceeded'), isEmpty);
    });

    test('a skipped (invalid) skill does not take a slot', () {
      final catalog = parse([
        skillFile('bad', frontmatter: {'name': 'bad'}),
        validSkill('a'),
        validSkill('b'),
      ], settings: const SkillsConfig(maxSkills: 2));

      expect(names(catalog.skills), ['a', 'b']);
    });
  });

  group('modelVisible and commands', () {
    test('disable-model-invocation hides a skill from the model, the '
        'command stays (scenario "Навык только для команды")', () {
      final catalog = parse([
        validSkill('manual', extra: {'disable-model-invocation': true}),
        validSkill('auto'),
      ]);

      expect(names(catalog.modelVisible), ['auto']);
      expect(catalog.skills.where((s) => s.userInvocable).map((s) => s.name), [
        'auto',
        'manual',
      ]);
    });

    test('user-invocable: false removes the command, not the model entry', () {
      final catalog = parse([
        validSkill('internal', extra: {'user-invocable': false}),
      ]);

      expect(names(catalog.modelVisible), ['internal']);
      expect(catalog.skills.single.userInvocable, isFalse);
    });

    test('scenario "Навык, запрещённый правилом": permissions.deny '
        'skill:pdf removes pdf from modelVisible only', () {
      final catalog = parse(
        [validSkill('pdf'), validSkill('notes')],
        rules: PolicyRules(denyPatterns: {const PermissionKey('skill', 'pdf')}),
      );

      expect(names(catalog.modelVisible), ['notes']);
      expect(names(catalog.skills), ['notes', 'pdf']);
      expect(
        catalog.skills.firstWhere((s) => s.name == 'pdf').userInvocable,
        isTrue,
      );
    });

    test('permissions.tools.skill: deny hides every skill from the model, '
        'the commands stay', () {
      final catalog = parse([
        validSkill('pdf'),
        validSkill('notes'),
      ], rules: const PolicyRules(toolPolicies: {'skill': ToolPolicy.deny}));

      expect(catalog.modelVisible, isEmpty);
      expect(names(catalog.skills), ['notes', 'pdf']);
      expect(catalog.skills.every((s) => s.userInvocable), isTrue);
    });

    test('a deny rule of another tool or another name hides nothing', () {
      final catalog = parse(
        [validSkill('pdf')],
        rules: PolicyRules(
          denyPatterns: {
            const PermissionKey('exec', 'pdf'),
            const PermissionKey('skill', 'other'),
          },
          toolPolicies: const {'skill': ToolPolicy.ask},
        ),
      );

      expect(names(catalog.modelVisible), ['pdf']);
    });

    test('modelVisible follows the order of the catalog (by name)', () {
      final catalog = parse([validSkill('b'), validSkill('a')]);

      expect(names(catalog.modelVisible), ['a', 'b']);
    });
  });

  group('immutability', () {
    test('the snapshot lists cannot be modified', () {
      final catalog = parse([validSkill('a')]);

      expect(
        () => catalog.skills.add(catalog.skills.first),
        throwsUnsupportedError,
      );
      expect(() => catalog.diagnostics.clear(), throwsUnsupportedError);
      expect(() => catalog.modelVisible.clear(), throwsUnsupportedError);
    });
  });

  group('shadowed by name (Q39, D16)', () {
    SkillFile named(
      String dir,
      String name, {
      String root = '/home/.codelab/skills',
      int rootIndex = 0,
      Map<String, Object?> extra = const {},
    }) => skillFile(
      dir,
      root: root,
      rootIndex: rootIndex,
      frontmatter: {'name': name, 'description': 'D', ...extra},
    );

    test('two directories of one root with the same name: the first wins, '
        'warning shadowed with the path of the loser and of the winner', () {
      final catalog = parse([named('first', 'same'), named('second', 'same')]);

      expect(catalog.skills.single.dir, '/home/.codelab/skills/first');
      final d = withCode(catalog, 'shadowed').single;
      expect(d.level, DiagnosticLevel.warning);
      expect(d.path, '/home/.codelab/skills/second/SKILL.md');
      expect(
        d.message,
        'the skill is shadowed by /home/.codelab/skills/first/SKILL.md with '
        'the same name',
      );
    });

    test('different roots: the lower rootIndex wins whatever the order of '
        'the list', () {
      final catalog = parse([
        named('a', 'same', root: '/x', rootIndex: 3),
        named('b', 'same', root: '/y', rootIndex: 1),
      ]);

      expect(catalog.skills.single.dir, '/y/b');
      expect(withCode(catalog, 'shadowed').single.path, '/x/a/SKILL.md');
    });

    test('the name is the "name" field, the directory name only when there '
        'is none', () {
      final catalog = parse([
        named('dir-one', 'shared'),
        named('dir-two', 'shared', rootIndex: 1),
        skillFile('shared', frontmatter: {'description': 'D'}, rootIndex: 2),
        named('other', 'distinct'),
      ]);

      expect(names(catalog.skills), ['distinct', 'shared']);
      expect(withCode(catalog, 'shadowed'), hasLength(2));
    });

    test('scenario "Коллизия по полю name": directories a and b with '
        'name: notes -> a is loaded; b has name_mismatch and shadowed with '
        'both paths', () {
      final catalog = parse([
        skillFile('a', frontmatter: {'name': 'notes', 'description': 'D'}),
        skillFile('b', frontmatter: {'name': 'notes', 'description': 'D'}),
      ]);

      expect(catalog.skills.single.dir, '/home/.codelab/skills/a');
      final bPath = '/home/.codelab/skills/b/SKILL.md';
      final forB = [
        for (final d in catalog.diagnostics)
          if (d.path == bPath) d.code,
      ];
      expect(forB, unorderedEquals(['name_mismatch', 'shadowed']));
      expect(
        withCode(catalog, 'shadowed').single.message,
        contains('/home/.codelab/skills/a/SKILL.md'),
      );
    });

    test('scenario "Битый навык выше ничего не перекрывает"', () {
      final catalog = parse([
        skillFile(
          'release',
          root: '/repo/.codelab/skills',
          scope: ExtensionScope.project,
          frontmatter: {'name': 'release'},
        ),
        validSkill('release', rootIndex: 1),
      ]);

      expect(catalog.skills.single.scope, ExtensionScope.user);
      expect(codes(catalog), ['missing_description']);
    });

    test('a skill with an error shadows nothing', () {
      final catalog = parse([
        skillFile('broken', frontmatter: {'name': 'same'}, rootIndex: 0),
        named('good', 'same', rootIndex: 1),
      ]);

      expect(catalog.skills.single.dir, '/home/.codelab/skills/good');
      expect(withCode(catalog, 'shadowed'), isEmpty);
    });

    test('a disabled name is not "accepted": the later one is disabled '
        'too, shadowed is not issued', () {
      final catalog = parse([
        named('a', 'same'),
        named('b', 'same', rootIndex: 1),
      ], settings: const SkillsConfig(disabled: ['same']));

      expect(catalog.skills, isEmpty);
      expect(withCode(catalog, 'shadowed'), isEmpty);
    });

    test('order of steps: shadowed first, then max_skills (a shadowed '
        'duplicate does not take a slot)', () {
      final catalog = parse([
        named('a', 'a'),
        named('dup', 'a', rootIndex: 1),
        named('b', 'b', rootIndex: 1),
        named('c', 'c', rootIndex: 2),
      ], settings: const SkillsConfig(maxSkills: 2));

      expect(names(catalog.skills), ['a', 'b']);
      expect(withCode(catalog, 'shadowed'), hasLength(1));
      expect(
        withCode(catalog, 'limit_exceeded').single.path,
        '/home/.codelab/skills/c/SKILL.md',
      );
    });
  });
}
