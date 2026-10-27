// Неизвестная команда и команды агента (tasks 7.5; spec codelab-cli
// «Slash-меню и клиентские команды»; design.md change `add-codelab-cli`, D7).

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

  test('an unknown command says so without a request', () async {
    repl.line('/nope');

    await repl.waitText('Unknown command /nope');
    expect(repl.sentMethods, isNot(contains(sessionPromptMethod)));
  });

  test('/agent:<name> goes to the agent as a prompt', () async {
    repl.agent.update('s1', {
      'sessionUpdate': 'available_commands_update',
      'availableCommands': [
        {'name': 'plan', 'description': 'Create a plan'},
      ],
    });
    await Future<void>.delayed(Duration.zero);

    repl.line('/agent:plan the release');

    expect(
      promptTextOf(await repl.agent.next(sessionPromptMethod)),
      '/plan the release',
    );
  });

  test('Tab completes a command in the line', () async {
    repl.type('/sess');
    repl.press(const [0x09]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repl.press(const [0x0d]);

    await repl.waitText('1. s1 (s1)');
  });

  test('Tab with several candidates lists them with the agent mark', () async {
    repl.agent.update('s1', {
      'sessionUpdate': 'available_commands_update',
      'availableCommands': [
        {'name': 'compact', 'description': 'Compact the conversation'},
      ],
    });
    await Future<void>.delayed(Duration.zero);

    repl.type('/c');
    repl.press(const [0x09]);

    await repl.waitText('/compact');
    expect(repl.lastOutput, contains('(agent)'));
    expect(repl.lastOutput, contains('/cancel'));
  });
}
