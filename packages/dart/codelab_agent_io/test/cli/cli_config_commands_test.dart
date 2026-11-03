import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_io/src/cli/config_edit_runner.dart'
    show ConfigFileLayer;
import 'package:codelab_agent_io/src/config/config_paths.dart'
    show configLayerFilePath;
import 'package:codelab_agent_io/src/config/config_writer.dart'
    show ConfigWriteSeam;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/fake_secret_input.dart';
import '../support/fake_secret_process_runner.dart';

/// Подкоманды записи и чтения конфига `config path|get|set|unset`,
/// `provider add|list|remove`, `mcp add|list|remove` (agent-configuration
/// «Подкоманды записи и чтения конфига», все сценарии; design.md change
/// `add-config-writer-and-reload`, D6, D15; задача 4.1).
///
/// Общая реализация `ConfigCommands`, `ProviderCommands`, `McpServerCommands`
/// для `codelab-agent` и `codelab`: тексты и коды выхода. Тест не читает
/// настоящий `~/.codelab`: `CODELAB_HOME` и окружение передаются явно, ввод
/// ключа — фейк, хранилище — `MemorySecretStore` или бэкенд `file` во
/// временном каталоге; значения «секретов» выдуманные.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late String userPath;

  const providers = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''';

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  String read(String path) => File(path).readAsStringSync();

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('cli_config_commands')
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

  Map<String, String> env([Map<String, String> extra = const {}]) => {
    'CODELAB_HOME': home,
    ...extra,
  };

  ConfigCommands configCommands({
    Future<void> Function(ConfigWriteSeam point)? seam,
  }) =>
      ConfigCommands(processRunner: FakeSecretProcessRunner(), writeSeam: seam);

  Future<ConfigCommandResult> setKey(
    String key,
    String value, {
    ConfigFileLayer layer = ConfigFileLayer.user,
    ConfigCommands? commands,
    Map<String, String>? environment,
  }) => (commands ?? configCommands()).set(
    ConfigSetOptions(
      key: key,
      value: value,
      cwd: cwd,
      environment: environment ?? env(),
      project: layer == ConfigFileLayer.project,
      local: layer == ConfigFileLayer.local,
    ),
  );

  Future<ConfigCommandResult> getKey(
    String key, {
    ConfigGetLayer layer = ConfigGetLayer.merged,
    Map<String, String>? environment,
  }) => configCommands().get(
    ConfigGetOptions(
      key: key,
      cwd: cwd,
      environment: environment ?? env(),
      layer: layer,
    ),
  );

  Future<ConfigCommandResult> unsetKey(
    String key, {
    ConfigFileLayer layer = ConfigFileLayer.user,
  }) => configCommands().unset(
    ConfigUnsetOptions(
      key: key,
      cwd: cwd,
      environment: env(),
      project: layer == ConfigFileLayer.project,
      local: layer == ConfigFileLayer.local,
    ),
  );

  String allOutput(ConfigCommandResult result) =>
      [...result.stdout, ...result.stderr].join('\n');

  group('config path', () {
    test('без флагов: слои user, project, local и CODELAB_CONFIG с пометкой '
        'exists/missing', () async {
      write(userPath, providers);
      final extra = '${root.path}/extra.yaml';
      write(extra, providers);

      final result = await configCommands().path(
        ConfigPathOptions(
          cwd: cwd,
          environment: env({'CODELAB_CONFIG': extra}),
        ),
      );

      expect(result.exitCode, 0);
      expect(result.stdout, [
        'user: $userPath (exists)',
        'project: $cwd/.codelab/config.yaml (missing)',
        'local: $cwd/.codelab/config.local.yaml (missing)',
        'CODELAB_CONFIG: $extra (exists)',
      ]);
      // Подкоманда ничего не создаёт.
      expect(Directory('$cwd/.codelab').existsSync(), isFalse);
    });

    test('без CODELAB_CONFIG четвёртой строки нет', () async {
      final result = await configCommands().path(
        ConfigPathOptions(cwd: cwd, environment: env()),
      );

      expect(result.exitCode, 0);
      expect(result.stdout, [
        'user: $userPath (missing)',
        'project: $cwd/.codelab/config.yaml (missing)',
        'local: $cwd/.codelab/config.local.yaml (missing)',
      ]);
    });

    test('--project и --local: только путь файла слоя', () async {
      final project = await configCommands().path(
        ConfigPathOptions(cwd: cwd, environment: env(), project: true),
      );
      final local = await configCommands().path(
        ConfigPathOptions(cwd: cwd, environment: env(), local: true),
      );

      expect(project.stdout, ['$cwd/.codelab/config.yaml']);
      expect(local.stdout, ['$cwd/.codelab/config.local.yaml']);
    });
  });

  group('config set и get', () {
    test(
      'set в пустой CODELAB_HOME: путь, прежняя проблема как warning, '
      'затем get: значение и слой user (сценарий «config set и get»)',
      () async {
        final set = await setKey('budget.max_steps', '40');

        expect(set.exitCode, 0, reason: allOutput(set));
        expect(set.stdout.first, 'Updated budget.max_steps in $userPath');
        expect(set.stdout, contains('warning: agent.default_model: required'));
        expect(read(userPath), contains('max_steps: 40'));

        final get = await getKey('budget.max_steps');

        expect(get.exitCode, 0, reason: allOutput(get));
        expect(get.stdout, ['40', 'layer: user']);
      },
    );

    test('set сохраняет комментарии и порядок файла', () async {
      write(
        userPath,
        '# keep me\n$providers\nbudget:\n  max_steps: 5 # five\n',
      );

      final result = await setKey('budget.max_steps', '7');

      expect(result.exitCode, 0, reason: allOutput(result));
      final text = read(userPath);
      expect(text, contains('# keep me'));
      expect(text, contains('max_steps: 7 # five'));
    });

    test('set --project и --local пишут в файлы проекта', () async {
      write(userPath, providers);

      final project = await setKey(
        'agent.effort',
        'low',
        layer: ConfigFileLayer.project,
      );
      final local = await setKey(
        'agent.effort',
        'high',
        layer: ConfigFileLayer.local,
      );

      expect(project.exitCode, 0, reason: allOutput(project));
      expect(local.exitCode, 0, reason: allOutput(local));
      expect(project.stdout.first, contains('$cwd/.codelab/config.yaml'));
      expect(read('$cwd/.codelab/config.yaml'), contains('effort: low'));
      expect(read('$cwd/.codelab/config.local.yaml'), contains('effort: high'));
      expect(read(userPath), isNot(contains('effort')));
    });

    test('ключ, требующий перезапуска, даёт строку note', () async {
      write(userPath, providers);

      final result = await setKey('permissions.mode', 'standard');

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(result.stdout, [
        'Updated permissions.mode in $userPath',
        'note: restart the agent to apply: permissions.mode',
      ]);
    });

    test('неизвестный ключ: код 64, подсказка ближайшего, файл не создан '
        '(сценарий «Неизвестный ключ set»)', () async {
      final result = await setKey('budget.max_stepz', '10');

      expect(result.exitCode, 64);
      expect(result.stderr.join('\n'), contains('budget.max_steps'));
      expect(File(userPath).existsSync(), isFalse);
    });

    test('неверное значение (ConfigValueException): код 64, значение не '
        'цитируется', () async {
      write(userPath, providers);
      final before = read(userPath);

      final result = await setKey('budget.max_steps', 'sk-test-abc');

      expect(result.exitCode, 64);
      expect(result.stderr.join('\n'), contains('budget.max_steps'));
      expect(allOutput(result), isNot(contains('sk-test-abc')));
      expect(read(userPath), before);
    });

    test('секрет значением: код 1, подсказка codelab secret set, значения '
        'нет ни в выводе, ни в файле', () async {
      final result = await setKey('providers.gw.api_key', 'sk-test-12345');

      expect(result.exitCode, 1);
      expect(allOutput(result), contains('codelab secret set'));
      expect(allOutput(result), isNot(contains('sk-test-12345')));
      expect(File(userPath).existsSync(), isFalse);
    });

    test(
      'литеральный токен в mcp.servers через set: код 1, файл цел',
      () async {
        write(userPath, providers);
        final before = read(userPath);

        final result = await setKey(
          'mcp.servers',
          '[{"name":"gh","type":"http","url":"https://h",'
              '"headers":{"Authorization":"Bearer lit-123"}}]',
        );

        expect(result.exitCode, 1);
        expect(allOutput(result), isNot(contains('lit-123')));
        expect(read(userPath), before);
      },
    );

    test('get не раскрывает \${VAR} при любом слое, включая merged '
        '(сценарий «get не раскрывает переменную»)', () async {
      write(userPath, '''
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.test/v1
    headers:
      X-Token: "\${GW_TOKEN}"
    models:
      m: {}
