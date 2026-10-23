import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

void main() {
  test(
    'transformContext throws: AgentError(hook) and TurnEnded(failed) once',
    () async {
      final h = await LoopHarness.create(llm: script([textStep('never')]));

      await h.run(
        [user('go')],
        config: h.config(
          transformContext: (messages, cancel) async =>
              throw StateError('bad hook'),
        ),
      );

      expect(h.trace, [
        'TurnStarted',
        'MessageStarted(user)',
        'MessageEnded(user)',
        'StepStarted(0)',
        'AgentError(hook)',
        'TurnEnded(failed)',
      ]);
      expect(h.events.whereType<AgentError>().single.message, 'bad hook');
    },
  );

  test('prepareNextStep throws after the step', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('read')],
      llm: script([
        callStep([('a', 'read', const {})]),
      ]),
    );

    await h.run(
      [user('go')],
      config: h.config(
        prepareNextStep: (step) async => throw Exception('no next'),
      ),
    );

    expect(h.trace.sublist(h.trace.length - 3), [
      'StepEnded(0)',
      'AgentError(hook)',
      'TurnEnded(failed)',
    ]);
    expect(h.events.whereType<TurnEnded>(), hasLength(1));
  });

  test('prepareNextStep can replace the model of the next step', () async {
    final models = <String>[];
    final h = await LoopHarness.create(
      tools: [FakeTool('read')],
      llm: script([
        callStep([('a', 'read', const {})]),
        textStep('ok'),
      ]),
    );
    final base = h.config();

    await h.run(
      [user('go')],
      config: h.config(
        prepareNextStep: (step) async {
          models.add(step.response.model.id);
          return StepUpdate(
            model: ModelRef(
              provider: 'test',
              id: 'model-2',
              api: base.model.api,
              baseUrl: base.model.baseUrl,
              contextWindow: 32000,
              maxOutputTokens: 4096,
            ),
          );
        },
      ),
    );

    final requested = h.events.whereType<ModelRequested>().map(
      (e) => e.model.id,
    );
    expect(requested, ['model-1', 'model-2']);
  });
}
