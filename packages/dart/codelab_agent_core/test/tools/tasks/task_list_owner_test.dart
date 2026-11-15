import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
// Детский вариант списка — внутренний тип ядра: его создаёт фабрика дочерней
// сессии, хосты и клиенты его не видят (D36 Т2, Т7).
import 'package:codelab_agent_core/src/subagents/subagent_task_list.dart';
import 'package:test/test.dart';

import '../../subagents/subagent_rig.dart';
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

  // Итерация 4, задача 4.1 (agent-tools «Инструменты списка задач»,
  // сценарии «Назначение пункта ребёнку» и «Повторное назначение пункта»;
  // TSK-4; design.md change `add-subagents-and-tasks`, D45 Т8, D46 п. 3;
  // `agent-core/17-16-task-list.md` §17.16.4). Красные до задачи 4.5: ядро
  // не выполняет операцию `assign` при получении слота и не передаёт ребёнку
  // строку `Your task:`.
  group('назначение пункта ребёнку (операция assign)', () {
    List<(String, String, Map<String, Object?>)> twoItems() => [
      ('t1', 'task_create', {'subject': 'First item'}),
      ('t2', 'task_create', {'subject': 'Parser work'}),
    ];

    List<Map<String, Object?>> journalLines(SubagentRig rig) => [
      for (final line in const LineSplitter().convert(rig.rootJournal))
        jsonDecode(line) as Map<String, Object?>,
    ];

    test('сценарий «Назначение пункта ребёнку»: TaskListChanged(assign) без '
        'toolCallId приходит раньше SubagentStarted и до первого запроса '
        'ребёнка к модели, пункт — in_progress с владельцем-ребёнком; '
        'системный промпт ребёнка содержит строку Your task', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            multiCallStep(twoItems()),
            oneCallStep('c1', 'agent', agentArgs('kid job', task: '2')),
            replyStep('done'),
          ],
          'kid job': [replyStep('kid report')],
        },
      );
      await rig.open();
      final seen = <String>[];
      var kidRequestsAtAssign = -1;
      rig.session.events.listen((e) {
        if (e is TaskListChanged && e.change.op == 'assign') {
          seen.add('assign');
          kidRequestsAtAssign = rig.requestsOf('kid job').length;
        } else if (e is SubagentStarted) {
          seen.add('started');
        }
      });

      await rig.run('go');

      expect(seen, ['assign', 'started']);
      expect(kidRequestsAtAssign, 0);
      final kid = rig.eventsOf<SubagentStarted>().single.subagentId;
      final assign = rig
          .eventsOf<TaskListChanged>()
          .singleWhere((e) => e.change.op == 'assign')
          .change;
      expect(assign.actor, const MainActor());
      expect(assign.toolCallId, isNull);
      final item = assign.changed.single;
      expect(item.id, '2');
      expect(item.owner, TaskOwner(kid));
      expect(item.status, TaskStatus.inProgress);
      expect(
        rig.requestsOf('kid job').first.systemPrompt,
        contains('Your task: #2 Parser work'),
      );
      // Запись task журнала корня — как у остальных операций, от main.
      final record = journalLines(
        rig,
      ).singleWhere((r) => r['type'] == 'task' && r['op'] == 'assign');
      expect(record['actor'], 'main');
    });

    test('сценарий «Повторное назначение пункта»: ребёнок B получает слот с '
        'тем же пунктом — владелец B без проверки прежнего; update ребёнка A '
        'отклонён с reason owner', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            multiCallStep(twoItems()),
            multiCallStep([
              ('a1', 'agent', agentArgs('alpha', task: '2')),
              ('a2', 'agent', agentArgs('beta', task: '2')),
            ]),
            replyStep('done'),
          ],
          'alpha': [
            oneCallStep('u1', 'task_update', {
              'id': '2',
              'status': 'completed',
            }, delayMs: 10),
            replyStep('alpha done'),
          ],
          'beta': [replyStep('beta done', delayMs: 20)],
        },
      );
      await rig.open();

      final turn = rig.run('go');
      await pumpUntil(
        () =>
            rig
                .eventsOf<TaskListChanged>()
                .where((e) => e.change.op == 'assign')
                .length ==
            2,
        reason: 'both children must receive the item in turn',
      );
      await rig.clock.elapse(const Duration(milliseconds: 10));
      await rig.clock.elapse(const Duration(milliseconds: 20));
      await turn;

      final started = rig.eventsOf<SubagentStarted>();
      final alpha = started.singleWhere((s) => s.parentToolCallId == 'a1');
      final beta = started.singleWhere((s) => s.parentToolCallId == 'a2');
      final assigns = [
        for (final e in rig.eventsOf<TaskListChanged>())
          if (e.change.op == 'assign') e.change.changed.single.owner,
      ];
      expect(assigns, [
        TaskOwner(alpha.subagentId),
        TaskOwner(beta.subagentId),
      ]);
      expect(
        rig.session.tasks.items.singleWhere((i) => i.id == '2').owner,
        TaskOwner(beta.subagentId),
        reason: 'последнее назначение побеждает',
      );
      final last = rig.requestsOf('alpha').last;
      expect(
        resultText(last, 'u1'),
        'Subagents may change only the status of their own tasks.',
      );
      expect(resultIsError(last, 'u1'), isTrue);
      final rejected = rig.logger.eventsOf('task.rejected').single;
      expect(rejected.fields['reason'], 'owner');
    });
  });

  // Характеризующий, зелёный сразу (D45 Т3): префикс цепочки задаёт тот, кто
  // создаёт список; операция внука строит id как `<префикс>/<id вызова>`.
  test('цепочка toolCallId операции внука: префикс из двух сегментов даёт '
      '«вызов agent корня/вызов agent ребёнка/вызов внука»', () async {
    final deep = SessionTaskList(
      isKnownOwner: (owner) => owner.value == 'sub_deep',
      publish: (items, change) =>
          published.add(TaskListChanged(session, items: items, change: change)),
    );
    await deep.apply(
      const CreateTask(subject: 'Deep item', owner: TaskOwner('sub_deep')),
      const MainActor(),
    );
    published.clear();
    final harness = await TaskHarness.create(
      list: SubagentTaskList(
        root: deep,
        subagentId: 'sub_deep',
        parentToolCallId: 'call_3/call_2',
      ),
    );

    await harness.run('task_update', {'id': '1', 'status': 'completed'});

    expect(published.single.change.toolCallId, 'call_3/call_2/call_1');
  });
}
