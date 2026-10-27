// `/thoughts dim|collapsed|hidden` (tasks 7.5; spec codelab-cli «Рендер хода
// в REPL»; U-08; design.md change `add-codelab-cli`, D6).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:test/test.dart';

import '../../support/repl_harness.dart';

void main() {
  late ReplHarness repl;

  setUp(() async {
    repl = ReplHarness();
    await repl.start();
  });
  tearDown(() => repl.dispose());

  test('/thoughts hidden hides the next thoughts', () async {
    repl.line('/thoughts hidden');
    await repl.waitText('hidden');

    repl.line('go');
    final prompt = await repl.agent.next(sessionPromptMethod);
    repl.agent
      ..update('s1', {
        'sessionUpdate': 'agent_thought_chunk',
        'content': {'type': 'text', 'text': 'secret thinking'},
      })
      ..chunk('s1', 'answer')
      ..respond(prompt, {'stopReason': 'end_turn'});
    await repl.waitText('answer');

    expect(repl.output, isNot(contains('secret thinking')));
  });

  test('/thoughts with a wrong mode prints the usage', () async {
    repl.line('/thoughts loud');

    await repl.waitText('/thoughts dim|collapsed|hidden');
  });
}
