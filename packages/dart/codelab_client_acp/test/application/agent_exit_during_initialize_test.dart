// Агент завершается во время `initialize` (tasks 3.6 change
// `add-codelab-cli`): `connect` не должен ждать таймаута запроса — ответа
// оборванного соединения не будет (как для хода, design D2 change
// `add-connection-and-error-states`).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

void main() {
  test('a transport failure during initialize fails connect at once, not '
      'after the request timeout', () async {
    final client = AcpClientApplication(
      transport: FakeAcpTransport(),
      requestTimeout: const Duration(seconds: 30),
    );
    addTearDown(client.dispose);
    final agent = FakeAcpTransport()..autoRespondToInitialize = false;
    final initialize = agent.sent.firstWhere(
      (message) =>
          message is JsonRpcRequest && message.method == initializeMethod,
    );

    final connected = client.connect(agent);
    await initialize;
    agent.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'Stdio ACP agent exited unexpectedly with code 64.',
      ),
    );

    final error = await connected
        .then<Object?>((_) => null, onError: (Object e) => e)
        .timeout(const Duration(seconds: 2));
    expect(error, isA<AcpConnectionLostException>());
    expect(
      (error! as AcpConnectionLostException).message,
      contains('exited unexpectedly with code 64'),
    );
    expect(client.connectionState, isA<ClientConnectionFailed>());
  });
}
