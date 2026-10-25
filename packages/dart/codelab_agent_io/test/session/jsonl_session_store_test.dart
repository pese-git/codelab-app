import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../../../codelab_agent_core/test/session/session_store_contract.dart';
import 'journal_helpers.dart';

/// agent-sessions «JsonlSessionStore пакета codelab_agent_io» (задача 5.1):
/// общий контракт порта во временном каталоге и правила записи §8.5, §8.9,
/// §8.10.
void main() {
  group('contract', () {
    sessionStoreContract(
      () async => storeAt(tempRoot('jsonl_contract_', addTearDown)),
    );
  });

  late String root;

  setUp(() => root = tempRoot('jsonl_store_', addTearDown));

  const id = '01JB8Q2W6R9T3M5K7N1P4X8Z0A';
  const sid = SessionId(id);

  test('the file lives in the slug directory, named by time and id', () async {
    final store = storeAt(root);
    await store.create(headerOf(id));

    final file = File(
      '$root/${cwdSlug('/work/demo')}/2026-10-21T08-00-00-000Z_$id.jsonl',
    );
    expect(file.existsSync(), isTrue);
    final header = jsonDecode(file.readAsLinesSync().single) as Map;
    expect(header['type'], 'session');
    expect(header['id'], id);
  });

  test('a store over the same root finds the journal by id', () async {
    await storeAt(root).create(headerOf(id));
    await storeAt(root).append(sid, userRecord('aaaaaaaa', null, 'one'));

    final snapshot = await storeAt(root).open(sid);

    expect(snapshot.records.map((r) => r.id), ['aaaaaaaa']);
  });

  // Строка с `\n` внутри — `StateError` (§8.5, шаг 1), но `jsonEncode`
  // экранирует переводы строк, поэтому проверяется сам результат: текст с
  // ними занимает одну строку файла и читается обратно без изменений.
  test('text with line breaks takes one line of the file', () async {
    final store = storeAt(root);
    await store.create(headerOf(id));

    await store.append(sid, userRecord('aaaaaaaa', null, 'a\nb\r\nc'));

    expect(journalFile(root, id).readAsLinesSync(), hasLength(2));
    final message = (await store.open(sid)).records.single as MessageRecord;
    final text = (message.message as UserMessage).content.single;
    expect((text as TextContent).text, 'a\nb\r\nc');
  });

  test('100 parallel appends give 100 whole lines with unique ids', () async {
    final store = storeAt(root);
    await store.create(headerOf(id));

    await Future.wait([
      for (var i = 0; i < 100; i++)
        store.append(
          sid,
          userRecord(i.toRadixString(36).padLeft(8, '0'), null, 'x' * 2000),
        ),
    ]);
    await store.close(sid);

    final lines = journalFile(root, id).readAsLinesSync().skip(1).toList();
    expect(lines, hasLength(100));
    final ids = {for (final l in lines) (jsonDecode(l) as Map)['id']};
    expect(ids, hasLength(100));
  });

  group('FsyncPolicy', () {
    Future<int> syncsFor(FsyncPolicy policy) async {
      var syncs = 0;
      final store = storeAt(
        tempRoot('jsonl_fsync_', addTearDown),
        fsync: policy,
        sync: (file) async => syncs++,
      );
      await store.create(headerOf(id));
      syncs = 0;
      await store.append(sid, userRecord('aaaaaaaa', null, 'plain'));
      await store.append(
        sid,
        userRecord('bbbbbbbb', 'aaaaaaaa', 'tool result'),
        durable: true,
      );
      await store.flush(sid);
      return syncs;
    }

    test('checkpoints — only durable records and flush', () async {
      expect(await syncsFor(FsyncPolicy.checkpoints), 2);
    });

    test('always — after every record and on flush', () async {
      expect(await syncsFor(FsyncPolicy.always), 3);
    });

    test('never — not at all', () async {
      expect(await syncsFor(FsyncPolicy.never), 0);
    });
  });

  test('a failed write closes the handle; the next write succeeds', () async {
    final handles = <RandomAccessFile>[];
    var fail = false;
    final store = storeAt(
      root,
      fsync: FsyncPolicy.always,
      sync: (file) async {
        handles.add(file);
        if (fail) {
          fail = false;
          throw const FileSystemException('disk full');
        }
      },
    );
    await store.create(headerOf(id));
    handles.clear();
    fail = true;

    await expectLater(
      store.append(sid, userRecord('aaaaaaaa', null, 'one')),
      throwsA(isA<FileSystemException>()),
    );
    await store.append(sid, userRecord('bbbbbbbb', null, 'two'));

    expect(handles, hasLength(2));
    expect(identical(handles.first, handles.last), isFalse);
    final snapshot = await store.open(sid);
    expect(snapshot.records.map((r) => r.id), contains('bbbbbbbb'));
  });

  group('index.json', () {
    File index() => File('$root/index.json');

    Future<JsonlSessionStore> seeded() async {
      final store = storeAt(root);
      await store.create(headerOf(id));
      await store.append(sid, userRecord('aaaaaaaa', null, 'first task'));
      await store.close(sid);
      return store;
    }

    test('a hit by size and mtime takes the cached summary', () async {
      final store = await seeded();
      expect((await store.list()).items.single.title, 'first task');
      expect(index().existsSync(), isTrue);

      final cached = index().readAsStringSync();
      index().writeAsStringSync(
        cached.replaceAll('"first task"', '"from the cache"'),
      );

      expect((await storeAt(root).list()).items.single.title, 'from the cache');
    });

    test('a changed file is summarised again', () async {
      final store = await seeded();
      await store.list();
      index().writeAsStringSync(
        index().readAsStringSync().replaceAll(
          '"first task"',
          '"from the cache"',
        ),
      );

      await store.append(
        sid,
        SessionInfoRecord(
          id: 'bbbbbbbb',
          parentId: 'aaaaaaaa',
          timestamp: t0,
          title: 'renamed',
        ),
      );
      await store.close(sid);

      expect((await storeAt(root).list()).items.single.title, 'renamed');
    });

    test('a broken cache is ignored and rebuilt', () async {
      await seeded();
      index().writeAsStringSync('{oops');

      final page = await storeAt(root).list();

      expect(page.items.single.title, 'first task');
      expect(() => jsonDecode(index().readAsStringSync()), returnsNormally);
    });

    test('list does not repair the file on disk', () async {
      await seeded();
      final file = journalFile(root, id)
        ..writeAsStringSync('{"type":"mess', mode: FileMode.append);
      final before = bytesOf(file);

      final page = await storeAt(root).list();

      expect(page.items.single.title, 'first task');
      expect(bytesOf(file), before);
      expect(File('${file.path}.corrupt').existsSync(), isFalse);
    });

    test('a journal of an unknown version is skipped by list', () async {
      await seeded();
      Directory('$root/other').createSync();
      File(
        '$root/other/2026-10-21T08-00-00-000Z_01JB8Q2W6R9T3M5K7N1P4X8Z0B.jsonl',
      ).writeAsStringSync(
        '{"type":"session","version":2,"id":"01JB8Q2W6R9T3M5K7N1P4X8Z0B"}\n',
      );

      final page = await storeAt(root).list();

      expect(page.items.map((s) => s.id), [sid]);
    });
  });

  test('slugs of /a/b-c and /a-b/c differ and are stable', () {
    expect(cwdSlug('/a/b-c'), isNot(cwdSlug('/a-b/c')));
    expect(cwdSlug('/a/b-c'), cwdSlug('/a/b-c'));
  });
}
