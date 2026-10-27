// Ход, прерванный заменой транспорта (tasks 1.2 change
// `cancel-turn-on-ws-disconnect`; spec acp-protocol-client «Ход, прерванный
// заменой транспорта»; design D2, D3).
//
// Для MVP обрыв соединения отменяет ход и у stdio, и у WebSocket: агент не
// держит ход до переподключения. После `session/load` клиент показывает
// прерванный ход отменённым, а не завершённым без `stopReason`.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');

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

  AcpSession current() => client.sessionById(_session)!;

  /// Сессия с идущим ходом `long task`, транспорт которой заменён
  /// переподключением; возвращает новый транспорт.
  Future<FakeAcpTransport> interruptTurn() async {
    await _createSession(client, transport);
    transport.drainSentMessages();
    final prompt = client.sendPrompt(
      const SendPromptCommand(
        sessionId: _session,
        prompt: [ContentBlock.text(text: 'long task')],
      ),
    );
    // Ответ на `session/prompt` старого соединения не придёт: замена
    // транспорта проваливает запрос.
    unawaited(
      expectLater(prompt, throwsA(isA<AcpClientApplicationException>())),
    );
    await _pump();
    expect(current().activeTurn?.status, PromptTurnStatus.running);

    final replacement = FakeAcpTransport();
    addTearDown(replacement.close);
    await client.reconnect(
      ReconnectCommand(transportFactory: () => replacement),
    );
    replacement.drainSentMessages();
    return replacement;
  }

  /// `session/load` через [via] с реплеем реплики `long task`; ответ — после
  /// реплея.
  Future<AcpSession> load(FakeAcpTransport via) async {
    final future = client.loadSession(
      const LoadSessionCommand(sessionId: _session, cwd: '/workspace'),
    );
    await _pump();
    final request = via.drainSentMessages().single as JsonRpcRequest;
    expect(request.method, sessionLoadMethod);
    via
      ..emitInbound(
        _sessionUpdate(
          const SessionUpdate.userMessageChunk(
            content: ContentBlock.text(text: 'long task'),
          ),
        ),
      )
      ..emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: const LoadSessionResponse().toJson(),
        ),
      );
    return future;
  }

  test('the interrupted turn is shown cancelled after session/load', () async {
    final replacement = await interruptTurn();

    final session = await load(replacement);

    expect(session.activeTurn, isNull);
    expect(session.status, SessionLifecycleStatus.active);
    final turn = session.turns.single;
    expect(turn.prompt, const [ContentBlock.text(text: 'long task')]);
    expect(turn.status, PromptTurnStatus.cancelled);
    expect(turn.stopReason, StopReason.cancelled);
    expect(current(), session);
  });

  test('a late update after session/load does not reopen the turn', () async {
    final replacement = await interruptTurn();
    await load(replacement);

    replacement.emitInbound(
      _sessionUpdate(
        const SessionUpdate.agentMessageChunk(
          content: ContentBlock.text(text: 'stray'),
        ),
      ),
    );
    await _pump();

    expect(current().activeTurn, isNull);
    expect(current().turns.single.status, PromptTurnStatus.cancelled);
    expect(current().turns.single.updates, isEmpty);
  });

  test('a session that was not interrupted keeps completed turns', () async {
    final session = await load(transport);

    expect(session.turns.single.status, PromptTurnStatus.completed);
    expect(session.turns.single.stopReason, isNull);
  });

  test('a failed session/load keeps the mark for the next load', () async {
    final replacement = await interruptTurn();
    final failed = client.loadSession(
      const LoadSessionCommand(sessionId: _session, cwd: '/workspace'),
    );
    unawaited(expectLater(failed, throwsA(anything)));
    await _pump();
    final request = replacement.drainSentMessages().single as JsonRpcRequest;
    replacement.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        error: const JsonRpcError(code: -32603, message: 'busy'),
      ),
    );
    await _pump();

    final session = await load(replacement);

    expect(session.turns.single.status, PromptTurnStatus.cancelled);
  });

  test(
    'the mark is used once: a second load shows the history as is',
    () async {
      final replacement = await interruptTurn();
      await load(replacement);

      final again = await load(replacement);

      expect(again.turns.single.status, PromptTurnStatus.completed);
    },
  );
}

Future<void> _createSession(
  AcpClientApplication client,
  FakeAcpTransport transport,
) async {
  final future = client.createSession(
    const CreateSessionCommand(cwd: '/workspace'),
  );
  await _pump();
  final request = transport.sentMessages.single as JsonRpcRequest;
  transport.emitInbound(
    JsonRpcMessage.response(
      id: request.id,
      result: const NewSessionResponse(sessionId: _session).toJson(),
    ),
  );
  await future;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

JsonRpcNotification _sessionUpdate(SessionUpdate update) =>
    JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: _session,
            update: update,
          ).toJson(),
        )
        as JsonRpcNotification;
