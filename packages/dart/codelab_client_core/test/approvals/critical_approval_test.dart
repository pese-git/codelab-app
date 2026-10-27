// Признак критичного запроса одобрения (tasks 4.1 change `add-codelab-cli`;
// spec acp-client-kit «Одобрения привязаны к вызову»; design.md, D14).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

void main() {
  late KitAgent agent;

  setUp(() async {
    agent = KitAgent();
    await agent.start();
  });
  tearDown(() => agent.dispose());

  Future<PendingApprovalView> approvalFor({
    Map<String, Object?>? requestMeta,
    Map<String, Object?>? toolCallMeta,
  }) async {
    final session = await agent.newSession('s1');
    await agent.prompt(session, 'go');
    agent.transport.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(7),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: const SessionId('s1'),
          toolCall: ToolCallUpdate(
            toolCallId: const ToolCallId('call_1'),
            title: 'Run rm -rf build',
            kind: ToolKind.execute,
            status: ToolCallStatus.pending,
            rawInput: const {'command': 'rm -rf build'},
            meta: toolCallMeta,
          ),
          options: const [
            PermissionOption(
              optionId: PermissionOptionId('allow-once'),
              name: 'Allow once',
              kind: PermissionOptionKind.allowOnce,
            ),
            PermissionOption(
              optionId: PermissionOptionId('reject-once'),
              name: 'Reject',
              kind: PermissionOptionKind.rejectOnce,
            ),
          ],
          meta: requestMeta,
        ).toJson(),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    return session.current.pendingApprovals.single;
  }

  test('_meta.codelab.critical on the tool call marks the approval '
      'critical', () async {
    final approval = await approvalFor(
      toolCallMeta: {
        'codelab': {'critical': true, 'label': 'recursive delete'},
      },
    );

    expect(approval.critical, isTrue);
  });

  test('_meta.codelab.critical on the request marks the approval '
      'critical', () async {
    final approval = await approvalFor(
      requestMeta: {
        'codelab': {'critical': true},
      },
    );

    expect(approval.critical, isTrue);
  });

  test('without the field or with a non-true value the approval is not '
      'critical', () async {
    expect((await approvalFor()).critical, isFalse);
  });

  test('a non-boolean critical value is not critical', () async {
    final approval = await approvalFor(
      toolCallMeta: {
        'codelab': {'critical': 'yes'},
      },
    );

    expect(approval.critical, isFalse);
  });
}
