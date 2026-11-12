// Ожидающие одобрения снимаются при замене и потере соединения (D22 change
// `require-project-folder`; AGENTS.md §9–§10: решение привязано к своему
// соединению и вызову, позднее решение по старому запросу ничего не меняет).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

void main() {
  late KitAgent agent;

  tearDown(() => agent.dispose());

  /// Сессия `s-1`, ход которой ждёт одобрения `call_1`.
  Future<(SessionHandle, ApprovalRequestId)> waitingForApproval(
    AgentCapabilities capabilities,
  ) async {
    agent = KitAgent(capabilities: capabilities);
    await agent.start();
    final handle = await agent.newSession('s-1');
    await agent.prompt(handle, 'go');
    agent.requestPermission(id: 7, sessionId: 's-1', toolCallId: 'call_1');
    await Future<void>.delayed(Duration.zero);
    final approval = handle.current.pendingApprovals.single;
    expect(handle.current.status, SessionStatusView.running);
    return (handle, approval.approvalId);
  }

  void expectDropped(SessionHandle handle) {
    expect(handle.current.pendingApprovals, isEmpty);
    final cards = handle.current.transcript
        .whereType<ToolCallItem>()
        .map((item) => item.approval)
        .whereType<PendingApprovalView>();
    expect(cards, isEmpty);
  }

  test('reconnect drops the approval of a detached session and a late '
      'decision sends nothing', () async {
    final (handle, approvalId) = await waitingForApproval(
      const AgentCapabilities(),
    );

    agent.restartAgent();
    await agent.workspace.reconnect();

    expect(handle.current.status, SessionStatusView.detached);
    expectDropped(handle);
    await expectLater(
      handle.respond(approvalId, const PermissionOptionId('allow-once')),
      throwsA(isA<StateTransitionException>()),
    );
    expect(agent.transport.sentMessages.whereType<JsonRpcResponse>(), isEmpty);
    expectDropped(handle);
  });

  test('a lost connection drops the approval', () async {
    final (handle, approvalId) = await waitingForApproval(
      const AgentCapabilities(),
    );

    agent.transport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'agent process exited',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expectDropped(handle);
    await expectLater(
      handle.respond(approvalId, const PermissionOptionId('allow-once')),
      throwsA(isA<StateTransitionException>()),
    );
  });

  const withLoad = AgentCapabilities(loadSession: true);

  List<JsonRpcResponse> responsesOf(FakeAcpTransport transport) =>
      transport.sentMessages.whereType<JsonRpcResponse>().toList();

  test('the dropped-approval diagnostic carries no tool input', () async {
    agent = KitAgent();
    await agent.start();
    final handle = await agent.newSession('s-1');
    await agent.prompt(handle, 'go');
    agent.requestPermission(
      id: 7,
      sessionId: 's-1',
      toolCallId: 'call_1',
      rawInput: const {'command': 'curl -H sk-test-leak-0123456789'},
    );
    await Future<void>.delayed(Duration.zero);

    agent.transport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'agent process exited',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final entries = agent.application.diagnostics
        .where((entry) => entry.message.contains('Pending permission'))
        .toList();
    expect(entries, hasLength(1));
    final text = '${entries.single.message} ${entries.single.context}';
    expect(text, isNot(contains('sk-test-leak')));
    expect(text, isNot(contains('rawInput')));
    expect(text, isNot(contains('curl')));
    expect(text, contains('permission-7'));
  });

  test('a resolved approval of another session is unchanged', () async {
    agent = KitAgent();
    await agent.start();
    final other = await agent.newSession('s-2');
    await agent.prompt(other, 'go');
    agent.requestPermission(id: 8, sessionId: 's-2', toolCallId: 'call_2');
    await Future<void>.delayed(Duration.zero);
    await other.respond(
      other.current.pendingApprovals.single.approvalId,
      const PermissionOptionId('allow-once'),
    );
    List<ApprovalStateView?> approvals() => [
      for (final item in other.current.transcript.whereType<ToolCallItem>())
        item.approval,
    ];
    final before = approvals();
    expect(before.single, isA<ResolvedApprovalView>());

    final handle = await agent.newSession('s-1');
    await agent.prompt(handle, 'go');
    agent.requestPermission(id: 7, sessionId: 's-1', toolCallId: 'call_1');
    await Future<void>.delayed(Duration.zero);
    agent.transport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'agent process exited',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(handle.current.pendingApprovals, isEmpty);
    expect(approvals(), before);
    expect(responsesOf(agent.transport), hasLength(1));
  });

  test('a cancelling turn holds no pending approval after the drop', () async {
    final (handle, _) = await waitingForApproval(const AgentCapabilities());
    await handle.cancel();

    agent.transport.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'agent process exited',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expectDropped(handle);
  });

  test('session/load after the restart rebuilds the turn and the queue '
      'survives', () async {
    final (handle, approvalId) = await waitingForApproval(withLoad);
    expect(await handle.send('queued'), isA<PromptQueued>());
    final old = agent.transport;

    agent.restartAgent(capabilities: withLoad);
    final load = agent.next(sessionLoadMethod);
    final prompt = agent.next(sessionPromptMethod);
    final reconnecting = agent.workspace.reconnect();
    agent.respond(await load, const <String, Object?>{});
    await reconnecting;

    expectDropped(handle);
    expect(handle.current.status, isNot(SessionStatusView.detached));
    final sent = await prompt;
    expect(PromptRequest.fromJson(sent.params).prompt, const [
      ContentBlock.text(text: 'queued'),
    ]);
    await expectLater(
      handle.respond(approvalId, const PermissionOptionId('allow-once')),
      throwsA(isA<StateTransitionException>()),
    );
    expect(responsesOf(old), isEmpty);
    expect(responsesOf(agent.transport), isEmpty);
  });

  // Гонка: ответ пользователя и замена соединения в одном такте. Либо ответ
  // ушёл в старый транспорт и одобрение решено, либо ничего не ушло и оно
  // снято: «агент получил allow, а состояние cancelled» недопустимо.
  test('a user decision during the replacement is consistent', () async {
    final (handle, approvalId) = await waitingForApproval(withLoad);
    final old = agent.transport;

    final decision = handle.respond(
      approvalId,
      const PermissionOptionId('allow-once'),
    );
    agent.restartAgent(capabilities: withLoad);
    final load = agent.next(sessionLoadMethod);
    final reconnecting = agent.workspace.reconnect();
    Object? error;
    try {
      await decision;
    } on Object catch (e) {
      error = e;
    }
    agent.respond(await load, const <String, Object?>{});
    await reconnecting;

    expect(responsesOf(old).isNotEmpty, error == null);
    expect(responsesOf(agent.transport), isEmpty);
    expectDropped(handle);
  });

  // Принудительный порядок без таймеров: ответ на запрос завис в `send`
  // старого транспорта, соединение заменяется, и лишь потом `send` завершается.
  test('a response finishing after the replacement does not swallow the same '
      'JSON-RPC id of the new connection', () async {
    const caps = AgentCapabilities(loadSession: true);
    final gate = Completer<void>();
    final oldAgent = FakeAcpTransport()..initializeAgentCapabilities = caps;
    final newAgent = FakeAcpTransport()..initializeAgentCapabilities = caps;
    final transports = <AcpTransport>[
      _GatedResponseTransport(oldAgent, gate.future),
      newAgent,
    ];
    final application = AcpClientApplication(transport: FakeAcpTransport());
    final workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [
        ConfigTransportResolver(stdio: (_) => transports.removeAt(0)),
      ],
    );
    addTearDown(() async {
      await workspace.dispose();
      await application.dispose();
    });
    Future<JsonRpcRequest> next(FakeAcpTransport t, String method) async =>
        await t.sent.firstWhere(
              (m) => m is JsonRpcRequest && m.method == method,
            )
            as JsonRpcRequest;
    void reply(FakeAcpTransport t, JsonRpcRequest r, Object? result) =>
        t.emitInbound(JsonRpcMessage.response(id: r.id, result: result));
    void permission(FakeAcpTransport t, String call) => t.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(7),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: const SessionId('s-1'),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(call),
            title: 'Run $call',
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

    await workspace.connect(
      const StdioProfile(id: 'agent', label: 'Agent', command: 'agent'),
      projectDirectory: '/work',
    );
    final created = next(oldAgent, sessionNewMethod);
    final pending = workspace.newSession();
    reply(oldAgent, await created, {'sessionId': 's-1'});
    final handle = await pending;
    final prompted = next(oldAgent, sessionPromptMethod);
    unawaited(handle.send('go'));
    await prompted;
    permission(oldAgent, 'call_1');
    await Future<void>.delayed(Duration.zero);
    final approvalId = handle.current.pendingApprovals.single.approvalId;

    final decision = handle
        .respond(approvalId, const PermissionOptionId('allow-once'))
        .then<Object?>((_) => null, onError: (Object e) => e);

    final load = next(newAgent, sessionLoadMethod);
    final reconnecting = workspace.reconnect();
    reply(newAgent, await load, const <String, Object?>{});
    await reconnecting;
    gate.complete();
    await decision;

    final second = next(newAgent, sessionPromptMethod);
    unawaited(handle.send('again'));
    await second;
    permission(newAgent, 'call_9');
    await Future<void>.delayed(Duration.zero);

    final fresh = handle.current.pendingApprovals.single;
    await handle.respond(
      fresh.approvalId,
      const PermissionOptionId('allow-once'),
    );
    expect(responsesOf(newAgent), hasLength(1));
  });
}

/// Транспорт, у которого отправка ответа агенту завершается по сигналу теста.
final class _GatedResponseTransport implements AcpTransport {
  _GatedResponseTransport(this._inner, this._gate);

  final FakeAcpTransport _inner;
  final Future<void> _gate;

  @override
  Stream<JsonRpcMessage> get inbound => _inner.inbound;

  @override
  Stream<AcpTransportEvent> get events => _inner.events;

  @override
  AcpTransportState get state => _inner.state;

  @override
  Future<void> start() => _inner.start();

  @override
  Future<void> close({Duration? timeout}) => _inner.close(timeout: timeout);

  @override
  Future<void> send(JsonRpcMessage message) async {
    await _inner.send(message);
    if (message is JsonRpcResponse) {
      await _gate;
    }
  }
}
