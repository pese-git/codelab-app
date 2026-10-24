import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import '../tools/fake_tools.dart';
import 'loop_harness.dart';

void main() {
  test(
    'transformContext and pairing repair change only the payload (LOOP-7)',
    () async {
      final history = <Message>[
        user('old question'),
        AssistantMessage(
          content: [ToolCall(id: 'lost', name: 'read', arguments: const {})],
          model: testModel,
          usage: Usage.zero,
          stopReason: StopReason.toolUse,
          timestamp: time,
        ),
      ];
      final h = await LoopHarness.create(
        tools: [FakeTool('read')],
        llm: script([textStep('ok')]),
      );

      final added = await h.run(
        [user('new question')],
        history: history,
        config: h.config(
          transformContext: (messages, cancel) async => messages.sublist(1),
        ),
      );

      final payload = h.scripted!.requests.single.messages;
      expect(payload.first, isA<AssistantMessage>());
      expect(payload[1], isA<ToolResultMessage>());
      expect((payload[1] as ToolResultMessage).isError, isTrue);
      expect(h.trace, contains('ToolPairingRepaired'));
      final repaired = h.events.whereType<ToolPairingRepaired>().single;
      expect(repaired.report.actions, ['synthesized lost']);
      expect(added.map((m) => m.runtimeType), [UserMessage, AssistantMessage]);
      expect(history, hasLength(2));
    },
  );
}
