import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/tasks/task_tools.dart';
import 'package:test/test.dart';

import '../../loop/loop_harness.dart';
import '../fake_tools.dart';

/// Стратегия «parallel» для инструментов списка задач (исследовательская
/// альтернатива D39 «barrier»): `task_*` не переводят пакет в
/// последовательный режим (LOOP-4, `agent_loop.dart`, `_runBatch`), а
/// корректность держат замок `SessionTaskList._locked` (операции
/// сериализуются, `TaskListChanged` публикуется под замком и ждётся внутри
/// `execute`, то есть раньше `ToolCallFinished` своего вызова — TSK-1) и
/// привязка `plan` по `change.toolCallId` (D35).
///
/// Теряется: глобальный порядок вызовов и порядок выдачи id — он зависит от
/// того, кто первым возьмёт замок, и тестами НЕ закрепляется.
void main() {
  test('executionMode of every task tool is not sequential', () {
    for (final tool in <AgentTool>[
      TaskCreateTool(),
      TaskUpdateTool(),
      TaskListTool(),
      TaskGetTool(),
    ]) {
      expect(
        tool.executionModeOf(const {}),
        isNot(ToolExecutionMode.sequential),
        reason: tool.name,
      );
    }
  });

  /// Прогон [slow c1, task_create c2, task_create c3], где `slow` ждёт, пока
  /// оба `task_create` не завершатся.
  Future<LoopHarness> runBatch() async {
    final bothFinished = Completer<void>();
    final slow = FakeTool(
      'slow',
      onExecute: (args, ctx) async {
        // Последовательный пакет зависнет здесь: c1/c2 не стартуют, пока
        // slow (c3) не вернётся, а он ждёт их. Таймаут вместо замера времени.
        await bothFinished.future.timeout(const Duration(seconds: 2));
        return ToolExecutionResult([TextContent('slow done')]);
      },
    );
    final h = await LoopHarness.create(
      tools: [TaskCreateTool(), slow],
      llm: script([
        callStep([
          // slow стоит ПЕРВЫМ: при последовательном исполнении task_create
          // не стартуют, пока slow не вернётся, а он ждёт их — тест падает по
          // таймауту, а не проходит случайно.
          ('c1', 'slow', <String, Object?>{}),
          ('c2', 'task_create', {'subject': 'first'}),
          ('c3', 'task_create', {'subject': 'second'}),
        ]),
        textStep('done'),
      ]),
    );
    // Хук вызывается после `execute` своего вызова, до его Finished: когда он
    // отработал для обоих task_create, оба уже применили операцию.
    final done = <String>{};
    final config = h.config(
      afterToolCall: [
        (call, result, isError) async {
          if (call.name == 'task_create') done.add(call.id);
          if (done.length == 2 && !bothFinished.isCompleted) {
            bothFinished.complete();
          }
          return null;
        },
      ],
    );
    await h.run([user('go')], config: config);
    return h;
  }

  test('[slow, task_create, task_create] runs in parallel', () async {
    final h = await runBatch().timeout(const Duration(seconds: 5));

    final started = h.events.whereType<ToolCallStarted>().toList();
    final firstFinished = h.events.indexWhere((e) => e is ToolCallFinished);
    expect(started.map((e) => e.toolCallId), ['c1', 'c2', 'c3']);
    for (final s in started) {
      expect(h.events.indexOf(s), lessThan(firstFinished));
    }
  });

  test('operations are neither lost nor duplicated', () async {
    final h = await runBatch().timeout(const Duration(seconds: 5));

    final changes = h.events.whereType<TaskListChanged>().toList();
    expect(changes, hasLength(2));
    expect({for (final c in changes) c.change.toolCallId}, {'c2', 'c3'});
    // Порядок выдачи id НЕДЕТЕРМИНИРОВАН (зависит от порядка захвата замка),
    // поэтому сравниваем множества.
    expect({for (final c in changes) c.change.changed.single.id}, {'1', '2'});
    final last = changes.last.items;
    expect(last, hasLength(2));
    expect({for (final i in last) i.id}, {'1', '2'});
    expect({for (final i in last) i.subject}, {'first', 'second'});
  });

  test(
    'TSK-1 per call: TaskListChanged precedes its ToolCallFinished',
    () async {
      final h = await runBatch().timeout(const Duration(seconds: 5));

      for (final id in ['c2', 'c3']) {
        final changed = h.events.indexWhere(
          (e) => e is TaskListChanged && e.change.toolCallId == id,
        );
        final finished = h.events.indexWhere(
          (e) => e is ToolCallFinished && e.toolCallId == id,
        );
        expect(changed, isNonNegative, reason: id);
        expect(changed, lessThan(finished), reason: id);
      }
    },
  );

  // Журнал (пункт e) пропущен: `LoopHarness` не пишет журнал сессии, а
  // записи `task` строит `SessionWriter` из потока событий в стенде
  // `test/session/*` — подключать его к циклу непропорционально. Порядок
  // записей определяется порядком эмита `TaskListChanged`, который
  // сериализован замком; реплей покрыт `task_list_journal_test.dart`.
}
