import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/event_projection.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Проекция списка задач и событий субагентов в кадры ACP (ACP-6).
///
/// Почему отдельный файл: `every_agent_event_is_projected_test.dart` сверяет
/// таблицу `projectionTable` с иерархией `AgentEvent`, а здесь проверяется
/// содержимое кадра: `TaskListChanged` → `plan` (включая восстановление из
/// новой ветки), строки `Subagent*` и вызов `agent` (D24, D28). Источники:
/// agent-acp-server «Проекция субагентов и списка задач», design.md change
/// `add-subagents-and-tasks` D24, D28, D29, §17.16.5–§17.16.6 и §17.3.7
/// документов ядра; задачи 1.1, 1.5a, 2.1, 2.8.
///
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
        {
          'sessionUpdate': 'plan',
          'entries': <Object?>[],
          // «Список новой ветки без toolCallId» (D35): ключа toolCallId нет.
          '_meta': {
            'codelab': {
              'taskChange': {
                'op': 'restore',
                'actor': 'main',
                'changed': <String>[],
                'deleted': ['1', '2'],
              },
            },
          },
        },
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
          '_meta': {
            'codelab': {
              'taskChange': {
                'op': 'restore',
                'actor': 'main',
                'changed': ['1', '4'],
                'deleted': <String>[],
              },
            },
          },
        },
      ]);
    });

    // §17.16.5: `restore` — не особый кадр, а тот же `plan`, что у `create`
    // и `update` (D29: «клиенту — обычный plan со всем списком»).
    test('op restore and op create produce the same entries', () {
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

      expect(
        project(restore(items)).single['entries'],
        project(created).single['entries'],
      );
    });

    // agent-acp-server «Список задач в ходе», D35: операция вызова `task_*`
    // несёт `toolCallId`, `changed` и `deleted` — id пунктов, а не снимки.
    test('a task_* operation carries taskChange with toolCallId', () {
      final items = [item('1', 'A'), item('2', 'B')];
      final event = TaskListChanged(
        s,
        items: [items.first],
        change: TaskChange(
          op: 'delete',
          actor: const MainActor(),
          toolCallId: 'call_7',
          changed: [items.first],
          deleted: const ['2'],
        ),
      );

      final meta = project(event).single['_meta'];
      expect(meta, {
        'codelab': {
          'taskChange': {
            'op': 'delete',
            'actor': 'main',
            'toolCallId': 'call_7',
            'changed': ['1'],
            'deleted': ['2'],
          },
        },
      });
    });

    // `assign` и операция потомка: `actor` — id субагента, `toolCallId`
    // опускается, пока ядро его не передало (§17.16.5).
    test('a subagent operation without a call has no toolCallId key', () {
      final items = [item('1', 'A', owner: const TaskOwner('sub_k3f9a1c2'))];
      final event = TaskListChanged(
        s,
        items: items,
        change: TaskChange(
          op: 'assign',
          actor: const SubagentActor('sub_k3f9a1c2'),
          changed: items,
          deleted: const [],
        ),
      );

      final change =
          ((project(event).single['_meta']! as Map)['codelab']!
                  as Map)['taskChange']!
              as Map;
      expect(change['actor'], 'sub_k3f9a1c2');
      expect(change, isNot(contains('toolCallId')));
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

    // «Реплей плана без taskChange» (D35): с `replay: true` у `plan` нет
    // `_meta` вовсе, entries с `_meta.codelab.task` остаются.
    test('a replayed plan has no taskChange', () {
      final event = TaskListChanged(
        s,
        items: [item('1', 'A')],
        change: TaskChange(
          op: 'update',
          actor: const MainActor(),
          toolCallId: 'call_7',
          changed: [item('1', 'A')],
          deleted: const [],
        ),
      );

      final frame = projectEvent(
        event,
        configOptions: () => const [],
        replay: true,
      ).single.toJson();

      expect(frame, isNot(contains('_meta')));
      final entry = (frame['entries']! as List).single as Map;
      expect(entry['_meta'], isNotNull);
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

  // Строки `Subagent*` и первый кадр вызова `agent` (agent-acp-server
  // «Проекция субагентов и списка задач»; D24, D28; задачи 2.1, 2.8).
  SubagentSnapshot snapshot() => SubagentSnapshot(
    id: 'sub_k3f9a1c2',
    parentToolCallId: 'call_1',
    agent: 'explore',
    description: 'Find auth code',
    depth: 1,
    state: SubagentState.running,
    steps: 1,
    toolCalls: 2,
    usage: Usage.zero,
    activeChildren: 0,
    startedAt: DateTime.utc(2026, 11, 14),
  );

  group('Subagent* → not sent', () {
    test('SubagentStarted gives no frame', () {
      final event = SubagentStarted(
        s,
        subagentId: 'sub_k3f9a1c2',
        parentToolCallId: 'call_1',
        agent: 'explore',
        description: 'Find auth code',
        childSessionId: const SessionId('child_1'),
        journalPath: 'subagents/child_1.jsonl',
      );

      expect(project(event), isEmpty);
    });

    // Строку прогресса клиент получает через `ToolCallProgress(agent)`, а не
    // из `SubagentProgress` (§17.3.7): иначе строка пришла бы дважды.
    test('SubagentProgress gives no frame', () {
      expect(project(SubagentProgress(s, snapshot: snapshot())), isEmpty);
    });

    test('SubagentFinished gives no frame', () {
      final event = SubagentFinished(
        s,
        subagentId: 'sub_k3f9a1c2',
        parentToolCallId: 'call_1',
        status: SubagentState.completed,
        usage: Usage.zero,
        duration: const Duration(seconds: 48),
        reportPreview: 'Auth is in lib/auth/session.dart',
      );

      expect(project(event), isEmpty);
    });

    // SUB-12: клиенту без `subagentToolCalls` — не отправляется; в итерации 2
    // агент это расширение не объявляет (D36, Т12), поэтому не отправляется
    // никому.
    test('SubagentActivity gives no frame in iteration 2', () {
      final event = SubagentActivity(
        s,
        subagentId: 'sub_k3f9a1c2',
        parentToolCallId: 'call_1',
        path: const [],
        depth: 1,
        event: ToolCallStarted(
          const SessionId('child_1'),
          toolCallId: 'call_1',
          tool: 'read',
          kind: ToolKind.read,
          title: 'Read a.dart',
          input: const {'path': 'a.dart'},
        ),
      );

      expect(project(event), isEmpty);
    });

    test('the projection table has a "not sent" row for each of them', () {
      for (final type in [
        SubagentStarted,
        SubagentProgress,
        SubagentFinished,
        SubagentActivity,
      ]) {
        expect(
          projectionTable[type],
          allOf(isNotNull, startsWith('not sent')),
          reason: '$type',
        );
      }
    });
  });

  group('ToolCallStarted(agent) → tool_call with _meta.codelab.subagent', () {
    ToolCallStarted agentCall({SubagentCallRef? subagent}) => ToolCallStarted(
      s,
      toolCallId: 'call_1',
      tool: 'agent',
      kind: ToolKind.think,
      title: 'Subagent explore: Find auth code',
      input: const {
        'type': 'explore',
        'description': 'Find auth code',
        'prompt': 'Find where authentication is implemented.',
      },
      subagent: subagent,
    );

    // D28: признак вызова `agent` с первого кадра — только данные `_meta`.
    test('the first frame carries {id, type}', () {
      final frames = project(
        agentCall(
          subagent: SubagentCallRef(id: 'sub_k3f9a1c2', type: 'explore'),
        ),
      );

      expect(frames, [
        {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call_1',
          'title': 'Subagent explore: Find auth code',
          'kind': 'think',
          'status': 'pending',
          'rawInput': {
            'type': 'explore',
            'description': 'Find auth code',
            'prompt': 'Find where authentication is implemented.',
          },
          '_meta': {
            'codelab': {
              'subagent': {'id': 'sub_k3f9a1c2', 'type': 'explore'},
            },
          },
        },
      ]);
    });

    // Вызов без `SubagentCallRef` (любой другой инструмент) `_meta` не
    // получает: расширение не должно протекать в чужие вызовы.
    test('a call without SubagentCallRef has no _meta', () {
      final frame = project(agentCall()).single;

      expect(frame, isNot(contains('_meta')));
    });
  });

  group('ToolCallFinished(agent) content', () {
    ToolCallFinished finished(ToolOutcome outcome) => ToolCallFinished(
      s,
      toolCallId: 'call_1',
      outcome: outcome,
      content: const [
        TextContent(
          '<untrusted-content source="agent">\n'
          '<subagent-report id="sub_a" agent="explore" status="failed">\n'
          'Subagent failed: boom\n'
          '</subagent-report>\n'
          '</untrusted-content>',
        ),
      ],
    );

    SubagentFinished done(String report) => SubagentFinished(
      s,
      subagentId: 'sub_a',
      parentToolCallId: 'call_1',
      status: SubagentState.failed,
      failure: SubagentFailure.error,
      report: report,
    );

    List<Map<String, Object?>> frames(SubagentFinished result) => [
      for (final u in projectEvent(
        finished(ToolOutcome.failed),
        configOptions: () => const [],
        subagentResult: result,
      ))
        u.toJson(),
    ];

    // Дельта agent-acp-server: клиенту — тело отчёта без обёртки и ограды.
    test('a failed child with a report gets the bare body', () {
      final update = frames(done('Partial findings.')).single;

      expect(update['content'], [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': 'Partial findings.'},
        },
      ]);
    });

    // Пустой отчёт: обёртка из результата для модели клиенту не уходит.
    test('a failed child without a report gets no wrapped text', () {
      final update = frames(done('')).single;

      expect(update['status'], 'failed');
      expect(update.toString(), isNot(contains('subagent-report')));
      expect(update.toString(), isNot(contains('untrusted-content')));
      expect((update['_meta']! as Map)['codelab'], contains('subagent'));
    });
  });
}
