import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/call_sequence.dart';
import '../support/models.dart';

final _context = LlmContext(systemPrompt: '', messages: const []);

void main() {
  late FakeClock clock;
  late RecordingLogger logger;

  setUp(() {
    clock = FakeClock();
    logger = RecordingLogger();
  });

  StreamFunction retried(
    CallSequence inner, {
    RetryPolicy policy = const RetryPolicy(),
  }) => withTransientRetry(
    inner.call,
    policy,
    clock: clock,
    random: Random(42),
    logger: logger,
  );

  Future<List<AssistantMessageEvent>> run(
    CallSequence inner, {
    RetryPolicy policy = const RetryPolicy(),
    CancelToken? cancel,
  }) => collect(
    retried(inner, policy: policy)(testModel, _context, cancel: cancel),
    clock,
  );

  test('network error before first block is retried, after first block is '
      'surfaced', () async {
    final inner = CallSequence(clock, [
      failBefore(LlmErrorClass.network),
      failAfterBlock(LlmErrorClass.network),
    ]);

    final events = await run(inner);

    expect(inner.calls, 2, reason: 'one retry, then no retry after output');
    expect(events.whereType<StartEvent>(), hasLength(1));
    final last = terminalOf(events);
    expect(last.errorClass, LlmErrorClass.network);
    expect(last.content, [const TextContent('Hi')]);
  });

  test(
    'a retry that succeeds: one StartEvent, usage of attempts is summed',
    () async {
      final inner = CallSequence(clock, [
        failBefore(LlmErrorClass.server, usage: const Usage(input: 100)),
        answer('ok', usage: const Usage(input: 100, output: 5)),
      ]);

      final events = await run(inner);

      expect(events.whereType<StartEvent>(), hasLength(1));
      expect(events.last, isA<DoneEvent>());
      expect(terminalOf(events).usage.input, 200);
      expect(terminalOf(events).usage.output, 5);
    },
  );

  test('delays follow equal jitter within the formula', () async {
    final inner = CallSequence(clock, [
      failBefore(LlmErrorClass.network),
      failBefore(LlmErrorClass.timeout),
      answer('ok'),
    ]);

    await run(inner);

    final first = inner.callTimes[1] - inner.callTimes[0];
    final second = inner.callTimes[2] - inner.callTimes[1];
    expect(first.inMilliseconds, inInclusiveRange(500, 1100));
    expect(second.inMilliseconds, inInclusiveRange(1000, 2100));
  });

  for (final cls in [
    LlmErrorClass.terminalFinish,
    LlmErrorClass.auth,
    LlmErrorClass.overflow,
    LlmErrorClass.badRequest,
    LlmErrorClass.aborted,
  ]) {
    test('${cls.name} is not retried (LLM-9)', () async {
      final inner = CallSequence(clock, [failBefore(cls), answer('never')]);

      final events = await run(inner);

      expect(inner.calls, 1);
      expect(terminalOf(events).errorClass, cls);
    });
  }

  test(
    'maxAttempts limits transient retries; history is in the error',
    () async {
      final inner = CallSequence(clock, [
        failBefore(LlmErrorClass.network),
        failBefore(LlmErrorClass.server),
        failBefore(LlmErrorClass.server),
      ]);

      final events = await run(
        inner,
        policy: const RetryPolicy(maxAttempts: 3),
      );

      expect(inner.calls, 3);
      final message = terminalOf(events).errorMessage!;
      expect(message, startsWith('request failed after 3 attempts in '));
      expect(message, contains('attempt 1 network (network failure)'));
      expect(message, contains('attempt 3 server (server failure)'));
    },
  );

  test('429 has its own budget and honours Retry-After', () async {
    final inner = CallSequence(clock, [
      failBefore(
        LlmErrorClass.rateLimited,
        retryAfter: const Duration(seconds: 2),
      ),
      failBefore(
        LlmErrorClass.rateLimited,
        retryAfter: const Duration(seconds: 2),
      ),
      failBefore(
        LlmErrorClass.rateLimited,
        retryAfter: const Duration(seconds: 2),
      ),
      answer('ok'),
    ]);

    final events = await run(inner, policy: const RetryPolicy(maxAttempts: 1));

    expect(inner.calls, 4);
    expect(events.last, isA<DoneEvent>());
    final delay = inner.callTimes[1] - inner.callTimes[0];
    expect(delay.inMilliseconds, inInclusiveRange(2000, 2350));
  });

  test('the rate limit budget runs out', () async {
    final inner = CallSequence(clock, [
      for (var i = 0; i < 4; i++) failBefore(LlmErrorClass.rateLimited),
    ]);

    final events = await run(
      inner,
      policy: const RetryPolicy(rateLimitRetries: 2),
    );

    expect(inner.calls, 3);
    expect(terminalOf(events).errorClass, LlmErrorClass.rateLimited);
  });

  test('Retry-After: 200 above maxRetryAfter does not wait', () async {
    final inner = CallSequence(clock, [
      failBefore(
        LlmErrorClass.rateLimited,
        retryAfter: const Duration(seconds: 200),
      ),
      answer('never'),
    ]);

    final events = await run(inner);

    expect(inner.calls, 1);
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    expect(terminalOf(events).errorClass, LlmErrorClass.rateLimited);
  });

  test('each retry is logged as llm.retry', () async {
    final inner = CallSequence(clock, [
      failBefore(LlmErrorClass.network),
      answer('ok'),
    ]);

    await run(inner);

    final record = logger.eventsOf('llm.retry').single;
    expect(record.level, LogLevel.info);
    expect(record.fields, containsPair('attempt', 1));
    expect(record.fields, containsPair('class', 'network'));
    expect(record.fields['delay_ms'], isA<int>());
  });

  test('a cancel during the retry delay ends with aborted', () async {
    final source = CancelTokenSource();
    final inner = CallSequence(clock, [
      failBefore(LlmErrorClass.network),
      answer('never'),
    ]);
    final events = <AssistantMessageEvent>[];
    var done = false;
    retried(inner)(
      testModel,
      _context,
      cancel: source.token,
    ).listen(events.add, onDone: () => done = true);

    await clock.elapse(const Duration(milliseconds: 100));
    source.cancel();
    for (var i = 0; i < 20 && !done; i++) {
      await clock.elapse(const Duration(milliseconds: 100));
    }

    expect(done, isTrue);
    expect(terminalOf(events).errorClass, LlmErrorClass.aborted);
    expect(inner.calls, lessThanOrEqualTo(2));
  });

  group('withFallback', () {
    final modelB = ModelRef(
      provider: 'test',
      id: 'model-b',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost/v1'),
      contextWindow: 32000,
      maxOutputTokens: 4096,
    );

    Future<
      (
        List<AssistantMessageEvent>,
        List<FallbackNotice>,
        CallSequence,
        CallSequence,
      )
    >
    fallback(List<CallBehaviour> a, List<CallBehaviour> b) async {
      final first = CallSequence(clock, a);
      final second = CallSequence(clock, b);
      final notices = <FallbackNotice>[];
      final stream = withFallback(
        [testModel, modelB],
        (model) => model == testModel ? first.call : second.call,
        onNotice: notices.add,
      );
      final events = await collect(stream(testModel, _context), clock);
      return (events, notices, first, second);
    }

    test('429 before output switches to model B', () async {
      final (events, notices, _, second) = await fallback(
        [failBefore(LlmErrorClass.rateLimited, usage: const Usage(input: 10))],
        [answer('from B', usage: const Usage(input: 20))],
      );

      expect(notices.single.from, testModel);
      expect(notices.single.to, modelB);
      expect(notices.single.cause, LlmErrorClass.rateLimited);
      expect(notices.single.message, contains('model-b'));
      expect(second.calls, 1);
      final message = terminalOf(events);
      expect(message.model, modelB);
      expect(message.content, [const TextContent('from B')]);
      expect(message.usage.input, 30);
      expect(events.whereType<StartEvent>(), hasLength(1));
    });

    test('an error after output does not switch', () async {
      final (events, notices, _, second) = await fallback(
        [failAfterBlock(LlmErrorClass.network)],
        [answer('never')],
      );

      expect(second.calls, 0);
      expect(notices, isEmpty);
      expect(terminalOf(events).errorClass, LlmErrorClass.network);
    });

    for (final cls in [
      LlmErrorClass.aborted,
      LlmErrorClass.overflow,
      LlmErrorClass.badRequest,
      LlmErrorClass.terminalFinish,
    ]) {
      test('${cls.name} does not switch', () async {
        final (_, notices, _, second) = await fallback(
          [failBefore(cls)],
          [answer('never')],
        );

        expect(second.calls, 0);
        expect(notices, isEmpty);
      });
    }

    test('a chain of one model is transparent', () async {
      final only = CallSequence(clock, [failBefore(LlmErrorClass.server)]);
      final notices = <FallbackNotice>[];

      final events = await collect(
        withFallback([testModel], (_) => only.call, onNotice: notices.add)(
          testModel,
          _context,
        ),
        clock,
      );

      expect(notices, isEmpty);
      expect(terminalOf(events).errorClass, LlmErrorClass.server);
    });
  });
}
