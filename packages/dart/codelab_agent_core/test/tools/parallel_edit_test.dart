import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/path_lock.dart';
import 'package:test/test.dart';

import '../loop/loop_harness.dart';
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
  });
}
