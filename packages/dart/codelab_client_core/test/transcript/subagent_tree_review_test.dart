// Исправления по двойному ревью итерации 5 `add-subagents-and-tasks`
// (клиентский слой, kit):
//   1. «Итог и хвост субагента» (acp-client-kit) и D48 п. 3: операция со
//      списком задач у потомка входит в хвост поддерева как вызов; хост
//      отличает её по `SubagentTailView.operations` и рисует тихой строкой;
//   2. строка счётчика работающего `agent` готовится kit:
//      `ToolRowView.runningCounter` (тот же формат, что `summaryShort`);

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

Map<String, Object?> _meta({String? parent, Map<String, Object?>? subagent}) =>
    {
      'codelab': {'parentToolCallId': ?parent, 'subagent': ?subagent},
    };

Map<String, Object?> _agentCall(String id) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': 'Subagent explore: Find auth code',
  'kind': 'think',
  'status': 'in_progress',
  'rawInput': {'type': 'explore', 'description': 'Find auth code'},
  '_meta': _meta(subagent: {'id': 'sub_a1', 'type': 'explore'}),
};

Map<String, Object?> _call(
  String id, {
  String? parent,
  String kind = 'read',
  String status = 'in_progress',
}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': 'Read lib/${id.split('/').last}.dart',
  'kind': kind,
  'status': status,
  if (parent != null) '_meta': _meta(parent: parent),
};

Map<String, Object?> _finish(String id) => {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': id,
  'status': 'completed',
};

Map<String, Object?> _plan(String call, String taskId) => {
  'sessionUpdate': 'plan',
  'entries': [
    {
      'content': 'Task $taskId',
      'status': 'pending',
      'priority': 'medium',
      '_meta': {
        'codelab': {
          'task': {'id': taskId},
        },
      },
    },
  ],
  '_meta': {
    'codelab': {
      'taskChange': {
        'op': 'create',
        'actor': 'main',
        'toolCallId': call,
        'changed': [taskId],
        'deleted': const <String>[],
      },
    },
  },
};

void main() {
  late KitAgent agent;
  late SessionHandle session;
  late JsonRpcRequest prompt;

  setUp(() async {
    agent = KitAgent(capabilities: const AgentCapabilities(loadSession: true));
    await agent.start();
    session = await agent.newSession('s1');
    prompt = (await agent.prompt(session, 'go')).request;
  });
  tearDown(() async {
    agent.respond(prompt, const {'stopReason': 'end_turn'});
    await pumpEventQueue();
    await agent.dispose();
  });

  Future<void> emit(Map<String, Object?> update) async {
    agent.update('s1', update);
    await pumpEventQueue();
  }

  ToolCallItem topCall(String id) => session.current.transcript
      .whereType<ToolCallItem>()
      .singleWhere((item) => item.toolCallId == ToolCallId(id));

  Future<void> childOp(String id, String taskId) async {
    await emit(_call(id, parent: 'call_1', kind: 'think'));
    await emit(_plan(id, taskId));
    await emit(_finish(id));
  }

  group('the tail includes the task operations of descendants (D48 п. 3)', () {
    test('operation inside the last three calls: counted, in the tail, '
        'marked quiet', () async {
      await emit(_agentCall('call_1'));
      await emit(_call('call_1/call_1', parent: 'call_1'));
      await childOp('call_1/call_2', '1');
      await emit(_call('call_1/call_3', parent: 'call_1'));

      final root = topCall('call_1');
      expect(root.subtreeCalls, 3);
      expect(root.tail.calls.map((c) => c.toolCallId.value), [
        'call_1/call_1',
        'call_1/call_2',
        'call_1/call_3',
      ]);
      expect(root.tail.moreCount, 0);
      expect(root.tail.operations.keys.map((id) => id.value), [
        'call_1/call_2',
      ]);
      expect(root.tail.operations[ToolCallId('call_1/call_2')]!.added, ['1']);
    });

    test('older operation falls out of the tail into moreCount', () async {
      await emit(_agentCall('call_1'));
      await childOp('call_1/call_1', '1');
      for (var i = 2; i <= 5; i++) {
        await emit(_call('call_1/call_$i', parent: 'call_1'));
      }

      final root = topCall('call_1');
      expect(root.tail.calls, hasLength(3));
      expect(root.tail.moreCount, 2);
      expect(root.tail.operations, isEmpty);
    });
  });

  group('ToolRowView.runningCounter (kit готовит счётчик, не маппер app)', () {
    ToolCallItem running(int subtree, {ToolCallStatusView? status}) =>
        ToolCallItem(
          id: 'i',
          toolCallId: ToolCallId('call_1'),
          title: 'Subagent explore: Find auth code',
          subtreeCalls: subtree,
          details: ToolCallView(
            kind: ToolKind.think,
            status: status ?? ToolCallStatusView.running,
            subagentCall: const SubagentCallView(id: 'sub_a1', type: 'explore'),
          ),
        );

    test('plural, singular and no counter without a tree', () {
      expect(
        ToolRowFormatter.format(running(5), cwd: '/w').runningCounter,
        '5 tool calls',
      );
      expect(
        ToolRowFormatter.format(running(1), cwd: '/w').runningCounter,
        '1 tool call',
      );
      expect(
        ToolRowFormatter.format(running(0), cwd: '/w').runningCounter,
        isNull,
      );
    });

    test('a finished agent has no running counter', () {
      expect(
        ToolRowFormatter.format(
          running(5, status: ToolCallStatusView.succeeded),
          cwd: '/w',
        ).runningCounter,
        isNull,
      );
    });
  });
}
