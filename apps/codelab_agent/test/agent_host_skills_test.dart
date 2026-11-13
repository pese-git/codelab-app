import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/skills_rig.dart';

/// Навыки в хостах бинаря: `AgentHost.build` передаёт ядру `skillFiles` и
/// `hostFiles` по `--stdio`, не передаёт по `--ws`, а со сценарием
/// `--llm-script` не читает пользовательский уровень, но читает абсолютный
/// `skills.extra_roots` из `--config` (agent-skills «Навыки в хостах»,
/// сценарии «Навык пользователя по stdio», «WebSocket без навыков»;
/// agent-project-context «Порт файлов проекта», сценарий «Один загрузчик для
/// двух портов»; design.md change `add-agent-skills`, D3, D16; задача 5.1).
///
/// Хост поднимается в процессе теста; `CODELAB_HOME` и `HOME` — временные
/// каталоги из словаря окружения `ServeOptions`, настоящие `~/.codelab` и
/// `~/.agents` не читаются.
///
/// Красные (до 5.2): `--stdio` ещё не передаёт `skillFiles` и `hostFiles`
/// (`AgentHost.build` собирает `AgentCoreServices` без них) — нет команд
/// `skill:*`, секции каталога и чтения файла навыка; `--llm-script` не
/// читает `extra_roots`. Стражи (зелёные сразу, защищают 5.2 от
/// переусердствования): `--ws` без навыков, `--llm-script` без
/// пользовательского уровня и без навыков недоверенного проекта.
void main() {
  Future<void> turn(AgentSession session) =>
      session.prompt([const TextContent('hi')]);

  List<String> skillCommands(AgentSession session) => [
    for (final c in session.commands)
      if (c.name.startsWith('skill:')) c.name,
  ]..sort();

  group('--stdio', () {
    test('scenario "Навык пользователя по stdio": skills of '
        r'$CODELAB_HOME and ~/.agents give commands, the catalog and '
        'skills.loaded', () async {
      final rig = await SkillsRig.create();
      rig.writeSkill(rig.codelabSkills, 'release-notes');
      rig.writeSkill(rig.agentsSkills, 'agents-skill');
      final host = await rig.startHost(['--stdio'], [textJson('ok')]);

      final session = await host.core.runtime.createSession(
        SessionSpec(cwd: rig.project),
      );
      await turn(session);

      expect(skillCommands(session), [
        'skill:agents-skill',
        'skill:release-notes',
      ]);
      final prompt = rig.contexts.single.systemPrompt;
      expect(prompt, contains('## Skills'));
      expect(prompt, contains('release-notes'));
      expect(prompt, contains('agents-skill'));
      final loaded = rig.logger.eventsOf('skills.loaded').single;
      expect(loaded.fields['names'], ['agents-skill', 'release-notes']);
      expect(loaded.fields['project'], isFalse);
      // Тело навыка и описание в журнал не попадают (agent-skills
      // «Наблюдаемость навыков»).
      expect(
        [for (final r in rig.logger.records) r.toString()].join('\n'),
        isNot(contains('Follow the steps')),
      );
    });

    test(
      'hostFiles is passed: read of a file in the user skill directory '
      'comes from the agent file system (no client env in the session)',
      () async {
        final rig = await SkillsRig.create();
        final dir = rig.writeSkill(
          rig.codelabSkills,
          'release-notes',
          files: {'template.md': 'template text\n'},
        );
        final host = await rig.startHost(
          ['--stdio'],
          [
            callJson('c1', 'read', {'path': '$dir/template.md'}),
            textJson('ok'),
          ],
        );

        final session = await host.core.runtime.createSession(
          SessionSpec(cwd: rig.project),
        );
        await turn(session);

        final result = toolResultsOf(rig.contexts.last).single;
        expect(result.isError, isFalse, reason: result.text);
        expect(result.text, contains('template text'));
      },
    );

    test('the same loader gives project skills of a trusted project (one '
        'loader for two ports)', () async {
      final rig = await SkillsRig.create(trusted: true);
      rig.writeSkill('${rig.project}/.codelab/skills', 'pdf');
      File('${rig.project}/AGENTS.md').writeAsStringSync('project rule\n');
      final host = await rig.startHost(['--stdio'], [textJson('ok')]);

      final session = await host.core.runtime.createSession(
        SessionSpec(cwd: rig.project),
      );

      expect(skillCommands(session), ['skill:pdf']);
      // Порт файлов проекта по-прежнему на месте: оба порта — один загрузчик.
      expect(
        rig.logger.eventsOf('project_context.loaded').single.fields['files'],
        ['AGENTS.md'],
      );
      expect(
        rig.logger.eventsOf('skills.loaded').single.fields['project'],
        isTrue,
      );
    });
  });

  group('--ws', () {
    test(
      'scenario "WebSocket без навыков": no skills port, no commands, no '
      'catalog, no skills.loaded; the read-only root is not there either',
      () async {
        final rig = await SkillsRig.create();
        final dir = rig.writeSkill(
          rig.codelabSkills,
          'release-notes',
          files: {'template.md': 'template text\n'},
        );
        final host = await rig.startHost(
          ['--ws', '--port', '0'],
          [
            callJson('c1', 'read', {'path': '$dir/template.md'}),
            textJson('ok'),
          ],
        );

        final session = await host.core.runtime.createSession(
          SessionSpec(cwd: rig.project),
        );
        await turn(session);

        expect(skillCommands(session), isEmpty);
        expect(rig.contexts.first.systemPrompt, isNot(contains('## Skills')));
        expect(
          rig.contexts.first.systemPrompt,
          isNot(contains('release-notes')),
        );
        expect(rig.logger.eventsOf('skills.loaded'), isEmpty);
        final result = toolResultsOf(rig.contexts.last).single;
        expect(result.isError, isTrue);
        expect(result.text, 'Path is outside the workspace: $dir/template.md');
      },
    );
  });

  group('--llm-script', () {
    String writeScript(SkillsRig rig) {
      final file = File('${rig.temp.path}/script.json')
        ..writeAsStringSync(
          jsonEncode({
            'llm': {
              'steps': [textJson('ok')],
            },
          }),
        );
      return file.path;
    }

    String writeConfig(SkillsRig rig, String body) =>
        (File('${rig.temp.path}/extra.yaml')..writeAsStringSync(body)).path;

    test('user level is not read: neither \$CODELAB_HOME/skills nor '
        '~/.agents/skills, nor skills of the untrusted project', () async {
      final rig = await SkillsRig.create();
      rig.writeSkill(rig.codelabSkills, 'user-skill');
      rig.writeSkill(rig.agentsSkills, 'home-skill');
      rig.writeSkill('${rig.project}/.agents/skills', 'project-skill');
      final host = await rig.startHost([
        '--stdio',
        '--llm-script',
        writeScript(rig),
      ], const []);

      final session = await host.core.runtime.createSession(
        SessionSpec(cwd: rig.project),
      );

      expect(skillCommands(session), isEmpty);
      for (final event in rig.logger.eventsOf('skills.loaded')) {
        expect(event.fields['names'], isEmpty);
        expect(event.fields['project'], isFalse);
      }
    });

    test('an absolute skills.extra_roots from --config is read; the user '
        'level still is not', () async {
      final rig = await SkillsRig.create();
      rig.writeSkill(rig.codelabSkills, 'user-skill');
      rig.writeSkill(rig.agentsSkills, 'home-skill');
      final extra = '${rig.temp.path}/extra-skills';
      rig.writeSkill(extra, 'extra-skill');
      final config = writeConfig(
        rig,
        'skills:\n  extra_roots: [${jsonEncode(extra)}]\n',
      );
      final options = rig.options([
        '--stdio',
        '--llm-script',
        writeScript(rig),
        '--config',
        config,
      ]);
      // Предусловие: корень дошёл до CoreConfig (зелёное и до 5.2).
      expect(
        loadServeConfig(options, cwd: rig.project).orThrow().skills.extraRoots,
        [extra],
      );
      final host = await rig.startHostWith(options);

      final session = await host.core.runtime.createSession(
        SessionSpec(cwd: rig.project),
      );

      expect(skillCommands(session), ['skill:extra-skill']);
    });
  });
}
