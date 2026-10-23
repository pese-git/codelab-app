import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/agent.dart';
import 'package:test/test.dart';

import 'loop_harness.dart';

void main() {
  test('a second prompt during a turn is a StateError (LOOP-10)', () async {
    final h = await LoopHarness.create(
      llm: script([
        {'waitForCancel': true},
      ]),
    );
    final agent = Agent(
      config: h.config(),
      systemPrompt: 'You are CodeLab.',
      tools: const [],
    );

    final turn = agent.prompt([user('first')]);
    await pumpEventQueue();

    await expectLater(agent.prompt([user('second')]), throwsStateError);
    expect(agent.isRunning, isTrue);
    agent.abort();
    await turn;
    expect(
      agent.messages.whereType<UserMessage>().map(
        (m) => (m.content.single as TextContent).text,
      ),
      ['first'],
    );
  });
}
