/// Structured logging port used by ACP client application code.
///
/// Implementations back this with a concrete logging technology (see
/// `structured_log`-based adapter in `src/infrastructure/`). Application
/// code depends only on this abstraction, never on a concrete backend
/// (`docs/architecture/observability.md` §33).
abstract interface class Logger {
  /// Returns a child logger with [context] merged on top of this logger's
  /// existing context. Does not mutate this logger.
  Logger bind(Map<String, Object?> context);

  /// Returns a child logger with the given correlation identifiers merged
  /// on top of this logger's existing correlation (only non-null fields are
  /// changed; unset fields are inherited). Does not mutate this logger.
  Logger withCorrelation({
    String? sessionId,
    String? requestId,
    int? connectionGeneration,
    String? toolCallId,
    String? messageId,
    String? operationId,
  });

  /// Very detailed internal events (e.g. raw protocol payloads). Off by
  /// default — only reaches a sink that explicitly opts in.
  void trace(String? event, {Map<String, Object?>? context});

  /// Development-workflow diagnostics (state transitions, reconnect
  /// attempts, protocol mapping details).
  void debug(String? event, {Map<String, Object?>? context});

  /// Significant normal lifecycle events (connected, session created,
  /// request completed).
  void info(String? event, {Map<String, Object?>? context});

  /// Recoverable abnormal conditions (reconnect attempt, stale event,
  /// retryable failure).
  void warning(String? event, {Map<String, Object?>? context});

  /// An operation failed or an expected flow was violated.
  void error(String? event, {Map<String, Object?>? context});

  /// The application cannot safely continue.
  void critical(String? event, {Map<String, Object?>? context});
}
