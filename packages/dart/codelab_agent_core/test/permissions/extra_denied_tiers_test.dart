import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

/// Режим `ask` с запретом write/exec: сочетание `ask` и `plan` слоёв
/// конфигурации (`agent-core-architecture` §15.3; change
/// `add-agent-configuration`, D7).
void main() {
  test(
    'read is still asked, write and exec are denied without a question',
    () async {
      final gate = FakeGate();
      final p = await PolicyHarness.create(
        mode: ModeId.ask,
        gate: gate,
        extraDeniedTiers: {ToolTier.write, ToolTier.exec},
      );

      final read = await p.run('r', const {}, id: 'r1');
      final write = await p.run('w', const {}, id: 'w1');
      final exec = await p.run('x', const {}, id: 'x1');

      expect(read.outcome, ToolOutcome.completed);
      expect(gate.requests.map((r) => r.tool), ['r']);
      expect(
        textOf(write),
        deniedText('w', 'plan mode: changes are not allowed'),
      );
      expect(exec.outcome, ToolOutcome.rejected);
    },
  );

  test('without extra tiers ask mode only asks', () async {
    final gate = FakeGate();
    final p = await PolicyHarness.create(mode: ModeId.ask, gate: gate);

    await p.run('w', const {});

    expect(gate.requests, hasLength(1));
  });

  test('a tier set stays with the mode of the policy (the union)', () async {
    final p = await PolicyHarness.create(
      mode: ModeId.plan,
      extraDeniedTiers: {ToolTier.network},
    );

    expect((await p.run('w', const {})).outcome, ToolOutcome.rejected);
    expect(
      (await p.run('n', const {}, id: 'n1')).outcome,
      ToolOutcome.rejected,
    );
  });
}
