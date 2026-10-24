import '../cancel/cancel_token.dart';
import '../util/clock.dart';

/// [Clock] whose time moves only when a test moves it.
///
/// [elapse] fires due timers one by one in the order of their due time
/// (ties — in the order they were started) and lets microtasks run after
/// each one, so code that awaits a delay and starts the next timer is seen
/// within the same [elapse].
final class FakeClock implements Clock {
  FakeClock({DateTime? start}) : _start = start ?? DateTime.utc(2026);

  final DateTime _start;
  late DateTime _now = _start;
  final _timers = <_FakeTimer>[];
  var _sequence = 0;

  @override
  DateTime now() => _now;

  /// Time moved since the start.
  Duration get elapsed => _now.difference(_start);

  /// Active timers that have not fired yet.
  int get pendingTimers => _timers.where((t) => t.isActive).length;

  @override
  Future<void> delay(Duration duration, {CancelToken? cancel}) =>
      waitOnTimer(this, duration, cancel);

  @override
  ClockTimer timer(Duration duration, void Function() onFire) {
    final timer = _FakeTimer(
      due: _now.add(duration < Duration.zero ? Duration.zero : duration),
      sequence: _sequence++,
      onFire: onFire,
    );
    _timers.add(timer);
    return timer;
  }

  /// Moves the time by [duration], firing due timers on the way.
  Future<void> elapse(Duration duration) async {
    final target = _now.add(duration);
    await _flushMicrotasks();
    while (true) {
      final next = _nextDue(target);
      if (next == null) {
        break;
      }
      _now = next.due;
      next.fire();
      await _flushMicrotasks();
    }
    _now = target;
    await _flushMicrotasks();
  }

  _FakeTimer? _nextDue(DateTime target) {
    _timers.removeWhere((t) => !t.isActive);
    _FakeTimer? next;
    for (final timer in _timers) {
      if (timer.due.isAfter(target)) {
        continue;
      }
      if (next == null ||
          timer.due.isBefore(next.due) ||
          (timer.due == next.due && timer.sequence < next.sequence)) {
        next = timer;
      }
    }
    return next;
  }

  static Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);
}

final class _FakeTimer implements ClockTimer {
  _FakeTimer({required this.due, required this.sequence, required this.onFire});

  final DateTime due;
  final int sequence;
  final void Function() onFire;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) {
      return;
    }
    _active = false;
    onFire();
  }
}