agent:
  default_model: gw/m
''');
      final environment = env({'GW_TOKEN': 't-123'});

      for (final layer in [ConfigGetLayer.merged, ConfigGetLayer.user]) {
        final result = await getKey(
          'providers.gw.headers',
          layer: layer,
          environment: environment,
        );

        expect(result.exitCode, 0, reason: allOutput(result));
        expect(result.stdout.join('\n'), contains(r'${GW_TOKEN}'));
        expect(allOutput(result), isNot(contains('t-123')));
        expect(result.stdout.last, 'layer: user');
      }
    });

    test('get --layer project читает только файл проекта', () async {
      write(userPath, '$providers\nbudget:\n  max_steps: 5\n');
      write('$cwd/.codelab/config.yaml', 'budget:\n  max_steps: 6\n');

      final merged = await getKey('budget.max_steps');
      final user = await getKey('budget.max_steps', layer: ConfigGetLayer.user);
      final project = await getKey(
        'budget.max_steps',
        layer: ConfigGetLayer.project,
      );
      final local = await getKey(
        'budget.max_steps',
        layer: ConfigGetLayer.local,
      );

      expect(merged.stdout, ['6', 'layer: project']);
      expect(user.stdout, ['5', 'layer: user']);
      expect(project.stdout, ['6', 'layer: project']);
      expect(local.exitCode, 1);
      expect(local.stdout, isEmpty);
    });

    test('get ключа, которого нет: код 1 и объяснение в stderr', () async {
      write(userPath, providers);

      final result = await getKey('budget.max_steps');

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(result.stderr.join('\n'), contains('budget.max_steps'));
    });

    test('get неразбираемого пути: код 64', () async {
      final result = await getKey('providers..kind');

      expect(result.exitCode, 64);
    });

    test('повтор при конфликте: первая запись конфликтует с ручной правкой, '
        'вторая проходит и сохраняет правку', () async {
      write(userPath, providers);
      var writes = 0;
      final commands = configCommands(
        seam: (point) async {
          if (point == ConfigWriteSeam.tmpWritten && ++writes == 1) {
            write(userPath, '$providers# edited by hand\n');
          }
        },
      );

      final result = await setKey('budget.max_steps', '9', commands: commands);

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(writes, 2);
      expect(read(userPath), contains('# edited by hand'));
      expect(read(userPath), contains('max_steps: 9'));
    });

    test(
      'второй конфликт подряд: код 1 и текст про повторный запуск',
      () async {
        write(userPath, providers);
        var writes = 0;
        final commands = configCommands(
          seam: (point) async {
            if (point == ConfigWriteSeam.tmpWritten) {
              write(userPath, '$providers# edit ${++writes}\n');
            }
          },
        );

        final result = await setKey(
          'budget.max_steps',
          '9',
          commands: commands,
        );

        expect(result.exitCode, 1);
        expect(writes, 2);
        expect(
          result.stderr,
          contains(
            'config file changed during the edit; run the command again',
          ),
        );
        expect(read(userPath), isNot(contains('max_steps')));
      },
    );
  });

  group('config unset', () {
    test('удаляет запрещённый ключ из невалидного файла, значение не '
        'печатается (сценарий «unset удаляет запрещённый ключ»)', () async {
      write(userPath, '''
