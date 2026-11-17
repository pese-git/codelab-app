// Тесты загрузки сессии из списка (tasks 2.2 change
// `add-session-list-and-reload`; spec acp-client-kit «Список и загрузка
// сессий проекта»; design D4).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

const _withLoad = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

const _listed = ListSessionsResponse(
  sessions: [
    SessionInfo(sessionId: SessionId('sess-1'), cwd: '/work', title: 'Plan'),
  ],
);

void main() {
  late KitAgent agent;

  tearDown(() => agent.dispose());

  /// Загружает [sessionId] и отвечает на `session/load` реплеем: реплика
  /// пользователя и ответ агента.
  Future<SessionHandle> load(String sessionId, {String answer = 'done'}) async {
    final next = agent.next(sessionLoadMethod);
    final loading = agent.workspace.loadSession(
      SessionId(sessionId),
      cwd: '/work',
    );
    final request = await next;
    agent
      ..update(sessionId, {
        'sessionUpdate': 'user_message_chunk',
        'content': {'type': 'text', 'text': 'fix the tests'},
      })
      ..update(sessionId, {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': answer},
      })
      ..respond(request, const <String, Object?>{});
    return loading;
  }

  List<String> texts(SessionHandle handle) => [
    for (final item in handle.current.transcript)
      switch (item) {
        UserItem(:final text) => 'user: $text',
        AgentTextItem(:final text) => 'agent: $text',
        _ => item.runtimeType.toString(),
      },
  ];

  test('loadSession builds the transcript from the replay and registers '
      'the handle', () async {
    agent = KitAgent(capabilities: _withLoad);
    await agent.start(sessions: _listed);

    final handle = await load('sess-1');

    expect(handle.id, const SessionId('sess-1'));
    expect(agent.workspace.session(const SessionId('sess-1')), same(handle));
    expect(texts(handle), ['user: fix the tests', 'agent: done']);
    final row = agent.workspace.current.sessions.single;
    expect(row.status, SessionStatusView.idle);
    expect(row.title, 'Plan');
  });

  test('a second call while loading sends no second session/load', () async {
    agent = KitAgent(capabilities: _withLoad);
    await agent.start(sessions: _listed);

    final next = agent.next(sessionLoadMethod);
    final first = agent.workspace.loadSession(
      const SessionId('sess-1'),
      cwd: '/work',
    );
    final second = agent.workspace.loadSession(
      const SessionId('sess-1'),
      cwd: '/work',
    );
    agent.respond(await next, const <String, Object?>{});

    expect(await second, same(await first));
    expect(
      agent.transport.sentMessages.whereType<JsonRpcRequest>().where(
        (request) => request.method == sessionLoadMethod,
      ),
      hasLength(1),
    );
  });

  test('without loadSession the call fails and sends nothing', () async {
    agent = KitAgent();
    await agent.start();
    final sentBefore = agent.transport.sentMessages.length;

    await expectLater(
      agent.workspace.loadSession(const SessionId('sess-1'), cwd: '/work'),
      throwsA(isA<ClientWorkspaceException>()),
    );
    expect(agent.transport.sentMessages, hasLength(sentBefore));
  });

  test('a failed load keeps the row notLoaded and reports', () async {
    agent = KitAgent(capabilities: _withLoad);
    await agent.start(sessions: _listed);

    final request = agent.next(sessionLoadMethod);
    final loading = agent.workspace.loadSession(
      const SessionId('sess-1'),
      cwd: '/work',
    );
    agent.fail(await request, 'Resource not found');

    await expectLater(loading, throwsA(anything));
    expect(agent.workspace.session(const SessionId('sess-1')), isNull);
    expect(
      agent.workspace.current.sessions.single.status,
      SessionStatusView.notLoaded,
    );
    expect(
      agent.diagnostics.last.message,
      startsWith('Failed to load ACP session sess-1: '),
    );
  });

  test('loading an open session again rebuilds its transcript from the '
      'replay instead of appending', () async {
    agent = KitAgent(capabilities: _withLoad);
    await agent.start(sessions: _listed);

    final handle = await load('sess-1');

    expect(await load('sess-1', answer: 'done again'), same(handle));

    expect(texts(handle), ['user: fix the tests', 'agent: done again']);
  });

  // D16 change `require-project-folder`: фокус на `detached`-сессии у
  // работающего агента с `loadSession` загружает её, а не ждёт перезапуска.
  group('a detached session', () {
    /// Открытая сессия `s-a` с занятым ходом и одним отложенным промптом;
    /// после переподключения её `session/load` падает — сессия `detached`.
    Future<SessionHandle> detachedWithQueue() async {
      // Без `session/list`: тест не отвечает на список.
      const loadOnly = AgentCapabilities(loadSession: true);
      agent = KitAgent(capabilities: loadOnly);
      await agent.start();
      final handle = await agent.newSession('s-a');
      final busy = await agent.prompt(handle, 'long');
      await handle.send('queued');

      agent.restartAgent(capabilities: loadOnly);
      final firstLoad = agent.next(sessionLoadMethod);
      final reconnecting = agent.workspace.reconnect();
      agent.fail(await firstLoad, 'Resource not found');
      await reconnecting;
      await busy.done;
      expect(handle.current.status, SessionStatusView.detached);
      expect(handle.current.queue.map((q) => q.text), ['queued']);
      return handle;
    }

    test('loadSession() makes it receive prompts again: the queue drains '
        'after the load and send() reaches the agent', () async {
      final handle = await detachedWithQueue();

      final load = agent.next(sessionLoadMethod);
      final drained = agent.next(sessionPromptMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('s-a'),
        cwd: '/work',
      );
      agent.respond(await load, const <String, Object?>{});
      expect(await loading, same(handle));

      expect(handle.current.status, isNot(SessionStatusView.detached));
      final queued = await drained;
      expect(
        PromptRequest.fromJson(queued.params).prompt.single,
        isA<TextContent>().having((b) => b.text, 'text', 'queued'),
      );
      expect(handle.current.queue, isEmpty);
      expect(
        agent.workspace.current.sessions.single.status,
        SessionStatusView.running,
      );

      agent.respond(queued, const {'stopReason': 'end_turn'});
      await pumpEventQueue();
      final after = agent.next(sessionPromptMethod);
      final sending = handle.send('after');
      final request = await after;
      agent.respond(request, const {'stopReason': 'end_turn'});
      expect(await sending, isA<PromptCompleted>());
    });

    test('a failed load keeps it detached with the previous notice and '
        'reports the error', () async {
      final handle = await detachedWithQueue();

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('s-a'),
        cwd: '/work',
      );
      agent.fail(await load, 'Resource not found');

      await expectLater(loading, throwsA(anything));
      expect(handle.current.status, SessionStatusView.detached);
      expect(
        // Уведомление стоит на месте обрыва, ниже него могут быть итоги
        // оборванного хода.
        handle.current.transcript,
        contains(
          isA<NoticeItem>().having(
            (notice) => notice.text,
            'text',
            'Session s-a could not be restored after reconnecting.',
          ),
        ),
      );
      expect(handle.current.queue.map((q) => q.text), ['queued']);
      expect(
        agent.diagnostics.last.message,
        startsWith('Failed to load ACP session s-a: '),
      );
    });
  });
}
