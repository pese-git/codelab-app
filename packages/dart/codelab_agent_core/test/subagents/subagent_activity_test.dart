import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'subagent_rig.dart';

/// События потомков в потоке родителя, вариант глубины 1 (agent-subagents
/// «События потомков в потоке родителя», сценарий «Адрес события внука» в
/// части глубины 1; agent-loop «События AgentEvent»; LOOP-2, SUB-12, SUB-24;
/// design.md change `add-subagents-and-tasks`, D6;
/// `agent-core/17-3-subagents.md` §17.3.2 «События», §17.3.4 шаг 4).
///
/// Красные до задач 2.4 и 2.6: нет `SubagentManager`, событий `Subagent*` и
/// строки прогресса через `onUpdate`.
void main() {
  Future<(SubagentRig, MemoryExecutionEnv)> readingChild() async {
    final env = MemoryExecutionEnv(cwd: '/proj');
    await env.writeText('/proj/a.txt', 'alpha\n');
    final rig = SubagentRig(
      baseEnv: env,
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('read a.txt', type: 'explore')),
          replyStep('thanks'),
        ],
        'read a.txt': [
          oneCallStep('child_read_1', 'read', {'path': 'a.txt'}),
          replyStep('alpha it is'),
        ],
      },
    );
    await rig.open();
    await rig.run('go');
    return (rig, env);
  }

  test('событие ребёнка переизлучается в поток родителя обёрнутым: адрес '
      'depth 1, path пуст, вызов agent родителя, исходное событие '
      'внутри', () async {
    final (rig, _) = await readingChild();

    final started = rig.eventsOf<SubagentStarted>().single;
    final read = rig.eventsOf<SubagentActivity>().where((a) {
      final inner = a.event;
      return inner is ToolCallStarted && inner.tool == 'read';
    }).single;

    expect(read.sessionId, rig.session.id, reason: 'sessionId — родительский');
    expect(read.subagentId, started.subagentId);
    expect(read.parentToolCallId, 'c1');
    expect(read.depth, 1);
    expect(read.path, isEmpty);
    expect(read.event.sessionId, started.childSessionId);
  });

  test(
    'обёртка плоская: ни одна SubagentActivity не вложена в другую',
    () async {
      final (rig, _) = await readingChild();

      final activity = rig.eventsOf<SubagentActivity>();

      expect(activity, isNotEmpty);
      expect(activity.every((a) => a.event is! SubagentActivity), isTrue);
    },
  );

  test('журнал родителя не содержит событий ребёнка: SubagentActivity не '
      'пишется (SessionWriter)', () async {
    final (rig, _) = await readingChild();

    expect(rig.rootJournal, isNot(contains('child_read_1')));
  });

  test('порядок для одного вызова: ToolCallStarted(agent), SubagentStarted, '
      'SubagentProgress…, SubagentFinished, ToolCallFinished(agent)', () async {
    final (rig, _) = await readingChild();

    int at(bool Function(AgentEvent) test) => rig.events.indexWhere(test);
    final callStarted = at((e) => e is ToolCallStarted && e.toolCallId == 'c1');
    final started = at((e) => e is SubagentStarted);
    final firstProgress = at((e) => e is SubagentProgress);
    final finished = at((e) => e is SubagentFinished);
    final callFinished = at(
      (e) => e is ToolCallFinished && e.toolCallId == 'c1',
    );

    expect(callStarted, lessThan(started));
    expect(started, lessThan(firstProgress));
    expect(firstProgress, lessThan(finished));
    expect(finished, lessThan(callFinished));
    // События ребёнка — между его стартом и итогом.
    final firstActivity = at((e) => e is SubagentActivity);
    expect(firstActivity, greaterThan(started));
    expect(
      rig.events.lastIndexWhere((e) => e is SubagentActivity),
      lessThan(finished),
    );
  });

  group('строка прогресса через onUpdate (§17.3.4, шаг 4)', () {
    List<String> progressLines(SubagentRig rig) => [
      for (final e in rig.eventsOf<ToolCallProgress>())
        if (e.toolCallId == 'c1')
          for (final c in e.content)
            if (c is ToolCallBlock && c.block is TextContent)
              (c.block as TextContent).text,
    ];

    final shape = RegExp(
      r'^explore · (running|waiting) · \d+ steps · \d+ tool calls · '
      r'\d+(\.\dk)? tokens( · \d+ subagents)?( · .{1,60})?$',
    );

    test('формат: <agent> · <state> · N steps · N tool calls · tokens, '
        'lastActivity — title последнего вызова ребёнка', () async {
      final (rig, _) = await readingChild();

      final lines = progressLines(rig);

      expect(lines, isNotEmpty);
      expect(lines, everyElement(matches(shape)));
      final title = rig
          .eventsOf<SubagentActivity>()
          .map((a) => a.event)
          .whereType<ToolCallStarted>()
          .single
          .title;
      expect(lines.any((l) => l.endsWith(' · $title')), isTrue);
    });

    test('чаще progress_interval не приходит; после интервала — следующая '
        'строка', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep(
              'c1',
              'agent',
              agentArgs('busy child', type: 'explore'),
            ),
            replyStep('thanks'),
          ],
          'busy child': [
            oneCallStep('r1', 'read', {'path': 'a.txt'}),
            oneCallStep('r2', 'read', {'path': 'b.txt'}),
            oneCallStep('r3', 'read', {'path': 'c.txt'}, delayMs: 2000),
            replyStep('done'),
          ],
        },
      );
      await rig.open();

      final turn = rig.run('go');
      await pumpUntil(
        () => rig.clock.pendingTimers > 0,
        reason: 'the child never reached the delayed step',
      );
      final before = progressLines(rig).length;
      await rig.clock.elapse(const Duration(milliseconds: 2000));
      await turn;

      // Первые шаги пришли в один момент часов: одна строка на них.
      expect(before, 1);
      expect(progressLines(rig).length, greaterThan(before));
    });

    test(
      'без событий строка приходит раз в heartbeat_interval (15 с)',
      () async {
        final rig = SubagentRig(
          scripts: {
            'go': [
              oneCallStep(
                'c1',
                'agent',
                agentArgs('slow child', type: 'explore'),
              ),
              replyStep('thanks'),
            ],
            'slow child': [replyStep('late report', delayMs: 40000)],
          },
        );
        await rig.open();

        final turn = rig.run('go');
        await pumpUntil(() => rig.clock.pendingTimers > 0);
        final first = progressLines(rig).length;
        await rig.clock.elapse(const Duration(seconds: 15));
        final second = progressLines(rig).length;
        await rig.clock.elapse(const Duration(seconds: 15));
        final third = progressLines(rig).length;
        await rig.clock.elapse(const Duration(seconds: 10));
        await turn;

        expect(second, first + 1);
        expect(third, second + 1);
      },
    );
  });
}
