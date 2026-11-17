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
        ...launch.environment,
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

  // U-03. Один тест на все агенты: имя начинается с id матрицы parity
  // (D3 change `switch-default-agent-to-dart`). Ожидания — из
  // `launch` (`support/e2e_agent.dart`); против `dart` и `embedded` меню
  // содержит клиентские `/help`, `/mode`, `/model`, `/config`, команды агента
  // с пометкой `(agent)` и одноимённые под префиксом `/agent:`, а
  // `/agent:help` печатает ответ агента (tasks 1.7 change
  // `add-agent-builtin-slash-commands`, D10, Q1, Q8).
  test('cli/slash-menu-merges-agent-commands', () async {
    final scripted = E2eCliAgent.current.isScripted;
    final pty = await repl(
      scripted
          ? CodelabCompatibleStdioAgentMode.withAvailableCommands
          : CodelabCompatibleStdioAgentMode.normal,
    );
    await pty.waitFor('> ');
    // Команды агент объявляет после ответа на `session/new`: ждём, пока
    // они дойдут, по Tab на их префиксе.
    final from = pty.text.length;
    pty.write('/\t');
    final expected = [...launch.agentCommands, ...launch.prefixedAgentCommands];
    for (final command in expected) {
      await pty.waitFor(command, from: from);
    }
    final menu = pty.text.substring(from);
    // Пометка проверяется на строке самой команды: у клиента есть своя
    // `/config`, и одно имя в меню не доказывает, что есть команда агента.
    for (final command in launch.agentCommands) {
      expect(
        menu,
        matches(RegExp('${RegExp.escape(command)} [^\\n]*\\(agent\\)')),
        reason: 'the menu has no agent command $command',
      );
    }
    for (final client in const ['/help', '/mode', '/model', '/config']) {
      expect(menu, contains(client));
    }

    pty.write('\x15');
    if (launch.agentHelpAnswer.isNotEmpty) {
      final helpFrom = pty.text.length;
      pty.write('/agent:help\r');
      for (final fragment in launch.agentHelpAnswer) {
        await pty.waitFor(fragment, from: helpFrom);
      }
    }
    pty.write('\x04');
    expect(await pty.exitCode, 0);
  }, skip: skip);

  // Прежняя проверка со scripted-агентом: префикс `/agent:` и разбор команд
  // агента отвечает сам scripted-агент.
  test(
    'cli/slash-menu-scripted-agent-prefix',
    () async {
      final pty = await repl(
        CodelabCompatibleStdioAgentMode.withAvailableCommands,
      );
      await pty.waitFor('> ');
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
