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

  group('announce failure releases tickets', () {
    for (final (label, tool) in [
      ('path', FakeTool('w', lockArg: 'path')),
      ('key', FakeTool('w', lockKeyValue: 'k')),
    ]) {
      test('$label: next call with the same $label does not hang', () async {
        final h = await ExecutorHarness.create([tool]);
        final inv = invocationWith(h, throwingOn(1, h.events));

        await expectLater(
          h.executor.announce(
            ToolCall(id: 'c1', name: 'w', arguments: const {'path': 'a'}),
            inv,
          ),
          throwsStateError,
        );

        final outcome = await h
            .run('w', const {'path': 'a'}, id: 'c2')
            .timeout(const Duration(seconds: 2));
        expect(outcome.outcome, ToolOutcome.completed);
      });
    }
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

  group('lock diagnostics', () {
    test(
      'key: wait and acquired with waited_ms; no log without queue',
      () async {
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
        await pumpEventQueue();
        expect(h.logger.eventsOf('tool.lock.wait'), isEmpty);

        final second = h.run('w', const {'n': 2}, id: 'c2');
        await pumpEventQueue();
        final waits = h.logger.eventsOf('tool.lock.wait');
        expect(waits, hasLength(1));
        expect(waits.single.level, LogLevel.debug);
        expect(waits.single.fields, {
          'tool': 'w',
          'tool_call_id': 'c2',
          'session_id': 'sess-1',
          'key': 'tasks',
        });
        expect(h.logger.eventsOf('tool.lock.acquired'), isEmpty);

        await h.clock.elapse(const Duration(milliseconds: 30));
        release.complete();
        await Future.wait([first, second]);

        final acquired = h.logger.eventsOf('tool.lock.acquired');
        expect(acquired, hasLength(1));
        expect(acquired.single.fields, {
          'tool': 'w',
          'tool_call_id': 'c2',
          'session_id': 'sess-1',
          'key': 'tasks',
          'waited_ms': 30,
        });
      },
    );

    test('path: wait, acquired and cancelled after the wait', () async {
      final release = Completer<void>();
      final tool = FakeTool(
        'w',
        lockArg: 'path',
        onExecute: (args, ctx) async {
          if (args['n'] == 1) {
            await release.future;
          }
          return const ToolExecutionResult([TextContent('ok')]);
        },
      );
      final h = await ExecutorHarness.create([tool]);
      final source = CancelTokenSource();
      final inv = h.invocation(cancel: source.token);
      final first = h.run(
        'w',
        const {'path': 'a.txt', 'n': 1},
        id: 'c1',
        invocation: inv,
      );
      await pumpEventQueue();
      final second = h.run(
        'w',
        const {'path': 'a.txt', 'n': 2},
        id: 'c2',
        invocation: inv,
      );
      await pumpEventQueue();
      source.cancel();
      release.complete();
      await Future.wait([first, second]);

      final waits = h.logger.eventsOf('tool.lock.wait');
      expect(waits, hasLength(1));
      expect(waits.single.fields, {
        'tool': 'w',
        'tool_call_id': 'c2',
        'session_id': 'sess-1',
        'path': 'a.txt',
      });
      expect(h.logger.eventsOf('tool.lock.acquired'), hasLength(1));
      final cancelled = h.logger.eventsOf('tool.lock.cancelled');
      expect(cancelled, hasLength(1));
      expect(cancelled.single.fields['tool_call_id'], 'c2');
      expect(cancelled.single.fields['path'], 'a.txt');
      expect(cancelled.single.fields['session_id'], 'sess-1');
    });

    test(
      'path outside cwd is logged as a marker, not as absolute path',
      () async {
        final release = Completer<void>();
        final tool = FakeTool(
          'w',
          lockArg: 'path',
          onExecute: (args, ctx) async {
            if (args['n'] == 1) {
              await release.future;
            }
            return const ToolExecutionResult([TextContent('ok')]);
          },
        );
        final h = await ExecutorHarness.create([tool]);
        final first = h.run('w', const {'path': '/etc/x', 'n': 1}, id: 'c1');
        await pumpEventQueue();
        final second = h.run('w', const {'path': '/etc/x', 'n': 2}, id: 'c2');
        await pumpEventQueue();
        release.complete();
        await Future.wait([first, second]);

        final waits = h.logger.eventsOf('tool.lock.wait');
        expect(waits.single.fields['path'], '<outside cwd>');
      },
    );
  });
}
