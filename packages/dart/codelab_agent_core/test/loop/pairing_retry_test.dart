import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/call_sequence.dart';
import 'loop_harness.dart';

void main() {
  test('a pairing 400 is retried once with a rebuilt payload (D8)', () async {
    late final CallSequence calls;
    final h = await LoopHarness.create(
      stream: (model, context, {cancel}) =>
          calls(model, context, cancel: cancel),
    );
    calls = CallSequence(h.clock, [
      (state) => state
        ..start()
        ..fail(
          LlmErrorClass.badRequest,
          'messages.2: tool_use ids were found without tool_result blocks',
        ),
      answer('ok'),
    ]);

    final added = await h.run([user('go')]);

    expect(calls.calls, 2);
    expect(h.trace.where((t) => t == 'ModelRequested'), hasLength(2));
    expect(h.trace.where((t) => t.startsWith('StepStarted')), [
      'StepStarted(0)',
    ]);
    expect(h.trace, isNot(contains(startsWith('AgentError'))));
    expect(
      added.whereType<AssistantMessage>().single.stopReason,
      StopReason.stop,
    );
    expect(h.trace.last, 'TurnEnded(completed)');
  });

  test('a second pairing 400 is an ordinary failure', () async {
    late final CallSequence calls;
    final h = await LoopHarness.create(
      stream: (model, context, {cancel}) =>
          calls(model, context, cancel: cancel),
    );
    void fail(state) => state
      ..start()
      ..fail(LlmErrorClass.badRequest, 'invalid tool_call_id');
    calls = CallSequence(h.clock, [fail, fail]);

    await h.run([user('go')]);

    expect(calls.calls, 2);
    expect(h.trace.last, 'TurnEnded(failed)');
    expect(h.trace, contains('AgentError(provider badRequest)'));
  });

  test('a badRequest about something else is not retried', () async {
    late final CallSequence calls;
    final h = await LoopHarness.create(
      stream: (model, context, {cancel}) =>
          calls(model, context, cancel: cancel),
    );
    calls = CallSequence(h.clock, [failBefore(LlmErrorClass.badRequest)]);

    await h.run([user('go')]);

    expect(calls.calls, 1);
    expect(h.trace.last, 'TurnEnded(failed)');
  });
}
