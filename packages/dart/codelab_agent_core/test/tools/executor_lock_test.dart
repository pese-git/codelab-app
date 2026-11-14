import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:test/test.dart';

import 'executor_harness.dart';
import 'fake_tools.dart';

/// Очереди точки исполнения (`PathLock` путей — TOOL-7, ключи `lockKey` —
/// §17.16a.4, исследование D39-alt): освобождение мест на всех путях
/// завершения и диагностика ожидания (`agent-core-architecture` §6.3.7,
/// AGENTS.md §16).
void main() {
  /// Эмит, который бросает на [n]-м по счёту `ToolCallStarted`.
  AgentEventSink throwingOn(int n, List<AgentEvent> events) {
    var started = 0;
    return (event) {
      if (event is ToolCallStarted && ++started == n) {
        throw StateError('emit failed');
      }
      events.add(event);
    };
  }

  ToolInvocation invocationWith(ExecutorHarness h, AgentEventSink emit) =>
      ToolInvocation(
        sessionId: session,
        cancel: CancelToken.none,
        stepTools: [for (final t in h.registry.tools) t.name],
        emit: emit,
      );

  // Для пути то же самое проверяет `parallel_edit_test.dart` (TOOL-7).
  test('key: next call with the same key does not hang after a failed '
      'announce', () async {
    final h = await ExecutorHarness.create([FakeTool('w', lockKeyValue: 'k')]);
    final inv = invocationWith(h, throwingOn(1, h.events));

    await expectLater(
      h.executor.announce(
        ToolCall(id: 'c1', name: 'w', arguments: const {}),
        inv,
      ),
      throwsStateError,
    );

    final outcome = await h
        .run('w', const {}, id: 'c2')
        .timeout(const Duration(seconds: 2));
    expect(outcome.outcome, ToolOutcome.completed);
  });

  test(
    'lockKey throwing on raw arguments does not leak the path ticket',
    () async {
      final h = await ExecutorHarness.create([
        FakeTool(
          'w',
          lockArg: 'path',
          lockKeyOf: (args) {
            if (args['boom'] == true) {
              throw StateError('bad key');
            }
            return null;
          },
        ),
      ]);

      await expectLater(
        h.executor.announce(
          ToolCall(
            id: 'c1',
            name: 'w',
            arguments: const {'path': 'a', 'boom': true},
          ),
          h.invocation(),
        ),
        throwsStateError,
      );

      final outcome = await h
          .run('w', const {'path': 'a'}, id: 'c2')
          .timeout(const Duration(seconds: 2));
      expect(outcome.outcome, ToolOutcome.completed);
    },
  );

  test('abandon releases the key ticket', () async {
    final h = await ExecutorHarness.create([FakeTool('w', lockKeyValue: 'k')]);
    final first = await h.executor.announce(
      ToolCall(id: 'c1', name: 'w', arguments: const {}),
      h.invocation(),
    );
    final second = await h.executor.announce(
      ToolCall(id: 'c2', name: 'w', arguments: const {}),
      h.invocation(),
    );

    await h.executor.abandon(first);

    final outcome = await h.executor
        .complete(second)
        .timeout(const Duration(seconds: 2));
    expect(outcome.outcome, ToolOutcome.completed);
  });

  // Формат логов — как у пути (`tool.lock.wait`, без `session_id`), плюс
  // `key`; отдельного `tool.lock.acquired` и прерывания ожидания ключа нет:
  // после захвата ключа отмена не проверяется (D35 «Отмена»).
  test('key: tool.lock.wait carries the key, not arguments', () async {
    final release = Completer<void>();
    final tool = FakeTool(
      'w',
      lockKeyValue: 'tasks',
      onExecute: (args, ctx) async {
        if (args['n'] == 1) {
          await release.future;
        }
        return const ToolExecutionResult([TextContent('ok')]);
      },
    );
    final h = await ExecutorHarness.create([tool]);
    final first = h.run('w', const {'n': 1}, id: 'c1');
    final second = h.run('w', const {'n': 2}, id: 'c2');
    await pumpEventQueue();
    release.complete();
    await Future.wait([first, second]);

    final waits = h.logger.eventsOf('tool.lock.wait');
    expect(waits, hasLength(2));
    expect(waits.every((w) => w.level == LogLevel.debug), isTrue);
    expect(waits.last.fields, {
      'tool': 'w',
      'tool_call_id': 'c2',
      'key': 'tasks',
    });
  });
}
