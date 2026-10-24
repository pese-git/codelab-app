import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../tools/fake_shell.dart';
import 'fake_gate.dart';

void main() {
  test('no tool executes without a policy decision', () async {
    final shell = FakeShellEnv(
      MemoryExecutionEnv(cwd: '/proj'),
      answering('ran'),
    );
    await shell.writeText('/proj/a.txt', 'a\n');
    final executedByHost = <String>[];
    final h = CoreHarness.build(
      baseEnv: shell,
      gate: gateAnswering(PermissionDecision.rejectOnce),
      steps: [
        {
          'reply': [
            for (final (id, name, args) in [
              ('c1', 'read', {'path': 'a.txt'}),
              ('c2', 'edit', {'path': 'a.txt', 'oldText': 'a', 'newText': 'b'}),
              ('c3', 'exec', {'command': 'rm -rf build'}),
            ])
              {
                'toolCall': {'id': id, 'name': name, 'arguments': args},
              },
          ],
        },
        textStep('ok'),
      ],
    );
    final session = await h.core.runtime.createSession(
      SessionSpec(
        cwd: '/proj',
        mode: ModeId.ask,
        extraBeforeToolCall: [
          (call, args, ctx) async {
            executedByHost.add(call.name);
            return null;
          },
        ],
      ),
    );
    final finished = <ToolCallFinished>[];
    session.events.listen((e) {
      if (e is ToolCallFinished) {
        finished.add(e);
      }
    });

    final result = await session.prompt([const TextContent('go')]);
    await pumpEventQueue();

    expect(shell.commands, isEmpty);
    expect(
      await shell.readText('/proj/a.txt'),
      const Ok<String, FileError>('a\n'),
    );
    expect(executedByHost, isEmpty);
    expect(finished.map((e) => e.outcome), everyElement(ToolOutcome.rejected));
    expect(finished, hasLength(3));
    expect(result.reason, TurnEndReason.completed);
  });
}
