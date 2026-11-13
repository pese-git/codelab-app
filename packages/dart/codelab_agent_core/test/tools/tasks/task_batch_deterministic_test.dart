import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/builtin/write.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:codelab_agent_core/src/tools/tasks/task_tools.dart';
import 'package:test/test.dart';

import '../../loop/loop_harness.dart';
import 'task_harness.dart';

/// «Детерминированный parallel» (change `add-subagents-and-tasks`, D39-alt):
/// `task_*` исполняются параллельно с остальным пакетом, но между собой — по
/// очереди ключа `lockKey == 'tasks'` в порядке ответа модели, независимо от
/// того, чей хук `beforeToolCall` ответил раньше. Порядок выдачи id и
/// применения операций поэтому равен порядку вызовов.
void main() {
  group('lockKey', () {
    test('all four task tools share the key "tasks"', () {
      for (final tool in <AgentTool>[
        TaskCreateTool(),
        TaskUpdateTool(),
        TaskListTool(),
        TaskGetTool(),
      ]) {
        expect(tool.lockKey(const {}), 'tasks', reason: tool.name);
      }
    });

    test('builtin read/write have no key', () {
      expect(ReadTool().lockKey(const {'path': 'a'}), isNull);
      expect(WriteTool().lockKey(const {'path': 'a'}), isNull);
    });
  });

  /// Прогон пакета; хук [first] для c1 ждёт [gate], остальные отвечают сразу.
  Future<LoopHarness> run(
    List<(String, String, Map<String, Object?>)> calls, {
    required Completer<void> gate,
    Block? Function(ToolCall)? blockOf,
  }) async {
    final h = await LoopHarness.create(
      tools: [TaskCreateTool(), TaskUpdateTool()],
      llm: script([callStep(calls), textStep('done')]),
    );
    final config = h.config(
      beforeToolCall: [
        (call, args, ctx) async {
          if (call.id == 'c1') {
            // Хук первого вызова отвечает позже хука второго: без очереди по
            // ключу c2 взял бы замок списка первым.
            await gate.future;
          }
          return blockOf?.call(call);
        },
      ],
    );
    // Освобождаем c1 после того, как c2 успел дойти до своего шага 6.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (!gate.isCompleted) gate.complete();
      }),
    );
    await h.run([user('go')], config: config);
    return h;
  }

  test('ids follow model order when the first hook answers later', () async {
    final h = await run([
      ('c1', 'task_create', {'subject': 'A'}),
      ('c2', 'task_create', {'subject': 'B'}),
    ], gate: Completer<void>());

    final changes = h.events.whereType<TaskListChanged>().toList();
    expect([for (final c in changes) c.change.toolCallId], ['c1', 'c2']);
    expect([for (final c in changes) c.change.changed.single.id], ['1', '2']);
    expect(changes.last.items.map((i) => (i.id, i.subject)), [
      ('1', 'A'),
      ('2', 'B'),
    ]);
  });

  test('task_update of an item created in the same batch succeeds', () async {
    final h = await run([
      ('c1', 'task_create', {'subject': 'A'}),
      ('c2', 'task_update', {'id': '1', 'status': 'in_progress'}),
    ], gate: Completer<void>());

    final finished = {
      for (final e in h.events.whereType<ToolCallFinished>())
        e.toolCallId: e.outcome,
    };
    expect(finished['c2'], ToolOutcome.completed);
    final last = h.events.whereType<TaskListChanged>().last;
    expect(last.items.single.status, TaskStatus.inProgress);
  });

  test('invalid first call does not hold the queue', () async {
    final h = await run([
      ('c1', 'task_create', <String, Object?>{}),
      ('c2', 'task_create', {'subject': 'B'}),
    ], gate: Completer<void>());

    final changes = h.events.whereType<TaskListChanged>().toList();
    expect(changes, hasLength(1));
    expect(changes.single.change.toolCallId, 'c2');
    expect(changes.single.change.changed.single.id, '1');
  });

  test('first call blocked by a hook does not hold the queue', () async {
    final h = await run(
      [
        ('c1', 'task_create', {'subject': 'A'}),
        ('c2', 'task_create', {'subject': 'B'}),
      ],
      gate: Completer<void>(),
      blockOf: (call) => call.id == 'c1' ? const Block('denied') : null,
    );

    final changes = h.events.whereType<TaskListChanged>().toList();
    expect(changes, hasLength(1));
    expect(changes.single.change.toolCallId, 'c2');
    expect(changes.single.change.changed.single.id, '1');
  });

  test('cancel while c2 waits for the key releases both tickets', () async {
    final h = await TaskHarness.create();
    final source = CancelTokenSource();
    ToolInvocation inv(CancelToken t) => ToolInvocation(
      sessionId: h.invocation().sessionId,
      cancel: t,
      stepTools: [for (final t in h.registry.tools) t.name],
      emit: h.events.add,
    );
    final first = await h.executor.announce(
      ToolCall(id: 'c1', name: 'task_create', arguments: {'subject': 'A'}),
      inv(source.token),
    );
    final second = await h.executor.announce(
      ToolCall(id: 'c2', name: 'task_create', arguments: {'subject': 'B'}),
      inv(source.token),
    );
    // c2 доходит до ожидания ключа, пока c1 ещё не завершён.
    final secondDone = h.executor.complete(second);
    await Future<void>.delayed(Duration.zero);
    source.cancel();
    final firstOutcome = await h.executor.complete(first);
    final secondOutcome = await secondDone;

    expect(firstOutcome.outcome, ToolOutcome.cancelled);
    expect(secondOutcome.outcome, ToolOutcome.cancelled);
    expect(h.changes, isEmpty);

    // Тикеты освобождены: вызов под новым токеном не зависает.
    final next = await h
        .run('task_create', {'subject': 'C'})
        .timeout(const Duration(seconds: 2));
    expect(next.outcome, ToolOutcome.completed);
  });
}
