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

  group('a failed announce does not leave the path taken (TOOL-7)', () {
    // Приёмник событий, который бросает на `ToolCallStarted` вызова [id]:
    // контракт `AgentEventSink` этого не запрещает, а `Agent.emit`
    // пробрасывает ошибку подписчика.
    AgentEventSink failingOn(String id, List<AgentEvent> events) => (event) {
      if (event is ToolCallStarted && event.toolCallId == id) {
        throw StateError('subscriber failed');
      }
      events.add(event);
    };

    FakeTool touch(List<String> log) => FakeTool(
      'touch',
      lockArg: 'path',
      onExecute: (args, ctx) {
        log.add('run ${args['id']}');
        return const ToolExecutionResult([TextContent('ok')]);
      },
    );

    ToolCall touchCall(String id) =>
        ToolCall(id: id, name: 'touch', arguments: {'id': id, 'path': 'a.txt'});

    // Следующий вызов того же пути после сбоя: путь свободен — вызов
    // исполняется, а не ждёт тикет, который никто не отпустит.
    Future<void> expectPathFree(
      ToolExecutor executor,
      List<AgentEvent> events,
    ) async {
      final handle = await executor.announce(
        touchCall('c3'),
        ToolInvocation(
          sessionId: ex.session,
          cancel: CancelToken.none,
          stepTools: const ['touch'],
          emit: events.add,
        ),
      );
      var done = false;
      unawaited(executor.complete(handle).then((_) => done = true));
      await _waitFor(() => done);
    }

    test('executor: c1 holds the path, emit of ToolCallStarted throws for '
        'c2, c3 waits for c1 and then runs', () async {
      final log = <String>[];
      final h = await ex.ExecutorHarness.create([touch(log)]);
      final invocation = ToolInvocation(
        sessionId: ex.session,
        cancel: CancelToken.none,
        stepTools: const ['touch'],
        emit: failingOn('c2', h.events),
      );

      final h1 = await h.executor.announce(touchCall('c1'), invocation);
      await expectLater(
        h.executor.announce(touchCall('c2'), invocation),
        throwsStateError,
      );
      final h3 = await h.executor.announce(touchCall('c3'), invocation);
      var thirdDone = false;
      unawaited(h.executor.complete(h3).then((_) => thirdDone = true));
      // Отпущенный при сбое тикет c2 не впускает c3, пока путь держит c1.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(log, isEmpty, reason: 'c3 must wait for c1');

      await h.executor.complete(h1);
      // Тикет c2, не отпущенный при сбое, держал бы путь до конца сессии.
      await _waitFor(() => thirdDone);

      expect(log, ['run c1', 'run c3']);
    });

    test('loop: announce of c2 fails in a parallel batch', () async {
      final log = <String>[];
      final h = await LoopHarness.create(
        tools: [touch(log)],
        llm: script([
          callStep([
            ('c1', 'touch', {'id': 'c1', 'path': 'a.txt'}),
            ('c2', 'touch', {'id': 'c2', 'path': 'a.txt'}),
          ]),
          textStep('done'),
        ]),
      );

      await h.run([user('go')], emit: failingOn('c2', h.events));

      expect(
        h.events.whereType<TurnEnded>().single.reason,
        TurnEndReason.failed,
      );
      // c1 был объявлен до сбоя: его вызов закрыт как отменённый ровно
      // одним финишем, а не брошен с занятым местом в очереди пути. У c2
      // финиша нет — нет «Finished без Started».
      List<String> idsOf<T extends AgentEvent>(String Function(T) id) => [
        for (final e in h.events.whereType<T>()) id(e),
      ];
      expect(idsOf<ToolCallStarted>((e) => e.toolCallId), ['c1']);
      expect(idsOf<ToolCallFinished>((e) => e.toolCallId), ['c1']);
      expect(_finished(h.events, 'c1')?.outcome, ToolOutcome.cancelled);
      expect(log, isEmpty);

      // Следующий ход той же сессии правит тот же путь.
      await expectPathFree(h.executor, h.events);
      expect(log, ['run c3']);
    });

    test('loop: abandon itself fails when the sink breaks for good', () async {
      final log = <String>[];
      final h = await LoopHarness.create(
        tools: [touch(log)],
        llm: script([
          callStep([
            ('c1', 'touch', {'id': 'c1', 'path': 'a.txt'}),
            ('c2', 'touch', {'id': 'c2', 'path': 'a.txt'}),
          ]),
          textStep('done'),
        ]),
      );
      // После `ToolCallStarted(c1)` приёмник бросает на всём: падают
      // объявление c2, финиш отката c1, `AgentError` и `TurnEnded`.
      var broken = false;
      Future<void> sink(AgentEvent event) async {
        if (broken) {
          throw StateError('subscriber is broken');
        }
        h.events.add(event);
        if (event is ToolCallStarted && event.toolCallId == 'c1') {
          broken = true;
        }
      }

      await expectLater(h.run([user('go')], emit: sink), throwsStateError);

      expect(log, isEmpty);
      final abandonErrors = h.logger.eventsOf('tool.abandon.error');
      expect(abandonErrors, hasLength(1));
      expect(abandonErrors.single.fields['tool_call_id'], 'c1');
      // Откат отпустил путь c1 до эмита финиша, сбой которого путь не
      // держит.
      await expectPathFree(h.executor, h.events);
      expect(log, ['run c3']);
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
