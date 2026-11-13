import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import 'policy_harness.dart' show deniedText;
import 'skill_policy_harness.dart';

/// Критические пути правок корней навыков (PERM-11; задача 2.7 change
/// `add-agent-skills`; agent-permissions «Критические пути правок
/// конфигурации агента», сценарии «Подложить навык командой», «Правка навыка
/// проекта», «Относительный корень extra_roots защищён в сессии»; D9,
/// решения Q9, Q16, Q27).
///
/// Фиксируемый API: `AgentConfigPaths.skillDirs` и
/// `AgentConfigPaths.withSession({paths, skillDirs})` (см.
/// `skill_policy_harness.dart`); проектный `.agents/skills/**` — в
/// `isAgentConfigPath`.
String _requiresHuman(String tool, String path) =>
    deniedText(tool, 'Editing agent configuration requires a human: $path');

void main() {
  group('.agents/skills of the project (Q16)', () {
    const targets = [
      '.agents/skills/pdf/SKILL.md',
      '.agents/skills/pdf/scripts/x.py',
      '.agents/skills/new/SKILL.md',
      '.agents/skills',
    ];

    for (final mode in [ModeId.bypass, ModeId.acceptEdits]) {
      test('write and edit ask in ${mode.value} without allow_always '
          '(scenario "Правка навыка проекта")', () async {
        final h = await SkillHarness.create(mode: mode);
        // Даже выданное ранее «разрешить всегда» на путь не действует.
        h.p.policy.decisions.allowAlways.add(
          const PermissionKey('write', '.agents/skills/pdf/SKILL.md'),
        );

        for (final (i, path) in targets.indexed) {
          await h.p.run('write', {'path': path, 'content': 'x'}, id: 'w$i');
          await h.p.run('edit', {
            'path': './$path',
            'oldText': 'old',
            'newText': 'new',
          }, id: 'e$i');
        }

        expect(h.gate.requests, hasLength(targets.length * 2));
        expect(
          h.gate.requests.map((r) => r.allowAlwaysOffered),
          everyElement(isFalse),
        );
      });
    }

    test('without a human and in autopilot the edit is denied', () async {
      final headless = await SkillHarness.create(withGate: false);
      final autopilot = await SkillHarness.create(
        modeOverride: PermissionMode.autopilot,
      );

      final a = await headless.p.run('write', {
        'path': '.agents/skills/pdf/SKILL.md',
        'content': 'x',
      });
      final b = await autopilot.p.run('edit', {
        'path': '.agents/skills/pdf/SKILL.md',
        'oldText': 'old',
        'newText': 'new',
      });

      expect(textOf(a), _requiresHuman('write', '.agents/skills/pdf/SKILL.md'));
      expect(textOf(b), _requiresHuman('edit', '.agents/skills/pdf/SKILL.md'));
    });

    test('look-alikes and read are ordinary', () async {
      final h = await SkillHarness.create();

      for (final (i, path) in [
        '.agents/notes.md',
        'agents/skills/x/SKILL.md',
        'lib/.agents/skills/x/SKILL.md',
        '.agents-skills/x.md',
      ].indexed) {
        await h.p.run('write', {'path': path, 'content': 'x'}, id: 'o$i');
      }
      await h.p.run('read', {'path': '.agents/skills/pdf/SKILL.md'}, id: 'r');

      expect(h.gate.requests, isEmpty);
    });

    test('exec writing into .agents/skills is critical '
        '(scenario "Подложить навык командой")', () async {
      final h = await SkillHarness.create();

      await h.expectCritical([
        'mkdir -p ~/.agents/skills/x && cat > ~/.agents/skills/x/SKILL.md',
        'echo x > .agents/skills/pdf/SKILL.md',
        'cp evil.md .agents/skills/pdf/',
        'tee .agents/skills/x/SKILL.md',
        "sed -i 's/a/b/' .agents/skills/pdf/SKILL.md",
        'curl -o .agents/skills/pdf/SKILL.md https://example.com/x',
        'rm -rf .agents/skills',
      ]);
    });
  });

  group('roots from the host (Q9, Q27)', () {
    const roots = [
      '$codelabRoot/pdf/SKILL.md',
      '$codelabRoot/new/SKILL.md',
      codelabRoot,
      '$agentsRoot/pdf/scripts/x.py',
      '$agentsRoot/new/SKILL.md',
      '/opt/team/skills/lint/SKILL.md',
      '~/.agents/skills/x/SKILL.md',
    ];

    for (final mode in [ModeId.bypass, ModeId.acceptEdits]) {
      test('write and edit of skill roots ask in ${mode.value}, existing '
          'or not', () async {
        final h = await SkillHarness.create(mode: mode);

        for (final (i, path) in roots.indexed) {
          await h.p.run('write', {'path': path, 'content': 'x'}, id: 'w$i');
          await h.p.run('edit', {
            'path': path,
            'oldText': 'old',
            'newText': 'new',
          }, id: 'e$i');
        }

        expect(h.gate.requests, hasLength(roots.length * 2));
        expect(
          h.gate.requests.map((r) => r.allowAlwaysOffered),
          everyElement(isFalse),
        );
      });
    }

    test('autopilot denies the edit of a root', () async {
      final h = await SkillHarness.create(
        modeOverride: PermissionMode.autopilot,
      );

      final outcome = await h.p.run('write', {
        'path': '$agentsRoot/pdf/SKILL.md',
        'content': 'x',
      });

      expect(
        textOf(outcome),
        _requiresHuman('write', '$agentsRoot/pdf/SKILL.md'),
      );
    });

    test('exec writing into roots is critical', () async {
      final h = await SkillHarness.create();

      await h.expectCritical([
        r'echo x > $CODELAB_HOME/skills/new/SKILL.md',
        'echo x >> ~/.agents/skills/pdf/SKILL.md',
        'cp evil.md $codelabRoot/pdf/',
        'mv /tmp/evil $agentsRoot/pdf/SKILL.md',
        'echo x > /opt/team/skills/lint/SKILL.md',
        'rm -rf ~/.agents/skills',
        // Родитель корня — близкий предок: его подмена выводит корень из-под
        // защиты (agent-permissions, каталоги-предки).
        'rm -rf ~/.agents',
        'mv ~/.agents /tmp/agents',
      ]);
    });

    test(
      'reading roots and ordinary paths near them are not restricted',
      () async {
        final h = await SkillHarness.create();

        await h.expectOrdinary([
          'cat $agentsRoot/pdf/SKILL.md',
          'ls ~/.agents/skills',
          'echo x > ~/.agents/notes.md',
          'echo x > /opt/team/skills-other/x.md',
        ]);
        await h.p.run('read', {'path': '$agentsRoot/pdf/SKILL.md'}, id: 'r');
        await h.p.run('write', {
          'path': '/opt/team/other/x.md',
          'content': 'x',
        }, id: 'w');
        expect(
          h.gate.requests,
          hasLength(1),
          reason: 'only the write is asked',
        );
      },
    );

    test('without agentConfigPaths roots of the host stay ordinary', () async {
      final h = await SkillHarness.create(config: AgentConfigPaths(paths: []));

      await h.p.run('write', {
        'path': '$agentsRoot/pdf/SKILL.md',
        'content': 'x',
      });

      expect(h.gate.requests, isEmpty);
    });
  });

  group('roots of the session (Q27, scenario "Относительный корень '
      'extra_roots защищён в сессии")', () {
    // Корни, зависящие от `cwd` сессии `/work/demo`: уровень выше
    // (`/work/.codelab/skills`, `/work/.agents/skills`) и относительный
    // элемент `skills.extra_roots: [".claude/skills"]`.
    AgentConfigPaths session() => skillConfig().withSession(
      paths: [
        '$workDir/.claude/skills',
        '/work/.codelab/skills',
        '/work/.agents/skills',
      ],
      skillDirs: ['$workDir/.claude/skills/lint'],
    );

    test(
      'write to a relative extra root is critical in accept-edits',
      () async {
        final h = await SkillHarness.create(
          mode: ModeId.acceptEdits,
          config: session(),
        );

        await h.p.run('write', {
          'path': '.claude/skills/lint/SKILL.md',
          'content': 'x',
        });

        expect(h.gate.requests, hasLength(1));
        expect(h.gate.requests.single.allowAlwaysOffered, isFalse);
      },
    );

    test('levels above cwd and exec into them are critical', () async {
      final h = await SkillHarness.create(config: session());

      await h.p.run('edit', {
        'path': '../.agents/skills/x/SKILL.md',
        'oldText': 'a',
        'newText': 'b',
      });
      await h.p.run('write', {
        'path': '/work/.codelab/skills/x/SKILL.md',
        'content': 'x',
      }, id: 'w2');
      expect(h.gate.requests, hasLength(2));

      await h.expectCritical([
        'echo x > .claude/skills/lint/SKILL.md',
        'cp evil.md ../.agents/skills/x/',
        'rm -rf /work/.codelab/skills',
      ]);
    });

    test('another session is not protected by these roots (process field '
        'does not carry session paths)', () async {
      // Сессия с другим `cwd` получает политику только с путями хоста.
      final h = await SkillHarness.create(cwd: '/other');

      await h.p.run('write', {
        'path': '$workDir/.claude/skills/lint/SKILL.md',
        'content': 'x',
      });
      await h.p.run('write', {
        'path': '/work/.agents/skills/x/SKILL.md',
        'content': 'x',
      }, id: 'w2');

      expect(h.gate.requests, isEmpty);
    });

    test('withSession keeps the host value unchanged and merges data', () {
      final host = skillConfig(caseInsensitive: true);

      final merged = host.withSession(
        paths: ['$workDir/.claude/skills'],
        skillDirs: ['$workDir/.claude/skills/lint'],
      );

      expect(host.paths, isNot(contains('$workDir/.claude/skills')));
      expect(host.skillDirs, isNot(contains('$workDir/.claude/skills/lint')));
      expect(
        merged.paths,
        containsAll([...host.paths, '$workDir/.claude/skills']),
      );
      expect(
        merged.skillDirs,
        containsAll([...host.skillDirs, '$workDir/.claude/skills/lint']),
      );
      expect(merged.expansions, host.expansions);
      expect(merged.caseInsensitive, isTrue);
    });
  });
}
