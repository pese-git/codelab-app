// E2E `codelab config path|get|set|unset`, `codelab provider add|list|remove`
// и `codelab mcp add|list|remove` против собранного `codelab-agent` (задача
// 4.5 change `add-config-writer-and-reload`; spec codelab-cli «Подкоманда
// codelab config», «Подкоманды codelab provider и codelab mcp»; design.md D6).
//
// Критерий итерации 4: те же команды дают одинаковые stdout, stderr, код
// выхода и байты файлов. Два бинаря запускаются по очереди над одним
// `CODELAB_HOME`, который перед каждым прогоном возвращается в исходное
// состояние: так пути в выводе (`Updated … in <home>/config.yaml`) совпадают
// буквально. Значения «секретов» выдуманные, настоящий `~/.codelab` не
// читается.
//
// Тег `scripted-only` на каждом тесте: файл не зависит от агента матрицы
// (D5 change `add-cli-e2e-agent-matrix`).
@Timeout(Duration(seconds: 240))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';

/// Исходный глобальный конфиг с комментариями: правка обязана их сохранить.
const _baseConfig = '''
# my settings
secrets:
  backend: file
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
budget:
  max_steps: 3 # three
''';

/// Как сверять stderr двух бинарей в `expectSame`.
enum StderrCheck {
  /// Побайтно: тексты результатов общие.
  exact,

  /// Побайтно после замены `codelab-agent` на `codelab` (справка, фраза
  /// ошибки использования).
  withoutBinaryName,

  /// Только первая строка после той же замены: справки `config` различаются
  /// описанием `check`.
  firstLine,

  /// Только «пуст/не пуст»: причину неизвестного флага у `config check|get|
  /// path` формулируют бинари по-своему (это поведение до change D6).
  presence,
}

