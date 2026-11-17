import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../../../codelab_agent_core/test/support/models.dart';
import 'journal_helpers.dart';

/// Реплей журнала в 1000 записей при `session/load` не зависит от того, где
/// идёт разбор (embedded-agent «Реплей после переноса разбора»; design.md
/// change `add-embedded-agent-mode`, D11, задача 5.2).
///
/// Почему: чтение и разбор JSONL в `JsonlSessionStore.open` уходят в
/// `Isolate.run`, чтобы большой журнал не занимал цикл событий UI-isolate. Перенос
/// не должен менять ни записи, ни дерево, ни лист, ни карантин, ни журнал
/// `session.leaf.healed`.
///
/// Для чего: характеризационный тест (исключение (а) `dart-agent-and-clients`
/// §9.0). Он зелёный до переноса и обязан остаться зелёным после: эталон —
/// `parseSessionLines` над текстом файла в том же isolate, то есть разбор,
/// который перенос не трогает; сравнивается полный результат загрузки, а не
/// число записей. Снимок загрузки заменяет сравнение кадров `session/load`:
/// проекция в кадры строится из снимка детерминированно, а кадров в
/// `codelab_agent_io` нет.
void main() {
  late String root;

  setUp(() => root = tempRoot('jsonl_replay_isolate_', addTearDown));

  const id = '01JB8Q2W6R9T3M5K7N1P4X8Z0A';
  const sid = SessionId(id);

  /// 1000 записей разных видов; каждая 50-я — `leaf` (ветвление) или метка.
  List<SessionRecord> thousand() {
    final records = <SessionRecord>[];
    String? parent;
    for (var i = 0; i < 1000; i++) {
      final recordId = i.toRadixString(36).padLeft(8, '0');
      final SessionRecord record;
      if (i > 0 && i % 50 == 0) {
        // Ветвление: лист возвращается на запись 10 назад.
        record = LeafRecord(
          id: recordId,
          parentId: parent,
          timestamp: t0,
          targetId: records[i - 10].id,
        );
      } else if (i % 7 == 3) {
        record = MessageRecord(
          id: recordId,
          parentId: parent,
          timestamp: t0,
          message: AssistantMessage(
            content: [
              const TextContent('ответ № с юникодом \u{1F600}'),
              ToolCall(id: 'c$i', name: 'read', arguments: {'path': 'f$i.txt'}),
            ],
            model: testModel,
            usage: const Usage(input: 10, output: 5),
            stopReason: StopReason.toolUse,
            timestamp: t0,
          ),
        );
      } else if (i % 7 == 4) {
        record = MessageRecord(
          id: recordId,
          parentId: parent,
          timestamp: t0,
          message: ToolResultMessage(
            toolCallId: 'c${i - 1}',
            toolName: 'read',
            content: [TextContent('строка 1\nстрока 2 №$i')],
            isError: i % 14 == 4,
            timestamp: t0,
          ),
        );
      } else if (i > 0 && i % 11 == 0) {
        record = LabelRecord(
          id: recordId,
          parentId: parent,
          timestamp: t0,
          targetId: records[i - 1].id,
          label: 'метка $i',
        );
      } else {
        record = userRecord(recordId, parent, 'сообщение $i');
      }
      records.add(record);
      parent = recordId;
    }
    return records;
  }

  /// Сверяемый целиком результат загрузки: заголовок, порядок и содержимое
  /// записей, индекс по id, лист и отчёт о ремонте.
  Map<String, Object?> fingerprint(SessionSnapshot s) => {
    'header': s.header.toJson(),
    'records': [for (final r in s.records) r.toJson()],
    'byId': s.byId.keys.toList(),
    'leaf': s.leafId,
    'repair': [
      s.repair.quarantinedLines,
      s.repair.headerMissing,
      s.repair.healedLeafFrom,
      s.repair.brokenLinks,
      s.repair.interruptedToolCalls,
    ],
  };

  Future<void> writeThousand(JsonlSessionStore store) async {
    await store.create(headerOf(id));
    for (final record in thousand()) {
      await store.append(sid, record);
    }
    await store.close(sid);
  }

  test('1000 records: the loaded snapshot equals the in-process parse of the '
      'file, record by record', () async {
    await writeThousand(storeAt(root));
    final file = journalFile(root, id);
    final reference = parseSessionLines(
      utf8.decode(file.readAsBytesSync()),
      id: sid,
      created: file.lastModifiedSync().toUtc(),
    );

    final snapshot = await storeAt(root).open(sid);

    expect(snapshot.records, hasLength(1000));
    expect(fingerprint(snapshot), fingerprint(reference.snapshot));
    // Не только эталон разбора: порядок и содержимое совпадают с записанным.
    expect(
      [for (final r in snapshot.records) r.toJson()],
      [for (final r in thousand()) r.toJson()],
    );
    // Дерево: у каждой записи, кроме первой, родитель — предыдущая.
    expect(snapshot.records.first.parentId, isNull);
    for (var i = 1; i < snapshot.records.length; i++) {
      expect(snapshot.records[i].parentId, snapshot.records[i - 1].id);
    }
    // Последняя запись не `leaf`, поэтому лист — она сама.
    expect(snapshot.leafId, snapshot.records.last.id);
  });

  test('1000 records with broken lines: snapshot, quarantine file and the '
      'repaired journal equal the in-process parse', () async {
    await writeThousand(storeAt(root));
    final file = journalFile(root, id);
    final lines = file.readAsLinesSync();
    // Битая строка в середине, битая JSON-строка и оборванный хвост без `\n`.
    lines[300] = '{"type":"message","id":';
    lines[301] = 'not json at all';
    final text = '${lines.join('\n')}\n{"type":"mess';
    file.writeAsStringSync(text);
    final reference = parseSessionLines(
      text,
      id: sid,
      created: file.lastModifiedSync().toUtc(),
    );
    expect(reference.quarantine, isNotEmpty);

    final snapshot = await storeAt(root).open(sid);

    expect(fingerprint(snapshot), fingerprint(reference.snapshot));
    final corrupt = File('${file.path}.corrupt').readAsLinesSync();
    expect(corrupt, hasLength(reference.quarantine.length));
    expect(
      [for (final l in corrupt) (jsonDecode(l) as Map)['line']],
      [for (final q in reference.quarantine) q.line],
    );
    expect(file.readAsStringSync(), '${reference.keptLines.join('\n')}\n');
  });

  test('a dangling leaf is healed the same way and logged with the same '
      'event as the in-process parse', () async {
    await writeThousand(storeAt(root));
    final file = journalFile(root, id);
    final leaf = jsonEncode(
      LeafRecord(
        id: 'zzzzzzzz',
        parentId: thousand().last.id,
        timestamp: t0,
        targetId: 'missing0',
      ).toJson(),
    );
    file.writeAsStringSync('$leaf\n', mode: FileMode.append);
    final referenceLog = RecordingLogger();
    final reference = parseSessionLines(
      utf8.decode(file.readAsBytesSync()),
      id: sid,
      created: file.lastModifiedSync().toUtc(),
      logger: referenceLog,
    );
    expect(referenceLog.eventsOf('session.leaf.healed'), hasLength(1));
    final log = RecordingLogger();

    final snapshot = await storeAt(root, logger: log).open(sid);

    expect(fingerprint(snapshot), fingerprint(reference.snapshot));
    final healed = log.eventsOf('session.leaf.healed');
    expect(healed, hasLength(1));
    // Хранилище добавляет `session_id` (AGENTS.md §16); остальное — как у ядра.
    expect(healed.single.fields, {
      'session_id': id,
      ...referenceLog.eventsOf('session.leaf.healed').single.fields,
    });
  });

  test('only a broken tail: the file is truncated in place, without a .tmp, '
      'and the snapshot equals the in-process parse', () async {
    await writeThousand(storeAt(root));
    final file = journalFile(root, id);
    final whole = file.readAsStringSync();
    file.writeAsStringSync('$whole{"type":"mess');
    final reference = parseSessionLines(
      file.readAsStringSync(),
      id: sid,
      created: file.lastModifiedSync().toUtc(),
    );
    expect(reference.onlyTailBroken, isTrue);

    final snapshot = await storeAt(root).open(sid);

    expect(fingerprint(snapshot), fingerprint(reference.snapshot));
    expect(file.readAsStringSync(), whole);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    expect(File('${file.path}.corrupt').readAsLinesSync(), hasLength(1));
  });
}
