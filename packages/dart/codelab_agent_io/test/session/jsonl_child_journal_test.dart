import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'journal_helpers.dart';

/// `JsonlSessionStore.createChild`: журнал потомка лежит в `subagents/`
/// корневой сессии и не виден `open`, `list` и `index.json` (agent-subagents
/// «Журнал субагента и прерывание», «Раскладка внука»; agent-sessions
/// «Дочерние журналы не в списке сессий»; design.md change
/// `add-subagents-and-tasks`, D7, D36 Т4; `agent-core/17-3-subagents.md`
/// §17.3.6).
///
/// Охраняют `createChild` порта и поле `parent` заголовка `SessionHeader`.
/// Общий контракт порта (в том числе группа `createChild`) —
/// `jsonl_session_store_test.dart`; здесь — раскладка файлов, которую знает
/// только файловое хранилище.
void main() {
  late String root;

  setUp(() => root = tempRoot('jsonl_child_', addTearDown));

  const rootId = '01JB8Q2W6R9T3M5K7N1P4X8Z0R';
  const childId = '01JB8Q3A1D2E3F4G5H6J7K8M9N';
  const grandId = '01JB8Q3A1D2E3F4G5H6J7K8M9P';

  SessionHeader childHeader(
    String id, {
    required String parentSession,
    required String subagentId,
    required int depth,
    String agent = 'explore',
  }) => SessionHeader(
    id: SessionId(id),
    cwd: '/work/demo',
    created: t0,
    agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
    parent: SessionParent(
      sessionId: SessionId(parentSession),
      rootSessionId: const SessionId(rootId),
      toolCallId: 'call_3',
      subagentId: subagentId,
      agent: agent,
      depth: depth,
    ),
  );

  Directory subagentsDir() => Directory(
    '$root/${cwdSlug('/work/demo')}/2026-10-21T08-00-00-000Z_$rootId/subagents',
  );

  test('журнал ребёнка — в <корень без .jsonl>/subagents/, адрес — путь '
      'относительно sessions/', () async {
    final store = storeAt(root);
    await store.create(headerOf(rootId));

    final address = await store.createChild(
      childHeader(
        childId,
        parentSession: rootId,
        subagentId: 'sub_k3f9a1c2',
        depth: 1,
      ),
    );

    final files = subagentsDir().listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('_$childId.jsonl'));
    expect(
      address,
      '${cwdSlug('/work/demo')}/2026-10-21T08-00-00-000Z_$rootId/subagents/'
      '2026-10-21T08-00-00-000Z_$childId.jsonl',
    );
    final header =
        jsonDecode(files.single.readAsLinesSync().single)
            as Map<String, Object?>;
    expect(header['type'], 'session');
    expect(header['id'], childId);
    expect(header['parent'], {
      'sessionId': rootId,
      'rootSessionId': rootId,
      'toolCallId': 'call_3',
      'subagentId': 'sub_k3f9a1c2',
      'agent': 'explore',
      'depth': 1,
    });
  });

  test('сценарий «Раскладка внука»: журнал внука лежит плоско рядом с '
      'журналом ребёнка, parent.sessionId — ребёнок, depth 2', () async {
    final store = storeAt(root);
    await store.create(headerOf(rootId));
    await store.createChild(
      childHeader(
        childId,
        parentSession: rootId,
        subagentId: 'sub_k3f9a1c2',
        depth: 1,
      ),
    );

    await store.createChild(
      childHeader(
        grandId,
        parentSession: childId,
        subagentId: 'sub_p4q5r6s7',
        depth: 2,
        agent: 'general',
      ),
    );

    final names = [
      for (final f in subagentsDir().listSync().whereType<File>())
        f.path.split('/').last,
    ]..sort();
    expect(names, [
      '2026-10-21T08-00-00-000Z_$childId.jsonl',
      '2026-10-21T08-00-00-000Z_$grandId.jsonl',
    ]);
    final grand = subagentsDir().listSync().whereType<File>().singleWhere(
      (f) => f.path.endsWith('_$grandId.jsonl'),
    );
    final header =
        jsonDecode(grand.readAsLinesSync().first) as Map<String, Object?>;
    expect((header['parent']! as Map)['sessionId'], childId);
    expect((header['parent']! as Map)['rootSessionId'], rootId);
    expect((header['parent']! as Map)['depth'], 2);
    // Вложенных каталогов по дереву нет (пути Windows, D7).
    expect(subagentsDir().listSync().whereType<Directory>(), isEmpty);
  });

  test(
    'записи ребёнка попадают в его файл, журнал корня не меняется',
    () async {
      final store = storeAt(root);
      await store.create(headerOf(rootId));
      final rootBefore = bytesOf(journalFile(root, rootId));
      await store.createChild(
        childHeader(
          childId,
          parentSession: rootId,
          subagentId: 'sub_k3f9a1c2',
          depth: 1,
        ),
      );

      await store.append(
        const SessionId(childId),
        userRecord('cccccccc', null, 'sub task'),
        durable: true,
      );
      await store.flush(const SessionId(childId));

      final child = subagentsDir()
          .listSync()
          .whereType<File>()
          .single
          .readAsLinesSync();
      expect(child, hasLength(2));
      expect(child.last, contains('sub task'));
      expect(bytesOf(journalFile(root, rootId)), rootBefore);
    },
  );

  test('open с id ребёнка — SessionNotFound, в том числе у нового '
      'хранилища над тем же каталогом', () async {
    final store = storeAt(root);
    await store.create(headerOf(rootId));
    await store.createChild(
      childHeader(
        childId,
        parentSession: rootId,
        subagentId: 'sub_k3f9a1c2',
        depth: 1,
      ),
    );

    await expectLater(
      store.open(const SessionId(childId)),
      throwsA(isA<SessionNotFound>()),
    );
    await expectLater(
      storeAt(root).open(const SessionId(childId)),
      throwsA(isA<SessionNotFound>()),
    );
  });

  test('сценарий «Дочерние журналы не в списке сессий»: list — одна '
      'сессия, index.json не содержит дочерних журналов', () async {
    final store = storeAt(root);
    await store.create(headerOf(rootId));
    await store.append(
      const SessionId(rootId),
      userRecord('aaaaaaaa', null, 'root task'),
    );
    for (final (id, sub) in [
      (childId, 'sub_k3f9a1c2'),
      (grandId, 'sub_p4q5r6s7'),
    ]) {
      await store.createChild(
        childHeader(id, parentSession: rootId, subagentId: sub, depth: 1),
      );
      await store.append(
        SessionId(id),
        userRecord('cccccccc', null, 'sub task'),
      );
    }

    final page = await store.list();
    final fresh = await storeAt(root).list();

    expect(page.items.map((s) => s.id.value), [rootId]);
    expect(fresh.items.map((s) => s.id.value), [rootId]);
    final index = File('$root/index.json').readAsStringSync();
    expect(index, contains(rootId));
    expect(index, isNot(contains(childId)));
    expect(index, isNot(contains(grandId)));
    expect(index, isNot(contains('subagents')));
  });

  group('openChild (задача 4.4, D45 Т7)', () {
    Future<String> seed() async {
      final store = storeAt(root);
      await store.create(headerOf(rootId));
      final address = await store.createChild(
        childHeader(
          childId,
          parentSession: rootId,
          subagentId: 'sub_k3f9a1c2',
          depth: 1,
        ),
      );
      await store.append(
        const SessionId(childId),
        userRecord('cccccccc', null, 'sub task'),
      );
      await store.close(const SessionId(childId));
      await store.close(const SessionId(rootId));
      return address;
    }

    test('новый экземпляр хранилища после перезапуска открывает журнал по '
        'адресу и дописывает в него по id ребёнка', () async {
      final address = await seed();
      final fresh = storeAt(root);

      final snapshot = await fresh.openChild(
        address,
        rootSessionId: const SessionId(rootId),
      );
      await fresh.append(
        const SessionId(childId),
        userRecord('dddddddd', 'cccccccc', 'after heal'),
      );
      await fresh.close(const SessionId(childId));

      expect(snapshot.header.parent?.depth, 1);
      expect(snapshot.records.map((r) => r.id), ['cccccccc']);
      final again = await storeAt(
        root,
      ).openChild(address, rootSessionId: const SessionId(rootId));
      expect(again.records.map((r) => r.id), ['cccccccc', 'dddddddd']);
    });

    test('адрес вне subagents/ или с выходом наверх — SessionNotFound, '
        'чужой файл не читается', () async {
      await seed();
      final store = storeAt(root);

      for (final bad in [
        '../outside/2026-10-21T08-00-00-000Z_$childId.jsonl',
        '/etc/2026-10-21T08-00-00-000Z_$childId.jsonl',
        '${cwdSlug('/work/demo')}/2026-10-21T08-00-00-000Z_$rootId.jsonl',
        'index.json',
      ]) {
        await expectLater(
          store.openChild(bad, rootSessionId: const SessionId(rootId)),
          throwsA(isA<SessionNotFound>()),
          reason: bad,
        );
      }
    });

    test('заголовок с другим id, чем в имени файла, — SessionNotFound '
        '(журнал подложен)', () async {
      final address = await seed();
      final file = File('$root/$address');
      final text = file.readAsStringSync().replaceFirst(
        '"id":"$childId"',
        '"id":"01JB8Q3A1D2E3F4G5H6J7K8M9Z"',
      );
      file.writeAsStringSync(text);

      await expectLater(
        storeAt(
          root,
        ).openChild(address, rootSessionId: const SessionId(rootId)),
        throwsA(isA<SessionNotFound>()),
      );
    });

    test('symlink внутри subagents/ наружу корня — SessionNotFound, внешний '
        'файл не читается и не переписывается', () async {
      final address = await seed();
      final outside = tempRoot('jsonl_outside_', addTearDown);
      final target = File('$outside/stolen_$childId.jsonl')
        ..writeAsStringSync(File('$root/$address').readAsStringSync());
      final before = target.readAsBytesSync();
      File('$root/$address').deleteSync();
      Link('$root/$address').createSync(target.path);

      await expectLater(
        storeAt(
          root,
        ).openChild(address, rootSessionId: const SessionId(rootId)),
        throwsA(isA<SessionNotFound>()),
      );
      expect(target.readAsBytesSync(), before);
    });
  });

  // Change `add-subagents-and-tasks`, D47 Т5: реплей дерева читает журнал
  // потомка, который может ещё писать потомок, переживший `cancel_grace`;
  // группа охраняет `openChildReadOnly` (чтение без записи).
  group('openChildReadOnly (задача 5.1, D47 Т5)', () {
    Future<String> seed() async {
      final store = storeAt(root);
      await store.create(headerOf(rootId));
      final address = await store.createChild(
        childHeader(
          childId,
          parentSession: rootId,
          subagentId: 'sub_k3f9a1c2',
          depth: 1,
        ),
      );
      await store.append(
        const SessionId(childId),
        userRecord('cccccccc', null, 'sub task'),
      );
      await store.append(
        const SessionId(childId),
        userRecord('dddddddd', 'cccccccc', 'more'),
      );
      await store.close(const SessionId(childId));
      await store.close(const SessionId(rootId));
      return address;
    }

    /// Все файлы под корнем хранилища: путь → байты.
    Map<String, List<int>> filesOf() => {
      for (final f in Directory(root).listSync(recursive: true))
        if (f is File) f.path: f.readAsBytesSync(),
    };

    test('оборванная последняя строка пропускается, файл остаётся побайтно '
        'прежним и карантина не появляется', () async {
      final address = await seed();
      final file = File('$root/$address');
      file.writeAsStringSync(
        '{"type":"message","id":"eeeeeeee","parentId":"dddd',
        mode: FileMode.append,
      );
      final before = filesOf();

      final snapshot = await storeAt(
        root,
      ).openChildReadOnly(address, rootSessionId: const SessionId(rootId));

      expect(snapshot.records.map((r) => r.id), ['cccccccc', 'dddddddd']);
      expect(filesOf(), before, reason: 'ни ремонта, ни .corrupt на диске');
    });

    test('повреждённая строка в середине пропускается в снимке, а файл не '
        'переписывается', () async {
      final address = await seed();
      final file = File('$root/$address');
      final lines = file.readAsLinesSync();
      file.writeAsStringSync(
        '${[lines[0], lines[1], 'not json at all', lines[2]].join('\n')}\n',
      );
      final before = filesOf();

      final snapshot = await storeAt(
        root,
      ).openChildReadOnly(address, rootSessionId: const SessionId(rootId));

      expect(snapshot.records.map((r) => r.id), contains('cccccccc'));
      expect(filesOf(), before);
    });

    test('путь не регистрируется для записи: в новом экземпляре append по id '
        'ребёнка после чтения — SessionNotFound, а не запись в журнал '
        'потомка', () async {
      final address = await seed();
      final fresh = storeAt(root);
      await fresh.openChildReadOnly(
        address,
        rootSessionId: const SessionId(rootId),
      );
      final before = filesOf();

      await expectLater(
        fresh.append(
          const SessionId(childId),
          userRecord('eeeeeeee', 'dddddddd', 'must not land'),
        ),
        throwsA(isA<SessionNotFound>()),
      );
      expect(filesOf(), before);
    });

    test('экземпляр, который пишет журнал потомка, продолжает писать после '
        'чтения: дескриптор не закрыт и запись не потеряна', () async {
      final store = storeAt(root);
      await store.create(headerOf(rootId));
      final address = await store.createChild(
        childHeader(
          childId,
          parentSession: rootId,
          subagentId: 'sub_k3f9a1c2',
          depth: 1,
        ),
      );
      await store.append(
        const SessionId(childId),
        userRecord('cccccccc', null, 'sub task'),
      );

      final snapshot = await store.openChildReadOnly(
        address,
        rootSessionId: const SessionId(rootId),
      );
      await store.append(
        const SessionId(childId),
        userRecord('dddddddd', 'cccccccc', 'after read'),
      );
      await store.close(const SessionId(childId));

      expect(snapshot.records.map((r) => r.id), ['cccccccc']);
      expect(
        File('$root/$address').readAsLinesSync(),
        hasLength(3),
        reason: 'заголовок и две записи, без дублей и потерь',
      );
    });

    test(
      'адрес вне subagents/ или с выходом наверх — SessionNotFound',
      () async {
        await seed();
        final store = storeAt(root);

        for (final bad in [
          '../outside/2026-10-21T08-00-00-000Z_$childId.jsonl',
          '/etc/2026-10-21T08-00-00-000Z_$childId.jsonl',
          '${cwdSlug('/work/demo')}/2026-10-21T08-00-00-000Z_$rootId.jsonl',
          'index.json',
        ]) {
          await expectLater(
            store.openChildReadOnly(
              bad,
              rootSessionId: const SessionId(rootId),
            ),
            throwsA(isA<SessionNotFound>()),
            reason: bad,
          );
        }
      },
    );

    test('журнал чужого корня — SessionNotFound', () async {
      final address = await seed();

      await expectLater(
        storeAt(root).openChildReadOnly(
          address,
          rootSessionId: const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0S'),
        ),
        throwsA(isA<SessionNotFound>()),
      );
    });

    test(
      'заголовок с другим id, чем в имени файла, — SessionNotFound',
      () async {
        final address = await seed();
        final file = File('$root/$address');
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
            '"id":"$childId"',
            '"id":"01JB8Q3A1D2E3F4G5H6J7K8M9Z"',
          ),
        );

        await expectLater(
          storeAt(
            root,
          ).openChildReadOnly(address, rootSessionId: const SessionId(rootId)),
          throwsA(isA<SessionNotFound>()),
        );
      },
    );

    test('symlink внутри subagents/ наружу корня — SessionNotFound, внешний '
        'файл не читается и не меняется', () async {
      final address = await seed();
      final outside = tempRoot('jsonl_outside_ro_', addTearDown);
      final target = File('$outside/stolen_$childId.jsonl')
        ..writeAsStringSync(File('$root/$address').readAsStringSync());
      final before = target.readAsBytesSync();
      File('$root/$address').deleteSync();
      Link('$root/$address').createSync(target.path);

      await expectLater(
        storeAt(
          root,
        ).openChildReadOnly(address, rootSessionId: const SessionId(rootId)),
        throwsA(isA<SessionNotFound>()),
      );
      expect(target.readAsBytesSync(), before);
    });
  });
}
