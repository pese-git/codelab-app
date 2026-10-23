import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/providers/openai_compatible.dart';
import 'package:test/test.dart';

import '../support/provider_harness.dart';

final _time = DateTime.utc(2026);

ModelRef _model({
  bool images = false,
  bool reasoning = false,
  ReasoningEffort? effort,
  String baseUrl = 'https://api.openai.com/v1',
}) => ModelRef(
  provider: 'p',
  id: 'gpt-4.1-mini',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse(baseUrl),
  contextWindow: 128000,
  maxOutputTokens: 16384,
  supportsImages: images,
  supportsReasoning: reasoning,
  reasoningEffort: effort,
);

ProviderConfig _config({
  String baseUrl = 'https://api.openai.com/v1',
  String? apiKey = 'sk-1',
  Map<String, String> headers = const {},
  String? maxTokensField = 'max_completion_tokens',
  ReasoningFormat? reasoningFormat,
  bool? promptCacheKey,
}) => ProviderConfig(
  name: 'p',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse(baseUrl),
  apiKey: apiKey,
  headers: headers,
  maxTokensField: maxTokensField,
  reasoningFormat: reasoningFormat,
  promptCacheKey: promptCacheKey,
);

final _readSchema = ToolSchema(
  name: 'read',
  description: 'Read a text file.',
  parameters: const {
    'type': 'object',
    'properties': {
      'path': {'type': 'string'},
    },
    'required': ['path'],
  },
);

List<Message> _transcript() => [
  UserMessage(const [TextContent('Fix the failing test')], timestamp: _time),
  AssistantMessage(
    content: [
      const ThinkingContent('hidden', api: ProviderApi.openaiChat),
      ToolCall(
        id: 'call_1',
        name: 'read',
        arguments: const {'path': 'test/a_test.dart'},
      ),
    ],
    model: _model(),
    usage: Usage.zero,
    stopReason: StopReason.toolUse,
    timestamp: _time,
  ),
  ToolResultMessage(
    toolCallId: 'call_1',
    toolName: 'read',
    content: const [TextContent('1| void main() {}')],
    isError: false,
    timestamp: _time,
  ),
];

Future<CapturedRequest> _send(
  LlmContext context, {
  ProviderConfig? config,
  ModelRef? model,
}) async {
  final harness = ProviderHarness(body: readSseFixture('openai/text.sse'));
  await harness.run(
    openAiCompatibleStreamFunction(config ?? _config(), harness.services),
    model ?? _model(),
    context,
  );
  return harness.requests.single;
}

LlmContext _context({
  List<Message>? messages,
  List<ToolSchema> tools = const [],
  String? cacheKey,
  String systemPrompt = 'You are CodeLab, a coding agent...',
}) => LlmContext(
  systemPrompt: systemPrompt,
  messages: messages ?? _transcript(),
  tools: tools,
  cacheKey: cacheKey,
);

