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
/// Красные до задачи 2.7: у порта нет `createChild`, у `SessionHeader` — поля
/// `parent`. Общий контракт порта (в том числе группа `createChild`) —
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
}
