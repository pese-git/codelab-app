import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/tasks/task_tools.dart';
import 'package:test/test.dart';

import '../../loop/loop_harness.dart';

/// Пакет вызовов со списком задач идёт строго по одному (`17-16-task-list.md`
/// §17.16.5, TSK-1): клиент привязывает `plan` по
/// `_meta.codelab.taskChange.toolCallId` (D35); последовательный режим
/// сериализует проверки и держит `TaskListChanged` между началом вызова и его
/// `ToolCallFinished`. Хук `beforeToolCall` (как `markInProgress` ACP) при
/// этом срабатывает сразу после `ToolCallStarted` своего вызова.
///
/// Механизм — `AgentTool.executionMode` = `sequential`: один такой вызов
/// переводит весь пакет в последовательный режим цикла (`agent_loop.dart`,
/// `_runBatch`).
void main() {
  test('executionMode of every task tool is sequential', () {
    for (final tool in <AgentTool>[
      TaskCreateTool(),
      TaskUpdateTool(),
      TaskListTool(),
      TaskGetTool(),
    ]) {
      expect(
        tool.executionModeOf(const {}),
        ToolExecutionMode.sequential,
        reason: tool.name,
      );
    }
  });

  test('[task_create, read, task_create]: one call at a time, plan between '
      'in_progress and completed of its own call', () async {
    final h = await LoopHarness.create(
      tools: [TaskCreateTool(), ReadTool()],
      llm: script([
        callStep([
          ('c1', 'task_create', {'subject': 'first'}),
          ('c2', 'read', {'path': 'a.txt'}),
          ('c3', 'task_create', {'subject': 'second'}),
        ]),
        textStep('done'),
      ]),
    );
    await h.env.writeText('/proj/a.txt', 'A\n');
    // Хук хоста (как `markInProgress` ACP-адаптера) стоит последним в
    // цепочке: запоминаем, что событие ему предшествовало.
    final beforeExecute = <String, String>{};
    final config = h.config(
      beforeToolCall: [
        (call, args, ctx) async {
          beforeExecute[call.id] = h.trace.last;
          return null;
        },
      ],
    );

    await h.run([user('go')], config: config);

    final calls = h.trace
        .where(
          (t) =>
              t.startsWith('ToolCallStarted') ||
              t.startsWith('ToolCallFinished') ||
              t.startsWith('TaskListChanged'),
        )
        .toList();
    expect(calls, [
      'ToolCallStarted(c1)',
      'TaskListChanged',
      'ToolCallFinished(c1 completed)',
      'ToolCallStarted(c2)',
      'ToolCallFinished(c2 completed)',
      'ToolCallStarted(c3)',
      'TaskListChanged',
      'ToolCallFinished(c3 completed)',
    ]);
    // `in_progress` вызова приходит сразу после его ToolCallStarted, до
    // любого события следующего вызова.
    expect(beforeExecute, {
      'c1': 'ToolCallStarted(c1)',
      'c2': 'ToolCallStarted(c2)',
      'c3': 'ToolCallStarted(c3)',
    });
  });
}
