import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

void main() {
  for (final (mode, override, asked, denied) in [
    (ModeId.ask, null, ['r', 'w', 'n', 'x'], <String>[]),
    (ModeId.standard, null, ['w', 'n', 'x'], <String>[]),
    (ModeId.acceptEdits, null, ['n', 'x'], <String>[]),
    (ModeId.bypass, null, ['n'], <String>[]),
    (ModeId.standard, PermissionMode.autopilot, <String>[], ['n']),
  ]) {
    test('${override?.name ?? mode.value}: asks ${asked.join(',')}', () async {
      final gate = FakeGate();
      final p = await PolicyHarness.create(
        mode: mode,
        modeOverride: override,
        gate: gate,
      );

      final outcomes = {
        for (final tool in ['r', 'w', 'n', 'x'])
          tool: (await p.run(tool, const {}, id: 'id_$tool')).outcome,
      };

      expect(gate.requests.map((r) => r.tool), asked);
      expect([
        for (final e in outcomes.entries)
          if (e.value == ToolOutcome.rejected) e.key,
      ], denied);
    });
  }

  test('autopilot denies network with the reason of §7.3', () async {
    final p = await PolicyHarness.create(
      modeOverride: PermissionMode.autopilot,
    );

    final outcome = await p.run('n', const {});

    expect(
      textOf(outcome),
      deniedText(
        'n',
        'network access needs approval and autopilot has no approver',
      ),
    );
  });

  test('plan mode denies write and exec without asking', () async {
    final gate = FakeGate();
    final p = await PolicyHarness.create(mode: ModeId.plan, gate: gate);

    final read = await p.run('r', const {}, id: 'a');
    final write = await p.run('w', const {}, id: 'b');
    final exec = await p.run('x', const {}, id: 'c');

    expect(read.outcome, ToolOutcome.completed);
    expect(write.outcome, ToolOutcome.rejected);
    expect(
      textOf(write),
      deniedText('w', 'plan mode: changes are not allowed'),
    );
    expect(exec.outcome, ToolOutcome.rejected);
    expect(gate.requests, isEmpty);
  });

  test('a mode change applies to the next call', () async {
    final gate = FakeGate();
    final p = await PolicyHarness.create(mode: ModeId.ask, gate: gate);

    await p.run('r', const {}, id: 'a');
    p.policy.mode = ModeId.bypass;
    await p.run('x', const {}, id: 'b');

    expect(gate.requests.map((r) => r.tool), ['r']);
  });
}
