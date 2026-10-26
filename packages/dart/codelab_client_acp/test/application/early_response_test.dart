// Регрессия: ответ агента приходит, пока кадр запроса ещё отправляется
// (найдено тестами итерации 2 change `add-session-list-and-reload`).
//
// Синхронный транспорт доставляет ответ до того, как `_sendRequest` дошёл
// до ожидания ответа; ошибка ответа не должна становиться необработанной.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

void main() {
  test('an error answer delivered while the request is being sent reaches '
      'the caller', () async {
    final transport = FakeAcpTransport();
    await transport.start();
    final client = AcpClientApplication(transport: transport);
    addTearDown(client.dispose);
    final answering = transport.sent.listen((message) {
      if (message is JsonRpcRequest) {
        transport.emitInbound(
          JsonRpcMessage.response(
            id: message.id,
            error: const JsonRpcError(code: -32603, message: 'busy'),
          ),
        );
      }
    });
    addTearDown(answering.cancel);

    await expectLater(
      client.createSession(const CreateSessionCommand(cwd: '/workspace')),
      throwsA(isA<AcpClientApplicationException>()),
    );
  });
}
