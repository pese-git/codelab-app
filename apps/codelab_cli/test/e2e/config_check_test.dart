// E2E `cli/config-check-reports-issues` (задача 11.3; spec codelab-cli
// «Подкоманда codelab config»; agent-configuration «Одинаковый вывод у двух
// бинарей»; design.md change `add-agent-configuration`, D13, D14): собранный
// CLI и собранный `codelab-agent` на одних и тех же файлах и окружении.
//
// Агент здесь не нужен как собеседник: `config check` не запускает ни
// транспорт, ни процесс агента. Бинарь агента запускается только ради
// сравнения вывода (kernel компилирует `E2eCliAgent.agentKernel`).
//
// Тег `scripted-only` на каждом тесте: файл не зависит от агента матрицы, и
// без тега `test:e2e:cli:dart-agent` гонял бы его повторно (D5 change
// `add-cli-e2e-agent-matrix`).
@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';

void main() {
  late Directory tmp;
  late String home;
  late String project;
  late Map<String, String> environment;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_cli_e2e_config_');
    home = '${tmp.path}/home';
    project = '${tmp.path}/project';
    Directory(home).createSync();
    Directory('$project/.codelab').createSync(recursive: true);
    File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''');
    File(
      '$project/.codelab/config.yaml',
    ).writeAsStringSync('budget:\n  max_steps: 0\n');
    // Одно окружение у обоих бинарей, включая HOME: иначе различие вывода
    // можно списать на разные `~/.codelab`.
    environment = {'CODELAB_HOME': home, 'HOME': '${tmp.path}/no-home'};
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Относительные пути и размеры всех файлов под [root]: снимок «до/после».
  Map<String, String> snapshot(String root) => {
    for (final entity in Directory(root).listSync(recursive: true))
      entity.path.substring(root.length): entity is File
          ? '${entity.lengthSync()}:${entity.readAsStringSync()}'
          : 'dir',
  };

  // Тест не зависит от агента e2e-матрицы (`CODELAB_E2E_AGENT`): он быстрый и
  // сам ничего не запускает, кроме двух бинарей.
  test('cli/config-check-reports-issues: a project issue gives code 1 and no '
      'agent process', () async {
    final homeBefore = snapshot(home);
    final projectBefore = snapshot('$project/.codelab');

    final result = await CliProcess.run([
      'config',
      'check',
      '--cwd',
      project,
    ], environment: environment);

    expect(result.exitCode, 1, reason: '$result');
    expect(result.stdout, contains('budget.max_steps'));
    expect(result.stdout, contains('config.yaml:'));
    expect(
      result.stdout.trimRight().split('\n').last,
      'Config: invalid (issues: 1)',
    );
    // Агент не запускался и ничего не писал: в CODELAB_HOME остался только
    // исходный `config.yaml` (нет `sessions/`, `profiles.json`,
    // `cli_history`), проектная `.codelab` не тронута.
    expect(snapshot(home), homeBefore);
    expect(homeBefore.keys, ['/config.yaml']);
    expect(snapshot('$project/.codelab'), projectBefore);
  }, tags: scriptedOnly);

  for (final args in [
    ['config', 'set', 'budget.max_steps', '10'],
    ['config', 'migrate'],
  ]) {
    test(
      '${args.join(' ')}: 64 and Unknown command, config untouched',
      () async {
        final result = await CliProcess.run(args, environment: environment);

        expect(result.exitCode, 64, reason: '$result');
        expect(result.stderr, contains('Unknown command'));
        expect(result.stdout, isEmpty);
        expect(
          File('$project/.codelab/config.yaml').readAsStringSync(),
          'budget:\n  max_steps: 0\n',
        );
      },
      tags: scriptedOnly,
    );
  }

  test(
    'the output and the exit code match codelab-agent config check',
    () async {
      final cli = await CliProcess.run([
        'config',
        'check',
        '--cwd',
        project,
      ], environment: environment);

      // Процесс агента с таймаутом и kill в tearDown: зависший бинарь не
      // должен остаться сиротой после падения теста.
      final agentProcess = await Process.start(
        dartExecutable(),
        [await E2eCliAgent.agentKernel(), 'config', 'check', '--cwd', project],
        environment: {
          'PATH': Platform.environment['PATH'] ?? '',
          ...environment,
        },
        includeParentEnvironment: false,
      );
      addTearDown(() => agentProcess.kill(ProcessSignal.sigkill));
      final agentOut = utf8.decodeStream(agentProcess.stdout);
      final agentErr = utf8.decodeStream(agentProcess.stderr);
      final agentCode = await agentProcess.exitCode.timeout(
        const Duration(seconds: 60),
      );
      final agent = (
        exitCode: agentCode,
        stdout: await agentOut,
        stderr: await agentErr,
      );

      expect(cli.exitCode, agent.exitCode, reason: '$cli');
      expect(cli.stdout, agent.stdout);
      expect(cli.stderr, agent.stderr);
    },
    tags: scriptedOnly,
  );
}
