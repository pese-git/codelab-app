// `codelab provider add` с клиентскими флагами `--preset`, `--yes`,
// `--skip-check` и выбор режима (задачи 4.0, 4.1 change
// `add-provider-setup-ui`; spec codelab-cli «Подкоманды codelab provider и
// codelab mcp»; design.md D15, решения Q13).
//
// Тесты идут через `runCodelab` в процессе: временные `CODELAB_HOME` и
// `HOME`, файловое хранилище секретов, фиктивный сервер `/models` на петле
// (`test/support/fake_models_server.dart`). Настоящие `~/.codelab` и
// keychain не читаются. Строки ошибок и коды — дословно из таблицы D15.
// Ввод ключа из stdin и терминальные режимы проверяет PTY-e2e
// `test/e2e/provider_setup_test.dart`.

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_setup/io.dart'
    show ProviderAddOptions, ProviderCommands, SecretInput;
import 'package:test/test.dart';

import '../support/fake_cli_io.dart';
import '../support/fake_models_server.dart';
import '../support/setup_fakes.dart' show leakMarker;

const _initialConfig = 'secrets:\n  backend: file\n';

void main() {
  late Directory temp;
  late String home;
  late String project;
  late Map<String, String> env;
  late FakeModelsServer server;

  setUp(() async {
    // Канонический путь: на macOS `/var` — ссылка на `/private/var`.
    temp = Directory(
      Directory.systemTemp
          .createTempSync('codelab_cli_provider_flags_')
          .resolveSymbolicLinksSync(),
    );
    home = '${temp.path}/home';
    project = '${temp.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    File('$home/config.yaml').writeAsStringSync(_initialConfig);
    env = {'CODELAB_HOME': home, 'HOME': '${temp.path}/no-home'};
    server = await FakeModelsServer.start();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<(int, FakeCliIo)> run(List<String> args, {FakeCliIo? io}) async {
    final out = io ?? FakeCliIo();
    final code = await runCodelab(
      ['-C', project, ...args],
      environment: env,
      io: out,
    );
    return (code, out);
  }

  String config() => File('$home/config.yaml').readAsStringSync();

  /// Полный набор клиентских флагов для Custom OpenAI-compatible.
  List<String> fullFlags({String? baseUrl}) => [
    'provider',
    'add',
    'gw',
    '--preset',
    'custom-openai',
    '--base-url',
    baseUrl ?? server.baseUrl,
    '--model',
    'm1',
    '--context-window',
    '8000',
  ];

  group('ошибки использования: код 64, stdout пуст, справка provider '
      '(таблица D15)', () {
    final table =
        <
          ({
            String name,
            List<String> Function(FakeModelsServer) args,
            String line,
          })
        >[
          (
            name: 'неизвестный --preset',
            args: (s) => [
              'provider',
              'add',
              'gw',
              '--preset',
              'nope-$leakMarker',
              '--yes',
            ],
            line:
                'codelab: unknown --preset; use openai, anthropic, '
                'openrouter, ollama, custom-openai or custom-anthropic',
          ),
          (
            name: '--kind не совпадает с видом --preset',
            args: (s) => [
              'provider',
              'add',
              'gw',
              '--preset',
              'anthropic',
              '--kind',
              'openai-compatible',
              '--yes',
            ],
            line: 'codelab: --kind does not match --preset',
          ),
          (
            name: '--kind gemini с клиентским флагом',
            args: (s) => [
              'provider',
              'add',
              'gw',
              '--kind',
              'gemini',
              '--base-url',
              s.baseUrl,
              '--model',
              'm1',
              '--context-window',
              '8000',
              '--yes',
            ],
            line:
                'codelab: --kind gemini is not supported with --preset, '
                '--yes or --skip-check; use the core flags only',
          ),
          (
            name: '--api-key-secret с клиентским флагом',
            args: (s) => [
              'provider',
              'add',
              'gw',
              '--preset',
              'custom-openai',
              '--api-key-secret',
              leakMarker,
              '--yes',
            ],
            line:
                'codelab: --api-key-secret is not supported with --preset, '
                '--yes or --skip-check; use --api-key-stdin or '
                '--api-key-env',
          ),
          (
            name: '--project с клиентским флагом',
            args: (s) => [
              'provider',
              'add',
              'gw',
              '--preset',
              'custom-openai',
              '--project',
              '--yes',
            ],
            line:
                'codelab: --project is not supported with --preset, --yes '
                'or --skip-check; use --local or the user config',
          ),
          (
            name: 'ни --preset, ни --kind',
            args: (s) => ['provider', 'add', 'gw', '--yes'],
            line: 'codelab: missing required options: --preset',
          ),
          (
            name: 'custom-* без --base-url',
            args: (s) => [
              'provider',
              'add',
              'gw',
              '--preset',
              'custom-openai',
              '--model',
              'm1',
              '--context-window',
              '8000',
              '--yes',
            ],
            line: 'codelab: missing required options: --base-url',
          ),
          (
            name: 'http:// к нелокальному хосту с --yes: запроса нет',
            args: (s) => [
              ...fullFlags(baseUrl: 'http://gw.example:8080/v1'),
              '--yes',
            ],
            line:
                'codelab: --base-url sends the key unencrypted to '
                'gw.example; use https, or run "codelab provider add" on a '
                'terminal to confirm',
          ),
          (
            name: 'http:// к нелокальному хосту без --yes',
            args: (s) => fullFlags(baseUrl: 'http://gw.example:8080/v1'),
            line:
                'codelab: --base-url sends the key unencrypted to '
                'gw.example; use https, or run "codelab provider add" on a '
                'terminal to confirm',
          ),
          (
            name: 'адрес не http/https',
            args: (s) => [
              ...fullFlags(baseUrl: 'ftp://$leakMarker.example/v1'),
              '--yes',
            ],
            line: 'codelab: --base-url: Enter an http or https address.',
          ),
          (
            name: 'userinfo в адресе',
            args: (s) => [
              ...fullFlags(baseUrl: 'http://bob:s3cr3tpw@127.0.0.1:1/v1'),
              '--yes',
            ],
            line:
                'codelab: --base-url: Remove the user name and password '
                'from the address.',
          ),
          (
            name: '«Review» без --yes и без терминала',
            args: (s) => fullFlags(),
            line: 'codelab: provider add needs --yes without a terminal',
          ),
        ];

    for (final row in table) {
      test(row.name, () async {
        final (code, io) = await run(row.args(server));

        expect(code, 64);
        expect(io.stdoutText, isEmpty);
        expect(io.stderrText, '${row.line}\n\n${providerUsage()}\n');
        // Присланные значения не цитируются (CFG-10).
        expect(io.stderrText, isNot(contains(leakMarker)));
        expect(io.stderrText, isNot(contains('s3cr3tpw')));
        expect(config(), _initialConfig, reason: 'файл не изменён');
      });
    }

    test('http:// к нелокальному хосту: запроса к /models нет', () async {
      final (code, _) = await run([
        ...fullFlags(baseUrl: 'http://gw.example:8080/v1'),
        '--yes',
      ]);

      // Проверка бы дала код 1 (`gw.example` не резолвится).
      expect(code, 64);
      expect(server.requests, isEmpty);
    });
  });

  group('проверка /models идёт до записи (SETUP-4)', () {
    test('закрытый порт без --skip-check: код 1, файл не изменён', () async {
      final port = await closedPort();

      final (code, io) = await run([
        ...fullFlags(baseUrl: 'http://127.0.0.1:$port/v1'),
        '--yes',
      ]);

      expect(code, 1);
      expect(io.stdoutText, isEmpty);
      expect(
        io.stderrText,
        startsWith(
          'codelab: provider check failed: unreachable '
          '(http://127.0.0.1:$port)\n',
        ),
      );
      expect(config(), _initialConfig);
    });

    test('отказ ключа 401: код 1, и --skip-check его не пропускает', () async {
      server.status = 401;

      for (final extra in [
        <String>[],
        ['--skip-check'],
      ]) {
        final (code, io) = await run([...fullFlags(), '--yes', ...extra]);

        expect(code, 1, reason: '$extra');
        expect(
          io.stderrText,
          startsWith(
            'codelab: provider check failed: unauthorized '
            '(${server.origin})\n',
          ),
        );
        expect(config(), _initialConfig);
      }
    });

    test('404 (notFound): код 1, --skip-check не пропускает', () async {
      server.status = 404;

      final (code, io) = await run([...fullFlags(), '--yes', '--skip-check']);

      expect(code, 1);
      expect(
        io.stderrText,
        startsWith(
          'codelab: provider check failed: notFound (${server.origin})\n',
        ),
      );
      expect(config(), _initialConfig);
    });

    test('--skip-check пропускает только unreachable: запись идёт', () async {
      final port = await closedPort();

      final (code, io) = await run([
        ...fullFlags(baseUrl: 'http://127.0.0.1:$port/v1'),
        '--yes',
        '--skip-check',
      ]);

      expect(code, 0, reason: io.stderrText);
      expect(
        io.stdoutText,
        'Saved provider "gw". Models are available in /model.\n',
      );
      expect(config(), contains('gw:'));
      expect(config(), contains('base_url: http://127.0.0.1:$port/v1'));
    });
  });

  group('успех: события из флагов, запись как у ядра', () {
    test('--yes: проверка до записи, адрес 127.0.0.1 без подтверждения '
        '(задача 4.0)', () async {
      final (code, io) = await run([...fullFlags(), '--yes']);

      expect(code, 0, reason: io.stderrText);
      expect(
        io.stdoutText,
        'Saved provider "gw". Models are available in /model.\n',
      );
      expect(io.stderrText, isEmpty);
      expect(server.requests.map((r) => r.path), ['/v1/models']);
      expect(server.requests.single.authorization, isNull);
      final written = config();
      expect(written, contains('secrets:\n  backend: file'));
      expect(written, contains('kind: openai-compatible'));
      expect(written, contains('base_url: ${server.baseUrl}'));
      expect(written, contains('context_window: 8000'));
    });

    test('--api-key-env и --default', () async {
      final (code, io) = await run([
        ...fullFlags(),
        '--api-key-env',
        'GW_KEY',
        '--default',
        '--yes',
      ]);

      expect(code, 0, reason: io.stderrText);
      expect(config(), contains('api_key_env: GW_KEY'));
      expect(config(), contains('default_model: gw/m1'));
    });

    test('--local пишет слой projectLocal, пользовательский файл не '
        'меняется', () async {
      // Слой projectLocal пишется только в доверенном проекте.
      final trusted =
          '$_initialConfig'
          'trusted_projects:\n  - $project\n';
      File('$home/config.yaml').writeAsStringSync(trusted);

      final (code, io) = await run([...fullFlags(), '--local', '--yes']);

      expect(code, 0, reason: io.stderrText);
      expect(config(), trusted);
      expect(
        File('$project/.codelab/config.local.yaml').readAsStringSync(),
        contains('gw:'),
      );
    });

    test(
      'модель не из списка ответа — ручной ввод с --context-window',
      () async {
        final (code, io) = await run([
          ...fullFlags().map((a) => a == 'm1' ? 'other-model' : a),
          '--yes',
        ]);

        expect(code, 0, reason: io.stderrText);
        expect(config(), contains('other-model'));
      },
    );

    test('без --preset: --kind openai-compatible → custom-openai', () async {
      final (code, io) = await run([
        'provider',
        'add',
        'gw',
        '--kind',
        'openai-compatible',
        '--base-url',
        server.baseUrl,
        '--model',
        'm1',
        '--context-window',
        '8000',
        '--yes',
      ]);

      expect(code, 0, reason: io.stderrText);
      expect(config(), contains('kind: openai-compatible'));
      expect(server.requests.single.path, '/v1/models');
    });

    test('без --preset: --kind anthropic → custom-anthropic', () async {
      final (code, io) = await run([
        'provider',
        'add',
        'gw',
        '--kind',
        'anthropic',
        '--base-url',
        server.origin,
        '--model',
        'm1',
        '--context-window',
        '8000',
        '--yes',
      ]);

      expect(code, 0, reason: io.stderrText);
      expect(config(), contains('kind: anthropic'));
      // Anthropic-вариант проверки: `<base>/v1/models`.
      expect(server.requests.single.path, '/v1/models');
    });

    test('--verbose: provider_wizard.started с entry=flags', () async {
      final (code, io) = await run([...fullFlags(), '--yes', '--verbose']);

      expect(code, 0, reason: io.stderrText);
      expect(
        io.stderrText,
        contains('provider_wizard.started mode=add entry=flags'),
      );
      expect(io.stderrText, isNot(contains(server.baseUrl)));
    });
  });

  group('выбор режима: мастер, флаги или ядро (D15, Q13)', () {
    test('флаги ядра без клиентских флагов на терминале: ядро без '
        'изменений, вопросов нет', () async {
      final (tCode, tty) = await run([
        'provider',
        'add',
        'gw',
        '--kind',
        'openai-compatible',
      ], io: FakeCliIo(stdinIsTerminal: true, stdoutIsTerminal: true));
      final (pCode, pipe) = await run([
        'provider',
        'add',
        'gw',
        '--kind',
        'openai-compatible',
      ]);

      expect(tCode, 64);
      expect(tty.stdoutText, isEmpty);
      expect(tty.stderrText, contains('missing required options'));
      expect(tty.stderrText, isNot(contains('? ')));
      expect(tCode, pCode);
      expect(tty.stderrText, pipe.stderrText);
      expect(tty.stdoutText, pipe.stdoutText);
      expect(config(), _initialConfig);
    });

    test('полный набор флагов ядра на терминале: вывод ядра, запроса '
        '/models нет', () async {
      final args = [
        'provider',
        'add',
        'gw',
        '--kind',
        'openai-compatible',
        '--base-url',
        server.baseUrl,
        '--model',
        'm1',
        '--context-window',
        '8000',
        '--api-key-env',
        'GW_KEY',
      ];

      final (code, io) = await run(
        args,
        io: FakeCliIo(stdinIsTerminal: true, stdoutIsTerminal: true),
      );

      expect(code, 0, reason: io.stderrText);
      expect(server.requests, isEmpty);
      final bytes = config();
      File('$home/config.yaml').writeAsStringSync(_initialConfig);
      final expected = await ProviderCommands().add(
        ProviderAddOptions(
          id: 'gw',
          cwd: project,
          environment: env,
          kind: 'openai-compatible',
          baseUrl: server.baseUrl,
          model: 'm1',
          contextWindow: '8000',
          apiKeyEnv: 'GW_KEY',
        ),
        _NoStdin(),
      );
      expect(io.stdoutText, '${expected.stdout.join('\n')}\n');
      expect(bytes, config());
    });

    test('без id и без терминала: прежний код 64 и текст', () async {
      final (code, io) = await run(['provider', 'add']);

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(
        io.stderrText,
        startsWith(
          'codelab: provider add needs the '
          'provider id\n',
        ),
      );
      expect(config(), _initialConfig);
    });

    test('без флагов без терминала с id: прежнее «missing required '
        'options»', () async {
      final (code, io) = await run(['provider', 'add', 'gw']);

      expect(code, 64);
      expect(
        io.stderrText,
        'provider add: missing required options: '
        '--kind, --model, --context-window\n',
      );
    });
  });
}

/// `SecretInput`, который не должен вызываться: ключ в этих флагах не нужен.
final class _NoStdin implements SecretInput {
  @override
  bool get hasTerminal => false;

  @override
  Future<String?> readHidden(String prompt) =>
      throw StateError('stdin is not expected');

  @override
  Future<String> readAll() => throw StateError('stdin is not expected');
}
