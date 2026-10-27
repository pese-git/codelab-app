// `/exit` и `/quit` (tasks 7.5; spec codelab-cli «Slash-меню и клиентские
// команды»; design.md change `add-codelab-cli`, D7).

import 'package:test/test.dart';

import '../../support/repl_harness.dart';

void main() {
  for (final command in ['/exit', '/quit']) {
    test('$command exits with 0', () async {
      final repl = ReplHarness();
      addTearDown(repl.dispose);
      await repl.start();

      repl.line(command);

      expect(await repl.exitCode, 0);
      expect(repl.terminal.rawEnabled, isFalse);
    });
  }
}
