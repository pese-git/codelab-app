import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import '../tools/fake_shell.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

/// Шаблон «всегда» и метка критического правила в запросе разрешения:
/// `AcpPermissionGate` называет ими варианты и `_meta.codelab.critical`
/// (§7.8, §13.9; design.md change `add-dart-agent-acp-server`, D13).
void main() {
  Future<(PolicyHarness, FakeGate)> harness(ModeId mode) async {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    await memory.writeText('/proj/README.md', '# foo\n');
    final h = await ExecutorHarness.create([
      EditTool(),
      ExecTool(),
    ], base: FakeShellEnv(memory, answering('')));
    final gate = FakeGate((_) => PermissionDecision.rejectOnce);
    return (await PolicyHarness.wrap(h, mode: mode, gate: gate), gate);
  }

  test('an ordinary request names its pattern, no critical label', () async {
    final (p, gate) = await harness(ModeId.standard);

    await p.run('edit', {
      'path': 'README.md',
      'oldText': 'foo',
      'newText': 'bar',
    });

    final request = gate.requests.single;
    expect(request.pattern, 'README.md');
    expect(request.criticalLabel, isNull);
  });

  test('a critical command carries the label of its rule', () async {
    final (p, gate) = await harness(ModeId.bypass);

    await p.run('exec', {'command': 'rm -rf /'});

    final request = gate.requests.single;
    expect(request.criticalLabel, 'recursive delete of a protected path');
    expect(request.reason, 'critical command: ${request.criticalLabel}');
    expect(request.allowAlwaysOffered, isFalse);
  });
}