void main() {
  test('URL and headers', () async {
    final request = await _send(
      _context(),
      config: _config(
        baseUrl: 'http://localhost:11434/v1/',
        headers: const {'HTTP-Referer': 'https://codelab.dev'},
      ),
    );

    expect(request.request.method, 'POST');
    expect(
      request.request.url.toString(),
      'http://localhost:11434/v1/chat/completions',
    );
    expect(
      request.request.headers,
      containsPair('content-type', startsWith('application/json')),
    );
    expect(
      request.request.headers,
      containsPair('accept', 'text/event-stream'),
    );
    expect(
      request.request.headers,
      containsPair('Authorization', 'Bearer sk-1'),
    );
    expect(
      request.request.headers,
      containsPair('HTTP-Referer', 'https://codelab.dev'),
    );
  });

  test('no key — no authorization header', () async {
    final request = await _send(_context(), config: _config(apiKey: null));

    expect(
      request.request.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
  });

  test('the body of §2.7', () async {
    final request = await _send(_context(tools: [_readSchema]));

    expect(request.json, {
      'model': 'gpt-4.1-mini',
      'messages': [
        {'role': 'system', 'content': 'You are CodeLab, a coding agent...'},
        {'role': 'user', 'content': 'Fix the failing test'},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'read',
                'arguments': '{"path":"test/a_test.dart"}',
              },
            },
          ],
        },
        {
          'role': 'tool',
          'tool_call_id': 'call_1',
          'content': '1| void main() {}',
        },
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'read',
            'description': 'Read a text file.',
            'parameters': {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
              },
              'required': ['path'],
            },
          },
        },
      ],
      'tool_choice': 'auto',
      'stream': true,
      'stream_options': {'include_usage': true},
      'max_completion_tokens': 16384,
    });
  });

  test('without tools there are no tools and tool_choice', () async {
    final json = (await _send(_context())).json;

    expect(json.containsKey('tools'), isFalse);
    expect(json.containsKey('tool_choice'), isFalse);
  });

  test('the max tokens field follows the config', () async {
    final legacy = (await _send(
      _context(),
      config: _config(maxTokensField: 'max_tokens'),
    )).json;
    final none = (await _send(
      _context(),
      config: _config(maxTokensField: null),
    )).json;

    expect(legacy['max_tokens'], 16384);
    expect(legacy.containsKey('max_completion_tokens'), isFalse);
    expect(none.keys, isNot(anyElement(contains('max'))));
  });

  test('an empty system prompt is not sent', () async {
    final json = (await _send(_context(systemPrompt: ''))).json;

    expect((json['messages']! as List).first, containsPair('role', 'user'));
  });

  test(
    'images: data URL for a model with images, a placeholder otherwise',
    () async {
      final messages = [
        UserMessage(const [
          TextContent('What is here?'),
          ImageContent(base64: 'iVBOR', mimeType: 'image/png'),
        ], timestamp: _time),
      ];

      final withImages = (await _send(
        _context(messages: messages),
        model: _model(images: true),
      )).json;
      final without = (await _send(_context(messages: messages))).json;

      expect((withImages['messages']! as List)[1], {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'What is here?'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,iVBOR'},
          },
        ],
      });
      expect((without['messages']! as List)[1], {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'What is here?'},
          {
            'type': 'text',
            'text': '[image omitted: the current model does not accept images]',
          },
        ],
      });
    },
  );

  test(
    'images of a tool result go to a user message after the results',
    () async {
      final messages = [
        ..._transcript().take(2),
        ToolResultMessage(
          toolCallId: 'call_1',
          toolName: 'read',
          content: const [
            TextContent('Image a.png (5 bytes)'),
            ImageContent(base64: 'iVBOR', mimeType: 'image/png'),
          ],
          isError: false,
          timestamp: _time,
        ),
      ];

      final json = (await _send(
        _context(messages: messages),
        model: _model(images: true),
      )).json;

      final sent = json['messages']! as List;
      expect(sent[3], {
        'role': 'tool',
        'tool_call_id': 'call_1',
        'content':
            'Image a.png (5 bytes)\n[image attached in the next message]',
      });
      expect(sent[4], {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Images returned by tool call call_1:'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,iVBOR'},
          },
        ],
      });
    },
  );

  test('a failed assistant message without content is skipped', () async {
    final messages = [
      UserMessage(const [TextContent('hi')], timestamp: _time),
      AssistantMessage(
        content: const [],
        model: _model(),
        usage: Usage.zero,
        stopReason: StopReason.error,
        errorClass: LlmErrorClass.network,
        timestamp: _time,
      ),
      UserMessage(const [TextContent('again')], timestamp: _time),
    ];

    final sent =
        (await _send(_context(messages: messages))).json['messages']! as List;

    expect(sent.map((m) => (m as Map)['role']), ['system', 'user', 'user']);
  });

  group('prompt cache key (LLM-12)', () {
    test('sent to api.openai.com by default', () async {
      final json = (await _send(_context(cacheKey: 'sess-1'))).json;

      expect(json['prompt_cache_key'], 'sess-1');
    });

    test('not sent to another host by default', () async {
      final json = (await _send(
        _context(cacheKey: 'sess-1'),
        config: _config(baseUrl: 'http://localhost:11434/v1'),
      )).json;

      expect(json.containsKey('prompt_cache_key'), isFalse);
    });

    test(
      'sent to another host with the flag; not sent without a key',
      () async {
        final config = _config(
          baseUrl: 'http://localhost:11434/v1',
          promptCacheKey: true,
        );

        expect(
          (await _send(
            _context(cacheKey: 'sess-1'),
            config: config,
          )).json['prompt_cache_key'],
          'sess-1',
        );
        expect(
          (await _send(
            _context(),
            config: config,
          )).json.containsKey('prompt_cache_key'),
          isFalse,
        );
      },
    );
  });

  group('reasoning effort (LLM-15)', () {
    test('openai format', () async {
      final json = (await _send(
        _context(),
        model: _model(reasoning: true, effort: ReasoningEffort.high),
      )).json;

      expect(json['reasoning_effort'], 'high');
      expect(json.containsKey('reasoning'), isFalse);
    });

    test('openrouter format', () async {
      final json = (await _send(
        _context(),
        config: _config(baseUrl: 'https://openrouter.ai/api/v1'),
        model: _model(reasoning: true, effort: ReasoningEffort.low),
      )).json;

      expect(json['reasoning'], {'effort': 'low'});
      expect(json.containsKey('reasoning_effort'), isFalse);
    });

    test('format none and a model without reasoning send nothing', () async {
      final none = (await _send(
        _context(),
        config: _config(reasoningFormat: ReasoningFormat.none),
        model: _model(reasoning: true, effort: ReasoningEffort.medium),
      )).json;
      final noReasoning = (await _send(
        _context(),
        model: _model(effort: ReasoningEffort.medium),
      )).json;

      for (final json in [none, noReasoning]) {
        expect(json.containsKey('reasoning_effort'), isFalse);
        expect(json.containsKey('reasoning'), isFalse);
        expect(json.containsKey('thinking'), isFalse);
      }
    });
  });

  test('the same snapshot gives byte-identical bodies (LLM-11)', () async {
    final a = await _send(_context(tools: [_readSchema], cacheKey: 'sess-1'));
    final b = await _send(_context(tools: [_readSchema], cacheKey: 'sess-1'));

    expect(a.body, b.body);
  });
}
