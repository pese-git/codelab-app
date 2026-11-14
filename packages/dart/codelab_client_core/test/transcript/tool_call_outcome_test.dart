// Отмена по признаку агента (задача 2.15/2.16 change
// `add-subagents-and-tasks`; spec acp-client-kit «Отмена по признаку агента»;
// design.md, D41 п. 1).
//
// Проверяет, что kit читает `_meta.codelab.outcome`: вызов, пришедший как
// `failed` с `outcome: "cancelled"` (реплей `session/load` одним кадром или
// живой `tool_call_update`), показывается как `ToolCallStatusView.cancelled`
// — для любого вида вызова (agent, exec). Признак снимается только итоговым
// `completed`; другие значения (`rejected`, `interrupted`, неизвестное)
// оставляют `failed`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show CancelTurnCommand;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

Map<String, Object?> _meta(String? outcome, {Map<String, Object?>? subagent}) =>
    {
      'codelab': {'outcome': ?outcome, 'subagent': ?subagent},
    };

/// Одним кадром `tool_call`, как при реплее `session/load`.
Map<String, Object?> _callFrame(
  String id, {
  String status = 'failed',
  String? outcome,
  String title = 'Subagent explore: Find auth code',
  String kind = 'think',
  Map<String, Object?>? subagent = const {'id': 'sub_a1', 'type': 'explore'},
}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': title,
  'kind': kind,
  'status': status,
  '_meta': _meta(outcome, subagent: subagent),
};

Map<String, Object?> _update(String id, String status, {String? outcome}) => {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': id,
  'status': status,
  if (outcome != null) '_meta': _meta(outcome),
};

