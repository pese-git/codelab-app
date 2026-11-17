// Цикл родителей A↔B в kit (находка 3 ревью итерации 5
// `add-subagents-and-tasks`; PERM-4, §9): `_hostRowOf` и
// `buildToolCallTree` используют одну карту родителей, поэтому одобрение
// вызова из цикла показывается одной панелью.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

Map<String, Object?> _meta({String? parent, Map<String, Object?>? subagent}) =>
    {
      'codelab': {'parentToolCallId': ?parent, 'subagent': ?subagent},
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

void main() {
  late KitAgent agent;
  late SessionHandle session;
  late JsonRpcRequest prompt;
  var nextRequestId = 7;

  setUp(() async {
    agent = KitAgent(capabilities: const AgentCapabilities(loadSession: true));
    await agent.start();
    session = await agent.newSession('s1');
    prompt = (await agent.prompt(session, 'go')).request;
    nextRequestId = 7;
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

  group('cycle of parents A↔B: one approval panel (PERM-4, §9)', () {
    test('the approval of A lives in exactly one place', () async {
      await emit(_call('A', parent: 'B', kind: 'execute', status: 'pending'));
      await emit(_call('B', parent: 'A', kind: 'execute', status: 'pending'));
      agent.transport.emitInbound(
        JsonRpcMessage.request(
          id: JsonRpcId.integer(nextRequestId++),
          method: sessionRequestPermissionMethod,
          params: RequestPermissionRequest(
            sessionId: const SessionId('s1'),
            toolCall: ToolCallUpdate(
              toolCallId: ToolCallId('A'),
              title: 'Run dart test',
              kind: ToolKind.execute,
              status: ToolCallStatus.pending,
              rawInput: const {'command': 'dart test'},
              meta: const {
                'codelab': {
                  'subagent': {
                    'id': 'sub_b2',
                    'type': 'explore',
                    'description': 'Check the diff',
                    'depth': 1,
                    'path': <String>[],
                    'parentToolCallId': 'B',
                  },
                },
              },
            ),
            options: const [
              PermissionOption(
                optionId: PermissionOptionId('allow-once'),
                name: 'Allow once',
                kind: PermissionOptionKind.allowOnce,
              ),
            ],
          ).toJson(),
        ),
      );
      await pumpEventQueue();

      final calls = session.current.transcript
          .whereType<ToolCallItem>()
          .toList();
      final panels = [
        for (final call in calls) ...[
          if (call.approval is PendingApprovalView) call.approval,
          ...call.childApprovals,
        ],
      ];
      // Своя строка A показывает одобрение (панель), `childApprovals` B пуст.
      expect(
        calls
            .singleWhere((c) => c.toolCallId == ToolCallId('B'))
            .childApprovals,
        isEmpty,
      );
      expect(panels, hasLength(1));
    });
  });
}
