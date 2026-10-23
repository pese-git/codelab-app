import 'dart:async';

import '../../cancel/cancel_token.dart';
import '../../util/clock.dart';
import '../errors.dart';
import '../event_stream.dart';
import '../events.dart';
import '../messages.dart';
import '../stream_function.dart';

/// Watchdogs of a model request (`agent-core-architecture` §2.10.1,
/// §2.10.5).
///
/// Every call gets a child token of [StreamFunction]'s `cancel`; the inner
/// stream gets the child. `connect` runs from the call to the first event;
/// `idle` is re-armed by every event of the inner stream — blocks of any
/// kind, reasoning included; keep-alive produces no event and does not
/// re-arm it (LLM-16). Before the first content block a model with
/// `hiddenReasoning` waits [idleReasoning] instead of [idle].
///
/// A firing cancels only the attempt token with [WatchdogFired] and
/// rewrites the resulting `aborted` into an `ErrorEvent` of class
/// `timeout`; a user cancel (the parent token) stays `aborted`.
StreamFunction withWatchdogs(
  StreamFunction inner, {
  required Duration connect,
  required Duration idle,
  Duration? idleReasoning,
  required Clock clock,
}) => (model, context, {cancel}) {
  final out = AssistantMessageEventStream();
  scheduleMicrotask(() async {
    final attempt = CancelTokenSource(parent: cancel);
    final hidden = model.hiddenReasoning;
    var phase = _Phase.connecting;
    String? fired;
    ClockTimer? timer;

    void arm(Duration duration, String message) {
      timer?.cancel();
      timer = clock.timer(duration, () {
        fired = message;
        attempt.cancel(
          WatchdogFired(phase == _Phase.connecting ? 'connect' : 'idle'),
        );
      });
    }

    void armIdle() {
      final waiting = phase == _Phase.awaitingContent;
      final duration = waiting && hidden ? idleReasoning ?? idle : idle;
      arm(
        duration,
        !waiting
            ? 'mid_stream_idle: no stream events for ${_seconds(duration)} '
                  '(idle watchdog)'
            : hidden
            ? 'first_byte_stall: no stream events for ${_seconds(duration)} '
                  'while waiting for hidden reasoning (idle watchdog)'
            : 'first_byte_stall: no stream events for ${_seconds(duration)} '
                  'after response headers (idle watchdog)',
      );
    }

    arm(
      connect,
      'connect_stall: no response headers within ${_seconds(connect)} '
      '(connect watchdog)',
    );
    try {
      await for (final event in inner(model, context, cancel: attempt.token)) {
        switch (event) {
          case DoneEvent():
            timer?.cancel();
            out.push(event);
          case ErrorEvent(:final error, :final retryAfter):
            timer?.cancel();
            final userCancelled = cancel?.isCancelled ?? false;
            if (fired case final message?
                when error.stopReason == StopReason.aborted && !userCancelled) {
              out.push(
                ErrorEvent(
                  error.copyWith(
                    stopReason: StopReason.error,
                    errorClass: LlmErrorClass.timeout,
                    errorMessage: message,
                  ),
                  retryAfter: retryAfter,
                ),
              );
            } else {
              out.push(event);
            }
          case StartEvent():
            phase = _Phase.awaitingContent;
            armIdle();
            out.push(event);
          case BlockStartEvent():
            phase = _Phase.streaming;
            armIdle();
            out.push(event);
          case BlockDeltaEvent() || BlockEndEvent():
            armIdle();
            out.push(event);
        }
      }
    } finally {
      timer?.cancel();
      attempt.dispose();
      out.end();
    }
  });
  return out;
};

enum _Phase { connecting, awaitingContent, streaming }

String _seconds(Duration d) => d.inMilliseconds % 1000 == 0
    ? '${d.inSeconds} s'
    : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
