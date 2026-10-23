import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

final _model = ModelRef(
  provider: 'anthropic',
  id: 'claude-sonnet-4-5',
  api: ProviderApi.anthropicMessages,
  baseUrl: Uri.parse('https://api.anthropic.com'),
  contextWindow: 200000,
  maxOutputTokens: 16384,
  cost: const ModelCost(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75),
  supportsImages: true,
  supportsReasoning: true,
  reasoningEffort: ReasoningEffort.medium,
);

ModelRef _resolve(String provider, String id) {
  expect((provider, id), ('anthropic', 'claude-sonnet-4-5'));
  return _model;
}

final _time = DateTime.utc(2026, 10, 23, 8, 0, 4);

List<Message> _transcript() => [
  UserMessage(const [
    TextContent('Fix the failing test'),
    ImageContent(base64: 'iVBORw0K', mimeType: 'image/png'),
  ], timestamp: _time),
  AssistantMessage(
    content: [
      const ThinkingContent(
        'Need to look at the test.',
        signature: 'EqQBCkYI',
        api: ProviderApi.anthropicMessages,
      ),
      const TextContent('Let me check'),
      ToolCall(id: 'call_1', name: 'read', arguments: {'path': 'a.txt'}),
    ],
    model: _model,
    usage: const Usage(
      input: 900,
      output: 40,
      cacheRead: 512,
      reasoning: 12,
      cost: UsageCost(input: 0.0027, output: 0.0006),
    ),
    stopReason: StopReason.toolUse,
    rawStopReason: 'tool_use',
    timestamp: _time,
  ),
  ToolResultMessage(
    toolCallId: 'call_1',
    toolName: 'read',
    content: const [TextContent('1| hello')],
    isError: false,
    timestamp: _time,
  ),
  AssistantMessage(
    content: const [ThinkingContent('opaque', redacted: true)],
    model: _model,
    usage: Usage.zero,
    stopReason: StopReason.error,
    errorMessage: 'anthropic 529: overloaded',
    errorClass: LlmErrorClass.server,
    timestamp: _time,
  ),
];

Object? _roundTrip(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  group('canonical JSON', () {
    test('the transcript survives serialization', () {
      final transcript = _transcript();

      final restored = [
        for (final message in transcript)
          Message.fromJson(
            _roundTrip(message.toJson())! as Map<String, Object?>,
            resolveModel: _resolve,
          ),
      ];

      expect(restored, transcript);
    });

    test('forms follow the table of §2.2', () {
      final [user, assistant, result, _] = [
        for (final message in _transcript()) message.toJson(),
      ];

      expect(user, {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Fix the failing test'},
          {'type': 'image', 'data': 'iVBORw0K', 'mimeType': 'image/png'},
        ],
        'timestamp': '2026-10-23T08:00:04.000Z',
      });
      expect(assistant['model'], {
        'provider': 'anthropic',
        'id': 'claude-sonnet-4-5',
      });
      expect(assistant['content'], [
        {
          'type': 'thinking',
          'thinking': 'Need to look at the test.',
          'signature': 'EqQBCkYI',
          'api': 'anthropicMessages',
        },
        {'type': 'text', 'text': 'Let me check'},
        {
          'type': 'toolCall',
          'id': 'call_1',
          'name': 'read',
          'arguments': {'path': 'a.txt'},
        },
      ]);
      expect(assistant['stopReason'], 'toolUse');
      expect(assistant['rawStopReason'], 'tool_use');
      expect(assistant['usage'], {
        'input': 900,
        'output': 40,
        'cacheRead': 512,
        'cacheWrite': 0,
        'reasoning': 12,
        'cost': {
          'input': 0.0027,
          'output': 0.0006,
          'cacheRead': 0.0,
          'cacheWrite': 0.0,
        },
      });
      expect(result, {
        'role': 'toolResult',
        'toolCallId': 'call_1',
        'toolName': 'read',
        'content': [
          {'type': 'text', 'text': '1| hello'},
        ],
        'isError': false,
        'timestamp': '2026-10-23T08:00:04.000Z',
      });
    });

    test('null fields are omitted', () {
      final json = jsonEncode([
        for (final message in _transcript()) message.toJson(),
      ]);

      expect(json, isNot(contains('null')));
      expect(json, isNot(contains('"redacted":false')));
    });

    test('unknown fields are ignored on read', () {
      final json = {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'hi', 'cache': true},
        ],
        'timestamp': '2026-10-23T08:00:04.000Z',
        'origin': 'steer',
      };

      final message = Message.fromJson(json, resolveModel: _resolve);

      expect(message, UserMessage(const [TextContent('hi')], timestamp: _time));
    });

    test('missing optional fields take defaults', () {
      final message = Message.fromJson({
        'role': 'assistant',
        'content': <Object?>[],
        'model': {'provider': 'anthropic', 'id': 'claude-sonnet-4-5'},
        'stopReason': 'stop',
        'timestamp': '2026-10-23T08:00:04.000Z',
      }, resolveModel: _resolve);

      expect(message, isA<AssistantMessage>());
      final assistant = message as AssistantMessage;
      expect(assistant.usage, Usage.zero);
      expect(assistant.errorClass, isNull);
    });

    test('an unknown block type is a format error', () {
      expect(
        () => ContentBlock.fromJson({'type': 'audio'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('lists inside messages are unmodifiable', () {
    final content = [const TextContent('hi')];
    final message = UserMessage(content, timestamp: _time);
    content.add(const TextContent('later'));

    expect(message.content, hasLength(1));
    expect(
      () => message.content.add(const TextContent('x')),
      throwsUnsupportedError,
    );
  });

  test('AssistantMessage.toolCalls', () {
    final assistant = _transcript()[1] as AssistantMessage;

    expect(assistant.toolCalls.map((c) => c.id), ['call_1']);
  });

  group('Usage', () {
    test('adds usage and cost', () {
      const a = Usage(
        input: 1,
        output: 2,
        cacheRead: 3,
        cacheWrite: 4,
        cost: UsageCost(input: 0.1, output: 0.2),
      );
      const b = Usage(input: 10, output: 20, reasoning: 5);

      final sum = a + b;

      expect(sum.input, 11);
      expect(sum.output, 22);
      expect(sum.cacheRead, 3);
      expect(sum.cacheWrite, 4);
      expect(sum.reasoning, 5);
      expect(sum.total, 40);
      expect(sum.cost.total, closeTo(0.3, 1e-12));
      expect((Usage.zero + Usage.zero).reasoning, isNull);
    });
  });
}
