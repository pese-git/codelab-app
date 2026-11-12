// `codelab config check` без агента (задача 11.3; spec codelab-cli «Подкоманда
// codelab config»; design.md change `add-agent-configuration`, D13, D14).

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

import 'support/fake_cli_io.dart';

/// Глобальный конфиг с провайдером и моделью по умолчанию: провайдеры
/// принимаются только из глобального слоя (CFG-3).
const _globalConfig = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''';

void main() {
  late Directory temp;
  late String home;
  late String project;

  setUp(() {
    // Каталог сразу канонический: писатель раскрывает ссылки (на macOS `/var` —
    // ссылка на `/private/var`), и путь в выводе должен совпасть с ожиданием.
    temp = Directory(
      Directory.systemTemp
          .createTempSync('codelab_cli_config_cmd_')
          .resolveSymbolicLinksSync(),
    );
    home = '${temp.path}/home';
    project = '${temp.path}/project';
    Directory(home).createSync();
    Directory('$project/.codelab').createSync(recursive: true);
    File('$home/config.yaml').writeAsStringSync(_globalConfig);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<(int, FakeCliIo)> run(List<String> args) async {
    final io = FakeCliIo();
    // HOME намеренно несуществующий: тест не должен видеть настоящий
    // `~/.codelab`; корень состояния задаёт только CODELAB_HOME.
    final code = await runCodelab(
      args,
      environment: {'CODELAB_HOME': home, 'HOME': '${temp.path}/no-home'},
      io: io,
    );
    return (code, io);
  }

  test('check --cwd: an invalid project value is reported, code 1', () async {
    File(
      '$project/.codelab/config.yaml',
    ).writeAsStringSync('budget:\n  max_steps: 0\n');

    final (code, io) = await run(['config', 'check', '--cwd', project]);

    expect(code, 1, reason: io.stderrText);
    expect(io.stdoutText, contains('budget.max_steps'));
    expect(io.stdoutText, contains('config.yaml:'));
    expect(
      io.stdoutText.trimRight().split('\n').last,
      'Config: invalid (issues: 1)',
    );
  });

  test('check on a valid config: Config: valid, code 0', () async {
    final (code, io) = await run(['config', 'check', '--cwd', project]);

    expect(code, 0, reason: io.stderrText);
    expect(io.stdoutText.trimRight().split('\n').last, 'Config: valid');
    expect(io.stderrText, isEmpty);
  });

  test('the top-level --cwd is the same as check --cwd', () async {
    File(
      '$project/.codelab/config.yaml',
    ).writeAsStringSync('budget:\n  max_steps: 0\n');

    final (code, io) = await run(['--cwd', project, 'config', 'check']);

    expect(code, 1, reason: io.stderrText);
    expect(io.stdoutText, contains('budget.max_steps'));
  });

  // Сценарий «Одинаково у двух бинарей» (change `add-agent-project-files`,
  // D13): битый шаблон пользователя виден в `codelab config check` той же
  // строкой `warning:`, что и в `codelab-agent config check`, потому что обе
  // команды вызывают один `ConfigCommands` через мост `codelab_setup`.
  test('check --cwd: a broken template in CODELAB_HOME/prompts is the same '
      'warning line as in codelab-agent, code 0', () async {
    Directory('$home/prompts').createSync(recursive: true);
    File('$home/prompts/Review.md').writeAsStringSync('body sk-test-secret\n');

    final (code, io) = await run(['config', 'check', '--cwd', project]);

    expect(code, 0, reason: io.stderrText);
    final lines = io.stdoutText.trimRight().split('\n');
    final warning = lines.singleWhere((l) => l.startsWith('warning: '));
    expect(warning, startsWith('warning: $home/prompts/Review.md: '));
    expect(warning, contains('not a valid command name'));
    expect(lines.last, 'Config: valid');
    expect(io.stdoutText, isNot(contains('sk-test-secret')));

    // Та же реализация, что вызывает `codelab-agent config check`.
    final expected = await ConfigCommands().check(
      CheckOptions(
        cwd: project,
        environment: {'CODELAB_HOME': home, 'HOME': '${temp.path}/no-home'},
      ),
    );
    expect(code, expected.exitCode);
    expect(lines, expected.stdout);
  });

  // D17: `CODELAB_HOME=~user/x` — ошибка использования, тот же текст и код 64,
  // что у `codelab-agent config check`.
  test('check: CODELAB_HOME=~user/x is the same usage error as in '
      'codelab-agent, code 64', () async {
    final env = {'CODELAB_HOME': '~bob/x', 'HOME': '${temp.path}/h'};
    final io = FakeCliIo();
    final code = await runCodelab(
      ['config', 'check', '--cwd', project],
      environment: env,
      io: io,
    );

    final expected = await ConfigCommands().check(
      CheckOptions(cwd: project, environment: env),
    );
    expect(code, 64);
    expect(code, expected.exitCode);
    expect(io.stdoutText, isEmpty);
    expect(io.stderrText.trimRight().split('\n'), expected.stderr);
  });

  test('a missing --cwd folder is a usage error, code 64', () async {
    final (code, io) = await run([
      'config',
      'check',
      '--cwd',
      '${temp.path}/missing',
    ]);

    expect(code, 64);
    expect(io.stdoutText, isEmpty);
    expect(io.stderrText, isNotEmpty);
  });

  // Подкоманды записи и чтения зарегистрированы (change
  // `add-config-writer-and-reload`, D6): незнакомой остаются `migrate` и любое
  // другое слово. Прежний тест требовал `Unknown command` и для `set`, `get`,
  // `unset`, `path`; теперь они рабочие, а контракт «неизвестная подкоманда —
  // 64» проверяется на `migrate` и `frobnicate`.
  for (final sub in ['migrate', 'frobnicate']) {
    test('config $sub: 64, Unknown command, file untouched', () async {
      final file = File('$project/.codelab/config.yaml')
        ..writeAsStringSync('budget:\n  max_steps: 3\n');

      final (code, io) = await run(['config', sub]);

      expect(code, 64);
      expect(io.stderrText, contains('Unknown command config $sub'));
      expect(io.stdoutText, isEmpty);
      expect(file.readAsStringSync(), 'budget:\n  max_steps: 3\n');
    });
  }

  test('config without a subcommand is a usage error, code 64', () async {
    final (code, io) = await run(['config']);

    expect(code, 64);
    expect(io.stdoutText, isEmpty);
    expect(
      io.stderrText,
      contains(
        'config needs a subcommand: codelab config path|get|set|unset|check',
      ),
    );
  });

  test('--help names config check', () async {
    final (code, io) = await run(['--help']);

    expect(code, 0);
    expect(io.stdoutText, contains('codelab config check [--cwd <dir>]'));
  });

  test('--cwd of the subcommand beats the general --cwd', () async {
    final other = '${temp.path}/other';
    Directory('$other/.codelab').createSync(recursive: true);
    File(
      '$project/.codelab/config.yaml',
    ).writeAsStringSync('budget:\n  max_steps: 0\n');

    // Общий --cwd указывает на битый проект, подкоманда — на чистый: D14.
    final (code, io) = await run([
      '--cwd',
      project,
      'config',
      'check',
      '--cwd',
      other,
    ]);

    expect(code, 0, reason: io.stdoutText);
    expect(io.stdoutText.trimRight().split('\n').last, 'Config: valid');
  });

  // Профиль подключения `config check` не учитывает (D14): флаги подключения
  // и запроса вместе с `config` — ошибка использования, а не тихий игнор.
  for (final flags in [
    ['--agent', 'x'],
    ['-a', 'x'],
    ['-p', 'hi'],
    ['--print', 'hi'],
    ['-f', 'prompt.txt'],
    ['--prompt-file', 'prompt.txt'],
    ['--model', 'm'],
    ['--mode', 'm'],
    ['--resume', 's'],
    ['--continue'],
    ['--approve', 'allow-all'],
    ['--timeout', '5s'],
    ['--ui', 'tui'],
  ]) {
    test('${flags.join(' ')} with config check: 64, nothing printed', () async {
      final (code, io) = await run([...flags, 'config', 'check']);

      expect(code, 64);
      expect(io.stdoutText, isEmpty);
      expect(io.stderrText, contains('config check'));
    });
  }

  group('the path goes to the bridge as it is (like codelab-agent)', () {
    Future<void> expectSameAsBridge(String cwd, List<String> args) async {
      final environment = {
        'CODELAB_HOME': home,
        'HOME': '${temp.path}/no-home',
      };
      final expected = await ConfigCommands().check(
        CheckOptions(cwd: cwd, environment: environment),
      );
      final io = FakeCliIo();

      final code = await runCodelab(args, environment: environment, io: io);

      expect(code, expected.exitCode, reason: io.stderrText);
      expect(io.stdoutText, expected.stdout.map((l) => '$l\n').join());
      expect(io.stderrText, expected.stderr.map((l) => '$l\n').join());
    }

    test('link/../proj through a symlink is resolved by the OS', () async {
      Directory('${temp.path}/real/sub').createSync(recursive: true);
      Directory('${temp.path}/real/proj/.codelab').createSync(recursive: true);
      File(
        '${temp.path}/real/proj/.codelab/config.yaml',
      ).writeAsStringSync('budget:\n  max_steps: 0\n');
      Link('${temp.path}/link').createSync('${temp.path}/real/sub');
      final raw = '${temp.path}/link/../proj';
      // Нормализация дала бы `${temp.path}/proj` (его нет, код 64), а ОС
      // ведёт в `real/proj` (код 1): вывод обязан совпасть с агентом.
      expect(Directory(raw).existsSync(), isTrue);

      await expectSameAsBridge(raw, ['config', 'check', '--cwd', raw]);
    });

    test(
      'a relative missing --cwd keeps the raw text in the message',
      () async {
        await expectSameAsBridge('no_such_dir_codelab', [
          'config',
          'check',
          '--cwd',
          'no_such_dir_codelab',
        ]);
      },
    );
  });

  // Задача 4.1 change `bind-mcp-secrets-to-origin` (agent-secrets
  // «Ссылки MCP-сервера проектного слоя привязаны к адресу»; design.md, D5): код CLI
  // не меняется, строку предупреждения печатает общая `ConfigCommands`.
  test('check: a project HTTP server with an unbound secret reference gives '
      'the warning, Config: valid, code 0, no value in the output', () async {
    const leak = 'sk-test-leak-0123456789';
    // Слой проекта читается только у доверенного проекта (CFG-3).
    File(
      '$home/config.yaml',
    ).writeAsStringSync('$_globalConfig\ntrusted_projects:\n  - $project\n');
    File('$project/.codelab/config.yaml').writeAsStringSync(r'''