providers:
  openai:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key: sk-1
    models:
      m: {}
agent:
  default_model: openai/m
''');

      final result = await unsetKey('providers.openai.api_key');

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(
        result.stdout.first,
        'Removed providers.openai.api_key from $userPath',
      );
      expect(read(userPath), isNot(contains('api_key')));
      expect(allOutput(result), isNot(contains('sk-1')));
    });

    test('unset api_key при прежних base_url и каталоге: код 0, прежние '
        'проблемы — предупреждения (R3-1, решение 2026-11-03)', () async {
      write(userPath, '''
agent:
  default_model: lm/m
providers:
  lm:
    api_key: sk-fake-1
    base_url: "https://u:p@ss@host/v1"
    kind: openai-compatible
    models:
      m:
        context_window: 8192
''');

      final result = await unsetKey('providers.lm.api_key');

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(
        result.stdout.first,
        'Removed providers.lm.api_key from $userPath',
      );
      final warnings = [
        for (final line in result.stdout)
          if (line.startsWith('warning:')) line,
      ];
      expect(
        warnings.any((w) => w.contains('providers.lm.base_url')),
        isTrue,
        reason: allOutput(result),
      );
      expect(
        warnings.any((w) => w.contains('agent.default_model')),
        isTrue,
        reason: allOutput(result),
      );
      expect(read(userPath), isNot(contains('api_key')));
      expect(allOutput(result), isNot(contains('sk-fake-1')));
    });

    test('ключ со значением null задан: unset удаляет его, а не молчит '
        '(ревью итерации 4, safety M)', () async {
      for (final empty in ['', ' ~', ' null']) {
        write(userPath, '${providers}budget:\n  max_steps:$empty\n');

        final result = await unsetKey('budget.max_steps');

        expect(result.exitCode, 0, reason: allOutput(result));
        expect(
          result.stdout.first,
          'Removed budget.max_steps from $userPath',
          reason: 'значение "$empty"',
        );
        expect(read(userPath), isNot(contains('max_steps')));
      }
    });

    test('ключа в файле нет: код 0, файл не меняется', () async {
      write(userPath, providers);
      final before = read(userPath);

      final result = await unsetKey('budget.max_steps');

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(result.stdout, ['budget.max_steps is not set in $userPath']);
      expect(read(userPath), before);
    });
  });

  group('provider add', () {
    ProviderAddOptions addOf({
      String id = 'gw',
      String? kind = 'openai-compatible',
      String? baseUrl = 'https://x/v1',
      String? model = 'm',
      String? contextWindow = '8192',
      String? apiKeySecret,
      String? apiKeyEnv,
      bool stdin = false,
      bool makeDefault = false,
      ConfigFileLayer layer = ConfigFileLayer.user,
    }) => ProviderAddOptions(
      id: id,
      cwd: cwd,
      environment: env(),
      kind: kind,
      baseUrl: baseUrl,
      model: model,
      contextWindow: contextWindow,
      apiKeySecret: apiKeySecret,
      apiKeyEnv: apiKeyEnv,
      apiKeyStdin: stdin,
      makeDefault: makeDefault,
      project: layer == ConfigFileLayer.project,
      local: layer == ConfigFileLayer.local,
    );

    ProviderCommands providerCommands({
      MemorySecretStore? store,
      Future<void> Function(ConfigWriteSeam point)? seam,
    }) => ProviderCommands(
      processRunner: FakeSecretProcessRunner(),
      openStore: store == null
          ? null
          : ({required choice, required environment, required home}) => store,
      writeSeam: seam,
    );

    YamlMap parsed() => loadYaml(read(userPath)) as YamlMap;

    test(
      'без ключа: провайдер, модель и --default записаны одной правкой',
      () async {
        final result = await providerCommands().add(
          addOf(makeDefault: true),
          FakeSecretInput(''),
        );

        expect(result.exitCode, 0, reason: allOutput(result));
        expect(result.stdout.first, 'Updated providers.gw in $userPath');
        final config = parsed();
        final gw = (config['providers'] as YamlMap)['gw'] as YamlMap;
        expect(gw['kind'], 'openai-compatible');
        expect(gw['base_url'], 'https://x/v1');
        expect(
          ((gw['models'] as YamlMap)['m'] as YamlMap)['context_window'],
          8192,
        );
        expect((config['agent'] as YamlMap)['default_model'], 'gw/m');
      },
    );

    test('без --default в пустом CODELAB_HOME: warning о прежней проблеме, '
        'код 0', () async {
      final result = await providerCommands().add(addOf(), FakeSecretInput(''));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(result.stdout, contains('warning: agent.default_model: required'));
    });

    test('идентификатор модели с точкой пишется одним ключом', () async {
      final result = await providerCommands().add(
        addOf(model: 'qwen2.5-coder'),
        FakeSecretInput(''),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      final gw = (parsed()['providers'] as YamlMap)['gw'] as YamlMap;
      expect((gw['models'] as YamlMap).keys, ['qwen2.5-coder']);
    });

    test('--api-key-secret и --api-key-env пишут только имя', () async {
      final secret = await providerCommands().add(
        addOf(apiKeySecret: 'codelab/gw'),
        FakeSecretInput(''),
      );
      final env2 = await providerCommands().add(
        addOf(id: 'gw2', apiKeyEnv: 'GW2_KEY'),
        FakeSecretInput(''),
      );

      expect(secret.exitCode, 0, reason: allOutput(secret));
      expect(env2.exitCode, 0, reason: allOutput(env2));
      final map = parsed()['providers'] as YamlMap;
      expect((map['gw'] as YamlMap)['api_key_secret'], 'codelab/gw');
      expect((map['gw2'] as YamlMap)['api_key_env'], 'GW2_KEY');
    });

    test(
      'нет --kind, --model или --context-window: код 64, файл не создан',
      () async {
        for (final options in [
          addOf(kind: null),
          addOf(model: null),
          addOf(contextWindow: null),
        ]) {
          final result = await providerCommands().add(
            options,
            FakeSecretInput(''),
          );

          expect(result.exitCode, 64, reason: allOutput(result));
        }
        expect(File(userPath).existsSync(), isFalse);
      },
    );

    test('неверные значения флагов: код 64', () async {
      for (final options in [
        addOf(kind: 'nope'),
        addOf(contextWindow: 'big'),
        addOf(id: 'Bad Id'),
        addOf(apiKeyEnv: 'not a var'),
      ]) {
        final result = await providerCommands().add(
          options,
          FakeSecretInput(''),
        );

        expect(result.exitCode, 64, reason: allOutput(result));
      }
      expect(File(userPath).existsSync(), isFalse);
    });

    test('несовместимые флаги ключа: код 64, ввод не читается', () async {
      final input = FakeSecretInput('sk-test-1');

      final result = await providerCommands().add(
        addOf(apiKeySecret: 'codelab/gw', stdin: true),
        input,
      );

      expect(result.exitCode, 64);
      expect(input.reads, 0);
      expect(File(userPath).existsSync(), isFalse);
    });

    test('--api-key-stdin на бэкенде file: ключ в secrets.yaml, в конфиге '
        'только имя (сценарий «provider add с ключом из stdin»)', () async {
      const key = 'sk-test-0123456789abcdef';
      write(userPath, 'secrets:\n  backend: file\n');

      final result = await providerCommands().add(
        addOf(stdin: true, makeDefault: true),
        FakeSecretInput('$key\n'),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(read('$home/secrets.yaml'), contains('codelab/gw'));
      final text = read(userPath);
      expect(text, contains('api_key_secret: codelab/gw'));
      expect(text, contains('default_model: gw/m'));
      expect(text, isNot(contains(key)));
      expect(allOutput(result), isNot(contains(key)));
      expect(allOutput(result), isNot(contains('sk-test')));
    });

    test('--api-key-stdin при существующем секрете: warning о замене, '
        'значения нет в выводе', () async {
      final store = MemorySecretStore({'codelab/gw': 'sk-old-111'});

      final result = await providerCommands(
        store: store,
      ).add(addOf(stdin: true), FakeSecretInput('sk-new-222\n'));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(
        result.stdout,
        contains('warning: replaced the existing secret codelab/gw'),
      );
      expect(await store.read('codelab/gw'), 'sk-new-222');
      expect(allOutput(result), isNot(contains('sk-old-111')));
      expect(allOutput(result), isNot(contains('sk-new-222')));
    });

    test('новый секрет: warning о замене нет', () async {
      final store = MemorySecretStore();

      final result = await providerCommands(
        store: store,
      ).add(addOf(stdin: true), FakeSecretInput('sk-new-222\n'));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(allOutput(result), isNot(contains('replaced')));
      expect(await store.read('codelab/gw'), 'sk-new-222');
    });

    test('бэкенд env: код 1, подсказка, ключ не запрашивается, конфиг не '
        'создан (сценарий «provider add при бэкенде env»)', () async {
      final input = FakeSecretInput('sk-test-1');

      final result = await providerCommands().add(addOf(stdin: true), input);

      expect(result.exitCode, 1, reason: allOutput(result));
      final err = result.stderr.join('\n');
      expect(err, contains('secrets.backend: file'));
      expect(err, contains('CODELAB_SECRET_CODELAB_GW'));
      expect(input.reads, 0);
      expect(File(userPath).existsSync(), isFalse);
    });

    test('кандидат конфига невалиден: код 1, ключ не запрашивается и не '
        'сохраняется', () async {
      // Файл CODELAB_CONFIG (выше слоя user) уже задаёт api_key_env того же
      // провайдера: источник ключа слоя user заменить нельзя, итог слоёв —
      // оба поля сразу.
      write('${root.path}/extra.yaml', '''
