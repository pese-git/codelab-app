import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'terminal_access.freezed.dart';

/// State machine for a terminal process's lifecycle. Deliberately two
/// states, not independent `killed`/`released` booleans (`AGENTS.md` §8):
/// `kill()` transitions `running` -> `exited` (with a signal-derived exit
/// status, same shape as a natural exit); `released` isn't a state at all —
/// once released, the process's [TerminalId] is dropped from the session
/// registry entirely, so there is nothing left to hold a "released" flag
/// (see `add-acp-terminal-client-support/design.md`, Decision 3).
@freezed
sealed class TerminalProcessState with _$TerminalProcessState {
  const factory TerminalProcessState.running() = TerminalProcessRunning;

  const factory TerminalProcessState.exited({int? exitCode, String? signal}) =
      TerminalProcessExited;
}

/// Client-side port for starting and controlling a non-interactive process,
/// backing ACP `terminal/*`. Implemented by an infrastructure adapter
/// (`apps/codelab_app/lib/core/platform/`) — this package stays free of
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

  /// Terminates the process. A no-op if it has already exited — this is
  /// the atomicity `terminal/kill` needs against a naturally-completing
  /// process (design.md, Risks).
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
