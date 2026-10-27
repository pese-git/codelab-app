// `/profile` и `/reconnect` (tasks 7.5; spec codelab-cli «Сессии в REPL»;
// design.md change `add-codelab-cli`, D7).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../../support/fake_agent.dart';
import '../../support/repl_harness.dart';

const _other = StdioProfile(id: 'other', label: 'Other', command: 'other');

const _withLoad = AgentCapabilities(loadSession: true);

void main() {
  late ReplHarness repl;

  tearDown(() => repl.dispose());

  test('/profile prints the current profile', () async {
    repl = ReplHarness();
    await repl.start();

    repl.line('/profile');

    await repl.waitText('agent');
    expect(repl.lastOutput, contains('stdio'));
  });

  test('/profile <id> connects to that profile and opens a new '
      'session', () async {
    repl = ReplHarness(profiles: {'other': _other});
    await repl.start();
    repl.agent.restartAgent();

    repl.line('/profile other');

    await repl.agent.next(initializeMethod);
    await repl.agent.acceptNewSession('s2');
    await repl.waitText('Connected to other');
    repl.line('hi');
    final prompt = await repl.agent.next(sessionPromptMethod);
    expect((prompt.params! as Map<String, Object?>)['sessionId'], 's2');
  });

  test('/profile with an unknown id says so', () async {
    repl = ReplHarness();
    await repl.start();

    repl.line('/profile nope');

    await repl.waitText('Unknown agent profile "nope"');
  });

  test('/reconnect reloads the active session', () async {
    repl = ReplHarness(agent: FakeAgent(capabilities: _withLoad));
    await repl.start();
    repl.agent.restartAgent(capabilities: _withLoad);

    repl.line('/reconnect');

    await repl.agent.next(initializeMethod);
    final load = await repl.agent.next(sessionLoadMethod);
    expect((load.params! as Map<String, Object?>)['sessionId'], 's1');
    repl.agent.respond(load, const <String, Object?>{});
    await repl.waitText('Reconnected');
  });

  test('/reconnect to an agent without loadSession opens a new '
      'session', () async {
    repl = ReplHarness();
    await repl.start();
    repl.agent.restartAgent();

    repl.line('/reconnect');

    await repl.agent.next(initializeMethod);
    await repl.agent.acceptNewSession('s2');
    await repl.waitText('new session');
  });
}
