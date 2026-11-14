import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart';
import 'subagent_rig.dart';

/// Владелец пункта списка корня — субагент дерева, и резерв `SubagentId`
/// (agent-tools «Инструменты списка задач», владелец «не из дерева»;
/// design.md change `add-subagents-and-tasks`, D28, D36 Т6, Т7;
/// `agent-core/17-16-task-list.md` §17.16.4: «когда-либо запущенный в
/// дереве»).
///
/// Красные до задач 2.4 и 2.4a: у списка корня по умолчанию владелец —
/// только `main`; нужен `isKnownOwner` по записям `subagent` журнала корня и
/// хэндлам дерева, а id резервирует `SubagentTool.present`.
void main() {
  Future<TaskResult> assign(AgentSession session, String owner) =>
      session.tasks.apply(
        CreateTask(subject: 'For $owner', owner: TaskOwner(owner)),
        const MainActor(),
      );

  group('резерв SubagentId (D28, Т6)', () {
    test('id из ToolCallStarted.subagent — тот же, что у SubagentStarted; '
        'type — тип вызова', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('look', type: 'explore')),
            replyStep('done'),
          ],
          'look': [replyStep('seen')],
        },
      );
      await rig.open();

      await rig.run('go');

      final ref = rig.eventsOf<ToolCallStarted>().single.subagent!;
      expect(ref.id, rig.eventsOf<SubagentStarted>().single.subagentId);
      expect(ref.type, 'explore');
      expect(ref.id, matches(RegExp(r'^sub_[0-9a-z]{8}$')));
    });

    test('отклонённый вызов (заголовок из двух символов): id есть в '
        'ToolCallStarted, ребёнка и журнала нет, id владельцем не '
        'становится', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('look', description: 'ab')),
            replyStep('done'),
          ],
        },
      );
      await rig.open();

      await rig.run('go');

      final reserved = rig.eventsOf<ToolCallStarted>().single.subagent!.id;
      expect(rig.eventsOf<SubagentStarted>(), isEmpty);
      expect(rig.rootJournal, isNot(contains('"type":"subagent"')));
      final result = await assign(rig.session, reserved);
      expect(result, isA<TaskRejected>());
      expect((result as TaskRejected).reason, TaskRejectReason.owner);
    });

    test('каждый вызов резервирует свой id', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            multiCallStep([
              ('c1', 'agent', agentArgs('one', description: 'ab')),
              ('c2', 'agent', agentArgs('two', description: 'cd')),
            ]),
            replyStep('done'),
          ],
        },
      );
      await rig.open();

      await rig.run('go');

      final ids = [
        for (final e in rig.eventsOf<ToolCallStarted>()) e.subagent!.id,
      ];
      expect(ids.toSet(), hasLength(2));
    });
  });

  group('isKnownOwner списка корня (задача 2.4a)', () {
    test('id запущенного ребёнка принимается владельцем после его '
        'завершения', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('look')),
            replyStep('done'),
          ],
          'look': [replyStep('seen')],
        },
      );
      await rig.open();
      await rig.run('go');
      final id = rig.eventsOf<SubagentStarted>().single.subagentId;

      final result = await assign(rig.session, id);

      expect(result, isA<TaskApplied>());
    });

    test('неизвестный id и произвольная строка — не владельцы', () async {
      final rig = SubagentRig(scripts: const {});
      await rig.open();

      expect(await assign(rig.session, 'sub_neverran'), isA<TaskRejected>());
      expect(await assign(rig.session, 'main'), isA<TaskApplied>());
    });

    test('после перезагрузки сессии принимается id из записи subagent '
        'журнала корня — в любом статусе', () async {
      const rootId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
      String record(
        String id,
        String? parent,
        String subagentId,
        String status,
      ) => jsonEncode({
        'type': 'subagent',
        'id': id,
        'parentId': parent,
        'timestamp': at,
        'subagentId': subagentId,
        'toolCallId': 'c1',
        'agent': 'explore',
        'description': 'Old job',
        'status': status,
      });
      final text = journal([
        header(cwd: '/proj', id: rootId.value),
        modelChange('m1', null),
        user('u1', 'm1', text: 'resume'),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'agent', {'description': 'Old job', 'prompt': 'old'}),
          ],
        ),
        record('s1', 'a1', 'sub_oldchild1', 'running'),
        record('s2', 's1', 'sub_oldchild2', 'completed'),
      ]);
      final rig = SubagentRig(
        store: MemorySessionStore()..putText(rootId, text),
        scripts: const {},
      );

      final session = await rig.load(rootId);

      expect(await assign(session, 'sub_oldchild1'), isA<TaskApplied>());
      expect(await assign(session, 'sub_oldchild2'), isA<TaskApplied>());
      expect(await assign(session, 'sub_neverran'), isA<TaskRejected>());
    });
  });
}
