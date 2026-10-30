import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// `codelab-agent serve` с невалидным конфигом (agent-binary «Конфиг бинаря
/// из файлов, окружения и флагов», сценарий «Битый конфиг не доходит до
/// первого хода»; «Логи бинаря»; задача 9.2, design.md change
/// `add-agent-configuration`, D4, D16). Интеграционный тест на Dart VM:
/// процесс бинаря в временном каталоге, stdin не читается.
void main() {
  late Directory temp;
  late String project;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_invalid_');
    project = '${temp.path}/project';
    Directory('$project/.codelab').createSync(recursive: true);
  });

  tearDown(() => temp.delete(recursive: true));

  Future<AgentProcess> start(List<String> extra) async {
    final agent = await AgentProcess.start(
      ['serve', '--stdio', ...extra],
      environment: {'CODELAB_HOME': '${temp.path}/home'},
      workingDirectory: project,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    return agent;
  }

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

  test('an unknown key: code 64 before stdin, file:line:column and the key '
      'path in stderr and in the log', () async {
    File('$project/.codelab/config.yaml').writeAsStringSync(
      'providers:\n  p:\n    kind: openai-compatible\n    base_url: https://llm.test/v1\n'
      '    models:\n      m: {}\nbudget:\n  max_stepz: 3\nagent:\n  default_model: p/m\n',
    );
    final logFile = '${temp.path}/logs/agent.log';

    final agent = await start(['--log-file', logFile]);

    // stdin не закрывается и ничего не получает: процесс обязан выйти сам.
    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 64);
    expect(agent.stderrText, contains('config.yaml:8:3'));
    expect(agent.stderrText, contains('budget.max_stepz'));
    expect(agent.stderrText, contains('serve.config.invalid'));
    final logged = File(logFile).readAsStringSync();
    expect(logged, contains('serve.config.invalid'));
    expect(logged, contains('"key":"budget.max_stepz"'));
    expect(logged, contains('"line":8'));
    expect(await agent.nextStdoutLine(), isNull, reason: 'stdout stays empty');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a key written as a value: the secret is in neither stderr nor the '
      'log file', () async {
    File('$project/.codelab/config.yaml').writeAsStringSync(
      'providers:\n  p:\n    kind: openai-compatible\n'
      '    base_url: https://llm.test/v1\n    api_key: sk-test-secret\n'
      '    models:\n      m: {}\nagent:\n  default_model: p/m\n',
    );
    final logFile = '${temp.path}/logs/agent.log';

    final agent = await start(['--log-file', logFile, '--log-level', 'trace']);

    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 64);
    expect(agent.stderrText, contains('config.yaml:5:'));
    expect(agent.stderrText, contains('providers.p.api_key'));
    expect(agent.stderrText, isNot(contains('sk-test-secret')));
    expect(File(logFile).readAsStringSync(), isNot(contains('sk-test-secret')));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a syntax error of the file has its line', () async {
    File('$project/.codelab/config.yaml').writeAsStringSync(
      '$providers'
      'budget: [1, 2\n',
    );

    final agent = await start(const []);

    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 64);
    expect(agent.stderrText, contains('config.yaml:'));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('no model anywhere: agent.default_model is required, code 64', () async {
    final agent = await start(const []);

    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 64);
    expect(agent.stderrText, contains('agent.default_model'));
    expect(agent.stderrText, contains('required'));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('--config with .toml is a usage error', () async {
    final agent = await start(['--config', '$project/codelab.toml']);

    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 64);
    expect(agent.stderrText, contains('codelab.toml is not supported'));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'CODELAB_CONFIG with .toml is a usage error that names the variable',
    () async {
      final agent = await AgentProcess.start(
        ['serve', '--stdio'],
        environment: {
          'CODELAB_HOME': '${temp.path}/home',
          'CODELAB_CONFIG': 'x.toml',
        },
        workingDirectory: project,
      );
      addTearDown(() => agent.kill9());

      expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 64);
      expect(agent.stderrText, contains('CODELAB_CONFIG'));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('--config to a missing file: code 64, stderr names --config and '
      'cannot read the file', () async {
    final agent = await start(['--config', '$project/nope.yaml']);

    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 64);
    expect(agent.stderrText, contains('--config'));
    expect(agent.stderrText, contains('cannot read the file'));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
