import 'dart:async';
import 'dart:math';

import '../../cancel/cancel_token.dart';
import '../../util/clock.dart';
import '../../util/logger.dart';
import '../errors.dart';
import '../event_stream.dart';
import '../events.dart';
import '../stream_function.dart';
import '../usage.dart';

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

/// Retries a request only until it is committed — the first
/// `BlockStartEvent` or `DoneEvent` (`agent-core-architecture` §2.10.2).
/// `StartEvent` is held until then and goes out exactly once. After the
/// commit nothing is retried (LLM-8); `aborted`, `overflow`, `auth`,
/// `badRequest` and `terminalFinish` are never retried (LLM-9). Transient
/// classes share [RetryPolicy.maxAttempts], 429 has its own budget and
/// honours `Retry-After`. Usage of failed attempts is added to the result;
/// the final error carries the attempt history.
StreamFunction withTransientRetry(
  StreamFunction inner,
  RetryPolicy policy, {
  required Clock clock,
  required Random random,
  required Logger logger,
}) => (model, context, {cancel}) {
  final out = AssistantMessageEventStream();
  scheduleMicrotask(() async {
    final started = clock.now();
    var attempt = 0;
    var rateLimitRetries = 0;
    var startForwarded = false;
    var failedUsage = Usage.zero;
    final history = <String>[];
    try {
      while (true) {
        attempt++;
        var committed = false;
        StartEvent? bufferedStart;
        ErrorEvent? failure;
        await for (final event in inner(model, context, cancel: cancel)) {
          if (committed) {
            out.push(addUsage(event, failedUsage));
            continue;
          }
          switch (event) {
            case StartEvent():
              bufferedStart = event;
            case BlockStartEvent() || DoneEvent():
              committed = true;
              if (!startForwarded && bufferedStart != null) {
                out.push(addUsage(bufferedStart, failedUsage));
                startForwarded = true;
              }
              out.push(addUsage(event, failedUsage));
            case ErrorEvent():
              failure = event;
            case BlockDeltaEvent() || BlockEndEvent():
              out.push(addUsage(event, failedUsage));
          }
        }
        if (failure == null) {
          break;
        }
        final error = failure.error;
        final cls = error.errorClass ?? LlmErrorClass.unknown;
        history.add('attempt $attempt ${cls.name} (${error.errorMessage})');
        final delay = _retryDelay(
          cls,
          attempt,
          rateLimitRetries,
          failure.retryAfter,
          policy,
          random,
        );
        if (delay == null || (cancel?.isCancelled ?? false)) {
          if (!startForwarded && bufferedStart != null) {
            out.push(addUsage(bufferedStart, failedUsage));
          }
          out.push(
            _withHistory(
              failure,
              history,
              failedUsage,
              clock.now().difference(started),
            ),
          );
          break;
        }
        failedUsage += error.usage;
        if (cls == LlmErrorClass.rateLimited) {
          rateLimitRetries++;
        }
        logger.log(
          LogLevel.info,
          'llm.retry',
          fields: {
            'attempt': attempt,
            'class': cls.name,
            'delay_ms': delay.inMilliseconds,
            'provider': model.provider,
            'model': model.id,
          },
        );
        try {
          await clock.delay(delay, cancel: cancel);
        } on CancelledException {
          // The next attempt answers aborted at once.
        }
      }
    } finally {
      out.end();
    }
  });
  return out;
};

/// [event] with [usage] of earlier attempts added to its snapshot.
AssistantMessageEvent addUsage(AssistantMessageEvent event, Usage usage) =>
    usage == Usage.zero
    ? event
    : event.withPartial((m) => m.copyWith(usage: m.usage + usage));

const _neverRetried = {
  LlmErrorClass.aborted,
  LlmErrorClass.overflow,
  LlmErrorClass.auth,
  LlmErrorClass.badRequest,
  LlmErrorClass.terminalFinish,
};

/// `null` — do not retry.
Duration? _retryDelay(
  LlmErrorClass cls,
  int attempt,
  int rateLimitRetries,
  Duration? retryAfter,
  RetryPolicy p,
  Random random,
) {
  if (_neverRetried.contains(cls)) {
    return null;
  }
  if (cls == LlmErrorClass.rateLimited) {
    if (rateLimitRetries >= p.rateLimitRetries) {
      return null;
    }
    if (retryAfter != null) {
      if (retryAfter > p.maxRetryAfter) {
        return null;
      }
      return retryAfter + Duration(milliseconds: random.nextInt(251));
    }
    return _backoff(
      p.rateLimitBaseDelay,
      p.rateLimitMaxDelay,
      rateLimitRetries + 1,
      random,
    );
  }
  if (attempt >= p.maxAttempts) {
    return null;
  }
  return _backoff(p.baseDelay, p.maxDelay, attempt, random);
}

/// Equal jitter: `cap = min(max, base × 2^(n−1))`,
/// `delay = cap / 2 + random × cap / 2`.
Duration _backoff(Duration base, Duration max, int n, Random random) {
  final exponential = base.inMicroseconds * pow(2, n - 1);
  final cap = min(max.inMicroseconds, exponential.toInt());
  return Duration(
    microseconds: (cap / 2 + random.nextDouble() * cap / 2).round(),
  );
}

ErrorEvent _withHistory(
  ErrorEvent failure,
  List<String> history,
  Usage failedUsage,
  Duration elapsed,
) {
  final error = failure.error;
  final message = history.length <= 1
      ? error.errorMessage
      : 'request failed after ${history.length} attempts in '
            '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s: '
            '${history.join('; ')}';
  return ErrorEvent(
    error.copyWith(usage: error.usage + failedUsage, errorMessage: message),
    retryAfter: failure.retryAfter,
  );
}
