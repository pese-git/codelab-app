import 'package:codelab_agent_core/src/loop/agent.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

void main() {
  test('the loop waits for every emit (LOOP-2)', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('read')],
      llm: script([
        callStep([('a', 'read', const {}), ('b', 'read', const {})]),
        textStep('ok'),
      ]),
    );
    final agent = Agent(
      config: h.config(),
      systemPrompt: 'You are CodeLab.',
      tools: h.tools,
    );
    final log = <String>[];
    var inside = false;
    agent.subscribe((e) async {
      expect(inside, isFalse, reason: 'events overlap at ${describe(e)}');
      inside = true;
      log.add('begin ${describe(e)}');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      log.add('end ${describe(e)}');
      inside = false;
    });

    await agent.prompt([user('go')]);

    for (var i = 0; i < log.length; i += 2) {
      expect(log[i], startsWith('begin '));
      expect(log[i + 1], 'end ${log[i].substring(6)}');
    }
    expect(log.last, 'end TurnEnded(completed)');
  });
}
