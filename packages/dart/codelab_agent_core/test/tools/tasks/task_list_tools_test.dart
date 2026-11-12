import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/tasks/task_tools.dart';
import 'package:test/test.dart';

import 'task_harness.dart';

/// Инструменты списка задач (agent-tools «Инструменты списка задач»;
/// `agent-core/17-16-task-list.md` §17.16.3, TSK-1, TSK-3).
///
/// Красные до задачи 1.2: нет `TaskList`, `TaskItem`, `TaskListChanged`,
/// `ToolServices.tasks` и самих инструментов `task_*`.
void main() {
  late TaskHarness h;

  setUp(() async {
    h = await TaskHarness.create();
  });

  group('схемы, tier и kind (§17.16.3)', () {
    final tools = <AgentTool>[
      TaskCreateTool(),
      TaskUpdateTool(),
      TaskListTool(),
      TaskGetTool(),
    ];

    test('имена и порядок: create, update, list, get', () {
      expect(
        [for (final t in tools) t.name],
        ['task_create', 'task_update', 'task_list', 'task_get'],
      );
    });

    test('tier read, kind think, вывод trusted, шаблон разрешения *', () {
      for (final tool in tools) {
        expect(tool.tier, ToolTier.read, reason: tool.name);
        expect(tool.kind, ToolKind.think, reason: tool.name);
        expect(tool.outputTrust(const {}), ContentTrust.trusted);
        expect(tool.permissionPattern(const {}, '/proj'), '*');
      }
    });

    test('обязательные параметры и enum статусов', () {
      final create = TaskCreateTool().parameters;
      final update = TaskUpdateTool().parameters;

      expect(create['required'], ['subject']);
      expect(
        (create['properties']! as Map)['priority'],
        containsPair('enum', ['high', 'medium', 'low']),
      );
      expect(update['required'], ['id']);
      expect(
        (update['properties']! as Map)['status'],
        containsPair('enum', [
          'pending',
          'in_progress',
          'completed',
          'deleted',
        ]),
      );
      expect(TaskGetTool().parameters['required'], ['id']);
      expect(
        (TaskListTool().parameters['properties'] as Map?) ?? const {},
        isEmpty,
      );
    });
  });

  // Сценарий «Создание, разблокировка и удаление» (`core/task-list-create-update`).
  test('создание, разблокировка и удаление: шесть TaskListChanged', () async {
    final created1 = await h.run('task_create', {'subject': 'Read the test'});
    final created2 = await h.run('task_create', {
      'subject': 'Fix the parser',
      'blocked_by': ['1'],
    });
    await h.run('task_create', {'subject': 'Update the docs'});

    final done = await h.run('task_update', {'id': '1', 'status': 'completed'});
    await h.run('task_update', {'id': '3', 'status': 'deleted'});
    final created4 = await h.run('task_create', {'subject': 'Run the tests'});

    expect(created1.outcome, ToolOutcome.completed);
    expect(created2.outcome, ToolOutcome.completed);
    expect(textOf(created4), startsWith('Created task #4: Run the tests.'));
    expect(textOf(done), contains('Unblocked: #2 Fix the parser'));
    final listed = await h.text('task_list', {});
    expect(listed.split('\n'), [
      '#1 [completed] Read the test',
      '#2 [pending] Fix the parser',
      '#4 [pending] Run the tests',
    ]);
    // По одному событию на операцию, изменившую список; task_list не считается.
    expect(h.changes, hasLength(6));
    expect(
      [for (final c in h.changes) c.change.op],
      ['create', 'create', 'create', 'update', 'delete', 'create'],
    );
  });

  group('task_create', () {
    test('результат: Created task + строка сводки', () async {
      final text = await h.text('task_create', {
        'subject': 'Read main.dart',
        'priority': 'high',
      });

      expect(text, '''
Created task #1: Read main.dart.
Task list: 1 items (0 completed, 0 in progress, 1 pending).''');
    });

    test('умолчания: priority medium, owner main, без блокеров', () async {
      await h.run('task_create', {'subject': 'a'});

      final item = h.tasks.items.single;
      expect(item.id, '1');
      expect(item.status, TaskStatus.pending);
      expect(item.priority, TaskPriority.medium);
      expect(item.owner, TaskOwner.main);
      expect(item.blockedBy, isEmpty);
      expect(item.description, isNull);
    });

    test('TaskListChanged: весь список и change до ToolCallFinished', () async {
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {'subject': 'b', 'description': 'details'});

      final kinds = [for (final e in h.events) e.runtimeType];
      expect(kinds, [
        ToolCallStarted,
        TaskListChanged,
        ToolCallFinished,
        ToolCallStarted,
        TaskListChanged,
        ToolCallFinished,
      ]);
      final second = h.changes.last;
      expect([for (final i in second.items) i.id], ['1', '2']);
      expect(second.change.op, 'create');
      expect(second.change.actor, isA<MainActor>());
      expect([for (final i in second.change.changed) i.id], ['2']);
      expect(second.change.changed.single.description, 'details');
      expect(second.change.deleted, isEmpty);
    });

    test('владелец main принимается, владелец вне дерева — ошибка', () async {
      final ok = await h.run('task_create', {'subject': 'a', 'owner': 'main'});
      final bad = await h.run('task_create', {
        'subject': 'b',
        'owner': 'sub_unknown',
      });

      expect(ok.outcome, ToolOutcome.completed);
      expect(bad.outcome, ToolOutcome.failed);
      expect(
        textOf(bad),
        'Invalid task: owner must be "main" or the id of a subagent of this '
        'session.',
      );
      expect(h.tasks.items, hasLength(1));
    });
  });

  group('ошибки: список не меняется, TaskListChanged нет', () {
    Future<void> expectRejected(
      String tool,
      Map<String, Object?> args,
      String text,
    ) async {
      final before = h.tasks.items;
      final eventsBefore = h.changes.length;

      final outcome = await h.run(tool, args);

      expect(outcome.outcome, ToolOutcome.failed);
      expect(textOf(outcome), text);
      expect(h.tasks.items, before);
      expect(h.changes, hasLength(eventsBefore));
    }

    test('заголовок: пустой и длиннее 200 символов', () async {
      const text = 'Invalid task: subject must be 1-200 characters.';

      await expectRejected('task_create', {'subject': ''}, text);
      await expectRejected('task_create', {'subject': 'x' * 201}, text);
      final ok = await h.run('task_create', {'subject': 'x' * 200});
      expect(ok.outcome, ToolOutcome.completed);
      await expectRejected('task_update', {'id': '1', 'subject': ''}, text);
    });

    test('описание длиннее 4000 символов', () async {
      await expectRejected('task_create', {
        'subject': 'a',
        'description': 'd' * 4001,
      }, 'Invalid task: description must be at most 4000 characters.');
      final ok = await h.run('task_create', {
        'subject': 'a',
        'description': 'd' * 4000,
      });
      expect(ok.outcome, ToolOutcome.completed);
    });

    test('сто пунктов — предел, сто первый отклонён', () async {
      for (var i = 0; i < 100; i++) {
        await h.run('task_create', {'subject': 'item $i'});
      }

      await expectRejected(
        'task_create',
        {'subject': 'one more'},
        'Task limit reached: at most 100 items. Delete completed items first.',
      );
      // После удаления место появляется; id не переиспользуется (TSK-3).
      await h.run('task_update', {'id': '1', 'status': 'deleted'});
      final text = await h.text('task_create', {'subject': 'one more'});
      expect(text, startsWith('Created task #101: one more.'));
    });

    test('неизвестный id: update и get; пустой список', () async {
      await expectRejected(
        'task_update',
        {'id': '7', 'status': 'completed'},
        // Пустой список: вместо перечня известных id — фраза списка (§17.16.3).
        'Unknown task #7. The task list is empty.',
      );
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {'subject': 'b'});

      await expectRejected('task_get', {
        'id': '7',
      }, 'Unknown task #7. Known: #1, #2.');
    });

    test('зависимость на себя и на несуществующий пункт', () async {
      const text = 'Invalid task: blocked_by must list other existing tasks.';
      await h.run('task_create', {'subject': 'a'});

      await expectRejected('task_create', {
        'subject': 'b',
        'blocked_by': ['9'],
      }, text);
      await expectRejected('task_update', {
        'id': '1',
        'blocked_by': ['1'],
      }, text);
    });
  });

  group('task_update', () {
    test('поля в порядке параметров, сводка и TaskChange(update)', () async {
      await h.run('task_create', {'subject': 'a'});

      final text = await h.text('task_update', {
        'id': '1',
        'priority': 'high',
        'status': 'in_progress',
        'subject': 'a2',
      });

      expect(text, '''
Updated task #1: subject, status, priority.
Task list: 1 items (0 completed, 1 in progress, 0 pending).''');
      final change = h.changes.last.change;
      expect(change.op, 'update');
      expect(change.changed.single.subject, 'a2');
      expect(change.changed.single.priority, TaskPriority.high);
    });

    test('blocked_by заменяет список целиком', () async {
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {'subject': 'b'});
      await h.run('task_create', {
        'subject': 'c',
        'blocked_by': ['1'],
      });

      await h.run('task_update', {
        'id': '3',
        'blocked_by': ['2'],
      });

      expect(h.tasks.items.last.blockedBy, ['2']);
      expect(
        await h.text('task_list', {}),
        contains('#3 [pending] c (blocked by #2)'),
      );
    });

    test('Unblocked только у тех, кого освободила эта операция', () async {
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {'subject': 'b'});
      await h.run('task_create', {
        'subject': 'c',
        'blocked_by': ['1', '2'],
      });
      await h.run('task_create', {
        'subject': 'd',
        'blocked_by': ['1'],
      });

      final first = await h.text('task_update', {
        'id': '1',
        'status': 'completed',
      });
      final second = await h.text('task_update', {
        'id': '2',
        'status': 'completed',
      });

      expect(first, contains('Unblocked: #4 d'));
      expect(first, isNot(contains('#3 c')));
      expect(second, contains('Unblocked: #3 c'));
    });

    test(
      'in_progress при незавершённых блокерах допускается с заметкой',
      () async {
        await h.run('task_create', {'subject': 'a'});
        await h.run('task_create', {'subject': 'b'});
        await h.run('task_create', {
          'subject': 'c',
          'blocked_by': ['1', '2'],
        });

        final outcome = await h.run('task_update', {
          'id': '3',
          'status': 'in_progress',
        });

        expect(outcome.outcome, ToolOutcome.completed);
        expect(
          textOf(outcome),
          contains(
            '[Note: task #3 is in_progress, but #1, #2 are not completed yet.]',
          ),
        );
        expect(h.tasks.items.last.status, TaskStatus.inProgress);
      },
    );

    test('больше одного in_progress — заметка', () async {
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {'subject': 'b'});
      await h.run('task_update', {'id': '1', 'status': 'in_progress'});

      final text = await h.text('task_update', {
        'id': '2',
        'status': 'in_progress',
      });

      expect(text, contains('[Note: more than one task is in_progress.]'));
    });
  });

  group('удаление', () {
    test('убирает id из blocked_by остальных; они входят в changed', () async {
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {
        'subject': 'b',
        'blocked_by': ['1'],
      });
      await h.run('task_create', {
        'subject': 'c',
        'blocked_by': ['1', '2'],
      });

      final text = await h.text('task_update', {
        'id': '1',
        'status': 'deleted',
      });

      expect(text, startsWith('Deleted task #1.'));
      expect(
        [for (final i in h.tasks.items) '${i.id}:${i.blockedBy}'],
        ['2:[]', '3:[2]'],
      );
      final change = h.changes.last.change;
      expect(change.op, 'delete');
      expect(change.deleted, ['1']);
      expect([for (final i in change.changed) i.id], ['2', '3']);
      expect(
        [for (final i in h.changes.last.items) i.id],
        ['2', '3'],
        reason: 'TaskListChanged.items — весь список после операции',
      );
    });

    test('id удалённого пункта не выдаётся снова (TSK-3)', () async {
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {'subject': 'b'});
      await h.run('task_update', {'id': '2', 'status': 'deleted'});

      final text = await h.text('task_create', {'subject': 'c'});

      expect(text, startsWith('Created task #3: c.'));
    });

    test('опустевший список: TaskListChanged с пустым items', () async {
      await h.run('task_create', {'subject': 'a'});

      await h.run('task_update', {'id': '1', 'status': 'deleted'});

      expect(h.changes.last.items, isEmpty);
      expect(await h.text('task_list', {}), 'The task list is empty.');
    });
  });

  group('task_list и task_get не меняют список', () {
    test('task_list: строка на пункт, владелец и блокеры', () async {
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {
        'subject': 'b',
        'blocked_by': ['1'],
      });
      await h.run('task_update', {'id': '1', 'status': 'in_progress'});
      final events = h.changes.length;

      final text = await h.text('task_list', {});

      expect(text, '''
#1 [in_progress] a
#2 [pending] b (blocked by #1)''');
      expect(h.changes, hasLength(events));
    });

    test('task_get: поля, blocks и blocked by с заголовками', () async {
      await h.run('task_create', {'subject': 'a', 'description': 'first step'});
      await h.run('task_create', {
        'subject': 'b',
        'blocked_by': ['1'],
      });
      final events = h.changes.length;

      final first = await h.text('task_get', {'id': '1'});
      final second = await h.text('task_get', {'id': '2'});

      expect(first, contains('first step'));
      expect(first, contains('Blocks: #2 b'));
      expect(second, contains('Blocked by: #1 a'));
      expect(h.changes, hasLength(events));
    });
  });
}
