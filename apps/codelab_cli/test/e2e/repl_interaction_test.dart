// PTY-e2e взаимодействия в REPL (tasks 7.7; spec codelab-cli «Одобрение в
// REPL», «Slash-меню и клиентские команды», «Сессии в REPL»; testing-quality
// «PTY-e2e терминального клиента»; design.md change `add-codelab-cli`, D11).
@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart'
    show CodelabCompatibleStdioAgentMode;
import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';
import 'support/pty_process.dart';

Future<void> main() async {
  final skip = await PtyProcess.unavailableReason();
  late Directory dir;
  late E2eCliLaunch launch;

  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_repl_'));
  tearDown(() => dir.delete(recursive: true));

  Future<PtyProcess> repl(
    CodelabCompatibleStdioAgentMode mode, {
    List<String> args = const [],
  }) async {
    launch = await E2eCliAgent.current.launch(dir, mode: mode);
    return PtyProcess.start(
      dartExecutable(),
      [
        await CliProcess.kernel(),
        '--agent',
        launch.agent,
        '--cwd',
        dir.path,
        ...args,
      ],
      environment: {
        'HOME': '${dir.path}/home',
        'CODELAB_HOME': '${dir.path}/codelab',
        'LANG': 'en_US.UTF-8',
      },
    );
  }

  /// Вводит [line] с Enter и ждёт [text] в выводе после ввода.
  Future<void> send(PtyProcess pty, String line, String text) async {
    final from = pty.text.length;
    pty.write('$line\r');
    await pty.waitFor(text, from: from);
  }

  test('cli/repl-permission-allow-once', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.withPermissionRequest,
      args: ['run it'],
    );
    await pty.waitFor('[y] allow once');
    expect(pty.text, contains('Permission: ${launch.permissionTitle}'));
    expect(pty.text, contains('command: ${launch.permissionCommand}'));

    pty.write('y');

    await pty.waitFor(launch.allowedMarker);
    pty.write('\x04');
    expect(await pty.exitCode, 0);
  }, skip: skip);

  test('cli/repl-permission-reject', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.withPermissionRequest,
      args: ['run it'],
    );
    await pty.waitFor('[n] reject once');

    pty.write('n');

    await pty.waitFor(launch.rejectedMarker);
    pty.write('\x04');
    expect(await pty.exitCode, 0);
  }, skip: skip);

  test(
    'cli/slash-menu-merges-agent-commands',
    () async {
      final pty = await repl(
        CodelabCompatibleStdioAgentMode.withAvailableCommands,
      );
      await pty.waitFor('> ');
      // Команды агент объявляет после ответа на `session/new`: ждём, пока
      // они дойдут, по Tab на их префиксе.
      final from = pty.text.length;
      pty.write('/\t');
      await pty.waitFor('/compact', from: from);
      expect(pty.text.substring(from), contains('(agent)'));
      expect(pty.text.substring(from), contains('/agent:plan'));
      expect(pty.text.substring(from), contains('/help'));

      pty.write('\x15');
      await send(pty, '/agent:plan the release', 'echo: /plan the release');
      await send(pty, '/plan', 'No plan yet.');
      pty.write('\x04');
      expect(await pty.exitCode, 0);
      // Dart-агент объявит свои команды на этапе 8 (R-07, R-08).
    },
    skip: skip,
    tags: scriptedOnly,
  );

  test('cli/client-commands-smoke', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.withSessionList,
      args: ['first prompt'],
    );
    final answer = launch.sessionAnswer('first prompt');
    await pty.waitFor(answer);

    await send(pty, '/help', '/help keys');
    await send(pty, '/new', 'New session');
    // Scripted-агент не шлёт `session_info_update`, и строка списка
    // показывает id; Dart-агент называет сессию по первому промпту.
    final listed = launch.listedSession('first prompt');
    await send(pty, '/sessions', listed);
    final listing = pty.text.substring(pty.text.lastIndexOf('/sessions'));
    final number = RegExp(
      '(\\d+)\\. ${RegExp.escape(listed)} ',
    ).firstMatch(listing)!.group(1)!;
    await send(pty, '/resume $number', answer);
    await send(pty, '/cancel', 'Nothing to cancel.');
    pty.write('/exit\r');

    expect(await pty.exitCode, 0);
  }, skip: skip);

  test('cli/model-picker-sets-config-option', () async {
    final pty = await repl(CodelabCompatibleStdioAgentMode.withConfigOptions);
    await pty.waitFor('> ');

    final [current, next] = launch.models;
    await send(pty, '/model', '* $current');
    await send(pty, '/model $next', 'model = $next');
    await send(pty, '/model', '* $next');
    await send(pty, '/model zzz', 'Unknown model "zzz"');
    pty.write('\x04');
    expect(await pty.exitCode, 0);
  }, skip: skip);
}
