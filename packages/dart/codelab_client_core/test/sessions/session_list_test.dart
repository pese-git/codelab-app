// Тесты списка сессий проекта (tasks 2.1 change `add-session-list-and-reload`;
// spec acp-client-kit «Список и загрузка сессий проекта»; design D3).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

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
}
