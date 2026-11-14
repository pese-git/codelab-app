import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:codelab_agent_core/src/tools/misuse.dart';
import 'package:codelab_agent_core/src/tools/path_lock.dart';
import 'package:test/test.dart';

import '../loop/loop_harness.dart';
import 'executor_harness.dart' as ex;
import 'fake_tools.dart';

void main() {
  test(
    'ten parallel edits of one file are applied in call order (TOOL-7)',
    () async {
      final h = await LoopHarness.create(
        tools: [EditTool()],
        llm: script([
          callStep([
            for (var i = 1; i <= 10; i++)
              (
                'c$i',
                'edit',
                {'path': 'a.txt', 'oldText': 'l$i\n', 'newText': 'L$i\n'},
              ),
          ]),
          textStep('done'),
        ]),
      );
      await h.env.writeText(
        '/proj/a.txt',
        [for (var i = 1; i <= 10; i++) 'l$i\n'].join(),
      );
      // Первые вызовы держатся в хуке дольше последних: без блокировки
      // правки читали бы файл одновременно и затирали друг друга.
      final config = h.config(
        beforeToolCall: [
          (call, args, ctx) async {
            final n = int.parse(call.id.substring(1));
            for (var i = 0; i < 11 - n; i++) {
              await Future<void>.delayed(Duration.zero);
            }
            return null;
          },
        ],
      );

      await h.run([user('go')], config: config);

      expect(
        await h.env.readText('/proj/a.txt'),
        Ok<String, FileError>([for (var i = 1; i <= 10; i++) 'L$i\n'].join()),
      );
      final finished = h.events.whereType<ToolCallFinished>();
      expect(
        finished.map((e) => e.outcome),
        everyElement(ToolOutcome.completed),
      );
    },
  );

  test(
    'calls of different paths run in parallel, of one path in order',
    () async {
      final gate = Completer<void>();
      final log = <String>[];
      final tool = FakeTool(
        'touch',
        lockArg: 'path',
        onExecute: (args, ctx) async {
          log.add('start ${args['id']}');
          if (args['id'] == 'c1') {
            await gate.future;
          }
          log.add('end ${args['id']}');
          return const ToolExecutionResult([TextContent('ok')]);
        },
      );
      final h = await LoopHarness.create(
        tools: [tool],
        llm: script([
          callStep([
            ('c1', 'touch', {'id': 'c1', 'path': 'a.txt'}),
            ('c2', 'touch', {'id': 'c2', 'path': 'b.txt'}),
            ('c3', 'touch', {'id': 'c3', 'path': './a.txt'}),
          ]),
          textStep('done'),
        ]),
      );

      final turn = h.run([user('go')]);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      // c2 (другой путь) закончился, пока c1 держит a.txt; c3 (тот же путь
      // после нормализации) ещё не начинался.
      expect(log, ['start c1', 'start c2', 'end c2']);
      gate.complete();
      await turn;

      expect(log, [
        'start c1',
        'start c2',
        'end c2',
        'end c1',
        'start c3',
        'end c3',
      ]);
    },
  );

  group('a refused middle call keeps the path queue (TOOL-7)', () {
    const params = {
      'type': 'object',
      'required': ['id', 'path'],
      'properties': {
        'id': {'type': 'string'},
        'path': {'type': 'string'},
      },
    };

    // Тело инструмента пишет в журнал начало и конец исполнения; по журналу
    // видно, вошёл ли вызов под блокировку пути.
    FakeTool touch(String name, List<String> log, {String? preflight}) =>
        FakeTool(
          name,
          parameters: params,
          lockArg: 'path',
          preflightText: preflight,
          onExecute: (args, ctx) async {
            log.add('start ${args['id']}');
            await Future<void>.delayed(Duration.zero);
            log.add('end ${args['id']}');
            return const ToolExecutionResult([TextContent('ok')]);
          },
        );

    // Сценарий цикла: c1 ждёт одобрения в хуке, c2 отказывает до захвата
    // пути, c3 пишет тот же путь. c3 не должен начаться, пока c1 не закончил.
    Future<void> expectOrder({
      required String middleTool,
      required Map<String, Object?> middleArgs,
      Block? Function(ToolCall call)? block,
      bool throwInHook = false,
    }) async {
      final approval = Completer<void>();
      final log = <String>[];
      final hooked = <String>{};
      final h = await LoopHarness.create(
        tools: [
          touch('touch', log),
          touch('refuse', log, preflight: 'refused by preflight'),
        ],
        llm: script([
          callStep([
            ('c1', 'touch', {'id': 'c1', 'path': 'a.txt'}),
            ('c2', middleTool, middleArgs),
            ('c3', 'touch', {'id': 'c3', 'path': 'a.txt'}),
          ]),
          textStep('done'),
        ]),
      );
      final config = h.config(
        beforeToolCall: [
          (call, args, ctx) async {
            if (call.id == 'c1') {
              await approval.future;
            }
            if (call.id == 'c2') {
              if (throwInHook) {
                throw StateError('hook failed');
              }
              return block?.call(call);
            }
            hooked.add(call.id);
            return null;
          },
        ],
      );

      final turn = h.run([user('go')], config: config);
      await _waitFor(
        () => hooked.contains('c3') && _finished(h.events, 'c2') != null,
      );
      // После хука c3 синхронно доходит до ожидания пути; при сломанной
      // очереди тело c3 начало бы исполняться за этот оборот.
      await Future<void>.delayed(Duration.zero);
      expect(log, isEmpty, reason: 'c3 must wait for c1');
      approval.complete();
      await turn;

      expect(log, ['start c1', 'end c1', 'start c3', 'end c3']);
    }

    test('validation error', () async {
      await expectOrder(middleTool: 'touch', middleArgs: {'path': 'a.txt'});
    });

    test('preflight refusal', () async {
      await expectOrder(
        middleTool: 'refuse',
        middleArgs: {'id': 'c2', 'path': 'a.txt'},
      );
    });

    test('hook block', () async {
      await expectOrder(
        middleTool: 'touch',
        middleArgs: {'id': 'c2', 'path': 'a.txt'},
        block: (_) => const Block('no'),
      );
    });

    test('hook block with cancelled outcome', () async {
      await expectOrder(
        middleTool: 'touch',
        middleArgs: {'id': 'c2', 'path': 'a.txt'},
        block: (_) => const Block('stop', outcome: ToolOutcome.cancelled),
      );
    });

    test('hook throws', () async {
      await expectOrder(
        middleTool: 'touch',
        middleArgs: {'id': 'c2', 'path': 'a.txt'},
        throwInHook: true,
      );
    });

    // Сценарий исполнителя напрямую: средний вызов завершается путём,
    // которого нет в цикле параллельного пакета (abandon, блок MisuseBreaker).
    Future<void> expectExecutorOrder({
      required Map<String, Object?> middleArgs,
      required Future<ToolExecutionOutcome> Function(
        ToolCallExecutor executor,
        ToolCallHandle handle,
      )
      finishMiddle,
      MisuseBreaker? misuse,
    }) async {
      final approval = Completer<void>();
      final log = <String>[];
      final hooked = <String>{};
      final h = await ex.ExecutorHarness.create([touch('touch', log)]);
      final invocation = h.invocation(
        misuse: misuse,
        before: [
          (call, args, ctx) async {
            if (call.id == 'c1') {
              await approval.future;
            }
            hooked.add(call.id);
            return null;
          },
        ],
      );
      Future<ToolCallHandle> announce(String id, Map<String, Object?> args) =>
          h.executor.announce(
            ToolCall(id: id, name: 'touch', arguments: args),
            invocation,
          );
      final h1 = await announce('c1', {'id': 'c1', 'path': 'a.txt'});
      final h2 = await announce('c2', middleArgs);
      final h3 = await announce('c3', {'id': 'c3', 'path': 'a.txt'});

      final first = h.executor.complete(h1);
      final middle = await finishMiddle(h.executor, h2);
      final third = h.executor.complete(h3);
      await _waitFor(() => hooked.contains('c3'));
      await Future<void>.delayed(Duration.zero);
      expect(log, isEmpty, reason: 'c3 must wait for c1');
      approval.complete();
      await Future.wait([first, third]);

      expect(middle.outcome, isNot(ToolOutcome.completed));
      expect(log, ['start c1', 'end c1', 'start c3', 'end c3']);
    }

    test('abandon before start', () async {
      await expectExecutorOrder(
        middleArgs: {'id': 'c2', 'path': 'a.txt'},
        finishMiddle: (executor, handle) => executor.abandon(handle),
      );
    });

    test('MisuseBreaker block', () async {
      const invalid = {'path': 'a.txt'};
      final breaker = MisuseBreaker(const MisuseLimits());
      final key = MisuseBreaker.keyOf('touch', invalid);
      while (!breaker.isBlocked(key)) {
        breaker.recordInvalid(key);
      }
      await expectExecutorOrder(
        middleArgs: invalid,
        misuse: breaker,
        finishMiddle: (executor, handle) => executor.complete(handle),
      );
    });

    test(
      'turn cancelled while c1 waits for approval: c3 does not write',
      () async {
        final approval = Completer<void>();
        final cancel = CancelTokenSource();
        final log = <String>[];
        final hooked = <String>{};
        final h = await LoopHarness.create(
          tools: [touch('touch', log)],
          llm: script([
            callStep([
              ('c1', 'touch', {'id': 'c1', 'path': 'a.txt'}),
              ('c2', 'touch', {'path': 'a.txt'}),
              ('c3', 'touch', {'id': 'c3', 'path': 'a.txt'}),
            ]),
            textStep('done'),
          ]),
        );
        final config = h.config(
          beforeToolCall: [
            (call, args, ctx) async {
              if (call.id == 'c1') {
                await approval.future;
              }
              hooked.add(call.id);
              return null;
            },
          ],
        );

        final turn = h.run([user('go')], config: config, cancel: cancel.token);
        await _waitFor(() => hooked.contains('c3'));
        await Future<void>.delayed(Duration.zero);
        expect(log, isEmpty, reason: 'c3 must wait for c1');
        cancel.cancel();
        approval.complete();
        await turn;

        expect(log, isEmpty);
        expect(_finished(h.events, 'c3')?.outcome, ToolOutcome.cancelled);
      },
    );
  });

  group('cancelling the turn interrupts the wait for the path (TOOL-7)', () {
    test('c3 waiting behind c1 finishes cancelled at once; c4 still waits '
        'for c1', () async {
      final release = Completer<void>();
      final log = <String>[];
      final tool = FakeTool(
        'touch',
        lockArg: 'path',
        onExecute: (args, ctx) async {
          log.add('start ${args['id']}');
          // c1 держит путь и не реагирует на отмену: ждёт только ворот.
          if (args['id'] == 'c1') {
            await release.future;
          }
          log.add('end ${args['id']}');
          return const ToolExecutionResult([TextContent('ok')]);
        },
      );
      final h = await ex.ExecutorHarness.create([tool]);
      final cancel = CancelTokenSource();
      final turn = h.invocation(cancel: cancel.token);
      // c4 — вызов следующего хода: его отмена текущего хода не касается.
      final next = h.invocation();
      Future<ToolCallHandle> announce(String id, ToolInvocation invocation) =>
          h.executor.announce(
            ToolCall(
              id: id,
              name: 'touch',
              arguments: {'id': id, 'path': 'a.txt'},
            ),
            invocation,
          );
      final h1 = await announce('c1', turn);
      final h3 = await announce('c3', turn);
      final h4 = await announce('c4', next);

      final first = h.executor.complete(h1);
      var thirdDone = false;
      final third = h.executor.complete(h3)..then((_) => thirdDone = true);
      final fourth = h.executor.complete(h4);
      await _waitFor(() => log.contains('start c1'));
      expect(
        h.logger
            .eventsOf('tool.lock.wait')
            .map((r) => r.fields['tool_call_id']),
        containsAll(['c3', 'c4']),
      );

      cancel.cancel();
      await _waitFor(() => thirdDone);
      final outcome = await third;
      expect(outcome.outcome, ToolOutcome.cancelled);
      expect(log, ['start c1'], reason: 'c3 body must not run');
      final cancelled = h.logger.eventsOf('tool.lock.cancelled');
      expect(cancelled.map((r) => r.fields['tool_call_id']), ['c3']);
      expect(cancelled.single.fields['tool'], 'touch');
      expect(_finished(h.events, 'c3')?.outcome, ToolOutcome.cancelled);
      // Путь в логи очереди не попадает (observability.md §43).
      for (final r in [...h.logger.eventsOf('tool.lock.wait'), ...cancelled]) {
        expect(r.fields.keys.toSet(), {'tool', 'tool_call_id'});
      }

      // Тикет c3 отпущен, но c4 всё равно ждёт c1.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(log, ['start c1'], reason: 'c4 must wait for c1');
      release.complete();
      await Future.wait([first, fourth]);

      expect(log, ['start c1', 'end c1', 'start c4', 'end c4']);
    });

    test('path freed and turn cancelled in the same turn of the event loop: '
        'c3 finishes cancelled without running', () async {
      final release = Completer<void>();
      final log = <String>[];
      final tool = FakeTool(
        'touch',
        lockArg: 'path',
        onExecute: (args, ctx) async {
          log.add('start ${args['id']}');
          if (args['id'] == 'c1') {
            await release.future;
          }
          log.add('end ${args['id']}');
          return const ToolExecutionResult([TextContent('ok')]);
        },
      );
      final h = await ex.ExecutorHarness.create([tool]);
      final cancel = CancelTokenSource();
      final turn = h.invocation(cancel: cancel.token);
      Future<ToolCallHandle> announce(String id) => h.executor.announce(
        ToolCall(id: id, name: 'touch', arguments: {'id': id, 'path': 'a.txt'}),
        turn,
      );
      final h1 = await announce('c1');
      final h3 = await announce('c3');

      final first = h.executor.complete(h1);
      final third = h.executor.complete(h3);
      await _waitFor(() => log.contains('start c1'));
      // Держатель отпускает путь, и в тот же оборот приходит отмена хода:
      // какая бы сторона `Future.any` ни победила, тело c3 не исполняется.
      release.complete();
      cancel.cancel();
      final outcomes = await Future.wait([first, third]);

      expect(outcomes.last.outcome, ToolOutcome.cancelled);
      expect(log, ['start c1', 'end c1']);
      expect(_finished(h.events, 'c3')?.outcome, ToolOutcome.cancelled);
    });
  });

  group('PathLock', () {
    test('bodies of one key run one by one in the order of run', () async {
      final lock = PathLock();
      final log = <String>[];
      Future<void> body(String name, int ticks) async {
        log.add('start $name');
        for (var i = 0; i < ticks; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        log.add('end $name');
      }

      await Future.wait([
        lock.run('/a', () => body('1', 3)),
        lock.run('/a', () => body('2', 1)),
        lock.run('/b', () => body('3', 1)),
      ]);

      expect(log.indexOf('end 1'), lessThan(log.indexOf('start 2')));
      expect(log.indexOf('start 3'), lessThan(log.indexOf('end 1')));
    });

    test('a failed body does not block the next holder', () async {
      final lock = PathLock();

      await expectLater(
        lock.run<void>('/a', () async => throw StateError('x')),
        throwsStateError,
      );
      expect(await lock.run('/a', () async => 1), 1);
    });

    test('a reserved ticket keeps the place in the queue', () async {
      final lock = PathLock();
      final log = <String>[];
      final first = lock.reserve('/a');
      final second = lock.reserve('/a');
      final done = second.acquired.then((_) => log.add('second'));

      await Future<void>.delayed(Duration.zero);
      expect(log, isEmpty);
      await first.acquired;
      log.add('first');
      first.release();
      await done;
      second.release();

      expect(log, ['first', 'second']);
    });

    test('release is idempotent', () async {
      final lock = PathLock();
      final ticket = lock.reserve('/a')
        ..release()
        ..release();

      await ticket.acquired;
      expect(await lock.run('/a', () async => 2), 2);
    });
    test('a ticket released early does not let the next one in before the '
        'previous holder releases', () async {
      // Отпущенный без захвата тикет (отказ валидации, блок хука) не
      // должен открывать путь следующему, пока предыдущий держатель
      // ещё не отпустил его (TOOL-7).
      final lock = PathLock();
      final first = lock.reserve('/a');
      final middle = lock.reserve('/a');
      final third = lock.reserve('/a');
      var thirdAcquired = false;
      unawaited(third.acquired.then((_) => thirdAcquired = true));

      middle.release();
      await first.acquired;
      // Старая очередь отдавала путь за одну-две микрозадачи; оборот цикла
      // событий (таймер) выполняется после всех микрозадач, его хватает.
      await Future<void>.delayed(Duration.zero);
      expect(thirdAcquired, isFalse);

      first.release();
      await third.acquired;
      third.release();
      expect(await lock.run('/a', () async => 3), 3);
    });

    test('a repeated early release does not shorten the queue', () async {
      final lock = PathLock();
      final first = lock.reserve('/a');
      lock.reserve('/a')
        ..release()
        ..release();
      final third = lock.reserve('/a');
      var thirdAcquired = false;
      unawaited(third.acquired.then((_) => thirdAcquired = true));

      // Старая очередь отдавала путь за одну-две микрозадачи; оборот цикла
      // событий (таймер) выполняется после всех микрозадач, его хватает.
      await Future<void>.delayed(Duration.zero);
      expect(thirdAcquired, isFalse);
      first.release();
      await third.acquired;
      third.release();
    });
  });
}

/// Ждёт условия по оборотам цикла событий, а не фиксированное число тиков:
/// ожидание привязано к событию сценария и не зависит от длины пути вызова.
Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 1000 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: 'condition was not reached');
}

ToolCallFinished? _finished(List<AgentEvent> events, String id) => events
    .whereType<ToolCallFinished>()
    .where((e) => e.toolCallId == id)
    .firstOrNull;
