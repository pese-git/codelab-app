import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:codelab_agent_core/src/tools/registry.dart';
import 'package:codelab_agent_core/src/tools/tasks/task_tools.dart';
import 'package:codelab_agent_core/testing.dart';

import '../executor_harness.dart' show session, textOf;

export '../executor_harness.dart' show textOf;

/// Исполнитель четырёх инструментов списка задач над одним `SessionTaskList`
/// (`agent-core/17-16-task-list.md` §17.16.2–§17.16.3).
///
/// Почему отдельный стенд, а не `ExecutorHarness`: тот ещё держит
/// `PlanService` до удаления `update_plan` (задача 1.4); общий стенд нельзя
/// ломать ради красных тестов итерации 1.
///
/// Как использовать: `TaskHarness.create()`, затем `run('task_create', {...})`;
/// все опубликованные списком события лежат в [events] в порядке эмита —
/// вместе с `ToolCallStarted`/`ToolCallFinished` вызова (TSK-1: событие
/// списка приходит до `ToolCallFinished`).
final class TaskHarness {
  TaskHarness._(this.executor, this.registry, this.tasks, this.events);

  static Future<TaskHarness> create({
    MemoryExecutionEnv? memory,
    RecordingLogger? logger,
    TaskListPublisher? publish,
    TaskList? list,
  }) async {
    final clock = FakeClock();
    final base = memory ?? MemoryExecutionEnv(cwd: '/proj', clock: clock);
    final env = await BoundedEnv.wrap(base, base.cwd);
    final registry = ToolRegistry();
    for (final tool in <AgentTool>[
      TaskCreateTool(),
      TaskUpdateTool(),
      TaskListTool(),
      TaskGetTool(),
    ]) {
      registry.register(tool);
    }
    final events = <AgentEvent>[];
    // Публикация идёт в ту же запись, что и события вызова: порядок
    // `TaskListChanged` относительно `ToolCallFinished` виден в [events].
    final TaskList tasks =
        list ??
        SessionTaskList(
          sessionId: session.value,
          logger: logger,
          publish:
              publish ??
              (items, change) => events.add(
                TaskListChanged(session, items: items, change: change),
              ),
        );
    final executor = ToolCallExecutor(
      registry: registry,
      env: env,
      services: ToolServices(
        clock: clock,
        logger: logger ?? RecordingLogger(),
        tasks: tasks,
      ),
    );
    return TaskHarness._(executor, registry, tasks, events);
  }

  final ToolCallExecutor executor;
  final ToolRegistry registry;
  final TaskList tasks;
  final List<AgentEvent> events;

  /// Токен отмены вызовов стенда; по умолчанию отмены нет.
  CancelToken cancel = CancelToken.none;

  ToolInvocation invocation() => ToolInvocation(
    sessionId: session,
    cancel: cancel,
    stepTools: [for (final t in registry.tools) t.name],
    emit: events.add,
    beforeToolCall: const [],
    afterToolCall: const [],
    supportsImages: false,
  );

  var _calls = 0;

  Future<ToolExecutionOutcome> run(
    String name,
    Map<String, Object?> args, {
    String? id,
  }) async {
    final handle = await executor.announce(
      ToolCall(id: id ?? 'call_${++_calls}', name: name, arguments: args),
      invocation(),
    );
    return executor.complete(handle);
  }

  /// Текст результата вызова — как его видит модель.
  Future<String> text(String name, Map<String, Object?> args) async =>
      textOf(await run(name, args));

  /// Опубликованные `TaskListChanged` в порядке эмита.
  List<TaskListChanged> get changes =>
      events.whereType<TaskListChanged>().toList();
}
