import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import 'policy_harness.dart';

void main() {
  test('without a gate a question becomes a denial (PERM-5)', () async {
    final p = await PolicyHarness.create();

    final read = await p.run('r', const {}, id: 'a');
    final write = await p.run('w', const {}, id: 'b');

    expect(read.outcome, ToolOutcome.completed);
    expect(write.outcome, ToolOutcome.rejected);
    expect(
      textOf(write),
      deniedText('w', 'no approval interface is available'),
    );
  });
}
