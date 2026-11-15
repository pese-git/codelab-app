import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

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
      containsAll([
        'failure',
        'steps',
        'tool_calls',
        'tokens_in',
        'tokens_out',
        'duration_ms',
      ]),
    );
  });

  // D18, D41 п. 2: счётчики названы как в §12.3 (`llm.request.end`,
  // `turn.end`) и пишутся целыми числами. Красный до задачи 2.18: ядро пишет
  // одно поле `tokens`.
  test(
    'subagent.end: tokens_in и tokens_out — целые числа, поля tokens нет',
    () async {
      final rig = await run();

      final end = rig.logger.eventsOf('subagent.end').single;
      expect(end.fields['tokens_in'], isA<int>());
      expect(end.fields['tokens_out'], isA<int>());
      expect(end.fields.containsKey('tokens'), isFalse);
    },
  );

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
    // standard: запись требует вопроса, у корня нет gate — отказ (PERM-5).
    // Итерация 3: с gate у корня ребёнок спрашивал бы пользователя, поэтому
    // отказ без вопроса проверяется при корне без gate.
    final rig = await run(mode: ModeId.standard);

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
