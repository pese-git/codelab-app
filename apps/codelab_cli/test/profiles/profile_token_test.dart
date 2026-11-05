// Токен WebSocket-профиля CLI через общий источник kit (tasks 2.7 change
// `add-app-settings-shell`; spec codelab-cli «Профили подключения CLI»,
// «Токен из произвольной переменной», «Старые профили читаются как раньше»;
// design.md, D15).

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

import '../support/fake_cli_io.dart';
import '../support/memory_profile_store.dart';

const _secret = 'super-secret-value';

/// Логгер-заглушка для `ClientSecretAccess.open`.
final class _SilentLogger implements Logger {
  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

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
      expect(io.stdoutText, contains('token: env DEVBOX_TOKEN'));
      expect(io.stdoutText + io.stderrText, isNot(contains(_secret)));
    });
  });

  // Токен из хранилища секретов (task 1.8 change `add-provider-setup-ui`;
  // spec codelab-cli «Токен из хранилища секретов»; design.md, D13, D4).
  group('secret: token references (add-provider-setup-ui)', () {
    const leak = 'sk-test-leak-0123456789';
    const name = 'codelab/profiles/devbox/token';

    void writeDevbox(String tokenRef) => writeProfiles(
      '{"type": "webSocket", "id": "devbox", "label": "Devbox", '
      '"uri": "wss://devbox.test/acp", "tokenRef": "$tokenRef"}',
    );

    void useFileBackend() {
      File('${tmp.path}/home/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('secrets:\n  backend: file\n');
    }

    // Секрет кладёт тот же мост, что и app: `codelab secret set` читает
    // настоящий stdin процесса и в модульном тесте повис бы.
    Future<void> storeSecret(String value) async {
      final access = await ClientSecretAccess.open(
        codelabHome: '${tmp.path}/home',
        environment: environment,
        logger: _SilentLogger(),
      );
      expect(await access.admin.store(name, value), isA<SecretStored>());
    }

    test('show prints the secret name and (set) from the file backend, '
        'never the value', () async {
      useFileBackend();
      writeDevbox('secret:$name');
      await storeSecret(leak);

      final (code, io) = await run(['profiles', 'show', 'devbox']);

      expect(code, 0, reason: io.stderrText);
      expect(io.stdoutText, contains('token: secret $name (set)'));
      expect(io.stdoutText + io.stderrText, isNot(contains(leak)));
    });

    test('show prints (missing) when the secret is not stored', () async {
      useFileBackend();
      writeDevbox('secret:$name');

      final (code, io) = await run(['profiles', 'show', 'devbox']);

      expect(code, 0, reason: io.stderrText);
      expect(io.stdoutText, contains('token: secret $name (missing)'));
    });

    test('the CODELAB_SECRET_<NAME> override counts as set', () async {
      useFileBackend();
      writeDevbox('secret:$name');
      environment['CODELAB_SECRET_CODELAB_PROFILES_DEVBOX_TOKEN'] = leak;

      final (_, io) = await run(['profiles', 'show', 'devbox']);

      expect(io.stdoutText, contains('token: secret $name (set)'));
      expect(io.stdoutText + io.stderrText, isNot(contains(leak)));
    });

    test('a broken user config does not fail show: the reference is '
        'missing, no value printed', () async {
      File('${tmp.path}/home/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('secrets: [unclosed');
      writeDevbox('secret:$name');

      final (code, io) = await run(['profiles', 'show', 'devbox']);

      expect(code, 0, reason: io.stderrText);
      expect(io.stdoutText, contains('token: secret $name (missing)'));
    });

    test(
      'secret: with an invalid name is unrecognized and not printed',
      () async {
        writeDevbox('secret:Bad Name $leak');

        final (_, io) = await run(['profiles', 'show', 'devbox']);

        expect(
          io.stdoutText,
          contains(
            'token: unrecognized token reference (not supported in this version)',
          ),
        );
        expect(io.stdoutText + io.stderrText, isNot(contains(leak)));
      },
    );

    test('the profile list and show do not touch the secret store when the '
        'profile has no secret reference', () async {
      writeDevbox('env:DEVBOX_TOKEN');

      final (_, io) = await run(['profiles', 'show', 'devbox']);

      expect(io.stdoutText, contains('token: env DEVBOX_TOKEN'));
      expect(File('${tmp.path}/home/secrets.yaml').existsSync(), isFalse);
    });
  });

  // Предупреждение D13 (ревью итерации 1): секрет `secret:` без значения —
  // подключение без токена, и пользователь должен узнать причину.
  group('missing token secret warning (add-provider-setup-ui, D13)', () {
    const warning =
        'codelab: profile devbox has no stored secret value; connecting '
        'without a token.';

    void writeDevbox(String ref) => writeProfiles(
      '{"type": "webSocket", "id": "devbox", "label": "Devbox", '
      '"uri": "ws://127.0.0.1:1/acp", "tokenRef": "$ref"}',
    );

    Future<FakeCliIo> headless() async {
      final io = FakeCliIo();
      await runCodelab(
        ['-a', 'devbox', '--cwd', tmp.path, '-p', 'hi'],
        environment: environment,
        io: io,
      );
      return io;
    }

    test(
      'headless warns once on stderr, without the secret name or value',
      () async {
        File('${tmp.path}/home/config.yaml')
          ..createSync(recursive: true)
          ..writeAsStringSync('secrets:\n  backend: file\n');
        writeDevbox('secret:codelab/profiles/devbox/token');

        final io = await headless();

        expect(io.stderrText, contains(warning));
        expect(
          RegExp(RegExp.escape(warning)).allMatches(io.stderrText).length,
          1,
        );
        expect(io.stderrText, isNot(contains('codelab/profiles/devbox/token')));
      },
    );

    test('no warning when the secret has a value', () async {
      File('${tmp.path}/home/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('secrets:\n  backend: file\n');
      writeDevbox('secret:codelab/profiles/devbox/token');
      environment['CODELAB_SECRET_CODELAB_PROFILES_DEVBOX_TOKEN'] = _secret;

      final io = await headless();

      expect(io.stderrText, isNot(contains(warning)));
      expect(io.stderrText + io.stdoutText, isNot(contains(_secret)));
    });

    test('test-scenario warns the same way before playing fixtures', () async {
      File('${tmp.path}/home/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('secrets:\n  backend: file\n');
      writeDevbox('secret:codelab/profiles/devbox/token');
      final io = FakeCliIo();
      final fixtures = Directory('${tmp.path}/fixtures')..createSync();

      await runCodelab(
        ['test-scenario', fixtures.path, '-a', 'devbox'],
        environment: environment,
        io: io,
      );

      expect(io.stderrText, contains(warning));
    });

    test('--verbose also logs connection_profile.token_secret_missing with '
        'the profile_id field only', () async {
      File('${tmp.path}/home/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('secrets:\n  backend: file\n');
      writeDevbox('secret:codelab/profiles/devbox/token');
      final io = FakeCliIo();

      await runCodelab(
        ['-a', 'devbox', '--cwd', tmp.path, '-p', 'hi', '--verbose'],
        environment: environment,
        io: io,
      );

      final event = io.stderrText
          .split('\n')
          .where((l) => l.contains('connection_profile.token_secret_missing'));
      expect(event, hasLength(1));
      expect(
        event.single,
        '[warning] connection_profile.token_secret_missing '
        'profile_id=devbox',
      );
    });

    test('without --verbose there is no event line', () async {
      File('${tmp.path}/home/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('secrets:\n  backend: file\n');
      writeDevbox('secret:codelab/profiles/devbox/token');

      final io = await headless();

      expect(io.stderrText, isNot(contains('connection_profile.')));
    });

    test('no warning for env: references', () async {
      writeDevbox('env:DEVBOX_TOKEN');

      final io = await headless();

      expect(io.stderrText, isNot(contains('token secret')));
    });
  });
}
