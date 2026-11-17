// Тесты правила «активная сессия снимка грузится только в папке проекта»
// (tasks A1.10 change `require-project-folder`; design D10, HIGH-1; spec
// acp-client-kit «Восстановление после перезапуска»).

import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

const _withLoad = AgentCapabilities(loadSession: true);

/// Снимок: проект `/work/app`, активная `s1` с [sessionCwd].
String _snapshot(String sessionCwd) => jsonEncode({
  'version': 1,
  'windows': {
    'main': {
      'projectDirectory': '/work/app',
      'activeSessionId': 's1',
      'openSessions': [
        {'id': 's1', 'cwd': sessionCwd},
      ],
    },
  },
});

void main() {
  late KitAgent agent;

  tearDown(() => agent.dispose());

  List<String> sentMethods() => [
    for (final message in agent.transport.sentMessages)
      if (message is JsonRpcRequest) message.method,
  ];

  test(
    'loadSession, cwd of the active session is outside the project: no '
    'session/load, no session/new, no activation, the row is notLoaded',
    () async {
      agent = KitAgent(
        capabilities: _withLoad,
        snapshots: InMemoryWorkspaceSnapshotStore(_snapshot('/')),
      );
      await agent.workspace.restoreProject();

      await agent.start(projectDirectory: '/work/app');

      expect(sentMethods(), [initializeMethod]);
      expect(agent.workspace.current.activeSessionId, isNull);
      expect(
        agent.workspace.current.sessions.map((s) => (s.id.value, s.status)),
        [('s1', SessionStatusView.notLoaded)],
      );
    },
  );

  test('no loadSession, cwd outside the project: no new session with a '
      'notice', () async {
    agent = KitAgent(snapshots: InMemoryWorkspaceSnapshotStore(_snapshot('/')));
    await agent.workspace.restoreProject();

    await agent.start(projectDirectory: '/work/app');

    expect(sentMethods(), [initializeMethod]);
    expect(agent.workspace.current.activeSessionId, isNull);
    expect(agent.workspace.current.sessions, isEmpty);
  });

  test('cwd equal to the project: loaded as before', () async {
    agent = KitAgent(
      capabilities: _withLoad,
      snapshots: InMemoryWorkspaceSnapshotStore(_snapshot('/work/app')),
    );
    await agent.workspace.restoreProject();

    final load = agent.next(sessionLoadMethod);
    final connecting = agent.start(projectDirectory: '/work/app');
    final request = await load;
    final params = LoadSessionRequest.fromJson(request.params);
    expect(params.sessionId.value, 's1');
    expect(params.cwd, '/work/app');
    agent.respond(request, const <String, Object?>{});
    await connecting;

    expect(agent.workspace.current.activeSessionId, const SessionId('s1'));
  });
}
