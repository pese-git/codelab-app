import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/providers/openai_compatible.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/provider_harness.dart';

final _config = ProviderConfig(
  name: 'openai',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('https://api.openai.com/v1'),
  apiKey: 'sk-test-key',
);

final _model = ModelRef(
  provider: 'openai',
  id: 'gpt-fixture',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('https://api.openai.com/v1'),
  contextWindow: 128000,
  maxOutputTokens: 16384,
);

final _context = LlmContext(
  systemPrompt: 'You are CodeLab.',
  messages: [
    UserMessage(const [TextContent('hi')], timestamp: DateTime.utc(2026)),
  ],
);

Future<List<AssistantMessageEvent>> _play(
  String fixture, {
  Chunking chunking = Chunking.whole,
  ProviderHarness? harness,
}) {
  final h =
      harness ??
      ProviderHarness(
        body: readSseFixture('openai/$fixture'),
        chunking: chunking,
      );
  return h.run(
    openAiCompatibleStreamFunction(_config, h.services),
    _model,
    _context,
  );
}

AssistantMessage _final(List<AssistantMessageEvent> events) =>
    switch (events.last) {
      DoneEvent(:final message) => message,
      ErrorEvent(:final error) => error,
      final other => throw StateError('not terminal: $other'),
    };

void _expectGrammar(List<AssistantMessageEvent> events) {
  expect(events.first, anyOf(isA<StartEvent>(), isA<ErrorEvent>()));
  final terminals = events.where((e) => e is DoneEvent || e is ErrorEvent);
  expect(terminals, hasLength(1), reason: 'LLM-2');
  expect(terminals.single, same(events.last));
  if (events.last is DoneEvent) {
    final opened = events.whereType<BlockStartEvent>().map((e) => e.index);
    final closed = events.whereType<BlockEndEvent>().map((e) => e.index);
    expect(closed.toSet(), opened.toSet(), reason: 'LLM-5');
  }
}

