// Преобразование кода выхода `Process.exitCode` в состояние terminal-процесса
// (change `add-client-process-shutdown-on-exit`, D14): отрицательный код — это
// сигнал только на POSIX; на Windows это NTSTATUS-код выхода.

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_io/src/platform/terminal_process_runner.dart';
import 'package:test/test.dart';

void main() {
  group('terminalStateFromExitCode on POSIX', () {
    test('a non-negative code is exitCode with no signal', () {
      expect(
        terminalStateFromExitCode(3, posix: true),
        const TerminalProcessState.exited(exitCode: 3),
      );
    });

    test('a negative code is a signal with no exitCode', () {
      expect(
        terminalStateFromExitCode(-15, posix: true),
        const TerminalProcessState.exited(signal: 'SIGTERM'),
      );
      expect(
        terminalStateFromExitCode(-30, posix: true),
        const TerminalProcessState.exited(signal: 'SIG30'),
      );
    });
  });

  group('terminalStateFromExitCode on Windows', () {
    test('a non-negative code is exitCode with no signal', () {
      expect(
        terminalStateFromExitCode(1, posix: false),
        const TerminalProcessState.exited(exitCode: 1),
      );
    });

    test('a negative NTSTATUS code is an unsigned exitCode, signal is null', () {
      // 0xC0000005 (access violation) приходит из `Process.exitCode` как int32.
      expect(
        terminalStateFromExitCode(-1073741819, posix: false),
        const TerminalProcessState.exited(exitCode: 0xC0000005),
      );
      expect(
        terminalStateFromExitCode(-1, posix: false),
        const TerminalProcessState.exited(exitCode: 0xFFFFFFFF),
      );
    });
  });
}
