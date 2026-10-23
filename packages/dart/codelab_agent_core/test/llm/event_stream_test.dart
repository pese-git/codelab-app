import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';

void main() {
  test('end() without terminal completes result with StateError', () async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final stream = AssistantMessageEventStream()
        ..push(StartEvent(() => partialMessage()))
        ..end();
      final events = await stream.toList();

      expect(events, hasLength(1));
      await expectLater(stream.result, throwsA(isA<StateError>()));
    }, (error, _) => errors.add(error));

    expect(errors, isEmpty);
  });

  test('an unobserved result never becomes an unhandled error', () async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      AssistantMessageEventStream().end();
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => errors.add(error));

    expect(errors, isEmpty);
  });

  test('result is the message of the terminal event', () async {
    final message = partialMessage(text: 'done');
    final stream = AssistantMessageEventStream()
      ..push(StartEvent(() => partialMessage()))
      ..push(DoneEvent(message));

    expect(await stream.result, message);
    expect(await stream.toList(), hasLength(2));
  });

  test('the error of ErrorEvent is the result', () async {
    final error = partialMessage(
      stopReason: StopReason.error,
      errorClass: LlmErrorClass.network,
    );
    final stream = AssistantMessageEventStream()..push(ErrorEvent(error));

    expect(await stream.result, error);
  });

  test('events pushed before listen are not lost', () async {
    final stream = AssistantMessageEventStream()
      ..push(StartEvent(() => partialMessage()))
      ..push(DoneEvent(partialMessage()));
    await Future<void>.delayed(Duration.zero);

    final events = await stream.toList();

    expect(events.map((e) => e.runtimeType), [StartEvent, DoneEvent]);
  });

  test('push after the terminal event is ignored', () async {
    final stream = AssistantMessageEventStream()
      ..push(DoneEvent(partialMessage()))
      ..push(StartEvent(() => partialMessage()))
      ..end();

    expect(await stream.toList(), hasLength(1));
  });

  test('a second listen is a StateError', () {
    final stream = AssistantMessageEventStream()..listen((_) {});

    expect(() => stream.listen((_) {}), throwsStateError);
  });

  test('partial of DoneEvent and ErrorEvent is their message', () {
    final message = partialMessage(text: 'x');

    expect(DoneEvent(message).partial, same(message));
    expect(ErrorEvent(message).partial, same(message));
  });

  test('withPartial maps the snapshot lazily and keeps the event kind', () {
    var built = 0;
    final event = BlockDeltaEvent(
      () {
        built++;
        return partialMessage(text: 'a');
      },
      index: 0,
      delta: 'a',
    );

    final mapped = event.withPartial(
      (m) => m.copyWith(usage: const Usage(input: 5)),
    );

    expect(built, 0);
    expect(mapped, isA<BlockDeltaEvent>());
    expect((mapped as BlockDeltaEvent).delta, 'a');
    expect(mapped.partial.usage.input, 5);
    expect(built, 1);
  });
}
