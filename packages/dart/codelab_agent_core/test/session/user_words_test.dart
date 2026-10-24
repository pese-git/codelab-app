import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/user_words.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'fixtures.dart';

/// Предикат «слова пользователя» (agent-sessions «Слова пользователя»,
/// §8.2.5, SES-14, SES-15).
void main() {
  setUp(resetUnknownOriginWarnings);

  final records = [
    for (final line
        in const LineSplitter()
            .convert(sessionFixture('all_origins.jsonl'))
            .skip(1))
      SessionRecord.fromJson(jsonDecode(line) as Map<String, Object?>),
  ];

  /// The answer for every record of `all_origins.jsonl`, by id.
  const expected = {
    'u0000001': true, // user without origin — a prompt
    'u0000002': true, // steer
    'u0000003': false, // subagent_notice
    'u0000004': false, // job_notice
    'u0000005': false, // loop_nudge
    'u0000006': false, // deadline_notice
    'u0000007': true, // parent_message
    'u0000008': false, // subagent_resume
    'u0000009': false, // future_value — unknown to this version
    'u0000010': false, // loop_note — assistant
    'u0000011': false, // assistant
    'u0000012': false, // toolResult
    'u0000013': false, // compaction
    'u0000014': false, // branch — unknown record
    'u0000015': false, // memory_recall — unknown record
  };

  /// The class of every [RecordOrigin]; one row per value.
  const classes = {
    RecordOrigin.steer: OriginClass.userWords,
    RecordOrigin.subagentNotice: OriginClass.service,
    RecordOrigin.jobNotice: OriginClass.service,
    RecordOrigin.loopNudge: OriginClass.service,
    RecordOrigin.loopNote: OriginClass.service,
    RecordOrigin.deadlineNotice: OriginClass.service,
    RecordOrigin.parentMessage: OriginClass.userWords,
    RecordOrigin.subagentResume: OriginClass.service,
  };

  test('every record of the fixture gets the expected answer', () {
    expect(records.map((r) => r.id).toList(), expected.keys.toList());
    for (final record in records) {
      expect(isUserWords(record), expected[record.id], reason: record.id);
    }
  });

  test('the table has a row for every RecordOrigin value (SES-15)', () {
    expect(classes.keys.toSet(), RecordOrigin.values.toSet());
    for (final MapEntry(key: origin, value: cls) in classes.entries) {
      expect(classifyOrigin(origin), cls, reason: origin.wire);
    }
  });

  test('wire values parse back', () {
    for (final origin in RecordOrigin.values) {
      expect(RecordOrigin.parse(origin.wire), origin);
    }
    expect(RecordOrigin.parse('future_value'), isNull);
  });

  test('isUserWordsEvent agrees with the record the writer builds', () {
    final at = DateTime.utc(2026, 10, 21);
    final cases = <(Message, MessageOrigin?)>[
      (UserMessage(const [TextContent('hi')], timestamp: at), null),
      (
        UserMessage(const [TextContent('Continue.')], timestamp: at),
        const LoopNudgeOrigin(LoopNudgeReason.emptyResponse, 1),
      ),
      (
        AssistantMessage(
          content: const [TextContent('note')],
          model: testModel,
          usage: Usage.zero,
          stopReason: StopReason.stop,
          timestamp: at,
        ),
        const LoopNoteOrigin(LoopNudgeReason.emptyResponse),
      ),
    ];
    for (final (message, origin) in cases) {
      final fields = origin == null ? null : originFieldsOf(origin);
      final record = MessageRecord(
        id: 'abcdefgh',
        parentId: null,
        timestamp: at,
        message: message,
        origin: fields?.origin,
        nudge: fields?.nudge,
        attempt: fields?.attempt,
      );

      expect(
        isUserWordsEvent(message, origin),
        isUserWords(record),
        reason: '$origin',
      );
      if (origin != null) {
        expect(recordOriginOf(origin).wire, fields!.origin);
      }
    }
  });

  test('an unknown origin warns once per value', () {
    final logger = RecordingLogger();
    final unknown = records.singleWhere((r) => r.id == 'u0000009');

    expect(isUserWords(unknown, logger: logger), isFalse);
    expect(isUserWords(unknown, logger: logger), isFalse);

    final warnings = logger.records
        .where((r) => r.event == 'session.origin.unknown')
        .toList();
    expect(warnings, hasLength(1));
    expect(warnings.single.level, LogLevel.warning);
    expect(warnings.single.fields, {'origin': 'future_value'});
  });
}
