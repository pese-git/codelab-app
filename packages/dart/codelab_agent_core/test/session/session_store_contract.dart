import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Общий контрактный набор порта `SessionStore` (agent-sessions «Порт
/// SessionStore», «Список сессий и автоматический заголовок»): его
/// проходят `MemorySessionStore` и `JsonlSessionStore`.
///
/// [make] создаёт пустое хранилище перед каждым тестом.
void sessionStoreContract(Future<SessionStore> Function() make) {
  late SessionStore store;

  setUp(() async => store = await make());

  SessionHeader headerOf(String id, String cwd, DateTime created) =>
      SessionHeader(
        id: SessionId(id),
        cwd: cwd,
        created: created,
        agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
      );

  MessageRecord userRecord(
    String id,
    String? parent,
    DateTime at,
    String text,
  ) => MessageRecord(
    id: id,
    parentId: parent,
    timestamp: at,
    message: UserMessage([TextContent(text)], timestamp: at),
  );

  final t0 = DateTime.utc(2026, 10, 21, 8);

  test('create, append and open give the records in order', () async {
    const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0A');
    await store.create(headerOf(id.value, '/work/demo', t0));
    await store.append(id, userRecord('aaaaaaaa', null, t0, 'one'));
    await store.append(
      id,
      userRecord('bbbbbbbb', 'aaaaaaaa', t0, 'two'),
      durable: true,
    );

    final snapshot = await store.open(id);

    expect(snapshot.header.id, id);
    expect(snapshot.header.cwd, '/work/demo');
    expect(snapshot.records.map((r) => r.id), ['aaaaaaaa', 'bbbbbbbb']);
    expect(snapshot.leafId, 'bbbbbbbb');
    expect(snapshot.repair.isClean, isTrue);
  });

  test('a fresh journal has no records and no leaf', () async {
    const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0B');
    await store.create(headerOf(id.value, '/work/demo', t0));

    final snapshot = await store.open(id);

    expect(snapshot.records, isEmpty);
    expect(snapshot.leafId, isNull);
  });

  test('a second create with the same id is a StateError', () async {
    const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
    await store.create(headerOf(id.value, '/work/demo', t0));

    await expectLater(
      store.create(headerOf(id.value, '/work/demo', t0)),
      throwsStateError,
    );
  });

  test('open of an unknown session is SessionNotFound', () async {
    await expectLater(
      store.open(const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0Z')),
      throwsA(isA<SessionNotFound>()),
    );
  });

  test('close keeps the journal; flush completes', () async {
    const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0D');
    await store.create(headerOf(id.value, '/work/demo', t0));
    await store.append(id, userRecord('aaaaaaaa', null, t0, 'one'));
    await store.flush(id);
    await store.close(id);

    await store.append(id, userRecord('bbbbbbbb', 'aaaaaaaa', t0, 'two'));

    expect((await store.open(id)).records, hasLength(2));
  });

  group('list', () {
    Future<void> seed() async {
      final sessions = [
        ('01JB8Q2W6R9T3M5K7N1P4X8Z01', '/a', 1),
        ('01JB8Q2W6R9T3M5K7N1P4X8Z02', '/a', 3),
        ('01JB8Q2W6R9T3M5K7N1P4X8Z03', '/b', 2),
      ];
      for (final (id, cwd, minute) in sessions) {
        await store.create(headerOf(id, cwd, t0));
        await store.append(
          SessionId(id),
          userRecord(
            'aaaaaaaa',
            null,
            t0.add(Duration(minutes: minute)),
            'task in $cwd',
          ),
        );
      }
    }

    test('filters by cwd, the newest first', () async {
      await seed();

      final page = await store.list(cwd: '/a');

      expect(page.items.map((s) => s.id.value), [
        '01JB8Q2W6R9T3M5K7N1P4X8Z02',
        '01JB8Q2W6R9T3M5K7N1P4X8Z01',
      ]);
      expect(page.items.first.title, 'task in /a');
      expect(page.items.first.cwd, '/a');
      expect(page.nextCursor, isNull);
    });

    test('without cwd — all sessions by updatedAt', () async {
      await seed();

      final page = await store.list();

      expect(page.items.map((s) => s.id.value.substring(24)), [
        '02',
        '03',
        '01',
      ]);
    });

    test('equal updatedAt — the greater id first', () async {
      for (final id in [
        '01JB8Q2W6R9T3M5K7N1P4X8Z0X',
        '01JB8Q2W6R9T3M5K7N1P4X8Z0Y',
      ]) {
        await store.create(headerOf(id, '/c', t0));
      }

      final page = await store.list(cwd: '/c');

      expect(page.items.map((s) => s.id.value.substring(24)), ['0Y', '0X']);
    });

    test('the cursor continues strictly after the page', () async {
      await seed();

      final first = await store.list(pageSize: 2);
      final second = await store.list(pageSize: 2, cursor: first.nextCursor);

      expect(first.items, hasLength(2));
      expect(first.nextCursor, isNotNull);
      expect(second.items.map((s) => s.id.value.substring(24)), ['01']);
      expect(second.nextCursor, isNull);
    });

    test('a broken cursor is InvalidCursor', () async {
      await expectLater(
        store.list(cursor: 'not-a-cursor'),
        throwsA(isA<InvalidCursor>()),
      );
    });
  });
}
