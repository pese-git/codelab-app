import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'subagent_rig.dart';

/// Блокировки путей общие на всё дерево (TOOL-7; `agent-core/
/// 06-tools.md` §6.3.4; design.md change `add-subagents-and-tasks`, D36 Т2):
/// параллельные правки одного файла родителем и детьми не теряют друг друга.
void main() {
  Future<String> read(MemoryExecutionEnv env) async =>
      ((await env.readText('/proj/foo.txt')) as Ok<String, FileError>).value;

  Map<String, Object?> edit(String from, String to) => {
    'path': 'foo.txt',
    'oldText': from,
    'newText': to,
  };

  test(
    'два ребёнка в accept-edits правят один файл: обе правки на месте',
    () async {
      final env = MemoryExecutionEnv(cwd: '/proj');
      await env.writeText('/proj/foo.txt', 'a b c');
      final rig = SubagentRig(
        baseEnv: env,
        config: rigConfig(mode: ModeId.acceptEdits),
        scripts: {
          'go': [
            multiCallStep([
              ('a1', 'agent', agentArgs('child one', description: 'One')),
              ('a2', 'agent', agentArgs('child two', description: 'Two')),
            ]),
            replyStep('done'),
          ],
          'child one': [
            oneCallStep('e1', 'edit', edit('a', 'A')),
            replyStep('ok'),
          ],
          'child two': [
            oneCallStep('e2', 'edit', edit('b', 'B')),
            replyStep('ok'),
          ],
        },
      );
      await rig.open();

      await rig.run('go');

      expect(await read(env), 'A B c');
    },
  );

  test('[edit, agent(edit)] одной группой: правка корня и правка ребёнка '
      'обе на месте', () async {
    final env = MemoryExecutionEnv(cwd: '/proj');
    await env.writeText('/proj/foo.txt', 'a b c');
    final rig = SubagentRig(
      baseEnv: env,
      config: rigConfig(mode: ModeId.acceptEdits),
      scripts: {
        'go': [
          multiCallStep([
            ('e0', 'edit', edit('a', 'A')),
            ('a1', 'agent', agentArgs('child one', description: 'One')),
          ]),
          replyStep('done'),
        ],
        'child one': [
          oneCallStep('e1', 'edit', edit('b', 'B')),
          replyStep('ok'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    expect(await read(env), 'A B c');
  });
}
