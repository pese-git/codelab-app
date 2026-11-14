import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../subagents/subagent_rig.dart';

/// Субагенты и `task_*` в одном пакете при стратегии «parallel + очередь
/// ключа» (D39-alt; LOOP-4, TOOL-7, TSK-1; design.md change
/// `add-subagents-and-tasks`, D39, D35;
/// `agent-core/17-16-task-list.md` §17.16a.4).
///
/// Почему отдельный файл: барьер итерации 2 (`task_*` — `sequential`) делил
/// пакет `[task_update, agent, agent]` на группы и откладывал детей до конца
/// `task_update`. `task_*` барьеров не образуют: пакет — одна параллельная
/// группа, а порядок операций списка держит очередь ключа `tasks` в
/// `ToolExecutor` сессии.
///
/// Время — `FakeClock` (дети ждут `delayMs`), «одновременно» проверяется
/// порядком событий и таймерами, без `Future.delayed`.
void main() {
  bool toolStarted(AgentEvent e, String id) =>
      e is ToolCallStarted && e.toolCallId == id;
  bool toolFinished(AgentEvent e, String id) =>
      e is ToolCallFinished && e.toolCallId == id;
  int indexOf(List<AgentEvent> events, bool Function(AgentEvent) test) =>
      events.indexWhere(test);

  test('[task_update, agent, agent]: оба agent стартуют, не дожидаясь друг '
      'друга и task_update; task_update применён', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep('t0', 'task_create', {'subject': 'Split the work'}),
          multiCallStep([
            ('t1', 'task_update', {'id': '1', 'status': 'in_progress'}),
            ('a1', 'agent', agentArgs('child one', description: 'One')),
            ('a2', 'agent', agentArgs('child two', description: 'Two')),
          ]),
          replyStep('done'),
        ],
        'child one': [replyStep('one', delayMs: 10)],
        'child two': [replyStep('two', delayMs: 10)],
      },
    );
    await rig.open();

    final turn = rig.run('go');
    // Оба ребёнка ждут часы одновременно: ни один не закончил.
    await pumpUntil(
      () =>
          rig.eventsOf<SubagentStarted>().length == 2 &&
          rig.clock.pendingTimers >= 2,
      reason: 'both children must be waiting on the clock together',
    );
    expect(rig.eventsOf<SubagentFinished>(), isEmpty);
    await rig.clock.elapse(const Duration(milliseconds: 10));
    final result = await turn;

    expect(result.reason, TurnEndReason.completed);
    final events = rig.events;
    // Барьера нет: все три Started идут раньше любого Finished, в частности
    // ребёнок не ждёт конца task_update.
    final firstFinished = indexOf(
      events,
      (e) => e is ToolCallFinished && e.toolCallId != 't0',
    );
    for (final id in ['t1', 'a1', 'a2']) {
      expect(
        indexOf(events, (e) => toolStarted(e, id)),
        lessThan(firstFinished),
        reason: id,
      );
    }
    // task_update применён: событие списка вызова t1 и статус в результате.
    final changed = rig.eventsOf<TaskListChanged>().where(
      (e) => e.change.toolCallId == 't1',
    );
    expect(changed, hasLength(1));
    expect(changed.single.items.single.status, TaskStatus.inProgress);
    expect(
      indexOf(events, (e) => e == changed.single),
      lessThan(indexOf(events, (e) => toolFinished(e, 't1'))),
      reason: 'TSK-1',
    );
    expect(resultIsError(rig.requestsOf('go').last, 't1'), isFalse);
  });

  test('[agent, task_create, agent, task_create]: одна группа, id задач по '
      'порядку ответа, оба субагента параллельно', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          multiCallStep([
            ('a1', 'agent', agentArgs('child one', description: 'One')),
            ('c1', 'task_create', {'subject': 'first'}),
            ('a2', 'agent', agentArgs('child two', description: 'Two')),
            ('c2', 'task_create', {'subject': 'second'}),
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
    // Пока дети работают, оба task_create уже выполнены (не ждут барьера).
    expect(rig.eventsOf<TaskListChanged>(), hasLength(2));
    expect(rig.eventsOf<SubagentFinished>(), isEmpty);
    await rig.clock.elapse(const Duration(milliseconds: 10));
    await turn;

    final changes = rig.eventsOf<TaskListChanged>();
    expect([for (final c in changes) c.change.toolCallId], ['c1', 'c2']);
    expect([for (final c in changes) c.change.changed.single.id], ['1', '2']);
    final last = rig.requestsOf('go').last;
    expect(resultText(last, 'c1'), startsWith('Created task #1'));
    expect(resultText(last, 'c2'), startsWith('Created task #2'));
    expect(
      [
        for (final m in last.messages.whereType<ToolResultMessage>())
          m.toolCallId,
      ],
      ['a1', 'c1', 'a2', 'c2'],
      reason: 'LOOP-3: результаты в порядке ответа',
    );
  });

  test('отмена хода при двух работающих субагентах и task_* в очереди '
      'ключа: дети cancelled, ход cancelled, ключ освобождён', () async {
    // t1 держит ключ `tasks` в afterToolCall (ключ отпускается после
    // хуков), t2 уже прошёл beforeToolCall и ждёт ключ.
    final holdKey = Completer<void>();
    var holding = false;
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep('t0', 'task_create', {'subject': 'Work'}),
          multiCallStep([
            ('a1', 'agent', agentArgs('wait one', description: 'One')),
            ('a2', 'agent', agentArgs('wait two', description: 'Two')),
            ('t1', 'task_update', {'id': '1', 'status': 'in_progress'}),
            ('t2', 'task_update', {'id': '1', 'status': 'completed'}),
          ]),
          oneCallStep('t3', 'task_list', const {}),
          replyStep('after cancel'),
        ],
        'wait one': [
          {
            'waitForCancel': true,
            'reply': [
              {'text': 'working'},
            ],
          },
        ],
        'wait two': [
          {
            'waitForCancel': true,
            'reply': [
              {'text': 'working'},
            ],
          },
        ],
      },
    );
    await rig.open(
      ports: SessionHostPorts(
        extraAfterToolCall: [
          (call, result, isError) async {
            if (call.id == 't1') {
              holding = true;
              await holdKey.future;
            }
            return null;
          },
        ],
      ),
    );

    final turn = rig.run('go');
    await pumpUntil(
      () =>
          holding &&
          rig.eventsOf<SubagentStarted>().length == 2 &&
          rig.requestsOf('wait one').isNotEmpty &&
          rig.requestsOf('wait two').isNotEmpty,
      reason: 'children running and t1 holding the key',
    );
    await rig.session.cancel();
    // Дети отменяются сами по токену, не дожидаясь держателя ключа.
    await pumpUntil(
      () => rig.eventsOf<SubagentFinished>().length == 2,
      reason: 'both children must finish by the turn token',
    );
    holdKey.complete();
    final result = await turn.timeout(const Duration(seconds: 5));

    expect(result.reason, TurnEndReason.cancelled);
    expect(
      rig.eventsOf<SubagentFinished>().map((e) => e.status),
      everyElement(SubagentState.cancelled),
    );
    final finished = {
      for (final e in rig.eventsOf<ToolCallFinished>()) e.toolCallId: e.outcome,
    };
    expect(finished['a1'], ToolOutcome.cancelled);
    expect(finished['a2'], ToolOutcome.cancelled);
    expect(finished.keys, containsAll(['t1', 't2']));

    // Ключ свободен: task_list следующего хода не зависает на очереди.
    final next = await rig.run('again').timeout(const Duration(seconds: 5));
    expect(next.reason, TurnEndReason.completed);
    expect(resultIsError(rig.requestsOf('go').last, 't3'), isFalse);
  });
}