/// Минимальный валидный конфиг: без провайдера и модели по умолчанию запись
/// отклоняется проверкой итогового файла.
const _withDefaultModel = '''
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
  late Directory tmp;
  late String home;
  late String project;
  late Map<String, String> environment;

  setUp(() {
    // Канонический путь: писатель раскрывает ссылки (на macOS `/var` — ссылка
    // на `/private/var`), и вывод должен совпасть с ожиданием.
    tmp = Directory(
      Directory.systemTemp
          .createTempSync('codelab_cli_e2e_write_')
          .resolveSymbolicLinksSync(),
    );
    home = '${tmp.path}/home';
    project = '${tmp.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    environment = {'CODELAB_HOME': home, 'HOME': '${tmp.path}/no-home'};
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Возвращает `CODELAB_HOME` в исходное состояние [files] (имя -> текст).
  void reset(Map<String, String> files) {
    for (final entity in Directory(home).listSync()) {
      entity.deleteSync(recursive: true);
    }
    files.forEach((name, text) => File('$home/$name').writeAsStringSync(text));
  }

  /// Текст файлов `CODELAB_HOME` после прогона: имя -> содержимое.
  Map<String, String> homeFiles() => {
    for (final entity in Directory(home).listSync().whereType<File>())
      entity.uri.pathSegments.last: entity.readAsStringSync(),
  };

  Future<CliResult> runAgent(List<String> args, {String? stdin}) async {
    final process = await Process.start(
      dartExecutable(),
      [await E2eCliAgent.agentKernel(), ...args],
      environment: {'PATH': Platform.environment['PATH'] ?? '', ...environment},
      workingDirectory: project,
      includeParentEnvironment: false,
    );
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    if (stdin != null) {
      process.stdin.write(stdin);
    }
    await process.stdin.close();
    final out = utf8.decodeStream(process.stdout);
    final err = utf8.decodeStream(process.stderr);
    final code = await process.exitCode.timeout(const Duration(seconds: 60));
    return CliResult(code, await out, await err);
  }

  /// Запускает [args] у `codelab` и у `codelab-agent` из одного исходного
  /// состояния и требует совпадения кода, stdout, stderr и файлов
  /// `CODELAB_HOME`. Возвращает результат `codelab`.
  Future<CliResult> expectSame(
    List<String> args, {
    Map<String, String> files = const {'config.yaml': _baseConfig},
    String? stdin,
    StderrCheck stderrCheck = StderrCheck.exact,
  }) async {
    reset(files);
    final cli = await CliProcess.run(
      args,
      environment: environment,
      workingDirectory: project,
      stdin: stdin,
    );
    final cliFiles = homeFiles();

    reset(files);
    final agent = await runAgent(args, stdin: stdin);
    final agentFiles = homeFiles();

    expect(cli.exitCode, agent.exitCode, reason: '$args\n$cli\n$agent');
    expect(cli.stdout, agent.stdout, reason: '$args');
    // Справки и сообщения ошибок использования называют свой бинарь, поэтому
    // у них сверка мягче точной (см. [StderrCheck]).
    final agentStderr = agent.stderr.replaceAll('codelab-agent', 'codelab');
    switch (stderrCheck) {
      case StderrCheck.exact:
        expect(cli.stderr, agent.stderr, reason: '$args');
      case StderrCheck.withoutBinaryName:
        expect(cli.stderr, agentStderr, reason: '$args');
      case StderrCheck.firstLine:
        expect(
          cli.stderr.split('\n').first,
          agentStderr.split('\n').first,
          reason: '$args',
        );
      case StderrCheck.presence:
        expect(cli.stderr.isEmpty, agent.stderr.isEmpty, reason: '$args');
    }
    expect(cliFiles, agentFiles, reason: '$args');
    return cli;
  }

  test('config set: байты config.yaml, stdout и код как у codelab-agent, '
      'комментарии сохранены', () async {
    final cli = await expectSame(['config', 'set', 'budget.max_steps', '10']);

    expect(cli.exitCode, 0, reason: '$cli');
    expect(cli.stdout, 'Updated budget.max_steps in $home/config.yaml\n');
    final text = File('$home/config.yaml').readAsStringSync();
    expect(text, contains('# my settings'));
    expect(text, contains('max_steps: 10 # three'));
  }, tags: scriptedOnly);

  test('config unset, get и path совпадают с codelab-agent', () async {
    await expectSame(['config', 'unset', 'budget.max_steps']);
    await expectSame(['config', 'unset', 'budget.max_steps_absent']);
    final get = await expectSame(['config', 'get', 'budget.max_steps']);
    expect(get.stdout, '3\nlayer: user\n');
    await expectSame(['config', 'get', 'budget.max_steps', '--layer', 'user']);
    await expectSame(['config', 'get', 'agent.default_model']);
    await expectSame(['config', 'path']);
    await expectSame(['config', 'path', '--project']);
  }, tags: scriptedOnly);

  test('config set --local через общий -C: файл проекта, глобальный не '
      'тронут', () async {
    reset({'config.yaml': _baseConfig});

    final result = await CliProcess.run([
      '-C',
      project,
      'config',
      'set',
      'permissions.mode',
      'plan',
      '--local',
    ], environment: environment);

    expect(result.exitCode, 0, reason: '$result');
    expect(
      File('$project/.codelab/config.local.yaml').readAsStringSync(),
      contains('mode: plan'),
    );
    expect(File('$home/config.yaml').readAsStringSync(), _baseConfig);
  }, tags: scriptedOnly);

  test('ошибки записи совпадают с codelab-agent: неизвестный ключ, '
      'неверное значение, литеральный секрет', () async {
    for (final args in [
      ['config', 'set', 'budget.max_stepz', '10'],
      ['config', 'set', 'budget.max_steps', 'abc'],
      ['config', 'set', 'providers.p.api_key', 'sk-test-0123456789abcdef'],
      ['config', 'get', 'nothing.here'],
    ]) {
      final cli = await expectSame(args);
      expect(cli.exitCode, isNot(0), reason: '$args');
      expect(cli.stdout + cli.stderr, isNot(contains('sk-test-0123456789')));
    }
  }, tags: scriptedOnly);

  test('provider add --api-key-stdin, list и remove совпадают с '
      'codelab-agent; ключ не в выводе и не в конфиге', () async {
    const key = 'sk-test-0123456789abcdef';
    final add = await expectSame([
      'provider',
      'add',
      'gw',
      '--kind',
      'openai-compatible',
      '--base-url',
      'https://x/v1',
      '--model',
      'm',
      '--context-window',
      '8192',
      '--api-key-stdin',
    ], stdin: '$key\n');
    expect(add.exitCode, 0, reason: '$add');
    expect(add.stdout + add.stderr, isNot(contains(key)));
    expect(File('$home/config.yaml').readAsStringSync(), isNot(contains(key)));

    const withProvider = {
      'config.yaml': '''
