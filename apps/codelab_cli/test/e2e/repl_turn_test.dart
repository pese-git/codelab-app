// PTY-e2e хода в REPL (tasks 6.8; spec codelab-cli «Рендер хода в REPL»,
// «Поверхности вывода», «Редактор строки и клавиши», «Очередь промптов в
// REPL», «Сигналы CLI»; testing-quality «PTY-e2e терминального клиента»;
// design.md change `add-codelab-cli`, D11).
//
// Очередь проверяется на `hangs_until_cancel`, а не на
// `with_queued_prompt_drain`: первый ход того режима ждёт ответа на запрос
// одобрения, а пока ждёт одобрение, ввод промпта недоступен (spec «Одобрение
// в REPL»); блок одобрения появляется в группе 7.
@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart'
    show CodelabCompatibleStdioAgentMode;
import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';
import 'support/pty_process.dart';

const _esc = '\x1b';
final _sgr = RegExp('\x1b\\[[0-9;]*m');

Future<void> main() async {
  final skip = await PtyProcess.unavailableReason();
  late Directory dir;
  late E2eCliLaunch launch;

  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_repl_'));
  tearDown(() => dir.delete(recursive: true));

  /// `codelab` в PTY; после выхода печатается `stty -a`, чтобы проверить,
  /// что терминал восстановлен.
  Future<PtyProcess> repl(
    CodelabCompatibleStdioAgentMode mode, {
    List<String> args = const [],
    Map<String, String> environment = const {},
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
        ...args,
      ],
      environment: {
        'HOME': '${dir.path}/home',
        'CODELAB_HOME': '${dir.path}/codelab',
        'LANG': 'en_US.UTF-8',
        ...environment,
      },
    );
  }

  /// `with_tool_calls` кончается одобрением (правки у scripted-агента,
  /// команды у Dart-агента): Esc отменяет ход, только когда запрос уже
  /// показан, иначе отмена гонится с запросом.
  Future<void> cancelAtApproval(PtyProcess pty) async {
    await pty.waitFor('Permission:');
    pty.write(_esc);
    await pty.waitFor('cancelled', from: pty.text.indexOf('Permission:'));
  }

  /// После выхода терминал снова канонический и с эхо.
  void expectRestored(PtyProcess pty) {
    final stty = pty.text.split('[stty] ').last;
    expect(stty, contains('icanon'));
    expect(stty, isNot(contains('-icanon')));
    expect(stty, isNot(contains('-echo ')));
  }

  test('cli/repl-prompt-streaming', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.normal,
      args: ['hello'],
    );

    await pty.waitFor(launch.answer);
    expect(launch.answer.allMatches(pty.text), hasLength(1));
    pty.write('\x04');

    expect(await pty.exitCode, 0);
    expectRestored(pty);
  }, skip: skip);

  test('cli/repl-prompt-streaming in a pipe has no escape bytes', () async {
    final launch = await E2eCliAgent.current.launch(dir);

    final result = await CliProcess.run(
      ['--agent', launch.agent, '--cwd', dir.path, 'hello'],
      environment: {'CODELAB_HOME': '${dir.path}/codelab'},
      stdin: '',
    );

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, contains(launch.answer));
    expect(result.stdout, isNot(contains(_esc)));
  });

  test('cli/repl-prompt-streaming with NO_COLOR has no SGR', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.withToolCalls,
      args: ['hello'],
      environment: {'NO_COLOR': '1'},
    );

    await pty.waitFor('Read');
    await cancelAtApproval(pty);
    pty.write('\x04');

    expect(await pty.exitCode, 0);
    expect(_sgr.hasMatch(pty.text), isFalse, reason: pty.text);
  }, skip: skip);

  test('cli/esc-cancels-turn', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.hangsUntilCancel,
      args: ['slow'],
    );
    await pty.waitFor('> slow');

    pty.write(_esc);
    await pty.waitFor('cancelled');

    pty.write('again\r');
    await pty.waitFor('> again');
    pty.write(_esc);
    await pty.waitFor('cancelled', from: pty.text.indexOf('> again'));
    pty.write('\x04');

    expect(await pty.exitCode, 0);
    expectRestored(pty);
  }, skip: skip);

  test('cli/prompt-queue-drains-after-turn', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.hangsUntilCancel,
      args: ['first'],
    );
    await pty.waitFor('> first');

    pty.write('second\r');
    await pty.waitFor('queued: 1');
    final queuedAt = pty.text.indexOf('queued: 1');

    pty.write(_esc);
    await pty.waitFor('> second', from: queuedAt);

    pty.write(_esc);
    await pty.waitFor('cancelled', from: pty.text.indexOf('> second'));
    pty.write('\x04');
    expect(await pty.exitCode, 0);
  }, skip: skip);

  test('cli/thought-rendered-dimmed', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.withToolCalls,
      args: ['fix it'],
    );

    await pty.waitFor('Read');
    final thought = pty.text.indexOf('\x1b[2m');
    expect(thought, isNonNegative, reason: pty.text);
    expect(thought, lessThan(pty.text.indexOf('Read')));

    await cancelAtApproval(pty);
    pty.write('\x04');
    expect(await pty.exitCode, 0);
  }, skip: skip);

  test('cli/tool-row-format', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.withToolCalls,
      args: ['fix it'],
    );

    await pty.waitFor(launch.completedToolRow);
    final rows = [
      for (final line in pty.text.split('\n'))
        if (line.contains('Read') ||
            line.contains('Run') ||
            line.contains('Write'))
          line,
    ];
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row, isNot(contains('{')));
      expect(row, isNot(contains('"env"')));
    }

    await cancelAtApproval(pty);
    pty.write('\x04');
    expect(await pty.exitCode, 0);
  }, skip: skip);

  test('SIGTERM during a turn exits with 143 and restores the '
      'terminal', () async {
    final pty = await repl(
      CodelabCompatibleStdioAgentMode.hangsUntilCancel,
      args: ['slow'],
    );
    await pty.waitFor('> slow');

    // Сигнал — только процессу CLI: у обёрток `sh -c` и `script` в
    // командной строке те же аргументы, поэтому шаблон привязан к её началу
    // — исполняемому файлу Dart (`dart` или `dartvm`, который запускает
    // `dart` в новых SDK).
    final killed = await Process.run('pkill', [
      '-TERM',
      '-f',
      '^[^ ]*dart(vm)? .*codelab\\.dill --agent .* --cwd ${dir.path}',
    ]);
    expect(killed.exitCode, 0, reason: '${killed.stderr}');

    expect(await pty.exitCode, 143);
    expectRestored(pty);
  }, skip: skip);
}
