import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(transport: transport);
  });

  tearDown(() async {
    await client.dispose();
    await transport.close();
  });

  test('CreateSession sends session/new and stores active session', () async {
    final changes = <AcpSession>[];
    final subscription = client.sessionChanges.listen(changes.add);
    final createSession = CreateSession(client);

    final future = createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    ).run();
    await _pump();

    final request = transport.sentMessages.single as JsonRpcRequest;
    expect(request.method, sessionNewMethod);
    expect(
      NewSessionRequest.fromJson(request.params),
      const NewSessionRequest(cwd: '/workspace', mcpServers: []),
    );

    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(
          sessionId: SessionId('session-1'),
        ).toJson(),
      ),
    );

    final result = await future;
    final session = result.getOrElse((failure) => fail('$failure'));
    expect(session.id, const SessionId('session-1'));
    expect(session.cwd, '/workspace');
    expect(session.status, SessionLifecycleStatus.active);
    expect(client.sessionById(const SessionId('session-1')), session);
    expect(changes.single, session);

    await subscription.cancel();
  });

  test('SendPrompt streams updates and completes from stopReason', () async {
    await _createSession(client, transport);
    transport.drainSentMessages();

    final changes = <AcpSession>[];
    final subscription = client.sessionChanges.listen(changes.add);
    final sendPrompt = SendPrompt(client);

    final future = sendPrompt(
      const SendPromptCommand(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    ).run();
    await _pump();

    final request = transport.sentMessages.single as JsonRpcRequest;
    expect(request.method, sessionPromptMethod);
    expect(
      PromptRequest.fromJson(request.params),
      const PromptRequest(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    );
    expect(changes.single.status, SessionLifecycleStatus.runningTurn);
    expect(changes.single.turns.single.status, PromptTurnStatus.running);

    transport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: const SessionNotification(
          sessionId: SessionId('session-1'),
          update: SessionUpdate.agentMessageChunk(
            content: ContentBlock.text(text: 'hi'),
          ),
        ).toJson(),
      ),
    );

    final updated = client.sessionById(const SessionId('session-1'));
    expect(updated?.turns.single.updates, hasLength(1));
    expect(updated?.turns.single.status, PromptTurnStatus.running);

    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
      ),
    );

    final result = await future;
    final turn = result.getOrElse((failure) => fail('$failure'));
    expect(turn.status, PromptTurnStatus.completed);
    expect(turn.stopReason, StopReason.endTurn);
    expect(turn.updates.single, isA<AgentMessageChunk>());

    final session = client.sessionById(const SessionId('session-1'));
    expect(session?.status, SessionLifecycleStatus.active);
    expect(session?.turns.single, turn);
    expect(changes.map((session) => session.status), [
      SessionLifecycleStatus.runningTurn,
      SessionLifecycleStatus.runningTurn,
      SessionLifecycleStatus.active,
    ]);

    await subscription.cancel();
  });

  test('SendPrompt returns typed failure when session is missing', () async {
    final sendPrompt = SendPrompt(client);

    final result = await sendPrompt(
      const SendPromptCommand(
        sessionId: SessionId('missing-session'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    ).run();

    expect(result.isLeft(), isTrue);
    result.match((failure) {
      expect(failure, isA<AcpClientMissingSessionFailure>());
      expect(
        (failure as AcpClientMissingSessionFailure).sessionId,
        const SessionId('missing-session'),
      );
    }, (_) => fail('expected missing session failure'));
    expect(transport.sentMessages, isEmpty);
  });
}

Future<void> _createSession(
  AcpClientApplication client,
  FakeAcpTransport transport,
) async {
  final future = CreateSession(client)(
    const CreateSessionCommand(cwd: '/workspace'),
  ).run();
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
  final result = await future;
  result.getOrElse((failure) => fail('$failure'));
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
