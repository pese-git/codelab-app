import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

void main() {
  test(
    'a repeated call id gets _2 already in the first MessageStarted (LOOP-11)',
    () async {
      final h = await LoopHarness.create(
        tools: [FakeTool('read')],
        llm: script([
          callStep([('call_1', 'read', const {})]),
          callStep([('call_1', 'read', const {})]),
          textStep('ok'),
        ]),
      );

      final added = await h.run([user('go')]);

      final starts = h.events
          .whereType<MessageStarted>()
          .map((e) => e.message)
          .whereType<AssistantMessage>()
          .toList();
      expect(starts[1].toolCalls.single.id, 'call_1_2');
      expect(
        [for (final m in added.whereType<ToolResultMessage>()) m.toolCallId],
        ['call_1', 'call_1_2'],
      );
      expect(h.events.whereType<ToolCallStarted>().map((e) => e.toolCallId), [
        'call_1',
        'call_1_2',
      ]);
    },
  );
}
