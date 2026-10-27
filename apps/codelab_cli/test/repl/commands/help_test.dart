// `/help` и `/help keys` (tasks 7.5; spec codelab-cli «Slash-меню и
// клиентские команды»; §12.2.11, TUI-7; design.md change `add-codelab-cli`,
// D7).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../../support/repl_harness.dart';

void main() {
  late ReplHarness repl;

  setUp(() async {
    repl = ReplHarness();
    await repl.start();
  });
  tearDown(() => repl.dispose());

  test('/help lists the client commands with usage', () async {
    repl.line('/help');

    await repl.waitText('/help keys');
    for (final command in [
      '/exit',
      '/new',
      '/sessions',
      '/resume',
      '/mode',
      '/model',
      '/config',
      '/cancel',
      '/queue',
      '/profile',
      '/reconnect',
      '/plan',
      '/clear',
      '/thoughts',
    ]) {
      expect(repl.lastOutput, contains(command), reason: command);
    }
    expect(repl.sentMethods, isNot(contains('session/prompt')));
  });

  test('/help lists the agent commands', () async {
    repl.agent.update('s1', {
      'sessionUpdate': 'available_commands_update',
      'availableCommands': [
        {'name': 'compact', 'description': 'Compact the conversation'},
      ],
    });
    await Future<void>.delayed(Duration.zero);

    repl.line('/help');

    await repl.waitText('/compact');
    expect(repl.lastOutput, contains('Compact the conversation'));
  });

  test('/help keys is the key table', () async {
    repl.line('/help keys');

    await repl.waitText('Ctrl+C');
    for (final line in KeyBindings.mvp.helpLines()) {
      expect(repl.lastOutput, contains(line));
    }
  });
}
