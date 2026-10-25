import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/summarizer.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'region.dart';

/// agent-compaction «Генерация резюме» (задача 8.3, `agent-core-
/// architecture` §9.7; CMP-4, CMP-7, CMP-9).
void main() {
  const sid = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0A');
  const sections = [
    '## Open user requests',
    '## Goal',
    '## Constraints and preferences',
    '## Progress',
    '### Done',
    '### In progress',
    '### Blocked',
    '## Key decisions',
    '## Next steps',
    '## Critical context',
  ];

  ScriptedStreamFunction model(List<Map<String, Object?>> steps) =>
      ScriptedStreamFunction.fromJson({'steps': steps});

  Map<String, Object?> reply(String text) => {
    'reply': [
      {'text': text},
    ],
  };

  Summarizer summarizerOf(ScriptedStreamFunction m) =>
      modelSummarizer(stream: m.call, model: testModel, sessionId: sid);

  String requestText(ScriptedStreamFunction m, [int i = 0]) =>
      ((m.requests[i].messages.single as UserMessage).content.single
              as TextContent)
          .text;

  List<MessageRecord> messages(RegionBuilder r) =>
      r.records.whereType<MessageRecord>().toList();

  group('serializeRegion', () {
    test('headers for every kind of message', () {
      final r = RegionBuilder()
        ..user(6, fill: 'q')
        ..nudge(5)
        ..call('c1', 'read')
        ..result('c1', 'read', 7)
        ..assistant(5);

      final text = serializeRegion(messages(r));

      expect(text, contains('[user]\nqqqqqqqq'));
      expect(text, contains('[notice]\nnnnn'));
      expect(text, contains('[tool call read]\n{"path":"a.txt"}'));
      expect(text, contains('[tool result read]\noooo'));
      expect(text, contains('[assistant]\naaaa'));
      expect(
        text.indexOf('[user]') < text.indexOf('[notice]') &&
            text.indexOf('[notice]') < text.indexOf('[tool call read]'),
        isTrue,
      );
    });

    test('arguments are canonical JSON: keys sorted at every level', () {
      final at = DateTime.utc(2026);
      final record = MessageRecord(
        id: 'aaaaaaaa',
        parentId: null,
        timestamp: at,
        message: AssistantMessage(
          content: [
            ToolCall(
              id: 'c1',
              name: 'edit',
              arguments: const {
                'path': 'a',
                'edits': [
                  {'z': 1, 'a': 2},
                ],
              },
            ),
          ],
          model: testModel,
          usage: Usage.zero,
          stopReason: StopReason.toolUse,
          timestamp: at,
        ),
      );

      expect(
        serializeRegion([record]),
        contains('{"edits":[{"a":2,"z":1}],"path":"a"}'),
      );
    });

    test('an error result is marked and a long result is shortened', () {
      final at = DateTime.utc(2026);
      final long = '${'h' * 2000}${'m' * 1000}${'t' * 2000}';
      final record = MessageRecord(
        id: 'aaaaaaaa',
        parentId: null,
        timestamp: at,
        message: ToolResultMessage(
          toolCallId: 'c1',
          toolName: 'exec',
          content: [TextContent(long)],
          isError: true,
          timestamp: at,
        ),
      );

      final text = serializeRegion([record]);

      expect(text, contains('[tool result exec, error]'));
      expect(text, contains('[… 2000 characters omitted …]'));
      expect(text, contains('h' * 1500));
      expect(text, isNot(contains('h' * 1501)));
      expect(text, contains('t' * 1500));
      expect(text, isNot(contains('m')));
    });
  });

  test('the first summary: no tools, the summary cacheKey, sections', () async {
    final m = model([reply('## Open user requests\n- fix the build')]);
    final r = RegionBuilder()
      ..user(10)
      ..assistant(10);

    final summary = await summarizerOf(m)(
      SummaryRequest(
        region: messages(r),
        fileOps: const FileOps(read: ['lib/a.dart'], modified: ['lib/b.dart']),
      ),
      CancelToken.none,
    );

    expect(summary, '## Open user requests\n- fix the build');
    final request = m.requests.single;
    expect(request.tools, isEmpty);
    expect(request.cacheKey, '${sid.value}:summary');
    expect(request.systemPrompt, isNotEmpty);
    final text = requestText(m);
    for (final header in sections) {
      expect(text, contains(header), reason: header);
    }
    expect(text, contains('Files read: lib/a.dart'));
    expect(text, contains('Files modified: lib/b.dart'));
    expect(text, contains('<transcript>'));
    expect(text, isNot(contains('<previous-summary>')));
    expect(text, isNot(contains('<focus>')));
  });

  test('empty file lists are "none"', () async {
    final m = model([reply('ok')]);
    final r = RegionBuilder()..user(10);

    await summarizerOf(m)(
      SummaryRequest(region: messages(r)),
      CancelToken.none,
    );

    expect(requestText(m), contains('Files read: none'));
    expect(requestText(m), contains('Files modified: none'));
  });

  test('the next summary updates the previous one (CMP-9)', () async {
    final m = model([reply('updated')]);
    final r = RegionBuilder()..user(10);

    await summarizerOf(m)(
      SummaryRequest(
        region: messages(r),
        previousSummary: '## Open user requests\n- rename greet() to hello()',
      ),
      CancelToken.none,
    );

    final text = requestText(m);
    expect(text, contains('<previous-summary>'));
    expect(text, contains('- rename greet() to hello()'));
    expect(text, contains('## Open user requests'));
  });

  test('focus adds the <focus> block', () async {
    final m = model([reply('ok')]);
    final r = RegionBuilder()..user(10);

    await summarizerOf(m)(
      SummaryRequest(region: messages(r), focus: 'API changes'),
      CancelToken.none,
    );

    expect(requestText(m), contains('<focus>'));
    expect(requestText(m), contains('API changes'));
  });

  test('a split turn quotes the user request verbatim (CMP-7)', () async {
    final m = model([reply('earlier work'), reply('turn so far')]);
    final region = RegionBuilder()..user(10);
    final prefix = RegionBuilder()
      ..user(8, fill: 'w')
      ..call('c1', 'read')
      ..result('c1', 'read', 6);

    final summary = await summarizerOf(m)(
      SummaryRequest(region: messages(region), turnPrefix: messages(prefix)),
      CancelToken.none,
    );

    expect(m.requests, hasLength(2));
    expect(requestText(m, 1), contains('[tool call read]'));
    expect(summary, startsWith('earlier work'));
    expect(summary, contains('## Current turn context (split turn)'));
    expect(summary, contains('User request, verbatim:\n\n> ${'w' * 16}'));
    expect(summary, endsWith('turn so far'));
  });

  test('a split turn without an earlier region asks only once', () async {
    final m = model([reply('turn so far')]);
    final prefix = RegionBuilder()
      ..user(8, fill: 'w')
      ..assistant(6);

    final summary = await summarizerOf(m)(
      SummaryRequest(region: const [], turnPrefix: messages(prefix)),
      CancelToken.none,
    );

    expect(m.requests, hasLength(1));
    expect(summary, contains('## Current turn context (split turn)'));
  });

  group('failures', () {
    test('an ErrorEvent is CompactionFailure', () async {
      final m = model([
        {
          'error': {'class': 'rateLimited', 'message': 'slow down'},
        },
      ]);
      final r = RegionBuilder()..user(10);

      await expectLater(
        summarizerOf(m)(SummaryRequest(region: messages(r)), CancelToken.none),
        throwsA(isA<CompactionFailure>()),
      );
    });

    test('an empty answer is CompactionFailure', () async {
      final m = model([reply('   \n')]);
      final r = RegionBuilder()..user(10);

      await expectLater(
        summarizerOf(m)(SummaryRequest(region: messages(r)), CancelToken.none),
        throwsA(
          isA<CompactionFailure>().having(
            (e) => e.message,
            'message',
            'empty summary',
          ),
        ),
      );
    });

    test('a cancel is CancelledException (CMP-4)', () async {
      final m = model([
        {'waitForCancel': true},
      ]);
      final r = RegionBuilder()..user(10);
      final source = CancelTokenSource();

      final pending = summarizerOf(m)(
        SummaryRequest(region: messages(r)),
        source.token,
      );
      await pumpEventQueue();
      source.cancel(const UserCancel());

      await expectLater(pending, throwsA(isA<CancelledException>()));
    });
  });
}
