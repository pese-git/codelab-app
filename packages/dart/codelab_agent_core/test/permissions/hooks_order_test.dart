import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import 'fake_gate.dart';

void main() {
  // Критерий матрицы core/hooks-order-approval-first (C-12): хуки хоста
  // стоят после политики разрешений и видят только разрешённые вызовы.
  test('a host hook sees a call only after it is allowed', () async {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    await memory.writeText('/proj/a.txt', 'a\n');
    final log = <String>[];
    final gate = FakeGate((request) {
      log.add('gate ${request.toolCallId}');
      return request.toolCallId == 'c1'
          ? PermissionDecision.allowOnce
          : PermissionDecision.rejectOnce;
    });
    final h = CoreHarness.build(
      baseEnv: memory,
      narrow: noExec,
      gate: gate,
      steps: [
        {
          'reply': [
            for (final (id, path) in [('c1', 'a.txt'), ('c2', 'b.txt')])
              {
                'toolCall': {
                  'id': id,
                  'name': 'write',
                  'arguments': {'path': path, 'content': 'x\n'},
                },
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
            log.add('host ${call.id}');
            return null;
          },
        ],
      ),
    );

    final result = await session.prompt([const TextContent('go')]);

    expect(log.indexOf('gate c1'), lessThan(log.indexOf('host c1')));
    expect(log, contains('gate c2'));
    expect(log, isNot(contains('host c2')));
    expect(
      await memory.readText('/proj/a.txt'),
      const Ok<String, FileError>('x\n'),
    );
    expect(result.reason, TurnEndReason.completed);
  });

  test(
    'a throwing afterToolCall is an error result, not a failed turn',
    () async {
      final memory = MemoryExecutionEnv(cwd: '/proj');
      await memory.writeText('/proj/a.txt', 'a\n');
      final h = CoreHarness.build(
        baseEnv: memory,
        narrow: noExec,
        gate: gateAnswering(PermissionDecision.allowOnce),
        steps: [
          callStep('c1', 'read', {'path': 'a.txt'}),
          textStep('ok'),
        ],
      );
      final session = await h.core.runtime.createSession(
        SessionSpec(
          cwd: '/proj',
          mode: ModeId.ask,
          extraAfterToolCall: [
            (call, result, isError) async => throw StateError('hook broke'),
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

      expect(result.reason, TurnEndReason.completed);
      expect(finished.single.outcome, ToolOutcome.failed);
      expect(
        (finished.single.content.single as TextContent).text,
        'hook broke',
      );
      h.model.verify();
    },
  );
}
