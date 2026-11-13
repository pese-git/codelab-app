import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'subagent_rig.dart';

/// Жизненный цикл и отмена ребёнка (agent-subagents «Жизненный цикл и
/// отмена», сценарии «Отмена хода корня» и «Отмена в момент завершения»;
/// «Вложенность и слоты дерева», абзац об отменённом в очереди; SUB-6, CAN-3,
/// CAN-5; design.md change `add-subagents-and-tasks`, D5;
/// `agent-core/17-3-subagents.md` §17.3.4, шаги 3 и 8).
///
/// Красные до задачи 2.4: нет `SubagentManager`, токена-потомка и событий
/// `Subagent*`. Вариант глубины 1; отмена внука — тесты итерации 4.
void main() {
  /// Корень с одним вызовом `agent`, ребёнок ждёт отмены.
  SubagentRig waitingChild({CoreConfig? config}) => SubagentRig(
    config: config,
    scripts: {
      'go': [
        oneCallStep('c1', 'agent', agentArgs('wait forever')),
        replyStep('never requested'),
      ],
      'wait forever': [
        {
          'waitForCancel': true,
          'reply': [
            {'text': 'working'},
          ],
        },
      ],
    },
  );

  int indexOf(List<AgentEvent> events, bool Function(AgentEvent) test) =>
      events.indexWhere(test);

  test('сценарий «Отмена хода корня»: ребёнок получает cancelled, '
      'TurnEnded(cancelled) корня — после ToolCallFinished(agent) с '
      'cancelled', () async {
    final rig = waitingChild();
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(
      () => rig.requestsOf('wait forever').isNotEmpty,
      reason: 'the child never asked the model',
    );
    await rig.session.cancel();
    final result = await turn;

    expect(result.reason, TurnEndReason.cancelled);
    final finished = rig.eventsOf<SubagentFinished>().single;
    expect(finished.status, SubagentState.cancelled);
    final call = rig.eventsOf<ToolCallFinished>().single;
    expect(call.toolCallId, 'c1');
    expect(call.outcome, ToolOutcome.cancelled);
    final events = rig.events;
    expect(
      indexOf(events, (e) => e == finished),
      lessThan(indexOf(events, (e) => e == call)),
      reason: 'SubagentFinished до ToolCallFinished(agent)',
    );
    expect(
      indexOf(events, (e) => e == call),
      lessThan(indexOf(events, (e) => e is TurnEnded)),
      reason: 'CAN-5: TurnEnded(cancelled) после ToolCallFinished(agent)',
    );
    expect(rig.trace.last, 'TurnEnded(cancelled)');
  });

  test('после отмены ребёнок не переизлучается: ни одного '
      'SubagentActivity после SubagentFinished (поздние события, AGENTS.md '
      '§9)', () async {
    final rig = waitingChild();
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(() => rig.requestsOf('wait forever').isNotEmpty);
    await rig.session.cancel();
    await turn;
    // Дочерняя сессия закрывается в фоне: даём ей завершиться.
    await pumpEventQueue(times: 50);

    final events = rig.events;
    final finished = indexOf(events, (e) => e is SubagentFinished);
    expect(finished, isNonNegative);
    expect(events.skip(finished + 1).whereType<SubagentActivity>(), isEmpty);
  });

  test('сценарий «Отмена в момент завершения»: ровно одно терминальное '
      'состояние, один результат вызова agent, ни одного события ребёнка '
      'после итога', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('finish quickly')),
          replyStep('done'),
        ],
        'finish quickly': [replyStep('quick report')],
      },
    );
    await rig.open();
    // Отмена приходит ровно тогда, когда в поток родителя переизлучается
    // TurnEnded ребёнка: гонка «завершился / отменён».
    rig.session.events.listen((e) {
      if (e is SubagentActivity &&
          e.event is TurnEnded &&
          (e.event as TurnEnded).reason == TurnEndReason.completed) {
        unawaited(rig.session.cancel());
      }
    });

    await rig.run('go');
    await pumpEventQueue(times: 50);

    final finished = rig.eventsOf<SubagentFinished>();
    final calls = rig.eventsOf<ToolCallFinished>().where(
      (e) => e.toolCallId == 'c1',
    );
    expect(finished, hasLength(1));
    expect(calls, hasLength(1));
    // Победило первое записанное состояние, и вызов видит именно его.
    expect(
      calls.single.outcome,
      finished.single.status == SubagentState.completed
          ? ToolOutcome.completed
          : ToolOutcome.cancelled,
    );
    expect(
      finished.single.status,
      anyOf(SubagentState.completed, SubagentState.cancelled),
    );
    final events = rig.events;
    final index = indexOf(events, (e) => e is SubagentFinished);
    expect(events.skip(index + 1).whereType<SubagentActivity>(), isEmpty);
    expect(rig.trace.last, startsWith('TurnEnded('));
  });

  test('ребёнок, отменённый в очереди: SubagentFinished(cancelled) без '
      'SubagentStarted, без запроса к модели и без журнала', () async {
    final rig = SubagentRig(
      config: CoreConfig(
        defaultModel: testModel,
        subagents: const SubagentsConfig(maxConcurrent: 1),
      ),
      scripts: {
        'go': [
          multiCallStep([
            ('a1', 'agent', agentArgs('holds the slot', description: 'First')),
            ('a2', 'agent', agentArgs('waits in queue', description: 'Second')),
          ]),
          replyStep('never requested'),
        ],
        'holds the slot': [
          {
            'waitForCancel': true,
            'reply': [
              {'text': 'working'},
            ],
          },
        ],
        'waits in queue': [replyStep('must not run')],
      },
    );
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(() => rig.requestsOf('holds the slot').isNotEmpty);
    await rig.session.cancel();
    await turn;

    final started = rig.eventsOf<SubagentStarted>();
    expect([for (final s in started) s.parentToolCallId], ['a1']);
    expect(
      {
        for (final f in rig.eventsOf<SubagentFinished>())
          f.parentToolCallId: f.status,
      },
      {'a1': SubagentState.cancelled, 'a2': SubagentState.cancelled},
    );
    expect(rig.requestsOf('waits in queue'), isEmpty);
    final queued = rig.eventsOf<SubagentFinished>().singleWhere(
      (f) => f.parentToolCallId == 'a2',
    );
    expect(queued.usage, Usage.zero);
    expect(queued.duration, Duration.zero);
  });
}