providers:
  gw:
    api_key_env: GW_KEY
''');
      write(userPath, providers);
      final before = read(userPath);
      final store = MemorySecretStore();
      final input = FakeSecretInput('sk-test-1');

      final result = await providerCommands(store: store).add(
        ProviderAddOptions(
          id: 'gw',
          cwd: cwd,
          environment: env({'CODELAB_CONFIG': '${root.path}/extra.yaml'}),
          kind: 'openai-compatible',
          baseUrl: 'https://x/v1',
          model: 'm',
          contextWindow: '8192',
          apiKeyStdin: true,
        ),
        input,
      );

      expect(result.exitCode, 1, reason: allOutput(result));
      expect(input.reads, 0);
      expect(await store.names(), isEmpty);
      expect(read(userPath), before);
    });

    group('смена источника ключа (R4-4)', () {
      const withEnv = '''
providers:
  gw:
    kind: openai-compatible
    base_url: https://x/v1
    api_key_env: GW_KEY
    models:
      m: {}
agent:
  default_model: gw/m
''';

      YamlMap gw() => (parsed()['providers'] as YamlMap)['gw'] as YamlMap;

      test(
        'env -> stdin: api_key_env удалён, в файле только api_key_secret',
        () async {
          write(userPath, '$withEnv\nsecrets:\n  backend: file\n');

          final result = await providerCommands().add(
            addOf(stdin: true),
            FakeSecretInput('sk-test-5\n'),
          );

          expect(result.exitCode, 0, reason: allOutput(result));
          expect(gw()['api_key_secret'], 'codelab/gw');
          expect(gw().containsKey('api_key_env'), isFalse);
        },
      );

      test('secret -> env: api_key_secret удалён', () async {
        write(
          userPath,
          withEnv.replaceAll(
            'api_key_env: GW_KEY',
            'api_key_secret: codelab/old',
          ),
        );

        final result = await providerCommands().add(
          addOf(apiKeyEnv: 'NEW_KEY'),
          FakeSecretInput(''),
        );

        expect(result.exitCode, 0, reason: allOutput(result));
        expect(gw()['api_key_env'], 'NEW_KEY');
        expect(gw().containsKey('api_key_secret'), isFalse);
      });

      test('env -> secret по имени', () async {
        write(userPath, withEnv);

        final result = await providerCommands().add(
          addOf(apiKeySecret: 'codelab/gw'),
          FakeSecretInput(''),
        );

        expect(result.exitCode, 0, reason: allOutput(result));
        expect(gw()['api_key_secret'], 'codelab/gw');
        expect(gw().containsKey('api_key_env'), isFalse);
      });

      test(
        'уже битый конфиг с обоими полями: после add остаётся одно',
        () async {
          write(
            userPath,
            withEnv.replaceFirst(
              'api_key_env: GW_KEY',
              'api_key_env: GW_KEY\n    api_key_secret: codelab/old',
            ),
          );

          final result = await providerCommands().add(
            addOf(apiKeyEnv: 'NEW_KEY'),
            FakeSecretInput(''),
          );

          expect(result.exitCode, 0, reason: allOutput(result));
          expect(gw()['api_key_env'], 'NEW_KEY');
          expect(gw().containsKey('api_key_secret'), isFalse);
        },
      );

      test('без флагов ключа прежний источник не трогается', () async {
        write(userPath, withEnv);

        final result = await providerCommands().add(
          addOf(),
          FakeSecretInput(''),
        );

        expect(result.exitCode, 0, reason: allOutput(result));
        expect(gw()['api_key_env'], 'GW_KEY');
      });

      test('повтор при конфликте строит правки от свежего снимка', () async {
        write(userPath, withEnv);
        var edited = false;

        final result = await providerCommands(
          seam: (point) async {
            if (point == ConfigWriteSeam.tmpWritten && !edited) {
              edited = true;
              // Рука заменила источник на secret между чтением и записью.
              write(
                userPath,
                withEnv.replaceAll(
                  'api_key_env: GW_KEY',
                  'api_key_secret: codelab/hand',
                ),
              );
            }
          },
        ).add(addOf(apiKeyEnv: 'NEW_KEY'), FakeSecretInput(''));

        expect(result.exitCode, 0, reason: allOutput(result));
        expect(gw()['api_key_env'], 'NEW_KEY');
        expect(gw().containsKey('api_key_secret'), isFalse);
      });
    });

    test('нет нескольких обязательных флагов: одна строка со всеми '
        'недостающими (ревью итерации 4, arch L8)', () async {
      final result = await providerCommands().add(
        addOf(kind: null, model: null, contextWindow: null),
        FakeSecretInput(''),
      );
      final onlyModel = await providerCommands().add(
        addOf(model: null),
        FakeSecretInput(''),
      );

      expect(result.exitCode, 64);
      expect(result.stderr, [
        'provider add: missing required options: --kind, --model, '
            '--context-window',
      ]);
      expect(onlyModel.stderr, [
        'provider add: missing required options: --model',
      ]);
    });

    test('исключение шага записи после сохранения ключа: код 1, текст '
        'называет секрет и тип исключения, не его сообщение', () async {
      write(userPath, providers);
      final store = MemorySecretStore();

      final result = await providerCommands(
        store: store,
        seam: (point) async {
          if (point == ConfigWriteSeam.tmpWritten) {
            throw StateError('boom sk-test-88');
          }
        },
      ).add(addOf(stdin: true), FakeSecretInput('sk-test-88\n'));

      expect(result.exitCode, 1, reason: allOutput(result));
      final err = result.stderr.join('\n');
      expect(err, contains('the secret codelab/gw was stored'));
      expect(err, contains('StateError'));
      expect(allOutput(result), isNot(contains('sk-test-88')));
      expect(await store.read('codelab/gw'), 'sk-test-88');
    });

    test(
      'сбой записи конфига после сохранения ключа называет секрет',
      () async {
        write(userPath, providers);
        var writes = 0;
        final store = MemorySecretStore();

        final result = await providerCommands(
          store: store,
          seam: (point) async {
            if (point == ConfigWriteSeam.tmpWritten) {
              write(userPath, '$providers# edit ${++writes}\n');
            }
          },
        ).add(addOf(stdin: true), FakeSecretInput('sk-test-77\n'));

        expect(result.exitCode, 1, reason: allOutput(result));
        expect(
          result.stderr.join('\n'),
          contains(
            'the secret codelab/gw was stored; the config was not changed',
          ),
        );
        expect(await store.read('codelab/gw'), 'sk-test-77');
        expect(allOutput(result), isNot(contains('sk-test-77')));
      },
    );
  });

  group('provider list и remove', () {
    const listed = '''
