// Тесты таймаута исходящих запросов (tasks 1.2 change
// `add-session-list-and-reload`; spec acp-protocol-client «Таймаут
// исходящих запросов»; design D2).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _timeout = Duration(milliseconds: 50);

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(
      transport: transport,
      requestTimeout: _timeout,
    );
  });

  tearDown(() async {
    await client.dispose();
    await transport.close();
  });

  test('the default request timeout is 60 seconds', () {
    expect(
      AcpClientApplication.defaultRequestTimeout,
      const Duration(seconds: 60),
    );
  });

  test('a request without an answer fails with a typed timeout naming the '
      'method', () async {
    final created = client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );

    final error = await created.then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );

    expect(error, isA<AcpRequestTimeoutException>());
    final timeout = error! as AcpRequestTimeoutException;
    expect(timeout.method, sessionNewMethod);
    expect(timeout.timeout, _timeout);
    expect(client.sessions, isEmpty);
  });

  test('a late answer after the timeout does not change state', () async {
    final created = client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );
    await _pump();
    final request = transport.sentMessages.single as JsonRpcRequest;
    await expectLater(created, throwsA(isA<AcpRequestTimeoutException>()));

    final changes = <AcpSession>[];
    final subscription = client.sessionChanges.listen(changes.add);
    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(
          sessionId: SessionId('session-1'),
        ).toJson(),
      ),
    );
    await _pump();

    expect(client.sessions, isEmpty);
    expect(changes, isEmpty);
    await subscription.cancel();
  });

  test('session/prompt is not limited by the request timeout', () async {
    await _createSession(client, transport);
    transport.drainSentMessages();

    final turn = client.sendPrompt(
      const SendPromptCommand(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'long task')],
      ),
    );
    await Future<void>.delayed(_timeout * 3);
    final request = transport.sentMessages.single as JsonRpcRequest;
    expect(request.method, sessionPromptMethod);

    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
      ),
    );

    expect((await turn).status, PromptTurnStatus.completed);
  });

  test('a timed out session/load drops its replay buffer', () async {
    final loading = client.loadSession(
      const LoadSessionCommand(
        sessionId: SessionId('session-1'),
        cwd: '/workspace',
      ),
    );
    await _pump();
    transport.emitInbound(
      _sessionUpdate(
        const SessionUpdate.userMessageChunk(
          content: ContentBlock.text(text: 'old'),
        ),
      ),
    );
    await expectLater(loading, throwsA(isA<AcpRequestTimeoutException>()));
    transport.drainSentMessages();

    // Новая сессия с тем же id получает обновления без реплея.
    final created = client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );
    await _pump();
    final create = transport.sentMessages.single as JsonRpcRequest;
    transport.emitInbound(
      JsonRpcMessage.response(
        id: create.id,
        result: const NewSessionResponse(
          sessionId: SessionId('session-1'),
        ).toJson(),
      ),
    );
    expect((await created).turns, isEmpty);
  });
}

Future<void> _createSession(
  AcpClientApplication client,
  FakeAcpTransport transport,
) async {
  final created = client.createSession(
    const CreateSessionCommand(cwd: '/workspace'),
  );
  await _pump();
  final request = transport.sentMessages.single as JsonRpcRequest;
  transport.emitInbound(
    JsonRpcMessage.response(
      id: request.id,
      result: const NewSessionResponse(
        sessionId: SessionId('session-1'),
      ).toJson(),
    ),
  );
  await created;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

JsonRpcNotification _sessionUpdate(SessionUpdate update) =>
    JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: const SessionId('session-1'),
            update: update,
          ).toJson(),
        )
        as JsonRpcNotification;
