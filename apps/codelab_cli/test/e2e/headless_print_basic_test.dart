// E2E `cli/headless-print-basic` (tasks 3.6; H-01, U-06; spec cli-headless
// «Источники промпта headless», «Вывод headless»; codelab-cli «Профили
// подключения CLI»): собранный CLI против агента `CODELAB_E2E_AGENT`
// (testing-quality «PTY-e2e терминального клиента»).

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';

void main() {
  late Directory tmp;
  late Map<String, String> environment;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_cli_e2e_');
    environment = {'CODELAB_HOME': '${tmp.path}/home'};
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('cli/headless-print-basic: the answer goes to stdout and the exit '
      'code is 0', () async {
    final launch = await E2eCliAgent.current.launch(tmp);

    final result = await CliProcess.run([
      '-p',
      'hello',
      '-a',
      launch.agent,
      '-C',
      tmp.path,
    ], environment: environment);

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, '${launch.answer}\n');
  });

  test('cli/headless-print-basic: the default profile is used without '
      '--agent', () async {
    final launch = await E2eCliAgent.current.launch(tmp);
    final saved = await CliProcess.run([
      'profiles',
      'add',
      'default',
      launch.agent,
    ], environment: environment);
    expect(saved.exitCode, 0, reason: '$saved');

    final result = await CliProcess.run([
      '-p',
      'hello',
      '-C',
      tmp.path,
    ], environment: environment);

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, '${launch.answer}\n');
  });

  test('cli/headless-print-basic: an empty CODELAB_HOME without --agent is '
      '64 with the hint, and no agent starts', () async {
    final result = await CliProcess.run([
      '-p',
      'hi',
      '-C',
      tmp.path,
    ], environment: environment);

    expect(result.exitCode, 64, reason: '$result');
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('codelab profiles add default'));
  }, tags: scriptedOnly);

  test('cli/headless-print-basic: an agent that cannot start is 1', () async {
    final result = await CliProcess.run([
      '-p',
      'hi',
      '-a',
      'stdio:/nonexistent/agent',
      '-C',
      tmp.path,
    ], environment: environment);

    expect(result.exitCode, 1, reason: '$result');
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('/nonexistent/agent'));
  }, tags: scriptedOnly);

  test('an unknown flag is 64 with an empty stdout', () async {
    final result = await CliProcess.run([
      '--output-format',
      'stream-json',
      '-p',
      'hi',
    ], environment: environment);

    expect(result.exitCode, 64, reason: '$result');
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('Unknown flag --output-format'));
  }, tags: scriptedOnly);
}
