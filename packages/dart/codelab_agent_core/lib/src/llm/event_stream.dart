import 'dart:async';

import 'events.dart';
import 'messages.dart';

/// A stream with an awaited result (`agent-core-architecture` §2.4): the
/// producer pushes events, the consumer reads them once and/or awaits
/// [result].
///
/// Single-subscription on purpose: the producer may push before the
/// consumer listens, and no event is lost; a second `listen` is a
/// programmer error ([StateError]). [result] always completes — with the
/// terminal event's value or with [StateError] if the stream ends without
/// one — and never becomes an unhandled error (LLM-3).
class EventStream<T, R> extends Stream<T> {
  EventStream({
    required bool Function(T event) isTerminal,
    required R Function(T event) resultOf,
  }) : _isTerminal = isTerminal,
       _resultOf = resultOf;

  final bool Function(T event) _isTerminal;
  final R Function(T event) _resultOf;
  final _controller = StreamController<T>();
  final _result = Completer<R>();
  var _closed = false;

  Future<R> get result => _result.future;

  /// Ignored after the terminal event and after [end].
  void push(T event) {
    if (_closed) {
      return;
    }
    _controller.add(event);
    if (_isTerminal(event)) {
      _complete(_resultOf(event));
      end();
    }
  }

  /// Idempotent. Without a terminal event [result] completes with
  /// [StateError].
  void end([R? result]) {
    if (_closed) {
      return;
    }
    _closed = true;
    if (result != null) {
      _complete(result);
    }
    if (!_result.isCompleted) {
      _result.future.ignore();
      _result.completeError(
        StateError('stream ended without a terminal event'),
      );
    }
    _controller.close();
  }

  void _complete(R value) {
    if (!_result.isCompleted) {
      _result.complete(value);
    }
  }

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

final class AssistantMessageEventStream
    extends EventStream<AssistantMessageEvent, AssistantMessage> {
  AssistantMessageEventStream()
    : super(
        isTerminal: (e) => e is DoneEvent || e is ErrorEvent,
        resultOf: (e) => switch (e) {
          DoneEvent(:final message) => message,
          ErrorEvent(:final error) => error,
          _ => throw StateError('not a terminal event'),
        },
      );
}
