// Тесты списка сессий проекта (tasks 2.1 change `add-session-list-and-reload`;
// spec acp-client-kit «Список и загрузка сессий проекта»; design D3).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/gated_workspace.dart';
import '../support/kit_agent.dart';

const _withList = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

const _twoSessions = ListSessionsResponse(
  sessions: [
    SessionInfo(
      sessionId: SessionId('sess-2'),
      cwd: '/work',
      title: 'Fix tests',
      updatedAt: '2026-10-26T10:00:00Z',
    ),
    SessionInfo(sessionId: SessionId('sess-1'), cwd: '/work', title: 'Plan'),
  ],
);

void main() {
  late KitAgent agent;

  tearDown(() => agent.dispose());

  List<(String, SessionStatusView, String?)> rows() => [
    for (final summary in agent.workspace.current.sessions)
      (summary.id.value, summary.status, summary.title),
  ];

  test('after connect() the first page lists the project sessions as '
      'notLoaded', () async {
    agent = KitAgent(capabilities: _withList);
    final request = agent.next(sessionListMethod);
    await agent.start(sessions: _twoSessions);

    expect(
      ListSessionsRequest.fromJson((await request).params),
      const ListSessionsRequest(cwd: '/work'),
    );
    expect(rows(), [
      ('sess-2', SessionStatusView.notLoaded, 'Fix tests'),
      ('sess-1', SessionStatusView.notLoaded, 'Plan'),
    ]);
    expect(
      agent.workspace.current.sessions.first.updatedAt,
      DateTime.utc(2026, 10, 26, 10),
    );
    expect(agent.workspace.current.hasMoreSessions, isFalse);
  });

  test('a session opened in this run is listed once, before the agent '
      'sessions', () async {
    agent = KitAgent(capabilities: _withList);
    await agent.start(sessions: _twoSessions);

    await agent.newSession('sess-1');

    expect(rows().map((row) => row.$1), ['sess-1', 'sess-2']);
    expect(rows().first.$2, SessionStatusView.idle);
    expect(rows().first.$3, 'Plan');
  });

  test('loadMoreSessions() appends the next page; a second call in flight '
      'is ignored; the last page clears hasMoreSessions', () async {
    agent = KitAgent(capabilities: _withList);
    await agent.start(
      sessions: const ListSessionsResponse(
        sessions: [SessionInfo(sessionId: SessionId('sess-3'), cwd: '/work')],
        nextCursor: 'page-2',
      ),
    );
    expect(agent.workspace.current.hasMoreSessions, isTrue);

    final request = agent.next(sessionListMethod);
    final more = agent.workspace.loadMoreSessions();
    final sentBefore = agent.transport.sentMessages.length;
    await agent.workspace.loadMoreSessions();
    final page = await request;
    expect(agent.transport.sentMessages, hasLength(sentBefore));
    expect(ListSessionsRequest.fromJson(page.params).cursor, 'page-2');
    agent.respond(page, _twoSessions.toJson());
    await more;

    expect(rows().map((row) => row.$1), ['sess-3', 'sess-2', 'sess-1']);
    expect(agent.workspace.current.hasMoreSessions, isFalse);
  });

  test('without sessionCapabilities.list nothing is requested', () async {
    agent = KitAgent();
    await agent.start();

    expect(
      agent.transport.sentMessages.whereType<JsonRpcRequest>().map(
        (request) => request.method,
      ),
      isNot(contains(sessionListMethod)),
    );
    expect(agent.workspace.current.sessions, isEmpty);
  });

  test('a failed list is a diagnostic; the connection stays up', () async {
    agent = KitAgent(capabilities: _withList);
    final request = agent.next(sessionListMethod);
    final connecting = agent.start();
    agent.fail(await request, 'journal unavailable');
    await connecting;

    expect(agent.workspace.current.connection, isA<Connected>());
    expect(agent.workspace.current.sessions, isEmpty);
    expect(agent.diagnostics.last.severity, DiagnosticSeverity.error);
    expect(
      agent.diagnostics.last.message,
      startsWith('Failed to list ACP sessions: '),
    );
  });

  // Список следует за выбранным проектом (D15, D17 change
  // `require-project-folder`; spec acp-client-kit «Смена проекта
  // перезапрашивает список»). Порядок ответов задаёт тест.
  group('project change', () {
    late GatedWorkspace host;

    // `tearDown` файла освобождает `agent`; ему нужен хоть какой-то
    // экземпляр, а этим тестам нужен свой.
    setUp(() => agent = KitAgent());
    tearDown(() => host.dispose());

    ListSessionsResponse page(String id, String cwd, {String? next}) =>
        ListSessionsResponse(
          sessions: [SessionInfo(sessionId: SessionId(id), cwd: cwd)],
          nextCursor: next,
        );

    /// Подключён к агенту; первая страница [project] отвечена.
    Future<FakeAcpTransport> connectedTo(
      String project, {
      ListSessionsResponse? first,
      AgentCapabilities capabilities = _withList,
    }) async {
      host = GatedWorkspace(capabilities: capabilities);
      final transport = host.resolver.transport();
      host.resolver.next().complete(transport);
      final hasList = capabilities.sessionCapabilities.list != null;
      final listed = hasList
          ? host.nextRequest(sessionListMethod, transport)
          : null;
      final connecting = host.workspace.connect(
        gatedProfile,
        projectDirectory: project,
      );
      if (listed != null) {
        host.respond(
          transport,
          await listed,
          (first ?? page('a-1', project)).toJson(),
        );
      }
      await connecting;
      return transport;
    }

    List<String> ids() => [
      for (final row in host.workspace.current.sessions) row.id.value,
    ];

    test('selectProject() while connected requests the new project list and '
        'replaces the old one', () async {
      final transport = await connectedTo('/work/a');
      expect(ids(), ['a-1']);

      final listed = host.nextRequest(sessionListMethod, transport, index: 1);
      host.workspace.selectProject('/work/b');
      final request = await listed;
      host.respond(transport, request, page('b-1', '/work/b').toJson());
      await pumpEventQueue();

      expect(ListSessionsRequest.fromJson(request.params).cwd, '/work/b');
      expect(ids(), ['b-1']);
    });

    test('a late answer for the previous project changes neither the list '
        'nor the cursor', () async {
      host = GatedWorkspace(capabilities: _withList);
      final transport = host.resolver.transport();
      host.resolver.next().complete(transport);
      final firstPage = host.nextRequest(sessionListMethod, transport);
      final connecting = host.workspace.connect(
        gatedProfile,
        projectDirectory: '/work/a',
      );
      final late = await firstPage;
      final second = host.nextRequest(sessionListMethod, transport, index: 1);
      host.workspace.selectProject('/work/b');
      final current = await second;

      host.respond(transport, current, page('b-1', '/work/b').toJson());
      host.respond(
        transport,
        late,
        page('a-1', '/work/a', next: 'a-2').toJson(),
      );
      await connecting;

      expect(ids(), ['b-1']);
      expect(host.workspace.current.hasMoreSessions, isFalse);
    });

    test('a loadMoreSessions() in flight does not block the list of the new '
        'project, and its late page is dropped', () async {
      final transport = await connectedTo(
        '/work/a',
        first: page('a-1', '/work/a', next: 'a-2'),
      );
      final more = host.nextRequest(sessionListMethod, transport, index: 1);
      final loadingMore = host.workspace.loadMoreSessions();
      final stale = await more;

      final first = host.nextRequest(sessionListMethod, transport, index: 2);
      host.workspace.selectProject('/work/b');
      final request = await first;
      host.respond(
        transport,
        request,
        page('b-1', '/work/b', next: 'b-2').toJson(),
      );
      await pumpEventQueue();
      // Страница нового проекта допускает собственный `loadMoreSessions`,
      // хотя запрос прежнего проекта ещё не вернулся.
      final next = host.nextRequest(sessionListMethod, transport, index: 3);
      final loadingNext = host.workspace.loadMoreSessions();
      final nextRequest = await next;
      expect(ListSessionsRequest.fromJson(nextRequest.params).cursor, 'b-2');
      host.respond(transport, stale, page('a-2', '/work/a').toJson());
      await loadingMore;
      host.respond(transport, nextRequest, page('b-2', '/work/b').toJson());
      await loadingNext;

      expect(ListSessionsRequest.fromJson(request.params).cwd, '/work/b');
      expect(ids(), ['b-1', 'b-2']);
      expect(host.workspace.current.hasMoreSessions, isFalse);
    });

    test('without sessionCapabilities.list nothing is requested', () async {
      final transport = await connectedTo(
        '/work/a',
        capabilities: const AgentCapabilities(),
      );

      host.workspace.selectProject('/work/b');
      await pumpEventQueue();

      expect(host.requests(sessionListMethod, on: transport), isEmpty);
      expect(host.workspace.current.projectDirectory, '/work/b');
    });

    test(
      'A -> B -> A while the agent starts: one open and the list of A',
      () async {
        host = GatedWorkspace(capabilities: _withList);
        final workspace = host.workspace..selectProject('/work/a');
        final gate = host.resolver.next();
        final transport = host.resolver.transport();
        final listed = host.nextRequest(sessionListMethod, transport);

        final starting = workspace.ensureAgent(
          '/work/a',
          profile: gatedProfile,
        );
        workspace
          ..selectProject('/work/b')
          ..selectProject('/work/a');
        gate.complete(transport);
        final request = await listed;
        host.respond(transport, request, page('a-1', '/work/a').toJson());
        await starting;

        expect(host.resolver.directories, ['/work/a']);
        expect(host.requests(sessionListMethod, on: transport), hasLength(1));
        expect(ListSessionsRequest.fromJson(request.params).cwd, '/work/a');
        expect(ids(), ['a-1']);
      },
    );
  });
}
