// Тесты списка и загрузки сессий в рабочем месте (tasks 5.2 change
// `add-session-list-and-reload`; spec agent-workbench-ui «Sessions sidebar
// lists the project's sessions from the agent», «Selecting a not-loaded
// session restores its transcript»; design D7).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_cubit_characterization/harness.dart';

const _withListAndLoad = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

FakeAcpTransport _agent(AgentCapabilities capabilities) =>
    FakeAcpTransport()..initializeAgentCapabilities = capabilities;

void main() {
  setUp(setUpCharacterization);

  /// Подключается и отвечает на первый `session/list` страницей [page].
  Future<void> connectListing(ShellHarness h, ListSessionsResponse page) async {
    final list = h.nextSent(sessionListMethod);
    final connecting = h.cubit.connect();
    final request = await list as JsonRpcRequest;
    h.agent.emitInbound(
      JsonRpcMessage.response(id: request.id, result: page.toJson()),
    );
    await connecting;
  }

  List<(String, CodeLabSessionStatus, String)> rows(ShellHarness h) => [
    for (final row in h.cubit.state.sessions) (row.id, row.status, row.title),
  ];

  test('the sidebar lists open sessions first, then the agent sessions as '
      'not loaded', () async {
    final h = ShellHarness(agent: _agent(_withListAndLoad));
    await connectListing(
      h,
      const ListSessionsResponse(
        sessions: [
          SessionInfo(
            sessionId: SessionId('s-old'),
            cwd: '/work',
            title: 'Fix tests',
          ),
        ],
        nextCursor: 'page-2',
      ),
    );
    await h.createSession('s-new');

    expect(rows(h), [
      ('s-new', CodeLabSessionStatus.idle, 'New session'),
      ('s-old', CodeLabSessionStatus.notLoaded, 'Fix tests'),
    ]);
    expect(h.cubit.state.hasMoreSessions, isTrue);

    final more = h.nextSent(sessionListMethod);
    final loadingMore = h.cubit.loadMoreSessions();
    final page = await more as JsonRpcRequest;
    expect(ListSessionsRequest.fromJson(page.params).cursor, 'page-2');
    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: page.id,
        result: const ListSessionsResponse(
          sessions: [
            SessionInfo(sessionId: SessionId('s-older'), cwd: '/work'),
          ],
        ).toJson(),
      ),
    );
    await loadingMore;

    expect(rows(h).map((row) => row.$1), ['s-new', 's-old', 's-older']);
    expect(h.cubit.state.hasMoreSessions, isFalse);
  });

  test('selecting a not loaded session loads it and shows its replayed '
      'transcript', () async {
    final h = ShellHarness(agent: _agent(_withListAndLoad));
    await connectListing(
      h,
      const ListSessionsResponse(
        sessions: [SessionInfo(sessionId: SessionId('s-old'), cwd: '/work')],
      ),
    );

    final load = h.nextSent(sessionLoadMethod);
    h.cubit.selectSession('s-old');
    final request = await load as JsonRpcRequest;
    expect(LoadSessionRequest.fromJson(request.params).cwd, '/work');
    h
      ..sessionUpdate('s-old', {
        'sessionUpdate': 'user_message_chunk',
        'content': {'type': 'text', 'text': 'fix the tests'},
      })
      ..agentText('s-old', 'done');
    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const <String, Object?>{},
      ),
    );
    await h.settle();
    await h.settle();

    expect(h.cubit.state.activeSessionId, 's-old');
    expect(h.cubit.state.transcriptEntries.map((entry) => entry.body), [
      'fix the tests',
      'done',
    ]);
    expect(rows(h).single.$2, CodeLabSessionStatus.idle);
  });

  test(
    'a failed load keeps the active session and the not loaded row',
    () async {
      final h = ShellHarness(agent: _agent(_withListAndLoad));
      await connectListing(
        h,
        const ListSessionsResponse(
          sessions: [SessionInfo(sessionId: SessionId('s-old'), cwd: '/work')],
        ),
      );
      await h.createSession('s-new');

      final load = h.nextSent(sessionLoadMethod);
      h.cubit.selectSession('s-old');
      final request = await load as JsonRpcRequest;
      h.agent.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          error: const JsonRpcError(
            code: -32002,
            message: 'Resource not found',
          ),
        ),
      );
      await h.settle();
      await h.settle();

      expect(h.cubit.state.activeSessionId, 's-new');
      expect(rows(h).last.$2, CodeLabSessionStatus.notLoaded);
      expect(
        h.logEvents,
        contains(startsWith('Failed to load ACP session s-old: ')),
      );
    },
  );

  test(
    'a session the agent cannot restore after Reconnect is detached',
    () async {
      final first = _agent(const AgentCapabilities(loadSession: true));
      final second = _agent(const AgentCapabilities());
      final transports = [first, second];
      var starts = 0;
      final h = ShellHarness(
        agent: first,
        stdioTransportFactory: (_) => transports[starts++],
      );
      await h.connect();
      await h.createSession('s-a');

      await h.cubit.reconnect();
      await h.settle();

      expect(rows(h).single.$2, CodeLabSessionStatus.detached);
      expect(
        h.cubit.state.transcriptEntries.last.body,
        'The agent cannot restore sessions after reconnecting.',
      );
    },
  );
}
