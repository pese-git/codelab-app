import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'journal_helpers.dart';

/// agent-sessions «Открытие и ремонт журнала» на диске (задача 6.1): шаги
/// 5a–5b §8.6 поверх разбора ядра (SES-1, SES-2, SES-5, SES-6).
void main() {
  late String root;
  late File file;

  const id = '01JB8Q2W6R9T3M5K7N1P4X8Z0A';
  const sid = SessionId(id);

  String line(SessionRecord record) => jsonEncode(record.toJson());
  final header = jsonEncode(headerOf(id).toJson());
  final a = line(userRecord('aaaaaaaa', null, 'one'));
  final b = line(userRecord('bbbbbbbb', 'aaaaaaaa', 'two'));
  final c = line(userRecord('cccccccc', 'bbbbbbbb', 'three'));

  /// Журнал [id] с текстом [text] по пути, где его ищет хранилище.
  Future<void> journal(String text) async {
    await storeAt(root).create(headerOf(id));
    file = journalFile(root, id)..writeAsStringSync(text);
  }

  List<Map<String, Object?>> corrupt() => [
    for (final l in File('${file.path}.corrupt').readAsLinesSync())
      jsonDecode(l) as Map<String, Object?>,
  ];

  setUp(() => root = tempRoot('jsonl_repair_', addTearDown));

  test('a line cut mid-way is truncated away and quarantined', () async {
    final whole = '$header\n$a\n$b\n';
    await journal('$whole${c.substring(0, 40)}');
    final store = storeAt(root);

    final snapshot = await store.open(sid);

    expect(file.readAsStringSync(), whole);
    expect(snapshot.records.map((r) => r.id), ['aaaaaaaa', 'bbbbbbbb']);
    expect(snapshot.leafId, 'bbbbbbbb');
    expect(snapshot.repair.quarantinedLines, 1);
    final quarantined = corrupt().single;
    expect(quarantined['line'], 4);
    expect(quarantined['text'], c.substring(0, 40));
    expect(quarantined['reason'], 'truncated');
    expect(quarantined['at'], '2026-10-21T08:00:00.000Z');

    await store.append(sid, userRecord('dddddddd', snapshot.leafId, 'four'));
    final reopened = await storeAt(root).open(sid);
    expect(reopened.records.last.parentId, 'bbbbbbbb');
    expect(reopened.repair.isClean, isTrue);
  });

  test('garbage in the middle is quarantined and the file rewritten', () async {
    await journal('$header\n$a\n{oops\n$b\n');

    final snapshot = await storeAt(root).open(sid);

    expect(snapshot.records.map((r) => r.id), ['aaaaaaaa', 'bbbbbbbb']);
    expect(file.readAsStringSync(), '$header\n$a\n$b\n');
    expect(corrupt().single, containsPair('reason', 'invalid'));
    expect(corrupt().single, containsPair('text', '{oops'));
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('the rewrite keeps surviving lines byte for byte', () async {
    // Поля в порядке, которого `toJson` не даёт: переписывание переносит
    // строку как была (D14, `keptLines`).
    const odd =
        '{"id":"eeeeeeee","type":"label","parentId":"aaaaaaaa",'
        '"timestamp":"2026-10-21T08:00:00.000Z","targetId":"aaaaaaaa",'
        '"label":"x","future":1}';
    await journal('$header\n$a\n[1]\n$odd\n');

    await storeAt(root).open(sid);

    expect(file.readAsStringSync(), '$header\n$a\n$odd\n');
  });

  test('a duplicate id goes to the quarantine', () async {
    await journal('$header\n$a\n$a\n');

    final snapshot = await storeAt(root).open(sid);

    expect(snapshot.records, hasLength(1));
    expect(corrupt().single, containsPair('reason', 'duplicate id'));
    expect(file.readAsStringSync(), '$header\n$a\n');
  });

  test('a dangling leaf heals in memory; the file is unchanged', () async {
    final leaf = line(
      LeafRecord(
        id: 'ffffffff',
        parentId: 'bbbbbbbb',
        timestamp: t0,
        targetId: 'zzzzzzzz',
      ),
    );
    await journal('$header\n$a\n$b\n$leaf\n');
    final before = bytesOf(file);

    final snapshot = await storeAt(root).open(sid);

    expect(snapshot.leafId, 'bbbbbbbb');
    expect(snapshot.repair.healedLeafFrom, 'zzzzzzzz');
    expect(bytesOf(file), before);
  });

  test('a missing parent and a parent cycle do not break open', () async {
    final orphan = line(userRecord('gggggggg', 'missing0', 'orphan'));
    final loopA = line(userRecord('hhhhhhhh', 'iiiiiiii', 'loop a'));
    final loopB = line(userRecord('iiiiiiii', 'hhhhhhhh', 'loop b'));
    await journal('$header\n$a\n$orphan\n$loopA\n$loopB\n');
    final before = bytesOf(file);

    final snapshot = await storeAt(root).open(sid);

    expect(snapshot.records, hasLength(4));
    expect(snapshot.repair.brokenLinks, 1);
    expect(bytesOf(file), before);
  });

  test('an unknown version throws and leaves the file untouched', () async {
    await journal(
      '${header.replaceFirst('"version":1', '"version":2')}\n$a\n{oops\n',
    );
    final before = bytesOf(file);

    await expectLater(
      storeAt(root).open(sid),
      throwsA(
        isA<SessionOpenException>().having(
          (e) => e.error,
          'error',
          SessionOpenError.unsupportedVersion,
        ),
      ),
    );
    expect(bytesOf(file), before);
    expect(File('${file.path}.corrupt').existsSync(), isFalse);
  });

  group('a missing header', () {
    test('is synthesised in memory and not written', () async {
      await journal('$a\n$b\n');
      final before = bytesOf(file);

      final snapshot = await storeAt(root).open(sid);

      expect(snapshot.repair.headerMissing, isTrue);
      expect(snapshot.header.id, sid);
      expect(snapshot.header.cwd, '');
      expect(snapshot.header.created, file.lastModifiedSync().toUtc());
      expect(bytesOf(file), before);
    });

    test('takes cwd from index.json by the file name', () async {
      await journal('$header\n$a\n');
      await storeAt(root).list();
      file.writeAsStringSync('$a\n$b\n');

      final snapshot = await storeAt(root).open(sid);

      expect(snapshot.repair.headerMissing, isTrue);
      expect(snapshot.header.cwd, '/work/demo');
    });
  });

  test('a whole last line without a newline gets one', () async {
    await journal('$header\n$a');
    final store = storeAt(root);

    final snapshot = await store.open(sid);
    await store.append(sid, userRecord('bbbbbbbb', snapshot.leafId, 'two'));
    await store.close(sid);

    expect(file.readAsStringSync(), '$header\n$a\n$b\n');
  });
}
