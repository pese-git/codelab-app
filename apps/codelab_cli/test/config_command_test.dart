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
    temp = Directory.systemTemp.createTempSync('codelab_cli_config_cmd_');
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

  for (final args in [
    ['config', 'set', 'budget.max_steps', '10'],
    ['config', 'migrate'],
    ['config', 'get', 'x'],
    ['config', 'unset', 'x'],
    ['config', 'path'],
  ]) {
    test('${args.join(' ')}: 64, Unknown command, file untouched', () async {
      final file = File('$project/.codelab/config.yaml')
        ..writeAsStringSync('budget:\n  max_steps: 3\n');

      final (code, io) = await run(args);

      expect(code, 64);
      expect(io.stderrText, contains('Unknown command'));
      expect(io.stdoutText, isEmpty);
      expect(file.readAsStringSync(), 'budget:\n  max_steps: 3\n');
    });
  }

  test('config without a subcommand is a usage error, code 64', () async {
    final (code, io) = await run(['config']);

    expect(code, 64);
    expect(io.stdoutText, isEmpty);
    expect(io.stderrText, contains('config check'));
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
      final expected = ConfigCommands().check(
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
}
