import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import 'subagent_rig.dart';

/// Наблюдаемость субагентов (design.md change `add-subagents-and-tasks`, D18;
/// `AGENTS.md` §16): события `subagent.*` без текстов промпта и отчёта,
/// логгер ребёнка несёт корреляцию.
void main() {
  Future<SubagentRig> run({PermissionGate? gate, ModeId? mode}) async {
    final rig = SubagentRig(
      gate: gate,
      config: rigConfig(mode: mode),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('secret prompt text')),
          replyStep('done'),
        ],
        'secret prompt text': [
          oneCallStep('w1', 'write', {'path': 'a.txt', 'content': 'x'}),
          replyStep('secret report text'),
        ],
      },
    );
    await rig.open();
    await rig.run('go');
    return rig;
  }

  test('spawn, start, slot.release и end с полями D18', () async {
    final rig = await run();

    final started = rig.eventsOf<SubagentStarted>().single;
    final spawn = rig.logger.eventsOf('subagent.spawn').single;
    expect(spawn.fields['session_id'], rig.session.id.value);
    expect(spawn.fields['tool_call_id'], 'c1');
    expect(spawn.fields['subagent_id'], started.subagentId);
    expect(spawn.fields['subagent_type'], 'general');
    expect(spawn.fields['depth'], 1);
    final start = rig.logger.eventsOf('subagent.start').single;
    expect(start.fields['child_session_id'], started.childSessionId.value);
    expect(start.fields['wait_ms'], isA<int>());
    expect(rig.logger.eventsOf('subagent.slot.release'), hasLength(1));
    final end = rig.logger.eventsOf('subagent.end').single;
    expect(end.fields['status'], 'completed');
    expect(
      end.fields.keys,
      containsAll(['failure', 'steps', 'tool_calls', 'tokens', 'duration_ms']),
    );
  });

  test('в логах нет текстов промпта и отчёта', () async {
    final rig = await run();

    final text = [
      for (final r in rig.logger.records) '$r ${r.fields}',
    ].join('\n');
    expect(text, isNot(contains('secret prompt text')));
    expect(text, isNot(contains('secret report text')));
  });

  test('отказ политики ребёнка несёт session_id ребёнка, root_session_id, '
      'subagent_id и parent_tool_call_id', () async {
    // standard: запись требует вопроса, у ребёнка нет gate — отказ.
    final rig = await run(gate: FakeGate(), mode: ModeId.standard);

    final started = rig.eventsOf<SubagentStarted>().single;
    final denied = rig.logger
        .eventsOf('permission.denied')
        .where((r) => r.fields['tool_call_id'] == 'w1')
        .single;
    expect(denied.fields['session_id'], started.childSessionId.value);
    expect(denied.fields['root_session_id'], rig.session.id.value);
    expect(denied.fields['subagent_id'], started.subagentId);
    expect(denied.fields['parent_tool_call_id'], 'c1');
  });
}
