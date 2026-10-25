import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'fake_gate.dart';
import 'policy_harness.dart';

/// Отмена хода во время вопроса — исход `cancelled`, а `cancelled` клиента
/// без отмены хода — отказ `rejected` (PERM-7; §13.7, «Статусы вызова»;
/// design.md change `add-dart-agent-acp-server`, D13).
void main() {
  test('the turn is cancelled while asking: outcome cancelled', () async {
    final cancel = CancelTokenSource();
    final gate = FakeGate((_) {
      cancel.cancel();
      return PermissionDecision.cancelled;
    });
    final p = await PolicyHarness.create(gate: gate);

    final outcome = await p.run('w', const {}, cancel: cancel.token);

    expect(outcome.outcome, ToolOutcome.cancelled);
  });

  test('cancelled by the client without a turn cancel: rejected', () async {
    final p = await PolicyHarness.create(
      gate: gateAnswering(PermissionDecision.cancelled),
    );

    final outcome = await p.run('w', const {});

    expect(outcome.outcome, ToolOutcome.rejected);
  });
}
