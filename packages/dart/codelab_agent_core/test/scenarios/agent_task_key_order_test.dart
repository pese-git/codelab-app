import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/subagents/subagent_manager.dart';
import 'package:codelab_agent_core/src/subagents/subagent_tool.dart';
import 'package:codelab_agent_core/src/subagents/subagent_types.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../subagents/subagent_rig.dart';

/// `agent{task}` встаёт в очередь ключа `tasks` (D39-alt, §17.16a.4): проверка
/// пункта идёт в порядке ответа модели, а ключ отпускается до ожидания
/// ребёнка (`ToolContext.releaseLockKey`, контракт `AgentTool.lockKey`).
void main() {
  test('[task_create, task_create, agent{1}, agent{2}]: оба agent видят '
      'пункты и работают параллельно', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          multiCallStep([
            ('c1', 'task_create', {'subject': 'Read a'}),
            ('c2', 'task_create', {'subject': 'Read b'}),
            (
              'a1',
              'agent',
              agentArgs('child one', description: 'One', task: '1'),
            ),
            (
              'a2',
              'agent',
              agentArgs('child two', description: 'Two', task: '2'),
            ),
          ]),
          replyStep('done'),
        ],
        'child one': [replyStep('one', delayMs: 10)],
        'child two': [replyStep('two', delayMs: 10)],
      },
    );
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(
      () =>
          rig.eventsOf<SubagentStarted>().length == 2 &&
          rig.clock.pendingTimers >= 2,
      reason: 'both children must be waiting on the clock together',
    );
    await rig.clock.elapse(const Duration(milliseconds: 10));
    final result = await turn;

    expect(result.reason, TurnEndReason.completed);
    final last = rig.requestsOf('go').last;
    expect(resultIsError(last, 'a1'), isFalse, reason: resultText(last, 'a1'));
    expect(resultIsError(last, 'a2'), isFalse, reason: resultText(last, 'a2'));
  });

  test('[agent{1}, task_create]: порядок ответа соблюдён, agent получает '
      'Unknown task #1', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          multiCallStep([
            ('a1', 'agent', agentArgs('child', description: 'One', task: '1')),
            ('c1', 'task_create', {'subject': 'Late'}),
          ]),
          replyStep('done'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    final last = rig.requestsOf('go').last;
    expect(resultIsError(last, 'a1'), isTrue);
    expect(
      resultText(last, 'a1'),
      contains('Unknown task #1. The task list is empty.'),
    );
    expect(resultIsError(last, 'c1'), isFalse);
    expect(rig.eventsOf<SubagentStarted>(), isEmpty);
  });

  test('ключ отпущен до ожидания ребёнка: task_update за agent{1} '
      'завершается, пока ребёнок работает', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep('c0', 'task_create', {'subject': 'Work'}),
          multiCallStep([
            ('a1', 'agent', agentArgs('wait', description: 'One', task: '1')),
            ('t1', 'task_update', {'id': '1', 'status': 'in_progress'}),
          ]),
          replyStep('after cancel'),
        ],
        'wait': [
          {
            'waitForCancel': true,
            'reply': [
              {'text': 'working'},
            ],
          },
        ],
      },
    );
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(
      () =>
          rig.eventsOf<SubagentStarted>().length == 1 &&
          rig.eventsOf<ToolCallFinished>().any((e) => e.toolCallId == 't1'),
      reason: 'task_update must finish while the child is still working',
    );
    expect(rig.eventsOf<SubagentFinished>(), isEmpty);
    await rig.session.cancel();
    await turn;
  });

  test('agent без task и вне корня ключ не берёт (lockKey == null)', () {
    SubagentTool toolAt(int depth) {
      final clock = FakeClock();
      final logger = RecordingLogger();
      return SubagentTool(
        manager: SubagentManager(
          tree: SubagentTree(limits: () => const SubagentsConfig()),
          limits: () => const SubagentsConfig(),
          emit: (_) async {},
          create: (_) => throw StateError('no child'),
          clock: clock,
          logger: logger,
          sessionId: const SessionId('root'),
          rootBudget: () => const TurnBudget(),
          parent: () => throw StateError('no child'),
        ),
        types: buildSubagentTypes(const []),
        ids: SequentialIdGenerator(),
        limits: () => const SubagentsConfig(),
        clock: clock,
        logger: logger,
        parentSessionId: const SessionId('root'),
        depth: depth,
        maxDepth: 3,
        maxConcurrent: 3,
      );
    }

    const base = {'description': 'Look around', 'prompt': 'find it'};
    expect(toolAt(0).lockKey(base), isNull);
    expect(toolAt(0).lockKey({...base, 'task': '1'}), 'tasks');
    expect(toolAt(1).lockKey({...base, 'task': '1'}), isNull);
    expect(toolAt(0).lockKey({...base, 'task': 1}), isNull);
  });
}
