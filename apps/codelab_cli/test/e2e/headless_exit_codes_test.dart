// E2E headless: коды выхода, политика одобрений и продолжение сессии
// (tasks 4.12; H-01, H-02; spec cli-headless «Коды выхода headless»,
// «Политика одобрений headless», «Источники промпта headless»; codelab-cli
// «Сигналы CLI»). Собранный CLI против scripted stdio-агента.

import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart'
    show CodelabCompatibleStdioAgentMode;
import 'package:test/test.dart';

import '../support/cli_process.dart';

typedef _Mode = CodelabCompatibleStdioAgentMode;

void main() {
  late Directory tmp;
  late Map<String, String> environment;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_cli_e2e_');
    environment = {'CODELAB_HOME': '${tmp.path}/home'};
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<CliResult> run(_Mode mode, List<String> args, {String? stdin}) async {
    final agent = await scriptedAgent(tmp, mode: mode);
    return CliProcess.run(
      [...args, '-a', agent, '-C', tmp.path],
      environment: environment,
      stdin: stdin,
    );
  }

  /// CLI с ходом, который агент не завершит сам; сигнал — после старта
  /// агента и отправки промпта.
  Future<CliProcess> hangingTurn() async {
    final agent = await scriptedAgent(tmp, mode: _Mode.hangsUntilCancel);
    final process = await CliProcess.start([
      '-p',
      'hello',
      '-a',
      agent,
      '-C',
      tmp.path,
      '-v',
    ], environment: environment);
    await process.waitFor('test agent ready');
    // Промпт уходит сразу после `session/new`; пауза с запасом на старт VM.
    await Future<void>.delayed(const Duration(seconds: 1));
    return process;
  }

  group('cli/headless-exit-codes', () {
    test('a provider error is 1 with the reason in stderr', () async {
      final result = await run(_Mode.promptError, ['-p', 'hi']);

      expect(result.exitCode, 1, reason: '$result');
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('Provider is unavailable'));
    });

    test('end_turn without an answer is 1', () async {
      final result = await run(_Mode.emptyResponse, ['-p', 'hi']);

      expect(result.exitCode, 1, reason: '$result');
      expect(result.stdout, isEmpty);
    });

    test('--timeout cancels the turn and is 130', () async {
      final result = await run(_Mode.hangsUntilCancel, [
        '-p',
        'hi',
        '--timeout',
        '1s',
      ]);

      expect(result.exitCode, 130, reason: '$result');
      expect(result.stderr, contains('timeout'));
    });

    test('SIGTERM during the turn is 143', () async {
      final process = await hangingTurn();

      process.kill(ProcessSignal.sigterm);

      expect((await process.result()).exitCode, 143);
    });

    test('SIGINT during the turn is 130', () async {
      final process = await hangingTurn();

      process.kill(ProcessSignal.sigint);

      expect((await process.result()).exitCode, 130);
    });

    test('a prompt from stdin and from -f works like -p', () async {
      final piped = await run(_Mode.normal, [], stdin: 'hello');
      File('${tmp.path}/task.md').writeAsStringSync('hello');
      final fromFile = await run(_Mode.normal, ['-f', '${tmp.path}/task.md']);

      for (final result in [piped, fromFile]) {
        expect(result.exitCode, 0, reason: '$result');
        expect(result.stdout, 'hello from compatible stdio agent\n');
      }
    });

    test('an empty prompt is 64 and starts no agent', () async {
      final result = await run(_Mode.normal, ['-p', '  ']);

      expect(result.exitCode, 64, reason: '$result');
      expect(result.stderr, contains('No prompt.'));
    });
  });

  test('cli/headless-permission-denied: without --approve the request is '
      'rejected once and the decision is in stderr', () async {
    final result = await run(_Mode.withPermissionRequest, ['-p', 'go']);

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, 'approved: reject_once\n');
    expect(
      result.stderr,
      contains('permission "Run test command": reject_once (policy)'),
    );
  });

  group('cli/headless-bypass-flag', () {
    test('--approve allow-all allows a request once and warns', () async {
      final result = await run(_Mode.withPermissionRequest, [
        '-p',
        'go',
        '--approve',
        'allow-all',
      ]);

      expect(result.exitCode, 0, reason: '$result');
      expect(result.stdout, 'approved: allow_once\n');
      expect(result.stderr, contains('allow-all'));
    });

    test('--approve allow-all rejects a critical request', () async {
      final result = await run(_Mode.withCriticalPermission, [
        '-p',
        'clean up',
        '--approve',
        'allow-all',
      ]);

      expect(result.exitCode, 0, reason: '$result');
      expect(result.stdout, 'approved: reject_once\n');
      expect(
        result.stderr,
        contains('permission "Run rm -rf build": reject_once (critical)'),
      );
    });
  });

  test('cli/resume-last-session: -c continues the session of the '
      'folder', () async {
    final first = await run(_Mode.withSessionList, ['-p', 'first']);
    expect(first.exitCode, 0, reason: '$first');
    expect(first.stdout, 'echo: first\n');

    final second = await run(_Mode.withSessionList, ['-c', '-p', 'second']);

    expect(second.exitCode, 0, reason: '$second');
    // Реплей первого хода в stdout не попадает.
    expect(second.stdout, 'echo: second\n');
    final journal =
        jsonDecode(
              File(
                '${tmp.path}/codelab_compatible_stdio_agent.dart.sessions.json',
              ).readAsStringSync(),
            )
            as List;
    expect(journal, hasLength(1));
    expect((journal.single as Map)['turns'], hasLength(2));
  });
}
