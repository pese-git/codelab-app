import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'subagent_rig.dart';

/// Бюджет предков на границе шага потомка (agent-subagents «Бюджет и usage
/// дерева», сценарий «Бюджет корня останавливает внука»; SUB-11, LOOP-12;
/// design.md change `add-subagents-and-tasks`, D4, D45 Т5;
/// `agent-core/17-3-subagents.md` §17.3.4, шаг 7).
///
/// Красные до задач 4.2 и 4.3: у потомка нет `agent`, а `ancestorBudget`
/// проверяет только бюджет корня и не знает usage промежуточных предков и
/// внуков.
void main() {
  Map<String, Object?> usage(int input, int output) => {
    'input': input,
    'output': output,
  };

  /// Внук глубины 2 из SubagentFinished дерева: единственный потомок
  /// глубины 2 в этих сценариях.
  SubagentFinished grandchildOf(SubagentRig rig) =>
      allFinished(rig).singleWhere((f) => f.parentToolCallId == 'g1');

  test('сценарий «Бюджет корня останавливает внука»: токены хода корня '
      'исчерпаны usage внука, пока корень и ребёнок ждут — внук '
      'останавливается на своей границе шага с budget_exceeded:tokens, его '
      'usage входит в TurnEnded.usage корня', () async {
    // Корень 40; ребёнок 20; внук 50 + 50. Бюджет корня 130: после первого
    // шага внука 110 < 130, после второго 160 — на границе третьего шага
    // внук видит бюджет корня, хотя собственный бюджет внука не тронут.
    final rig = SubagentRig(
      config: rigConfig(budget: const TurnBudget(maxTokens: 130)),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('kid'), usage: usage(30, 10)),
          replyStep('root never asks again'),
        ],
        'kid': [
          oneCallStep(
            'g1',
            'agent',
            agentArgs('grandchild'),
            usage: usage(20, 0),
          ),
          replyStep('kid never asks again'),
        ],
        'grandchild': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}, usage: usage(40, 10)),
          oneCallStep('r2', 'read', {'path': 'b.txt'}, usage: usage(50, 0)),
          replyStep('third step is never requested'),
        ],
      },
    );
    await rig.open();

    final result = await rig.run('go');

    expect(rig.requestsOf('grandchild'), hasLength(2));
    final grand = grandchildOf(rig);
    expect(grand.status, SubagentState.failed);
    expect(grand.failure, SubagentFailure.budgetExceeded);
    expect(grand.budgetExceeded, BudgetLimit.tokens);
    expect(result.budgetExceeded, BudgetLimit.tokens);
    // Usage ребёнка вместе с внуком: 20 + (90 + 10) входа и выхода.
    expect(result.subagentUsage, const Usage(input: 110, output: 10));
    expect(result.usage.input, 30 + 110);
    expect(result.usage.output, 10 + 10);
  });

  test('бюджет ребёнка останавливает внука (D45 Т5): subagents.max_tokens '
      'против usage ребёнка вместе с внуком — внук стоит, хотя его '
      'собственный бюджет не исчерпан', () async {
    // max_tokens 100 у каждого потомка. Ребёнок 30, внук 40 + 40: сам внук
    // потратил 80 < 100, но ребёнок вместе с ним — 110 ≥ 100.
    final rig = SubagentRig(
      config: CoreConfig(
        defaultModel: subagentTestModel,
        subagents: const SubagentsConfig(maxTokens: 100),
      ),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('kid')),
          replyStep('noted'),
        ],
        'kid': [
          oneCallStep(
            'g1',
            'agent',
            agentArgs('grandchild'),
            usage: usage(30, 0),
          ),
          replyStep('kid never asks again'),
        ],
        'grandchild': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}, usage: usage(40, 0)),
          oneCallStep('r2', 'read', {'path': 'b.txt'}, usage: usage(40, 0)),
          replyStep('third step is never requested'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    expect(rig.requestsOf('grandchild'), hasLength(2));
    final grand = grandchildOf(rig);
    expect(grand.status, SubagentState.failed);
    expect(grand.failure, SubagentFailure.budgetExceeded);
    expect(grand.budgetExceeded, BudgetLimit.tokens);
    expect(
      grand.usage,
      const Usage(input: 80, output: 0),
      reason: 'собственный usage внука ниже его бюджета',
    );
  });
}
