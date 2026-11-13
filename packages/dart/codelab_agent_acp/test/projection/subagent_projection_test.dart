import 'package:codelab_agent_acp/src/event_projection.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Проекция событий субагентов итерации 2 (ACP-6): строки таблицы §13.7 для
/// `Subagent*` и `SubagentActivity` — «not sent», а первый `tool_call` вызова
/// `agent` несёт `_meta.codelab.subagent {id, type}` (D28).
///
/// Почему отдельный файл, а не `acp_projection_exhaustive_test.dart`: тот
/// файл уже зелёный для `TaskListChanged`, а этот целиком ссылается на типы,
/// которых в ядре ещё нет (`SubagentStarted`, `SubagentProgress`,
/// `SubagentFinished`, `SubagentActivity`, `SubagentSnapshot`,
/// `SubagentCallRef`, `ToolCallStarted.subagent`), и не скомпилировался бы —
/// вместе с ним упали бы существующие тесты задач. Источники: agent-acp-server
/// «Проекция субагентов и списка задач», design.md change
/// `add-subagents-and-tasks` D24, D28; задача 2.1 (красный тест), 2.8.
///
/// Красный до задач 2.4–2.6 (типы ядра) и 2.8 (проекция). Формы конструкторов
/// взяты из §17.3.2 и §5.3 документов ядра; при расхождении с реализацией
/// поправляются здесь, смысл проверок остаётся.
void main() {
  const s = SessionId('sess_1');

  List<Map<String, Object?>> project(AgentEvent event) => [
    for (final update in projectEvent(event, configOptions: () => const []))
      update.toJson(),
  ];

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
}