secrets:
  backend: file
providers:
  gw:
    kind: openai-compatible
    base_url: https://x/v1
    api_key_secret: codelab/gw
    models:
      m: {context_window: 8192}
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''',
    };
    final list = await expectSame(['provider', 'list'], files: withProvider);
    expect(list.stdout, startsWith('Secrets: file\n'), reason: '$list');
    await expectSame(['provider', 'remove', 'gw'], files: withProvider);
    await expectSame(['provider', 'remove', 'absent'], files: withProvider);
  }, tags: scriptedOnly);

  test('mcp add, list, remove совпадают с codelab-agent; комментарии '
      'сохранены', () async {
    final add = await expectSame([
      'mcp',
      'add',
      'docs',
      '--type',
      'stdio',
      '--command',
      'docs-mcp',
      '--arg',
      '--stdio',
    ]);
    expect(add.exitCode, 0, reason: '$add');
    expect(File('$home/config.yaml').readAsStringSync(), contains('# my'));

    const withDocs = {
      'config.yaml': '''
# my settings
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
mcp:
  servers:
    - name: docs
      type: stdio
      command: docs-mcp
      args: [--stdio]
''',
    };
    final list = await expectSame(['mcp', 'list'], files: withDocs);
    for (final word in ['docs', 'stdio', 'user', 'enabled']) {
      expect(list.stdout, contains(word));
    }
    await expectSame(['mcp', 'remove', 'docs'], files: withDocs);
    expect(
      File('$home/config.yaml').readAsStringSync(),
      contains('# my settings'),
    );
    await expectSame([
      'mcp',
      'add',
      'github',
      '--type',
      'http',
      '--url',
      'https://h',
      '--header',
      'Authorization=Bearer ghp_x',
    ]);
  }, tags: scriptedOnly);

  test('флаги подключения вместе с подкомандами: 64, stdout пуст, файлы не '
      'изменены, агент не запущен', () async {
    reset({'config.yaml': _baseConfig});
    for (final args in [
      ['-p', 'hi', 'config', 'set', 'budget.max_steps', '1'],
      ['--agent', 'stdio:x', 'config', 'check'],
      ['--prompt-file', 'f', 'config', 'get', 'budget.max_steps'],
      ['-p', 'hi', 'provider', 'list'],
      ['--ui', 'tui', 'mcp', 'list'],
    ]) {
      final result = await CliProcess.run(
        args,
        environment: environment,
        workingDirectory: project,
      );

      expect(result.exitCode, 64, reason: '$args\n$result');
      expect(result.stdout, isEmpty, reason: '$args');
      expect(result.stderr, contains('does not apply to'), reason: '$args');
    }
    expect(homeFiles(), {'config.yaml': _baseConfig});
  }, tags: scriptedOnly);

  group('ревью итерации 4: новые случаи совпадают с codelab-agent', () {
    const withProviderEnv = {
      'config.yaml': '''
providers:
  gw:
    kind: openai-compatible
    base_url: https://x/v1
    api_key_env: GW_KEY
    models:
      m: {context_window: 8192}
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''',
    };
    const withDocs = {
      'config.yaml': '''
mcp:
  servers:
    - name: docs
      type: stdio
      command: docs-mcp
    - name: other
      type: stdio
      command: other-mcp