providers:
  gw:
    kind: openai-compatible
    base_url: https://u:pw@gw.test/v1
    api_key_secret: codelab/gw
    models:
      m: {}
      n: {}
  loc:
    kind: openai-compatible
    base_url: http://localhost:1/v1
    api_key_env: LOC_KEY
    models:
      m: {}
agent:
  default_model: gw/m
''';

    ProviderCommands commandsOver(MemorySecretStore store) => ProviderCommands(
      processRunner: FakeSecretProcessRunner(),
      openStore: ({required choice, required environment, required home}) =>
          store,
    );

    Future<ConfigCommandResult> list(
      MemorySecretStore store, {
      Map<String, String>? environment,
    }) => commandsOver(
      store,
    ).list(ProviderListOptions(cwd: cwd, environment: environment ?? env()));

    test('Secrets первой строкой, по строке на провайдера, источник ключа '
        'без значения', () async {
      write(userPath, listed);

      final result = await list(MemorySecretStore());

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(result.stdout.first, 'Secrets: memory');
      final gw = result.stdout.firstWhere((l) => l.startsWith('gw'));
      expect(gw, contains('openai-compatible'));
      expect(gw, contains('https://gw.test/v1'));
      expect(gw, contains('m, n'));
      expect(gw, contains('secret codelab/gw: not set'));
      final loc = result.stdout.firstWhere((l) => l.startsWith('loc'));
      expect(loc, contains('env LOC_KEY: not set'));
    });

    test('found для сохранённого секрета и set для заданной переменной, '
        'значения не печатаются', () async {
      write(userPath, listed);

      final result = await list(
        MemorySecretStore({'codelab/gw': 'sk-test-secret-1'}),
        environment: env({'LOC_KEY': 'loc-secret-2'}),
      );

      final text = result.stdout.join('\n');
      expect(text, contains('secret codelab/gw: found'));
      expect(text, contains('env LOC_KEY: set'));
      expect(allOutput(result), isNot(contains('sk-test-secret-1')));
      expect(allOutput(result), isNot(contains('loc-secret-2')));
    });

    test('userinfo адреса не печатается', () async {
      write(userPath, listed);

      final result = await list(MemorySecretStore());

      expect(allOutput(result), isNot(contains('pw')));
      expect(allOutput(result), isNot(contains('u:')));
    });

    test('remove провайдера, на которого ссылается default_model: код 1, '
        'подсказка сменить модель, файл цел (сценарий «provider remove со '
        'ссылкой»)', () async {
      write(userPath, listed);
      final before = read(userPath);

      final result = await commandsOver(
        MemorySecretStore(),
      ).remove(ProviderRemoveOptions(id: 'gw', cwd: cwd, environment: env()));

      expect(result.exitCode, 1, reason: allOutput(result));
      final err = result.stderr.join('\n');
      expect(err, contains('agent.default_model'));
      expect(err, contains('config set agent.default_model'));
      expect(read(userPath), before);
    });

    test('remove провайдера без ссылки удаляет таблицу', () async {
      write(userPath, listed);

      final result = await commandsOver(
        MemorySecretStore(),
      ).remove(ProviderRemoveOptions(id: 'loc', cwd: cwd, environment: env()));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(result.stdout.first, 'Removed providers.loc from $userPath');
      final map = (loadYaml(read(userPath)) as YamlMap)['providers'] as YamlMap;
      expect(map.keys, ['gw']);
    });

    test('remove провайдера со значением null задан: таблица удаляется '
        '(ревью итерации 4, safety M)', () async {
      write(userPath, 'providers:\n  empty:\n');

      final result = await commandsOver(MemorySecretStore()).remove(
        ProviderRemoveOptions(id: 'empty', cwd: cwd, environment: env()),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(result.stdout.first, 'Removed providers.empty from $userPath');
      expect(read(userPath), isNot(contains('empty')));
    });

    test('remove отсутствующего провайдера: код 0, файл не меняется', () async {
      write(userPath, listed);
      final before = read(userPath);

      final result = await commandsOver(
        MemorySecretStore(),
      ).remove(ProviderRemoveOptions(id: 'zzz', cwd: cwd, environment: env()));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(result.stdout, ['providers.zzz is not set in $userPath']);
      expect(read(userPath), before);
    });
  });

  group('mcp add, list, remove', () {
    McpServerCommands mcpCommands() =>
        McpServerCommands(processRunner: FakeSecretProcessRunner());

    McpAddOptions addOf({
      String name = 'srv',
      String? type = 'stdio',
      String? command = 'npx',
      List<String> args = const [],
      List<String> envPairs = const [],
      String? url,
      List<String> headers = const [],
      bool disabled = false,
      ConfigFileLayer layer = ConfigFileLayer.user,
    }) => McpAddOptions(
      name: name,
      cwd: cwd,
      environment: env(),
      type: type,
      command: command,
      args: args,
      env: envPairs,
      url: url,
      headers: headers,
      disabled: disabled,
      project: layer == ConfigFileLayer.project,
      local: layer == ConfigFileLayer.local,
    );

    List<Object?> servers() =>
        ((loadYaml(read(userPath)) as YamlMap)['mcp'] as YamlMap)['servers']
            as List<Object?>;

    test('stdio: command, args и env записаны', () async {
      final result = await mcpCommands().add(
        addOf(args: ['-y', 'pkg'], envPairs: ['MODE=fast']),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(result.stdout.first, 'Updated mcp.servers[srv] in $userPath');
      final server = servers().single as YamlMap;
      expect(server['name'], 'srv');
      expect(server['type'], 'stdio');
      expect(server['command'], 'npx');
      expect(server['args'], ['-y', 'pkg']);
      expect((server['env'] as YamlMap)['MODE'], 'fast');
    });

    test('http с заголовком-ссылкой и --disabled', () async {
      final result = await mcpCommands().add(
        addOf(
          name: 'github',
          type: 'http',
          command: null,
          url: 'https://h/mcp',
          headers: [r'Authorization=Bearer ${secret:codelab/mcp/github/auth}'],
          disabled: true,
        ),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      final server = servers().single as YamlMap;
      expect(server['url'], 'https://h/mcp');
      expect(server['enabled'], false);
      expect(
        (server['headers'] as YamlMap)['Authorization'],
        r'Bearer ${secret:codelab/mcp/github/auth}',
      );
    });

    test('повторный add с тем же именем заменяет сервер на месте', () async {
      await mcpCommands().add(addOf());
      final result = await mcpCommands().add(addOf(command: 'uvx'));

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(servers(), hasLength(1));
      expect((servers().single as YamlMap)['command'], 'uvx');
    });

    test('литеральный токен в заголовке: код 1, подсказка с именем секрета, '
        'значения нет, файл не создан (сценарий «mcp add с литеральным '
        'токеном»)', () async {
      final result = await mcpCommands().add(
        addOf(
          name: 'github',
          type: 'http',
          command: null,
          url: 'https://h',
          headers: ['Authorization=Bearer ghp_x'],
        ),
      );

      expect(result.exitCode, 1, reason: allOutput(result));
      final err = result.stderr.join('\n');
      expect(err, contains(r'${secret:codelab/mcp/github/authorization}'));
      expect(
        err,
        contains('codelab secret set codelab/mcp/github/authorization'),
      );
      expect(allOutput(result), isNot(contains('ghp_x')));
      expect(File(userPath).existsSync(), isFalse);
    });

    test('ошибки использования: код 64, значение пары не цитируется', () async {
      for (final options in [
        addOf(type: null),
        addOf(type: 'sse'),
        addOf(command: null),
        addOf(type: 'http', command: null, url: null),
        addOf(url: 'https://h'),
        addOf(envPairs: ['SECRETVALUE-NO-EQUALS']),
        addOf(
          type: 'http',
          command: null,
          url: 'https://h',
          headers: ['SECRETVALUE-NO-EQUALS'],
        ),
      ]) {
        final result = await mcpCommands().add(options);

        expect(result.exitCode, 64, reason: allOutput(result));
        expect(allOutput(result), isNot(contains('SECRETVALUE')));
      }
      expect(File(userPath).existsSync(), isFalse);
    });

    test('list: серверы файлов по слоям без подключения', () async {
      write(userPath, '''
