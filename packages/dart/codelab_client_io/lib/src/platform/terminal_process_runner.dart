import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:codelab_client_acp/codelab_client_acp.dart';

/// Реализация клиентского порта ACP `terminal/*` на `dart:io`.
///
/// Почему: процессы — забота платформы, а не web-безопасного ядра клиента;
/// адаптер общий для app и CLI (`docs/architecture/platform-integration.md`
/// §9–10; форма порта — `add-acp-terminal-client-support/design.md`).
///
/// Как использовать: composition root передаёт экземпляр в
/// `AcpClientApplication(terminalProcessRunner:)`. Вывод stdout и stderr
/// копится вместе и при `outputByteLimit` обрезается с начала по границе
/// символа UTF-8; не запустившийся процесс — `TerminalStartFailure`.
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
    _stdoutSubscription = _process.stdout.listen(
      _appendOutput,
      onDone: _stdoutDone.complete,
    );
    _stderrSubscription = _process.stderr.listen(
      _appendOutput,
      onDone: _stderrDone.complete,
    );
    unawaited(_process.exitCode.then(_handleExit));
  }

  /// Сколько ждать конца stdout и stderr после выхода процесса.
  ///
  /// Код выхода может прийти раньше последних байтов вывода (так бывает на
  /// Linux), поэтому вывод дочитывается до конца потоков. Но потомок, ушедший
  /// в фон, может держать каналы открытыми бесконечно — ожидание ограничено,
  /// чтобы `terminal/wait_for_exit` не зависал.
  static const _outputDrainTimeout = Duration(seconds: 2);

  final Process _process;
  final int? outputByteLimit;
  final _outputBytes = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  final _exitCompleter = Completer<TerminalProcessState>();
  final _stdoutDone = Completer<void>();
  final _stderrDone = Completer<void>();

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

  Future<void> _handleExit(int exitCode) async {
    try {
      await Future.wait([
        _stdoutDone.future,
        _stderrDone.future,
      ]).timeout(_outputDrainTimeout);
    } on TimeoutException {
      // Каналы держит фоновый потомок; вывод, пришедший до этого момента,
      // уже сохранён.
    }
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
