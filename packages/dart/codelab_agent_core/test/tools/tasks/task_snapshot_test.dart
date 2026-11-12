import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'task_harness.dart';

/// Ответ `task_create`/`task_update` строится по снимку `TaskApplied`, а не по
/// `TaskList.items`, прочитанному вне замка (ревью итерации 1, `17-16`
/// §17.16.2). Заглушка отдаёт в `apply` один список, а в `items` — другой:
/// любая сводка или заметка по `items` расходится с ожидаемой.
void main() {
  TaskItem item(String id, {TaskStatus? status, List<String>? blockedBy}) =>
      TaskItem(
        id: id,
        subject: 's$id',
        status: status ?? TaskStatus.pending,
        blockedBy: blockedBy ?? const [],
      );

  final snapshot = [
    item('1'),
    item('2', status: TaskStatus.inProgress, blockedBy: ['1']),
  ];

  Future<TaskHarness> harness(TaskList list) => TaskHarness.create(list: list);

  test('task_create: сводка и заметки — по снимку операции', () async {
    final h = await harness(
      _StubList(applied: snapshot, applyItem: snapshot.last, items: const []),
    );

    final text = textOf(await h.run('task_create', {'subject': 'x'}));

    expect(text, contains('Created task #2: s2.'));
    expect(
      text,
      contains('Task list: 2 items (0 completed, 1 in progress, 1 pending).'),
    );
    expect(
      text,
      contains('[Note: task #2 is in_progress, but #1 is not completed yet.]'),
    );
  });

  test('task_update: сводка и заметки — по снимку операции', () async {
    final h = await harness(
      _StubList(applied: snapshot, applyItem: snapshot.last, items: const []),
    );

    final text = textOf(
      await h.run('task_update', {'id': '2', 'status': 'in_progress'}),
    );

    expect(text, contains('Task list: 2 items'));
    expect(
      text,
      contains('[Note: task #2 is in_progress, but #1 is not completed yet.]'),
    );
  });
}

final class _StubList implements TaskList {
  _StubList({
    required this.applied,
    required this.applyItem,
    required this.items,
  });

  final List<TaskItem> applied;
  final TaskItem applyItem;

  @override
  final List<TaskItem> items;

  @override
  List<TaskId> blocksOf(TaskId id) => const [];

  @override
  Future<TaskResult> apply(
    TaskOp op,
    TaskActor actor, {
    String? toolCallId,
  }) async => TaskApplied(
    change: TaskChange(
      op: 'update',
      actor: actor,
      changed: [applyItem],
      deleted: const [],
    ),
    item: applyItem,
    snapshot: applied,
  );

  @override
  Future<void> restore(
    List<TaskItem> items, {
    required int nextId,
    required bool announce,
  }) async {}
}
