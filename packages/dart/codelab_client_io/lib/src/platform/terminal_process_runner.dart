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

  /// Код выхода уже получен (вывод может ещё дочитываться): повторный
  /// [kill] после этого не шлёт сигналов (D4: no-op для вышедшего).
  var _exitCodeReceived = false;

  Future<void>? _killing;
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

  /// Сколько ждать выхода после `SIGTERM`, прежде чем послать `SIGKILL`.
  ///
  /// Процесс, игнорирующий `SIGTERM` (`trap '' TERM`), иначе пережил бы и
  /// `terminal/kill`, и выход из приложения (D4 change
  /// `add-client-process-shutdown-on-exit`).
  static const _termGracePeriod = Duration(seconds: 2);

  /// `SIGTERM`, через [_termGracePeriod] — `SIGKILL`.
  ///
  /// Future завершается после выхода процесса либо сразу после отправки
  /// `SIGKILL` (не позже ~2 s): ждать код выхода после `SIGKILL` не нужно,
  /// сигнал неперехватываем. Сигнал получает только сам процесс команды,
  /// не его потомки (design.md, Q2). Для вышедшего процесса — no-op;
  /// параллельные вызовы делят одно завершение.
  @override
  Future<void> kill() {
    if (_exitCodeReceived || _state is TerminalProcessExited) {
      return Future<void>.value();
    }
    return _killing ??= _terminate();
  }

  Future<void> _terminate() async {
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.exitCode.timeout(_termGracePeriod);
    } on TimeoutException {
      if (!_exitCodeReceived) {
        _process.kill(ProcessSignal.sigkill);
      }
    }
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
    // `outputByteLimit` field requires (`docs/protocols/acp/protocol/10-Terminal.md`).
    while (cutIndex < bytes.length && (bytes[cutIndex] & 0xC0) == 0x80) {
      cutIndex++;
    }

    _outputBytes.clear();
    _outputBytes.add(bytes.sublist(cutIndex));
    _truncated = true;
  }

  Future<void> _handleExit(int exitCode) async {
    _exitCodeReceived = true;
    try {
      await Future.wait([
        _stdoutDone.future,
        _stderrDone.future,
      ]).timeout(_outputDrainTimeout);
    } on TimeoutException {
      // Каналы держит фоновый потомок; вывод, пришедший до этого момента,
      // уже сохранён.
    }
    // Статус выводится из кода выхода ОС, а не из отправленного сигнала:
    // процесс мог выйти сам или обработать SIGTERM (D14). Выбор платформы
    // изолирован здесь, в адаптере (`AGENTS.md` §11).
    _state = terminalStateFromExitCode(exitCode, posix: !Platform.isWindows);
    unawaited(_stdoutSubscription.cancel());
    unawaited(_stderrSubscription.cancel());
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(_state);
    }
  }
}

/// Состояние вышедшего процесса по коду выхода `Process.exitCode`.
///
/// Почему: на POSIX отрицательный код означает завершение сигналом (`-15` —
/// `SIGTERM`), а на Windows это NTSTATUS-код (`0xC0000005` приходит как
/// `-1073741819`), и называть его сигналом нельзя (D14 change
/// `add-client-process-shutdown-on-exit`). Инвариант состояния: ровно одно из
/// `exitCode` и `signal` непусто (`TerminalProcessState.exited`).
///
/// Для чего: чистая функция без обращения к платформе — обе ветки проверяются
/// тестом; платформу выбирает вызывающий адаптер ([posix]).
///
/// Как использовать: `terminalStateFromExitCode(code, posix: !Platform.isWindows)`.
/// На Windows отрицательный код отдаётся беззнаковым 32-битным `exitCode`,
/// `signal` — `null`.
TerminalProcessState terminalStateFromExitCode(
  int exitCode, {
  required bool posix,
}) {
  if (exitCode >= 0) {
    return TerminalProcessState.exited(exitCode: exitCode);
  }
  if (posix) {
    return TerminalProcessState.exited(signal: _signalName(-exitCode));
  }
  return TerminalProcessState.exited(exitCode: exitCode & 0xFFFFFFFF);
}

/// Имя сигнала по номеру из отрицательного кода выхода `Process.exitCode`.
///
/// Почему только часть номеров: имена даны лишь сигналам с одинаковым номером
/// на Linux и macOS; номера прочих различаются (`SIGUSR1` — 10 на Linux и 30
/// на macOS), и угадывать имя по номеру нельзя. Остальные номера отдаются как
/// `SIG<n>` (D14 change `add-client-process-shutdown-on-exit`). Формат строки
/// ACP не задаёт (`signal: string | null`), таблица — решение CodeLab.
String _signalName(int number) => switch (number) {
  1 => 'SIGHUP',
  2 => 'SIGINT',
  3 => 'SIGQUIT',
  6 => 'SIGABRT',
  9 => 'SIGKILL',
  11 => 'SIGSEGV',
  13 => 'SIGPIPE',
  14 => 'SIGALRM',
  15 => 'SIGTERM',
  _ => 'SIG$number',
};
