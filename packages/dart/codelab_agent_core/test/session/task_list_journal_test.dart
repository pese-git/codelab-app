import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import 'journal_lines.dart';

/// Список задач и журнал (agent-sessions «Список задач из журнала»:
/// «Список после загрузки», «Счётчик id по всем веткам»; «Список задач
/// следует ветке журнала»: «Восстановление при открытии»; TSK-3, TSK-6,
/// D29; `agent-core/17-16-task-list.md` §17.16.6).
///
/// Красные до задачи 1.3: нет `TaskRecord`, `buildTaskList`,
/// `AgentSession.tasks` и восстановления `TaskList` при `open`.
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  SessionSnapshot snapshot(List<String> lines) => parseSessionLines(
    journal([header(cwd: '/proj'), ...lines]),
    id: id,
  ).snapshot;

  List<String> idsOf(List<TaskItem> items) => [for (final i in items) i.id];

  group('buildTaskList: свёртка активной ветки', () {
    test('пустой журнал: пустой список, следующий id 1', () {
      final state = buildTaskList(snapshot([]));

      expect(state.items, isEmpty);
      expect(state.nextId, 1);
    });

    test('task вставляет и заменяет items, убирает deleted', () {
      final s = snapshot([
        user('u1', null),
        taskRecord(
          't1',
          'u1',
          items: [taskItem('1', 'a'), taskItem('2', 'b'), taskItem('3', 'c')],
        ),
        taskRecord(
          't2',
          't1',
          op: 'update',
          items: [taskItem('2', 'b2', status: 'in_progress')],
        ),
        taskRecord('t3', 't2', op: 'delete', deleted: ['2']),
      ]);

      final state = buildTaskList(s);

      expect(idsOf(state.items), ['1', '3']);
      expect(state.nextId, 4, reason: 'удалённый #2 тоже был выдан');
    });

    test('delete с очисткой blocked_by: changed заменяет снимок', () {
      final s = snapshot([
        taskRecord(
          't1',
          null,
          items: [
            taskItem('1', 'a'),
            taskItem('2', 'b', blockedBy: ['1']),
          ],
        ),
        taskRecord(
          't2',
          't1',
          op: 'delete',
          items: [taskItem('2', 'b')],
          deleted: ['1'],
        ),
      ]);

      final state = buildTaskList(s);

      expect(idsOf(state.items), ['2']);
      expect(state.items.single.blockedBy, isEmpty);
    });

    test('порядок пунктов — порядок создания, а не последнего изменения', () {
      final s = snapshot([
        taskRecord('t1', null, items: [taskItem('1', 'a'), taskItem('2', 'b')]),
        taskRecord(
          't2',
          't1',
          op: 'update',
          items: [taskItem('1', 'a', status: 'completed')],
        ),
      ]);

      expect(idsOf(buildTaskList(s).items), ['1', '2']);
    });

    test('запись plan старого формата: пункты "1"…"n", owner main (D12)', () {
      final s = snapshot([
        plan('p1', null, ['read', 'fix', 'run']),
      ]);

      final state = buildTaskList(s);

      expect(idsOf(state.items), ['1', '2', '3']);
      expect([for (final i in state.items) i.subject], ['read', 'fix', 'run']);
      expect(
        state.items.every(
          (i) =>
              i.owner == TaskOwner.main &&
              i.blockedBy.isEmpty &&
              i.priority == TaskPriority.high &&
              i.status == TaskStatus.pending,
        ),
        isTrue,
        reason: 'приоритет и статус берутся как есть (из plan-фикстуры)',
      );
      expect(state.nextId, 4);
    });

    test('plan заменяет весь список, task после него продолжает', () {
      final s = snapshot([
        taskRecord('t1', null, items: [taskItem('1', 'old')]),
        plan('p1', 't1', ['x', 'y']),
        taskRecord(
          't2',
          'p1',
          op: 'update',
          items: [taskItem('2', 'y', status: 'completed')],
        ),
      ]);

      final state = buildTaskList(s);

      expect(
        [for (final i in state.items) (i.id, i.subject)],
        [('1', 'x'), ('2', 'y')],
      );
      expect(state.items.last.status, TaskStatus.completed);
      expect(state.nextId, 3);
    });
  });

  // Сценарий «Счётчик id по всем веткам» (TSK-3, D29).
  group('buildTaskList: счётчик по всем веткам', () {
    /// Две ветки от `u1`: активная `B` (#1…#3) и покинутая `A` (#1…#5).
    /// Запись `leaf` возвращает лист на `B` после записей `A` (§8.4).
    SessionSnapshot twoBranches({List<String> abandoned = const []}) =>
        snapshot([
          user('u1', null),
          taskRecord(
            'tb',
            'u1',
            items: [
              taskItem('1', 'B one'),
              taskItem('2', 'B two'),
              taskItem('3', 'B three'),
            ],
          ),
          taskRecord(
            'ta',
            'u1',
            items: [for (var n = 1; n <= 5; n++) taskItem('$n', 'A $n')],
          ),
          ...abandoned,
          leaf('lf', 'ta', target: 'tb'),
        ]);

    test('items активной ветки, nextId по покинутой: 6', () {
      final state = buildTaskList(twoBranches());

      expect(idsOf(state.items), ['1', '2', '3']);
      expect(
        [for (final i in state.items) i.subject],
        ['B one', 'B two', 'B three'],
        reason: 'пункты покинутой ветки в список не попадают',
      );
      expect(state.nextId, 6);
    });

    test('deleted покинутой ветки тоже занимает id', () {
      final s = snapshot([
        user('u1', null),
        taskRecord('tb', 'u1', items: [taskItem('1', 'B')]),
        taskRecord('ta', 'u1', items: [taskItem('1', 'A')]),
        taskRecord('ta2', 'ta', op: 'delete', deleted: ['7']),
        leaf('lf', 'ta2', target: 'tb'),
      ]);

      expect(buildTaskList(s).nextId, 8);
    });

    test('запись plan покинутой ветки считается числом entries', () {
      final s = snapshot([
        user('u1', null),
        taskRecord('tb', 'u1', items: [taskItem('1', 'B')]),
        plan('pa', 'u1', ['a', 'b', 'c', 'd']),
        leaf('lf', 'pa', target: 'tb'),
      ]);

      final state = buildTaskList(s);

      expect(idsOf(state.items), ['1']);
      expect(state.nextId, 5);
    });
  });

  group('открытие сессии (AgentRuntime.loadSession)', () {
    Future<(CoreHarness, AgentSession)> open(
      MemorySessionStore store,
      List<Map<String, Object?>> steps,
    ) async {
      final h = CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        narrow: noExec,
        gate: FakeGate(),
        sessions: store,
        steps: steps,
      );
      final session = await h.core.runtime.loadSession(
        id,
        const SessionHostPorts(),
      );
      return (h, session);
    }

    /// Текст результата последнего вызова инструмента в запросе к модели.
    String lastResult(CoreHarness h) {
      final result = h.model.requests.last.messages
          .whereType<ToolResultMessage>()
          .last;
      return (result.content.single as TextContent).text;
    }

    // Сценарий «Список после загрузки».
    test(
      'создание трёх, удаление второго; после загрузки #1, #3, затем #4',
      () async {
        final store = MemorySessionStore();
        final first = CoreHarness.build(
          baseEnv: MemoryExecutionEnv(cwd: '/proj'),
          narrow: noExec,
          gate: FakeGate(),
          sessions: store,
          steps: [
            callStep('c1', 'task_create', {'subject': 'one'}),
            callStep('c2', 'task_create', {'subject': 'two'}),
            callStep('c3', 'task_create', {'subject': 'three'}),
            callStep('c4', 'task_update', {'id': '2', 'status': 'deleted'}),
            textStep('done'),
          ],
        );
        final created = await first.core.runtime.createSession(
          SessionSpec(cwd: '/proj'),
        );
        await created.prompt(const [TextContent('plan')]);
        final before = created.tasks.items;
        await first.core.runtime.dispose();

        final second = CoreHarness.build(
          baseEnv: MemoryExecutionEnv(cwd: '/proj'),
          narrow: noExec,
          gate: FakeGate(),
          sessions: store,
          steps: [
            callStep('c5', 'task_create', {'subject': 'four'}),
            textStep('ok'),
          ],
        );
        final loaded = await second.core.runtime.loadSession(
          created.id,
          const SessionHostPorts(),
        );

        expect(idsOf(loaded.tasks.items), ['1', '3']);
        expect(loaded.tasks.items, before, reason: 'TSK-6: список до = после');
        await loaded.prompt(const [TextContent('more')]);
        expect(lastResult(second), startsWith('Created task #4: four.'));
      },
    );

    // Сценарий «Счётчик id по всем веткам» на уровне открытия сессии.
    test('две ветки: список активной, следующий task_create даёт #6', () async {
      final store = MemorySessionStore()
        ..putText(
          id,
          journal([
            header(cwd: '/proj'),
            user('u1', null),
            taskRecord(
              'tb',
              'u1',
              items: [
                taskItem('1', 'B one'),
                taskItem('2', 'B two'),
                taskItem('3', 'B three'),
              ],
            ),
            taskRecord(
              'ta',
              'u1',
              items: [for (var n = 1; n <= 5; n++) taskItem('$n', 'A $n')],
            ),
            leaf('lf', 'ta', target: 'tb'),
          ]),
        );
      final (h, session) = await open(store, [
        callStep('c1', 'task_create', {'subject': 'six'}),
        textStep('ok'),
      ]);

      expect(
        [for (final i in session.tasks.items) i.subject],
        ['B one', 'B two', 'B three'],
      );
      await session.prompt(const [TextContent('go')]);

      expect(lastResult(h), startsWith('Created task #6: six.'));
    });

    // Сценарий «Восстановление при открытии».
    test('список равен buildTaskList ветки; событий и записей нет', () async {
      final text = journal([
        header(cwd: '/proj'),
        user('u1', null),
        taskRecord(
          't1',
          'u1',
          items: [
            taskItem('1', 'a'),
            taskItem('2', 'b', blockedBy: ['1']),
          ],
        ),
        taskRecord(
          't2',
          't1',
          op: 'update',
          items: [taskItem('1', 'a', status: 'completed')],
        ),
      ]);
      final store = MemorySessionStore()..putText(id, text);
      final expected = buildTaskList(parseSessionLines(text, id: id).snapshot);

      final (_, session) = await open(store, const []);
      final seen = <AgentEvent>[];
      session.events.listen(seen.add);
      await pumpEventQueue();

      expect(session.tasks.items, expected.items);
      expect(seen.whereType<TaskListChanged>(), isEmpty);
      expect(
        store.textOf(id),
        text,
        reason: 'открытие журнала ничего в него не пишет (TSK-1, TSK-6)',
      );
    });
  });
}
