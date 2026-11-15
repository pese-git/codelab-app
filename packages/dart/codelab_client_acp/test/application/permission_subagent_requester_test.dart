// `_meta.codelab.subagent` запроса разрешения хранится у `ApprovalRequest`
// отдельно от `ToolCallRecord.subagentMeta` (задача 3.1 `[client]` change
// `add-subagents-and-tasks`; design.md, D43 п. 1; spec acp-client-kit
// «Запрос одобрения от субагента», сценарий «Запрос ребёнка не делает вызов
// вызовом agent»).
//
// Красный тест: у `ApprovalRequest` нет поля `subagentRequester` — файл не
// компилируется, пока задача 3.4 его не добавит. Имя — предложение этой
// задачи (spec задаёт только «хранится у `ApprovalRequest`»); значение —
// сырая карта, как у `subagentMeta`: терпимый разбор — в
// `codelab_client_core`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');
const _approvalId = ApprovalRequestId('permission-7');

const _requester = {
  'id': 'sub_x9',
  'type': 'explore',
  'description': 'Find auth code',
  'depth': 2,
  'path': ['sub_a1'],
  'parentToolCallId': 'call_1',
};

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(transport: transport);
    final created = client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );
    await pumpEventQueue();
    transport.emitInbound(
      JsonRpcMessage.response(
        id: (transport.sentMessages.single as JsonRpcRequest).id,
        result: const NewSessionResponse(sessionId: _session).toJson(),
      ),
    );
    await created;
    final prompt = client.sendPrompt(
      const SendPromptCommand(
        sessionId: _session,
        prompt: [ContentBlock.text(text: 'go')],
      ),
    );
    await pumpEventQueue();
    // Ход закрывается в `tearDown`; ответ на промпт здесь не нужен.
    addTearDown(() async {
      await client.dispose();
      await prompt.then<void>((_) {}, onError: (_) {});
    });
  });

  void announceAgentCall() => transport.emitInbound(
    JsonRpcMessage.notification(
      method: sessionUpdateMethod,
      params: {
        'sessionId': _session.value,
        'update': {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call_1',
          'title': 'Subagent review: Check',
          'kind': 'think',
          'status': 'in_progress',
          '_meta': {
            'codelab': {
              'subagent': {'id': 'sub_a1', 'type': 'review'},
            },
          },
        },
      },
    ),
  );

  void ask(String toolCallId, {Map<String, Object?>? meta}) =>
      transport.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(7),
          method: sessionRequestPermissionMethod,
          params: RequestPermissionRequest(
            sessionId: _session,
            toolCall: ToolCallUpdate(
              toolCallId: ToolCallId(toolCallId),
              title: 'Run dart test',
              kind: ToolKind.execute,
              status: ToolCallStatus.pending,
              meta: meta,
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

  ApprovalRequest approval() =>
      client.sessionById(_session)!.activeTurn!.approvals[_approvalId]!;

  test('the requester is stored on the approval, not merged into '
      'subagentMeta of the call', () async {
    ask(
      'call_1/call_1/call_1',
      meta: const {
        'codelab': {'subagent': _requester},
      },
    );
    await pumpEventQueue();

    expect(approval().subagentRequester, _requester);
    expect(approval().toolCall.subagentMeta, isNull);
  });

  test('a request for an announced agent call does not touch its '
      'subagentMeta', () async {
    announceAgentCall();
    await pumpEventQueue();
    ask(
      'call_1',
      meta: const {
        'codelab': {'subagent': _requester},
      },
    );
    await pumpEventQueue();

    expect(approval().subagentRequester?['id'], 'sub_x9');
    expect(approval().toolCall.subagentMeta, {
      'id': 'sub_a1',
      'type': 'review',
    });
    final turn = client.sessionById(_session)!.activeTurn!;
    expect(turn.toolCalls[const ToolCallId('call_1')]!.subagentMeta, {
      'id': 'sub_a1',
      'type': 'review',
    });
  });

  test(
    'without _meta.codelab.subagent the approval has no requester',
    () async {
      ask('call_1/call_1');
      await pumpEventQueue();

      expect(approval().subagentRequester, isNull);
    },
  );

  test('the requester stays on the approval after the decision', () async {
    ask(
      'call_1/call_1',
      meta: const {
        'codelab': {'subagent': _requester},
      },
    );
    await pumpEventQueue();

    final resolved = await client.respondToPermission(
      const RespondToPermissionCommand.selected(
        sessionId: _session,
        approvalId: _approvalId,
        optionId: PermissionOptionId('allow-once'),
      ),
    );

    expect(resolved.subagentRequester, _requester);
    expect(approval().subagentRequester, _requester);
  });
}