void main() {
  late KitAgent agent;
  late SessionHandle session;

  setUp(() async {
    agent = KitAgent();
    await agent.start();
    session = await agent.newSession('s1');
    await agent.prompt(session, 'go');
  });
  tearDown(() => agent.dispose());

  Future<void> emit(Map<String, Object?> update) async {
    agent.update('s1', update);
    await pumpEventQueue();
  }

  ToolCallStatusView? status(String id) => session.current.transcript
      .whereType<ToolCallItem>()
      .singleWhere((item) => item.toolCallId == ToolCallId(id))
      .details
      ?.status;

  group('outcome "cancelled" on a failed call', () {
    test('an agent call in one tool_call frame becomes cancelled', () async {
      await emit(_callFrame('c1', outcome: 'cancelled'));
      expect(status('c1'), ToolCallStatusView.cancelled);
    });

    test('an exec call (no subagent sign) becomes cancelled too', () async {
      await emit(
        _callFrame(
          'c2',
          outcome: 'cancelled',
          title: 'Run tests',
          kind: 'execute',
          subagent: null,
        ),
      );
      expect(status('c2'), ToolCallStatusView.cancelled);
    });

    test(
      'a live tool_call_update failed + cancelled becomes cancelled',
      () async {
        await emit(_callFrame('c3', status: 'in_progress'));
        await emit(_update('c3', 'failed', outcome: 'cancelled'));
        expect(status('c3'), ToolCallStatusView.cancelled);
      },
    );

    test('a repeated frame is idempotent', () async {
      await emit(_callFrame('c4', outcome: 'cancelled'));
      await emit(_callFrame('c4', outcome: 'cancelled'));
      expect(status('c4'), ToolCallStatusView.cancelled);
    });

    test('the sign is dropped by a final completed', () async {
      await emit(_callFrame('c5', outcome: 'cancelled'));
      await emit(_update('c5', 'completed'));
      expect(status('c5'), ToolCallStatusView.succeeded);
    });

    test('a later failed without the sign does not drop it', () async {
      await emit(_callFrame('c6', outcome: 'cancelled'));
      await emit(_update('c6', 'failed'));
      expect(status('c6'), ToolCallStatusView.cancelled);
    });

    // Требование «Отмена по признаку агента»: статус сливается из кадров по
    // общим правилам (поздний `in_progress`/`pending` показывается как
    // running/queued), а признак сохраняется — его снимает только `completed`.
    // Последующий `failed` без признака снова даёт `cancelled`.
    const lateExpected = {
      'in_progress': ToolCallStatusView.running,
      'pending': ToolCallStatusView.queued,
    };
    for (final late in lateExpected.entries) {
      test(
        'a later ${late.key} frame after failed+cancelled keeps the sign',
        () async {
          await emit(_callFrame('c6_${late.key}', outcome: 'cancelled'));
          await emit(_update('c6_${late.key}', late.key));
          expect(status('c6_${late.key}'), late.value);
          await emit(_update('c6_${late.key}', 'failed'));
          expect(status('c6_${late.key}'), ToolCallStatusView.cancelled);
        },
      );
    }
  });

  group('the sign is dropped only by a final completed', () {
    test(
      'failed+cancelled, completed, then late failed gives failed',
      () async {
        await emit(_callFrame('d1', outcome: 'cancelled'));
        await emit(_update('d1', 'completed'));
        await emit(_update('d1', 'failed'));
        expect(status('d1'), ToolCallStatusView.failed);
      },
    );

    test('a repeated tool_call completed drops the sign too', () async {
      await emit(_callFrame('d2', outcome: 'cancelled'));
      await emit(_callFrame('d2', status: 'completed'));
      await emit(_update('d2', 'failed'));
      expect(status('d2'), ToolCallStatusView.failed);
    });
  });

  group('other outcomes stay failed', () {
    for (final outcome in ['rejected', 'interrupted', 'something_new']) {
      test('outcome "$outcome" gives failed', () async {
        await emit(_callFrame('c_$outcome', outcome: outcome));
        expect(status('c_$outcome'), ToolCallStatusView.failed);
      });
    }

    test('no outcome gives failed', () async {
      await emit(_callFrame('c_none'));
      expect(status('c_none'), ToolCallStatusView.failed);
    });
  });

  // Пометка клиента (D27) и признак агента сочетаются: живой
  // `failed`+`cancelled` после `cancelTurn` даёт cancelled без дублей строк.
  test(
    'a live failed + cancelled after cancelTurn is cancelled once',
    () async {
      await emit(_callFrame('c7', status: 'in_progress'));
      await agent.application.cancelTurn(
        CancelTurnCommand(sessionId: const SessionId('s1')),
      );
      expect(status('c7'), ToolCallStatusView.cancelled);

      await emit(_update('c7', 'failed', outcome: 'cancelled'));

      expect(status('c7'), ToolCallStatusView.cancelled);
      expect(
        session.current.transcript.whereType<ToolCallItem>().where(
          (item) => item.toolCallId == const ToolCallId('c7'),
        ),
        hasLength(1),
      );
    },
  );

  test('a failed call without outcome stays failed', () async {
    await emit(_callFrame('c8', status: 'in_progress'));
    await emit(_update('c8', 'failed'));
    expect(status('c8'), ToolCallStatusView.failed);
  });

  test('a malformed outcome (not a string) leaves the call failed', () async {
    await emit({
      ..._callFrame('c9'),
      '_meta': {
        'codelab': {'outcome': 5},
      },
    });
    expect(status('c9'), ToolCallStatusView.failed);
  });

  test('a cancelled subagent after load keeps the parsed summary', () async {
    await emit({
      ..._callFrame('c10', outcome: 'cancelled'),
      '_meta': {
        'codelab': {
          'outcome': 'cancelled',
          'subagent': {
            'id': 'sub_a1',
            'type': 'explore',
            'summary': {
              'toolCalls': 2,
              'tokens': {'input': 900, 'output': 100},
              'durationMs': 4000,
            },
          },
        },
      },
    });
    final details = session.current.transcript
        .whereType<ToolCallItem>()
        .singleWhere((item) => item.toolCallId == const ToolCallId('c10'))
        .details;
    expect(details?.status, ToolCallStatusView.cancelled);
    expect(
      details?.subagentSummary,
      const SubagentSummaryView(
        toolCalls: 2,
        inputTokens: 900,
        outputTokens: 100,
        duration: Duration(seconds: 4),
      ),
    );
  });

  // Регрессия kit (D41 п. 3, 2.15): kit не разбирает заголовок, поэтому
  // `Subagent general` без описания показывается как есть. Ожидается зелёным.
  test('a rejected agent call titled "Subagent general" keeps its title', () {
    final row = ToolRowFormatter.format(
      ToolCallItem(
        id: 'tool-1',
        toolCallId: const ToolCallId('call-1'),
        title: 'Subagent general',
        details: const ToolCallView(
          kind: ToolKind.think,
          status: ToolCallStatusView.failed,
          rawInput: <String, Object?>{},
          textOutput: ['Invalid arguments\nsecond line'],
        ),
      ),
      cwd: '/work',
    );
    final shown = '${row.label} ${row.detail}';
    expect(shown, contains('Subagent general'));
    expect(shown, isNot(contains('Subagent general:')));
    expect(row.secondary, 'Invalid arguments');
  });
}
