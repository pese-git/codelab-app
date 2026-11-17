import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
// Шов записи (`ConfigWriteSeam`) — только для тестов, из барели не экспортируется.
import 'package:codelab_agent_io/src/config/config_writer.dart'
    show ConfigWriteSeam;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/fake_secret_input.dart';
import '../support/fake_secret_process_runner.dart';

// Заведомо фиктивные значения: ни одно не похоже на настоящий токен.
const _token = 'tok-test-value-1';
const _github = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
const _skProj = 'sk-proj-AbCdEfGhIjKlMnOpQrStUvWx';

/// `mcp add --header-stdin|--env-stdin|--header-scheme` (agent-configuration
/// «Значение заголовка или переменной mcp add из stdin»; design.md change
/// `add-config-literal-secrets-and-migrate`, D11, R8-5; задача 3.4).
///
/// Тест работает во временных `CODELAB_HOME` и `cwd`, ввод — фейк, настоящий
/// `~/.codelab` не читается. Во всех сценариях значение не должно попасть в
/// вывод и в файл конфига: там остаётся только ссылка `${secret:…}`.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late String userPath;

  const authName = 'codelab/mcp/gh/authorization';
  const tokenName = 'codelab/mcp/gh/github_token';
  const fileBackend = 'secrets:\n  backend: file\n';

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('mcp_add_stdin')
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

  /// Команды над памятью (или настоящими бэкендами, если [store] не задан).
  McpServerCommands commands({
    MemorySecretStore? store,
    Future<void> Function(ConfigWriteSeam point)? seam,
  }) => McpServerCommands(
    processRunner: FakeSecretProcessRunner(),
    openStore: store == null
        ? null
        : ({required choice, required environment, required home}) => store,
    writeSeam: seam,
  );

  McpAddOptions http({
    String name = 'gh',
    List<String> headerStdin = const [],
    String? headerScheme,
    List<String> envStdin = const [],
    List<String> headers = const [],
  }) => McpAddOptions(
    name: name,
    cwd: cwd,
    environment: env(),
    type: 'http',
    url: 'https://h',
    headers: headers,
    headerStdin: headerStdin,
    headerScheme: headerScheme,
    envStdin: envStdin,
  );

  McpAddOptions stdio({
    String name = 'gh',
    List<String> envStdin = const [],
    List<String> headerStdin = const [],
    List<String> env_ = const [],
  }) => McpAddOptions(
    name: name,
    cwd: cwd,
    environment: env(),
    type: 'stdio',
    command: 'x',
    env: env_,
    envStdin: envStdin,
    headerStdin: headerStdin,
  );

  YamlMap server(String name) {
    final servers =
        ((loadYaml(File(userPath).readAsStringSync()) as YamlMap)['mcp']
                as YamlMap)['servers']
            as YamlList;
    return servers.firstWhere((s) => (s as YamlMap)['name'] == name) as YamlMap;
  }

  void expectNoValue(ConfigCommandResult result, [String value = _token]) {
    expect(allOutput(result), isNot(contains(value)));
    if (File(userPath).existsSync()) {
      expect(File(userPath).readAsStringSync(), isNot(contains(value)));
    }
  }

  group('успешные сценарии', () {
    test('заголовок со схемой: токен в хранилище, в файле ссылка', () async {
      write(userPath, fileBackend);
      final input = FakeSecretInput('$_token\n');

      final result = await commands().add(
        http(headerStdin: ['Authorization'], headerScheme: 'Bearer'),
        input,
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(
        server('gh')['headers']['Authorization'],
        'Bearer \${secret:$authName}',
      );
      expect(File('$home/secrets.yaml').readAsStringSync(), contains(_token));
      expect(input.reads, 1);
      expectNoValue(result);
    });

    test('заголовок без схемы: значение stdin — весь заголовок', () async {
      final store = MemorySecretStore();

      final result = await commands(store: store).add(
        http(name: 'gh', headerStdin: ['X-Api-Key']),
        FakeSecretInput('$_token\n'),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(
        server('gh')['headers']['X-Api-Key'],
        '\${secret:codelab/mcp/gh/x-api-key}',
      );
      expect(await store.read('codelab/mcp/gh/x-api-key'), _token);
      expectNoValue(result);
    });

    test('переменная: env.<NAME> ссылается на секрет', () async {
      final store = MemorySecretStore();

      final result = await commands(
        store: store,
      ).add(stdio(envStdin: ['GITHUB_TOKEN']), FakeSecretInput(_token));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(server('gh')['env']['GITHUB_TOKEN'], '\${secret:$tokenName}');
      expect(await store.read(tokenName), _token);
      expectNoValue(result);
    });

    test('--header и --env с ссылками работают как прежде', () async {
      final store = MemorySecretStore();

      final result = await commands(store: store).add(
        http(
          headerStdin: ['Authorization'],
          headers: ['X-Other=\${secret:codelab/other}'],
        ),
        FakeSecretInput(_token),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(server('gh')['headers']['X-Other'], '\${secret:codelab/other}');
    });

    test('слой --local: файл проекта, секрет в хранилище', () async {
      // Серверы проектных слоёв читаются только в доверенном проекте.
      write(userPath, 'trusted_projects: [$cwd]\n');
      final store = MemorySecretStore();
      final options = McpAddOptions(
        name: 'gh',
        cwd: cwd,
        environment: env(),
        type: 'http',
        url: 'https://h',
        headerStdin: const ['Authorization'],
        local: true,
      );

      final result = await commands(
        store: store,
      ).add(options, FakeSecretInput(_token));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(
        File('$cwd/.codelab/config.local.yaml').readAsStringSync(),
        isNot(contains(_token)),
      );
      expect(await store.read(authName), _token);
    });
  });

  group('ошибки использования (64)', () {
    test(
      'два флага -stdin: ни stdin, ни файл, ни хранилище не тронуты',
      () async {
        final store = MemorySecretStore();
        final input = FakeSecretInput(_token);

        final result = await commands(
          store: store,
        ).add(stdio(envStdin: ['A', 'B']), input);

        expect(result.exitCode, 64);
        expect(result.stderr, [
          'mcp add: only one of --header-stdin, --env-stdin can be used per '
              'call',
        ]);
        expect(input.reads, 0);
        expect(File(userPath).existsSync(), isFalse);
        expect(await store.names(), isEmpty);
      },
    );

    test('--header-stdin и --env-stdin вместе — то же сообщение', () async {
      final input = FakeSecretInput(_token);

      final result = await commands(store: MemorySecretStore()).add(
        McpAddOptions(
          name: 'gh',
          cwd: cwd,
          environment: env(),
          type: 'http',
          url: 'https://h',
          headerStdin: const ['A'],
          envStdin: const ['B'],
        ),
        input,
      );

      expect(result.exitCode, 64);
      expect(result.stderr.single, contains('only one of --header-stdin'));
      expect(input.reads, 0);
    });

    test('--header-scheme без --header-stdin', () async {
      final input = FakeSecretInput(_token);

      final result = await commands(store: MemorySecretStore()).add(
        McpAddOptions(
          name: 'gh',
          cwd: cwd,
          environment: env(),
          type: 'stdio',
          command: 'x',
          headerScheme: 'Bearer',
          envStdin: const ['A'],
        ),
        input,
      );

      expect(result.exitCode, 64);
      expect(result.stderr.single, contains('--header-scheme'));
      expect(input.reads, 0);
      expect(File(userPath).existsSync(), isFalse);
    });

    test('имя уже задано в --header: без учёта регистра', () async {
      final input = FakeSecretInput(_token);

      final result = await commands(store: MemorySecretStore()).add(
        http(
          headerStdin: ['Authorization'],
          headers: ['authorization=\${secret:codelab/x}'],
        ),
        input,
      );

      expect(result.exitCode, 64);
      expect(input.reads, 0);
      expect(File(userPath).existsSync(), isFalse);
    });

    test('имя уже задано в --env', () async {
      final input = FakeSecretInput(_token);

      final result = await commands(store: MemorySecretStore()).add(
        stdio(envStdin: ['GITHUB_TOKEN'], env_: ['GITHUB_TOKEN=\${X}']),
        input,
      );

      expect(result.exitCode, 64);
      expect(input.reads, 0);
    });

    test('имя, похожее на токен, не печатается', () async {
      for (final options in [
        http(headerStdin: [_github]),
        stdio(envStdin: [_skProj]),
      ]) {
        final input = FakeSecretInput(_token);
        final result = await commands(
          store: MemorySecretStore(),
        ).add(options, input);

        expect(result.exitCode, 64);
        expect(allOutput(result), isNot(contains(_github)));
        expect(allOutput(result), isNot(contains(_skProj)));
        expect(input.reads, 0);
        expect(File(userPath).existsSync(), isFalse);
      }
    });

    test('пустое значение stdin: код 64, файл не изменён', () async {
      final result = await commands(
        store: MemorySecretStore(),
      ).add(http(headerStdin: ['Authorization']), FakeSecretInput('\n'));

      expect(result.exitCode, 64);
      expect(File(userPath).existsSync(), isFalse);
    });
  });

  group('хранилище', () {
    test('бэкенд env: код 1, stdin не читается, подсказка', () async {
      final input = FakeSecretInput(_token);

      final result = await commands().add(
        stdio(envStdin: ['GITHUB_TOKEN']),
        input,
      );

      expect(result.exitCode, 1, reason: allOutput(result));
      expect(input.reads, 0);
      final err = result.stderr.join('\n');
      expect(err, contains("'secrets.backend: file'"));
      expect(err, contains('CODELAB_SECRET_CODELAB_MCP_GH_GITHUB_TOKEN'));
      expect(File(userPath).existsSync(), isFalse);
    });

    test('существующий секрет заменяется с предупреждением', () async {
      final store = MemorySecretStore({authName: 'old-test-value'});

      final result = await commands(
        store: store,
      ).add(http(headerStdin: ['Authorization']), FakeSecretInput(_token));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(
        result.stdout,
        contains('warning: replaced the existing secret $authName'),
      );
      expect(await store.read(authName), _token);
    });

    test('повторный mcp add того же сервера заменяет без отказа', () async {
      write(
        userPath,
        'mcp:\n  servers:\n    - name: gh\n      type: http\n'
        '      url: https://h\n      headers:\n'
        '        Authorization: "\${secret:$authName}"\n',
      );
      final store = MemorySecretStore({authName: 'old-test-value'});

      final result = await commands(
        store: store,
      ).add(http(headerStdin: ['Authorization']), FakeSecretInput(_token));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(await store.read(authName), _token);
    });

    test(
      'сбой записи конфига после сохранения: код 1, стдерр называет имя',
      () async {
        final store = MemorySecretStore();

        final result = await commands(
          store: store,
          seam: (point) async {
            if (point == ConfigWriteSeam.tmpWritten) {
              throw StateError('boom $_token');
            }
          },
        ).add(http(headerStdin: ['Authorization']), FakeSecretInput(_token));

        expect(result.exitCode, 1, reason: allOutput(result));
        expect(result.stderr.join('\n'), contains(authName));
        expect(await store.read(authName), _token);
        expectNoValue(result);
      },
    );

    test('невалидный итог: отказ до чтения stdin', () async {
      final input = FakeSecretInput(_token);

      final result = await commands(store: MemorySecretStore()).add(
        McpAddOptions(
          name: 'gh',
          cwd: cwd,
          environment: env(),
          type: 'http',
          url: 'not a url',
          headerStdin: const ['Authorization'],
        ),
        input,
      );

      expect(result.exitCode, isNot(0));
      expect(input.reads, 0);
    });
  });

  group('коллизия имён секрета (код 1 до чтения stdin)', () {
    void expectRefused(ConfigCommandResult result, FakeSecretInput input) {
      expect(result.exitCode, 1, reason: allOutput(result));
      expect(input.reads, 0);
    }

    test('имя занято другим сервером по ссылке', () async {
      const config =
          'mcp:\n  servers:\n    - name: GH\n      type: http\n'
          '      url: https://h\n      headers:\n'
          '        Authorization: "\${secret:$authName}"\n';
      write(userPath, config);
      final store = MemorySecretStore();
      final input = FakeSecretInput(_token);

      final result = await commands(
        store: store,
      ).add(http(headerStdin: ['Authorization']), input);

      expectRefused(result, input);
      final err = result.stderr.join('\n');
      expect(err, contains('mcp.servers[GH].headers.Authorization'));
      expect(err, contains('secret $authName is already used by'));
      expect(err, contains('codelab secret set'));
      expect(File(userPath).readAsStringSync(), config);
      expect(await store.names(), isEmpty);
    });

    test('имя занято провайдером (api_key_secret)', () async {
      write(
        userPath,
        'providers:\n  gw:\n    kind: openai-compatible\n'
        '    base_url: https://x/v1\n    api_key_secret: $authName\n'
        '    models:\n      m:\n        context_window: 8192\n'
        'agent:\n  default_model: gw/m\n',
      );
      final input = FakeSecretInput(_token);

      final result = await commands(
        store: MemorySecretStore(),
      ).add(http(headerStdin: ['Authorization']), input);

      expectRefused(result, input);
      expect(result.stderr.join('\n'), contains('providers.gw.api_key_secret'));
    });

    test('forMcp другого сервера совпал: GH и gh', () async {
      write(
        userPath,
        'mcp:\n  servers:\n    - name: GH\n      type: http\n'
        '      url: https://h\n',
      );
      final input = FakeSecretInput(_token);

      final result = await commands(
        store: MemorySecretStore(),
      ).add(http(headerStdin: ['Authorization']), input);

      expectRefused(result, input);
      expect(result.stderr.join('\n'), contains('mcp.servers[GH]'));
    });

    test('другой сервер с другим именем не мешает', () async {
      write(
        userPath,
        'mcp:\n  servers:\n    - name: other\n      type: http\n'
        '      url: https://h\n',
      );

      final result = await commands(
        store: MemorySecretStore(),
      ).add(http(headerStdin: ['Authorization']), FakeSecretInput(_token));

      expect(result.exitCode, 0, reason: allOutput(result));
    });
  });

  group('тип сервера и схема (D11)', () {
    test('--header-stdin у stdio и --env-stdin у http: код 64, stdin не '
        'читался, файл и хранилище не тронуты', () async {
      final cases = [
        (
          stdio(headerStdin: const ['Authorization']),
          '--header-stdin is for --type http',
        ),
        (http(envStdin: const ['TOKEN']), '--env-stdin is for --type stdio'),
      ];
      for (final (options, message) in cases) {
        final input = FakeSecretInput(_token);
        final store = MemorySecretStore();

        final result = await commands(store: store).add(options, input);

        expect(result.exitCode, 64);
        expect(result.stderr.single, contains(message));
        expect(input.reads, 0);
        expect(File(userPath).existsSync(), isFalse);
        expect(await store.names(), isEmpty);
        expectNoValue(result);
      }
    });

    test('--header-scheme пустая, с пробелом, с \$ или с недопустимым '
        'символом: код 64 до чтения stdin', () async {
      for (final scheme in ['', 'Bea rer', 'Bearer\$', 'Bea"rer', 'a:b']) {
        final input = FakeSecretInput(_token);
        final store = MemorySecretStore();

        final result = await commands(store: store).add(
          http(headerStdin: const ['Authorization'], headerScheme: scheme),
          input,
        );

        expect(result.exitCode, 64, reason: 'scheme "$scheme"');
        expect(result.stderr.single, contains('--header-scheme'));
        expect(input.reads, 0);
        expect(File(userPath).existsSync(), isFalse);
        expect(await store.names(), isEmpty);
      }
    });

    test('допустимые схемы: токен RFC 9110', () async {
      for (final scheme in ['Bearer', 'Basic', 'X-Custom.1']) {
        final result = await commands(store: MemorySecretStore()).add(
          http(
            name: 's${scheme.length}',
            headerStdin: const ['Authorization'],
            headerScheme: scheme,
          ),
          FakeSecretInput(_token),
        );

        expect(result.exitCode, 0, reason: allOutput(result));
      }
    });
  });
}
