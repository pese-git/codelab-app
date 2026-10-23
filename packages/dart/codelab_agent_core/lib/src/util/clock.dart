import 'dart:async';

import '../cancel/cancel_token.dart';

/// Time port of the core (PKG-6): the core never reads the wall clock or
/// starts timers itself. Tests pass `FakeClock` from `testing.dart`, so
/// watchdogs, retry delays and scripted delays run without real waiting
/// (design.md, D6).
abstract interface class Clock {
  DateTime now();

  /// Completes after [duration]; throws [CancelledException] when [cancel]
  /// fires first.
  Future<void> delay(Duration duration, {CancelToken? cancel});

  /// Calls [onFire] once after [duration] unless cancelled.
  ClockTimer timer(Duration duration, void Function() onFire);
}

abstract interface class ClockTimer {
  bool get isActive;

  void cancel();
}

/// Wall-clock [Clock] on `dart:async` timers — the default of hosts.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Future<void> delay(Duration duration, {CancelToken? cancel}) =>
      waitOnTimer(this, duration, cancel);

  @override
  ClockTimer timer(Duration duration, void Function() onFire) =>
      _SystemTimer(Timer(duration, onFire));
}

final class _SystemTimer implements ClockTimer {
  _SystemTimer(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}

/// [Clock.delay] in terms of [Clock.timer]: shared by clock implementations.
Future<void> waitOnTimer(Clock clock, Duration duration, CancelToken? cancel) {
  if (cancel != null && cancel.isCancelled) {
    return Future.error(CancelledException(cancel.reason));
  }
  final done = Completer<void>();
  final timer = clock.timer(duration, () {
    if (!done.isCompleted) {
      done.complete();
    }
  });
  cancel?.onCancel.then((_) {
    if (!done.isCompleted) {
      timer.cancel();
      done.completeError(CancelledException(cancel.reason));
    }
  });
  return done.future;
}
