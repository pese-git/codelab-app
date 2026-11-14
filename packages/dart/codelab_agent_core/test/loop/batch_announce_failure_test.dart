import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/agent_loop.dart';
import 'package:codelab_agent_core/src/loop/loop_config.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

/// Сбой `emit` при объявлении вызова параллельного пакета (TOOL-7, §17.16a):
/// ход заканчивается `failed` с исходной ошибкой, а места очередей пути и
/// ключа освобождаются — следующий вызов не зависает.
void main() {
  for (final (label, makeTool) in <(String, FakeTool Function())>[
    ('key', () => FakeTool('w', lockKeyValue: 'k')),
    ('path', () => FakeTool('w', lockArg: 'path')),
  ]) {
    group('$label queue', () {
      /// Ход из двух вызовов `w`; [failing] решает, на каком событии `emit`
      /// бросает. Сбой не должен задеть `AgentError` и `TurnEnded`.
      Future<(LoopHarness, List<AgentEvent>)> runTurn(
        bool Function(AgentEvent event, int startedSoFar) failing,
      ) async {
        final h = await LoopHarness.create(
          tools: [makeTool()],
          llm: script([
            callStep([
              ('c1', 'w', {'path': 'a'}),
              ('c2', 'w', {'path': 'a'}),
            ]),
            textStep('done'),
          ]),
        );
        final seen = <AgentEvent>[];
        var started = 0;
        await runAgentLoop(
          prompts: [user('go')],
          context: LoopContext(
            systemPrompt: 'You are CodeLab.',
            messages: const [],
            tools: h.tools,
          ),
          config: h.config(),
          emit: (event) {
            if (event is ToolCallStarted) {
              started++;
            }
            if (failing(event, started)) {
              throw StateError('emit failed');
            }
            seen.add(event);
          },
          cancel: CancelToken.none,
        );
        return (h, seen);
      }

      Future<void> expectQueueFree(LoopHarness h) async {
        final handle = await h.executor.announce(
          ToolCall(id: 'c3', name: 'w', arguments: const {'path': 'a'}),
          ToolInvocation(
            sessionId: session,
            cancel: CancelToken.none,
            stepTools: ['w'],
            emit: (_) {},
          ),
        );
        final outcome = await h.executor
            .complete(handle)
            .timeout(const Duration(seconds: 2));
        expect(outcome.outcome, ToolOutcome.completed);
      }

      test('announce failing on c2: failed turn with the original error, '
          'queue is free', () async {
        final (h, seen) = await runTurn(
          (e, started) => e is ToolCallStarted && started == 2,
        );

        final error = seen.whereType<AgentError>().single;
        expect(error.message, 'emit failed');
        expect(seen.whereType<TurnEnded>().single.reason, TurnEndReason.failed);
        // c1 закрыт `abandon` цикла, c2 — best effort самого `announce`.
        expect(
          [
            for (final e in seen.whereType<ToolCallFinished>())
              (e.toolCallId, e.outcome),
          ],
          unorderedEquals([
            ('c1', ToolOutcome.cancelled),
            ('c2', ToolOutcome.cancelled),
          ]),
        );
        await expectQueueFree(h);
      });

      test('emit fails on c2 Started and on every Finished: still failed '
          'with the original error, queue is free', () async {
        final (h, seen) = await runTurn(
          (e, started) =>
              (e is ToolCallStarted && started == 2) || e is ToolCallFinished,
        );

        expect(seen.whereType<AgentError>().single.message, 'emit failed');
        expect(seen.whereType<TurnEnded>().single.reason, TurnEndReason.failed);
        expect(seen.whereType<ToolCallFinished>(), isEmpty);
        await expectQueueFree(h);
      });
    });
  }
}
