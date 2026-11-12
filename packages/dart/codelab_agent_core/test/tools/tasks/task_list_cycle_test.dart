import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../../host/core_harness.dart';
import '../../permissions/fake_gate.dart';
import 'task_harness.dart';

/// Цикл зависимостей (agent-tools «Инструменты списка задач», сценарий
/// «Цикл зависимостей», `core/task-list-cycle-rejected`; TSK-1, TSK-2).
///
/// Красные до задачи 1.2: нет `task_*`, `SessionTaskList`, `TaskListChanged`.
void main() {
  test('#1 blocked_by #2 при #2 blocked_by #1 — ошибка с цепочкой', () async {
    final h = await TaskHarness.create();
    await h.run('task_create', {'subject': 'first'});
    await h.run('task_create', {
      'subject': 'second',
      'blocked_by': ['1'],
    });
    final before = h.tasks.items;
    final events = h.events.length;

    final outcome = await h.run('task_update', {
      'id': '1',
      'blocked_by': ['2'],
    });

    expect(outcome.outcome, ToolOutcome.failed);
    expect(
      textOf(outcome),
      'Invalid task: blocked_by would create a cycle: #1 → #2 → #1.',
    );
    expect(h.tasks.items, before);
    expect(
      h.events.skip(events).whereType<TaskListChanged>(),
      isEmpty,
      reason: 'отклонённая операция не публикуется (TSK-1)',
    );
  });

  test('цепочка из трёх: цикл называет весь путь', () async {
    final h = await TaskHarness.create();
    await h.run('task_create', {'subject': 'a'});
    await h.run('task_create', {
      'subject': 'b',
      'blocked_by': ['1'],
    });
    await h.run('task_create', {
      'subject': 'c',
      'blocked_by': ['2'],
    });

    final text = await h.text('task_update', {
      'id': '1',
      'blocked_by': ['3'],
    });

    expect(
      text,
      'Invalid task: blocked_by would create a cycle: #1 → #3 → #2 → #1.',
    );
  });

  test(
    'граф остаётся ациклическим: допустимая перестановка проходит',
    () async {
      final h = await TaskHarness.create();
      await h.run('task_create', {'subject': 'a'});
      await h.run('task_create', {
        'subject': 'b',
        'blocked_by': ['1'],
      });

      // Замена списка целиком убирает ребро #2 → #1, после чего обратное
      // ребро допустимо.
      final cleared = await h.run('task_update', {
        'id': '2',
        'blocked_by': <String>[],
      });
      final reversed = await h.run('task_update', {
        'id': '1',
        'blocked_by': ['2'],
      });

      expect(cleared.outcome, ToolOutcome.completed);
      expect(reversed.outcome, ToolOutcome.completed);
    },
  );

  test(
    'журнал не меняется: записей task ровно по числу принятых операций',
    () async {
      final store = MemorySessionStore();
      final h = CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        narrow: noExec,
        gate: FakeGate(),
        sessions: store,
        steps: [
          callStep('c1', 'task_create', {'subject': 'first'}),
          callStep('c2', 'task_create', {
            'subject': 'second',
            'blocked_by': ['1'],
          }),
          callStep('c3', 'task_update', {
            'id': '1',
            'blocked_by': ['2'],
          }),
          textStep('done'),
        ],
      );
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      final events = <AgentEvent>[];
      session.events.listen(events.add);

      await session.prompt(const [TextContent('plan it')]);
      await pumpEventQueue();

      expect(
        '"type":"task"'.allMatches(store.textOf(session.id)!),
        hasLength(2),
        reason: 'отклонённый цикл не оставляет записи task (TSK-1)',
      );
      expect(events.whereType<TaskListChanged>(), hasLength(2));
      expect(
        [for (final i in session.tasks.items) (i.id, i.blockedBy)],
        [
          ('1', <String>[]),
          ('2', ['1']),
        ],
      );
    },
  );
}
