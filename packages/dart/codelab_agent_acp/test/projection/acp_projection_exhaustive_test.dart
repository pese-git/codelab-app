import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/event_projection.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Проекция `TaskListChanged` в `plan` (ACP-6): исчерпывающая строка таблицы
/// §13.7 для списка задач, включая восстановление из новой ветки.
///
/// Почему отдельный файл: `every_agent_event_is_projected_test.dart` сверяет
/// таблицу `projectionTable` с иерархией `AgentEvent`, а здесь проверяется
/// содержимое кадра. Источники: agent-acp-server «Проекция субагентов и списка
/// задач» («Список новой ветки»), design.md change `add-subagents-and-tasks`
/// D29, §17.16.5–§17.16.6 документа ядра; задача 1.1 (красный тест) и 1.5a.
///
/// Красный до задач 1.2 и 1.5a: `TaskListChanged`, `TaskItem` и `TaskChange`
/// вводит ядро (1.2, 1.2a), проекцию — адаптер (1.5, 1.5a). Формы
/// конструкторов взяты из §17.16.2; при расхождении с реализацией ядра
/// поправляются здесь, смысл проверок (кадр `plan`, `_meta.codelab.task`,
/// пустой список) остаётся.
void main() {
  const s = SessionId('sess_1');

  List<Map<String, Object?>> project(AgentEvent event) => [
    for (final update in projectEvent(event, configOptions: () => const []))
      update.toJson(),
  ];

  TaskItem item(
    String id,
    String subject, {
    TaskStatus status = TaskStatus.pending,
    TaskPriority priority = TaskPriority.medium,
    TaskOwner owner = TaskOwner.main,
    List<String> blockedBy = const [],
    String? description,
  }) => TaskItem(
    id: id,
    subject: subject,
    description: description,
    status: status,
    priority: priority,
    owner: owner,
    blockedBy: blockedBy,
  );

  TaskListChanged restore(
    List<TaskItem> items, {
    List<String> deleted = const [],
  }) => TaskListChanged(
    s,
    items: items,
    change: TaskChange(
      op: 'restore',
      actor: const MainActor(),
      changed: items,
      deleted: deleted,
    ),
  );

  group('TaskListChanged → plan', () {
    // agent-acp-server «Список новой ветки»: ядро публикует `restore` с
    // пустым списком, затем с пунктами `#1`, `#4`; клиент получает пустой
    // `plan` (иначе он продолжил бы показывать список покинутой ветки,
    // `11-Agent Plan.md`: клиент заменяет план целиком), затем `plan` с двумя
    // entries и `_meta.codelab.task.id` "1", "4".
    test('op restore with an empty list is a plan with no entries', () {
      expect(project(restore(const [], deleted: const ['1', '2'])), [
        {'sessionUpdate': 'plan', 'entries': <Object?>[]},
      ]);
    });

    test('op restore with items #1 and #4 is a plan with both of them', () {
      final frames = project(
        restore([
          item(
            '1',
            'Read the failing test',
            status: TaskStatus.completed,
            priority: TaskPriority.high,
          ),
          item(
            '4',
            'Fix the parser',
            status: TaskStatus.inProgress,
            owner: const TaskOwner('sub_k3f9a1c2'),
            blockedBy: const ['1'],
          ),
        ]),
      );

      expect(frames, [
        {
          'sessionUpdate': 'plan',
          'entries': [
            {
              'content': 'Read the failing test',
              'priority': 'high',
              'status': 'completed',
              '_meta': {
                'codelab': {
                  'task': {'id': '1', 'owner': 'main', 'blockedBy': <String>[]},
                },
              },
            },
            {
              'content': 'Fix the parser',
              'priority': 'medium',
              'status': 'in_progress',
              '_meta': {
                'codelab': {
                  'task': {
                    'id': '4',
                    'owner': 'sub_k3f9a1c2',
                    'blockedBy': ['1'],
                  },
                },
              },
            },
          ],
        },
      ]);
    });

    // §17.16.5: `restore` — не особый кадр, а тот же `plan`, что у `create`
    // и `update` (D29: «клиенту — обычный plan со всем списком»).
    test('op restore and op create produce the same frame', () {
      final items = [
        item('1', 'A'),
        item('2', 'B', blockedBy: const ['1']),
      ];
      final created = TaskListChanged(
        s,
        items: items,
        change: TaskChange(
          op: 'create',
          actor: const MainActor(),
          changed: [items.last],
          deleted: const [],
        ),
      );

      expect(project(restore(items)), project(created));
    });

    // §17.16.5: `description` в ACP не уходит; порядок entries — порядок
    // списка (создания), а не id.
    test('description stays out of the frame, the order is the list order', () {
      final frames = project(
        restore([
          item('4', 'Later id first', description: 'long text'),
          item('1', 'Earlier id second'),
        ]),
      );

      final entries = (frames.single['entries']! as List).cast<Map>();
      expect(entries.map((e) => e['content']), [
        'Later id first',
        'Earlier id second',
      ]);
      expect(entries.every((e) => !e.containsKey('description')), isTrue);
      expect(frames.toString(), isNot(contains('long text')));
    });

    // ACP-6: строка таблицы §13.7 существует и называет `plan`.
    test('the projection table has a plan row for TaskListChanged', () {
      expect(projectionTable[TaskListChanged], contains('plan'));
    });

    // Тип кадра — настоящий `SessionUpdate.plan` кодека, а не сырой JSON:
    // все сообщения ACP — типизированные модели (AGENTS.md §7).
    test('the frame is a typed SessionUpdate', () {
      final updates = projectEvent(
        restore([item('1', 'A')]),
        configOptions: () => const [],
      );

      expect(updates.single, isA<acp.SessionUpdate>());
      expect(updates.single.toJson()['sessionUpdate'], 'plan');
    });
  });
}