mcp:
  servers:
    - name: relay
      type: http
      url: https://relay.test/mcp
      headers:
        Authorization: "Bearer ${secret:codelab/mcp/relay/authorization}"
''');
    final io = FakeCliIo();

    final code = await runCodelab(
      ['config', 'check', '--cwd', project],
      environment: {
        'CODELAB_HOME': home,
        'HOME': '${temp.path}/no-home',
        // Переопределение секрета из ссылки: значение есть, но сервер
        // заблокирован и до него дело не доходит.
        'CODELAB_SECRET_CODELAB_MCP_RELAY_AUTHORIZATION': leak,
      },
      io: io,
    );

    expect(code, 0, reason: io.stderrText);
    final lines = io.stdoutText.trimRight().split('\n');
    expect(lines.where((l) => l.startsWith('warning: ')), [
      'warning: $project/.codelab/config.yaml:7:9: '
          'mcp.servers[relay].headers.Authorization: the reference is bound '
          'to another address and is not used',
    ]);
    expect(lines.last, 'Config: valid');
    expect(io.stdoutText + io.stderrText, isNot(contains(leak)));
  });

  // Задача 4.3 change `bind-mcp-secrets-to-origin` (D12; agent-secrets
  // «Stdio-сервер закоммиченного конфига со ссылкой на секрет»).
  group('check: a stdio server with a secret reference (D12)', () {
    const leak = 'sk-test-leak-0123456789';
    const stdioServer = r'''
