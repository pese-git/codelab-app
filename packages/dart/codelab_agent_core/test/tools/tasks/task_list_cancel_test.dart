import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'task_harness.dart';

/// `TaskChange.toolCallId` и отмена во время ожидания замка (agent-tools
/// «Инструменты списка задач», сценарий «Отмена во время ожидания замка»;
/// design.md change `add-subagents-and-tasks`, D35;
/// `agent-core/17-16-task-list.md` §17.16.2).
///
/// Красные до задачи 1.2c: у `TaskChange` нет поля `toolCallId`.
void main() {
  test('create, update and delete carry the id of their tool call', () async {
    final h = await TaskHarness.create();

    await h.run('task_create', {'subject': 'a'}, id: 'call_c');
    await h.run('task_update', {
      'id': '1',
      'status': 'completed',
    }, id: 'call_u');
    await h.run('task_update', {'id': '1', 'status': 'deleted'}, id: 'call_d');
    await h.run('task_get', {'id': '1'}, id: 'call_g');

    expect(
      [for (final c in h.changes) c.change.toolCallId],
      ['call_c', 'call_u', 'call_d'],
    );
  });

  test('restore has no toolCallId', () async {
    final published = <TaskChange>[];
    final list = SessionTaskList(publish: (items, c) => published.add(c));

    await list.restore(
      [TaskItem(id: '1', subject: 'a')],
      nextId: 2,
      announce: true,
    );

    expect(published.single.op, 'restore');
    expect(published.single.toolCallId, isNull);
  });

  // `apply` отмену не проверяет: начатая операция применяется, иначе модель
  // получила бы «cancelled» для пункта, который уже есть в списке. Второй
  // вызов ещё не начат: он ждёт очередь ключа `tasks` (D39-alt) и после
  // ожидания повторно проверяет отмену — получает `cancelled`, список не
  // меняется.
  test('cancel while the second call waits for the key: the first is applied, '
      'the second is cancelled', () async {
    final release = Completer<void>();
    final firstPublishing = Completer<void>();
    late TaskHarness h;
    final changes = <TaskChange>[];
    h = await TaskHarness.create(
      publish: (items, change) async {
        changes.add(change);
        if (changes.length == 1) {
          firstPublishing.complete();
          await release.future;
        }
      },
    );
    final source = CancelTokenSource();
    h.cancel = source.token;

    final first = h.run('task_create', {'subject': 'a'}, id: 'call_1');
    await firstPublishing.future;
    final second = h.run('task_create', {'subject': 'b'}, id: 'call_2');
    await pumpEventQueue();

    source.cancel();
    release.complete();
    final outcomes = [await first, await second];

    expect(outcomes.map((o) => o.outcome), [
      ToolOutcome.completed,
      ToolOutcome.cancelled,
    ]);
    expect(textOf(outcomes[0]), startsWith('Created task #1: a.'));
    expect([for (final c in changes) c.toolCallId], ['call_1']);
    expect(h.tasks.items.map((i) => i.id), ['1']);
  });
}
