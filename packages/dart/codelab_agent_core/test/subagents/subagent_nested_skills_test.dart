import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../skills/skills_support.dart';
import '../tools/fake_shell.dart';
import 'subagent_rig.dart';

/// Внук получает пути и снимок корня (agent-subagents «Вложенность и слоты
/// дерева», сценарий «Внук получает пути и снимок корня»; SKL-9, PERM-11,
/// SUB-1; design.md change `add-subagents-and-tasks`, D34, D45 Т2;
/// `agent-core/17-3-subagents.md` §17.3.3, шаги 5 и 8).
///
/// Красные до задачи 4.2: потомку не даётся `agent`, поэтому внука нет, а
/// менеджер потомка должен передавать внуку те же `skills`,
/// `agentConfigPaths` и `readOnlyRoots`, что у корня, а не пересчитывать
/// их.
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

  test('схема skill и секция skills/catalog внука совпадают с корневыми; '
      'порт файлов навыков за запуск потомков не вызывается', () async {
    port.files = SkillFiles(
      skills: [validSkill('a-skill'), validSkill('b-skill')],
    );
    final rig = SubagentRig(
      skillFiles: port,
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('kid job')),
          replyStep('done'),
        ],
        'kid job': [
          oneCallStep('g1', 'agent', agentArgs('grandchild job')),
          replyStep('kid done'),
        ],
        'grandchild job': [replyStep('ok')],
      },
    );
    await rig.open();
    final queriesBefore = port.queries.length;

    await rig.run('go');

    final root = rig.requestsOf('go').first;
    expect(rig.requestsOf('grandchild job'), hasLength(1), reason: 'нет внука');
    final grandchild = rig.requestsOf('grandchild job').single;
    expect(skillEnum(grandchild), ['a-skill', 'b-skill']);
    expect(skillEnum(grandchild), skillEnum(root));
    expect(
      skillsSection(grandchild.systemPrompt),
      skillsSection(root.systemPrompt),
    );
    expect(port.queries, hasLength(queriesBefore));
  });

  test('readOnlyRoots навыков внука — как у корня: read файла навыка '
      'работает, write — outsideWorkspace', () async {
    port.files = SkillFiles(skills: [validSkill('notes')]);
    final hostFs = MemoryExecutionEnv(cwd: '/');
    await hostFs.writeText('$notes/ref.md', 'reference text\n');
    final rig = SubagentRig(
      skillFiles: port,
      hostFiles: hostFs,
      config: rigConfig(mode: ModeId.bypass),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('kid job')),
          replyStep('done'),
        ],
        'kid job': [
          oneCallStep('g1', 'agent', agentArgs('grandchild job')),
          replyStep('kid done'),
        ],
        'grandchild job': [
          oneCallStep('r1', 'read', {'path': '$notes/ref.md'}),
          oneCallStep('w1', 'write', {'path': '$notes/ref.md', 'content': 'x'}),
          replyStep('ok'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    expect(rig.requestsOf('grandchild job'), isNotEmpty, reason: 'нет внука');
    final grandchild = rig.requestsOf('grandchild job').last;
    expect(resultIsError(grandchild, 'r1'), isFalse);
    expect(resultText(grandchild, 'r1'), contains('reference text'));
    expect(resultIsError(grandchild, 'w1'), isTrue);
    expect(
      resultText(grandchild, 'w1'),
      'Path is outside the workspace: $notes/ref.md',
    );
  });

  test('защищаемые пути политики внука — набор корня: запись в '
      '.codelab/config.yaml при bypass — критический вопрос к gate корня '
      'с цепочкой из трёх сегментов и без «разрешить всегда»', () async {
    final shell = FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), answering(''));
    final gate = FakeGate((_) => PermissionDecision.rejectOnce);
    final rig = SubagentRig(
      baseEnv: shell,
      narrow: const {},
      gate: gate,
      agentConfigPaths: AgentConfigPaths(
        paths: const ['/home/u/.codelab'],
        expansions: const {
          'HOME': '/home/u',
          'CODELAB_HOME': '/home/u/.codelab',
        },
      ),
      config: rigConfig(mode: ModeId.bypass),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('kid job')),
          replyStep('done'),
        ],
        'kid job': [
          oneCallStep('g1', 'agent', agentArgs('grandchild job')),
          replyStep('kid done'),
        ],
        'grandchild job': [
          oneCallStep('w1', 'write', {
            'path': '.codelab/config.yaml',
            'content': 'x',
          }),
          replyStep('stopped'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    expect(gate.requests, hasLength(1), reason: 'внук не спросил gate корня');
    final request = gate.requests.single;
    expect(request.toolCallId, 'c1/g1/w1');
    expect(request.allowAlwaysOffered, isFalse);
    expect(request.reason, contains('agent configuration'));
  });
}
