// Тесты сессий после переподключения (tasks 3.1 change
// `add-session-list-and-reload`; spec acp-client-kit «Сессии после
// переподключения», «Явный автомат соединения»; design D5).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

const _withLoad = AgentCapabilities(loadSession: true);

const _withLoadAndList = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

void main() {
  late KitAgent agent;

  tearDown(() => agent.dispose());

  List<String> texts(SessionHandle handle) => [
    for (final item in handle.current.transcript)
      switch (item) {
        UserItem(:final text) => 'user: $text',
        AgentTextItem(:final text) => 'agent: $text',
        NoticeItem(:final kind, :final text) => '${kind.name}: $text',
        _ => item.runtimeType.toString(),
      },
  ];

  /// Отвечает на `session/load` [request] реплеем с ответом [answer].
  Future<void> replay(
    Future<JsonRpcRequest> request,
    String sessionId,
    String answer,
  ) async {
    final load = await request;
    agent
      ..update(sessionId, {
        'sessionUpdate': 'user_message_chunk',
        'content': {'type': 'text', 'text': 'hello'},
      })
      ..update(sessionId, {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': answer},
      })
      ..respond(load, const <String, Object?>{});
  }

  /// Сессия с завершённым ходом `hello` → [answer].
  Future<SessionHandle> sessionWithTurn(String id, String answer) async {
    final handle = await agent.newSession(id);
    final turn = await agent.prompt(handle, 'hello');
    agent
      ..update(id, {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': answer},
      })
      ..respond(turn.request, const {'stopReason': 'end_turn'});
    await turn.done;
    return handle;
  }

  String loadedId(JsonRpcRequest request) =>
      LoadSessionRequest.fromJson(request.params).sessionId.value;

  test('reconnect() to an agent with loadSession reloads the open sessions, '
      'active first, replacing the transcript with the replay', () async {
    agent = KitAgent(capabilities: _withLoad);
    await agent.start();
    final a = await sessionWithTurn('s-a', 'old a');
    final b = await sessionWithTurn('s-b', 'old b');
    agent.workspace.activate(const SessionId('s-a'));

    agent.restartAgent(capabilities: _withLoad);
    final first = agent.next(sessionLoadMethod);
    final reconnecting = agent.workspace.reconnect();
    final firstLoad = await first;
    expect(loadedId(firstLoad), 's-a');
    final second = agent.next(sessionLoadMethod);
    await replay(Future.value(firstLoad), 's-a', 'replayed a');
    expect(loadedId(await second), 's-b');
    await replay(second, 's-b', 'replayed b');
    await reconnecting;

    expect(texts(a), ['user: hello', 'agent: replayed a']);
    expect(texts(b), ['user: hello', 'agent: replayed b']);
    expect(a.current.status, SessionStatusView.idle);
  });

  test('an agent without loadSession leaves every open session detached with '
      'a notice', () async {
    agent = KitAgent(capabilities: _withLoad);
    await agent.start();
    final a = await sessionWithTurn('s-a', 'old a');

    agent.restartAgent();
    await agent.workspace.reconnect();

    expect(a.current.status, SessionStatusView.detached);
    expect(
      texts(a).last,
      'detached: The agent cannot restore sessions after reconnecting.',
    );
    expect(texts(a).first, 'user: hello');
    expect(
      agent.workspace.current.sessions.single.status,
      SessionStatusView.detached,
    );
  });

  test('a failed session/load detaches only that session', () async {
    agent = KitAgent(capabilities: _withLoad);
    await agent.start();
    final a = await sessionWithTurn('s-a', 'old a');
    final b = await sessionWithTurn('s-b', 'old b');

    agent.restartAgent(capabilities: _withLoad);
    final first = agent.next(sessionLoadMethod);
    final reconnecting = agent.workspace.reconnect();
    final firstLoad = await first;
    final second = agent.next(sessionLoadMethod);
    agent.fail(firstLoad, 'Resource not found');
    await replay(second, loadedId(await second), 'replayed');
    await reconnecting;

    // Активная сессия — последняя созданная, `s-b`; она грузится первой.
    expect(loadedId(firstLoad), 's-b');
    expect(b.current.status, SessionStatusView.detached);
    expect(
      texts(b).last,
      'detached: Session s-b could not be restored after reconnecting.',
    );
    expect(a.current.status, SessionStatusView.idle);
    expect(texts(a), ['user: hello', 'agent: replayed']);
  });

  test('a prompt to a detached session fails without a frame and its queue '
      'does not drain', () async {
    agent = KitAgent(capabilities: _withLoad);
    await agent.start();
    final a = await sessionWithTurn('s-a', 'old a');
    final busy = await agent.prompt(a, 'long');
    await a.send('queued');
    expect(a.current.queue, hasLength(1));

    agent.restartAgent();
    await agent.workspace.reconnect();
    await busy.done;
    final sentBefore = agent.transport.sentMessages.length;

    final outcome = await a.send('after');

    expect(outcome, isA<PromptFailed>());
    expect(
      describeFailure((outcome as PromptFailed).error),
      'Session s-a is detached from the agent.',
    );
    expect(agent.transport.sentMessages, hasLength(sentBefore));
    expect(a.current.queue.map((q) => q.text), ['queued']);
    expect(await a.queue.sendNow(a.current.queue.single.id), isNull);
  });

  test('after reconnect() the session list is requested again', () async {
    agent = KitAgent(capabilities: _withLoadAndList);
    await agent.start(sessions: const ListSessionsResponse(sessions: []));

    agent.restartAgent(capabilities: _withLoadAndList);
    final list = agent.next(sessionListMethod);
    final reconnecting = agent.workspace.reconnect();
    agent.respond(
      await list,
      const ListSessionsResponse(
        sessions: [SessionInfo(sessionId: SessionId('s-old'), cwd: '/work')],
      ).toJson(),
    );
    await reconnecting;

    expect(
      agent.workspace.current.sessions.map((s) => (s.id.value, s.status)),
      [('s-old', SessionStatusView.notLoaded)],
    );
  });

  test('a failed reconnect() is one attempt', () async {
    agent = KitAgent(capabilities: _withLoad);
    await agent.start();
    final connections = <ConnectionView>[];
    final subscription = agent.workspace.state.listen(
      (state) => connections.add(state.connection),
    );
    addTearDown(subscription.cancel);

    agent.restartAgent();
    agent.transport.autoRespondToInitialize = false;
    final initialize = agent.next(initializeMethod);
    final reconnecting = agent.workspace.reconnect();
    agent.fail(await initialize, 'not now');
    await expectLater(reconnecting, throwsA(anything));

    expect(
      connections.whereType<Reconnecting>().map((view) => view.attempt).toSet(),
      {1},
    );
    expect(connections.last, isA<ConnectionFailed>());
    expect(
      agent.transport.sentMessages.whereType<JsonRpcRequest>().where(
        (request) => request.method == initializeMethod,
      ),
      hasLength(1),
    );
  });

  // Повторный Connect к новому процессу агента (в том числе к другому агенту
  // из диалога подключения) ведёт себя как Reconnect: открытые сессии
  // перезагружаются или становятся detached, а не остаются привязанными к
  // агенту, который их не знает (fix: «Session not found» после смены агента).
  group('connect() with open sessions', () {
    test('reloads the open sessions from an agent with loadSession', () async {
      agent = KitAgent(capabilities: _withLoad);
      await agent.start();
      final a = await sessionWithTurn('s-a', 'old a');

      agent.restartAgent(capabilities: _withLoad);
      final load = agent.next(sessionLoadMethod);
      final connecting = agent.workspace.connect(
        const StdioProfile(id: 'other', label: 'Other', command: 'other'),
        projectDirectory: '/work',
      );
      await replay(load, 's-a', 'replayed a');
      await connecting;

      expect(loadedId(await load), 's-a');
      expect(texts(a), ['user: hello', 'agent: replayed a']);
      expect(a.current.status, SessionStatusView.idle);
    });

    test('detaches the open sessions when the new agent cannot load them, '
        'and a prompt to them never reaches the agent', () async {
      agent = KitAgent(capabilities: _withLoad);
      await agent.start();
      final a = await sessionWithTurn('s-a', 'old a');

      agent.restartAgent();
      await agent.workspace.connect(
        const StdioProfile(id: 'other', label: 'Other', command: 'other'),
        projectDirectory: '/work',
      );

      expect(a.current.status, SessionStatusView.detached);
      agent.transport.drainSentMessages();
      final outcome = await a.send('hello again');
      expect(outcome, isA<PromptFailed>());
      expect(
        agent.transport.sentMessages.whereType<JsonRpcRequest>().where(
          (request) => request.method == sessionPromptMethod,
        ),
        isEmpty,
      );
    });
  });
}
