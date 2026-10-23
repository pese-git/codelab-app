import 'dart:async';

import '../util/clock.dart';

/// Cooperative cancellation — `agent-core-architecture` §3.
///
/// The owner of an operation keeps a [CancelTokenSource]; only the read side
/// [CancelToken] is passed down. Listeners of [CancelToken.onCancel] never run
/// inside [CancelTokenSource.cancel] (CAN-1), a cancelled token never becomes
/// uncancelled (CAN-2), and cancelling a parent cancels its children (CAN-3).

final class CancelledException implements Exception {
  const CancelledException(this.reason);

  final Object? reason;

  @override
  String toString() =>
      'Operation cancelled${reason == null ? '' : ': $reason'}';
}

abstract interface class CancelToken {
  bool get isCancelled;

  /// The first reason; `null` while the token is not cancelled.
  Object? get reason;

  /// Completes when the token is cancelled; never completes with an error.
  Future<void> get onCancel;

  /// Throws [CancelledException] with [reason] if the token is cancelled.
  void throwIfCancelled();

  /// A token that is never cancelled.
  static final CancelToken none = CancelTokenSource().token;
}

final class CancelTokenSource {
  /// A child of [parent] is cancelled together with it, with its reason.
  CancelTokenSource({CancelToken? parent}) {
    if (parent == null) {
      return;
    }
    if (parent.isCancelled) {
      _token._cancel(parent.reason);
      return;
    }
    parent.onCancel.then((_) {
      if (!_disposed) {
        _token._cancel(parent.reason);
      }
    });
  }

  final _token = _Token();
  var _disposed = false;

  CancelToken get token => _token;

  bool get isCancelled => _token.isCancelled;

  /// Idempotent; the first reason wins. Without a reason — [UserCancel].
  void cancel([Object? reason]) => _token._cancel(reason ?? const UserCancel());

  /// Unlinks the source from its parent; the token keeps its state.
  void dispose() => _disposed = true;
}

final class _Token implements CancelToken {
  final _done = Completer<void>();
  Object? _reason;
  var _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  @override
  Object? get reason => _reason;

  @override
  Future<void> get onCancel => _done.future;

  @override
  void throwIfCancelled() {
    if (_cancelled) {
      throw CancelledException(_reason);
    }
  }

  void _cancel(Object? reason) {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _reason = reason;
    scheduleMicrotask(_done.complete);
  }
}

/// `session/cancel` or `AgentSession.cancel()`.
final class UserCancel {
  const UserCancel();

  @override
  String toString() => 'user cancel';
}

/// A watchdog of one model request fired: `connect` or `idle`.
final class WatchdogFired {
  const WatchdogFired(this.kind);

  final String kind;

  @override
  String toString() => 'watchdog $kind';
}

/// The host is shutting down.
final class ShutdownCancel {
  const ShutdownCancel();

  @override
  String toString() => 'shutdown';
}

/// Completes with the result of [work], or throws [CancelledException] if
/// [cancel] fires first. The late result or error of [work] is dropped, so
/// it never becomes an unhandled error; the owner of [work] releases its
/// resources on [CancelToken.onCancel] itself.
Future<T> raceCancel<T>(Future<T> work, CancelToken cancel) {
  if (cancel.isCancelled) {
    work.ignore();
    return Future.error(CancelledException(cancel.reason));
  }
  final result = Completer<T>();
  work.then(
    (value) {
      if (!result.isCompleted) {
        result.complete(value);
      }
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) {
        result.completeError(error, stack);
      }
    },
  );
  cancel.onCancel.then((_) {
    if (!result.isCompleted) {
      result.completeError(CancelledException(cancel.reason));
    }
  });
  return result.future;
}

/// Waits [duration] on [clock]; throws [CancelledException] on cancel.
Future<void> delayCancellable(
  Clock clock,
  Duration duration,
  CancelToken cancel,
) => clock.delay(duration, cancel: cancel);
