// Токен WebSocket-профиля CLI через общий источник kit (tasks 2.7 change
// `add-app-settings-shell`; spec codelab-cli «Профили подключения CLI»,
// «Токен из произвольной переменной», «Старые профили читаются как раньше»;
// design.md, D15).

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:test/test.dart';

import '../support/fake_cli_io.dart';
import '../support/memory_profile_store.dart';

const _secret = 'super-secret-value';

void main() {
  late Directory tmp;
  late Map<String, String> environment;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_profile_token_');
    environment = {'CODELAB_HOME': '${tmp.path}/home'};
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(int, FakeCliIo)> run(List<String> args) async {
    final io = FakeCliIo();
    final code = await runCodelab(args, environment: environment, io: io);
    return (code, io);
  }

  void writeProfiles(String records) {
    final file = File('${tmp.path}/home/profiles.json')
      ..createSync(recursive: true);
    file.writeAsStringSync('{"version": 1, "profiles": [$records]}');
  }

  group('ProfileSecretSource for CLI profiles', () {
    test('env:DEVBOX_TOKEN of a profile made in codelab-app is read from '
        'the process environment', () async {
      final store = MemoryProfileStore([
        ConnectionProfile.webSocket(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('wss://devbox.test/acp'),
          tokenRef: 'env:DEVBOX_TOKEN',
        ),
      ]);
      final profile =
          await resolveAgentProfile('devbox', store: store) as WebSocketProfile;
      final secrets = ProfileSecretSource({
        'DEVBOX_TOKEN': _secret,
        'CODELAB_AGENT_TOKEN': 'other',
      });

      expect(await secrets.read(profile.tokenRef!), _secret);
    });

    test('-a ws://… keeps reading CODELAB_AGENT_TOKEN', () async {
      final profile =
          await resolveAgentProfile(
                'wss://agent.test/acp',
                store: MemoryProfileStore(),
              )
              as WebSocketProfile;
      final secrets = ProfileSecretSource({'CODELAB_AGENT_TOKEN': _secret});

      expect(profile.tokenRef, 'env:CODELAB_AGENT_TOKEN');
      expect(await secrets.read(profile.tokenRef!), _secret);
    });

    test('the old profile Old with capital letters is selected by -a and '
        'gets the token of CODELAB_AGENT_TOKEN', () async {
      writeProfiles(
        '{"type": "webSocket", "id": "Old", "label": "Old", '
        '"uri": "wss://agent.test/acp", "tokenRef": '
        '"env:CODELAB_AGENT_TOKEN"}',
      );
      final store = JsonFileProfileStore('${tmp.path}/home/profiles.json');

      final profile =
          await resolveAgentProfile('Old', store: store) as WebSocketProfile;

      expect(
        await ProfileSecretSource({
          'CODELAB_AGENT_TOKEN': _secret,
        }).read(profile.tokenRef!),
        _secret,
      );
    });
  });

  group('the value of the token is never printed', () {
    test('profiles show prints the variable name only', () async {
      writeProfiles(
        '{"type": "webSocket", "id": "devbox", "label": "Devbox", '
        '"uri": "wss://devbox.test/acp", "tokenRef": "env:DEVBOX_TOKEN"}',
      );
      environment['DEVBOX_TOKEN'] = _secret;

      final (code, io) = await run(['profiles', 'show', 'devbox']);

      expect(code, 0);
      expect(io.stdoutText, contains(r'token: $DEVBOX_TOKEN'));
      expect(io.stdoutText + io.stderrText, isNot(contains(_secret)));
    });
  });
}
