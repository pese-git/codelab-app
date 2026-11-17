import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/fake_secret_input.dart';
import '../support/fake_secret_process_runner.dart';

// Заведомо фиктивные значения в формате шаблонов §12.4.
const _skProj = 'sk-proj-AbCdEfGhIjKlMnOpQrStUvWx';
const _github = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';

/// `provider add` и `provider list` при литеральном ключе (agent-configuration
/// «Литеральные секреты в файле конфига»; design.md change
/// `add-config-literal-secrets-and-migrate`, D4, R4-4, R8-6; задача 1.6).
///
/// Источник ключа у провайдера один: любой из `--api-key-stdin`,
/// `--api-key-secret`, `--api-key-env` удаляет литеральный `api_key` той же
/// правкой, а `provider list` показывает, что ключ лежит в файле, без значения.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late String userPath;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('provider_commands')
          .resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    userPath = '$home/config.yaml';
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, String> env() => {'CODELAB_HOME': home};

  String allOutput(ConfigCommandResult r) =>
      [...r.stdout, ...r.stderr].join('\n');

  const literal =
      '''
providers:
  gw:
    kind: openai-compatible
    base_url: https://x/v1
    api_key: $_skProj
    models:
      m: {}
agent:
  default_model: gw/m
''';

  ProviderCommands commands(MemorySecretStore store) => ProviderCommands(
    processRunner: FakeSecretProcessRunner(),
    openStore: ({required choice, required environment, required home}) =>
        store,
  );

  ProviderAddOptions addOf({
    String? apiKeySecret,
    String? apiKeyEnv,
    bool stdin = false,
  }) => ProviderAddOptions(
    id: 'gw',
    cwd: cwd,
    environment: env(),
    kind: 'openai-compatible',
    baseUrl: 'https://x/v1',
    model: 'm',
    contextWindow: '8192',
    apiKeySecret: apiKeySecret,
    apiKeyEnv: apiKeyEnv,
    apiKeyStdin: stdin,
  );

  YamlMap gw() =>
      ((loadYaml(File(userPath).readAsStringSync()) as YamlMap)['providers']
              as YamlMap)['gw']
          as YamlMap;

  group('provider add replaces a literal api_key (R4-4, R8-6)', () {
    test(
      '--api-key-secret: api_key is removed, no value in the output',
      () async {
        write(userPath, literal);

        final result = await commands(
          MemorySecretStore(),
        ).add(addOf(apiKeySecret: 'codelab/gw'), FakeSecretInput(''));

        expect(result.exitCode, 0, reason: allOutput(result));
        expect(gw()['api_key_secret'], 'codelab/gw');
        expect(gw().containsKey('api_key'), isFalse);
        expect(File(userPath).readAsStringSync(), isNot(contains(_skProj)));
        expect(allOutput(result), isNot(contains(_skProj)));
      },
    );

    test('--api-key-env: api_key is removed', () async {
      write(userPath, literal);

      final result = await commands(
        MemorySecretStore(),
      ).add(addOf(apiKeyEnv: 'GW_KEY'), FakeSecretInput(''));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(gw()['api_key_env'], 'GW_KEY');
      expect(gw().containsKey('api_key'), isFalse);
    });

    test(
      '--api-key-stdin: the key goes to the store, api_key is removed',
      () async {
        write(userPath, '$literal\nsecrets:\n  backend: file\n');
        final store = MemorySecretStore();

        final result = await commands(
          store,
        ).add(addOf(stdin: true), FakeSecretInput('sk-test-5\n'));

        expect(result.exitCode, 0, reason: allOutput(result));
        expect(gw()['api_key_secret'], 'codelab/gw');
        expect(gw().containsKey('api_key'), isFalse);
        expect(await store.read('codelab/gw'), 'sk-test-5');
        expect(allOutput(result), isNot(contains(_skProj)));
      },
    );

    test('without a key flag the literal key stays untouched', () async {
      write(userPath, literal);

      final result = await commands(
        MemorySecretStore(),
      ).add(addOf(), FakeSecretInput(''));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(gw()['api_key'], _skProj);
    });
  });

  group('provider list', () {
    Future<ConfigCommandResult> list() => commands(
      MemorySecretStore(),
    ).list(ProviderListOptions(cwd: cwd, environment: env()));

    test('key: literal in config file, without the value', () async {
      write(userPath, literal);

      final result = await list();

      expect(result.exitCode, 0, reason: allOutput(result));
      final line = result.stdout.firstWhere((l) => l.startsWith('gw'));
      expect(line, endsWith('key: literal in config file'));
      expect(allOutput(result), isNot(contains(_skProj)));
    });

    test(
      'a reference that is a secret value is named, never printed',
      () async {
        write(
          userPath,
          literal.replaceFirst('api_key: $_skProj', 'api_key_env: $_github'),
        );

        final result = await list();

        expect(result.exitCode, 0, reason: allOutput(result));
        final line = result.stdout.firstWhere((l) => l.startsWith('gw'));
        expect(
          line,
          endsWith('key: unusable reference (looks like a secret value)'),
        );
        expect(allOutput(result), isNot(contains(_github)));
      },
    );

    test(
      r'api_key: ${VAR} is an environment source, like api_key_env (R8-8)',
      () async {
        write(
          userPath,
          literal.replaceFirst('api_key: $_skProj', r'api_key: ${GW_KEY}'),
        );

        final set = await commands(MemorySecretStore()).list(
          ProviderListOptions(
            cwd: cwd,
            environment: {...env(), 'GW_KEY': 'k1'},
          ),
        );

        expect(
          set.stdout.firstWhere((l) => l.startsWith('gw')),
          endsWith('key: env GW_KEY: set'),
        );
        expect(allOutput(set), isNot(contains('k1')));
      },
    );

    test(
      r'api_key: ${secret:x} is a secret source, like api_key_secret',
      () async {
        write(
          userPath,
          literal.replaceFirst(
            'api_key: $_skProj',
            r'api_key: ${secret:codelab/gw}',
          ),
        );

        final missing = await list();
        final found = await commands(
          MemorySecretStore({'codelab/gw': 'sk-test-1'}),
        ).list(ProviderListOptions(cwd: cwd, environment: env()));

        expect(
          missing.stdout.firstWhere((l) => l.startsWith('gw')),
          endsWith('key: secret codelab/gw: not set'),
        );
        expect(
          found.stdout.firstWhere((l) => l.startsWith('gw')),
          endsWith('key: secret codelab/gw: found'),
        );
      },
    );

    test('a provider without any key stays "none"', () async {
      write(userPath, literal.replaceFirst('    api_key: $_skProj\n', ''));

      final result = await list();

      expect(
        result.stdout.firstWhere((l) => l.startsWith('gw')),
        endsWith('key: none'),
      );
    });
  });
}
