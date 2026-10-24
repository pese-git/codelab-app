import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/loop_config.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

String _lastUserText(LlmContext request) =>
    ((request.messages.last as UserMessage).content.single as TextContent).text;

void main() {
  // Финальный гейт ответа (LOOP-13): в MVP только интерфейс, без хука —
  // Accept.
  test('without a hook the answer is accepted', () async {
    final h = await LoopHarness.create(llm: script([textStep('Done.')]));

    await h.run([user('go')]);

    expect(h.trace.last, 'TurnEnded(completed)');
    expect(h.events.whereType<StepStarted>(), hasLength(1));
  });

  test('Revise adds a step with the note in the payload only', () async {
    final turns = <TurnInfo>[];
    final h = await LoopHarness.create(
      llm: script([textStep('draft'), textStep('final')]),
    );
    var calls = 0;

    final added = await h.run(
      [user('go')],
      config: h.config(
        beforeFinalResponse: (message, turn) async {
          turns.add(turn);
          return calls++ == 0 ? const Revise('Add tests.') : const Accept();
        },
      ),
    );

    expect(h.events.whereType<StepStarted>(), hasLength(2));
    expect(_lastUserText(h.scripted!.requests[1]), 'Add tests.');
    // Заметка не входит в транскрипт.
    expect(added.whereType<UserMessage>(), hasLength(1));
    expect(turns.map((t) => (t.stepIndex, t.revisions)), [(0, 0), (1, 1)]);
    expect(turns.last.turnMessages.last, added.last);
    expect(turns.first.turnId, const TurnId('turn-1'));
    expect(h.trace.last, 'TurnEnded(completed)');
  });

  test('Revise stops at maxResponseRevisions', () async {
    final h = await LoopHarness.create(
      llm: script([textStep('a'), textStep('b'), textStep('c')]),
    );
    var calls = 0;

    await h.run(
      [user('go')],
      config: h.config(
        maxResponseRevisions: 2,
        beforeFinalResponse: (message, turn) async {
          calls++;
          return const Revise('again');
        },
      ),
    );

    expect(h.events.whereType<StepStarted>(), hasLength(3));
    expect(calls, 3);
    expect(h.trace.last, 'TurnEnded(completed)');
  });

  test('Hold marks TurnEnded.held', () async {
    final h = await LoopHarness.create(llm: script([textStep('risky')]));

    await h.run(
      [user('go')],
      config: h.config(
        beforeFinalResponse: (message, turn) async =>
            const Hold('needs review'),
      ),
    );

    final ended = h.events.whereType<TurnEnded>().single;
    expect(ended.held, 'needs review');
    expect(ended.reason, TurnEndReason.completed);
  });

  test('the hook is not called for a step with tool calls', () async {
    var calls = 0;
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([
        callStep([('c1', 'probe', const {})]),
        textStep('Done.'),
      ]),
    );

    await h.run(
      [user('go')],
      config: h.config(
        beforeFinalResponse: (message, turn) async {
          calls++;
          return const Accept();
        },
      ),
    );

    expect(calls, 1);
  });
}
