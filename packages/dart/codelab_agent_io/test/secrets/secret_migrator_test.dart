import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
// Шов записи конфига (`ConfigWriteSeam`) не входит в публичный барель: он
// нужен только тесту сбоя записи после сохранения секретов.
import 'package:codelab_agent_io/src/config/config_writer.dart'
    show ConfigWriteSeam;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/fake_secret_process_runner.dart';

/// Движок `secret migrate` (agent-secrets «Подкоманда secret migrate», все
/// сценарии; design.md change `add-config-literal-secrets-and-migrate`, D7,
/// R8-4, H4, L7).
///
/// Значения «секретов» выдуманные (синтетические токены по шаблонам §12.4);
/// ни одно из них не должно попасть в отчёт, его строки и `toString`.
/// Тест не читает настоящий `~/.codelab`: `CODELAB_HOME` и окружение
/// передаются явно, хранилище — в памяти либо настоящий бэкенд `env`.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late String userPath;
  late String projectPath;

  final sk = 'sk-${'a1b2c3d4e5' * 3}';
  final ghp = 'ghp_${'abcdef0123' * 3}abcdef';
  final ghp2 = 'ghp_${'fedcba9876' * 3}fedcba';
  final allValues = [sk, ghp, ghp2];

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('secret_migrator_test')
          .resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    userPath = '$home/config.yaml';
    projectPath = '$cwd/.codelab/config.yaml';
  });

  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  String read(String path) => File(path).readAsStringSync();

  /// Значение по пути ключей разобранного файла (сравнение значений, а не
  /// текста: форма кавычек — дело редактора YAML).
  Object? valueAt(String path, List<Object> keys) {
    Object? node = loadYaml(read(path));
    for (final key in keys) {
      node = key is int ? (node! as YamlList)[key] : (node! as YamlMap)[key];
    }
    return node;
  }

  Map<String, String> env([Map<String, String> extra = const {}]) => {
    'CODELAB_HOME': home,
    // Подстановка `${X}` в заголовках не должна давать проблему загрузки.
    'X': '1',
    ...extra,
  };

  SecretMigrator migrator({
    DescribedSecretStore? store,
    Future<void> Function(ConfigWriteSeam point)? seam,
    String? platform,
  }) => SecretMigrator(
    processRunner: FakeSecretProcessRunner(),
    platform: platform,
    writeSeam: seam,
    openStore: store == null
        ? null
        : ({required choice, required environment, required home}) => store,
  );

  Future<SecretMigrationReport> run(
    SecretMigrator m, {
    Set<ConfigLayer> layers = const {ConfigLayer.user},
    bool dryRun = false,
    bool force = false,
    Map<String, String>? environment,
  }) => m.run(
    SecretMigrationOptions(
      cwd: cwd,
      environment: environment ?? env(),
      layers: layers,
      dryRun: dryRun,
      force: force,
    ),
  );

  /// Ни одно значение секрета не попало в отчёт: строки, `toString` отчёта и
  /// пунктов, `describe()`.
  void expectNoValues(SecretMigrationReport report) {
    final text = [
      ...report.stdoutLines,
      ...report.stderrLines,
      '$report',
      for (final item in report.items) ...['$item', item.describe()],
    ].join('\n');
    for (final value in allValues) {
      expect(text, isNot(contains(value)));
      expect(text, isNot(contains(value.substring(0, 8))));
    }
  }

  String userConfig({
    String? key,
    String? gatewayHeader,
    String servers = '',
    String extra = '',
  }) =>
      '''
# top comment
${extra}providers:
  lm: # the gateway
    kind: openai-compatible
    base_url: https://llm.test/v1
${key == null ? '' : '    api_key: $key # inline comment\n'}${gatewayHeader == null ? '' : '    headers:\n      X-Gateway-Key: $gatewayHeader\n'}    models:
      m: {}
agent:
  default_model: lm/m
$servers''';

  String ghServer({String? authorization, String extra = ''}) => '''
mcp:
  servers:
    - name: gh # github
      type: http
      url: https://gh.test/mcp
$extra${authorization == null ? '' : '      headers:\n        Authorization: "$authorization"\n'}''';

  group('перенос', () {
    test('ключ провайдера и смешанный заголовок: секреты в хранилище, '
        'ссылки в файле, комментарии на месте', () async {
      write(
        userPath,
        userConfig(
          key: sk,
          servers: ghServer(authorization: 'Bearer $ghp \${X}'),
        ),
      );
      final store = MemorySecretStore();

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(await store.read('codelab/lm'), sk);
      expect(await store.read('codelab/mcp/gh/authorization'), ghp);
      final file = read(userPath);
      expect(file, contains('api_key_secret: codelab/lm'));
      expect(file, isNot(contains('api_key: ')));
      expect(
        valueAt(userPath, ['mcp', 'servers', 0, 'headers', 'Authorization']),
        r'Bearer ${secret:codelab/mcp/gh/authorization} ${X}',
      );
      // R8-10: ссылка пишется в одинарных кавычках, `/` не экранируется.
      expect(
        file,
        contains(
          r"Authorization: 'Bearer ${secret:codelab/mcp/gh/authorization} ${X}'",
        ),
      );
      expect(file, contains('# top comment'));
      expect(file, contains('# the gateway'));
      expect(file, contains('# github'));
      expect(file, isNot(contains(sk)));
      expect(file, isNot(contains(ghp)));
      expect(report.stdoutLines, [
        'Moved providers.lm.api_key in $userPath to secret codelab/lm',
        'Moved mcp.servers[gh].headers.Authorization in $userPath to secret '
            'codelab/mcp/gh/authorization',
        'restart the agent to use the moved secrets',
      ]);
      expect(report.canApply, isTrue);
      expectNoValues(report);

      // После переноса литералов в слое больше нет: повтор ничего не находит.
      final again = await run(migrator(store: store));
      expect(again.exitCode, 0);
      expect(again.stdoutLines, ['Nothing to migrate']);
      expect(
        ConfigLoader()
            .load(cwd: cwd, environment: env())
            .warnings
            .where((w) => w.event == 'config.secret.in_file'),
        isEmpty,
      );
    });

    test('token сервера: сначала в хранилище, затем ключ удаляется из файла; '
        'строка action required', () async {
      write(
        userPath,
        userConfig(servers: ghServer(extra: '      token: $ghp\n')),
      );
      final inner = MemorySecretStore();
      String? fileAtWrite;
      final store = _HookStore(
        inner,
        onWrite: () => fileAtWrite = read(userPath),
      );

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(await inner.read('codelab/mcp/gh/token'), ghp);
      // Значение уже лежало в хранилище, пока файл ещё содержал ключ.
      expect(fileAtWrite, contains('token: '));
      expect(read(userPath), isNot(contains('token:')));
      expect(report.stdoutLines, [
        'Moved mcp.servers[gh].token in $userPath to secret '
            'codelab/mcp/gh/token',
        r'action required: reference ${secret:codelab/mcp/gh/token} in '
            'mcp.servers[gh].env or .headers',
        'restart the agent to use the moved secrets',
      ]);
      expectNoValues(report);
    });

    test('ссылка-значение п. 3: api_key_secret и secret-ссылка с токеном '
        'переносятся без проблем формата', () async {
      write(userPath, '''
providers:
  lm:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: $ghp
    models:
      m: {}
agent:
  default_model: lm/m
${ghServer(authorization: 'Bearer \${secret:$ghp2}')}''');
      final store = MemorySecretStore();

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(await store.read('codelab/lm'), ghp);
      expect(await store.read('codelab/mcp/gh/authorization'), ghp2);
      final file = read(userPath);
      expect(file, contains('api_key_secret: codelab/lm'));
      expect(
        valueAt(userPath, ['mcp', 'servers', 0, 'headers', 'Authorization']),
        r'Bearer ${secret:codelab/mcp/gh/authorization}',
      );
      expect(file, isNot(contains(ghp)));
      expect(file, isNot(contains(ghp2)));
      expectNoValues(report);
    });

    test('api_key_env с токеном заменяется на api_key_secret', () async {
      write(
        userPath,
        userConfig().replaceFirst(
          '    models:',
          '    api_key_env: $ghp\n    models:',
        ),
      );
      final store = MemorySecretStore();

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(await store.read('codelab/lm'), ghp);
      final file = read(userPath);
      expect(file, contains('api_key_secret: codelab/lm'));
      expect(file, isNot(contains('api_key_env')));
      expectNoValues(report);
    });

    test('нечего переносить: код 0 и Nothing to migrate, хранилище не '
        'требуется', () async {
      write(userPath, userConfig());

      final report = await run(migrator());

      expect(report.exitCode, 0);
      expect(report.stdoutLines, ['Nothing to migrate']);
      expect(report.stderrLines, isEmpty);
      expect(report.canApply, isFalse);
    });
  });

  group('--dry-run', () {
    test('план со статусом new; файл и хранилище не изменены', () async {
      write(
        userPath,
        userConfig(
          key: sk,
          servers: ghServer(authorization: 'Bearer $ghp \${X}'),
        ),
      );
      final before = read(userPath);
      final store = MemorySecretStore();

      final report = await run(migrator(store: store), dryRun: true);

      expect(report.exitCode, 0);
      expect(report.stdoutLines, [
        '$userPath: providers.lm.api_key -> api_key_secret: codelab/lm (new)',
        '$userPath: mcp.servers[gh].headers.Authorization -> '
            r'${secret:codelab/mcp/gh/authorization} (new)',
      ]);
      expect(read(userPath), before);
      expect(await store.names(), isEmpty);
      expect(report.canApply, isTrue);
      expectNoValues(report);
    });

    test(
      'значение, которое хранилище не примет, показывается и в плане',
      () async {
        write(
          userPath,
          userConfig(
            key: sk,
            servers: ghServer(extra: '      env:\n        KEY: ${_pem()}\n'),
          ),
        );

        final report = await run(
          migrator(store: MemorySecretStore()),
          dryRun: true,
        );

        expect(report.exitCode, 0);
        expect(
          report.stdoutLines,
          contains(
            'not migrated: mcp.servers[gh].env.KEY cannot be stored '
            '(secret value must be a single line)',
          ),
        );
      },
    );
  });

  group('бэкенд env (только чтение)', () {
    test('код 1 с подсказкой secrets.backend: file и именами переменных; '
        'файл не изменён', () async {
      write(
        userPath,
        userConfig(
          key: sk,
          servers: ghServer(authorization: 'Bearer $ghp'),
        ),
      );
      final before = read(userPath);

      // Хранилище не подменено: `secrets.backend` не задан — настоящий `env`.
      final report = await run(migrator());

      expect(report.exitCode, 1);
      expect(report.readOnlyBackend, isTrue);
      expect(report.canApply, isFalse);
      final text = report.stderrLines.join('\n');
      expect(text, contains('secrets.backend: file'));
      expect(text, contains('CODELAB_SECRET_CODELAB_LM'));
      expect(text, contains('CODELAB_SECRET_CODELAB_MCP_GH_AUTHORIZATION'));
      expect(read(userPath), before);
      expectNoValues(report);
    });

    test('Windows: файл не предлагается, только переменные', () async {
      write(userPath, userConfig(key: sk));

      final report = await run(migrator(platform: 'windows'));

      expect(report.exitCode, 1);
      final text = report.stderrLines.join('\n');
      expect(text, isNot(contains('secrets.backend: file')));
      expect(text, contains('CODELAB_SECRET_CODELAB_LM'));
    });
  });

  group('конфликт с хранилищем и --force (L7)', () {
    test('другое значение без --force: код 1 до записи, dry-run — тот же '
        'код', () async {
      write(userPath, userConfig(key: sk));
      final before = read(userPath);
      final store = MemorySecretStore({'codelab/lm': 'old-value-0001'});

      final real = await run(migrator(store: store));
      final dry = await run(migrator(store: store), dryRun: true);

      for (final report in [real, dry]) {
        expect(report.exitCode, 1);
        expect(
          report.stderrLines,
          contains(
            'secret codelab/lm already exists with a different value; '
            'rerun with --force to replace it',
          ),
        );
        expect(report.stdoutLines, isEmpty);
        expectNoValues(report);
      }
      expect(read(userPath), before);
      expect(await store.read('codelab/lm'), 'old-value-0001');
    });

    test('то же значение: Reused без записи', () async {
      write(userPath, userConfig(key: sk));
      final inner = MemorySecretStore({'codelab/lm': sk});
      var writes = 0;
      final store = _HookStore(inner, onWrite: () => writes++);

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(writes, 0);
      expect(report.stdoutLines, [
        'Reused secret codelab/lm for providers.lm.api_key in $userPath',
        'Moved providers.lm.api_key in $userPath to secret codelab/lm',
        'restart the agent to use the moved secrets',
      ]);
      expect(read(userPath), contains('api_key_secret: codelab/lm'));
    });

    test('--force: замена безвозвратна, предупреждение в stdout; dry-run '
        'показывает replace', () async {
      write(userPath, userConfig(key: sk));
      final store = MemorySecretStore({'codelab/lm': 'old-value-0001'});

      final dry = await run(migrator(store: store), dryRun: true, force: true);
      expect(dry.exitCode, 0);
      expect(dry.stdoutLines, [
        '$userPath: providers.lm.api_key -> api_key_secret: codelab/lm '
            '(replace)',
      ]);
      expect(await store.read('codelab/lm'), 'old-value-0001');

      final report = await run(migrator(store: store), force: true);

      expect(report.exitCode, 0);
      expect(
        report.stdoutLines,
        contains(
          'warning: replaced the existing secret codelab/lm; the previous '
          'value cannot be restored',
        ),
      );
      expect(await store.read('codelab/lm'), sk);
      expectNoValues(report);
    });

    test(
      '--project --force называет ключи, которые ссылаются на имя',
      () async {
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
        write(projectPath, '''
providers:
  lm:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key: $sk
    models:
      m: {}
''');
        final store = MemorySecretStore({'codelab/lm': 'old-value-0001'});

        final report = await run(
          migrator(store: store),
          layers: {ConfigLayer.project},
          force: true,
        );

        expect(report.exitCode, 0);
        expect(
          report.stdoutLines,
          contains(
            'warning: replaced the existing secret codelab/lm; the previous '
            'value cannot be restored; also referenced by: '
            'providers.other.api_key_secret (user)',
          ),
        );
        expect(read(projectPath), contains('api_key_secret: codelab/lm'));
        expect(await store.read('codelab/lm'), sk);
      },
    );
  });

  group('имена внутри запуска', () {
    test('разные значения под одним именем: суффикс -2; одинаковые — один '
        'секрет', () async {
      write(userPath, userConfig(key: sk, gatewayHeader: ghp));
      final store = MemorySecretStore();

      final dry = await run(migrator(store: store), dryRun: true);
      expect(dry.stdoutLines, [
        '$userPath: providers.lm.api_key -> api_key_secret: codelab/lm (new)',
        '$userPath: providers.lm.headers.X-Gateway-Key -> '
            r'${secret:codelab/lm-2} (new)',
      ]);

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(await store.read('codelab/lm'), sk);
      expect(await store.read('codelab/lm-2'), ghp);
      expect(
        valueAt(userPath, ['providers', 'lm', 'headers', 'X-Gateway-Key']),
        r'${secret:codelab/lm-2}',
      );

      // Одинаковые значения — один секрет без суффикса.
      write(userPath, userConfig(key: sk, gatewayHeader: sk));
      final same = MemorySecretStore();
      final sameReport = await run(migrator(store: same));
      expect(sameReport.exitCode, 0);
      expect(await same.names(), ['codelab/lm']);
    });

    test('два участка одного значения: имя и имя-2', () async {
      write(
        userPath,
        userConfig(servers: ghServer(authorization: 'Bearer $ghp $ghp2')),
      );
      final store = MemorySecretStore();

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(await store.read('codelab/mcp/gh/authorization'), ghp);
      expect(await store.read('codelab/mcp/gh/authorization-2'), ghp2);
      expect(
        valueAt(userPath, ['mcp', 'servers', 0, 'headers', 'Authorization']),
        r'Bearer ${secret:codelab/mcp/gh/authorization} '
        r'${secret:codelab/mcp/gh/authorization-2}',
      );
      expectNoValues(report);
    });

    test('ключ пользовательского слоя и заголовок проектного (--all, '
        'доверенный проект): имя и имя-2 в порядке слоёв', () async {
      // Литеральный `api_key` в двух слоях одного провайдера дал бы
      // промежуточный конфликт источников ключа (R8-6) при записи первого
      // файла, поэтому второй слой несёт заголовок: имя то же, значение
      // другое.
      write(
        userPath,
        userConfig(key: sk, extra: 'trusted_projects:\n  - $cwd\n'),
      );
      write(projectPath, '''
providers:
  lm:
    headers:
      X-Gateway-Key: $ghp
''');
      final store = MemorySecretStore();
      const all = {
        ConfigLayer.user,
        ConfigLayer.project,
        ConfigLayer.projectLocal,
      };

      final dry = await run(migrator(store: store), layers: all, dryRun: true);
      expect(dry.exitCode, 0);
      expect(dry.stdoutLines, [
        '$userPath: providers.lm.api_key -> api_key_secret: codelab/lm (new)',
        '$projectPath: providers.lm.headers.X-Gateway-Key -> '
            r'${secret:codelab/lm-2} (new)',
      ]);
      expect(await store.names(), isEmpty);

      final report = await run(migrator(store: store), layers: all);

      expect(report.exitCode, 0);
      expect(await store.read('codelab/lm'), sk);
      expect(await store.read('codelab/lm-2'), ghp);
      expect(read(userPath), contains('api_key_secret: codelab/lm\n'));
      expect(
        valueAt(projectPath, ['providers', 'lm', 'headers', 'X-Gateway-Key']),
        r'${secret:codelab/lm-2}',
      );
      expectNoValues(report);
    });

    group('литеральный api_key одного провайдера в двух слоях (R8-10)', () {
      void twoLayers(String projectKey) {
        write(
          userPath,
          userConfig(key: sk, extra: 'trusted_projects:\n  - $cwd\n'),
        );
        write(projectPath, '''
providers:
  lm:
    api_key: $projectKey
''');
      }

      const all = {
        ConfigLayer.user,
        ConfigLayer.project,
        ConfigLayer.projectLocal,
      };

      test(
        '--all: итог проверяется целиком, user — имя, project — имя-2',
        () async {
          twoLayers(ghp);
          final store = MemorySecretStore();

          final dry = await run(
            migrator(store: store),
            layers: all,
            dryRun: true,
          );
          expect(dry.exitCode, 0);
          expect(dry.stdoutLines, [
            '$userPath: providers.lm.api_key -> api_key_secret: codelab/lm (new)',
            '$projectPath: providers.lm.api_key -> api_key_secret: '
                'codelab/lm-2 (new)',
          ]);

          final report = await run(migrator(store: store), layers: all);

          expect(report.exitCode, 0);
          expect(await store.read('codelab/lm'), sk);
          expect(await store.read('codelab/lm-2'), ghp);
          expect(read(userPath), contains('api_key_secret: codelab/lm\n'));
          expect(read(projectPath), contains('api_key_secret: codelab/lm-2'));
          expectNoValues(report);
        },
      );

      test('--all, равные значения: оба слоя ссылаются на одно имя', () async {
        twoLayers(sk);
        final store = MemorySecretStore();

        final report = await run(migrator(store: store), layers: all);

        expect(report.exitCode, 0);
        expect(await store.names(), ['codelab/lm']);
        expect(read(projectPath), contains('api_key_secret: codelab/lm'));
      });

      test('только user: отказ до любой записи с текстом про --all', () async {
        twoLayers(ghp);
        final userBefore = read(userPath);
        final projectBefore = read(projectPath);
        final store = MemorySecretStore();

        for (final dryRun in [false, true]) {
          final report = await run(migrator(store: store), dryRun: dryRun);

          expect(report.exitCode, 1);
          expect(report.stderrLines, [
            'secret migrate: the result would leave two key sources for '
                'providers.lm (project keeps its own); run with --all',
          ]);
          expect(report.stdoutLines, isEmpty);
          expectNoValues(report);
        }
        expect(read(userPath), userBefore);
        expect(read(projectPath), projectBefore);
        expect(await store.names(), isEmpty);
      });
    });

    test('заголовок с именем token: not migrated вместо кода 1', () async {
      write(
        userPath,
        userConfig(
          servers: ghServer(
            extra: '      headers:\n        token: "Bearer $ghp"\n',
          ),
        ),
      );
      final before = read(userPath);
      final store = MemorySecretStore();

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(
        report.stdoutLines.single,
        startsWith('not migrated: mcp.servers[gh].headers.token '),
      );
      expect(read(userPath), before);
      expect(await store.names(), isEmpty);
      expectNoValues(report);
    });

    test(
      'forMcp разных серверов совпал после нормализации: суффикс -2',
      () async {
        write(
          userPath,
          userConfig(
            servers:
                '''
mcp:
  servers:
    - name: GH
      type: http
      url: https://a.test/mcp
      token: $ghp
    - name: gh
      type: http
      url: https://b.test/mcp
      token: $ghp2
''',
          ),
        );
        final store = MemorySecretStore();

        final report = await run(migrator(store: store));

        expect(report.exitCode, 0);
        expect(await store.read('codelab/mcp/gh/token'), ghp);
        expect(await store.read('codelab/mcp/gh/token-2'), ghp2);
        expectNoValues(report);
      },
    );
  });

  group('значения, которые хранилище не примет', () {
    test(
      'PEM: not migrated … cannot be stored, остальное перенесено, код 0',
      () async {
        write(
          userPath,
          userConfig(
            key: sk,
            servers: ghServer(extra: '      env:\n        KEY: ${_pem()}\n'),
          ),
        );
        final store = MemorySecretStore();

        final report = await run(migrator(store: store));

        expect(report.exitCode, 0);
        expect(
          report.stdoutLines,
          contains(
            'not migrated: mcp.servers[gh].env.KEY cannot be stored '
            '(secret value must be a single line)',
          ),
        );
        expect(await store.names(), ['codelab/lm']);
        expect(read(userPath), contains('PRIVATE KEY'));
        expectNoValues(report);
        expect(report.stdoutLines.join('\n'), isNot(contains('MIIB')));
      },
    );

    test('больше 64 КиБ: cannot be stored (… longer than 64 KiB)', () async {
      write(
        userPath,
        userConfig(
          servers: ghServer(extra: '      token: ${'a' * (70 * 1024)}\n'),
        ),
      );
      final store = MemorySecretStore();

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(
        report.stdoutLines,
        contains(
          'not migrated: mcp.servers[gh].token cannot be stored '
          '(secret value is longer than 64 KiB)',
        ),
      );
      expect(await store.names(), isEmpty);
      expect(read(userPath), contains('token:'));
    });
  });

  group('недоверенный проект (H4)', () {
    test('значение не попадает в хранилище, файл не изменён', () async {
      write(userPath, userConfig());
      write(projectPath, '''
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    api_key: $sk
    models:
      m: {}
''');
      final before = read(projectPath);
      final store = MemorySecretStore();

      final report = await run(
        migrator(store: store),
        layers: {
          ConfigLayer.user,
          ConfigLayer.project,
          ConfigLayer.projectLocal,
        },
      );

      expect(report.exitCode, 0);
      expect(
        report.stdoutLines,
        contains('not migrated: $projectPath is an untrusted project config'),
      );
      expect(await store.names(), isEmpty);
      expect(read(projectPath), before);
      expectNoValues(report);
    });

    test('локальный слой недоверенного проекта — то же', () async {
      write(userPath, userConfig());
      write('$cwd/.codelab/config.local.yaml', '''
mcp:
  servers:
    - name: gh
      type: http
      url: https://gh.test/mcp
      token: $ghp
''');
      final store = MemorySecretStore();

      final report = await run(
        migrator(store: store),
        layers: {ConfigLayer.projectLocal},
      );

      expect(report.exitCode, 0);
      expect(
        report.stdoutLines,
        contains(
          'not migrated: $cwd/.codelab/config.local.yaml is an untrusted '
          'project config',
        ),
      );
      expect(await store.names(), isEmpty);
    });
  });

  group('сбой записи конфига после секретов (L7, шов писателя)', () {
    test('код 1, stderr называет имя, файл не изменён; повтор переиспользует '
        'секрет', () async {
      write(userPath, userConfig(key: sk));
      final before = read(userPath);
      final store = MemorySecretStore();

      final failed = await run(
        migrator(
          store: store,
          seam: (point) async {
            if (point == ConfigWriteSeam.tmpWritten) {
              throw const FileSystemException('disk is gone');
            }
          },
        ),
      );

      expect(failed.exitCode, 1);
      expect(failed.stderrLines.join('\n'), contains('codelab/lm'));
      expect(read(userPath), before);
      expect(await store.read('codelab/lm'), sk);
      expect(failed.stdoutLines, isNot(contains(startsWith('Moved'))));
      expectNoValues(failed);
      // Ни tmp, ни lock не остались.
      expect(
        Directory(home).listSync().map((e) => e.path.split('/').last).toList()
          ..sort(),
        ['config.yaml'],
      );

      final second = await run(migrator(store: store));

      expect(second.exitCode, 0);
      expect(
        second.stdoutLines,
        contains(
          'Reused secret codelab/lm for providers.lm.api_key in $userPath',
        ),
      );
      expect(read(userPath), contains('api_key_secret: codelab/lm'));
    });

    test(
      'файл изменился во время записи: одно перечитывание и повтор',
      () async {
        write(userPath, userConfig(key: sk));
        var touched = false;
        final store = MemorySecretStore();

        final report = await run(
          migrator(
            store: store,
            seam: (point) async {
              if (point == ConfigWriteSeam.tmpWritten && !touched) {
                touched = true;
                File(
                  userPath,
                ).writeAsStringSync('# edited elsewhere\n${read(userPath)}');
              }
            },
          ),
        );

        expect(report.exitCode, 0);
        expect(read(userPath), contains('# edited elsewhere'));
        expect(read(userPath), contains('api_key_secret: codelab/lm'));
        expect(await store.read('codelab/lm'), sk);
        expectNoValues(report);
      },
    );

    test(
      'сбой хранилища посреди файла: код 1, конфиг файла не пишется',
      () async {
        write(userPath, userConfig(key: sk, gatewayHeader: ghp));
        final before = read(userPath);
        final inner = MemorySecretStore();
        var writes = 0;
        final store = _HookStore(
          inner,
          onWrite: () {
            if (++writes == 2) {
              throw const SecretStoreUnavailableException(
                backend: 'memory',
                reason: 'store is gone',
              );
            }
          },
        );

        final report = await run(migrator(store: store));

        expect(report.exitCode, 1);
        expect(read(userPath), before);
        expect(report.stderrLines.join('\n'), contains('store is gone'));
        expectNoValues(report);
      },
    );
  });

  group('не переносится', () {
    test('args: не изменён, строка not migrated с тегом, код 0', () async {
      write(
        userPath,
        userConfig(
          servers:
              '''
mcp:
  servers:
    - name: gh
      type: stdio
      command: gh-mcp
      args:
        - --token
        - $ghp
''',
        ),
      );
      final before = read(userPath);
      final store = MemorySecretStore();

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(
        report.stdoutLines.single,
        startsWith(
          'not migrated: mcp.servers[gh].args[1] looks like a secret (github)',
        ),
      );
      expect(report.stdoutLines.single, contains(r"--env <NAME>='${secret:"));
      expect(read(userPath), before);
      expect(await store.names(), isEmpty);
      expect(report.canApply, isFalse);
      expectNoValues(report);
    });

    test('CODELAB_CONFIG: слой не записывается, строка not migrated', () async {
      write(userPath, userConfig());
      final extra = '${root.path}/extra.yaml';
      write(extra, '''
providers:
  lm:
    api_key: $sk
''');
      final before = read(extra);
      final store = MemorySecretStore();

      final report = await run(
        migrator(store: store),
        environment: env({'CODELAB_CONFIG': extra}),
      );

      expect(report.exitCode, 0);
      expect(report.stdoutLines, [
        'not migrated: $extra is not a writable layer',
      ]);
      expect(read(extra), before);
      expect(await store.names(), isEmpty);
      expectNoValues(report);
    });

    test(
      'недопустимый CODELAB_CONFIG: предупреждение, код не меняется',
      () async {
        write(userPath, userConfig());

        final report = await run(
          migrator(store: MemorySecretStore()),
          environment: env({'CODELAB_CONFIG': 'relative.yaml'}),
        );

        expect(report.exitCode, 0);
        expect(
          report.stderrLines.single,
          startsWith('warning: CODELAB_CONFIG ignored: '),
        );
        expect(report.stdoutLines, ['Nothing to migrate']);
      },
    );
  });

  group('загрузка и использование', () {
    test('проблема загрузки конфига — код 1 с проблемой', () async {
      write(userPath, 'providers: [unclosed\n');

      final report = await run(migrator(store: MemorySecretStore()));

      expect(report.exitCode, 1);
      expect(report.stderrLines, isNotEmpty);
    });

    test('нет каталога --cwd: код 64', () async {
      write(userPath, userConfig());

      final report = await migrator(store: MemorySecretStore()).run(
        SecretMigrationOptions(
          cwd: '${root.path}/missing',
          environment: env(),
          layers: const {ConfigLayer.user},
        ),
      );

      expect(report.exitCode, 64);
      expect(report.stderrLines, [
        'secret migrate: no such directory: ${root.path}/missing',
      ]);
    });
  });

  group('частичный сбой --all, повтор и починка (R8-6, R8-10)', () {
    const all = {
      ConfigLayer.user,
      ConfigLayer.project,
      ConfigLayer.projectLocal,
    };

    void twoLayers() {
      write(
        userPath,
        userConfig(key: sk, extra: 'trusted_projects:\n  - $cwd\n'),
      );
      write(projectPath, 'providers:\n  lm:\n    api_key: $ghp\n');
    }

    /// Шов, роняющий запись [n]-го файла (считая с 1).
    Future<void> Function(ConfigWriteSeam) failOn(int n) {
      var count = 0;
      return (point) async {
        if (point == ConfigWriteSeam.tmpWritten && ++count == n) {
          throw const FileSystemException('disk is gone');
        }
      };
    }

    void expectLoads() {
      final loaded = ConfigLoader().load(cwd: cwd, environment: env());
      expect(loaded.issues, isEmpty, reason: '${loaded.issues}');
      expect(
        loaded.warnings.where((w) => w.event == 'config.secret.in_file'),
        isEmpty,
      );
    }

    test('сбой первой записи: секреты ВСЕХ файлов уже в хранилище и названы '
        'в stderr', () async {
      twoLayers();
      final store = MemorySecretStore();

      final report = await run(
        migrator(store: store, seam: failOn(1)),
        layers: all,
      );

      expect(report.exitCode, 1);
      expect(await store.names(), ['codelab/lm', 'codelab/lm-2']);
      final text = report.stderrLines.join('\n');
      expect(text, contains('codelab/lm'));
      expect(text, contains('codelab/lm-2'));
      expectNoValues(report);
    });

    test('сбой второй записи: отчёт хранит записанный файл; повтор чинит '
        'конфиг', () async {
      twoLayers();
      final store = MemorySecretStore();

      final failed = await run(
        migrator(store: store, seam: failOn(2)),
        layers: all,
      );

      expect(failed.exitCode, 1);
      expect(failed.movedAny, isTrue);
      expect(failed.items.whereType<SecretMovedItem>(), hasLength(1));
      expect(failed.stderrLines.join('\n'), contains('codelab/lm-2'));
      // Пользовательский слой уже со ссылкой, проектный — с литералом:
      // конфиг не загружается (R8-6).
      expect(
        ConfigLoader().load(cwd: cwd, environment: env()).issues,
        isNotEmpty,
      );

      final retry = await run(migrator(store: store), layers: all);

      expect(retry.exitCode, 0, reason: retry.stderrLines.join('\n'));
      expect(read(projectPath), contains('api_key_secret: codelab/lm-2'));
      expect(await store.read('codelab/lm-2'), ghp);
      expectLoads();
      expectNoValues(retry);
    });

    test('исходная пара api_key_secret в user и литерал в project: '
        'migrate --project чинит', () async {
      write(userPath, '''
trusted_projects:
  - $cwd
providers:
  lm:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: codelab/lm
    models:
      m: {}
agent:
  default_model: lm/m
''');
      write(projectPath, 'providers:\n  lm:\n    api_key: $ghp\n');
      final store = MemorySecretStore({'codelab/lm': sk});

      final report = await run(
        migrator(store: store),
        layers: {ConfigLayer.project},
      );

      expect(report.exitCode, 0, reason: report.stderrLines.join('\n'));
      expect(await store.read('codelab/lm'), sk);
      expect(await store.read('codelab/lm-2'), ghp);
      expect(read(projectPath), contains('api_key_secret: codelab/lm-2'));
      expectLoads();
    });

    test('конфликт источников без правок: код 1, как и раньше', () async {
      write(
        userPath,
        userConfig(extra: 'trusted_projects:\n  - $cwd\n').replaceFirst(
          '    models:',
          '    api_key_secret: codelab/lm\n    models:',
        ),
      );
      write(projectPath, 'providers:\n  lm:\n    api_key: plain\n');

      final report = await run(migrator(store: MemorySecretStore()));

      expect(report.exitCode, 1);
      expect(report.stderrLines, isNotEmpty);
    });
  });

  group('хранилище и порядок проверок (R8-10)', () {
    test('отказ R8-10 случается до единого чтения хранилища', () async {
      write(
        userPath,
        userConfig(
          key: sk,
          extra: 'trusted_projects:\n  - $cwd\n',
        ).replaceFirst(
          '    models:',
          "    headers:\n      X-Ref: '\${secret:codelab/lm}'\n    models:",
        ),
      );
      write(projectPath, 'providers:\n  lm:\n    api_key: $ghp\n');
      final store = _SpyStore({'codelab/lm': 'old-value-0001'});

      final report = await run(migrator(store: store));

      expect(report.exitCode, 1);
      expect(report.stderrLines.single, contains('two key sources'));
      expect(store.reads, isEmpty);
    });

    test('значение вместо имени в ссылке не читается как имя', () async {
      write(userPath, '''
providers:
  lm:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: $ghp
    headers:
      X-Ref: "\${secret:$ghp2}"
    models:
      m: {}
agent:
  default_model: lm/m
''');
      final store = _SpyStore();

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0, reason: report.stderrLines.join('\n'));
      expect(store.reads.where((n) => n.contains('ghp_')), isEmpty);
    });

    test('имя занято тем же провайдером, секрета в хранилище нет: берётся '
        '-2, codelab/lm не создаётся', () async {
      write(userPath, '''
trusted_projects:
  - $cwd
providers:
  lm:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: codelab/lm
    models:
      m: {}
agent:
  default_model: lm/m
''');
      write(projectPath, 'providers:\n  lm:\n    api_key: $ghp\n');
      final store = MemorySecretStore();

      final report = await run(
        migrator(store: store),
        layers: {ConfigLayer.project},
      );

      expect(report.exitCode, 0, reason: report.stderrLines.join('\n'));
      expect(await store.names(), ['codelab/lm-2']);
      expect(read(projectPath), contains('api_key_secret: codelab/lm-2'));
    });
  });

  group('отказы и тексты', () {
    test('слой CODELAB_CONFIG не советует --all', () async {
      write(userPath, userConfig(key: sk));
      final extra = '${root.path}/extra.yaml';
      write(extra, 'providers:\n  lm:\n    api_key: $ghp\n');
      final before = read(userPath);

      final report = await run(
        migrator(store: MemorySecretStore()),
        environment: env({'CODELAB_CONFIG': extra}),
      );

      expect(report.exitCode, 1);
      expect(report.stderrLines, [
        'secret migrate: the result would leave two key sources for '
            'providers.lm (CODELAB_CONFIG keeps its own); remove the key '
            'from CODELAB_CONFIG',
      ]);
      expect(read(userPath), before);
      expectNoValues(report);
    });

    test('api_key с литералом и подстановкой: not migrated, файл и хранилище '
        'не тронуты', () async {
      write(userPath, userConfig(key: '"$ghp \${X}"'));
      final before = read(userPath);
      final store = MemorySecretStore();

      final report = await run(migrator(store: store));

      expect(report.exitCode, 0);
      expect(report.stdoutLines, [
        'not migrated: providers.lm.api_key mixes a literal with a '
            'substitution; move it to api_key_secret manually',
      ]);
      expect(read(userPath), before);
      expect(await store.names(), isEmpty);
      expectNoValues(report);
    });

    test('конфликт с хранилищем называет ссылающиеся ключи', () async {
      write(
        userPath,
        userConfig(
          servers:
              '''
mcp:
  servers:
    - name: GH
      type: http
      url: https://a.test/mcp
      headers:
        Authorization: "\${secret:codelab/mcp/gh/authorization}"
    - name: gh
      type: http
      url: https://b.test/mcp
      headers:
        Authorization: "Bearer $ghp"
''',
        ),
      );
      final store = MemorySecretStore({
        'codelab/mcp/gh/authorization': 'old-value-0001',
      });

      final report = await run(migrator(store: store));

      expect(report.exitCode, 1);
      expect(report.stderrLines, [
        'secret codelab/mcp/gh/authorization already exists with a '
            'different value; rerun with --force to replace it; also referenced '
            'by: mcp.servers[GH].headers.Authorization (user)',
      ]);
      expect(
        await store.read('codelab/mcp/gh/authorization'),
        'old-value-0001',
      );
    });

    test('бэкенд env и совпавшие forMcp: подсказка называет оба имени '
        'переменных; на Windows без secrets.backend', () async {
      write(
        userPath,
        userConfig(
          servers:
              '''
mcp:
  servers:
    - name: GH
      type: http
      url: https://a.test/mcp
      token: $ghp
    - name: gh
      type: http
      url: https://b.test/mcp
      token: $ghp2
''',
        ),
      );

      final linux = await run(migrator());
      final windows = await run(migrator(platform: 'windows'));

      for (final report in [linux, windows]) {
        expect(report.exitCode, 1);
        final text = report.stderrLines.join('\n');
        expect(text, contains('CODELAB_SECRET_CODELAB_MCP_GH_TOKEN'));
        expect(text, contains('CODELAB_SECRET_CODELAB_MCP_GH_TOKEN_2'));
      }
      expect(
        windows.stderrLines.join('\n'),
        isNot(contains('secrets.backend')),
      );
    });

    test('файл испорчен во время записи: повтор даёт штатный отказ, а не '
        'исключение', () async {
      write(userPath, userConfig(key: sk));
      var touched = false;

      final report = await run(
        migrator(
          store: MemorySecretStore(),
          seam: (point) async {
            if (point == ConfigWriteSeam.tmpWritten && !touched) {
              touched = true;
              File(userPath).writeAsStringSync('providers: [unclosed\n');
            }
          },
        ),
      );

      expect(report.exitCode, 1);
      expect(report.stderrLines, isNotEmpty);
      expectNoValues(report);
    });
  });
}

