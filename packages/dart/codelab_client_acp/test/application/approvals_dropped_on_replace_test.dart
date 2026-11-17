// Ожидающие одобрения снимаются синхронно при замене транспорта (D22 change
// `require-project-folder`; AGENTS.md §9, §10): до первого `await` замены
// одобрение уже `cancelled`, а ответ по нему ничего не отправляет в старый
// транспорт. Тест держит порядок в `_replaceTransport`: снятие стоит сразу
// после `_generation++`, а не после отмены подписок.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');

void main() {
  test('the approval is cancelled in the same tick the transport is '
      'replaced', () async {
    final transport = FakeAcpTransport();
    await transport.start();
    final client = AcpClientApplication(transport: transport);
    final replacement = FakeAcpTransport();
    addTearDown(() async {
      await client.dispose();
      await replacement.close();
    });

    final created = client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );
    await Future<void>.delayed(Duration.zero);
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
    unawaited(
      expectLater(prompt, throwsA(isA<AcpClientApplicationException>())),
    );
    await Future<void>.delayed(Duration.zero);
    transport.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(7),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: _session,
          toolCall: const ToolCallUpdate(
            toolCallId: ToolCallId('call_1'),
            title: 'Run call_1',
            kind: ToolKind.execute,
            status: ToolCallStatus.inProgress,
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
    await Future<void>.delayed(Duration.zero);
    const approvalId = ApprovalRequestId('permission-7');
    expect(
      client.sessionById(_session)!.activeTurn!.approvals[approvalId]!.status,
      ApprovalStatus.pending,
    );

    // Без `await`: проверки идут в том же синхронном такте.
    final replacing = client.connect(replacement);

    final turn = client.sessionById(_session)!.activeTurn!;
    expect(turn.approvals[approvalId]!.status, ApprovalStatus.cancelled);
    expect(
      turn.approvals.values.where((a) => a.status == ApprovalStatus.pending),
      isEmpty,
    );
    final decision = client.respondToPermission(
      const RespondToPermissionCommand.selected(
        sessionId: _session,
        approvalId: approvalId,
        optionId: PermissionOptionId('allow-once'),
      ),
    );
    await expectLater(decision, throwsA(isA<StateTransitionException>()));
    expect(transport.sentMessages.whereType<JsonRpcResponse>(), isEmpty);

    await replacing;
  });
}
