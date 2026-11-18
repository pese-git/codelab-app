import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart' as j;
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

  /// agent-compaction «Согласованная оценка после сжатия» (design.md change
  /// `fix-compaction-estimate-and-no-gain`, D1): `before + rawAfter −
  /// rawBefore`, не ниже 0.
  group('estimateAfterCompaction', () {
    final cases = <(String, int, int, int, int)>[
      // (имя, before, rawBefore, rawAfter, ожидание)
      (
        'anchor below the heuristic: the difference is applied',
        3043,
        4450,
        3567,
        2160,
      ),
      (
        'no anchor (before == rawBefore): equals rawAfter',
        4450,
        4450,
        3567,
        3567,
      ),
      ('no gain: the estimate does not fall', 3000, 4000, 4500, 3500),
      ('lower bound: never negative', 100, 4000, 500, 0),
    ];
    for (final (name, before, rawBefore, rawAfter, expected) in cases) {
      test(name, () {
        expect(
          estimateAfterCompaction(
            before: before,
            rawBefore: rawBefore,
            rawAfter: rawAfter,
          ),
          expected,
        );
      });
    }
  });

  /// agent-compaction «Обнулённый usage без якоря сжатия», «Обнулённый usage
  /// после сжатия», «Первый ответ с usage снимает якорь сжатия», «Ответ без
  /// usage не снимает якорь сжатия» (design.md change
  /// `anchor-context-estimate-after-compaction`, D1, D2): третья ветка
  /// оценки — смещение `tokens − raw`, зафиксированное при сжатии.
  group('estimateContextTokens with a compaction anchor (D1, D2)', () {
    // Хвост после сжатия: одно сообщение пользователя, ceil(40/4)+4 = 14.
    final tail = user('t' * 40);
    const prompt = 'p';
    // Эвристика контекста «промпт + хвост»: 1 + 14.
    const h = 1 + 14;

    int estimate(List<Message> messages, CompactionAnchor? anchor) =>
        estimateContextTokens(
          messages,
          systemPrompt: prompt,
          tools: const [],
          compaction: anchor,
        );

    final cases = <(String, CompactionAnchor?, int)>[
      ('no anchor: the plain heuristic', null, h),
      (
        'the offset is applied: tokens + H − raw',
        (tokens: 5000, raw: 4000),
        5000 + h - 4000,
      ),
      (
        'raw below the heuristic: the estimate grows over tokens',
        (tokens: 3000, raw: 1),
        3000 + h - 1,
      ),
      (
        'right after the compaction (H == raw) the estimate is tokens',
        (tokens: 3000, raw: h),
        3000,
      ),
      ('lower bound: never negative', (tokens: 100, raw: 4000), 0),
    ];
    for (final (name, anchor, expected) in cases) {
      test(name, () => expect(estimate([tail], anchor), expected));
    }

    test('the usage anchor in the messages wins over the compaction anchor '
        '(D2)', () {
      final messages = [
        tail,
        assistant([
          const TextContent('reply'),
        ], usage: const Usage(input: 500, output: 7)),
      ];

      expect(estimate(messages, (tokens: 3000, raw: 1)), 507);
    });

    test('a reply with output only does not drop the compaction anchor, its '
        'text is in the tail (D2)', () {
      final reply = assistant([
        TextContent('r' * 8),
      ], usage: const Usage(output: 50));

      expect(
        estimate([tail, reply], (tokens: 3000, raw: 1)),
        3000 + (1 + 14 + (2 + 4)) - 1,
      );
    });

    test('a reply with a zero usage does not drop the compaction anchor '
        '(D2)', () {
      final reply = assistant([TextContent('r' * 8)]);

      expect(
        estimate([tail, reply], (tokens: 3000, raw: 1)),
        3000 + (1 + 14 + (2 + 4)) - 1,
      );
    });
  });

  /// `compactionAnchorOf` (D1, D6): якорь из проекции активной ветки.
  group('compactionAnchorOf (D1, D6)', () {
    const sid = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
    const prompt = 'system prompt';

    LlmContextProjection project(List<String> lines) => buildLlmContext(
      parseSessionLines(
        j.journal([j.header(id: sid.value), ...lines]),
        id: sid,
      ).snapshot,
    );

    List<String> chain({int tokensAfter = 700}) => [
      j.user('u1', null, text: 'old request'),
      j.answer('a1', 'u1'),
      j.user('u2', 'a1', text: 'kept request'),
      j.answer('a2', 'u2'),
      j.compaction('k1', 'a2', firstKept: 'u2', tokensAfter: tokensAfter),
      j.user('u3', 'k1', text: 'tail ${'t' * 400}'),
    ];

    test('no compaction: null', () {
      final p = project([j.user('u1', null), j.answer('a1', 'u1')]);

      expect(
        compactionAnchorOf(p, systemPrompt: prompt, tools: const []),
        isNull,
      );
    });

    test('tokens is tokensAfter of the last compaction, raw is H of the '
        'prompt, the schemas and the covered messages only', () {
      final p = project(chain());
      final tools = [
        ToolSchema(name: 'read', description: 'Read a file', parameters: {}),
      ];

      final anchor = compactionAnchorOf(p, systemPrompt: prompt, tools: tools);

      // Покрыто: резюме + u2 + a2; хвост u3 в raw не входит.
      expect(p.compactionCovered, 3);
      expect(anchor, isNotNull);
      expect(anchor!.tokens, 700);
      expect(
        anchor.raw,
        estimateTokens(
          p.messages.take(3).toList(),
          systemPrompt: prompt,
          tools: tools,
        ),
      );
    });

    for (final tokensAfter in [0, -5]) {
      test('tokensAfter $tokensAfter is not an anchor: null (D6)', () {
        final p = project(chain(tokensAfter: tokensAfter));

        expect(
          compactionAnchorOf(p, systemPrompt: prompt, tools: const []),
          isNull,
        );
      });
    }
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
