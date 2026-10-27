// Значение `--agent` (tasks 2.3; spec codelab-cli «Профили подключения
// CLI»; design.md change `add-codelab-cli`, D4).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/memory_profile_store.dart';

void main() {
  final store = MemoryProfileStore([
    const StdioProfile(
      id: 'default',
      label: 'Default',
      command: 'codelab-agent',
      args: ['serve', '--stdio'],
    ),
    const StdioProfile(id: 'py', label: 'Python', command: 'codelab'),
  ]);

  test('stdio: is split like a shell command', () async {
    final profile = await resolveAgentProfile(
      'stdio:python -m "codelab agent" --stdio',
      store: store,
    );

    expect(
      profile,
      isA<StdioProfile>()
          .having((p) => p.command, 'command', 'python')
          .having((p) => p.args, 'args', ['-m', 'codelab agent', '--stdio'])
          .having((p) => p.runInProjectDirectory, 'cwd', isTrue),
    );
  });

  test('stdio: without a command or with a broken quote is a usage '
      'error', () async {
    for (final value in ['stdio:', 'stdio:   ', 'stdio:run "oops']) {
      await expectLater(
        resolveAgentProfile(value, store: store),
        throwsA(isA<UsageError>()),
        reason: value,
      );
    }
  });

  test('ws:// and wss:// read the token from CODELAB_AGENT_TOKEN', () async {
    for (final value in ['ws://127.0.0.1:8765', 'wss://agent.test/acp']) {
      final profile = await resolveAgentProfile(value, store: store);

      expect(
        profile,
        isA<WebSocketProfile>()
            .having((p) => p.uri, 'uri', Uri.parse(value))
            .having((p) => p.tokenRef, 'tokenRef', 'env:CODELAB_AGENT_TOKEN'),
      );
    }
  });

  test('embedded is not available before stage 7', () async {
    await expectLater(
      resolveAgentProfile('embedded', store: store),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          'Embedded agent is not available in this build.',
        ),
      ),
    );
  });

  test('a profile id is looked up in the store', () async {
    expect(
      await resolveAgentProfile('py', store: store),
      isA<StdioProfile>().having((p) => p.command, 'command', 'codelab'),
    );
  });

  test('an unknown profile id is a usage error', () async {
    await expectLater(
      resolveAgentProfile('nope', store: store),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          contains('Unknown agent profile "nope"'),
        ),
      ),
    );
  });

  test('without --agent the profile is "default"', () async {
    expect(
      await resolveAgentProfile(null, store: store),
      isA<StdioProfile>().having((p) => p.command, 'command', 'codelab-agent'),
    );
  });

  test('without --agent and without "default" the hint names the '
      'command', () async {
    await expectLater(
      resolveAgentProfile(null, store: MemoryProfileStore()),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          'No default agent profile. Pass --agent or run '
              '"codelab profiles add default stdio:<command>".',
        ),
      ),
    );
  });

  test('a broken profiles file is a usage error', () async {
    await expectLater(
      resolveAgentProfile('py', store: MemoryProfileStore.broken()),
      throwsA(isA<UsageError>()),
    );
  });

  group('EnvSecretSource', () {
    test('reads env: references and nothing else', () async {
      const secrets = EnvSecretSource({'CODELAB_AGENT_TOKEN': 'tok'});

      expect(await secrets.read('env:CODELAB_AGENT_TOKEN'), 'tok');
      expect(await secrets.read('env:MISSING'), isNull);
      expect(await secrets.read('keychain:x'), isNull);
    });

    test('an empty variable is no token', () async {
      const secrets = EnvSecretSource({'CODELAB_AGENT_TOKEN': ''});

      expect(await secrets.read('env:CODELAB_AGENT_TOKEN'), isNull);
    });
  });
}