void main() {
  group('stream parsing', () {
    for (final chunking in Chunking.values) {
      test('text with keep-alive comments (${chunking.name})', () async {
        final events = await _play('text.sse', chunking: chunking);

        _expectGrammar(events);
        final message = _final(events);
        expect(message.content, [const TextContent('Hello, world')]);
        expect(message.stopReason, StopReason.stop);
        expect(message.rawStopReason, 'stop');
        expect(message.usage.input, 20);
        expect(message.usage.output, 3);
        expect(message.model, _model);
      });
    }

    test('a tool call in parts — the example of §2.7', () async {
      final events = await _play('tool_call_parts.sse');

      _expectGrammar(events);
      expect(events.map((e) => e.runtimeType), [
        StartEvent,
        BlockStartEvent,
        BlockDeltaEvent,
        BlockEndEvent,
        BlockStartEvent,
        BlockDeltaEvent,
        BlockDeltaEvent,
        BlockEndEvent,
        DoneEvent,
      ]);
      final deltas = events.whereType<BlockDeltaEvent>().map((e) => e.delta);
      expect(deltas, ['Let me check', '{"path":', '"a.txt"}']);
      final message = _final(events);
      expect(message.content, [
        const TextContent('Let me check'),
        ToolCall(
          id: 'call_1',
          name: 'read',
          arguments: const {'path': 'a.txt'},
        ),
      ]);
      expect(message.stopReason, StopReason.toolUse);
      expect(message.rawStopReason, 'tool_calls');
      expect(message.usage.input, 388);
      expect(message.usage.cacheRead, 512);
      expect(message.usage.output, 40);
    });

    test('two interleaved tool calls', () async {
      final events = await _play(
        'two_tool_calls.sse',
        chunking: Chunking.byChar,
      );

      _expectGrammar(events);
      expect(_final(events).toolCalls, [
        ToolCall(
          id: 'call_a',
          name: 'read',
          arguments: const {'path': 'a.txt'},
        ),
        ToolCall(id: 'call_b', name: 'ls', arguments: const {'path': 'src'}),
      ]);
    });

    test('a repeated arguments frame does not double the JSON', () async {
      final message = _final(await _play('repeated_arguments.sse'));

      expect(message.toolCalls.single.arguments, {'path': 'a.txt'});
      expect(message.errorMessage, isNull);
    });

    test('a new id on index 0 opens a second call', () async {
      final message = _final(await _play('reused_index.sse'));

      expect(message.toolCalls.map((c) => (c.id, c.name)), [
        ('call_1', 'read'),
        ('call_2', 'ls'),
      ]);
    });

    test('a call without id gets call_<n>', () async {
      final message = _final(await _play('call_without_id.sse'));

      expect(message.toolCalls.single.id, 'call_0');
      expect(message.toolCalls.single.name, 'ls');
    });

    test('reasoning_content and reasoning become thinking blocks', () async {
      final a = _final(await _play('reasoning_content.sse'));
      final b = _final(await _play('reasoning_field.sse'));

      expect(a.content, [
        const ThinkingContent('Thinking.', api: ProviderApi.openaiChat),
        const TextContent('Answer'),
      ]);
      expect(a.usage.reasoning, 20);
      expect(b.content, [
        const ThinkingContent('Plan.', api: ProviderApi.openaiChat),
        const TextContent('Done'),
      ]);
    });

    test(
      'cache usage: prompt_cache_hit_tokens and cache_write_tokens',
      () async {
        final hit = _final(await _play('usage_cache_hit_tokens.sse')).usage;
        final write = _final(await _play('usage_cache_write.sse')).usage;

        expect((hit.input, hit.cacheRead, hit.cacheWrite), (400, 600, 0));
        expect(
          (write.input, write.cacheRead, write.cacheWrite),
          (500, 200, 300),
        );
      },
    );

    test('finish_reason length', () async {
      expect(
        _final(await _play('finish_length.sse')).stopReason,
        StopReason.length,
      );
    });

    test('content_filter is terminalFinish', () async {
      final message = _final(await _play('finish_content_filter.sse'));

      expect(message.errorClass, LlmErrorClass.terminalFinish);
      expect(message.errorMessage, 'Provider finish_reason: content_filter');
      expect(message.content, [const TextContent('I')]);
    });

    test('an unknown finish_reason is unknown with a warning', () async {
      final harness = ProviderHarness(
        body: readSseFixture('openai/finish_unknown.sse'),
      );

      final message = _final(await _play('', harness: harness));

      expect(message.errorClass, LlmErrorClass.unknown);
      expect(message.errorMessage, 'Provider finish_reason: sleepy');
      expect(
        harness.logger.eventsOf('llm.finish_reason.unknown'),
        hasLength(1),
      );
    });

    test('end of body without finish_reason, with content', () async {
      final message = _final(await _play('no_finish_with_content.sse'));

      expect(message.stopReason, StopReason.stop);
      expect(message.content, [const TextContent('cut short')]);
      expect(message.errorMessage, contains('may be truncated'));
    });

    test(
      'end of body without finish_reason, unparseable arguments → length',
      () async {
        final message = _final(await _play('no_finish_bad_arguments.sse'));

        expect(message.stopReason, StopReason.length);
        expect(message.toolCalls.single.arguments, isEmpty);
      },
    );

    test('end of body without finish_reason and without content', () async {
      final message = _final(await _play('no_finish_empty.sse'));

      expect(message.errorClass, LlmErrorClass.network);
      expect(
        message.errorMessage,
        'stream ended without finish_reason and without content',
      );
    });

    test('an error object in a chunk', () async {
      final events = await _play('error_chunk.sse');

      _expectGrammar(events);
      final message = _final(events);
      expect(message.errorClass, LlmErrorClass.server);
      expect(message.errorMessage, contains('Upstream overloaded'));
      expect(message.content, [const TextContent('Hi')]);
    });

    test('200 without any event', () async {
      final message = _final(await _play('empty_body.sse'));

      expect(message.errorClass, LlmErrorClass.network);
      expect(message.errorMessage, contains('empty event stream'));
    });

    test(
      'unparseable chunk JSON is an ErrorEvent, not an exception (LLM-1)',
      () async {
        final harness = ProviderHarness(body: 'data: {"choices": [\n\n');

        final events = await _play('', harness: harness);

        _expectGrammar(events);
        expect(_final(events).errorClass, LlmErrorClass.server);
      },
    );
  });

  group('HTTP errors', () {
    test('429 with Retry-After, no StartEvent, key redacted', () async {
      final harness = ProviderHarness(
        status: 429,
        headers: const {'content-type': 'application/json', 'retry-after': '2'},
        body: jsonEncode({
          'error': {
            'message': 'Rate limit for key sk-test-key',
            'type': 'requests',
          },
        }),
      );

      final events = await _play('', harness: harness);

      expect(events.single, isA<ErrorEvent>());
      final error = events.single as ErrorEvent;
      expect(error.retryAfter, const Duration(seconds: 2));
      expect(error.error.errorClass, LlmErrorClass.rateLimited);
      expect(error.error.errorMessage, startsWith('openai 429: '));
      expect(error.error.errorMessage, isNot(contains('sk-test-key')));
    });

    test('200 with HTML is badRequest with a hint', () async {
      final harness = ProviderHarness(
        headers: const {'content-type': 'text/html'},
        body: '<html>not an API</html>',
      );

      final message = _final(await _play('', harness: harness));

      expect(message.errorClass, LlmErrorClass.badRequest);
      expect(
        message.errorMessage,
        'endpoint did not return an event stream (content-type: text/html); '
        'check baseUrl',
      );
    });

    test('200 with a JSON error object takes its class', () async {
      final harness = ProviderHarness(
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {
            'message': 'Invalid API key',
            'type': 'authentication_error',
          },
        }),
      );

      expect(
        _final(await _play('', harness: harness)).errorClass,
        LlmErrorClass.auth,
      );
    });

    test('a redirect to another host is badRequest', () async {
      final client = MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {
            'location': 'https://elsewhere.example.org/v1/chat/completions',
          },
        ),
      );
      final harness = ProviderHarness();
      final services = CoreLlmServices(
        httpClient: client,
        clock: harness.clock,
        random: harness.services.random,
        logger: harness.logger,
      );

      final message = _final(
        await openAiCompatibleStreamFunction(_config, services)(
          _model,
          _context,
        ).toList(),
      );

      expect(message.errorClass, LlmErrorClass.badRequest);
      expect(message.errorMessage, contains('redirect to another origin'));
    });
  });

  test(
    'cancel mid-stream yields ErrorEvent(aborted) and closes the request',
    () async {
      final body = StreamController<List<int>>();
      var bodyCancelled = false;
      body.onCancel = () => bodyCancelled = true;
      var aborted = false;
      final client = MockClient.streaming((request, _) async {
        unawaited(
          (request as http.Abortable).abortTrigger!.then((_) => aborted = true),
        );
        return http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final harness = ProviderHarness();
      final services = CoreLlmServices(
        httpClient: client,
        clock: harness.clock,
        random: harness.services.random,
        logger: harness.logger,
      );
      final source = CancelTokenSource();
      final events = <AssistantMessageEvent>[];
      final done = Completer<void>();
      openAiCompatibleStreamFunction(_config, services)(
        _model,
        _context,
        cancel: source.token,
      ).listen(events.add, onDone: done.complete);

      body.add(
        utf8.encode(
          'data: {"choices":[{"index":0,"delta":{"content":"Hel"}}]}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.whereType<BlockDeltaEvent>(), hasLength(1));

      source.cancel();
      await done.future.timeout(const Duration(seconds: 1));
      body.add(
        utf8.encode(
          'data: {"choices":[{"index":0,"delta":{"content":"lo"}}]}\n\n',
        ),
      );

      expect(events.whereType<BlockDeltaEvent>(), hasLength(1));
      final error = events.last as ErrorEvent;
      expect(error.error.stopReason, StopReason.aborted);
      expect(error.error.errorClass, LlmErrorClass.aborted);
      expect(error.error.content, [const TextContent('Hel')]);
      expect(
        bodyCancelled,
        isTrue,
        reason: 'the body subscription is cancelled',
      );
      expect(aborted, isTrue, reason: 'the request is aborted (LLM-10)');
    },
  );
}
