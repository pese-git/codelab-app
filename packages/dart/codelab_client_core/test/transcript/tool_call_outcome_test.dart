// Отмена по признаку агента (задача 2.15/2.16 change
// `add-subagents-and-tasks`; spec acp-client-kit «Отмена по признаку агента»;
// design.md, D41 п. 1).
//
// Красные тесты: kit не читает `_meta.codelab.outcome`, поэтому вызов,
// пришедший как `failed` с `outcome: "cancelled"` (реплей `session/load`
// одним кадром или живой `tool_call_update`), остаётся `failed`, а должен
// стать `ToolCallStatusView.cancelled` — для любого вида вызова (agent, exec).
// Признак снимается только итоговым `completed`; другие значения
// (`rejected`, `interrupted`, неизвестное) оставляют `failed`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
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

    test('a later non-final frame does not change the sign', () async {
      await emit(_callFrame('c6', outcome: 'cancelled'));
      await emit(_update('c6', 'failed'));
      expect(status('c6'), ToolCallStatusView.cancelled);
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

  // Регрессия (зелёная сразу): прежняя пометка клиента не меняется (D27).
  test(
    'a failed call without outcome after cancelTurn keeps its status',
    () async {
      await emit(_callFrame('c7', status: 'in_progress'));
      await emit(_update('c7', 'failed'));
      expect(status('c7'), ToolCallStatusView.failed);
    },
  );

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
