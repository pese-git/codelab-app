// Принудительное завершение terminal-процесса и статус выхода (change
// `add-client-process-shutdown-on-exit`, D4, D14; acp-terminal-client
// «Принудительное завершение terminal-процесса»): SIGTERM, через 2 s SIGKILL;
// при выходе по сигналу `exitCode` — `null` (в схеме ACP он не отрицателен),
// `signal` выводится из кода выхода ОС, а не из отправленного сигнала.
@TestOn('!windows')
library;

import 'dart:io';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:test/test.dart';

Future<TerminalProcessHandle> _start(String script) =>
    const IoTerminalProcessRunner().start(
      command: 'sh',
      args: ['-c', script],
      env: const {},
      cwd: '.',
    );

/// Ждёт строку в выводе процесса с дедлайном (5 s), затем падает с `fail`.
///
/// Нужно, чтобы `trap` в оболочке был установлен до сигнала: иначе `SIGTERM`
/// убил бы обычный `sh`. Без дедлайна сбой запуска повесил бы весь прогон.
Future<void> _waitForOutput(
  TerminalProcessHandle handle,
  String text, {
  Duration deadline = const Duration(seconds: 5),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!handle.output.contains(text)) {
    if (stopwatch.elapsed > deadline) {
      fail('Process did not print "$text" within $deadline.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

TerminalProcessExited _exited(TerminalProcessState state) {
  expect(state, isA<TerminalProcessExited>());
  final exited = state as TerminalProcessExited;
  // Инвариант D14: ни один статус выхода не содержит отрицательного кода.
  expect(exited.exitCode ?? 0, greaterThanOrEqualTo(0));
  return exited;
}

void main() {
  test('process ignoring SIGTERM is dead after kill within 3 s, signal '
      'SIGKILL and exitCode null', () async {
    final handle = await _start(
      "trap '' TERM; echo ready; while :; do sleep 1; done",
    );
    await _waitForOutput(handle, 'ready');

    await handle.kill().timeout(const Duration(seconds: 3));
    final state = await handle.waitForExit().timeout(
      const Duration(seconds: 5),
    );

    final exited = _exited(state);
    expect(exited.signal, 'SIGKILL');
    expect(exited.exitCode, isNull);
    expect(handle.state, state);
  });

  test('process exiting on SIGTERM reports SIGTERM with exitCode null and '
      'kill returns promptly', () async {
    final handle = await _start('exec sleep 30');
    final stopwatch = Stopwatch()..start();

    await handle.kill().timeout(const Duration(seconds: 3));

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    final exited = _exited(await handle.waitForExit());
    expect(exited.signal, 'SIGTERM');
    expect(exited.exitCode, isNull);
  });

  test('process handling SIGTERM and exiting with code 0 reports the code, '
      'not a signal', () async {
    final handle = await _start(
      "trap 'exit 0' TERM; echo ready; while :; do sleep 1; done",
    );
    await _waitForOutput(handle, 'ready');

    await handle.kill().timeout(const Duration(seconds: 3));
    final exited = _exited(await handle.waitForExit());

    expect(exited.exitCode, 0);
    expect(exited.signal, isNull);
  });

  test('process killed externally reports SIGKILL derived from the exit '
      'code', () async {
    // pid читается из вывода процесса: публичный API адаптера pid не даёт.
    final handle = await _start('echo \$\$; exec sleep 30');
    await _waitForOutput(handle, '\n');
    final pid = int.parse(handle.output.trim());

    expect(Process.killPid(pid, ProcessSignal.sigkill), isTrue);
    final exited = _exited(
      await handle.waitForExit().timeout(const Duration(seconds: 5)),
    );

    expect(exited.signal, 'SIGKILL');
    expect(exited.exitCode, isNull);
  });

  test('natural exit keeps the exit code and has no signal', () async {
    final handle = await _start('exit 3');

    final exited = _exited(await handle.waitForExit());

    expect(exited.exitCode, 3);
    expect(exited.signal, isNull);
  });

  test('a non-portable signal is reported as SIG<n>', () async {
    // SIGUSR1 имеет разные номера на Linux (10) и macOS (30), поэтому имя по
    // номеру не угадывается (D14); sh без trap завершается от этого сигнала.
    final handle = await _start('echo \$\$; exec sleep 30');
    await _waitForOutput(handle, '\n');
    final pid = int.parse(handle.output.trim());

    expect(Process.killPid(pid, ProcessSignal.sigusr1), isTrue);
    final exited = _exited(
      await handle.waitForExit().timeout(const Duration(seconds: 5)),
    );

    expect(exited.exitCode, isNull);
    expect(exited.signal, matches(RegExp(r'^SIG\d+$')));
  });

  test('repeated kill returns immediately and does not change the recorded '
      'status', () async {
    final handle = await _start('exec sleep 30');
    await handle.kill();
    final first = await handle.waitForExit();

    final stopwatch = Stopwatch()..start();
    await handle.kill();

    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 100)));
    expect(handle.state, first);
  });
}
