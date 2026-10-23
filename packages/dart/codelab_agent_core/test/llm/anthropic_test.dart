import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/providers/anthropic.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/provider_harness.dart';

final _time = DateTime.utc(2026);

ProviderConfig _config({
  String? apiKey = 'sk-ant-test',
  List<String> beta = const [],
}) => ProviderConfig(
  name: 'anthropic',
  api: ProviderApi.anthropicMessages,
  baseUrl: Uri.parse('https://api.anthropic.com'),
  apiKey: apiKey,
  anthropicBeta: beta,
);

ModelRef _model({
  bool images = false,
  bool reasoning = false,
  ReasoningEffort? effort,
  int maxOutputTokens = 16384,
  ThinkingMode thinking = ThinkingMode.budget,
}) => ModelRef(
  provider: 'anthropic',
  id: 'claude-sonnet-4-5',
  api: ProviderApi.anthropicMessages,
  baseUrl: Uri.parse('https://api.anthropic.com'),
  contextWindow: 200000,
  maxOutputTokens: maxOutputTokens,
  supportsImages: images,
  supportsReasoning: reasoning,
  reasoningEffort: effort,
  thinkingMode: thinking,
);

final _readSchema = ToolSchema(
  name: 'read',
  description: 'Read a text file...',
  parameters: const {
    'type': 'object',
    'properties': {
      'path': {'type': 'string'},
    },
    'required': ['path'],
  },
);

final _lsSchema = ToolSchema(
  name: 'ls',
  description: 'List a directory.',
  parameters: const {'type': 'object', 'properties': <String, Object?>{}},
);

UserMessage _user(String text) =>
    UserMessage([TextContent(text)], timestamp: _time);

AssistantMessage _assistant(
  List<ContentBlock> content, {
  StopReason stop = StopReason.toolUse,
}) => AssistantMessage(
  content: content,
  model: _model(),
  usage: Usage.zero,
  stopReason: stop,
  timestamp: _time,
);

ToolResultMessage _result(String id, String text, {bool isError = false}) =>
    ToolResultMessage(
      toolCallId: id,
      toolName: 'read',
      content: [TextContent(text)],
      isError: isError,
      timestamp: _time,
    );

LlmContext _context(List<Message> messages, {List<ToolSchema>? tools}) =>
    LlmContext(
      systemPrompt: 'You are CodeLab...',
      messages: messages,
      tools: tools ?? [_readSchema],
    );

Future<List<AssistantMessageEvent>> _play(
  String fixture, {
  Chunking chunking = Chunking.whole,
  ProviderHarness? harness,
}) {
  final h =
      harness ??
      ProviderHarness(
        body: readSseFixture('anthropic/$fixture'),
        chunking: chunking,
      );
  return h.run(
    anthropicStreamFunction(_config(), h.services),
    _model(),
    _context([_user('hi')]),
  );
}

Future<CapturedRequest> _send(
  LlmContext context, {
  ModelRef? model,
  ProviderConfig? config,
}) async {
  final harness = ProviderHarness(body: readSseFixture('anthropic/text.sse'));
  await harness.run(
    anthropicStreamFunction(config ?? _config(), harness.services),
    model ?? _model(),
    context,
  );
  return harness.requests.single;
}

AssistantMessage _final(List<AssistantMessageEvent> events) =>
    switch (events.last) {
      DoneEvent(:final message) => message,
      ErrorEvent(:final error) => error,
      final other => throw StateError('not terminal: $other'),
    };

int _cacheMarks(Object? node) => switch (node) {
  final Map<String, Object?> map =>
    (map.containsKey('cache_control') ? 1 : 0) +
        map.values.fold(0, (sum, v) => sum + _cacheMarks(v)),
  final List<Object?> list => list.fold(0, (sum, v) => sum + _cacheMarks(v)),
  _ => 0,
};

