import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/stream_state.dart';

/// A [StreamFunction] whose answer the test writes by hand through
/// [state]; cancelling the request token ends it with `ErrorEvent(aborted)`,
/// as a real adapter does.
final class ManualStream {
  ManualStream(this.clock);

  final Clock clock;
  final tokens = <CancelToken?>[];
  late ProviderStreamState state;
  late AssistantMessageEventStream _out;

  int get calls => tokens.length;

  AssistantMessageEventStream call(
    ModelRef model,
    LlmContext context, {
    CancelToken? cancel,
  }) {
    tokens.add(cancel);
    _out = AssistantMessageEventStream();
    state = ProviderStreamState(model, clock, _out);
    cancel?.onCancel.then((_) {
      state.fail(LlmErrorClass.aborted, 'Request was aborted', aborted: true);
      _out.end();
    });
    return _out;
  }

  /// Ends the stream after a terminal event pushed through [state].
  void end() => _out.end();
}

/// Collects events of [stream] as they arrive.
final class Recorder {
  Recorder(AssistantMessageEventStream stream) {
    stream.listen(events.add, onDone: _done.complete);
  }

  final events = <AssistantMessageEvent>[];
  final _done = Completer<void>();

  bool get isDone => _done.isCompleted;

  Future<void> get done => _done.future;

  AssistantMessage get last => switch (events.last) {
    DoneEvent(:final message) => message,
    ErrorEvent(:final error) => error,
    final other => throw StateError('not terminal: $other'),
  };
}
