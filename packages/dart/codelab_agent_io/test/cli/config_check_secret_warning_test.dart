import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

// Заведомо фиктивные значения в формате шаблонов §12.4.
const _skProj = 'sk-proj-AbCdEfGhIjKlMnOpQrStUvWx';
const _github = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';

/// `config check` и литеральные секреты в файле (agent-configuration
/// «Литеральные секреты в файле конфига»; design.md change
/// `add-config-literal-secrets-and-migrate`, D4, R8-4; задача 1.4): строка
/// `warning:` по шаблону, код выхода прежний, ссылка-значение не ищется в
/// хранилище.
void main() {
  late Directory root;
  late String home;
  late String cwd;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    final created = Directory.systemTemp.createTempSync('config_check_secret');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<ConfigCommandResult> check({Map<String, String> env = const {}}) =>
      ConfigCommands(platform: 'linux').check(
        CheckOptions(cwd: cwd, environment: {'CODELAB_HOME': home, ...env}),
      );

  String providers(String extra) =>
      '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
$extra
    models:
      m: {}
agent:
  default_model: p/m
''';

  String all(ConfigCommandResult r) => [...r.stdout, ...r.stderr].join('\n');

  String warningLine(ConfigCommandResult r) =>
      r.stdout.singleWhere((l) => l.contains('a secret is stored'));

  test('a literal api_key: a warning line by the template, code 0, '
      'Config: valid, no value', () async {
    write('$home/config.yaml', providers('    api_key: $_skProj'));

    final result = await check();

    expect(result.exitCode, 0, reason: all(result));
    expect(
      warningLine(result),
      matches(
        RegExp(
          '^warning: ${RegExp.escape(home)}/config\\.yaml:\\d+:\\d+: '
          r'providers\.p\.api_key: a secret is stored in the config file; '
          r'move it to the secret store: codelab secret migrate$',
        ),
      ),
    );
    expect(result.stdout.last, 'Config: valid');
    expect(all(result), isNot(contains(_skProj)));
  });

  test('a trusted project layer: the --project command; the local layer: '
      '--local', () async {
    write('$home/config.yaml', 'trusted_projects: [$cwd]\n${providers('')}');
    write('$cwd/.codelab/config.yaml', providers('    api_key: $_skProj'));
    write(
      '$cwd/.codelab/config.local.yaml',
      providers('    api_key: $_skProj'),
    );

    final result = await check();

    expect(result.exitCode, 0, reason: all(result));
    final lines = result.stdout.where((l) => l.contains('a secret is stored'));
    expect(lines.map((l) => l.split('secret store: ').last), [
      'codelab secret migrate --project',
      'codelab secret migrate --local',
    ]);
  });

  test('an untrusted project: untrusted_key, no secret warning', () async {
    write('$home/config.yaml', providers(''));
    write('$cwd/.codelab/config.yaml', providers('    api_key: $_skProj'));

    final result = await check();

    expect(result.exitCode, 0, reason: all(result));
    expect(all(result), isNot(contains('a secret is stored')));
    expect(all(result), contains('the project is not trusted'));
    expect(all(result), isNot(contains(_skProj)));
  });

  test(
    'CODELAB_CONFIG: the command is secret set with the suggested name',
    () async {
      write('$home/config.yaml', providers(''));
      final extra = '${root.path}/extra.yaml';
      write(extra, 'providers:\n  p:\n    api_key: $_skProj\n');

      final result = await check(env: {'CODELAB_CONFIG': extra});

      expect(result.exitCode, 0, reason: all(result));
      expect(
        warningLine(result),
        endsWith(
          'providers.p.api_key: a secret is stored in the config file; move it '
          'to the secret store: codelab secret set codelab/p',
        ),
      );
    },
  );

  group('a key written instead of a reference name (CFG-9 p.3)', () {
    test('api_key_secret with a token: a warning, the store is not asked '
        'for it', () async {
      // Контроль: настоящая ссылка `q` в том же конфиге ищется в хранилище.
      write('$home/config.yaml', '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: $_github
    models:
      m: {}
  q:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: codelab/q
    models:
      m: {}
agent:
  default_model: p/m
''');

      final result = await check();

      expect(result.exitCode, 0, reason: all(result));
      expect(warningLine(result), contains('providers.p.api_key_secret'));
      expect(all(result), contains('secret codelab/q is not set'));
      expect(
        all(result),
        isNot(contains('is not set; set CODELAB_SECRET_GHP')),
      );
      expect(
        result.stdout.where((l) => l.contains('GHP_') || l.contains('ghp_')),
        isEmpty,
        reason: 'the value is never printed, not even as a secret name',
      );
    });

    test(
      'api_key_env with a token: no key_missing warning, no value',
      () async {
        write('$home/config.yaml', providers('    api_key_env: $_skProj'));

        final result = await check();

        expect(result.exitCode, 0, reason: all(result));
        expect(warningLine(result), contains('providers.p.api_key_env'));
        expect(
          all(result),
          isNot(
            contains('the environment variable with the API key is not set'),
          ),
        );
        expect(all(result), isNot(contains(_skProj)));
      },
    );
  });

  test(
    'api_key together with api_key_secret: invalid, code 1, no value',
    () async {
      write(
        '$home/config.yaml',
        providers('    api_key: $_skProj\n    api_key_secret: codelab/p'),
      );

      final result = await check();

      expect(result.exitCode, 1);
      expect(
        all(result),
        contains(
          'providers.p.api_key: api_key, api_key_env and api_key_secret are '
          'mutually exclusive',
        ),
      );
      expect(all(result), isNot(contains(_skProj)));
    },
  );
}
