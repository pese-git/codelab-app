import 'package:codelab_agent_core/codelab_agent_core.dart';
// Детский вариант списка — внутренний тип ядра: его создаёт фабрика дочерней
// сессии, хосты и клиенты его не видят (D36 Т2, Т7).
import 'package:codelab_agent_core/src/subagents/subagent_task_list.dart';
import 'package:test/test.dart';

import '../executor_harness.dart' show session;
import 'task_harness.dart';

/// Детский вариант инструментов списка задач на общем списке корня
/// (agent-tools «Инструменты списка задач», детский вариант, сценарий
/// «Потомок меняет чужой пункт»; TSK-4; design.md change
/// `add-subagents-and-tasks`, D35, D36 Т7;
/// `agent-core/17-16-task-list.md` §17.16.4).
///
/// Красные до задачи 2.4a: нет `SubagentTaskList` — обёртки над `TaskList`
/// корня с актором `SubagentActor(id)`, проверкой TSK-4 и цепочкой
/// `toolCallId` глубины 1. Инструменты `task_*` — те же классы, что у
/// корня; различается только `ToolServices.tasks`.
///
/// Фиксируемый API: `SubagentTaskList({required TaskList root, required
/// String subagentId, required String parentToolCallId})`. Пункт ребёнку
/// назначает корень (`assign` — итерация 4), поэтому в тесте пункт с `owner`
/// ребёнка создаётся прямо в списке корня.
void main() {
  const childId = 'sub_a1';
  const otherId = 'sub_b2';
  const deniedText = 'Subagents may change only the status of their own tasks.';

  late SessionTaskList root;
  late List<TaskListChanged> published;
  late TaskHarness h;

  setUp(() async {
    published = [];
    root = SessionTaskList(
      // Владельцы-дети известны списку корня (isKnownOwner, задача 2.4).
      isKnownOwner: (owner) =>
          owner == TaskOwner.main ||
          owner.value == childId ||
          owner.value == otherId,
      publish: (items, change) =>
          published.add(TaskListChanged(session, items: items, change: change)),
    );
    await root.apply(
      const CreateTask(subject: 'Mine', owner: TaskOwner(childId)),
      const MainActor(),
    );
    await root.apply(const CreateTask(subject: 'Main item'), const MainActor());
    await root.apply(
      const CreateTask(subject: 'Sibling item', owner: TaskOwner(otherId)),
      const MainActor(),
    );
    published.clear();
    h = await TaskHarness.create(
      list: SubagentTaskList(
        root: root,
        subagentId: childId,
        parentToolCallId: 'call_3',
      ),
    );
  });

  test(
    'сценарий «Потомок меняет чужой пункт»: status у пункта main и '
    'subject у своего — обе ошибки TSK-4; список и события не изменились',
    () async {
      final foreign = await h.run('task_update', {
        'id': '2',
        'status': 'completed',
      });
      final renamed = await h.run('task_update', {'id': '1', 'subject': 'New'});

      expect(textOf(foreign), deniedText);
      expect(foreign.message.isError, isTrue);
      expect(textOf(renamed), deniedText);
      expect(renamed.message.isError, isTrue);
      expect(
        [for (final i in root.items) i.subject],
        ['Mine', 'Main item', 'Sibling item'],
      );
      expect(published, isEmpty);
    },
  );

  test('пункт соседнего ребёнка и смена владельца или зависимостей — та же '
      'ошибка', () async {
    for (final args in [
      {'id': '3', 'status': 'completed'},
      {'id': '1', 'owner': 'main'},
      {
        'id': '1',
        'blocked_by': ['2'],
      },
      {'id': '1', 'priority': 'high'},
      {'id': '1', 'description': 'x'},
    ]) {
      final outcome = await h.run('task_update', args);

      expect(textOf(outcome), deniedText, reason: '$args');
    }
    expect(published, isEmpty);
  });

  test('status своего пункта проходит: операция от имени ребёнка, '
      'toolCallId — цепочка «вызов agent корня/вызов ребёнка»', () async {
    final outcome = await h.run('task_update', {
      'id': '1',
      'status': 'completed',
    });

    expect(outcome.message.isError, isFalse);
    expect(root.items.first.status, TaskStatus.completed);
    final change = published.single.change;
    expect(change.actor, const SubagentActor(childId));
    expect(change.op, 'update');
    expect(change.toolCallId, 'call_3/call_1');
  });

  test('task_list и task_get ребёнка читают весь список корня, владельцы '
      'видны', () async {
    final listing = await h.text('task_list', const {});
    final got = await h.text('task_get', {'id': '2'});

    expect(listing, contains('Mine'));
    expect(listing, contains('Main item'));
    expect(listing, contains('(owner: sub_a1)'));
    expect(got, contains('Task #2: Main item'));
  });

  test('чужой id в task_get — обычная ошибка списка, не TSK-4', () async {
    final text = await h.text('task_get', {'id': '9'});

    expect(text, startsWith('Unknown task #9.'));
  });
}
