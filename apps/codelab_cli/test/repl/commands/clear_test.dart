// `/clear` (tasks 7.5; spec codelab-cli «Slash-меню и клиентские команды»;
// design.md change `add-codelab-cli`, D7).

import 'package:test/test.dart';

import '../../support/repl_harness.dart';

void main() {
  test('/clear clears the screen', () async {
    final repl = ReplHarness();
    addTearDown(repl.dispose);
    await repl.start();

    repl.line('/clear');

    await repl.waitText('\x1b[2J');
  });
}
