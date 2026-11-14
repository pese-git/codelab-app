import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/agent.dart';
import 'package:codelab_agent_core/src/subagents/subagent_manager.dart';
import 'package:codelab_agent_core/src/subagents/subagent_types.dart';
import 'package:codelab_agent_core/src/tools/path_lock.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../loop/loop_harness.dart';

/// Хэндл потомка после терминального состояния (agent-subagents «Жизненный
/// цикл и отмена»; design.md change `add-subagents-and-tasks`, D5): очистка
/// дочерней сессии не обнуляет `childSessionId`; `null` — только у ребёнка,
/// отменённого в очереди.
void main() {
  Future<(SubagentManager, List<AgentEvent>, CancelTokenSource)> build() async {
    final h = await LoopHarness.create(llm: script([textStep('report')]));
    final events = <AgentEvent>[];
    final clock = FakeClock();
    final env = MemoryExecutionEnv(cwd: '/proj');
    final manager = SubagentManager(
      tree: SubagentTree(limits: () => const SubagentsConfig(maxConcurrent: 1)),
      limits: () => const SubagentsConfig(maxConcurrent: 1),
      emit: (e) async => events.add(e),
      create: (spec) async => ChildSession(
        id: const SessionId('child-1'),
        journalPath: 'subagents/child-1.jsonl',
        agent: Agent(
          config: h.config(),
          systemPrompt: 'child',
          tools: const [],
        ),
        close: () async {},
      ),
      clock: clock,
      logger: RecordingLogger(),
      sessionId: const SessionId('root'),
      rootBudget: () => const TurnBudget(),
      parent: () => SubagentParent(
        tools: () => const [],
        model: () => h.config().model,
        mode: () => (mode: PermissionMode.write, deniedTiers: const {}),
        skills: SkillCatalog.empty,
        decisions: PermissionDecisionStore(),
        rules: const PolicyRules(),
        env: env,
        tasks: SessionTaskList(),
        locks: PathLock(),
        maxChildDepth: 1,
      ),
    );
    return (manager, events, CancelTokenSource());
  }

  SubagentSpec spec(String id) => SubagentSpec(
    id: id,
    parentSessionId: const SessionId('root'),
    parentToolCallId: 'c_$id',
    depth: 1,
    type: buildSubagentTypes(const []).firstWhere((t) => t.name == 'general'),
    description: 'Job $id',
    prompt: 'do it',
  );

  test('после терминального состояния childSessionId не обнуляется', () async {
    final (manager, events, parent) = await build();

    final handle = manager.spawn(spec('sub_aaaaaaaa'), parent.token);
    final report = await handle.report;
    await pumpEventQueue(times: 30);

    expect(report.status, SubagentState.completed);
    expect(handle.childSessionId, const SessionId('child-1'));
    final finished = events.whereType<SubagentFinished>().single;
    expect(finished.childSessionId, const SessionId('child-1'));
    expect(finished.journalPath, 'subagents/child-1.jsonl');
  });

  test('у ребёнка, отменённого в очереди, childSessionId — null', () async {
    final (manager, events, parent) = await build();
    final holder = CancelTokenSource();
    // Первый занимает единственный слот и не заканчивается до отмены.
    manager.spawn(spec('sub_bbbbbbbb'), holder.token);
    final queued = manager.spawn(spec('sub_cccccccc'), parent.token);
    parent.cancel();

    final report = await queued.report;

    expect(report.status, SubagentState.cancelled);
    expect(queued.childSessionId, isNull);
    holder.cancel();
    expect(events.whereType<SubagentFinished>(), isNotEmpty);
  });
}
