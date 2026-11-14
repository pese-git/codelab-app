import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:test/test.dart';

import 'journal_lines.dart';

/// Реплей вызова `agent` (agent-acp-server «Итог субагента» в реплее и
/// «Вызов agent»; D24, D28): `ToolCallStarted.subagent` из записи `subagent`
/// и `SubagentFinished` с итогом перед `ToolCallFinished`.
void main() {
  String record(String id, String parent, Map<String, Object?> extra) =>
      jsonEncode({
        'type': 'subagent',
        'id': id,
        'parentId': parent,
        'timestamp': at,
        'subagentId': 'sub_k3f9a1c2',
        'toolCallId': 'c1',
        'agent': 'explore',
        'description': 'Find auth',
        ...extra,
      });

  SessionSnapshot snapshot(List<String> lines) => parseSessionLines(
    journal([header(), ...lines]),
    id: const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C'),
  ).snapshot;

  final base = [
    user('u1', null),
    answer(
      'a1',
      'u1',
      calls: [
        ('c1', 'agent', {'description': 'Find auth', 'prompt': 'p'}),
      ],
    ),
  ];

  test('completed: id and type in the first frame, the summary before '
      'ToolCallFinished', () {
    final events = buildReplay(
      snapshot([
        ...base,
        record('s1', 'a1', {'status': 'running'}),
        record('s2', 's1', {
          'status': 'completed',
          'report': 'in lib/auth',
          'usage': {'input': 100, 'output': 20},
          'toolCalls': 4,
          'durationMs': 48000,
        }),
        toolResult('r1', 's2', callId: 'c1', tool: 'agent'),
      ]),
    );

    final started = events.whereType<ToolCallStarted>().single;
    final finished = events.whereType<SubagentFinished>().single;
    expect(
      started.subagent,
      const SubagentCallRef(id: 'sub_k3f9a1c2', type: 'explore'),
    );
    expect(finished.status, SubagentState.completed);
    expect(finished.toolCalls, 4);
    expect(finished.usage.input, 100);
    expect(finished.duration, const Duration(seconds: 48));
    expect(finished.report, 'in lib/auth');
    expect(
      events.indexOf(finished),
      lessThan(events.indexWhere((e) => e is ToolCallFinished)),
    );
    expect(events.indexOf(started), lessThan(events.indexOf(finished)));
  });

  test('failed: failure from the record', () {
    final events = buildReplay(
      snapshot([
        ...base,
        record('s1', 'a1', {
          'status': 'failed',
          'failure': 'budget_exceeded:tokens',
        }),
        toolResult('r1', 's1', callId: 'c1', tool: 'agent', isError: true),
      ]),
    );

    final finished = events.whereType<SubagentFinished>().single;
    expect(finished.failure, SubagentFailure.budgetExceeded);
    expect(finished.budgetExceeded, BudgetLimit.tokens);
    expect(
      failureWire(finished.failure, finished.budgetExceeded),
      'budget_exceeded:tokens',
    );
  });

  test('interrupted (the record is still running): the call ref only', () {
    final events = buildReplay(
      snapshot([
        ...base,
        record('s1', 'a1', {'status': 'running'}),
        toolResult(
          'r1',
          's1',
          callId: 'c1',
          tool: 'agent',
          outcome: 'interrupted',
          isError: true,
        ),
      ]),
    );

    expect(
      events.whereType<ToolCallStarted>().single.subagent?.id,
      'sub_k3f9a1c2',
    );
    expect(events.whereType<SubagentFinished>(), isEmpty);
  });

  test('a call of another tool has no subagent ref', () {
    final events = buildReplay(
      snapshot([
        user('u1', null),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'read', {'path': 'a'}),
          ],
        ),
        toolResult('r1', 'a1', callId: 'c1'),
      ]),
    );

    expect(events.whereType<ToolCallStarted>().single.subagent, isNull);
  });
}
