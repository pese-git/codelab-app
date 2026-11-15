import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/policy_harness.dart' show deniedText;
import 'subagent_rig.dart';

/// У корня нет gate — нет и у потомков: вопрос ребёнка становится отказом
/// `no approval interface is available` (agent-permissions «Разрешения
/// потомка через gate корневой сессии», последний абзац; design.md change
/// `add-subagents-and-tasks`, D8, D42 Т3, Т6; PERM-5, PERM-4;
/// `agent-core/17-3-subagents.md` §17.3.3 шаг 6).
///
/// Итерация 3 (задача 3.1) сузила тест итерации 2: прежний сценарий D38
/// «ребёнок без gate при gate у корня» заменён сценариями
/// `subagent_permission_prefix_test.dart`; здесь остался только случай, когда
/// gate нет у самого корня. Тесты зелёные до и после задачи 3.2 (регрессия
/// fail-closed).
void main() {
  test('write ребёнка в standard при корне без gate: отказ '
      '`no approval interface is available`, файл не создан', () async {
    final env = MemoryExecutionEnv(cwd: '/proj');
    final rig = SubagentRig(
      baseEnv: env,
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('write a file')),
          replyStep('done'),
        ],
        'write a file': [
          oneCallStep('w1', 'write', {'path': 'a.txt', 'content': 'x'}),
          replyStep('could not write'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    final child = rig.requestsOf('write a file')[1];
    expect(
      resultText(child, 'w1'),
      deniedText('write', 'no approval interface is available'),
    );
    expect(resultIsError(child, 'w1'), isTrue);
    expect(await env.stat('/proj/a.txt'), isA<Err<FileStat, FileError>>());
  });

  test('ребёнок в режиме, где вопроса нет, работает без gate: read и ls '
      'проходят', () async {
    final env = MemoryExecutionEnv(cwd: '/proj');
    await env.writeText('/proj/a.txt', 'alpha\n');
    final rig = SubagentRig(
      baseEnv: env,
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('read it', type: 'explore')),
          replyStep('done'),
        ],
        'read it': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}),
          replyStep('alpha'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    expect(resultIsError(rig.requestsOf('read it')[1], 'r1'), isFalse);
  });
}