mcp:
  servers:
    - name: docs
      type: stdio
      command: docs-server
      env:
        TOKEN: "${secret:codelab/mcp/docs/token}"
''';

    Future<(int, FakeCliIo)> check(String layerFile) async {
      File(
        '$home/config.yaml',
      ).writeAsStringSync('$_globalConfig\ntrusted_projects:\n  - $project\n');
      File('$project/.codelab/$layerFile').writeAsStringSync(stdioServer);
      final io = FakeCliIo();
      final code = await runCodelab(
        ['config', 'check', '--cwd', project],
        environment: {
          'CODELAB_HOME': home,
          'HOME': '${temp.path}/no-home',
          'CODELAB_SECRET_CODELAB_MCP_DOCS_TOKEN': leak,
        },
        io: io,
      );
      return (code, io);
    }

    test(
      'the committed config.yaml: exactly one warning, valid, no value',
      () async {
        final (code, io) = await check('config.yaml');

        expect(code, 0, reason: io.stderrText);
        final lines = io.stdoutText.trimRight().split('\n');
        final warnings = lines.where((l) => l.startsWith('warning: ')).toList();
        expect(warnings, hasLength(1));
        expect(
          warnings.single,
          matches(
            RegExp(
              '^warning: ${RegExp.escape(project)}/\\.codelab/config\\.yaml'
              r'(:\d+:\d+)?: mcp\.servers\[docs\]: a stdio server from the '
              r'committed project config receives a secret reference; it runs '
              r'as you, so move it to config\.local\.yaml if you did not write '
              r'it$',
            ),
          ),
        );
        expect(lines.last, 'Config: valid');
        expect(io.stdoutText + io.stderrText, isNot(contains(leak)));
        expect(
          io.stdoutText + io.stderrText,
          isNot(contains('codelab/mcp/docs/token')),
        );
      },
    );

    test('the same server in config.local.yaml: no warning', () async {
      final (code, io) = await check('config.local.yaml');

      expect(code, 0, reason: io.stderrText);
      expect(io.stdoutText, isNot(contains('warning:')));
      expect(io.stdoutText.trimRight().split('\n').last, 'Config: valid');
      expect(io.stdoutText + io.stderrText, isNot(contains(leak)));
      expect(
        io.stdoutText + io.stderrText,
        isNot(contains('codelab/mcp/docs/token')),
      );
    });
  });

  test('no secret value reaches stdout or stderr', () async {
    File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key: \${X}
    models:
      m: {}
agent:
  default_model: p/m
''');
    File(
      '$project/.codelab/config.yaml',
    ).writeAsStringSync('budget:\n  max_steps: 0\n');
    final io = FakeCliIo();

    await runCodelab(
      ['config', 'check', '--cwd', project],
      environment: {
        'CODELAB_HOME': home,
        'HOME': '${temp.path}/no-home',
        'CODELAB_API_KEY': 'sk-test-secret',
        'CODELAB_AGENT_TOKEN': 'tok-test-secret',
        'X': 'x-test-secret',
      },
      io: io,
    );

    final all = io.stdoutText + io.stderrText;
    for (final secret in [
      'sk-test-secret',
      'tok-test-secret',
      'x-test-secret',
    ]) {
      expect(all, isNot(contains(secret)));
    }
  });

  group(
    'config path, get, set, unset (change add-config-writer-and-reload, D6)',
    () {
      final env = <String, String>{};

      setUp(() {
        env
          ..clear()
          ..addAll({'CODELAB_HOME': home, 'HOME': '${temp.path}/no-home'});
      });

      Future<void> expectSameAsBridge(
        ConfigCommandResult expected,
        int code,
        FakeCliIo io,
      ) async {
        expect(code, expected.exitCode, reason: io.stderrText);
        expect(io.stdoutText, expected.stdout.map((l) => '$l\n').join());
        expect(io.stderrText, expected.stderr.map((l) => '$l\n').join());
      }

      test(
        'set пишет в user-слой, комментарии сохранены, вывод как у моста',
        () async {
          File('$home/config.yaml').writeAsStringSync(
            '# my settings\n$_globalConfig'
            'budget:\n  max_steps: 3 # three\n',
          );
          final (code, io) = await run([
            'config',
            'set',
            'budget.max_steps',
            '10',
          ]);

          expect(code, 0, reason: io.stderrText);
          expect(
            io.stdoutText,
            'Updated budget.max_steps in $home/config.yaml\n',
          );
          final text = File('$home/config.yaml').readAsStringSync();
          expect(text, contains('# my settings'));
          expect(text, contains('max_steps: 10 # three'));
          // Тот же результат даёт общий ConfigCommands (D6): байты совпадают.
          File('$home/config.yaml').writeAsStringSync(
            '# my settings\n$_globalConfig'
            'budget:\n  max_steps: 3 # three\n',
          );
          final expected = await ConfigCommands().set(
            ConfigSetOptions(
              key: 'budget.max_steps',
              value: '10',
              cwd: Directory.current.path,
              environment: env,
            ),
          );
          expect(File('$home/config.yaml').readAsStringSync(), text);
          expect(expected.stdout, [
            'Updated budget.max_steps in $home/config.yaml',
          ]);
        },
      );

      test('-C <dir> config set --local создаёт config.local.yaml проекта, '
          'глобальный конфиг не тронут', () async {
        final before = File('$home/config.yaml').readAsStringSync();

        final (code, io) = await run([
          '-C',
          project,
          'config',
          'set',
          'permissions.mode',
          'plan',
          '--local',
        ]);

        expect(code, 0, reason: io.stderrText);
        expect(
          File('$project/.codelab/config.local.yaml').readAsStringSync(),
          contains('mode: plan'),
        );
        expect(File('$home/config.yaml').readAsStringSync(), before);
      });

      test('--cwd подкоманды сильнее общего -C для get', () async {
        final other = '${temp.path}/other';
        Directory('$other/.codelab').createSync(recursive: true);
        File(
          '$project/.codelab/config.yaml',
        ).writeAsStringSync('budget:\n  max_steps: 7\n');

        final (code, io) = await run([
          '-C',
          other,
          'config',
          'get',
          'budget.max_steps',
          '--layer',
          'project',
          '--cwd',
          project,
        ]);

        expect(code, 0, reason: io.stderrText);
        expect(io.stdoutText, '7\nlayer: project\n');
      });

      test('get без --layer — merged; вывод как у моста', () async {
        File(
          '$project/.codelab/config.yaml',
        ).writeAsStringSync('budget:\n  max_steps: 7\n');

        final (code, io) = await run([
          'config',
          'get',
          'budget.max_steps',
          '--cwd',
          project,
        ]);

        await expectSameAsBridge(
          await ConfigCommands().get(
            ConfigGetOptions(
              key: 'budget.max_steps',
              cwd: project,
              environment: env,
              layer: ConfigGetLayer.merged,
            ),
          ),
          code,
          io,
        );
      });

      test('get отсутствующего ключа: код 1', () async {
        final (code, io) = await run(['config', 'get', 'budget.max_steps']);

        expect(code, 1);
        expect(io.stdoutText, isEmpty);
        expect(io.stderrText, contains('budget.max_steps is not set'));
      });

      test('unset отсутствующей записи: код 0 и «is not set in»', () async {
        final (code, io) = await run(['config', 'unset', 'budget.max_steps']);

        expect(code, 0, reason: io.stderrText);
        expect(
          io.stdoutText,
          'budget.max_steps is not set in $home/config.yaml\n',
        );
      });

      test('set, затем unset удаляет ключ', () async {
        await run(['config', 'set', 'budget.max_steps', '10']);
        final (code, io) = await run(['config', 'unset', 'budget.max_steps']);

        expect(code, 0, reason: io.stderrText);
        expect(
          io.stdoutText,
          'Removed budget.max_steps from $home/config.yaml\n',
        );
        expect(
          File('$home/config.yaml').readAsStringSync(),
          isNot(contains('max_steps')),
        );
      });

      test('path без флагов печатает слои; вывод как у моста', () async {
        final (code, io) = await run(['config', 'path', '--cwd', project]);

        await expectSameAsBridge(
          await ConfigCommands().path(
            ConfigPathOptions(cwd: project, environment: env),
          ),
          code,
          io,
        );
        expect(io.stdoutText, startsWith('user: $home/config.yaml (exists)\n'));
      });

      test('path --local печатает один путь', () async {
        final (code, io) = await run([
          'config',
          'path',
          '--local',
          '--cwd',
          project,
        ]);

        expect(code, 0, reason: io.stderrText);
        expect(io.stdoutText, endsWith('config.local.yaml\n'));
        expect(io.stdoutText.trimRight().split('\n'), hasLength(1));
      });

      test('неизвестный ключ set: код 64, файл не изменён', () async {
        final before = File('$home/config.yaml').readAsStringSync();
        final (code, io) = await run([
          'config',
          'set',
          'budget.max_stepz',
          '1',
        ]);

        expect(code, 64);
        expect(io.stdoutText, isEmpty);
        expect(io.stderrText, contains('budget.max_steps'));
        expect(File('$home/config.yaml').readAsStringSync(), before);
      });

      test('--project и --local вместе, лишние и недостающие аргументы, '
          'неверный --layer: 64, stdout пуст, файл не изменён', () async {
        final before = File('$home/config.yaml').readAsStringSync();
        for (final args in [
          ['config', 'set', 'budget.max_steps'],
          ['config', 'set', 'a', 'b', 'c'],
          ['config', 'get'],
          ['config', 'get', 'a', 'b'],
          ['config', 'unset'],
          ['config', 'get', 'a', '--layer', 'bogus'],
        ]) {
          final (code, io) = await run(args);

          expect(code, 64, reason: '$args: ${io.stderrText}');
          expect(io.stdoutText, isEmpty, reason: '$args');
          expect(io.stderrText, contains('codelab config'), reason: '$args');
          expect(io.stderrText, isNot(contains('codelab-agent')));
        }
        expect(File('$home/config.yaml').readAsStringSync(), before);
      });

      test('--project и --local вместе: 64 и текст общего кода, файл не '
          'изменён', () async {
        final before = File('$home/config.yaml').readAsStringSync();
        for (final sub in [
          ['set', 'budget.max_steps', '1'],
          ['unset', 'budget.max_steps'],
          ['path'],
        ]) {
          final (code, io) = await run([
            'config',
            ...sub,
            '--project',
            '--local',
          ]);

          expect(code, 64, reason: '$sub');
          expect(io.stdoutText, isEmpty, reason: '$sub');
          expect(
            io.stderrText,
            contains('--project and --local cannot be combined'),
            reason: '$sub',
          );
        }
        expect(File('$home/config.yaml').readAsStringSync(), before);
      });

      // Ревью итерации 4 (safety L): значение `set` может начинаться с `-` и
      // быть секретом; текст `package:args` его процитировал бы.
      test('ошибка разбора set и unset — фиксированная фраза без слов argv, '
          'справка config', () async {
        const leak = '--sk-LEAK-0123456789';
        for (final (args, verb) in [
          (['config', 'set', 'budget.max_steps', leak], 'set'),
          (['config', 'unset', leak], 'unset'),
          (['config', 'set', 'a', 'b', '--bogus=$leak'], 'set'),
          (['--approve=$leak', 'config', 'set', 'a', 'b'], 'set'),
        ]) {
          final (code, io) = await run(args);

          expect(code, 64, reason: '$args');
          expect(io.stdoutText, isEmpty, reason: '$args');
          expect(
            io.stderrText,
            startsWith('codelab: invalid arguments for config $verb\n'),
            reason: '$args',
          );
          expect(io.stderrText, contains('codelab config set'));
          expect(io.stderrText, isNot(contains('LEAK')), reason: '$args');
          expect(io.stderrText, isNot(contains('codelab-agent')));
        }
      });

      test(
        'ошибка разбора get называет причину: фраза не подменяется',
        () async {
          final (code, io) = await run([
            'config',
            'get',
            'a',
            '--layer',
            'bogus',
          ]);

          expect(code, 64);
          expect(
            io.stderrText,
            isNot(contains('invalid arguments for config')),
          );
        },
      );

      test('допустимые значения --layer совпадают с ConfigGetLayer', () {
        // cli_args.dart не вправе импортировать мост (guard), поэтому список
        // там записан литералом; тест держит его равным общему перечислению.
        for (final layer in ConfigGetLayer.values) {
          expect(
            parseCliArgs([
              'config',
              'get',
              'a',
              '--layer',
              layer.name,
            ]).subcommand?.option('layer'),
            layer.name,
          );
        }
        expect(
          () => parseCliArgs(['config', 'get', 'a', '--layer', 'bogus']),
          throwsA(isA<UsageError>()),
        );
      });

      // Спека «Флаги подключения с config — ошибка использования»: и для
      // подкоманд записи, конфиг не меняется.
      for (final flags in [
        ['-p', 'hi'],
        ['--agent', 'x'],
        ['--prompt-file', 'f'],
        ['--ui', 'tui'],
      ]) {
        test(
          '${flags.join(' ')} с config set: 64, конфиг не изменён',
          () async {
            final before = File('$home/config.yaml').readAsStringSync();

            final (code, io) = await run([
              ...flags,
              'config',
              'set',
              'budget.max_steps',
              '1',
            ]);

            expect(code, 64);
            expect(io.stdoutText, isEmpty);
            expect(io.stderrText, contains('does not apply to config'));
            expect(File('$home/config.yaml').readAsStringSync(), before);
          },
        );
      }

      test(
        'запись не создаёт sessions/, profiles.json и cli_history',
        () async {
          await run(['config', 'set', 'budget.max_steps', '10']);
          await run(['config', 'get', 'budget.max_steps']);
          await run(['config', 'unset', 'budget.max_steps']);

          final names = Directory(home)
              .listSync()
              .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
              .toSet();
          expect(names, isNot(contains('sessions')));
          expect(names, isNot(contains('profiles.json')));
          expect(names, isNot(contains('cli_history')));
        },
      );
    },
  );
}