''',
    };

    test('смена источника ключа провайдера (R4-4): прежний источник '
        'заменён', () async {
      final cli = await expectSame([
        'provider',
        'add',
        'gw',
        '--kind',
        'openai-compatible',
        '--model',
        'm',
        '--context-window',
        '8192',
        '--api-key-secret',
        'codelab/gw',
      ], files: withProviderEnv);

      expect(cli.exitCode, 0, reason: '$cli');
      final text = File('$home/config.yaml').readAsStringSync();
      expect(text, contains('api_key_secret: codelab/gw'));
      expect(text, isNot(contains('api_key_env')));
    }, tags: scriptedOnly);

    test('mcp remove 0 не удаляет сервер по индексу', () async {
      final cli = await expectSame(['mcp', 'remove', '0'], files: withDocs);

      expect(cli.exitCode, 0, reason: '$cli');
      expect(
        File('$home/config.yaml').readAsStringSync(),
        withDocs['config.yaml'],
      );
    }, tags: scriptedOnly);

    test('mcp remove с недопустимым именем: 64 у обоих, один текст', () async {
      final cli = await expectSame(['mcp', 'remove', 'a b']);

      expect(cli.exitCode, 64, reason: '$cli');
      expect(cli.stdout, isEmpty);
      expect(
        cli.stderr,
        'mcp remove: the server name must not contain whitespace, [, ] or '
        '"\n',
      );
    }, tags: scriptedOnly);

    test('config unset ключа со значением null удаляет его', () async {
      final cli = await expectSame(
        ['config', 'unset', 'budget.max_steps'],
        files: {
          'config.yaml': '$_withDefaultModel# c\nbudget:\n  max_steps: null\n',
        },
      );

      expect(cli.exitCode, 0, reason: '$cli');
      expect(cli.stdout, startsWith('Removed budget.max_steps from'));
      expect(
        File('$home/config.yaml').readAsStringSync(),
        isNot(contains('max_steps')),
      );
    }, tags: scriptedOnly);

    test('--project вместе с --local: 64 и один текст у обоих', () async {
      for (final args in [
        ['config', 'set', 'budget.max_steps', '1', '--project', '--local'],
        ['config', 'unset', 'budget.max_steps', '--project', '--local'],
        ['config', 'path', '--project', '--local'],
        ['provider', 'remove', 'gw', '--project', '--local'],
        ['mcp', 'remove', 'docs', '--project', '--local'],
      ]) {
        final cli = await expectSame(args);

        expect(cli.exitCode, 64, reason: '$args\n$cli');
        expect(cli.stdout, isEmpty, reason: '$args');
        expect(
          cli.stderr,
          contains('--project and --local cannot be combined'),
          reason: '$args',
        );
      }
    }, tags: scriptedOnly);

    test(
      'provider add без флагов: 64, одна строка, файлы не созданы',
      () async {
        final cli = await expectSame(['provider', 'add', 'gw'], files: {});

        expect(cli.exitCode, 64, reason: '$cli');
        expect(cli.stdout, isEmpty);
        expect(
          cli.stderr,
          'provider add: missing required options: '
          '--kind, --model, --context-window\n',
        );
        expect(Directory(home).listSync(), isEmpty);
      },
      tags: scriptedOnly,
    );

    test('неизвестная подкоманда provider и mcp не цитируется', () async {
      for (final args in [
        ['provider', 'frob'],
        ['mcp', 'frob'],
      ]) {
        final cli = await expectSame(
          args,
          stderrCheck: StderrCheck.withoutBinaryName,
        );

        expect(cli.exitCode, 64, reason: '$args');
        expect(cli.stdout, isEmpty);
        expect(cli.stderr, contains('unknown ${args.first} arguments (1)'));
        expect(cli.stderr, isNot(contains('frob')));
      }
    }, tags: scriptedOnly);

    test('ошибка разбора argv не цитирует слова: set со значением на '
        '«--», provider и mcp с неизвестным флагом', () async {
      for (final args in [
        ['config', 'set', 'budget.max_steps', '--sk-LEAK-0123456789'],
        ['config', 'unset', '--sk-LEAK-0123456789'],
        ['--X-LEAK-0123456789', 'provider', 'add', 'gw'],
        ['mcp', 'add', 'x', '--bogus=LEAK-0123456789'],
      ]) {
        final cli = await expectSame(args, stderrCheck: StderrCheck.firstLine);

        expect(cli.exitCode, 64, reason: '$args\n$cli');
        expect(cli.stdout, isEmpty);
        expect(cli.stderr, startsWith('codelab: invalid arguments for'));
        expect('${cli.stdout}${cli.stderr}', isNot(contains('LEAK')));
      }
    }, tags: scriptedOnly);

    test('маскирование адреса в config get и provider list (R4-5)', () async {
      const files = {
        'config.yaml': '''
