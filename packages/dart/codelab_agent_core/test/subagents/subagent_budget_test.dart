import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'subagent_rig.dart';

/// Бюджет и usage ребёнка (agent-subagents «Отчёт ребёнка», сценарий «Бюджет
/// ребёнка», «Итог с потомками»; «Бюджет и usage дерева» для глубины 1;
/// SUB-11, LOOP-12; design.md change `add-subagents-and-tasks`, D4,
/// D36 Т8; `agent-core/17-3-subagents.md` §17.3.3 шаг 9, §17.3.4 шаг 7).
///
/// Красные до задач 2.4–2.5: нет `SubagentTool`, `TurnEnded.subagentUsage` и
/// `TurnResult.subagentUsage`, источника usage детей в `AgentLoopConfig` и
/// проверки бюджета предков на границе шага ребёнка.
void main() {
  Map<String, Object?> usage(int input, int output) => {
    'input': input,
    'output': output,
  };

  test('сценарий «Бюджет ребёнка»: max_steps 2, ребёнку нужно три шага — '
      'isError и reason="budget_exceeded:steps"', () async {
    final rig = SubagentRig(
      config: CoreConfig(
        defaultModel: testModel,
        subagents: const SubagentsConfig(maxSteps: 2),
      ),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('needs three steps')),
          replyStep('noted'),
        ],
        'needs three steps': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}),
          oneCallStep('r2', 'read', {'path': 'b.txt'}),
          replyStep('third step is never requested'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    expect(rig.requestsOf('needs three steps'), hasLength(2));
    final last = rig.requestsOf('go').last;
    final text = resultText(last, 'c1');
    expect(resultIsError(last, 'c1'), isTrue);
    expect(text, contains('status="failed"'));
    expect(text, contains('reason="budget_exceeded:steps"'));
    expect(
      text,
      contains(
        'Subagent stopped: its budget was exhausted before it finished.',
      ),
    );
    final finished = rig.eventsOf<SubagentFinished>().single;
    expect(finished.status, SubagentState.failed);
    expect(finished.failure, SubagentFailure.budgetExceeded);
  });

  test('сценарий «Бюджет корня на границе шага ребёнка» (глубина 1): usage '
      'ребёнка входит в бюджет хода корня, ребёнок останавливается сам, '
      'пока корень ждёт', () async {
    final rig = SubagentRig(
      config: rigConfig(budget: const TurnBudget(maxTokens: 100)),
      scripts: {
        'go': [
          oneCallStep(
            'c1',
            'agent',
            agentArgs('burns tokens'),
            usage: usage(30, 10),
          ),
          replyStep('root never asks again'),
        ],
        'burns tokens': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}, usage: usage(40, 10)),
          oneCallStep('r2', 'read', {'path': 'b.txt'}, usage: usage(20, 0)),
          replyStep('third step is never requested'),
        ],
      },
    );
    await rig.open();

    final result = await rig.run('go');

    // Корень 40 + ребёнок 50 = 90 < 100 после первого шага ребёнка; после
    // второго — 110: на границе третьего шага ребёнок видит бюджет корня.
    expect(rig.requestsOf('burns tokens'), hasLength(2));
    // Корень после исчерпанного бюджета запрос не делает: результат agent
    // читается из события, а не из следующего запроса.
    final text =
        (rig.eventsOf<ToolCallFinished>().single.content.single as TextContent)
            .text;
    expect(text, contains('reason="budget_exceeded:tokens"'));
    expect(result.budgetExceeded, BudgetLimit.tokens);
    expect(result.subagentUsage, const Usage(input: 60, output: 10));
    // Usage хода корня уже включает usage ребёнка (SUB-11).
    expect(result.usage.input, 30 + 60);
    expect(result.usage.output, 10 + 10);
  });

  test('сценарий «Итог с потомками» (глубина 1): usage ребёнка — отдельная '
      'строка subagentUsage в TurnEnded и в TurnResult, и в сумме usage '
      'хода', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep(
            'c1',
            'agent',
            agentArgs('two steps'),
            usage: usage(10, 5),
          ),
          replyStep('thanks', usage: usage(30, 3)),
        ],
        'two steps': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}, usage: usage(100, 20)),
          replyStep('report', usage: usage(50, 10)),
        ],
      },
    );
    await rig.open();

    final result = await rig.run('go');

    const child = Usage(input: 150, output: 30);
    expect(result.subagentUsage, child);
    final ended = rig.eventsOf<TurnEnded>().single;
    expect(ended.subagentUsage, child);
    expect(ended.usage.input, 10 + 30 + child.input);
    expect(ended.usage.output, 5 + 3 + child.output);
    // Итог ребёнка в событии: usage и число вызовов (D24).
    final finished = rig.eventsOf<SubagentFinished>().single;
    expect(finished.usage.input, child.input);
    expect(finished.usage.output, child.output);
  });

  test('свой бюджет ребёнка: subagents.max_tokens останавливает ребёнка '
      'независимо от бюджета корня', () async {
    final rig = SubagentRig(
      config: CoreConfig(
        defaultModel: testModel,
        subagents: const SubagentsConfig(maxTokens: 50),
      ),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('small budget')),
          replyStep('noted'),
        ],
        'small budget': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}, usage: usage(40, 20)),
          replyStep('not requested'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    expect(rig.requestsOf('small budget'), hasLength(1));
    expect(
      resultText(rig.requestsOf('go').last, 'c1'),
      contains('reason="budget_exceeded:tokens"'),
    );
  });
}
