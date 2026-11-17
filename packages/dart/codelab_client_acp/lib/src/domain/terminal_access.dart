import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'terminal_access.freezed.dart';

/// Конечный автомат жизненного цикла terminal-процесса.
///
/// Намеренно два состояния, а не независимые булевы `killed`/`released`
/// (`AGENTS.md` §8): `kill()` переводит `running` в `exited` (с тем же видом
/// статуса, что и естественный выход); `released` — не состояние: после
/// release [TerminalId] вообще удаляется из реестра сессии, и держать флаг
/// «released» не в чем (`add-acp-terminal-client-support/design.md`, Decision 3).
@freezed
sealed class TerminalProcessState with _$TerminalProcessState {
  const factory TerminalProcessState.running() = TerminalProcessRunning;

  /// Процесс вышел.
  ///
  /// Почему поля такие: в схеме ACP `TerminalExitStatus.exitCode` — `null`
  /// либо число `>= 0`. При выходе по сигналу [exitCode] — `null` (не
  /// отрицательный номер сигнала ОС), а [signal] содержит имя (`SIGTERM`) или
  /// `SIG<n>` для непортируемых номеров; при обычном выходе [signal] — `null`.
  /// Адаптер обязан выдерживать этот инвариант (D14 change
  /// `add-client-process-shutdown-on-exit`): ядро клиента поля не правит.
  const factory TerminalProcessState.exited({int? exitCode, String? signal}) =
      TerminalProcessExited;
}

/// Client-side port for starting and controlling a non-interactive process,
/// backing ACP `terminal/*`. Implemented by an infrastructure adapter
/// (`apps/codelab_desktop/lib/core/platform/`) — this package stays free of
/// `dart:io`, same reasoning as `TextFileReader`/`TextFileWriter` in
/// `fs_access.dart`.
abstract interface class TerminalProcessRunner {
  Future<TerminalProcessHandle> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
    required String cwd,
    int? outputByteLimit,
  });
}

/// A single process started via [TerminalProcessRunner.start] — the
/// application layer holds one of these per [TerminalId] in its
/// session-scoped registry until `terminal/release`.
abstract interface class TerminalProcessHandle {
  /// Currently accumulated combined stdout+stderr, already truncated to
  /// `outputByteLimit` (if any) by the adapter (design.md, Decision 4).
  String get output;

  /// Whether [output] has been truncated to fit `outputByteLimit`.
  bool get truncated;

  /// The process's current state — `running`, or `exited` with whatever
  /// exit code/signal the OS reported (including after a [kill]).
  TerminalProcessState get state;

  /// Resolves once the process exits — immediately if it already has.
  Future<TerminalProcessState> waitForExit();

  /// Завершает процесс: `SIGTERM`, а если он не вышел — принудительно
  /// (`SIGKILL`); `Future` завершается не позже чем через ~2 с после вызова
  /// (D4 change `add-client-process-shutdown-on-exit`).
  ///
  /// Почему так: процесс, игнорирующий `SIGTERM`, иначе пережил бы и
  /// `terminal/kill`, и выход из приложения. Для вышедшего процесса — no-op:
  /// это атомарность, нужная `terminal/kill` при естественном завершении
  /// (design.md, Risks). Параллельные вызовы делят одно завершение. Ядро
  /// клиента вызывает `kill` из `terminal/kill`, `terminal/release`, разрыва
  /// соединения и `dispose`; сбой адаптера изолируется вызывающим.
  Future<void> kill();
}

sealed class TerminalAccessFailure implements Exception {
  const TerminalAccessFailure();
}

/// The requested `terminalId` does not exist in the session's registry —
/// never created, or already released via `terminal/release`. Both cases
/// produce the same "unknown terminal" outcome: release makes the id
/// invalid for all later `terminal/*` calls exactly as if it never existed.
final class UnknownTerminalFailure extends TerminalAccessFailure {
  const UnknownTerminalFailure(this.terminalId);

  final TerminalId terminalId;

  @override
  String toString() => 'Unknown terminal "${terminalId.value}".';
}

/// The OS failed to start the requested command (not found, not
/// executable, ...) — surfaced by a [TerminalProcessRunner] implementation.
final class TerminalStartFailure extends TerminalAccessFailure {
  const TerminalStartFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
