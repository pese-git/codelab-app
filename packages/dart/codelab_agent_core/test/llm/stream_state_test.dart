import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/stream_state.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/models.dart';

/// Runs [body] through [runProvider] and collects the events.
Future<List<AssistantMessageEvent>> _run(
  Future<void> Function(ProviderStreamState state) body, {
  CancelToken? cancel,
  LlmErrorClass Function(Object error)? classify,
}) => runProvider(
  testModel,
  cancel,
  FakeClock(),
  body,
  classify: classify,
).toList();

void main() {
  group('ProviderStreamState', () {
    test('text block: start, delta, end, done', () async {
      final events = await _run((state) async {
        state.start();
        final i = state.openBlock(BlockKind.text);
        state
          ..append(i, 'Hel')
          ..append(i, 'lo')
          ..closeBlock(i)
          ..setRawStopReason('stop')
          ..finish(StopReason.stop);
      });

      expect(events.map((e) => e.runtimeType), [
        StartEvent,
        BlockStartEvent,
        BlockDeltaEvent,
        BlockDeltaEvent,
        BlockEndEvent,
        DoneEvent,
      ]);
      expect((events[3] as BlockDeltaEvent).delta, 'lo');
      expect((events[4] as BlockEndEvent).block, const TextContent('Hello'));
      final done = (events.last as DoneEvent).message;
      expect(done.content, [const TextContent('Hello')]);
      expect(done.stopReason, StopReason.stop);
      expect(done.rawStopReason, 'stop');
    });

    test('each snapshot holds the content up to its event (LLM-4)', () async {
      final events = await _run((state) async {
        state.start();
        final i = state.openBlock(BlockKind.text);
        state
          ..append(i, 'a')
          ..append(i, 'b')
          ..append(i, 'c')
          ..finish(StopReason.stop);
      });

      final deltas = events.whereType<BlockDeltaEvent>().toList();
      expect(
        [
          for (final d in deltas)
            (d.partial.content.single as TextContent).text,
        ],
        ['a', 'ab', 'abc'],
      );
    });

    test(
      'interleaved tool calls pair start and end by index (LLM-5)',
      () async {
        final events = await _run((state) async {
          state.start();
          final a = state.openBlock(
            BlockKind.toolCall,
            id: 'call_1',
            name: 'read',
          );
          final b = state.openBlock(
            BlockKind.toolCall,
            id: 'call_2',
            name: 'ls',
          );
          state
            ..append(a, '{"path":')
            ..append(b, '{}')
            ..append(a, '"a.txt"}')
            ..closeBlock(b)
            ..closeBlock(a)
            ..finish(StopReason.toolUse);
        });

        final starts = events.whereType<BlockStartEvent>().map((e) => e.index);
        final ends = events.whereType<BlockEndEvent>().map((e) => e.index);
        expect(starts.toSet(), ends.toSet());
        final midway = events.whereType<BlockDeltaEvent>().first.partial;
        expect(
          midway.toolCalls.first.arguments,
          isEmpty,
          reason: 'an open call has no arguments yet (LLM-6)',
        );
        final done = (events.last as DoneEvent).message;
        expect(done.toolCalls.map((c) => c.arguments), [
          {'path': 'a.txt'},
          <String, Object?>{},
        ]);
      },
    );

    test('unparseable arguments become {} with a note (LLM-6)', () async {
      final events = await _run((state) async {
        state.start();
        final i = state.openBlock(
          BlockKind.toolCall,
          id: 'call_1',
          name: 'read',
        );
        state
          ..append(i, '{"path": "a.')
          ..closeBlock(i)
          ..finish(StopReason.toolUse);
      });

      final end = events.whereType<BlockEndEvent>().single;
      expect((end.block as ToolCall).arguments, isEmpty);
      final done = (events.last as DoneEvent).message;
      expect(done.toolCalls.single.arguments, isEmpty);
      expect(done.errorMessage, contains('call_1'));
    });

    test('empty arguments are {}', () async {
      final events = await _run((state) async {
        state.start();
        final i = state.openBlock(BlockKind.toolCall, id: 'call_1', name: 'ls');
        state
          ..closeBlock(i)
          ..finish(StopReason.toolUse);
      });

      final done = (events.last as DoneEvent).message;
      expect(done.toolCalls.single.arguments, isEmpty);
      expect(done.errorMessage, isNull);
    });

    test('finish closes open blocks before DoneEvent', () async {
      final events = await _run((state) async {
        state.start();
        state.append(state.openBlock(BlockKind.thinking), 'hmm');
        state.append(state.openBlock(BlockKind.text), 'ok');
        state.finish(StopReason.stop, note: 'stream may be truncated');
      });

      expect(events.whereType<BlockEndEvent>(), hasLength(2));
      expect(events.last, isA<DoneEvent>());
      expect(
        (events.last as DoneEvent).message.errorMessage,
        'stream may be truncated',
      );
    });

    test('fail keeps open blocks as they are', () async {
      final events = await _run((state) async {
        state.start();
        state.append(state.openBlock(BlockKind.text), 'partial');
        state.openBlock(BlockKind.toolCall, id: 'call_1', name: 'read');
        state.fail(
          LlmErrorClass.network,
          'connection reset',
          retryAfter: const Duration(seconds: 2),
        );
      });

      final error = events.last as ErrorEvent;
      expect(events.whereType<BlockEndEvent>(), isEmpty);
      expect(error.error.stopReason, StopReason.error);
      expect(error.error.errorClass, LlmErrorClass.network);
      expect(error.error.errorMessage, 'connection reset');
      expect(error.retryAfter, const Duration(seconds: 2));
      expect(error.error.content, [
        const TextContent('partial'),
        ToolCall(id: 'call_1', name: 'read', arguments: const {}),
      ]);
    });

    test('an aborted failure has stopReason aborted', () async {
      final events = await _run((state) async {
        state.start();
        state.fail(LlmErrorClass.aborted, 'Request was aborted', aborted: true);
      });

      final error = (events.last as ErrorEvent).error;
      expect(error.stopReason, StopReason.aborted);
      expect(error.errorClass, LlmErrorClass.aborted);
    });

    test('metadata after an event does not change its snapshot', () async {
      final events = await _run((state) async {
        state.start();
        final i = state.openBlock(BlockKind.thinking);
        state
          ..append(i, 'think')
          ..setSignature(i, 'sig')
          ..setUsage(const Usage(input: 10))
          ..closeBlock(i)
          ..finish(StopReason.stop);
      });

      final delta = events.whereType<BlockDeltaEvent>().single;
      expect(
        (delta.partial.content.single as ThinkingContent).signature,
        isNull,
      );
      expect(delta.partial.usage, Usage.zero);
      final done = (events.last as DoneEvent).message;
      expect(
        done.content.single,
        const ThinkingContent('think', signature: 'sig'),
      );
      expect(done.usage.input, 10);
    });

    test('state calls after the terminal event are ignored', () async {
      final events = await _run((state) async {
        state.start();
        state.finish(StopReason.stop);
        state.append(state.openBlock(BlockKind.text), 'late');
        state.fail(LlmErrorClass.network, 'late');
      });

      expect(events.last, isA<DoneEvent>());
      expect(events, hasLength(2));
    });
  });

  group('runProvider', () {
    test('work starts after the current microtask', () async {
      var started = false;
      final stream = runProvider(testModel, null, FakeClock(), (state) async {
        started = true;
        state
          ..start()
          ..finish(StopReason.stop);
      });

      expect(started, isFalse);
      await stream.toList();
      expect(started, isTrue);
    });

    test('an exception in the body becomes ErrorEvent (LLM-1)', () async {
      final errors = <Object>[];
      late List<AssistantMessageEvent> events;
      await runZonedGuarded(() async {
        events = await _run(
          (state) async {
            state.start();
            throw const FormatException('bad chunk');
          },
          classify: (error) => error is FormatException
              ? LlmErrorClass.server
              : LlmErrorClass.unknown,
        );
      }, (error, _) => errors.add(error));

      expect(errors, isEmpty);
      final error = (events.last as ErrorEvent).error;
      expect(error.errorClass, LlmErrorClass.server);
      expect(error.errorMessage, contains('bad chunk'));
    });

    test('a body that forgets the terminal gets one (LLM-2)', () async {
      final events = await _run((state) async => state.start());

      expect(events.last, isA<ErrorEvent>());
      expect(events.whereType<ErrorEvent>(), hasLength(1));
    });

    test(
      'a cancelled token gives ErrorEvent(aborted) before any work',
      () async {
        final source = CancelTokenSource()..cancel();
        var called = false;

        final events = await _run(
          (state) async => called = true,
          cancel: source.token,
        );

        expect(called, isFalse);
        expect(events.single, isA<ErrorEvent>());
        expect(
          (events.single as ErrorEvent).error.stopReason,
          StopReason.aborted,
        );
      },
    );

    test('CancelledException from the body is aborted', () async {
      final source = CancelTokenSource();
      final events = await _run((state) async {
        state.start();
        source.cancel();
        source.token.throwIfCancelled();
      }, cancel: source.token);

      expect(
        (events.last as ErrorEvent).error.errorClass,
        LlmErrorClass.aborted,
      );
    });
  });
}
