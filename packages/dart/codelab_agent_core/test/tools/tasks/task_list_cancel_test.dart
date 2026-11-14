import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'task_harness.dart';

/// `TaskChange.toolCallId` и отмена во время ожидания замка (agent-tools
/// «Инструменты списка задач», сценарий «Отмена во время ожидания замка»;
/// design.md change `add-subagents-and-tasks`, D35;
/// `agent-core/17-16-task-list.md` §17.16.2).
///
/// Сценарий «Отмена во время ожидания замка»: вызов, начавший исполнение и
/// ждущий ключ `tasks`, после отмены хода всё равно исполняется (D35
/// «Отмена»; операции под ключом короткие и атомарные).
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

  // Сценарий spec «Отмена во время ожидания замка» (D35 «Отмена»): второй
  // вызов уже начал исполнение (прошёл хук и проверку отмены) и ждёт ключ
  // `tasks`; после захвата ключа отмену он не проверяет, поэтому оба пункта
  // созданы с обычным результатом, а `TaskListChanged` несут `toolCallId`
  // своих вызовов.
  test('cancel while the second call waits for the key: both are applied '
      '(scenario "cancel while waiting for the lock")', () async {
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
      ToolOutcome.completed,
    ]);
    expect(textOf(outcomes[0]), startsWith('Created task #1: a.'));
    expect(textOf(outcomes[1]), startsWith('Created task #2: b.'));
    expect([for (final c in changes) c.toolCallId], ['call_1', 'call_2']);
    expect(h.tasks.items.map((i) => i.id), ['1', '2']);
  });
}
