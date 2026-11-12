import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'task_harness.dart';

/// Наблюдаемость и устойчивость списка задач (`17-16-task-list.md` §17.16.2;
/// design.md change `add-subagents-and-tasks`, D18; `AGENTS.md` §16).
void main() {
  group('логи task.op и task.rejected (D18)', () {
    late RecordingLogger logger;
    late TaskHarness h;

    setUp(() async {
      logger = RecordingLogger();
      h = await TaskHarness.create(logger: logger);
    });

    test(
      'принятая операция: op, actor, ids, session_id, tool_call_id',
      () async {
        await h.run('task_create', {
          'subject': 'secret subject',
          'description': 'secret description',
        }, id: 'call_a');
        await h.run('task_update', {
          'id': '1',
          'status': 'deleted',
        }, id: 'call_b');

        final [created, deleted] = logger.eventsOf('task.op');
        expect(created.fields, {
          'session_id': 'sess-1',
          'tool_call_id': 'call_a',
          'op': 'create',
          'actor': 'main',
          'ids': ['1'],
        });
        expect(deleted.fields['op'], 'delete');
        expect(deleted.fields['ids'], ['1']);
      },
    );

    test('отклонённая операция: причина без subject и description', () async {
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {
        'subject': 'b',
        'blocked_by': ['1'],
      });
      final cases = <(String, Map<String, Object?>, String)>[
        (
          'task_update',
          {
            'id': '1',
            'blocked_by': ['2'],
          },
          'cycle',
        ),
        ('task_update', {'id': '9', 'status': 'completed'}, 'unknown_id'),
        ('task_create', {'subject': 'secret ${'x' * 300}'}, 'validation'),
        ('task_create', {'subject': 'c', 'owner': 'sub_x'}, 'owner'),
        (
          'task_create',
          {
            'subject': 'c',
            'blocked_by': ['7'],
          },
          'blocked_by',
        ),
      ];
      for (final (i, (tool, args, _)) in cases.indexed) {
        await h.run(tool, args, id: 'rej_$i');
      }
      for (var n = 0; n < 98; n++) {
        await h.run('task_create', {'subject': 'fill $n'});
      }
      await h.run('task_create', {'subject': 'over'}, id: 'rej_limit');

      final rejected = logger.eventsOf('task.rejected');
      expect(
        [for (final r in rejected) r.fields['reason']],
        ['cycle', 'unknown_id', 'validation', 'owner', 'blocked_by', 'limit'],
      );
      expect(rejected.first.fields['session_id'], 'sess-1');
      expect(rejected.first.fields['tool_call_id'], 'rej_0');
      expect(rejected.first.fields['actor'], 'main');
      for (final r in rejected) {
        expect('${r.fields}', isNot(contains('secret')));
        expect('${r.fields}', isNot(contains('over')));
      }
    });
  });

  group('ошибка публикации внутри apply', () {
    test('замок жив после ошибки публикации; результат соответствует '
        'состоянию', () async {
      var calls = 0;
      final logger = RecordingLogger();
      final h = await TaskHarness.create(
        logger: logger,
        publish: (items, change) {
          if (++calls == 1) {
            throw StateError('subscriber failed');
          }
        },
      );

      final first = await h.run('task_create', {'subject': 'a'});
      final second = await h.run('task_create', {'subject': 'b'});

      expect(first.outcome, ToolOutcome.completed);
      expect(textOf(first), startsWith('Created task #1: a.'));
      expect(h.tasks.items.map((i) => i.id), ['1', '2']);
      expect(textOf(second), contains('Task list: 2 items'));
      final failed = logger.eventsOf('task.publish.failed').single;
      expect(failed.fields['op'], 'create');
      expect(failed.error, contains('subscriber failed'));
    });

    test('асинхронная ошибка публикации тоже не ломает замок', () async {
      final list = SessionTaskList(
        publish: (items, change) async => throw StateError('late'),
      );

      final result = await list.apply(
        CreateTask(subject: 'a'),
        const MainActor(),
      );
      await list.restore(const [], nextId: 5, announce: true);
      final next = await list.apply(
        CreateTask(subject: 'b'),
        const MainActor(),
      );

      expect(result, isA<TaskApplied>());
      expect((next as TaskApplied).item!.id, '5');
    });
  });

  group('снимок списка в TaskApplied', () {
    test('результат операции несёт список сразу после неё', () async {
      final list = SessionTaskList();

      final first = list.apply(CreateTask(subject: 'a'), const MainActor());
      final second = list.apply(CreateTask(subject: 'b'), const MainActor());

      expect(((await first) as TaskApplied).snapshot.map((i) => i.id), ['1']);
      expect(((await second) as TaskApplied).snapshot.map((i) => i.id), [
        '1',
        '2',
      ]);
    });

    test(
      'сводка параллельных вызовов строится по снимку своей операции',
      () async {
        final h = await TaskHarness.create();

        final a = h.run('task_create', {'subject': 'a'});
        final b = h.run('task_create', {'subject': 'b'});

        expect(textOf(await a), contains('Task list: 1 items'));
        expect(textOf(await b), contains('Task list: 2 items'));
      },
    );
  });

  group('предел id и поле id в task.rejected', () {
    test('id за пределом журнала не выдаётся: limit', () async {
      final logger = RecordingLogger();
      final list = SessionTaskList(logger: logger);
      await list.restore(const [], nextId: maxTaskIdValue, announce: false);

      final last = await list.apply(
        CreateTask(subject: 'a'),
        const MainActor(),
      );
      final over = await list.apply(
        CreateTask(subject: 'b'),
        const MainActor(),
      );

      expect((last as TaskApplied).item!.id, '$maxTaskIdValue');
      expect((over as TaskRejected).reason, TaskRejectReason.limit);
      expect(list.items.map((i) => i.id), ['$maxTaskIdValue']);
      expect(logger.eventsOf('task.rejected').single.fields['reason'], 'limit');
    });

    test(
      'id в логе только если он проходит формат; иначе id_invalid',
      () async {
        final logger = RecordingLogger();
        final list = SessionTaskList(logger: logger);
        final long = 'x' * 500;

        await list.apply(
          UpdateTask('7', status: TaskStatus.completed),
          const MainActor(),
        );
        await list.apply(DeleteTask(long), const MainActor());

        final [valid, invalid] = logger.eventsOf('task.rejected');
        expect(valid.fields['id'], '7');
        expect(valid.fields, isNot(contains('id_invalid')));
        expect(invalid.fields, isNot(contains('id')));
        expect(invalid.fields['id_invalid'], isTrue);
        expect('${invalid.fields}', isNot(contains('xxx')));
      },
    );
  });
}
