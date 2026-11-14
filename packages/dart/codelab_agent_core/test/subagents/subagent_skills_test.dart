import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/policy_harness.dart' show deniedText;
import '../skills/skills_support.dart';
import '../tools/fake_shell.dart';
import 'subagent_rig.dart';

/// Навыки у ребёнка (agent-subagents «Сборка ребёнка», сценарии «Каталог
/// ребёнка — снимок родителя», «Тип без skill», «Файлы навыка пользователя у
/// ребёнка», «Активные навыки родителя не наследуются», «Корень навыков выше
/// cwd у ребёнка»; SKL-9, SUB-1; design.md change `add-subagents-and-tasks`,
/// D34, D36 Т9; задача 2s.1).
///
/// Красные до задач 2.4, 2.11 и 2s.2: ребёнок получает тот же неизменяемый
/// снимок каталога родителя без второй загрузки; env ребёнка — env родителя;
/// политика ребёнка — защищённые пути корня, включая корни навыков сессии;
/// `SkillTool` ребёнка — с `sessionId` и `activeSkills` ребёнка.
void main() {
  const userHome = '/home/.codelab/skills';
  const notes = '$userHome/notes';

  late FakeSkillPort port;

  setUp(() => port = FakeSkillPort());

  /// Секция `## Skills` промпта: до начала секций ребёнка или до конца.
  String skillsSection(String prompt) {
    final from = prompt.indexOf('## Skills');
    expect(from, isNonNegative, reason: 'в промпте нет секции ## Skills');
    final end = prompt.indexOf('You are a subagent');
    return (end < 0 ? prompt.substring(from) : prompt.substring(from, end))
        .trimRight();
  }

  List<Object?> skillEnum(LlmContext context) =>
      ((schemaOf(context, 'skill').parameters['properties']!
                  as Map<String, Object?>)['name']!
              as Map<String, Object?>)['enum']!
          as List<Object?>;

  group('снимок каталога родителя', () {
    setUp(() {
      port.files = SkillFiles(
        skills: [validSkill('a-skill'), validSkill('b-skill')],
      );
    });

    SubagentRig rigFor({String type = 'general'}) => SubagentRig(
      skillFiles: port,
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('use skills', type: type)),
          replyStep('done'),
        ],
        'use skills': [replyStep('ok')],
      },
    );

    test('сценарий «Каталог ребёнка — снимок родителя»: enum skill и '
        'секция skills/catalog побайтово равны родительским, порт файлов '
        'навыков за запуск ребёнка не вызывается', () async {
      final rig = rigFor();
      await rig.open();
      final queriesBefore = port.queries.length;

      await rig.run('go');

      final root = rig.requestsOf('go').first;
      final child = rig.requestsOf('use skills').single;
      expect(skillEnum(child), ['a-skill', 'b-skill']);
      expect(skillEnum(child), skillEnum(root));
      expect(
        skillsSection(child.systemPrompt),
        skillsSection(root.systemPrompt),
      );
      expect(port.queries, hasLength(queriesBefore));
    });

    test('сценарий «Тип без skill»: у explore нет skill и секции '
        'skills/catalog', () async {
      final rig = rigFor(type: 'explore');
      await rig.open();

      await rig.run('go');

      final child = rig.requestsOf('use skills').single;
      expect(toolNamesOf(child), isNot(contains('skill')));
      expect(child.systemPrompt, isNot(contains('## Skills')));
    });

    test('сценарий «Активные навыки родителя не наследуются»: первый запрос '
        'ребёнка — системный промпт и одно user-сообщение, без блока '
        '<skill', () async {
      final rig = SubagentRig(
        skillFiles: port,
        scripts: {
          'go': [
            oneCallStep('s1', 'skill', {'name': 'a-skill'}),
            oneCallStep('c1', 'agent', agentArgs('use skills')),
            replyStep('done'),
          ],
          'use skills': [replyStep('ok')],
        },
      );
      await rig.open();

      await rig.run('go');

      // Родитель действительно загрузил навык: блок есть в его контексте.
      final parent = rig.requestsOf('go').last;
      expect(resultText(parent, 's1'), contains('<skill name="a-skill"'));
      final child = rig.requestsOf('use skills').single;
      expect(child.messages, hasLength(1));
      expect(child.messages.single, isA<UserMessage>());
      expect(firstUserText(child), 'use skills');
      expect(child.systemPrompt, isNot(contains('<skill')));
      expect(
        [
          for (final m in child.messages)
            for (final b in m.content.whereType<TextContent>()) b.text,
        ].join('\n'),
        isNot(contains('<skill')),
      );
    });
  });

  test('сценарий «Файлы навыка пользователя у ребёнка»: read файла навыка '
      'работает, write — outsideWorkspace без обращения к env', () async {
    port.files = SkillFiles(skills: [validSkill('notes')]);
    final hostFs = MemoryExecutionEnv(cwd: '/');
    await hostFs.writeText('$notes/ref.md', 'reference text\n');
    final base = FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), answering(''));
    final rig = SubagentRig(
      skillFiles: port,
      hostFiles: hostFs,
      baseEnv: base,
      config: rigConfig(mode: ModeId.bypass),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('work with notes')),
          replyStep('done'),
        ],
        'work with notes': [
          oneCallStep('s1', 'skill', {'name': 'notes'}),
          oneCallStep('r1', 'read', {'path': '$notes/ref.md'}),
          oneCallStep('w1', 'write', {'path': '$notes/ref.md', 'content': 'x'}),
          replyStep('ok'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    final child = rig.requestsOf('work with notes').last;
    expect(resultIsError(child, 'r1'), isFalse);
    expect(resultText(child, 'r1'), contains('reference text'));
    expect(resultIsError(child, 'w1'), isTrue);
    expect(
      resultText(child, 'w1'),
      'Path is outside the workspace: $notes/ref.md',
    );
    final stored = await hostFs.readText('$notes/ref.md');
    expect((stored as Ok<String, FileError>).value, 'reference text\n');
    expect(base.commands, isEmpty);
  });

  test('сценарий «Корень навыков выше cwd у ребёнка»: exec ребёнка с '
      'записью в SKILL.md корневого каталога навыков — критический, как у '
      'корня, и без решения пользователя не исполняется', () async {
    port.files = const SkillFiles(sessionRoots: ['/repo/.agents/skills']);
    final base = FakeShellEnv(
      MemoryExecutionEnv(cwd: '/repo/app'),
      answering(''),
    );
    final rig = SubagentRig(
      skillFiles: port,
      baseEnv: base,
      narrow: const {},
      config: rigConfig(mode: ModeId.bypass),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('edit a skill')),
          replyStep('done'),
        ],
        'edit a skill': [
          oneCallStep('x1', 'exec', {
            'command': 'cp /tmp/e /repo/.agents/skills/x/SKILL.md',
          }),
          replyStep('stopped'),
        ],
      },
    );
    await rig.open(cwd: '/repo/app');

    await rig.run('go');

    // У ребёнка нет gate (D38): вопрос корня становится отказом, а не
    // исполнением. Итерация 3 заменит отказ вопросом через gate корня.
    expect(
      resultText(rig.requestsOf('edit a skill').last, 'x1'),
      deniedText('exec', 'no approval interface is available'),
    );
    expect(base.commands, isEmpty);
  });
}
