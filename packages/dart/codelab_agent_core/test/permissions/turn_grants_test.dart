import 'package:test/test.dart';

import 'fake_gate.dart';
import 'policy_harness.dart';

void main() {
  test('a turn grant does not survive clearTurnGrants (PERM-8)', () async {
    final gate = FakeGate();
    final p = await PolicyHarness.create(gate: gate);
    p.policy.grantForTurn(allow: {'x'});

    await p.run('x', const {}, id: 'first');
    p.policy.clearTurnGrants();
    await p.run('x', const {}, id: 'second');

    expect(gate.requests.map((r) => r.toolCallId), ['second']);
  });
}
