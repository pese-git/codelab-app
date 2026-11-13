import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../permissions/policy_harness.dart' show deniedText;
import 'subagent_rig.dart';

/// Вопрос ребёнка без gate — отказ; gate корня не вызывается (design.md
/// change `add-subagents-and-tasks`, D38, D36 Т10; PERM-4, PERM-5;
/// `agent-core/17-3-subagents.md` §17.3.3 шаг 6).
///
/// Красный до задачи 2.4: нет ребёнка. Тест живёт только между PR итераций 2
/// и 3: итерация 3 заменяет его сценариями agent-permissions «Разрешения
/// потомка через gate корневой сессии» (`SubagentPermissionGate`, цепочка
/// `toolCallId`). Почему не gate корня напрямую: сырой `call_1` ребёнка не
/// уникален в сессии корня (PERM-4) и показал бы запрос без пути и префикса.
void main() {
  test('write ребёнка в standard требует вопроса: отказ '
      '`no approval interface is available`, gate корня не вызван', () async {
    final gate = FakeGate();
    final env = MemoryExecutionEnv(cwd: '/proj');
    final rig = SubagentRig(
      baseEnv: env,
      gate: gate,
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
    expect(gate.requests, isEmpty);
    expect(await env.stat('/proj/a.txt'), isA<Err<FileStat, FileError>>());
  });

  test('вызов agent самого корня gate не беспокоит (tier read), а write '
      'корня после ребёнка по-прежнему идёт к gate', () async {
    final gate = FakeGate();
    final rig = SubagentRig(
      gate: gate,
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('write a file')),
          oneCallStep('w0', 'write', {'path': 'root.txt', 'content': 'y'}),
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

    expect([for (final r in gate.requests) r.toolCallId], ['w0']);
  });

  test('ребёнок в режиме, где вопроса нет, работает без gate: read и ls '
      'проходят', () async {
    final env = MemoryExecutionEnv(cwd: '/proj');
    await env.writeText('/proj/a.txt', 'alpha\n');
    final rig = SubagentRig(
      baseEnv: env,
      gate: FakeGate(),
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
