import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

/// `StepUpdate.tools` и `StepUpdate.systemPrompt` (design.md change
/// `add-agent-mcp-client`, D6): набор инструментов и промпт меняются на
/// границе шага, транскрипт цикла остаётся.
void main() {
  test(
    'the next request gets the new tools and prompt, the transcript stays',
    () async {
      final read = FakeTool('read');
      final extra = FakeTool('mcp__fake__lookup');
      final h = await LoopHarness.create(
        tools: [read, extra],
        llm: script([
          {
            ...callStep([('a', 'read', const {})]),
            'expect': {
              'tools': ['read', 'mcp__fake__lookup'],
            },
          },
          {
            ...textStep('done'),
            'expect': {
              'tools': ['read'],
              'systemPrompt': {r'$textContains': 'NEW PROMPT'},
              'lastMessage': {'role': 'toolResult'},
            },
          },
        ]),
      );

      await h.run(
        [user('go')],
        config: h.config(
          prepareNextStep: (step) async =>
              StepUpdate(tools: [read], systemPrompt: 'NEW PROMPT'),
        ),
      );

      expect(h.trace.last, 'TurnEnded(completed)');
      expect(h.events.whereType<AgentError>(), isEmpty);
    },
  );
}
