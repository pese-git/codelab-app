import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/tasks/task_tools.dart';
import 'package:test/test.dart';

import '../../loop/loop_harness.dart';

/// Пакет вызовов со списком задач исполняется параллельно с остальным
/// пакетом (стратегия «parallel», LOOP-4): порядок `TaskListChanged` и id
/// недетерминирован, но TSK-1 держится per-call — `TaskListChanged` вызова
/// стоит раньше его `ToolCallFinished`, а клиент привязывает `plan` по
/// `change.toolCallId` (D35). Хук `beforeToolCall` в параллельном пакете
/// срабатывает уже после announce всех вызовов (`ToolCallStarted` всех трёх
/// идут первыми).
void main() {
  test('[task_create, read, task_create]: all Started first, plan of each '
      'call before its own Finished', () async {
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
    // Хук хоста (как `markInProgress` ACP-адаптера): фиксируем, какое
    // событие ему предшествовало.
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

    final firstFinished = h.events.indexWhere((e) => e is ToolCallFinished);
    for (final id in ['c1', 'c2', 'c3']) {
      expect(
        h.events.indexWhere((e) => e is ToolCallStarted && e.toolCallId == id),
        lessThan(firstFinished),
        reason: id,
      );
    }
    for (final id in ['c1', 'c3']) {
      final changed = h.events.indexWhere(
        (e) => e is TaskListChanged && e.change.toolCallId == id,
      );
      final finished = h.events.indexWhere(
        (e) => e is ToolCallFinished && e.toolCallId == id,
      );
      expect(changed, lessThan(finished), reason: id);
    }
    // Фактическое поведение: хук каждого вызова видит последним событием
    // Started последнего вызова пакета (announce всех — до исполнения).
    expect(beforeExecute, {
      'c1': 'ToolCallStarted(c3)',
      'c2': 'ToolCallStarted(c3)',
      'c3': 'ToolCallStarted(c3)',
    });
  });
}
