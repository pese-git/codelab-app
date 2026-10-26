import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Формат записей журнала (agent-sessions «Формат журнала JSONL», §8.2).
void main() {
  final lines = const LineSplitter().convert(
    sessionFixture('all_records.jsonl'),
  );

  Map<String, Object?> json(String line) =>
      jsonDecode(line) as Map<String, Object?>;

  test('the header round-trips byte for byte', () {
    final header = SessionHeader.fromJson(json(lines.first));

    expect(header.version, 1);
    expect(header.id, const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C'));
    expect(header.cwd, '/work/demo');
    expect(header.created, DateTime.utc(2026, 10, 21, 8));
    expect(header.agent.name, 'codelab-agent');
    expect(header.metadata, {'profile': 'agent-serve'});
    expect(jsonEncode(header.toJson()), lines.first);
  });

  test('every record of the fixture parses into its type', () {
    final records = [
      for (final line in lines.skip(1)) SessionRecord.fromJson(json(line)),
    ];

    expect(
      [for (final r in records) r.runtimeType],
      [
        ModelChangeRecord,
        MessageRecord,
        MessageRecord,
        MessageRecord,
        MessageRecord,
        MessageRecord,
        MessageRecord,
        MessageRecord,
        ModeChangeRecord,
        ConfigChangeRecord,
        PlanRecord,
        CompactionRecord,
        LabelRecord,
        SessionInfoRecord,
        CustomRecord,
        LeafRecord,
        CustomRecord,
        MessageRecord,
      ],
    );
  });

  test('toJson of every record equals its line', () {
    for (final line in lines.skip(1)) {
      final record = SessionRecord.fromJson(json(line));
      expect(jsonEncode(record.toJson()), line, reason: record.type);
    }
  });

  test('fields of the record stay out of the message', () {
    final result = SessionRecord.fromJson(json(lines[6])) as MessageRecord;

    expect(result.outcome, 'completed');
    expect(result.diff?.path, '/work/demo/test/a_test.dart');
    expect(result.toolMeta?.title, 'Edit test/a_test.dart');
    expect(result.toolMeta?.kind, ToolKind.edit);
    expect(result.toolMeta?.locations, [
      const Location('/work/demo/test/a_test.dart', line: 2),
    ]);
    expect(result.message, isA<ToolResultMessage>());
    expect(result.message.toJson().keys, isNot(contains('outcome')));
  });

  test('origin fields of service messages', () {
    final nudge = SessionRecord.fromJson(json(lines[7])) as MessageRecord;
    final note = SessionRecord.fromJson(json(lines[8])) as MessageRecord;

    expect(nudge.origin, 'loop_nudge');
    expect(nudge.nudge, 'empty_response');
    expect(nudge.attempt, 1);
    expect(note.origin, 'loop_note');
    expect(note.attempt, isNull);
  });

  test('a plan record keeps the wire statuses', () {
    final plan = SessionRecord.fromJson(json(lines[11])) as PlanRecord;

    expect(
      [for (final e in plan.entries) e.status],
      [PlanStatus.completed, PlanStatus.inProgress, PlanStatus.pending],
    );
    expect(
      [for (final e in plan.entries) e.priority],
      [PlanPriority.high, PlanPriority.medium, PlanPriority.low],
    );
  });

  test('an unknown type is kept as unknown custom record', () {
    final branch = SessionRecord.fromJson(json(lines[17])) as CustomRecord;

    expect(branch.customType, 'unknown:branch');
    expect(branch.type, 'branch');
    expect(branch.id, 'w8e7r6t5');
    expect(branch.parentId, 'u1i2o3p4');
  });

  test('unknown fields of a known record go to extra', () {
    final result = SessionRecord.fromJson(json(lines.last)) as MessageRecord;

    expect(result.extra.keys, ['spill']);
  });

  test('a record without id is a FormatException', () {
    expect(
      () => SessionRecord.fromJson({
        'type': 'leaf',
        'parentId': null,
        'timestamp': '2026-10-21T08:00:00.000Z',
        'targetId': 'x',
      }),
      throwsFormatException,
    );
  });

  test('assistant models come back as journal models', () {
    final answer = SessionRecord.fromJson(json(lines[3])) as MessageRecord;
    final model = (answer.message as AssistantMessage).model;

    expect(model.provider, 'test');
    expect(model.id, 'model-1');
    expect(model, journalModelRef('test', 'model-1'));
  });

  test('a new record writes the common fields first, null parent kept', () {
    final record = ModeChangeRecord(
      id: 'abcdefgh',
      parentId: null,
      timestamp: DateTime.utc(2026, 10, 21, 8, 0, 0, 5, 7),
      modeId: 'plan',
    );

    expect(
      jsonEncode(record.toJson()),
      '{"type":"mode_change","id":"abcdefgh","parentId":null,'
      '"timestamp":"2026-10-21T08:00:00.005Z","modeId":"plan"}',
    );
  });
}
