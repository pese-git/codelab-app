// Ход, переживший переподключение (tasks 1.2 change
// `add-resumed-turn-after-reload`; spec acp-protocol-client «Ход, переживший
// переподключение»; design D1–D5).
//
// Агент CodeLab держит ход закрытого соединения `detachGrace` и после
// `session/load` с нового соединения продолжает его: обновления хода и итог
// `_meta.codelab.turnEnded` приходят уже после ответа на `session/load`
// (`agent-core/13-acp-adapter.md` §13.5, шаги 3b, 8, 9).

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

  /// `session/load` с реплеем [replay] через [via]; ответ — после реплея.
  Future<AcpSession> load(
    FakeAcpTransport via, {
    List<SessionUpdate> replay = const [
      SessionUpdate.userMessageChunk(
        content: ContentBlock.text(text: 'long task'),
      ),
    ],
  }) async {
    final future = client.loadSession(
      const LoadSessionCommand(sessionId: _session, cwd: '/workspace'),
    );
    await _pump();
    final request = via.drainSentMessages().single as JsonRpcRequest;
    expect(request.method, sessionLoadMethod);
    for (final update in replay) {
      via.emitInbound(_sessionUpdate(update));
    }
    via.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const LoadSessionResponse().toJson(),
      ),
    );
    final session = await future;
    expect(session.activeTurn, isNull, reason: 'replay turns are completed');
    return session;
  }

  Future<void> emit(FakeAcpTransport via, SessionUpdate update) async {
    via.emitInbound(_sessionUpdate(update));
    await _pump();
  }

  test('a late agent_message_chunk resumes the interrupted turn', () async {
    final replacement = await interruptTurn();
    await load(replacement);

    await emit(
      replacement,
      const SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: 'echo: long task'),
      ),
    );

    final session = current();
    expect(session.status, SessionLifecycleStatus.runningTurn);
    expect(session.turns, hasLength(1));
    final turn = session.activeTurn!;
    expect(turn.status, PromptTurnStatus.running);
    expect(turn.prompt, const [ContentBlock.text(text: 'long task')]);
    expect(turn.updates, const [
      SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: 'echo: long task'),
      ),
    ]);

    // Отмена возобновлённого хода — обычный `session/cancel`.
    await client.cancelTurn(const CancelTurnCommand(sessionId: _session));
    final cancel = replacement.drainSentMessages().single;
    expect(cancel, isA<JsonRpcNotification>());
    expect((cancel as JsonRpcNotification).method, sessionCancelMethod);
  });

  test('turnEnded with a stopReason completes the resumed turn', () async {
    final replacement = await interruptTurn();
    await load(replacement);
    await emit(
      replacement,
      const SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: 'echo: long task'),
      ),
    );

    await emit(replacement, _turnEnded({'stopReason': 'end_turn'}));

    final session = current();
    expect(session.activeTurn, isNull);
    expect(session.status, SessionLifecycleStatus.active);
    expect(session.turns.single.status, PromptTurnStatus.completed);
    expect(session.turns.single.stopReason, StopReason.endTurn);
    expect(session.turns.single.updates, hasLength(1));
  });

  test('turnEnded with an error fails the resumed turn', () async {
    final replacement = await interruptTurn();
    await load(replacement);
    await emit(
      replacement,
      const SessionUpdate.agentThoughtChunk(
        content: ContentBlock.text(text: 'thinking'),
      ),
    );

    await emit(
      replacement,
      _turnEnded({
        'error': {
          'errorClass': 'provider',
          'message': 'upstream failed',
          'retryable': true,
        },
      }),
    );

    final turn = current().turns.single;
    expect(turn.status, PromptTurnStatus.failed);
    expect(turn.failureMessage, 'upstream failed');
    expect(current().activeTurn, isNull);
  });

  test('an unrecognized turnEnded fails the resumed turn', () async {
    final replacement = await interruptTurn();
    await load(replacement);
    await emit(
      replacement,
      const SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: 'partial'),
      ),
    );

    await emit(replacement, _turnEnded({'stopReason': 'galaxy_brain'}));

    final turn = current().turns.single;
    expect(turn.status, PromptTurnStatus.failed);
    expect(turn.failureMessage, contains('turnEnded'));
  });

  test('turnEnded alone resumes and closes the last turn', () async {
    final replacement = await interruptTurn();
    await load(replacement);

    await emit(replacement, _turnEnded({'stopReason': 'cancelled'}));

    final session = current();
    expect(session.activeTurn, isNull);
    expect(session.turns.single.status, PromptTurnStatus.cancelled);
    expect(session.turns.single.stopReason, StopReason.cancelled);
  });

  test('a re-sent permission request resumes the turn with a new '
      'approval', () async {
    final replacement = await interruptTurn();
    await load(replacement);

    replacement.emitInbound(_permissionRequest(id: 77));
    await _pump();

    final turn = current().activeTurn;
    expect(turn, isNotNull);
    expect(turn!.status, PromptTurnStatus.awaitingApproval);
    final approval = turn.approvals.values.single;
    expect(approval.toolCall.id, const ToolCallId('call_1'));
    expect(approval.isResolved, isFalse);
    // Запрос ждёт решения пользователя, а не получает `cancelled`.
    expect(replacement.sentMessages, isEmpty);
  });

  test('without a continuation the replayed turns stay completed', () async {
    final replacement = await interruptTurn();
    final session = await load(replacement);
    await _pump();

    expect(current(), session);
    expect(current().turns.single.status, PromptTurnStatus.completed);
  });

  test(
    'a late update of a session that was not interrupted is dropped',
    () async {
      await load(transport);

      await emit(
        transport,
        const SessionUpdate.agentMessageChunk(
          content: ContentBlock.text(text: 'stray'),
        ),
      );

      expect(current().activeTurn, isNull);
      expect(current().turns.single.updates, isEmpty);
    },
  );

  test('a new prompt ends the wait for a continuation', () async {
    final replacement = await interruptTurn();
    await load(replacement);

    final prompt = client.sendPrompt(
      const SendPromptCommand(
        sessionId: _session,
        prompt: [ContentBlock.text(text: 'next')],
      ),
    );
    await _pump();
    final request = replacement.drainSentMessages().single as JsonRpcRequest;
    replacement.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
      ),
    );
    await prompt;

    await emit(
      replacement,
      const SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: 'stray'),
      ),
    );

    expect(current().activeTurn, isNull);
    expect(current().turns, hasLength(2));
    expect(current().turns.last.updates, isEmpty);
  });

  test('a failed session/load ends the wait for a continuation', () async {
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
        error: const JsonRpcError(code: -32602, message: 'sessionBusy'),
      ),
    );
    await _pump();

    await load(replacement);
    await emit(
      replacement,
      const SessionUpdate.agentMessageChunk(
        content: ContentBlock.text(text: 'stray'),
      ),
    );

    expect(current().activeTurn, isNull);
  });

  test('turnEnded does not settle a live turn of this connection', () async {
    await _createSession(client, transport);
    transport.drainSentMessages();
    // Ответа на `session/prompt` в тесте нет: `dispose` провалит запрос.
    client
        .sendPrompt(
          const SendPromptCommand(
            sessionId: _session,
            prompt: [ContentBlock.text(text: 'live')],
          ),
        )
        .ignore();
    await _pump();

    await emit(transport, _turnEnded({'stopReason': 'end_turn'}));

    expect(current().activeTurn?.status, PromptTurnStatus.running);
  });
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

SessionUpdate _turnEnded(Map<String, Object?> ended) =>
    SessionUpdate.sessionInfoUpdate(
      meta: {
        'codelab': {'turnEnded': ended},
      },
    );

JsonRpcNotification _sessionUpdate(SessionUpdate update) =>
    JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: _session,
            update: update,
          ).toJson(),
        )
        as JsonRpcNotification;

JsonRpcRequest _permissionRequest({required int id}) =>
    JsonRpcMessage.request(
          id: JsonRpcId.integer(id),
          method: sessionRequestPermissionMethod,
          params: const RequestPermissionRequest(
            sessionId: _session,
            toolCall: ToolCallUpdate(
              toolCallId: ToolCallId('call_1'),
              title: 'echo hello',
              kind: ToolKind.execute,
            ),
            options: [
              PermissionOption(
                optionId: PermissionOptionId('allow-once'),
                name: 'Allow once',
                kind: PermissionOptionKind.allowOnce,
              ),
            ],
          ).toJson(),
        )
        as JsonRpcRequest;
