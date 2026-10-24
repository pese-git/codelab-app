import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import '../tools/fake_shell.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

Future<PolicyHarness> _exec({
  ModeId mode = ModeId.bypass,
  PermissionMode? modeOverride,
  PermissionGate? gate,
}) async {
  final shell = FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), answering(''));
  final h = await ExecutorHarness.create([ExecTool()], base: shell);
  return PolicyHarness.wrap(
    h,
    mode: mode,
    modeOverride: modeOverride,
    gate: gate,
  );
}

void main() {
  // Критические команды (PERM-2, PERM-9, P-07): вопрос даже в bypass и после
  // «разрешить всегда», отказ без вопроса в autopilot.
  test('bypass with allowAlways still asks, without allow_always', () async {
    final gate = FakeGate((_) => PermissionDecision.allowAlways);
    final p = await _exec(gate: gate);
    p.policy.decisions.allowAlways.add(const PermissionKey('exec', 'rm -rf /'));

    await p.run('exec', {'command': 'rm -rf /'});
    await p.run('exec', {'command': 'rm -rf /'}, id: 'call_2');

    expect(gate.requests, hasLength(2));
    for (final request in gate.requests) {
      expect(request.allowAlwaysOffered, isFalse);
      expect(
        request.reason,
        'critical command: recursive delete of a protected path',
      );
    }
  });

  test('several labels are joined with "; "', () async {
    final gate = FakeGate();
    final p = await _exec(gate: gate);

    await p.run('exec', {'command': 'sudo rm -rf /'});

    expect(
      gate.requests.single.reason,
      'critical command: recursive delete of a protected path; '
      'privileged command',
    );
  });

  test('autopilot denies a critical command without asking', () async {
    final gate = FakeGate();
    final p = await _exec(modeOverride: PermissionMode.autopilot, gate: gate);

    final outcome = await p.run('exec', {'command': 'rm -rf /'});

    expect(gate.requests, isEmpty);
    expect(outcome.outcome, ToolOutcome.rejected);
    expect(
      textOf(outcome),
      deniedText(
        'exec',
        'critical command blocked in autopilot: '
            'recursive delete of a protected path',
      ),
    );
  });

  test('a quoted command is safe and runs in bypass', () async {
    final gate = FakeGate();
    final p = await _exec(gate: gate);

    final outcome = await p.run('exec', {
      'command': 'git commit -m "rm -rf /"',
    });

    expect(gate.requests, isEmpty);
    expect(outcome.outcome, ToolOutcome.completed);
  });

  test('an unparsable command asks', () async {
    final gate = FakeGate();
    final p = await _exec(gate: gate);

    await p.run('exec', {'command': 'echo "unclosed'});

    expect(gate.requests.single.reason, 'critical command: unparsable command');
  });
}
