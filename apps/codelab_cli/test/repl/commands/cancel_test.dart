// `/cancel` (tasks 7.5; spec codelab-cli «Slash-меню и клиентские команды»;
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

  test('/cancel during a turn sends session/cancel', () async {
    repl.line('slow');
    final prompt = await repl.agent.next(sessionPromptMethod);

    repl.line('/cancel');

    await repl.agent.nextNotification(sessionCancelMethod);
    repl.agent.respond(prompt, {'stopReason': 'cancelled'});
    await repl.waitText('cancelled');
  });

  test('/cancel without a turn says so', () async {
    repl.line('/cancel');

    await repl.waitText('Nothing to cancel.');
  });
}