providers:
  p:
    kind: openai-compatible
    base_url: https://user:hunter2pass@llm.test/v1?token=abcdef0123456789
    models:
      m: {}
agent:
  default_model: p/m
''',
      };
      final get = await expectSame([
        'config',
        'get',
        'providers.p.base_url',
      ], files: files);
      final list = await expectSame(['provider', 'list'], files: files);

      for (final result in [get, list]) {
        expect(result.exitCode, 0, reason: '$result');
        expect(result.stdout, isNot(contains('hunter2pass')));
        expect(result.stdout, isNot(contains('abcdef0123456789')));
      }
    }, tags: scriptedOnly);

    test('provider list --cwd и mcp list --cwd: слой local доверенного '
        'проекта, как у codelab-agent', () async {
      // Каталог `other` — не текущий каталог процесса (`project`): конфиг
      // читается именно из-за `--cwd`. У `codelab-agent` общего `-C` нет,
      // поэтому приоритет `--cwd` над `-C` проверяет юнит-тест CLI.
      final other = '${tmp.path}/other';
      Directory('$other/.codelab').createSync(recursive: true);
      File('$other/.codelab/config.local.yaml').writeAsStringSync('''
providers:
  loc:
    kind: openai-compatible
    base_url: https://l/v1
    api_key_env: LOC_KEY
    models:
      m: {context_window: 8192}
agent:
  default_model: loc/m
mcp:
  servers:
    - name: docs
      type: http
      url: https://h
''');
      final files = {'config.yaml': 'trusted_projects: ["$other"]\n'};

      final mcp = await expectSame([
        'mcp',
        'list',
        '--cwd',
        other,
      ], files: files);
      expect(mcp.exitCode, 0, reason: '$mcp');
      expect(mcp.stdout, allOf(contains('docs'), contains('local')));

      final provider = await expectSame([
        'provider',
        'list',
        '--cwd',
        other,
      ], files: files);
      expect(provider.exitCode, 0, reason: '$provider');
      expect(provider.stdout, contains('loc'));
    }, tags: scriptedOnly);

    // Набор флагов каждой листовой подкоманды один и тот же: флаг, который
    // принимает один бинарь, принимает и другой (ревью итерации 4, arch L2).
    // Для каждой пары «подкоманда × флаг» сверяются код, stdout, первая
    // строка stderr и файлы: отвергнутый флаг даёт `invalid arguments` или
    // причину разбора у обоих, принятый — один и тот же результат.
    test(
      'набор флагов листовых подкоманд config|provider|mcp совпадает',
      () async {
        final leaves = <List<String>>[
          ['config', 'check'],
          ['config', 'path'],
          ['config', 'get', 'budget.max_steps'],
          ['config', 'set', 'budget.max_steps', '5'],
          ['config', 'unset', 'budget.max_steps'],
          ['provider', 'add', 'gw'],
          ['provider', 'list'],
          ['provider', 'remove', 'gw'],
          ['mcp', 'add', 'x'],
          ['mcp', 'list'],
          ['mcp', 'remove', 'x'],
        ];
        final flags = <List<String>>[
          ['--cwd', project],
          ['--layer', 'user'],
          ['--project'],
          ['--local'],
        ];
        for (final leaf in leaves) {
          for (final flag in flags) {
            // У `provider|mcp add|remove` `--cwd` подкоманды нет, но `--cwd` —
            // длинная форма общего `-C` верхнего парсера `codelab`, и
            // `package:args` принимает его после подкоманды: это папка по
            // спеке, а не расхождение набора флагов подкоманды.
            if (flag.first == '--cwd' &&
                (leaf.first == 'provider' || leaf.first == 'mcp') &&
                leaf[1] != 'list') {
              continue;
            }
            await expectSame(
              [...leaf, ...flag],
              // Причину неизвестного флага у `config check|get|path` бинари
              // формулируют по-своему; у остальных первая строка общая.
              stderrCheck:
                  leaf.first == 'config' && !{'set', 'unset'}.contains(leaf[1])
                  ? StderrCheck.presence
                  : StderrCheck.firstLine,
            );
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 8)),
      tags: scriptedOnly,
    );
  });
}
