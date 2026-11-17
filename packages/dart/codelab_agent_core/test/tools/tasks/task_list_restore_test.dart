import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/session_writer.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../../session/recording_store.dart';

/// `TaskList.restore` (agent-sessions «Список задач следует ветке журнала»:
/// «Восстановление с публикацией»; «Запись журнала из событий»:
/// «Восстановление списка не пишется»; TSK-1, TSK-3, D29;
/// `agent-core/17-16-task-list.md` §17.16.2, §17.16.6).
///
/// Красные до задач 1.2a и 1.3a: нет `SessionTaskList.restore`,
/// `TaskChange(op: restore)` и ветки `TaskListChanged` в `SessionWriter`.
void main() {
  const session = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  TaskItem item(
    String id,
    String subject, {
    List<String> blockedBy = const [],
  }) => TaskItem(id: id, subject: subject, blockedBy: blockedBy);

  late List<TaskListChanged> published;
  late SessionTaskList list;

  setUp(() {
    published = [];
    list = SessionTaskList(
      publish: (items, change) =>
          published.add(TaskListChanged(session, items: items, change: change)),
    );
  });

  // Сценарий «Восстановление с публикацией»: #1, #2, счётчик 6.
  test('restore([#1\'], nextId: 4, announce: true): один restore, deleted [2], '
      'следующий id 6', () async {
    await list.restore(
      [item('1', 'one'), item('2', 'two')],
      nextId: 6,
      announce: false,
    );
    published.clear();

    final replaced = item('1', 'one, other branch');
    await list.restore([replaced], nextId: 4, announce: true);

    final event = published.single;
    expect(event.items, [replaced]);
    expect(event.change.op, 'restore');
    expect(event.change.actor, isA<MainActor>());
    expect(event.change.changed, [replaced]);
    expect(event.change.deleted, ['2']);
    expect(list.items, [replaced]);

    await list.apply(CreateTask(subject: 'next'), const MainActor());
    expect(list.items.last.id, '6', reason: 'счётчик не убывает (TSK-3)');
  });

  test('announce: false ничего не публикует, но заменяет список', () async {
    await list.restore([item('1', 'one')], nextId: 2, announce: false);

    expect(published, isEmpty);
    expect(list.items, [item('1', 'one')]);
  });

  test(
    'announce: true публикует ровно один раз, в том числе пустой список',
    () async {
      await list.restore(const [], nextId: 1, announce: true);

      final event = published.single;
      expect(event.items, isEmpty);
      expect(event.change.op, 'restore');
      expect(event.change.changed, isEmpty);
      expect(event.change.deleted, isEmpty);
    },
  );

  test(
    'nextId меньше текущего счётчика не уменьшает его; больше — поднимает',
    () async {
      await list.restore([item('1', 'one')], nextId: 10, announce: false);
      await list.restore([item('1', 'one')], nextId: 2, announce: false);
      await list.apply(CreateTask(subject: 'a'), const MainActor());
      expect(list.items.last.id, '10');

      await list.restore(list.items, nextId: 20, announce: false);
      await list.apply(CreateTask(subject: 'b'), const MainActor());
      expect(list.items.last.id, '20');
    },
  );

  test('restore берёт тот же замок, что apply: ждёт идущую операцию', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    final locked = SessionTaskList(
      publish: (items, change) async {
        if (change.op == 'create') {
          started.complete();
          await release.future;
        }
      },
    );

    final applying = locked.apply(CreateTask(subject: 'a'), const MainActor());
    await started.future;
    var restored = false;
    final restoring = locked
        .restore([item('7', 'from branch')], nextId: 8, announce: false)
        .then((_) => restored = true);
    await pumpEventQueue();

    expect(restored, isFalse, reason: 'операция ещё публикуется под замком');

    release.complete();
    await applying;
    await restoring;

    expect(restored, isTrue);
    expect([for (final i in locked.items) i.id], ['7']);
  });

  group('SessionWriter', () {
    final at = DateTime.utc(2026, 10, 21, 8);
    late RecordingStore store;
    late SessionWriter writer;

    setUp(() async {
      store = RecordingStore();
      final header = SessionHeader(
        id: session,
        cwd: '/work/demo',
        created: at,
        agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
      );
      await store.create(header);
      writer = SessionWriter(
        store: store,
        snapshot: SessionSnapshot.empty(header),
        ids: SequentialIdGenerator(),
        clock: FakeClock(start: at),
        logger: RecordingLogger(),
        onFailure: (_) {},
      );
    });

    // Сценарий «Восстановление списка не пишется».
    test('TaskListChanged(restore) не пишет в журнал ничего', () async {
      final before = store.inner.textOf(session);
      await list.restore([item('1', 'one')], nextId: 2, announce: true);

      await writer.handle(published.single);

      expect(store.appended, isEmpty);
      expect(
        store.inner.textOf(session),
        before,
        reason: 'журнал побайтово не изменился (TSK-1, D29)',
      );
    });

    test(
      'TaskListChanged операции модели — одна запись task (TSK-1)',
      () async {
        await list.apply(
          CreateTask(subject: 'a', description: 'details'),
          const MainActor(),
        );

        await writer.handle(published.single);

        final record = store.appended.single.record as TaskRecord;
        expect(record.op, 'create');
        expect(record.actor, isA<MainActor>());
        expect(record.items.single.subject, 'a');
        expect(record.items.single.description, 'details');
        expect(record.deleted, isEmpty);
        expect(
          store.appended.single.durable,
          isFalse,
          reason: 'durable пишется у результата вызова, SES-9',
        );
      },
    );
  });
}
