import 'dart:async';

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
    // Валидатор приводит число и bool к строке (`_coerce('string')`): ключ
    // берётся и для них, иначе `agent{task: 1}` обходил бы очередь.
    expect(toolAt(0).lockKey({...base, 'task': 1}), 'tasks');
    expect(toolAt(0).lockKey({...base, 'task': true}), 'tasks');
    expect(toolAt(0).lockKey({...base, 'task': null}), isNull);
    expect(toolAt(0).lockKey({...base, 'task': <Object?>[]}), isNull);
    expect(toolAt(0).lockKey({...base, 'task': <String, Object?>{}}), isNull);
  });

  test('[task_create (медленный хук), agent{task: 1}] с числом: валидатор '
      'приводит 1 к "1", agent ждёт ключ и видит пункт', () async {
    final gate = Completer<void>();
    final rig = SubagentRig(
      scripts: {
        'go': [
          multiCallStep([
            ('c1', 'task_create', {'subject': 'Read a'}),
            (
              'a1',
              'agent',
              // Число вместо строки: сырые аргументы модели.
              {...agentArgs('child one', description: 'One'), 'task': 1},
            ),
          ]),
          replyStep('done'),
        ],
        'child one': [replyStep('one')],
      },
    );
    await rig.open(
      ports: SessionHostPorts(
        extraBeforeToolCall: [
          (call, args, ctx) async {
            if (call.id == 'c1') {
              await gate.future;
            }
            return null;
          },
        ],
      ),
    );

    final turn = rig.run('go');
    // a1 прошёл свой хук и стоит в очереди ключа за медленным c1.
    await pumpUntil(
      () => rig.eventsOf<ToolCallStarted>().length == 2,
      reason: 'both calls announced',
    );
    expect(rig.eventsOf<ToolCallFinished>(), isEmpty);
    gate.complete();
    final result = await turn.timeout(const Duration(seconds: 5));

    expect(result.reason, TurnEndReason.completed);
    final last = rig.requestsOf('go').last;
    expect(resultIsError(last, 'a1'), isFalse, reason: resultText(last, 'a1'));
    expect(rig.eventsOf<SubagentStarted>(), hasLength(1));
  });

  test('agent{task} ждёт ключ, ход отменён: после захвата ключа ребёнок не '
      'порождён, agent cancelled, ключ свободен', () async {
    // t1 держит ключ: его медленный beforeToolCall не даёт вызову дойти до
    // исполнения, а место в очереди уже занято (announce). a1 прошёл свой
    // хук и ждёт ключ за t1; пункт #1 создан предыдущим шагом.
    final gate = Completer<void>();
    var t1Waiting = false;
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep('c0', 'task_create', {'subject': 'Work'}),
          multiCallStep([
            ('t1', 'task_update', {'id': '1', 'status': 'in_progress'}),
            (
              'a1',
              'agent',
              agentArgs('never run', description: 'One', task: '1'),
            ),
          ]),
          oneCallStep('t3', 'task_list', const {}),
          replyStep('after cancel'),
        ],
      },
    );
    await rig.open(
      ports: SessionHostPorts(
        extraBeforeToolCall: [
          (call, args, ctx) async {
            if (call.id == 't1') {
              t1Waiting = true;
              await gate.future;
            }
            return null;
          },
        ],
      ),
    );

    final turn = rig.run('go');
    await pumpUntil(
      () => t1Waiting && rig.eventsOf<ToolCallStarted>().length == 3,
      reason: 'a1 announced and t1 holds the key',
    );
    await rig.session.cancel();
    // a1 стоит на ключе: отмена его не прерывает (D35), он ждёт t1.
    await pumpEventQueue(times: 20);
    expect(
      rig.eventsOf<ToolCallFinished>().where((e) => e.toolCallId == 'a1'),
      isEmpty,
    );
    gate.complete();
    final result = await turn.timeout(const Duration(seconds: 5));

    expect(result.reason, TurnEndReason.cancelled);
    final finished = {
      for (final e in rig.eventsOf<ToolCallFinished>()) e.toolCallId: e.outcome,
    };
    expect(finished['a1'], ToolOutcome.cancelled);
    expect(rig.eventsOf<SubagentStarted>(), isEmpty);
    expect(rig.requestsOf('never run'), isEmpty);
    // `spawn` не вызывался: ребёнок отменённого хода не порождается даже
    // «мёртворождённым» (иначе он занял бы слот и записал бы `Finished`).
    expect(rig.logger.eventsOf('subagent.spawn'), isEmpty);

    // Ключ свободен: task_list следующего хода не зависает на очереди.
    final next = await rig.run('again').timeout(const Duration(seconds: 5));
    expect(next.reason, TurnEndReason.completed);
    expect(resultIsError(rig.requestsOf('go').last, 't3'), isFalse);
  });

  test('agent{task} с неизвестным пунктом на отменённом ходе: cancelled, а не '
      'Unknown task', () async {
    final gate = Completer<void>();
    var t1Waiting = false;
    final rig = SubagentRig(
      scripts: {
        'go': [
          multiCallStep([
            ('t1', 'task_list', const {}),
            (
              'a1',
              'agent',
              agentArgs('never run', description: 'One', task: '9'),
            ),
          ]),
          replyStep('after cancel'),
        ],
      },
    );
    await rig.open(
      ports: SessionHostPorts(
        extraBeforeToolCall: [
          (call, args, ctx) async {
            if (call.id == 't1') {
              t1Waiting = true;
              await gate.future;
            }
            return null;
          },
        ],
      ),
    );

    final turn = rig.run('go');
    await pumpUntil(
      () => t1Waiting && rig.eventsOf<ToolCallStarted>().length == 2,
      reason: 'a1 announced and t1 holds the key',
    );
    await rig.session.cancel();
    // a1 стоял на ключе за t1: пока t1 держит место, a1 не завершён. Без этого
    // тест прошёл бы и при проверке пункта до очереди ключа.
    expect(
      rig.eventsOf<ToolCallFinished>().where((e) => e.toolCallId == 'a1'),
      isEmpty,
    );
    gate.complete();
    await turn.timeout(const Duration(seconds: 5));

    final finished = {
      for (final e in rig.eventsOf<ToolCallFinished>()) e.toolCallId: e.outcome,
    };
    expect(finished['a1'], ToolOutcome.cancelled);
  });
}
