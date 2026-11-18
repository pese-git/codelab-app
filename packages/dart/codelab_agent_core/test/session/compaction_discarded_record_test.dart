import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:codelab_agent_core/src/session/tree.dart';
import 'package:test/test.dart';

import 'journal_lines.dart';

/// Запись учёта отброшенного прохода сжатия `custom`
/// `codelab.compaction_discarded` в журнале: чтение, проекция, реплей (change
/// `fix-discarded-compaction-usage`, D1, D2; сценарии «Реплей» и «Старое ядро
/// читает новую запись»).
///
/// Тесты не используют новых имён ядра: запись — обычная `custom` по
/// §8.2.4, и «старый путь разбора» не должен меняться. Событие
/// `CompactionDiscarded` реплей не даёт — это проверяет
/// `test/compaction/compaction_discarded_event_test.dart`.
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  const data = {
    'reason': 'no reduction',
    'trigger': 'manual',
    'pass': 1,
    'tokensBefore': 3043,
    'tokensAfter': 3567,
    'summaryModel': 'openai/gpt-4o-mini',
    'usage': {
      'input': 764,
      'output': 171,
      'cacheRead': 0,
      'cacheWrite': 0,
      'cost': {
        'input': 0.0001146,
        'output': 0.0001026,
        'cacheRead': 0,
        'cacheWrite': 0,
      },
    },
  };

  String discarded(String recordId, String? parent) => jsonEncode({
    'type': 'custom',
    'id': recordId,
    'parentId': parent,
    'timestamp': at,
    'customType': 'codelab.compaction_discarded',
    'data': data,
  });

  SessionSnapshot parse(List<String> lines) =>
      parseSessionLines(journal([header(), ...lines]), id: id).snapshot;

  final base = [user('u1', null), answer('a1', 'u1', text: 'done')];

  test('the record is read as a CustomRecord with its data and written '
      'back unchanged', () {
    final snapshot = parse([...base, discarded('d1', 'a1')]);

    final record = snapshot.records.last as CustomRecord;
    expect(record.customType, 'codelab.compaction_discarded');
    expect(record.data, data);
    expect(record.parentId, 'a1');
    expect(snapshot.leafId, 'd1');
    expect(snapshot.repair.isClean, isTrue);
    expect(jsonEncode(record.toJson()), contains('"customType"'));
    expect(
      SessionRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
      ),
      isA<CustomRecord>().having((r) => r.data, 'data', data),
    );
  });

  test('the context projection is the same with the record and without it '
      '(§8.7: custom is not a message)', () {
    final without = buildLlmContext(parse(base));
    final withRecord = buildLlmContext(parse([...base, discarded('d1', 'a1')]));

    expect(
      [for (final m in withRecord.messages) m.toJson()],
      [for (final m in without.messages) m.toJson()],
    );
    expect(withRecord.lastCompaction, isNull);
    expect(withRecord.modeId, without.modeId);
  });

  test('a message after the record continues the branch: the record is on '
      'the path, the context is just the messages', () {
    final snapshot = parse([
      ...base,
      discarded('d1', 'a1'),
      user('u2', 'd1', text: 'next'),
    ]);

    final messages = buildLlmContext(snapshot).messages;

    expect(messages, hasLength(3));
    expect(pathToLeaf(snapshot).map((r) => r.id), ['u1', 'a1', 'd1', 'u2']);
  });

  test('the replay of the active branch is the same with the record and '
      'without it: no frame for the record', () {
    String names(SessionSnapshot s) =>
        [for (final e in buildReplay(s)) e.runtimeType].join(',');

    final without = names(parse(base));
    final withRecord = names(parse([...base, discarded('d1', 'a1')]));

    expect(withRecord, without);
    expect(without, isNotEmpty);
    expect(withRecord, isNot(contains('Compact')));
  });
}
