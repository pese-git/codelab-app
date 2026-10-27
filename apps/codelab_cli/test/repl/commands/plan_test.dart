// `/plan` (tasks 7.5; spec codelab-cli «Slash-меню и клиентские команды»;
// design.md change `add-codelab-cli`, D7).

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

  test('/plan without a plan says so', () async {
    repl.line('/plan');

    await repl.waitText('No plan yet.');
  });

  test('/plan prints the current plan again', () async {
    repl.line('go');
    final prompt = await repl.agent.next(sessionPromptMethod);
    repl.agent
      ..update('s1', {
        'sessionUpdate': 'plan',
        'entries': [
          {'content': 'Read', 'status': 'completed', 'priority': 'high'},
          {'content': 'Edit', 'status': 'pending', 'priority': 'low'},
        ],
      })
      ..respond(prompt, {'stopReason': 'end_turn'});
    await repl.waitText('[ ] Edit');

    repl.line('/plan');

    await repl.waitText('[x] Read');
    expect(repl.lastOutput, contains('[ ] Edit'));
  });
}
