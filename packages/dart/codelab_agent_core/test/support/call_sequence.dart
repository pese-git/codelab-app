import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/stream_state.dart';
import 'package:codelab_agent_core/testing.dart';

/// Behaviour of one model call, written through the adapter state.
typedef CallBehaviour = void Function(ProviderStreamState state);

/// A [StreamFunction] whose n-th call plays the n-th behaviour; it records
/// the time and the model of every call.
final class CallSequence {
  CallSequence(this.clock, this.behaviours);

  final FakeClock clock;
  final List<CallBehaviour> behaviours;
  final callTimes = <Duration>[];
  final models = <ModelRef>[];

  int get calls => callTimes.length;

  AssistantMessageEventStream call(
    ModelRef model,
    LlmContext context, {
    CancelToken? cancel,
  }) {
    final n = callTimes.length;
    callTimes.add(clock.elapsed);
    models.add(model);
    return runProvider(model, cancel, clock, (state) async {
      if (n >= behaviours.length) {
        throw StateError('unexpected call ${n + 1}');
      }
      behaviours[n](state);
    });
  }
}

CallBehaviour failBefore(
  LlmErrorClass errorClass, {
  Duration? retryAfter,
  Usage usage = Usage.zero,
}) =>
    (state) => state
      ..start()
      ..setUsage(usage)
      ..fail(
        errorClass,
        '${errorClass.name} failure',
        aborted: errorClass == LlmErrorClass.aborted,
        retryAfter: retryAfter,
      );

CallBehaviour failAfterBlock(LlmErrorClass errorClass) => (state) {
  state.start();
  state.append(state.openBlock(BlockKind.text), 'Hi');
  state.fail(errorClass, '${errorClass.name} after output');
};

CallBehaviour answer(String text, {Usage usage = Usage.zero}) => (state) {
  state.start();
  state.append(state.openBlock(BlockKind.text), text);
  state
    ..setUsage(usage)
    ..finish(StopReason.stop);
};

/// Collects [stream], moving [clock] while it runs.
Future<List<AssistantMessageEvent>> collect(
  AssistantMessageEventStream stream,
  FakeClock clock, {
  Duration step = const Duration(milliseconds: 100),
  Duration limit = const Duration(minutes: 30),
}) async {
  final events = <AssistantMessageEvent>[];
  var done = false;
  stream.listen(events.add, onDone: () => done = true);
  var moved = Duration.zero;
  await clock.elapse(Duration.zero);
  while (!done && moved < limit) {
    await clock.elapse(step);
    moved += step;
  }
  if (!done) {
    throw StateError('the stream did not end within $limit');
  }
  return events;
}

AssistantMessage terminalOf(List<AssistantMessageEvent> events) =>
    switch (events.last) {
      DoneEvent(:final message) => message,
      ErrorEvent(:final error) => error,
      final other => throw StateError('not terminal: $other'),
    };
