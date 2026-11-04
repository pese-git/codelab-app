import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
// Шов записи конфига не входит в публичный барель: он нужен только тесту
// сбоя записи после сохранения секретов.
import 'package:codelab_agent_io/src/config/config_writer.dart'
    show ConfigWriteSeam;
import 'package:test/test.dart';

import '../support/fake_secret_process_runner.dart';

/// `SecretCommands.migrate`: строки CLI, флаги, коды выхода (agent-secrets
/// «Подкоманда secret migrate»; design.md change
/// `add-config-literal-secrets-and-migrate`, D7). Движок проверяет
/// `secret_migrator_test.dart`; здесь — обёртка, одинаковая у `codelab` и
/// `codelab-agent`.
///
/// Значения «секретов» выдуманные; ни одно не должно попасть в stdout и
/// stderr. Тест не читает настоящий `~/.codelab`: `CODELAB_HOME` и окружение
/// передаются явно.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late String userPath;
  late String projectPath;
  late String localPath;

  final sk = 'sk-${'a1b2c3d4e5' * 3}';
  final ghp = 'ghp_${'abcdef0123' * 3}abcdef';

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('secret_migrate_command_test')
          .resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    userPath = '$home/config.yaml';
    projectPath = '$cwd/.codelab/config.yaml';
    localPath = '$cwd/.codelab/config.local.yaml';
  });

  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  String read(String path) => File(path).readAsStringSync();

  Map<String, String> env([Map<String, String> extra = const {}]) => {
    'CODELAB_HOME': home,
    'X': '1',
    ...extra,
  };

  String userConfig({String? key, String extra = ''}) =>
      '''
${extra}providers:
  lm:
    kind: openai-compatible
    base_url: https://llm.test/v1
${key == null ? '' : '    api_key: $key\n'}    models:
      m: {}
agent:
  default_model: lm/m
''';

  String serverWithToken(String name, String token) =>
      '''
mcp:
  servers:
    - name: $name
      type: http
      url: https://$name.test/mcp
      token: $token
''';

  SecretCommands over(
    DescribedSecretStore store, {
    Future<void> Function(ConfigWriteSeam point)? seam,
  }) => SecretCommands(
    runner: FakeSecretProcessRunner(),
    writeSeam: seam,
    openStore: ({required choice, required environment, required home}) =>
        store,
  );

  Future<SecretCommandResult> migrate(
    SecretCommands commands, {
    bool project = false,
    bool local = false,
    bool all = false,
    bool dryRun = false,
    bool force = false,
    String? workdir,
    Map<String, String>? environment,
  }) => commands.migrate(
    SecretMigrateOptions(
      environment: environment ?? env(),
      cwd: workdir ?? cwd,
      project: project,
      local: local,
      all: all,
      dryRun: dryRun,
      force: force,
    ),
  );

  void expectNoValues(SecretCommandResult result) {
    final text = [...result.stdout, ...result.stderr].join('\n');
    for (final value in [sk, ghp]) {
      expect(text, isNot(contains(value)));
      expect(text, isNot(contains(value.substring(0, 8))));
    }
  }

  void trustProject() => write(
    userPath,
    userConfig(key: sk, extra: 'trusted_projects:\n  - $cwd\n'),
  );

  group('вывод и коды', () {
    test('перенос по умолчанию — слой user: строки Moved и restart', () async {
      write(userPath, userConfig(key: sk));
      final store = MemorySecretStore();

      final result = await migrate(over(store));

      expect(result.exitCode, 0);
      expect(result.stdout, [
        'Moved providers.lm.api_key in $userPath to secret codelab/lm',
        'restart the agent to use the moved secrets',
      ]);
      expect(result.stderr, isEmpty);
      expect(result.showUsage, isFalse);
      expect(await store.read('codelab/lm'), sk);
      expectNoValues(result);
    });

    test('action required для ключа вне схемы идёт строкой stdout', () async {
      write(userPath, '${userConfig()}${serverWithToken('gh', ghp)}');
      final store = MemorySecretStore();

      final result = await migrate(over(store));

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          r'action required: reference ${secret:codelab/mcp/gh/token} in '
          'mcp.servers[gh].env or .headers',
        ),
      );
      expect(result.stdout.last, 'restart the agent to use the moved secrets');
      expectNoValues(result);
    });

    test('--dry-run: план без строки restart; файл и хранилище не '
        'изменены', () async {
      write(userPath, userConfig(key: sk));
      final before = read(userPath);
      final store = MemorySecretStore();

      final result = await migrate(over(store), dryRun: true);

      expect(result.exitCode, 0);
      expect(result.stdout, [
        '$userPath: providers.lm.api_key -> api_key_secret: codelab/lm (new)',
      ]);
      expect(read(userPath), before);
      expect(await store.names(), isEmpty);
    });

    test('нечего переносить: Nothing to migrate, код 0', () async {
      write(userPath, userConfig());

      final result = await migrate(over(MemorySecretStore()));

      expect(result.exitCode, 0);
      expect(result.stdout, ['Nothing to migrate']);
    });

    test('not migrated не меняет код выхода и не требует restart', () async {
      write(userPath, userConfig());
      write('${root.path}/extra.yaml', 'providers:\n  lm:\n    api_key: $sk\n');

      final result = await migrate(
        over(MemorySecretStore()),
        environment: env({'CODELAB_CONFIG': '${root.path}/extra.yaml'}),
      );

      expect(result.exitCode, 0);
      expect(result.stdout, [
        'not migrated: ${root.path}/extra.yaml is not a writable layer',
      ]);
      expectNoValues(result);
    });

    test(
      'CODELAB_CONFIG недопустим: warning в stderr, код не меняется',
      () async {
        write(userPath, userConfig());

        final result = await migrate(
          over(MemorySecretStore()),
          environment: env({'CODELAB_CONFIG': 'relative.yaml'}),
        );

        expect(result.exitCode, 0);
        expect(
          result.stderr.single,
          startsWith('warning: CODELAB_CONFIG ignored'),
        );
      },
    );
  });

  group('слои и флаги', () {
    test('--project: только проектный слой (user не тронут)', () async {
      trustProject();
      write(projectPath, serverWithToken('gh', ghp));
      final userBefore = read(userPath);
      final store = MemorySecretStore();

      final result = await migrate(over(store), project: true);

      expect(result.exitCode, 0);
      expect(
        result.stdout.first,
        startsWith('Moved mcp.servers[gh].token in '),
      );
      expect(result.stdout.first, contains(projectPath));
      expect(read(userPath), userBefore);
      expect(await store.names(), ['codelab/mcp/gh/token']);
    });

    test('--local: только локальный слой', () async {
      trustProject();
      write(localPath, serverWithToken('gh', ghp));
      final projectBefore = '# untouched\n';
      write(projectPath, projectBefore);
      final store = MemorySecretStore();

      final result = await migrate(over(store), local: true);

      expect(result.exitCode, 0);
      expect(result.stdout.first, contains(localPath));
      expect(read(projectPath), projectBefore);
    });

    test('--all: user, project и local по порядку слоёв', () async {
      trustProject();
      write(projectPath, serverWithToken('gh', ghp));
      write(
        localPath,
        serverWithToken('other', 'ghp_${'0123456789' * 3}abcdef'),
      );
      final store = MemorySecretStore();

      final result = await migrate(over(store), all: true);

      expect(result.exitCode, 0);
      final moved = [
        for (final line in result.stdout)
          if (line.startsWith('Moved ')) line,
      ];
      expect(moved, hasLength(3));
      expect(moved[0], contains(userPath));
      expect(moved[1], contains(projectPath));
      expect(moved[2], contains(localPath));
      expect(await store.names(), hasLength(3));
    });

    test('--all вместе с --project или --local: код 64 и справка, файлы не '
        'тронуты', () async {
      write(userPath, userConfig(key: sk));
      final before = read(userPath);
      final store = MemorySecretStore();

      for (final (project, local) in [(true, false), (false, true)]) {
        final result = await migrate(
          over(store),
          all: true,
          project: project,
          local: local,
        );

        expect(result.exitCode, 64);
        expect(result.showUsage, isTrue);
        expect(result.stderr, [
          'secret migrate: --all cannot be combined with --project or --local',
        ]);
        expect(result.stdout, isEmpty);
      }
      expect(read(userPath), before);
      expect(await store.names(), isEmpty);
    });

    test('--cwd: каталог проекта; несуществующий — код 64', () async {
      write(userPath, userConfig());

      final result = await migrate(
        over(MemorySecretStore()),
        workdir: '${root.path}/missing',
      );

      expect(result.exitCode, 64);
      expect(result.stderr, [
        'secret migrate: no such directory: ${root.path}/missing',
      ]);
    });
  });

  group('конфликты и --force', () {
    test('другое значение в хранилище: код 1 и текст про --force', () async {
      write(userPath, userConfig(key: sk));
      final store = MemorySecretStore({'codelab/lm': 'old-value-0001'});

      final result = await migrate(over(store));

      expect(result.exitCode, 1);
      expect(result.stderr, [
        'secret codelab/lm already exists with a different value; rerun with '
            '--force to replace it',
      ]);
      expect(result.stdout, isEmpty);
      expect(await store.read('codelab/lm'), 'old-value-0001');
      expectNoValues(result);
    });

    test('--force: warning о безвозвратной замене и код 0', () async {
      write(userPath, userConfig(key: sk));
      final store = MemorySecretStore({'codelab/lm': 'old-value-0001'});

      final result = await migrate(over(store), force: true);

      expect(result.exitCode, 0);
      expect(
        result.stdout.first,
        'warning: replaced the existing secret codelab/lm; the previous '
        'value cannot be restored',
      );
      expect(await store.read('codelab/lm'), sk);
    });

    test('--project --force называет ссылающиеся ключи других слоёв', () async {
      write(userPath, '''
trusted_projects:
  - $cwd
providers:
  other:
    kind: openai-compatible
    base_url: https://other.test/v1
    api_key_secret: codelab/lm
    models:
      m: {}
agent:
  default_model: other/m
''');
      write(
        projectPath,
        'providers:\n  lm:\n    kind: openai-compatible\n'
        '    base_url: https://llm.test/v1\n    api_key: $sk\n'
        '    models:\n      m: {}\n',
      );
      final store = MemorySecretStore({'codelab/lm': 'old-value-0001'});

      final result = await migrate(over(store), project: true, force: true);

      expect(result.exitCode, 0);
      expect(
        result.stdout.first,
        'warning: replaced the existing secret codelab/lm; the previous '
        'value cannot be restored; also referenced by: '
        'providers.other.api_key_secret (user)',
      );
    });
  });

  group('бэкенды', () {
    test(
      'env (по умолчанию): код 1, подсказка с файлом и переменными',
      () async {
        write(userPath, userConfig(key: sk));
        final before = read(userPath);

        final result = await migrate(
          SecretCommands(runner: FakeSecretProcessRunner()),
        );

        expect(result.exitCode, 1);
        final text = result.stderr.join('\n');
        expect(text, contains("'secrets.backend: file'"));
        expect(text, contains('CODELAB_SECRET_CODELAB_LM'));
        expect(read(userPath), before);
        expectNoValues(result);
      },
    );

    test('file: перенос в secrets.yaml и предупреждение об открытом '
        'тексте в stderr', () async {
      write(
        userPath,
        userConfig(key: sk, extra: 'secrets:\n  backend: file\n'),
      );

      final result = await migrate(
        SecretCommands(runner: FakeSecretProcessRunner(), platform: 'linux'),
      );

      expect(result.exitCode, 0);
      expect(result.stderr, [
        'warning: secrets are stored unencrypted in $home/secrets.yaml',
      ]);
      expect(File('$home/secrets.yaml').existsSync(), isTrue);
      expect(read(userPath), contains('api_key_secret: codelab/lm'));
      expectNoValues(result);
    });
  });

  group('сбой записи конфига', () {
    test('код 1, stderr называет сохранённые имена, файл не изменён', () async {
      write(userPath, userConfig(key: sk));
      final before = read(userPath);
      final store = MemorySecretStore();

      final result = await migrate(
        over(
          store,
          seam: (point) async {
            if (point == ConfigWriteSeam.tmpWritten) {
              throw const FileSystemException('disk is gone');
            }
          },
        ),
      );

      expect(result.exitCode, 1);
      expect(result.stderr.join('\n'), contains('codelab/lm'));
      expect(result.stdout, isNot(contains(startsWith('Moved'))));
      expect(read(userPath), before);
      expectNoValues(result);

      final second = await migrate(over(store));

      expect(second.exitCode, 0);
      expect(second.stdout.first, startsWith('Reused secret codelab/lm'));
    });
  });

  group('проблемы загрузки и окружения', () {
    test('синтаксическая ошибка конфига: код 1 с проблемой', () async {
      write(userPath, 'providers: [unclosed\n');

      final result = await migrate(over(MemorySecretStore()));

      expect(result.exitCode, 1);
      expect(result.stderr, isNotEmpty);
    });

    test('без домашнего каталога: код 64 и тот же текст, что у set', () async {
      final result = await migrate(
        over(MemorySecretStore()),
        environment: const {},
      );

      expect(result.exitCode, 64);
      expect(result.stderr, [
        'cannot find the home folder: set CODELAB_HOME or HOME',
      ]);
    });
  });
}