void main() {
  group('stream parsing', () {
    for (final chunking in Chunking.values) {
      test('text with ping and an unknown event (${chunking.name})', () async {
        final events = await _play('text.sse', chunking: chunking);

        expect(events.first, isA<StartEvent>());
        final message = _final(events);
        expect(message.content, [const TextContent('Hello, world')]);
        expect(message.stopReason, StopReason.stop);
        expect(message.rawStopReason, 'end_turn');
        expect(message.usage.input, 1200);
        expect(message.usage.cacheRead, 800);
        expect(message.usage.cacheWrite, 300);
        expect(
          message.usage.output,
          15,
          reason: 'message_delta replaces output',
        );
      });
    }

    test('initial text of content_block_start', () async {
      expect(_final(await _play('text_initial.sse')).content, [
        const TextContent('Hi there'),
      ]);
    });

    test('thinking with a signature, then tool_use', () async {
      final events = await _play(
        'thinking_tool_use.sse',
        chunking: Chunking.byChar,
      );

      final message = _final(events);
      expect(message.content, [
        const ThinkingContent(
          'Need to look at the test.',
          signature: 'sig-fixture-1',
          api: ProviderApi.anthropicMessages,
        ),
        ToolCall(
          id: 'toolu_fixture1',
          name: 'read',
          arguments: const {'path': 'a.txt'},
        ),
      ]);
      expect(message.stopReason, StopReason.toolUse);
      expect(
        events.whereType<BlockDeltaEvent>().map((e) => e.delta),
        isNot(contains('sig-fixture-1')),
        reason: 'signature_delta changes the snapshot without an event',
      );
    });

    test('redacted thinking', () async {
      expect(_final(await _play('redacted_thinking.sse')).content, [
        const ThinkingContent(
          'opaque-fixture-data',
          redacted: true,
          api: ProviderApi.anthropicMessages,
        ),
        const TextContent('ok'),
      ]);
    });

    test('stop reasons of §2.8', () async {
      expect(
        _final(await _play('max_tokens.sse')).stopReason,
        StopReason.length,
      );
      expect(
        _final(await _play('refusal.sse')).errorClass,
        LlmErrorClass.terminalFinish,
      );
      expect(
        _final(await _play('context_window_exceeded.sse')).errorClass,
        LlmErrorClass.overflow,
      );
      final harness = ProviderHarness(
        body: readSseFixture('anthropic/unknown_stop_reason.sse'),
      );
      expect(
        _final(await _play('', harness: harness)).errorClass,
        LlmErrorClass.unknown,
      );
      expect(
        harness.logger.eventsOf('llm.finish_reason.unknown'),
        hasLength(1),
      );
    });

    test('an error event: overloaded_error is server', () async {
      final message = _final(await _play('overloaded_error.sse'));

      expect(message.errorClass, LlmErrorClass.server);
      expect(message.errorMessage, contains('Overloaded'));
      expect(message.content, [const TextContent('Par')]);
    });

    test('a body without message_stop is a network error', () async {
      expect(
        _final(await _play('no_message_stop.sse')).errorClass,
        LlmErrorClass.network,
      );
    });

    test('HTTP 529 overloaded', () async {
      final harness = ProviderHarness(
        status: 529,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'type': 'error',
          'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
        }),
      );

      final events = await _play('', harness: harness);

      expect(events.single, isA<ErrorEvent>());
      expect(_final(events).errorClass, LlmErrorClass.server);
      expect(_final(events).errorMessage, 'anthropic 529: Overloaded');
    });

    test('cancel mid-stream yields ErrorEvent(aborted)', () async {
      final body = StreamController<List<int>>();
      var bodyCancelled = false;
      body.onCancel = () => bodyCancelled = true;
      final client = MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
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
      anthropicStreamFunction(_config(), services)(
        _model(),
        _context([_user('hi')]),
        cancel: source.token,
      ).listen(events.add, onDone: done.complete);

      body.add(utf8.encode(readSseFixture('anthropic/no_message_stop.sse')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      source.cancel();
      await done.future.timeout(const Duration(seconds: 1));

      expect(_final(events).stopReason, StopReason.aborted);
      expect(bodyCancelled, isTrue);
    });
  });

  group('request', () {
    test('URL and headers', () async {
      final request = await _send(
        _context([_user('hi')]),
        config: _config(beta: ['b1', 'b2']),
      );

      expect(
        request.request.url.toString(),
        'https://api.anthropic.com/v1/messages',
      );
      expect(request.request.headers, containsPair('x-api-key', 'sk-ant-test'));
      expect(
        request.request.headers,
        containsPair('anthropic-version', '2023-06-01'),
      );
      expect(request.request.headers, containsPair('anthropic-beta', 'b1,b2'));
      expect(
        request.request.headers,
        containsPair('accept', 'text/event-stream'),
      );
    });

    test('the body of §2.8', () async {
      final request = await _send(
        _context([
          _user('Fix the failing test'),
          _assistant([
            const ThinkingContent(
              'Need to look at the test.',
              signature: 'EqQBCkYI',
              api: ProviderApi.anthropicMessages,
            ),
            ToolCall(
              id: 'call_1',
              name: 'read',
              arguments: const {'path': 'test/a_test.dart'},
            ),
          ]),
          _result('call_1', '1| void main() {}'),
        ]),
        model: _model(reasoning: true, effort: ReasoningEffort.medium),
      );

      expect(request.json, {
        'model': 'claude-sonnet-4-5',
        'max_tokens': 16384,
        'system': [
          {
            'type': 'text',
            'text': 'You are CodeLab...',
            'cache_control': {'type': 'ephemeral'},
          },
        ],
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Fix the failing test'},
            ],
          },
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'thinking',
                'thinking': 'Need to look at the test.',
                'signature': 'EqQBCkYI',
              },
              {
                'type': 'tool_use',
                'id': 'call_1',
                'name': 'read',
                'input': {'path': 'test/a_test.dart'},
              },
            ],
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'call_1',
                'content': [
                  {'type': 'text', 'text': '1| void main() {}'},
                ],
                'is_error': false,
                'cache_control': {'type': 'ephemeral'},
              },
            ],
          },
        ],
        'tools': [
          {
            'name': 'read',
            'description': 'Read a text file...',
            'input_schema': {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
              },
              'required': ['path'],
            },
            'cache_control': {'type': 'ephemeral'},
          },
        ],
        'tool_choice': {'type': 'auto'},
        'stream': true,
        'thinking': {'type': 'enabled', 'budget_tokens': 8192},
      });
    });

    test('a series of results is one user message; roles merge', () async {
      final json = (await _send(
        _context([
          _user('a'),
          _user('b'),
          _assistant([
            ToolCall(id: 'call_1', name: 'read', arguments: const {}),
            ToolCall(id: 'call_2', name: 'read', arguments: const {}),
          ]),
          _result('call_1', 'one'),
          _result('call_2', 'two', isError: true),
          _user('next'),
        ]),
      )).json;

      final messages = json['messages']! as List;
      expect(messages.map((m) => (m as Map)['role']), [
        'user',
        'assistant',
        'user',
      ]);
      final first = (messages[0] as Map)['content'] as List;
      expect(first.map((b) => (b as Map)['text']), ['a', 'b']);
      final results = (messages[2] as Map)['content'] as List;
      expect(results.map((b) => (b as Map)['type']), [
        'tool_result',
        'tool_result',
        'text',
      ]);
      expect((results[1] as Map)['is_error'], isTrue);
    });

    test('tool call ids are normalized the same way on both sides', () async {
      final json = (await _send(
        _context([
          _user('a'),
          _assistant([
            ToolCall(id: 'call:1/x.y', name: 'read', arguments: const {}),
          ]),
          _result('call:1/x.y', 'one'),
        ]),
      )).json;

      final messages = json['messages']! as List;
      final use = ((messages[1] as Map)['content'] as List).single as Map;
      final result = ((messages[2] as Map)['content'] as List).single as Map;
      expect(use['id'], 'call_1_x_y');
      expect(result['tool_use_id'], use['id']);
    });

    test('a long id is cut to 64 characters', () async {
      final id = 'x' * 80;
      final json = (await _send(
        _context([
          _user('a'),
          _assistant([ToolCall(id: id, name: 'read', arguments: const {})]),
          _result(id, 'one'),
        ]),
      )).json;

      final use =
          (((json['messages']! as List)[1] as Map)['content'] as List).single
              as Map;
      expect((use['id']! as String).length, 64);
    });

    test(
      'signatures go only to their own api; empty texts are omitted',
      () async {
        final json = (await _send(
          _context([
            UserMessage(const [
              TextContent(''),
              TextContent('a'),
            ], timestamp: _time),
            _assistant([
              const ThinkingContent(
                'foreign',
                signature: 's',
                api: ProviderApi.openaiChat,
              ),
              const ThinkingContent(
                'unsigned',
                api: ProviderApi.anthropicMessages,
              ),
              const ThinkingContent(
                'opaque',
                redacted: true,
                api: ProviderApi.anthropicMessages,
              ),
              const TextContent(''),
              const TextContent('answer'),
            ], stop: StopReason.stop),
            _user('b'),
          ]),
        )).json;

        final messages = json['messages']! as List;
        expect((messages[0] as Map)['content'], [
          {'type': 'text', 'text': 'a'},
        ]);
        expect((messages[1] as Map)['content'], [
          {'type': 'redacted_thinking', 'data': 'opaque'},
          {'type': 'text', 'text': 'answer'},
        ]);
      },
    );

    test('images and the placeholder', () async {
      final messages = [
        UserMessage(const [
          TextContent('see'),
          ImageContent(base64: 'iVBOR', mimeType: 'image/png'),
        ], timestamp: _time),
      ];

      final withImages = (await _send(
        _context(messages),
        model: _model(images: true),
      )).json;
      final without = (await _send(_context(messages))).json;

      final a =
          ((withImages['messages']! as List).single as Map)['content'] as List;
      final b =
          ((without['messages']! as List).single as Map)['content'] as List;
      expect(a[1], {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/png',
          'data': 'iVBOR',
        },
        'cache_control': {'type': 'ephemeral'},
      });
      expect(b[1], {
        'type': 'text',
        'text': '[image omitted: the current model does not accept images]',
        'cache_control': {'type': 'ephemeral'},
      });
    });

    test(
      'three cache marks; system and tools are byte-identical (LLM-11)',
      () async {
        final turns = [
          [_user('Fix the test')],
          [
            _user('Fix the test'),
            _assistant([
              ToolCall(
                id: 'call_1',
                name: 'read',
                arguments: const {'path': 'a'},
              ),
            ]),
            _result('call_1', '1| a'),
          ],
          [
            _user('Fix the test'),
            _assistant([
              ToolCall(
                id: 'call_1',
                name: 'read',
                arguments: const {'path': 'a'},
              ),
            ]),
            _result('call_1', '1| a'),
            _assistant([
              ToolCall(id: 'call_2', name: 'ls', arguments: const {}),
            ]),
            _result('call_2', 'a\nb'),
          ],
        ];

        final bodies = [
          for (final messages in turns)
            (await _send(
              _context(messages, tools: [_readSchema, _lsSchema]),
            )).json,
        ];

        for (final body in bodies) {
          expect(_cacheMarks(body), 3);
          final last =
              ((body['messages']! as List).last as Map)['content'] as List;
          expect((last.last as Map).containsKey('cache_control'), isTrue);
          expect(
            (body['tools']! as List).last,
            containsPair('cache_control', {'type': 'ephemeral'}),
          );
        }
        expect(
          jsonEncode(bodies[1]['system']),
          jsonEncode(bodies[0]['system']),
        );
        expect(jsonEncode(bodies[2]['tools']), jsonEncode(bodies[0]['tools']));
      },
    );

    test('thinking budget by level, limited by max_tokens − 1024', () async {
      Future<Object?> thinking(ReasoningEffort effort, int maxTokens) async =>
          (await _send(
            _context([_user('a')]),
            model: _model(
              reasoning: true,
              effort: effort,
              maxOutputTokens: maxTokens,
            ),
          )).json['thinking'];

      expect(await thinking(ReasoningEffort.low, 16384), {
        'type': 'enabled',
        'budget_tokens': 2048,
      });
      expect(await thinking(ReasoningEffort.high, 32000), {
        'type': 'enabled',
        'budget_tokens': 16384,
      });
      expect(await thinking(ReasoningEffort.high, 4096), {
        'type': 'enabled',
        'budget_tokens': 3072,
      });
      expect(
        await thinking(ReasoningEffort.medium, 1800),
        isNull,
        reason: 'B < 1024',
      );
    });

    test('adaptive thinking: effort in output_config, summarized display, '
        'no budget', () async {
      Future<Map<String, Object?>> body(
        ReasoningEffort effort,
        int maxTokens,
      ) async => (await _send(
        _context([_user('a')]),
        model: _model(
          reasoning: true,
          effort: effort,
          maxOutputTokens: maxTokens,
          thinking: ThinkingMode.adaptive,
        ),
      )).json;

      for (final effort in ReasoningEffort.values) {
        final json = await body(effort, 128000);
        expect(json['thinking'], {'type': 'adaptive', 'display': 'summarized'});
        expect(json['output_config'], {'effort': effort.name});
        expect(json['max_tokens'], 128000);
      }
      final small = await body(ReasoningEffort.high, 1800);
      expect(small['thinking'], {'type': 'adaptive', 'display': 'summarized'});
      expect(jsonEncode(small), isNot(contains('budget_tokens')));
    });

    test('adaptive model without effort or reasoning: neither thinking nor '
        'output_config (LLM-15)', () async {
      for (final model in [
        _model(reasoning: true, thinking: ThinkingMode.adaptive),
        _model(effort: ReasoningEffort.high, thinking: ThinkingMode.adaptive),
      ]) {
        final json = (await _send(_context([_user('a')]), model: model)).json;
        expect(json.containsKey('thinking'), isFalse);
        expect(json.containsKey('output_config'), isFalse);
      }
    });

    test('budget thinking sends no output_config', () async {
      final json = (await _send(
        _context([_user('a')]),
        model: _model(reasoning: true, effort: ReasoningEffort.low),
      )).json;
      expect(json.containsKey('output_config'), isFalse);
    });

    test('a model without reasoning gets no thinking (LLM-15)', () async {
      final json = (await _send(
        _context([_user('a')]),
        model: _model(effort: ReasoningEffort.high),
      )).json;

      expect(json.containsKey('thinking'), isFalse);
      expect(json.containsKey('reasoning_effort'), isFalse);
      expect(json.containsKey('reasoning'), isFalse);
    });

    test('without tools there are no tools and tool_choice', () async {
      final json = (await _send(_context([_user('a')], tools: const []))).json;

      expect(json.containsKey('tools'), isFalse);
      expect(json.containsKey('tool_choice'), isFalse);
    });
  });
}
