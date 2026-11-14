import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:codelab_agent_core/src/subagents/subagent_report.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart';
import 'subagent_rig.dart';

/// Значение `max_tokens` как член `SubagentFailure` и как строка провода
/// (agent-subagents «Отчёт ребёнка»; design.md change
/// `add-subagents-and-tasks`, D41 п. 6; `agent-core/17-3-subagents.md`
/// §17.3.5–17.3.6).
///
/// Красный до задачи 2.20 по причине компиляции: члена
/// `SubagentFailure.maxTokens` ещё нет. Тесты вынесены в отдельный файл
/// намеренно, чтобы не ломать компиляцию остальных тестов субагентов, которые
/// проверяют то же поведение по тексту и записям журнала.
void main() {
  test('failureWire и parseFailure: max_tokens в обе стороны', () {
    expect(failureWire(SubagentFailure.maxTokens, null), 'max_tokens');
    expect(parseFailure('max_tokens').failure, SubagentFailure.maxTokens);
    expect(parseFailure('max_tokens').limit, isNull);
  });

  test('живой ход: SubagentFinished несёт failure maxTokens для пустого '
      'отчёта и null для оборванного непустого', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          multiCallStep([
            ('c1', 'agent', agentArgs('empty one', description: 'Empty')),
            ('c2', 'agent', agentArgs('cut one', description: 'Cut')),
          ]),
          replyStep('thanks'),
        ],
        'empty one': [
          {
            'reply': [
              {'thinking': 'thinking only'},
            ],
            'stopReason': 'length',
          },
        ],
        'cut one': [
          {
            'reply': [
              {'text': 'Half a sentence'},
            ],
            'stopReason': 'length',
          },
        ],
      },
    );
    await rig.open();
    await rig.run('go');

    final byCall = {
      for (final e in rig.eventsOf<SubagentFinished>()) e.parentToolCallId: e,
    };
    expect(byCall['c1']!.status, SubagentState.failed);
    expect(byCall['c1']!.failure, SubagentFailure.maxTokens);
    expect(byCall['c2']!.status, SubagentState.completed);
    expect(byCall['c2']!.failure, isNull);
  });

  test('реплей: итоговая запись failure: max_tokens даёт '
      'SubagentFinished.failure maxTokens', () {
    final snapshot = parseSessionLines(
      journal([
        header(),
        user('u1', null),
        answer(
          'a1',
          'u1',
          calls: [
            ('c1', 'agent', {'description': 'Find auth', 'prompt': 'p'}),
          ],
        ),
        jsonEncode({
          'type': 'subagent',
          'id': 's1',
          'parentId': 'a1',
          'timestamp': at,
          'subagentId': 'sub_k3f9a1c2',
          'toolCallId': 'c1',
          'agent': 'review',
          'description': 'Find auth',
          'status': 'failed',
          'failure': 'max_tokens',
        }),
        toolResult('r1', 's1', callId: 'c1', tool: 'agent', isError: true),
      ]),
      id: const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C'),
    ).snapshot;

    final finished = buildReplay(snapshot).whereType<SubagentFinished>().single;

    expect(finished.failure, SubagentFailure.maxTokens);
    expect(
      failureWire(finished.failure, finished.budgetExceeded),
      'max_tokens',
    );
  });
}
