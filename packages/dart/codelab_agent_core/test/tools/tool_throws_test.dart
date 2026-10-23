import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'executor_harness.dart';
import 'fake_tools.dart';

void main() {
  for (final (thrown, text) in [
    (StateError('x'), 'x'),
    (ArgumentError('bad'), 'bad'),
    (Exception('Bad state: nested'), 'nested'),
    (const FormatException('broken json'), 'FormatException: broken json'),
  ]) {
    test(
      '${thrown.runtimeType} → "$text" without Dart prefixes (TOOL-3)',
      () async {
        final h = await ExecutorHarness.create([
          FakeTool('boom', onExecute: (args, ctx) => throw thrown),
        ]);

        final outcome = await h.run('boom', const {});

        expect(outcome.outcome, ToolOutcome.failed);
        expect(outcome.message.isError, isTrue);
        expect(textOf(outcome), text);
      },
    );
  }
}
