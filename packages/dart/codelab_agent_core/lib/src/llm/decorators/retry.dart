/// Budgets of `withTransientRetry` (`agent-core-architecture` §2.10.2).
final class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 4,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.rateLimitRetries = 3,
    this.rateLimitBaseDelay = const Duration(seconds: 2),
    this.rateLimitMaxDelay = const Duration(seconds: 60),
    this.maxRetryAfter = const Duration(seconds: 120),
  });

  /// All attempts on transient failures, the first included:
  /// `transient_retries + 1` of the config (§15.4).
  final int maxAttempts;
  final Duration baseDelay, maxDelay;

  /// Retries after 429 — a separate budget (`rate_limit_retries`).
  final int rateLimitRetries;
  final Duration rateLimitBaseDelay, rateLimitMaxDelay;

  /// A longer `Retry-After` stops retrying: switching the model is better.
  final Duration maxRetryAfter;
}
