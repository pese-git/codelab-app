// `/new` (tasks 7.5; spec codelab-cli «Сессии в REPL»; design.md change
// `add-codelab-cli`, D7).

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

  test('/new creates a session in the same folder and prompts go '
      'there', () async {
    repl.line('/new');

    final request = await repl.agent.next(sessionNewMethod);
    expect((request.params! as Map<String, Object?>)['cwd'], '/work');
    repl.agent.respond(request, {'sessionId': 's2'});
    await repl.waitText('s2');

    repl.line('hi');
    final prompt = await repl.agent.next(sessionPromptMethod);
    expect((prompt.params! as Map<String, Object?>)['sessionId'], 's2');
  });
}
