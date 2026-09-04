import 'dart:async';

import 'package:acp_client_core/acp_client_core.dart';

/// A recorded call to [FakeTerminalProcessRunner.start].
final class FakeTerminalProcessStart {
  const FakeTerminalProcessStart({
    required this.command,
    required this.args,
    required this.env,
    required this.cwd,
    required this.outputByteLimit,
  });

  final String command;
  final List<String> args;
  final Map<String, String> env;
  final String cwd;
  final int? outputByteLimit;
}

/// Deterministic [TerminalProcessRunner] test double — no real OS process,
/// full manual control over output/exit via the returned
/// [FakeTerminalProcessHandle]s, for unit tests exercising `terminal/*`
/// handling in `AcpClientApplication` without spawning anything.
final class FakeTerminalProcessRunner implements TerminalProcessRunner {
  final started = <FakeTerminalProcessStart>[];
  final handles = <FakeTerminalProcessHandle>[];
  Object? nextStartFailure;

  @override
  Future<TerminalProcessHandle> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
    required String cwd,
    int? outputByteLimit,
  }) async {
    final failure = nextStartFailure;
    if (failure != null) {
      nextStartFailure = null;
      throw failure;
    }

    started.add(
      FakeTerminalProcessStart(
        command: command,
        args: args,
        env: env,
        cwd: cwd,
        outputByteLimit: outputByteLimit,
      ),
    );
    final handle = FakeTerminalProcessHandle(outputByteLimit: outputByteLimit);
    handles.add(handle);
    return handle;
  }
}

final class FakeTerminalProcessHandle implements TerminalProcessHandle {
  FakeTerminalProcessHandle({this.outputByteLimit});

  final int? outputByteLimit;
  final _exitCompleter = Completer<TerminalProcessState>();
  final _buffer = StringBuffer();

  var _truncated = false;
  var killCallCount = 0;
  TerminalProcessState _state = const TerminalProcessState.running();

  @override
  String get output => _buffer.toString();

  @override
  bool get truncated => _truncated;

  @override
  TerminalProcessState get state => _state;

  @override
  Future<TerminalProcessState> waitForExit() => _exitCompleter.future;

  @override
  Future<void> kill() async {
    killCallCount++;
    if (_state is TerminalProcessExited) {
      return;
    }
    exit(signal: 'SIGTERM');
  }

  /// Appends [text] to the accumulated output, truncating from the start
  /// once [outputByteLimit] is exceeded — same "start of buffer" contract
  /// as the real `IoTerminalProcessRunner` adapter (UTF-8 boundary safety
  /// is not simulated here; tests append plain ASCII).
  void appendOutput(String text) {
    _buffer.write(text);
    final limit = outputByteLimit;
    if (limit == null) {
      return;
    }
    final current = _buffer.toString();
    if (current.length > limit) {
      final trimmed = current.substring(current.length - limit);
      _buffer
        ..clear()
        ..write(trimmed);
      _truncated = true;
    }
  }

  /// Marks the process as exited, resolving [waitForExit] and any pending
  /// `terminal/wait_for_exit` call. A no-op if already exited.
  void exit({int? exitCode, String? signal}) {
    if (_state is TerminalProcessExited) {
      return;
    }
    _state = TerminalProcessState.exited(exitCode: exitCode, signal: signal);
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(_state);
    }
  }
}
