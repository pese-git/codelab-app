import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Контракт ACP-проекции на параллельный пакет `task_*` (заметка
/// `17-16a-task-batch-parallel-alt`, исследовательская ветка «parallel»).
///
/// Почему: `_TaskTool.executionMode == null`, поэтому пакет с `task_*`
/// исполняется параллельно (announce всех вызовов, затем `Future.wait`);
/// между собой `task_*` идут в порядке ответа модели по очереди ключа
/// `tasks` (`AgentTool.lockKey`, §17.16a.4), а `TaskListChanged` каждого
/// вызова публикуется до его `ToolCallFinished` (TSK-1 на вызов).
///
/// Для чего: убедиться, что проекция не теряет и не путает `plan` разных
/// вызовов — клиент привязывает их по `_meta.codelab.taskChange.toolCallId`
/// (D35), а не по порядку кадров.
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  Map<String, Object?> call(String id, String name, Map<String, Object?> a) => {
    'toolCall': {'id': id, 'name': name, 'arguments': a},
  };

  test('a parallel task_* batch: announce first, plan per call before its '
      'completed', () async {
    final files = MemoryExecutionEnv(cwd: '/work/demo');
    await files.writeText('/work/demo/README.md', '# foo\n');
    h = await ServerHarness.start(
      steps: [
        {
          'reply': [
            call('c1', 'task_create', {'subject': 'A'}),
            call('c2', 'read', {'path': 'README.md'}),
            call('c3', 'task_create', {'subject': 'B'}),
          ],
        },
        {
          'reply': [
            {'text': 'Done'},
          ],
        },
      ],
    );
    await h.initialize();
    final sessionId = await h.newSession();
    h.client.serveFiles(files);

    final response = await h.prompt(sessionId, 'Plan');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final frames = TestClient.updates(
      h.client.received.take(h.client.received.indexOf(response)),
    );

    int firstIndex(bool Function(Map<String, Object?>) test) =>
        frames.indexWhere(test);
    int indexOfCall(String id, String kind, String? status) => firstIndex(
      (u) =>
          u['toolCallId'] == id &&
          u['sessionUpdate'] == kind &&
          (status == null || u['status'] == status),
    );
    Map<String, Object?> change(Map<String, Object?> plan) =>
        ((plan['_meta']! as Map)['codelab']! as Map)['taskChange']!
            as Map<String, Object?>;

    // 1. Параллельность на проводе: все announce раньше первого plan и
    // раньше первого completed.
    final announces = [
      for (final id in ['c1', 'c2', 'c3'])
        indexOfCall(id, 'tool_call', 'pending'),
    ];
    expect(announces, everyElement(isNonNegative));
    final firstPlan = firstIndex((u) => u['sessionUpdate'] == 'plan');
    final firstCompleted = firstIndex(
      (u) =>
          u['sessionUpdate'] == 'tool_call_update' &&
          u['status'] == 'completed',
    );
    expect(firstPlan, isNonNegative);
    final lastAnnounce = announces.reduce((a, b) => a > b ? a : b);
    expect(lastAnnounce, lessThan(firstPlan));
    expect(lastAnnounce, lessThan(firstCompleted));

    // 2. Ровно два plan, привязанных к c1 и c3 с разными changed.
    final plans = [
      for (final u in frames)
        if (u['sessionUpdate'] == 'plan') u,
    ];
    expect(plans, hasLength(2));
    // `task_*` пакета стоят в очереди ключа `tasks` в порядке ответа модели
    // (`AgentTool.lockKey`, §17.16a.4), поэтому порядок plan и выдачи id
    // детерминирован: c1 получает #1, c3 — #2.
    expect([for (final p in plans) change(p)['toolCallId']], ['c1', 'c3']);
    expect(
      [for (final p in plans) change(p)['changed']],
      [
        ['1'],
        ['2'],
      ],
    );
    List<String> taskIds(Map<String, Object?> plan) => [
      for (final e in plan['entries']! as List)
        ((((e as Map)['_meta']! as Map)['codelab']! as Map)['task']!
                as Map)['id']
            as String,
    ];
    expect(taskIds(plans.last), ['1', '2']);

    // 3. TSK-1 на вызов: plan вызова раньше его completed.
    for (final id in ['c1', 'c3']) {
      final planIndex = firstIndex(
        (u) => u['sessionUpdate'] == 'plan' && change(u)['toolCallId'] == id,
      );
      expect(planIndex, isNonNegative, reason: 'plan для $id');
      expect(
        planIndex,
        lessThan(indexOfCall(id, 'tool_call_update', 'completed')),
        reason: 'TSK-1: plan раньше completed для $id',
      );
    }

    // 4. У каждого вызова in_progress раньше его completed.
    for (final id in ['c1', 'c2', 'c3']) {
      final started = indexOfCall(id, 'tool_call_update', 'in_progress');
      expect(started, isNonNegative, reason: 'in_progress для $id');
      expect(
        started,
        lessThan(indexOfCall(id, 'tool_call_update', 'completed')),
        reason: 'in_progress раньше completed для $id',
      );
    }
  });
}