/// Блок PEM в виде YAML-блочного скаляра (многострочное значение).
String _pem() =>
    '|\n          -----BEGIN PRIVATE KEY-----\n'
    '          MIIBVQIBADANBgkqhkiG9w0BAQEFAASC\n'
    '          -----END PRIVATE KEY-----';

/// Хранилище-обёртка: вызывает [onWrite] перед каждой записью (порядок
/// «значение в хранилище раньше правки файла», сбои, счётчик записей).
final class _HookStore implements DescribedSecretStore {
  _HookStore(this._inner, {required this.onWrite});

  final MemorySecretStore _inner;
  final void Function() onWrite;

  @override
  SecretBackendInfo get backend => _inner.backend;

  @override
  Future<String?> read(String name) => _inner.read(name);

  @override
  Future<void> write(String name, String value) {
    onWrite();
    return _inner.write(name, value);
  }

  @override
  Future<void> delete(String name) => _inner.delete(name);

  @override
  Future<List<String>> names() => _inner.names();
}

/// Хранилище-шпион: помнит имена, которые читали.
final class _SpyStore implements DescribedSecretStore {
  _SpyStore([Map<String, String> initial = const {}])
    : _inner = MemorySecretStore(initial);

  final MemorySecretStore _inner;
  final reads = <String>[];

  @override
  SecretBackendInfo get backend => _inner.backend;

  @override
  Future<String?> read(String name) {
    reads.add(name);
    return _inner.read(name);
  }

  @override
  Future<void> write(String name, String value) => _inner.write(name, value);

  @override
  Future<void> delete(String name) => _inner.delete(name);

  @override
  Future<List<String>> names() => _inner.names();
}
