import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/prompts.g.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../skills/skills_support.dart';

import 'fixtures.dart';
import 'journal_lines.dart';

/// Проекции журнала (agent-sessions «Проекции журнала», §8.7, §8.10,
/// SES-7).
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  SessionSnapshot snapshot(List<String> lines) =>
      parseSessionLines(journal([header(), ...lines]), id: id).snapshot;

  String textOf(Message m) =>
      m.content.whereType<TextContent>().map((b) => b.text).join();

  group('buildLlmContext', () {
    test('the active branch, messages only, with the last state', () {
      final s = snapshot([
        modelChange('m1', null),
        user('u1', 'm1', text: 'first'),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'read', {'path': 'a'}),
          ],
        ),
        toolResult('r1', 'a1', callId: 'c1'),
        modeChange('md', 'r1', 'plan'),
        plan('p1', 'md', ['step']),
        answer('a2', 'p1', text: 'done'),
      ]);

      final context = buildLlmContext(s);

      expect(context.messages.map((m) => m.runtimeType), [
        UserMessage,
        AssistantMessage,
        ToolResultMessage,
        AssistantMessage,
      ]);
      expect(context.model?.provider, 'test');
      expect(context.modeId, 'plan');
      expect(context.lastCompaction, isNull);
    });

    test(
      'a compaction replaces records before firstKeptId with the summary',
      () {
        final s = snapshot([
          user('u1', null, text: 'old request'),
          answer(
            'a1',
            'u1',
            usage: {
              'input': 90000,
              'output': 10,
              'cacheRead': 0,
              'cacheWrite': 0,
            },
          ),
          user('u2', 'a1', text: 'kept request'),
          answer(
            'a2',
            'u2',
            usage: {
              'input': 95000,
              'output': 5,
              'cacheRead': 0,
              'cacheWrite': 0,
            },
          ),
          compaction('k1', 'a2', firstKept: 'u2', summary: 'S'),
          user('u3', 'k1', text: 'after'),
        ]);

        final context = buildLlmContext(s);

        expect(context.messages.map(textOf), [
          Prompts.compactionSummaryWrapper.render({'summary': 'S'}),
          'kept request',
          'ok',
          'after',
        ]);
        expect(context.messages.first, isA<UserMessage>());
        expect(context.lastCompaction?.id, 'k1');
        // Usage ответов до сжатия обнулён в проекции, в журнале — как был.
        final kept = context.messages[2] as AssistantMessage;
        expect(kept.usage, Usage.zero);
        final inJournal = s.byId['a2']! as MessageRecord;
        expect((inJournal.message as AssistantMessage).usage.input, 95000);
      },
    );

    test('a lost firstKeptId keeps only records after the compaction', () {
      final logger = RecordingLogger();
      final s = snapshot([
        user('u1', null),
        compaction('k1', 'u1', firstKept: 'nowhere', summary: 'S'),
        user('u2', 'k1', text: 'after'),
      ]);

      final context = buildLlmContext(s, logger: logger);

      expect(context.messages.map(textOf), [
        Prompts.compactionSummaryWrapper.render({'summary': 'S'}),
        'after',
      ]);
      expect(logger.eventsOf('session.compaction.lost_anchor'), hasLength(1));
    });

    test('service user messages stay in the context', () {
      final s = snapshot([
        user('u1', null),
        user(
          'n1',
          'u1',
          text: 'Continue.',
          origin: 'loop_nudge',
          originFields: {'nudge': 'empty_response', 'attempt': 1},
        ),
      ]);

      expect(buildLlmContext(s).messages, hasLength(2));
    });

    test('the same snapshot gives the same messages (SES-7)', () {
      final text = sessionFixture('all_records.jsonl');
      final a = parseSessionLines(text, id: id).snapshot;
      final b = parseSessionLines(text, id: id).snapshot;

      expect(buildLlmContext(a).messages, buildLlmContext(b).messages);
    });

    test('the last config change wins per option', () {
      final s = parseSessionLines(
        sessionFixture('all_records.jsonl'),
        id: id,
      ).snapshot;

      expect(buildLlmContext(s).config, {'effort': 'high'});
    });
  });

  /// `compactionCovered` (design.md change
  /// `anchor-context-estimate-after-compaction`, D1, D4): число начальных
  /// сообщений проекции, которые покрывает `tokensAfter` последней записи
  /// `compaction` — резюме, сообщение навыков и сохранённые сообщения.
  group('compactionCovered (D1, D4)', () {
    test('is 0 without a compaction', () {
      final s = snapshot([
        user('u1', null),
        answer('a1', 'u1'),
        user('u2', 'a1'),
      ]);

      expect(buildLlmContext(s).compactionCovered, 0);
    });

    test('the summary plus the kept messages; the tail is not covered', () {
      final s = snapshot([
        user('u1', null, text: 'old'),
        answer('a1', 'u1'),
        user('u2', 'a1', text: 'kept'),
        answer('a2', 'u2'),
        compaction('k1', 'a2', firstKept: 'u2'),
        user('u3', 'k1', text: 'tail one'),
        answer('a3', 'u3'),
      ]);

      final context = buildLlmContext(s);

      // резюме + u2 + a2; u3 и a3 после записи — хвост.
      expect(context.messages, hasLength(5));
      expect(context.compactionCovered, 3);
    });

    test('the summary, the skills message and the kept messages', () {
      final catalog = parse([validSkill('notes', body: 'Take notes.')]);
      final fingerprint = sha256
          .convert(utf8.encode(catalog.skills.single.body))
          .toString();
      final record =
          jsonDecode(compaction('k1', 'a2', firstKept: 'u2'))
              as Map<String, Object?>;
      record['skills'] = [
        {'name': 'notes', 'fingerprint': fingerprint},
      ];
      final s = snapshot([
        user('u1', null),
        answer('a1', 'u1'),
        user('u2', 'a1'),
        answer('a2', 'u2'),
        jsonEncode(record),
        user('u3', 'k1', text: 'tail'),
      ]);

      final context = buildLlmContext(s, skillCatalog: catalog);

      // резюме + сообщение навыков + u2 + a2; u3 — хвост.
      expect(context.messages, hasLength(5));
      expect(context.compactionCovered, 4);
    });

    test('without the skill catalog the skills message is not counted', () {
      final record =
          jsonDecode(compaction('k1', 'a2', firstKept: 'u2'))
              as Map<String, Object?>;
      record['skills'] = [
        {'name': 'notes', 'fingerprint': 'f'},
      ];
      final s = snapshot([
        user('u1', null),
        answer('a1', 'u1'),
        user('u2', 'a1'),
        answer('a2', 'u2'),
        jsonEncode(record),
      ]);

      expect(buildLlmContext(s).compactionCovered, 3);
    });

    test('two compactions in a row: counted by the last one', () {
      final s = snapshot([
        user('u1', null),
        answer('a1', 'u1'),
        user('u2', 'a1'),
        answer('a2', 'u2'),
        compaction('k1', 'a2', firstKept: 'u2'),
        compaction('k2', 'k1', firstKept: 'u2'),
        user('u3', 'k2'),
      ]);

      final context = buildLlmContext(s);

      expect(context.lastCompaction?.id, 'k2');
      // резюме k2 + u2 + a2 (прошлая запись k1 заменена резюме k2).
      expect(context.compactionCovered, 3);
      expect(context.messages, hasLength(4));
    });
  });

  group('summarize', () {
    test('the title of the last session_info wins', () {
      final s = snapshot([
        user('u1', null, text: 'Fix it'),
        sessionInfo('i1', 'u1', 'First'),
        sessionInfo('i2', 'i1', 'Second'),
      ]);

      expect(summarize(s).title, 'Second');
    });

    test(
      'without session_info — the first user words, whitespace collapsed',
      () {
        final s = snapshot([
          user(
            'n0',
            null,
            text: 'notice',
            origin: 'loop_nudge',
            originFields: {'nudge': 'empty_response', 'attempt': 1},
          ),
          user('u1', 'n0', text: '  Почини   тест\n парсера '),
        ]);

        expect(summarize(s).title, 'Почини тест парсера');
      },
    );

    test('a long title is cut at a word boundary with an ellipsis', () {
      final words = List.filled(30, 'word').join(' ');
      final s = snapshot([user('u1', null, text: words)]);

      final title = summarize(s).title!;

      expect(title.length, lessThanOrEqualTo(80));
      expect(title, endsWith('…'));
      expect(title.substring(0, title.length - 1), isNot(endsWith(' ')));
      expect(words, startsWith(title.substring(0, title.length - 1)));
    });

    test('no user words — no title', () {
      expect(summarize(snapshot([answer('a1', null)])).title, isNull);
    });

    test('counts, the update time and the failed last turn', () {
      final s = snapshot([
        user('u1', null),
        answer('a1', 'u1'),
        user('u2', 'a1'),
        answer('a2', 'u2', stopReason: 'error'),
      ]);

      final summary = summarize(s);

      expect(summary.id, id);
      expect(summary.cwd, '/work/demo');
      expect(summary.messageCount, 4);
      expect(summary.lastTurnFailed, isTrue);
      expect(summary.updatedAt, DateTime.parse(at));
    });

    test('an empty journal is updated at its creation', () {
      expect(summarize(snapshot([])).updatedAt, DateTime.parse(at));
    });
  });

  group('buildReplay', () {
    test('messages, calls with metadata, task list, mode and title', () {
      final s = snapshot([
        user('u1', null, text: 'go'),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'read', {'path': 'a.txt'}),
          ],
        ),
        toolResult(
          'r1',
          'a1',
          callId: 'c1',
          toolMeta: {
            'title': 'Read a.txt',
            'kind': 'read',
            'locations': [
              {'path': '/work/demo/a.txt'},
            ],
          },
        ),
        plan('p1', 'r1', ['step']),
        modeChange('md', 'p1', 'plan'),
        sessionInfo('i1', 'md', 'Go'),
      ]);

      final events = buildReplay(s);

      expect(events.map((e) => e.runtimeType), [
        MessageStarted,
        MessageEnded,
        MessageStarted,
        MessageEnded,
        ToolCallStarted,
        ToolCallFinished,
        ModeChanged,
        SessionTitleChanged,
        // Список ветки — один снимок после истории (§17.16.6).
        TaskListChanged,
      ]);
      final started = events.whereType<ToolCallStarted>().single;
      expect(started.toolCallId, 'c1');
      expect(started.tool, 'read');
      expect(started.title, 'Read a.txt');
      expect(started.kind, ToolKind.read);
      expect(started.input, {'path': 'a.txt'});
      expect(started.locations, [const Location('/work/demo/a.txt')]);
      final finished = events.whereType<ToolCallFinished>().single;
      expect(finished.outcome, ToolOutcome.completed);
      expect(finished.interrupted, isFalse);
      expect(events.whereType<ModeChanged>().single.mode, ModeId.plan);
      expect(events.whereType<SessionTitleChanged>().single.title, 'Go');
      expect(events.every((e) => e.sessionId == id), isTrue);
    });

    test('an interrupted call replays as failed with the flag', () {
      final s = snapshot([
        user('u1', null),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'exec', {'command': 'x'}),
          ],
        ),
        toolResult(
          'r1',
          'a1',
          callId: 'c1',
          tool: 'exec',
          outcome: 'interrupted',
          isError: true,
        ),
      ]);

      final finished = buildReplay(s).whereType<ToolCallFinished>().single;

      expect(finished.outcome, ToolOutcome.failed);
      expect(finished.interrupted, isTrue);
    });

    test('service user messages are skipped, notes of the loop are not', () {
      final s = snapshot([
        user('u1', null),
        user(
          'n1',
          'u1',
          origin: 'loop_nudge',
          originFields: {'nudge': 'empty_response', 'attempt': 1},
        ),
        answer('a1', 'n1', text: 'note'),
      ]);

      final ended = buildReplay(s).whereType<MessageEnded>().toList();

      expect(ended.map((e) => e.message.runtimeType), [
        UserMessage,
        AssistantMessage,
      ]);
    });

    test('a compaction replays as ContextCompacted', () {
      final s = snapshot([
        user('u1', null),
        compaction('k1', 'u1', firstKept: 'u1'),
      ]);

      final compacted = buildReplay(s).whereType<ContextCompacted>().single;

      expect(compacted.tokensBefore, 1000);
      expect(compacted.tokensAfter, 100);
    });
  });
}
