import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../subagents/subagent_rig.dart';
import '../support/models.dart';

/// `core/subagent-nested-no-deadlock` (agent-subagents «Вложенность и слоты
/// дерева», сценарий «Нет взаимоблокировки при одном слоте»; SUB-23, SUB-24;
/// design.md change `add-subagents-and-tasks`, D3, Risks «Взаимоблокировка
/// при глубине 3»; `agent-core/17-3-subagents.md` §17.3.4, шаг 2).
///
/// Красный до задачи 4.2: у потомка нет `agent`, поэтому ни внука, ни
/// правнука не запускается, а возврата слота родителем нет. Вложенность
/// ребёнок → внук → правнук при единственном слоте завершается, только если
/// ждущий родитель отдаёт слот потомку и берёт его обратно (`acquire(resume:
/// true)`).
void main() {
  group('core/subagent-nested-no-deadlock', () {
    test('max_concurrent 1, max_depth 3: ребёнок запускает внука, внук — '
        'правнука; все трое завершаются, ход корня завершается', () async {
      final rig = SubagentRig(
        config: CoreConfig(
          defaultModel: subagentTestModel,
          subagents: const SubagentsConfig(maxConcurrent: 1, maxDepth: 3),
        ),
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('level one')),
            replyStep('all done'),
          ],
          'level one': [
            oneCallStep('c2', 'agent', agentArgs('level two')),
            replyStep('level one done'),
          ],
          'level two': [
            oneCallStep('c3', 'agent', agentArgs('level three')),
            replyStep('level two done'),
          ],
          'level three': [replyStep('level three done')],
        },
      );
      await rig.open();

      final result = await rig.run('go');

      expect(result.reason, TurnEndReason.completed);
      final finished = allFinished(rig);
      expect(finished, hasLength(3));
      expect(
        finished.map((f) => f.status),
        everyElement(SubagentState.completed),
      );
      expect(rig.eventsOf<SubagentStarted>(), hasLength(1));
      expect(allStarted(rig).map((s) => s.parentToolCallId), [
        'c1',
        'c2',
        'c3',
      ], reason: 'три потомка разной глубины по вызовам agent своих родителей');
      // Родители уровней 1 и 2 вернули слот на ожидании и взяли его обратно.
      expect(rig.logger.eventsOf('subagent.slot.resume'), hasLength(2));
      expect(
        resultText(rig.requestsOf('go').last, 'c1'),
        contains('level one done'),
      );
    });
  });
}
