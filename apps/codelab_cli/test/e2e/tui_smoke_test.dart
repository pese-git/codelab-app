// PTY-e2e полноэкранного режима `cli/tui-smoke` (tasks 3.3, 5.5 change
// `add-cli-tui`; spec codelab-tui «Одобрение в TUI», «Команды и пикеры TUI»; spec codelab-tui «Запуск полноэкранного режима»,
// «Восстановление терминала после TUI»; testing-quality «PTY-e2e
// терминального клиента»; §12.2.13; design.md, D13).
//
// PTY не отвечает на запросы терминала (DECRQM, kitty), поэтому здесь
// проверяется путь без synchronized output и без kitty; путь с ними — тест
// адаптера `test/tui/tui_app_test.dart`.
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

  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_tui_'));
  tearDown(() => dir.delete(recursive: true));

  Future<PtyProcess> tui(
    CodelabCompatibleStdioAgentMode mode, {
    List<String> args = const [],
  }) async {
    launch = await E2eCliAgent.current.launch(dir, mode: mode);
    return PtyProcess.start(
      'sh',
      [
        '-c',
        r'"$0" "$@"; code=$?; echo; echo "[stty] $(stty -a)"; exit $code',
        dartExecutable(),
        await CliProcess.kernel(),
        '--agent',
        launch.agent,
        '--cwd',
        dir.path,
        '--ui',
        'tui',
        ...args,
      ],
      columns: 100,
      rows: 30,
      environment: {
        'HOME': '${dir.path}/home',
        'CODELAB_HOME': '${dir.path}/codelab',
        'LANG': 'en_US.UTF-8',
      },
    );
  }

  /// После выхода: основной экран, bracketed paste выключен, курсор виден,
  /// терминал канонический и с эхо (TUI-4).
  void expectRestored(PtyProcess pty) {
    final text = pty.text;
    expect(text, contains('\x1b[?1049l'));
    expect(text, contains('\x1b[?2004l'));
    expect(text, contains('\x1b[?25h'));
    final stty = text.split('[stty] ').last;
    expect(stty, contains('icanon'));
    expect(stty, isNot(contains('-icanon')));
    expect(stty, isNot(contains('-echo ')));
  }

  test('cli/tui-smoke', () async {
    final pty = await tui(CodelabCompatibleStdioAgentMode.normal);
    await pty.waitFor('\x1b[?1049h');

    pty.write('hello');
    pty.write('\r');
    await pty.waitFor(launch.answer);
    pty.write('\x04');

    expect(await pty.exitCode, 0);
    expectRestored(pty);
  }, skip: skip);

  test('cli/tui-smoke: the first message from the arguments', () async {
    final pty = await tui(
      CodelabCompatibleStdioAgentMode.normal,
      args: ['hello'],
    );

    await pty.waitFor(launch.answer);
    pty.write('\x04');

    expect(await pty.exitCode, 0);
    expectRestored(pty);
  }, skip: skip);

  test('cli/tui-smoke: SIGTERM during a turn exits with 143', () async {
    final pty = await tui(
      CodelabCompatibleStdioAgentMode.hangsUntilCancel,
      args: ['slow'],
    );
    await pty.waitFor('> slow');

    // Сигнал — только процессу CLI, как в `repl_turn_test.dart`.
    final killed = await Process.run('pkill', [
      '-TERM',
      '-f',
      '^[^ ]*dart(vm)? .*codelab\\.dill --agent .* --cwd ${dir.path}',
    ]);
    expect(killed.exitCode, 0, reason: '${killed.stderr}');

    expect(await pty.exitCode, 143);
    expectRestored(pty);
  }, skip: skip);

  test('cli/tui-smoke: y allows the permission request once', () async {
    final pty = await tui(
      CodelabCompatibleStdioAgentMode.withPermissionRequest,
      args: ['run it'],
    );
    await pty.waitFor('[y] allow once');
    expect(pty.text, contains('command: ${launch.permissionCommand}'));

    pty.write('y');

    await pty.waitFor(launch.allowedMarker);
    pty.write('\x04');
    expect(await pty.exitCode, 0);
    expectRestored(pty);
  }, skip: skip);

  test('cli/tui-smoke: /model picks the next model', () async {
    final pty = await tui(CodelabCompatibleStdioAgentMode.withConfigOptions);
    await pty.waitFor('\x1b[?1049h');

    pty.write('/model\r');
    final [current, next] = launch.models;
    await pty.waitFor('› $current');
    pty
      ..write('\x1b[B')
      ..write('\r');

    await pty.waitFor('model = $next');
    pty.write('\x04');
    expect(await pty.exitCode, 0);
    expectRestored(pty);
  }, skip: skip);
}