mcp:
  servers:
    - name: a
      type: stdio
      command: definitely-not-installed-binary
    - name: b
      type: http
      url: https://h
      enabled: false
''');
      write('$cwd/.codelab/config.yaml', '''
mcp:
  servers:
    - name: c
      type: http
      url: https://p
''');

      final result = await mcpCommands().list(
        McpListOptions(cwd: cwd, environment: env()),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      final text = result.stdout;
      expect(
        text.firstWhere((l) => l.startsWith('a')),
        allOf(contains('stdio'), contains('user'), contains('enabled: true')),
      );
      expect(
        text.firstWhere((l) => l.startsWith('b')),
        allOf(contains('http'), contains('user'), contains('enabled: false')),
      );
      expect(
        text.firstWhere((l) => l.startsWith('c')),
        allOf(contains('http'), contains('project'), contains('enabled: true')),
      );
    });

    test('remove по числу не удаляет по индексу: mcp remove 0 без сервера '
        '"0" — "is not set", файл цел (ревью итерации 4, safety M)', () async {
      await mcpCommands().add(addOf());
      await mcpCommands().add(addOf(name: 'other'));
      final before = read(userPath);

      final result = await mcpCommands().remove(
        McpRemoveOptions(name: '0', cwd: cwd, environment: env()),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(result.stdout, ['mcp.servers[0] is not set in $userPath']);
      expect(read(userPath), before);
    });

    test('remove сервера, названного числом, удаляет его, а не первый '
        'элемент', () async {
      await mcpCommands().add(addOf());
      await mcpCommands().add(addOf(name: '0'));

      final result = await mcpCommands().remove(
        McpRemoveOptions(name: '0', cwd: cwd, environment: env()),
      );

      expect(result.exitCode, 0, reason: allOutput(result));
      expect(servers().map((s) => (s as YamlMap)['name']), ['srv']);
    });

    test('недопустимое имя сервера (пробел, [, ], "): add и remove — код '
        '64, файл не изменён', () async {
      await mcpCommands().add(addOf());
      final before = read(userPath);

      for (final name in ['a b', 'a[', 'a]', 'a"b', '']) {
        final add = await mcpCommands().add(addOf(name: name));
        final remove = await mcpCommands().remove(
          McpRemoveOptions(name: name, cwd: cwd, environment: env()),
        );

        expect(add.exitCode, 64, reason: 'add "$name"');
        expect(remove.exitCode, 64, reason: 'remove "$name"');
        expect(remove.stderr.single, startsWith('mcp remove: '));
      }
      expect(read(userPath), before);
    });

    test('remove по имени, отсутствующий — код 0', () async {
      await mcpCommands().add(addOf());
      await mcpCommands().add(addOf(name: 'other'));

      final removed = await mcpCommands().remove(
        McpRemoveOptions(name: 'srv', cwd: cwd, environment: env()),
      );
      final absent = await mcpCommands().remove(
        McpRemoveOptions(name: 'zzz', cwd: cwd, environment: env()),
      );

      expect(removed.exitCode, 0, reason: allOutput(removed));
      expect(removed.stdout.first, 'Removed mcp.servers[srv] from $userPath');
      expect(servers().map((s) => (s as YamlMap)['name']), ['other']);
      expect(absent.exitCode, 0, reason: allOutput(absent));
      expect(absent.stdout, ['mcp.servers[zzz] is not set in $userPath']);
    });
  });

  group('слои и флаги, общие для приложений', () {
    test('--project вместе с --local: код 64 и один текст у всех подкоманд '
        'записи и у config path, файлы не создаются', () async {
      final results = <String, ConfigCommandResult>{
        'config set': await configCommands().set(
          ConfigSetOptions(
            key: 'budget.max_steps',
            value: '5',
            cwd: cwd,
            environment: env(),
            project: true,
            local: true,
          ),
        ),
        'config unset': await configCommands().unset(
          ConfigUnsetOptions(
            key: 'budget.max_steps',
            cwd: cwd,
            environment: env(),
            project: true,
            local: true,
          ),
        ),
        'config path': await configCommands().path(
          ConfigPathOptions(
            cwd: cwd,
            environment: env(),
            project: true,
            local: true,
          ),
        ),
        'provider add':
            await ProviderCommands(
              processRunner: FakeSecretProcessRunner(),
            ).add(
              ProviderAddOptions(
                id: 'gw',
                cwd: cwd,
                environment: env(),
                kind: 'openai-compatible',
                model: 'm',
                contextWindow: '8192',
                project: true,
                local: true,
              ),
              FakeSecretInput(''),
            ),
        'provider remove':
            await ProviderCommands(
              processRunner: FakeSecretProcessRunner(),
            ).remove(
              ProviderRemoveOptions(
                id: 'gw',
                cwd: cwd,
                environment: env(),
                project: true,
                local: true,
              ),
            ),
        'mcp add':
            await McpServerCommands(
              processRunner: FakeSecretProcessRunner(),
            ).add(
              McpAddOptions(
                name: 'srv',
                cwd: cwd,
                environment: env(),
                type: 'stdio',
                command: 'npx',
                project: true,
                local: true,
              ),
            ),
        'mcp remove':
            await McpServerCommands(
              processRunner: FakeSecretProcessRunner(),
            ).remove(
              McpRemoveOptions(
                name: 'srv',
                cwd: cwd,
                environment: env(),
                project: true,
                local: true,
              ),
            ),
      };

      for (final MapEntry(:key, :value) in results.entries) {
        expect(value.exitCode, 64, reason: key);
        expect(value.stderr, [
          '$key: --project and --local cannot be combined',
        ], reason: key);
      }
      expect(Directory('$cwd/.codelab').existsSync(), isFalse);
      expect(File(userPath).existsSync(), isFalse);
    });

    test('ConfigGetLayer.parse: имена слоёв, без имени — merged', () {
      expect(ConfigGetLayer.parse(null), ConfigGetLayer.merged);
      for (final layer in ConfigGetLayer.values) {
        expect(ConfigGetLayer.parse(layer.name), layer);
      }
      expect(() => ConfigGetLayer.parse('nope'), throwsArgumentError);
    });

    test('config path --local указывает на файл, в который пишет set --local, '
        'и на каталог-ссылку проекта', () async {
      final real = Directory('${root.path}/real')..createSync();
      final link = '${root.path}/link';
      Link(link).createSync(real.path);
      write(userPath, providers);

      for (final (project, local) in [(true, false), (false, true)]) {
        final path = await configCommands().path(
          ConfigPathOptions(
            cwd: link,
            environment: env(),
            project: project,
            local: local,
          ),
        );
        final set = await configCommands().set(
          ConfigSetOptions(
            key: 'agent.effort',
            value: 'low',
            cwd: link,
            environment: env(),
            project: project,
            local: local,
          ),
        );

        expect(set.exitCode, 0, reason: allOutput(set));
        expect(
          set.stdout.first,
          'Updated agent.effort in ${path.stdout.single}',
        );
        expect(File(path.stdout.single).existsSync(), isTrue);
      }
    });

    test(
      'configLayerFilePath: одна функция пути для писателя и config path',
      () {
        expect(
          configLayerFilePath(const ConfigTarget.user(), home),
          '$home/config.yaml',
        );
        expect(
          configLayerFilePath(ConfigTarget.project(cwd), home),
          '$cwd/.codelab/config.yaml',
        );
        expect(
          configLayerFilePath(ConfigTarget.projectLocal(cwd), home),
          '$cwd/.codelab/config.local.yaml',
        );
      },
    );
  });

  group('общие правила', () {
    test('несуществующий --cwd: код 64', () async {
      final result = await configCommands().set(
        ConfigSetOptions(
          key: 'budget.max_steps',
          value: '5',
          cwd: '${root.path}/nope',
          environment: env(),
        ),
      );

      expect(result.exitCode, 64);
    });

    test('CODELAB_HOME с неверной тильдой: код 64', () async {
      final result = await setKey(
        'budget.max_steps',
        '5',
        environment: {'CODELAB_HOME': '~root/x'},
      );

      expect(result.exitCode, 64);
    });
  });
}
