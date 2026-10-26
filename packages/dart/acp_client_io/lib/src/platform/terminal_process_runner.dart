import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:acp_client_core/acp_client_core.dart';

/// `dart:io`-backed implementation of the ACP `terminal/*` client-side
/// port — see `docs/architecture/platform-integration.md` §9-10 for why
/// this adapter lives here rather than in `acp_client_core`, and
/// `add-acp-terminal-client-support/design.md` for the port's shape.
final class IoTerminalProcessRunner implements TerminalProcessRunner {
  const IoTerminalProcessRunner();

  @override
  Future<TerminalProcessHandle> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
    required String cwd,
    int? outputByteLimit,
  }) async {
    try {
      final process = await Process.start(
        command,
        args,
        workingDirectory: cwd,
        environment: env.isEmpty ? null : env,
      );
      return _IoTerminalProcessHandle(
        process,
        outputByteLimit: outputByteLimit,
      );
    } on Object catch (error) {
      throw TerminalStartFailure(
        'Failed to start "$command": ${error is ProcessException ? error.message : error}',
        cause: error,
      );
    }
  }
}

final class _IoTerminalProcessHandle implements TerminalProcessHandle {
  _IoTerminalProcessHandle(this._process, {required this.outputByteLimit}) {
    _stdoutSubscription = _process.stdout.listen(_appendOutput);
    _stderrSubscription = _process.stderr.listen(_appendOutput);
    unawaited(_process.exitCode.then(_handleExit));
  }

  final Process _process;
  final int? outputByteLimit;
  final _outputBytes = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  final _exitCompleter = Completer<TerminalProcessState>();

  var _truncated = false;
  var _killRequested = false;
  TerminalProcessState _state = const TerminalProcessState.running();

  @override
  String get output =>
      utf8.decode(_outputBytes.toBytes(), allowMalformed: true);

  @override
  bool get truncated => _truncated;

  @override
  TerminalProcessState get state => _state;

  @override
  Future<TerminalProcessState> waitForExit() => _exitCompleter.future;

  @override
  Future<void> kill() async {
    if (_state is TerminalProcessExited) {
      return;
    }
    _killRequested = true;
    _process.kill(ProcessSignal.sigterm);
  }

  void _appendOutput(List<int> chunk) {
    _outputBytes.add(chunk);
    final limit = outputByteLimit;
    if (limit == null || _outputBytes.length <= limit) {
      return;
    }

    final bytes = _outputBytes.toBytes();
    var cutIndex = bytes.length - limit;
    // Advance past any UTF-8 continuation bytes (`10xxxxxx`) so the cut
    // lands on a real character boundary — the retained output ends up
    // slightly under `outputByteLimit`, exactly as ACP's `terminal/create`
    // `outputByteLimit` field requires (`docs/acp/protocol/10-Terminal.md`).
    while (cutIndex < bytes.length && (bytes[cutIndex] & 0xC0) == 0x80) {
      cutIndex++;
    }

    _outputBytes.clear();
    _outputBytes.add(bytes.sublist(cutIndex));
    _truncated = true;
  }

  void _handleExit(int exitCode) {
    _state = TerminalProcessState.exited(
      exitCode: exitCode,
      signal: _killRequested ? 'SIGTERM' : null,
    );
    unawaited(_stdoutSubscription.cancel());
    unawaited(_stderrSubscription.cancel());
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(_state);
    }
  }
}
