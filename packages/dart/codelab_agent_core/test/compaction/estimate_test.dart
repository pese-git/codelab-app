import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';
import 'package:test/test.dart';

import '../support/models.dart';

/// agent-compaction «Оценка токенов с якорем на usage» (задача 7.1,
/// `agent-core-architecture` §9.3).
void main() {
  final at = DateTime.utc(2026);

  UserMessage user(String text) =>
      UserMessage([TextContent(text)], timestamp: at);

  AssistantMessage assistant(
    List<ContentBlock> content, {
    Usage usage = Usage.zero,
  }) => AssistantMessage(
    content: content,
    model: testModel,
    usage: usage,
    stopReason: StopReason.stop,
    timestamp: at,
  );

  ToolResultMessage result(String name, String text) => ToolResultMessage(
    toolCallId: 'c1',
    toolName: name,
    content: [TextContent(text)],
    isError: false,
    timestamp: at,
  );

  group('a block costs ceil(chars / 4) plus 4 per message', () {
    final cases = <(String, Message, int)>[
      ('text', user('x' * 10), 3 + 4),
      ('thinking', assistant([ThinkingContent('y' * 9)]), 3 + 4),
      (
        'redacted thinking — by the signature',
        assistant([
          ThinkingContent('opaque', signature: 's' * 12, redacted: true),
        ]),
        3 + 4,
      ),
      (
        'tool call — name and JSON arguments',
        assistant([
          ToolCall(id: 'c1', name: 'read', arguments: const {'path': 'a.txt'}),
        ]),
        ((4 + jsonEncode({'path': 'a.txt'}).length) / 4).ceil() + 4,
      ),
      (
        'image — a constant',
        UserMessage([
          ImageContent(base64: 'A' * 100000, mimeType: 'image/png'),
        ], timestamp: at),
        1200 + 4,
      ),
      ('tool result — plus the tool name', result('read', 'z' * 8), 2 + 1 + 4),
    ];
    for (final (name, message, tokens) in cases) {
      test(name, () => expect(estimateMessageTokens(message), tokens));
    }
  });

  test('the system prompt and tool schemas count by their text', () {
    final tools = [
      ToolSchema(name: 'read', description: 'Read a file', parameters: {}),
    ];
    final schemas = jsonEncode([
      for (final t in tools)
        {
          'name': t.name,
          'description': t.description,
          'parameters': t.parameters,
        },
    ]);

    expect(
      estimateTokens(const [], systemPrompt: 'p' * 40, tools: tools),
      10 + (schemas.length / 4).ceil(),
    );
  });

  test('the example of §9.3 anchors on usage: 53 659', () {
    final messages = [
      user('hello'),
      assistant([
        const TextContent('reading'),
      ], usage: const Usage(input: 41000, cacheRead: 9000, output: 600)),
      result('read', 'r' * 12000),
      user('u' * 200),
    ];

    expect(
      estimateContextTokens(messages, systemPrompt: 'system', tools: const []),
      53659,
    );
  });

  test('a zeroed usage is not an anchor', () {
    final messages = [
      user('a' * 40),
      assistant([const TextContent('b')]),
      user('c' * 8),
    ];

    expect(
      estimateContextTokens(messages, systemPrompt: 'p' * 4, tools: const []),
      1 + (10 + 4) + (1 + 4) + (2 + 4),
    );
  });

  test('the latest non-zero usage is the anchor', () {
    final messages = [
      assistant([
        const TextContent('old'),
      ], usage: const Usage(input: 100, output: 10)),
      assistant([
        const TextContent('new'),
      ], usage: const Usage(input: 500, cacheWrite: 20, output: 5)),
    ];

    expect(
      estimateContextTokens(messages, systemPrompt: '', tools: const []),
      525,
    );
  });

  group('effectiveContextWindow', () {
    test('is the model window without a cap', () {
      expect(effectiveContextWindow(testModel), testModel.contextWindow);
    });

    test('is min(window, cap)', () {
      final big = ModelRef(
        provider: 'test',
        id: 'big',
        api: ProviderApi.openaiChat,
        baseUrl: Uri.parse('http://localhost:8080/v1'),
        contextWindow: 128000,
        maxOutputTokens: 4096,
      );
      expect(effectiveContextWindow(big, cap: 50000), 50000);
      expect(effectiveContextWindow(big, cap: 500000), 128000);
    });
  });
}
