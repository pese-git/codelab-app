import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/manual_stream.dart';
import '../support/models.dart';

const _s = Duration(seconds: 1);

final _context = LlmContext(systemPrompt: '', messages: const []);

ModelRef _hidden() => ModelRef(
  provider: 'test',
  id: 'o-hidden',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost/v1'),
  contextWindow: 32000,
  maxOutputTokens: 4096,
  hiddenReasoning: true,
);

void main() {
  late FakeClock clock;
  late ManualStream inner;
  late StreamFunction watched;

  setUp(() {
    clock = FakeClock();
    inner = ManualStream(clock);
    watched = withWatchdogs(
      inner.call,
      connect: _s * 30,
      idle: _s * 120,
      idleReasoning: _s * 600,
      clock: clock,
    );
  });

  Future<Recorder> start({ModelRef? model, CancelToken? cancel}) async {
    final recorder = Recorder(
      watched(model ?? testModel, _context, cancel: cancel),
    );
    await Future<void>.delayed(Duration.zero);
    return recorder;
  }

  test('no headers within 30 s → timeout (connect watchdog)', () async {
    final recorder = await start();

    await clock.elapse(_s * 29);
    expect(recorder.isDone, isFalse);
    await clock.elapse(_s * 1);
    await recorder.done;

    expect(recorder.last.stopReason, StopReason.error);
    expect(recorder.last.errorClass, LlmErrorClass.timeout);
    expect(
      recorder.last.errorMessage,
      'connect_stall: no response headers within 30 s (connect watchdog)',
    );
  });

  test(
    'silence of 120 s after the headers → timeout (idle watchdog)',
    () async {
      final recorder = await start();
      await clock.elapse(_s);
      inner.state.start();

      await clock.elapse(_s * 120);
      await recorder.done;

      expect(recorder.last.errorClass, LlmErrorClass.timeout);
      expect(
        recorder.last.errorMessage,
        'first_byte_stall: no stream events for 120 s after response headers '
        '(idle watchdog)',
      );
    },
  );

  test('silence of 120 s after the first block → mid_stream_idle', () async {
    final recorder = await start();
    inner.state.start();
    inner.state.append(inner.state.openBlock(BlockKind.text), 'Hi');

    await clock.elapse(_s * 121);
    await recorder.done;

    expect(
      recorder.last.errorMessage,
      'mid_stream_idle: no stream events for 120 s (idle watchdog)',
    );
    expect(recorder.last.content, [const TextContent('Hi')]);
  });

  test('a user cancel stays aborted', () async {
    final source = CancelTokenSource();
    final recorder = await start(cancel: source.token);
    inner.state.start();

    source.cancel();
    await recorder.done;

    expect(recorder.last.stopReason, StopReason.aborted);
    expect(recorder.last.errorClass, LlmErrorClass.aborted);
  });

  test('the watchdog cancels only the attempt token', () async {
    final turn = CancelTokenSource();
    final recorder = await start(cancel: turn.token);

    await clock.elapse(_s * 30);
    await recorder.done;

    expect(inner.tokens.single!.isCancelled, isTrue);
    expect(inner.tokens.single!.reason, isA<WatchdogFired>());
    expect(turn.token.isCancelled, isFalse);
  });

  test('a normal answer passes through unchanged', () async {
    final recorder = await start();
    inner.state.start();
    inner.state.append(inner.state.openBlock(BlockKind.text), 'ok');
    inner.state.finish(StopReason.stop);
    inner.end();
    await recorder.done;

    expect(recorder.last.content, [const TextContent('ok')]);
    expect(clock.pendingTimers, 0, reason: 'timers are released');
  });

  group('reasoning is not idleness (L-31, LLM-16)', () {
    test('thinking deltas every 100 s for 400 s keep the request', () async {
      final recorder = await start();
      inner.state.start();
      final thinking = inner.state.openBlock(BlockKind.thinking);
      for (var i = 0; i < 4; i++) {
        await clock.elapse(_s * 100);
        inner.state.append(thinking, 'step $i ');
      }
      inner.state.finish(StopReason.stop);
      inner.end();
      await recorder.done;

      expect(recorder.events.last, isA<DoneEvent>());
    });

    test(
      'only keep-alive pings → timeout 120 s after the last event',
      () async {
        final recorder = await start();
        inner.state.start();
        inner.state.append(inner.state.openBlock(BlockKind.thinking), 'a');
        for (var i = 0; i < 3; i++) {
          await clock.elapse(_s * 30);
          // A ping produces no event: nothing reaches the watchdog.
        }
        expect(recorder.isDone, isFalse);
        await clock.elapse(_s * 30);
        await recorder.done;

        expect(recorder.last.errorClass, LlmErrorClass.timeout);
        expect(clock.elapsed, _s * 120);
      },
    );

    test(
      'hidden reasoning: 500 s of silence after the headers is fine',
      () async {
        final recorder = await start(model: _hidden());
        inner.state.start();

        await clock.elapse(_s * 500);
        expect(recorder.isDone, isFalse);
        inner.state.append(inner.state.openBlock(BlockKind.text), 'answer');
        inner.state.finish(StopReason.stop);
        inner.end();
        await recorder.done;

        expect(recorder.events.last, isA<DoneEvent>());
      },
    );

    test(
      'hidden reasoning: 600 s of silence → timeout about hidden reasoning',
      () async {
        final recorder = await start(model: _hidden());
        inner.state.start();

        await clock.elapse(_s * 600);
        await recorder.done;

        expect(
          recorder.last.errorMessage,
          'first_byte_stall: no stream events for 600 s while waiting for '
          'hidden reasoning (idle watchdog)',
        );
      },
    );

    test(
      'hidden reasoning: after the first block idle is 120 s again',
      () async {
        final recorder = await start(model: _hidden());
        inner.state.start();
        await clock.elapse(_s * 410);
        inner.state.append(inner.state.openBlock(BlockKind.text), 'a');

        await clock.elapse(_s * 121);
        await recorder.done;

        expect(
          recorder.last.errorMessage,
          'mid_stream_idle: no stream events for 120 s (idle watchdog)',
        );
      },
    );
  });
}
