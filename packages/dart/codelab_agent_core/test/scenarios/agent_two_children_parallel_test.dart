import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../subagents/subagent_rig.dart';
import '../support/models.dart';

/// `core/agent-two-children-parallel` (agent-subagents «Вложенность и слоты
/// дерева», сценарии «Предел слотов дерева» в варианте глубины 1 и «Лимит
/// запусков»; agent-loop «Пакет инструментов», сценарий «Барьер делит пакет
/// на группы»; SUB-4, SUB-5, SUB-23, LOOP-3, LOOP-4; design.md change
/// `add-subagents-and-tasks`, D3, D39, D36 Т14;
/// `agent-core/17-3-subagents.md` §17.3.4, шаги 1–2, 5–6).
///
/// Красный до задач 2.4 и 2.4b: нет `SubagentManager` и событий
/// `Subagent*`, а `task_*` сегодня делают последовательным весь пакет, в
/// том числе вызовы `agent` после них.
///
/// Сценарный тест ядра, а не фикстура `codelab_acp_testing` (D36 Т14):
/// модель — скрипты по участникам дерева (`SubagentRig`), время — `FakeClock`.
/// Дети ждут часы (`delayMs`), поэтому «одновременно» проверяется порядком
/// событий, а не гонкой.
void main() {
  int indexOf(List<AgentEvent> events, bool Function(AgentEvent) test) =>
      events.indexWhere(test);

  bool toolStarted(AgentEvent e, String id) =>
      e is ToolCallStarted && e.toolCallId == id;
  bool toolFinished(AgentEvent e, String id) =>
      e is ToolCallFinished && e.toolCallId == id;

  test('[task_update, agent, agent]: task_update — барьер, два agent после '
      'него одной группой; дети работают одновременно, итоги в порядке '
      'завершения, результаты — в порядке ответа', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep('t0', 'task_create', {'subject': 'Split the work'}),
          multiCallStep([
            ('t1', 'task_update', {'id': '1', 'status': 'in_progress'}),
            ('a1', 'agent', agentArgs('slow child', description: 'Slow one')),
            ('a2', 'agent', agentArgs('fast child', description: 'Fast one')),
          ]),
          replyStep('both done'),
        ],
        'slow child': [replyStep('slow report', delayMs: 20)],
        'fast child': [replyStep('fast report', delayMs: 5)],
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

    // Оба ребёнка уже стартовали, пока ни один не закончил.
    expect(rig.eventsOf<SubagentStarted>(), hasLength(2));
    expect(rig.eventsOf<SubagentFinished>(), isEmpty);

    await rig.clock.elapse(const Duration(milliseconds: 5));
    expect(
      [for (final e in rig.eventsOf<SubagentFinished>()) e.parentToolCallId],
      ['a2'],
      reason: 'быстрый ребёнок закончил первым',
    );
    await rig.clock.elapse(const Duration(milliseconds: 15));
    final result = await turn;

    expect(result.reason, TurnEndReason.completed);
    final events = rig.events;
    // Барьер: task_update целиком до первого ToolCallStarted(agent).
    expect(
      indexOf(events, (e) => toolFinished(e, 't1')),
      lessThan(indexOf(events, (e) => toolStarted(e, 'a1'))),
    );
    // Группа: оба ToolCallStarted(agent) по порядку ответа до первого
    // SubagentStarted.
    final firstStarted = indexOf(events, (e) => e is SubagentStarted);
    expect(
      indexOf(events, (e) => toolStarted(e, 'a1')),
      lessThan(indexOf(events, (e) => toolStarted(e, 'a2'))),
    );
    expect(
      indexOf(events, (e) => toolStarted(e, 'a2')),
      lessThan(firstStarted),
    );
    // ToolCallFinished(agent) — в порядке завершения, каждому предшествует
    // SubagentFinished своего ребёнка (SUB-10).
    expect(
      indexOf(events, (e) => toolFinished(e, 'a2')),
      lessThan(indexOf(events, (e) => toolFinished(e, 'a1'))),
    );
    for (final id in ['a1', 'a2']) {
      expect(
        indexOf(
          events,
          (e) => e is SubagentFinished && e.parentToolCallId == id,
        ),
        lessThan(indexOf(events, (e) => toolFinished(e, id))),
        reason: id,
      );
    }
    // Результаты в транскрипте — в порядке вызовов ответа (LOOP-3).
    final last = rig.requestsOf('go').last;
    expect(
      [
        for (final m in last.messages.whereType<ToolResultMessage>())
          m.toolCallId,
      ],
      ['t0', 't1', 'a1', 'a2'],
    );
    expect(resultText(last, 'a1'), contains('slow report'));
    expect(resultText(last, 'a2'), contains('fast report'));
  });

  test('сценарий «Предел слотов дерева» (глубина 1): три agent при '
      'max_concurrent 2 — слот держат не больше двух, третий ждёт в очереди '
      'и стартует после освобождения слота', () async {
    final rig = SubagentRig(
      config: CoreConfig(
        defaultModel: subagentTestModel,
        subagents: const SubagentsConfig(maxConcurrent: 2, maxDepth: 1),
      ),
      scripts: {
        'go': [
          multiCallStep([
            ('a1', 'agent', agentArgs('child one', description: 'One')),
            ('a2', 'agent', agentArgs('child two', description: 'Two')),
            ('a3', 'agent', agentArgs('child three', description: 'Three')),
          ]),
          replyStep('all done'),
        ],
        'child one': [replyStep('one', delayMs: 10)],
        'child two': [replyStep('two', delayMs: 10)],
        'child three': [replyStep('three', delayMs: 10)],
      },
    );
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(
      () => rig.eventsOf<SubagentStarted>().length == 2,
      reason: 'two children must get the two slots',
    );
    // Третий ребёнок в очереди: ни слота, ни журнала, ни запроса к модели.
    await pumpEventQueue(times: 30);
    expect(rig.eventsOf<SubagentStarted>(), hasLength(2));
    expect(rig.requestsOf('child three'), isEmpty);

    var holding = 0;
    var peak = 0;
    for (final e in rig.events) {
      if (e is SubagentStarted) {
        holding++;
      } else if (e is SubagentFinished) {
        holding--;
      }
      peak = holding > peak ? holding : peak;
    }
    expect(peak, 2);

    await rig.clock.elapse(const Duration(milliseconds: 10));
    await pumpUntil(
      () => rig.eventsOf<SubagentStarted>().length == 3,
      reason: 'the queued child must get the freed slot',
    );
    await rig.clock.elapse(const Duration(milliseconds: 10));
    await turn;

    // По всему ходу пик занятых слотов не больше двух; третий стартовал
    // после первого SubagentFinished (порядок spawn — порядок ответа).
    var running = 0;
    var maxRunning = 0;
    for (final e in rig.events) {
      if (e is SubagentStarted) {
        running++;
      } else if (e is SubagentFinished) {
        running--;
      }
      maxRunning = running > maxRunning ? running : maxRunning;
    }
    expect(maxRunning, lessThanOrEqualTo(2));
    final started = rig.eventsOf<SubagentStarted>();
    expect([for (final s in started) s.parentToolCallId], ['a1', 'a2', 'a3']);
    expect(
      indexOf(rig.events, (e) => e is SubagentFinished),
      lessThan(indexOf(rig.events, (e) => e == started.last)),
    );
  });

  group('сценарий «Лимит запусков» (глубина 1)', () {
    CoreConfig limited() => CoreConfig(
      defaultModel: subagentTestModel,
      subagents: const SubagentsConfig(maxPerTurn: 2, maxDepth: 1),
    );

    test('max_per_turn 2: третий вызов — ошибка лимита, остальные '
        'работают', () async {
      final rig = SubagentRig(
        config: limited(),
        scripts: {
          'go': [
            multiCallStep([
              ('a1', 'agent', agentArgs('child one', description: 'One')),
              ('a2', 'agent', agentArgs('child two', description: 'Two')),
              ('a3', 'agent', agentArgs('child three', description: 'Three')),
            ]),
            replyStep('done'),
          ],
          'child one': [replyStep('one')],
          'child two': [replyStep('two')],
        },
      );
      await rig.open();

      await rig.run('go');

      final last = rig.requestsOf('go').last;
      expect(resultText(last, 'a1'), contains('one'));
      expect(resultText(last, 'a2'), contains('two'));
      expect(
        resultText(last, 'a3'),
        startsWith('Subagent limit reached: at most 2 subagents per turn.'),
      );
      expect(resultIsError(last, 'a3'), isTrue);
      expect(rig.requestsOf('child three'), isEmpty);
      expect(rig.eventsOf<SubagentStarted>(), hasLength(2));
    });

    test('счётчик запусков сбрасывается новым ходом корня', () async {
      final rig = SubagentRig(
        config: limited(),
        scripts: {
          'go': [
            multiCallStep([
              ('a1', 'agent', agentArgs('child one', description: 'One')),
              ('a2', 'agent', agentArgs('child two', description: 'Two')),
            ]),
            replyStep('first turn'),
            multiCallStep([
              ('a3', 'agent', agentArgs('child three', description: 'Three')),
              ('a4', 'agent', agentArgs('child four', description: 'Four')),
            ]),
            replyStep('second turn'),
          ],
          'child one': [replyStep('one')],
          'child two': [replyStep('two')],
          'child three': [replyStep('three')],
          'child four': [replyStep('four')],
        },
      );
      await rig.open();

      await rig.run('go');
      await rig.run('again');

      final last = rig.requestsOf('go').last;
      expect(resultIsError(last, 'a3'), isFalse);
      expect(resultIsError(last, 'a4'), isFalse);
      expect(rig.eventsOf<SubagentStarted>(), hasLength(4));
    });
  });
}
