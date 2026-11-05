// E2E `cli/headless-print-basic` (tasks 3.6; H-01, U-06; spec cli-headless
// «Источники промпта headless», «Вывод headless»; codelab-cli «Профили
// подключения CLI»): собранный CLI против агента `CODELAB_E2E_AGENT`
// (testing-quality «PTY-e2e терминального клиента»).

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';

Future<void> main() async {
  final agentSkip = await E2eCliAgent.current.unavailable();
  late Directory tmp;
  late Map<String, String> environment;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_cli_e2e_');
    environment = {'CODELAB_HOME': '${tmp.path}/home'};
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'cli/headless-print-basic: the answer goes to stdout and the exit '
    'code is 0',
    () async {
      final launch = await E2eCliAgent.current.launch(tmp);

      final result = await CliProcess.run(
        ['-p', 'hello', '-a', launch.agent, '-C', tmp.path],
        environment: {...environment, ...launch.environment},
      );

      expect(result.exitCode, 0, reason: '$result');
      expect(result.stdout, '${launch.answer}\n');
    },
    skip: agentSkip,
    tags: pythonAgent,
  );

  test(
    'cli/headless-print-basic: a stored profile is used with -a <id>',
    () async {
      final launch = await E2eCliAgent.current.launch(tmp);
      final saved = await CliProcess.run([
        'profiles',
        'add',
        e2eProfileId,
        launch.agent,
      ], environment: environment);
      expect(saved.exitCode, 0, reason: '$saved');

      final result = await CliProcess.run([
        '-a',
        e2eProfileId,
        '-p',
        'hello',
        '-C',
        tmp.path,
      ], environment: environment);

      expect(result.exitCode, 0, reason: '$result');
      expect(result.stdout, '${launch.answer}\n');
    },
    skip: agentSkip ?? E2eCliAgent.current.needsStoredProfile,
    tags: pythonAgent,
  );

  // Без `--agent` запускается встроенный агент (D21); без
  // конфига рабочий бинарь отвечает кодом 64 с проблемой конфигурации и
  // подсказкой, а процесс агента не стартует (spec codelab-cli «Без профиля и
  // без конфига»; design.md change `add-embedded-agent-mode`, D5, D13 п. 1).
  test('cli/headless-print-basic: an empty CODELAB_HOME without --agent is '
      '64 with the embedded config hint, and no agent starts', () async {
    final result = await CliProcess.run(
      ['-p', 'hi', '-C', tmp.path],
      environment: environment,
      entry: CliEntry.production,
    );

    expect(result.exitCode, 64, reason: '$result');
    expect(result.stdout, isEmpty);
    expect(
      result.stderr,
      contains(
        'Configure the embedded agent in ${tmp.path}/home/config.yaml; '
        'check it with: codelab config check',
      ),
    );
  });

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

  test('cli/headless-print-basic: a start failure of a profile with one '
      'argument says "1 argument" and hides the value', () async {
    final result = await CliProcess.run([
      '-p',
      'hi',
      '-a',
      'stdio:/nonexistent/agent --stdio',
      '-C',
      tmp.path,
    ], environment: environment);

    expect(result.exitCode, 1, reason: '$result');
    expect(result.stdout, isEmpty);
    expect(
      result.stderr,
      contains(
        'codelab: cannot start the agent "/nonexistent/agent" with 1 '
        'argument:',
      ),
    );
    expect(result.stderr, isNot(contains('--stdio')));
  }, tags: scriptedOnly);

  // Регрессионная защита, а не доказательство D8: строка журнала печатает
  // `AcpTransportException.toString()` без вложенного `cause`, поэтому и до
  // D8 аргументов в ней не было (design.md, Context). Тест ловит будущий путь,
  // который выведет причину целиком; `SecretRedactor` флаг `--api-key` не
  // знает.
  test('cli/headless-print-basic: --verbose does not leak the arguments of '
      'a start failure through the log', () async {
    final result = await CliProcess.run([
      '-p',
      'hi',
      '--verbose',
      '-a',
      'stdio:/nonexistent/agent --api-key sk-test-leak-0123456789 '
          'sk-test-leak-0123456789',
      '-C',
      tmp.path,
    ], environment: environment);

    expect(result.exitCode, 1, reason: '$result');
    for (final out in [result.stdout, result.stderr]) {
      expect(out, isNot(contains('sk-test-leak-0123456789')));
      expect(out, isNot(contains('--api-key')));
    }
  }, tags: scriptedOnly);

  test('cli/headless-print-basic: a start failure prints the command and the '
      'argument count, not the values', () async {
    final result = await CliProcess.run([
      '-p',
      'hi',
      '-a',
      'stdio:/nonexistent/agent --api-key sk-test-leak-0123456789 sk-test-leak-0123456789',
      '-C',
      tmp.path,
    ], environment: environment);

    expect(result.exitCode, 1, reason: '$result');
    expect(result.stdout, isEmpty);
    expect(
      result.stderr,
      contains(
        'codelab: cannot start the agent "/nonexistent/agent" with 3 '
        'arguments:',
      ),
    );
    expect(result.stderr, isNot(contains('sk-test-leak-0123456789')));
    expect(result.stderr, isNot(contains('--api-key')));
  }, tags: scriptedOnly);

  test('cli/headless-print-basic: a value without a prefix is not repeated '
      'in the unknown-profile error', () async {
    final result = await CliProcess.run([
      '-p',
      'hi',
      '-a',
      'my-agent --api-key sk-test-leak-0123456789 sk-test-leak-0123456789',
      '-C',
      tmp.path,
    ], environment: environment);

    expect(result.exitCode, 64, reason: '$result');
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('Unknown agent profile.'));
    expect(result.stderr, isNot(contains('sk-test-leak-0123456789')));
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
