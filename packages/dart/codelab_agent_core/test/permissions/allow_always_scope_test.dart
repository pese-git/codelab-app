import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:test/test.dart';

import '../subagents/subagent_rig.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

void main() {
  test(
    'always for write lib/a.dart does not allow lib/b.dart or exec (PERM-3)',
    () async {
      final memory = MemoryExecutionEnv(cwd: '/proj');
      for (final name in ['a', 'b']) {
        await memory.writeText('/proj/lib/$name.dart', 'x = 1;\n');
      }
      final gate = FakeGate(
        (req) => req.rawInput['path'] == 'lib/a.dart'
            ? PermissionDecision.allowAlways
            : PermissionDecision.allowOnce,
      );
      final p = await PolicyHarness.create(
        tools: [EditTool(), ExecTool()],
        gate: gate,
        memory: memory,
      );
      Map<String, Object?> edit(String path, String to) => {
        'path': path,
        'oldText': 'x = ${int.parse(to) - 1};',
        'newText': 'x = $to;',
      };

      await p.run('edit', edit('lib/a.dart', '2'), id: 'a1');
      await p.run('edit', edit('./lib//a.dart', '3'), id: 'a2');
      await p.run('edit', edit('lib/b.dart', '2'), id: 'b1');
      await p.run('exec', {'command': 'dart test'}, id: 'x1');

      expect(gate.requests.map((r) => r.toolCallId), ['a1', 'b1', 'x1']);
    },
  );

  // Характеризующий, зелёный сразу (D42 Т1): `SubagentTool.permissionPattern`
  // уже возвращает имя типа. Сценарий agent-permissions «Всегда для типа
  // субагента»; `agent` в `ask` спрашивает даже на уровне read.
  test('always for agent explore does not allow agent general '
      '(agent-permissions «Всегда для типа субагента», PERM-3)', () async {
    final gate = FakeGate(
      (req) => req.rawInput['type'] == 'explore'
          ? PermissionDecision.allowAlways
          : PermissionDecision.allowOnce,
    );
    final rig = SubagentRig(
      gate: gate,
      config: rigConfig(mode: ModeId.ask),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('look 1', type: 'explore')),
          multiCallStep([
            ('c2', 'agent', agentArgs('look 2', type: 'explore')),
            ('c3', 'agent', agentArgs('work', type: 'general')),
          ]),
          replyStep('done'),
        ],
        'look 1': [replyStep('seen 1')],
        'look 2': [replyStep('seen 2')],
        'work': [replyStep('worked')],
      },
    );
    await rig.open();

    await rig.run('go');

    expect([for (final r in gate.requests) r.toolCallId], ['c1', 'c3']);
    expect(gate.requests.map((r) => r.pattern), ['explore', 'general']);
  });
}
