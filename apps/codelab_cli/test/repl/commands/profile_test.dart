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

  // Тот же текст отказа по токену, что при старте (spec codelab-cli «Отказ
  // подключения из-за токена»).
  group('a handshake rejected because of the token', () {
    test('/profile <id> says the agent rejected the token', () async {
      repl = ReplHarness(profiles: {'devbox': wsProfile()});
      await repl.start();
      repl.agent.openError = handshakeRejected(401);

      repl.line('/profile devbox');

      await repl.waitText('the agent rejected the token (HTTP 401).');
      expect(
        repl.lastOutput,
        contains(
          'codelab: cannot connect to ws://127.0.0.1:9: '
          'the agent rejected the token (HTTP 401).',
        ),
      );
      expect(repl.output, isNot(contains(fakeTokenMarker)));
      for (final leak in fakeUrlLeaks) {
        expect(repl.output, isNot(contains(leak)));
      }
    });

    test('/reconnect says the agent requires a token when none was '
        'sent', () async {
      repl = ReplHarness(profile: wsProfile(withToken: false));
      await repl.start();
      repl.agent.openError = handshakeRejected(403);

      repl.line('/reconnect');

      await repl.waitText('codelab: cannot reconnect: ');
      expect(
        repl.lastOutput,
        contains('the agent requires a token (HTTP 403).'),
      );
    });

    test('other failures keep the previous text', () async {
      repl = ReplHarness(profile: wsProfile());
      await repl.start();
      repl.agent.openError = handshakeRejected(500);

      repl.line('/reconnect');

      await repl.waitText('codelab: cannot reconnect: ');
      expect(repl.lastOutput, isNot(contains('token')));
    });
  });
}
