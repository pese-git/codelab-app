import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:test/test.dart';

import 'fake_shell.dart';
import 'skill_env_rig.dart';

const skill = '/home/u/.codelab/skills/release-notes';

/// Подсказка Q23 в инструменте `exec` (agent-execution-env «Корни только для
/// чтения», пункт о подсказке; agent-skills «Сопутствующие файлы и скрипты
/// навыка», сценарий «Скрипт пользовательского навыка через клиента ACP»;
/// design.md change `add-agent-skills`, D5; решения Q17, Q23 (а)).
///
/// Фиксируемый API: `ExecTool` получает именованные параметры
/// `readOnlyRoots` (список строк, по умолчанию пуст) и `execInReadOnlyRoots`
/// (`bool`, по умолчанию `false`) — `readOnlyRoots` сессии
/// (`SkillCatalog.readOnlyRoots`) и признак локального исполнения передаёт
/// рантайм, регистрируя инструмент сессии вместо базового (реестр заменяет
/// одноимённый на месте). Инструмент сравнивает нормализованный `cwd` с
/// корнями до вызова env.
void main() {
  late FakeShellEnv shell;
  late MemoryExecutionEnv files;
  final seen = <ExecOptions>[];

  setUp(() async {
    seen.clear();
    shell = FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), (command, options) {
      seen.add(options);
      return answering('ok\n')(command, options);
    });
    await shell.writeText('/proj/sub/.keep', '');
    files = MemoryExecutionEnv(cwd: '/');
    await files.writeText('$skill/scripts/x.py', 'print(1)\n');
    await files.writeText('/etc/passwd', 'root\n');
  });

  Future<SkillToolRig> rig({required bool local}) => SkillToolRig.create(
    [
      ExecTool(readOnlyRoots: const [skill], execInReadOnlyRoots: local),
    ],
    base: shell,
    hostFs: files,
    readOnlyRoots: const [skill],
    execInReadOnlyRoots: local,
  );

  final hint =
      'The working directory $skill is outside the client workspace; run the '
      'skill script by its absolute path from the skill block, with the '
      'workspace as the working directory.';

  group('execInReadOnlyRoots == false (the env is the ACP client)', () {
    test(
      'scenario "Скрипт пользовательского навыка через клиента ACP": cwd '
      'in the skill dir -> a tool error with the hint, the env got no call',
      () async {
        final h = await rig(local: false);

        final outcome = await h.run('exec', {
          'command': 'python3 scripts/x.py',
          'cwd': skill,
        });

        expect(outcome.outcome, ToolOutcome.failed);
        expect(outcome.message.isError, isTrue);
        expect(textOfOutcome(outcome), hint);
        expect(shell.commands, isEmpty);
      },
    );

    test('a subdirectory of the skill dir gets the hint with the cwd as '
        'given', () async {
      final h = await rig(local: false);

      final outcome = await h.run('exec', {
        'command': 'ls',
        'cwd': '$skill/scripts',
      });

      expect(outcome.outcome, ToolOutcome.failed);
      expect(
        textOfOutcome(outcome),
        startsWith(
          'The working directory $skill/scripts is outside the client '
          'workspace; run the skill script by its absolute path',
        ),
      );
      expect(shell.commands, isEmpty);
    });

    test('a relative cwd that resolves into the root is recognized', () async {
      final h = await rig(local: false);

      final outcome = await h.run('exec', {
        'command': 'ls',
        'cwd': '../home/u/.codelab/skills/release-notes',
      });

      expect(outcome.outcome, ToolOutcome.failed);
      expect(
        textOfOutcome(outcome),
        contains('is outside the client workspace'),
      );
      expect(shell.commands, isEmpty);
    });

    test('the recommended second step: the script by its absolute path with '
        'the workspace cwd reaches the env', () async {
      final h = await rig(local: false);

      final outcome = await h.run('exec', {
        'command': 'python3 $skill/scripts/x.py',
        'cwd': '.',
      });

      expect(outcome.outcome, ToolOutcome.completed);
      expect(shell.commands, ['python3 $skill/scripts/x.py']);
      expect(seen.single.cwd, '/proj');
    });
  });

  group('execInReadOnlyRoots == true (the env is local, Q17)', () {
    test(
      'the command with cwd in the skill dir is passed to the env',
      () async {
        final h = await rig(local: true);

        final outcome = await h.run('exec', {
          'command': 'python3 scripts/x.py',
          'cwd': skill,
        });

        expect(outcome.outcome, ToolOutcome.completed);
        expect(shell.commands, ['python3 scripts/x.py']);
        expect(seen.single.cwd, skill);
      },
    );
  });

  group('cwd outside every root', () {
    for (final local in [true, false]) {
      test(
        'the former outsideWorkspace of BoundedEnv, no hint (local: $local)',
        () async {
          final h = await rig(local: local);

          final outcome = await h.run('exec', {
            'command': 'ls',
            'cwd': '../other',
          });

          expect(outcome.outcome, ToolOutcome.failed);
          expect(
            textOfOutcome(outcome),
            'Path is outside the workspace: ../other',
          );
          expect(shell.commands, isEmpty);
        },
      );
    }

    test(
      'a neighbor of the skill dir and a prefix sibling get no hint',
      () async {
        final h = await rig(local: false);

        for (final cwd in [
          '/home/u/.codelab/skills/other',
          '$skill-evil',
          '/home/u/.codelab',
        ]) {
          final outcome = await h.run('exec', {'command': 'ls', 'cwd': cwd});

          expect(
            textOfOutcome(outcome),
            'Path is outside the workspace: $cwd',
            reason: cwd,
          );
        }
        expect(shell.commands, isEmpty);
      },
    );
  });

  group('the usual cwd is not affected', () {
    for (final local in [true, false]) {
      test('a workspace subdirectory runs (local: $local)', () async {
        final h = await rig(local: local);

        final outcome = await h.run('exec', {'command': 'ls', 'cwd': 'sub'});

        expect(outcome.outcome, ToolOutcome.completed);
        expect(seen.single.cwd, '/proj/sub');
      });
    }

    test('without roots the tool behaves as before', () async {
      final h = await SkillToolRig.create([ExecTool()], base: shell);

      final outcome = await h.run('exec', {'command': 'ls', 'cwd': skill});

      expect(textOfOutcome(outcome), 'Path is outside the workspace: $skill');
      expect(shell.commands, isEmpty);
    });
  });
}
