import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:test/test.dart';

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
}
