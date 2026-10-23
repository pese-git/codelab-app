import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import '../tools/fake_shell.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

void main() {
  test(
    'always for exec npm test does not allow exec rm -rf / (P-03)',
    () async {
      final gate = FakeGate(
        (req) => req.rawInput['command'] == 'npm test'
            ? PermissionDecision.allowAlways
            : PermissionDecision.rejectOnce,
      );
      final shell = FakeShellEnv(
        MemoryExecutionEnv(cwd: '/proj'),
        answering('ok'),
      );
      final h = await ExecutorHarness.create([ExecTool()], base: shell);
      final p = await PolicyHarness.wrap(h, gate: gate);

      await p.run('exec', {'command': 'npm test'}, id: 'c1');
      final again = await p.run('exec', {'command': ' npm test '}, id: 'c2');
      final other = await p.run('exec', {'command': 'rm -rf /'}, id: 'c3');
      final watch = await p.run('exec', {
        'command': 'npm test --watch',
      }, id: 'c4');

      expect(gate.requests.map((r) => r.toolCallId), ['c1', 'c3', 'c4']);
      expect(again.outcome, ToolOutcome.completed);
      expect(other.outcome, ToolOutcome.rejected);
      expect(watch.outcome, ToolOutcome.rejected);
      expect(shell.commands, ['npm test', ' npm test ']);
    },
  );

  test('reject always is remembered by the same key', () async {
    final gate = FakeGate((_) => PermissionDecision.rejectAlways);
    final shell = FakeShellEnv(
      MemoryExecutionEnv(cwd: '/proj'),
      answering('ok'),
    );
    final h = await ExecutorHarness.create([ExecTool()], base: shell);
    final p = await PolicyHarness.wrap(h, gate: gate);

    await p.run('exec', {'command': 'make'}, id: 'c1');
    final second = await p.run('exec', {'command': 'make'}, id: 'c2');

    expect(gate.requests, hasLength(1));
    expect(
      textOf(second),
      deniedText('exec', 'previously rejected by the user'),
    );
  });
}
