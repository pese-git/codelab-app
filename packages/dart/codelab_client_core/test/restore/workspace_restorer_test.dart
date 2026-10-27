// Тесты восстановления после перезапуска (tasks 4.1 change
// `add-session-list-and-reload`; spec acp-client-kit «Восстановление после
// перезапуска»; design D6).

import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

const _withLoad = AgentCapabilities(loadSession: true);

/// Снимок прошлого запуска: проект `/work`, активная `s-42`, открыты `s-42` и
/// `s-17`.
String _snapshot({int version = 1}) => jsonEncode({
  'version': version,
  'windows': {
    'main': {
      'projectDirectory': '/work',
      'activeSessionId': 's-42',
      'openSessions': [
        {'id': 's-42', 'cwd': '/work'},
        {'id': 's-17', 'cwd': '/work'},
      ],
    },
  },
});

void main() {
  late KitAgent agent;
  late InMemoryWorkspaceSnapshotStore store;

  tearDown(() => agent.dispose());

  List<String> sentMethods() => [
    for (final message in agent.transport.sentMessages)
      if (message is JsonRpcRequest) message.method,
  ];

  List<String> texts(SessionHandle handle) => [
    for (final item in handle.current.transcript)
      switch (item) {
        UserItem(:final text) => 'user: $text',
        AgentTextItem(:final text) => 'agent: $text',
        NoticeItem(:final kind, :final text) => '${kind.name}: $text',
        _ => item.runtimeType.toString(),
      },
  ];

  test('no snapshot: an ordinary start, nothing is restored', () async {
    store = InMemoryWorkspaceSnapshotStore();
    agent = KitAgent(capabilities: _withLoad, snapshots: store);

    expect(await agent.workspace.restoreProject(), isNull);
    await agent.start();

    expect(sentMethods(), [initializeMethod]);
    expect(agent.workspace.current.sessions, isEmpty);
  });

  for (final (name, value) in [
    ('broken JSON', '{not json'),
    ('an unknown version', _snapshot(version: 99)),
  ]) {
    test('$name is reported and removed; the start is ordinary', () async {
      store = InMemoryWorkspaceSnapshotStore(value);
      agent = KitAgent(capabilities: _withLoad, snapshots: store);
      final diagnostics = <WorkspaceDiagnostic>[];
      final subscription = agent.workspace.diagnostics.listen(diagnostics.add);
      addTearDown(subscription.cancel);

      expect(await agent.workspace.restoreProject(), isNull);

      expect(store.value, isNull);
      expect(
        diagnostics.single.message,
        'Workspace snapshot is invalid; starting fresh.',
      );
      await agent.start();
      expect(sentMethods(), [initializeMethod]);
    });
  }

  test('the project of the snapshot is given to the host before any '
      'connection', () async {
    store = InMemoryWorkspaceSnapshotStore(_snapshot());
    agent = KitAgent(capabilities: _withLoad, snapshots: store);

    expect(await agent.workspace.restoreProject(), '/work');
    expect(agent.transport.sentMessages, isEmpty);
  });

  test('an agent with loadSession: the active session is loaded and active, '
      'the other is notLoaded', () async {
    store = InMemoryWorkspaceSnapshotStore(_snapshot());
    agent = KitAgent(capabilities: _withLoad, snapshots: store);
    await agent.workspace.restoreProject();

    final load = agent.next(sessionLoadMethod);
    final connecting = agent.start();
    final request = await load;
    expect(LoadSessionRequest.fromJson(request.params).sessionId.value, 's-42');
    agent
      ..update('s-42', {
        'sessionUpdate': 'user_message_chunk',
        'content': {'type': 'text', 'text': 'hello'},
      })
      ..update('s-42', {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'hi'},
      })
      ..respond(request, const <String, Object?>{});
    await connecting;

    expect(agent.workspace.current.activeSessionId, const SessionId('s-42'));
    expect(
      agent.workspace.current.sessions.map((s) => (s.id.value, s.status)),
      [('s-42', SessionStatusView.idle), ('s-17', SessionStatusView.notLoaded)],
    );
    expect(texts(agent.workspace.session(const SessionId('s-42'))!), [
      'user: hello',
      'agent: hi',
    ]);
  });

  test('an agent without loadSession: a new session in the project with a '
      'notice', () async {
    store = InMemoryWorkspaceSnapshotStore(_snapshot());
    agent = KitAgent(snapshots: store);
    await agent.workspace.restoreProject();

    final create = agent.next(sessionNewMethod);
    final connecting = agent.start();
    final request = await create;
    expect(NewSessionRequest.fromJson(request.params).cwd, '/work');
    agent.respond(request, {'sessionId': 's-new'});
    await connecting;

    final active = agent.workspace.session(const SessionId('s-new'))!;
    expect(agent.workspace.current.activeSessionId, active.id);
    expect(texts(active), [
      'reconnected: The agent cannot restore sessions; a new session was '
          'started.',
    ]);
    expect(sentMethods(), isNot(contains(sessionLoadMethod)));
  });

  test('the notice about the new session stays where it happened: later '
      'turns go below it', () async {
    store = InMemoryWorkspaceSnapshotStore(_snapshot());
    agent = KitAgent(snapshots: store);
    await agent.workspace.restoreProject();

    final create = agent.next(sessionNewMethod);
    final connecting = agent.start();
    agent.respond(await create, {'sessionId': 's-new'});
    await connecting;
    final active = agent.workspace.session(const SessionId('s-new'))!;

    final turn = await agent.prompt(active, 'hello');
    agent
      ..update('s-new', {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'hi'},
      })
      ..respond(turn.request, {'stopReason': 'end_turn'});
    await turn.done;

    expect(texts(active), [
      'reconnected: The agent cannot restore sessions; a new session was '
          'started.',
      'user: hello',
      'agent: hi',
    ]);
  });

  test('a failed session/load: a new session with a notice, the id leaves '
      'the snapshot', () async {
    store = InMemoryWorkspaceSnapshotStore(_snapshot());
    agent = KitAgent(capabilities: _withLoad, snapshots: store);
    await agent.workspace.restoreProject();

    final load = agent.next(sessionLoadMethod);
    final create = agent.next(sessionNewMethod);
    final connecting = agent.start();
    agent.fail(await load, 'Resource not found');
    agent.respond(await create, {'sessionId': 's-new'});
    await connecting;
    await agent.workspace.flushSnapshot();

    final active = agent.workspace.session(const SessionId('s-new'))!;
    expect(texts(active), [
      'reconnected: Session s-42 could not be restored; a new session was '
          'started.',
    ]);
    final saved = jsonDecode(store.value!) as Map<String, Object?>;
    final window = (saved['windows']! as Map)['main'] as Map;
    expect(
      [for (final session in window['openSessions'] as List) session['id']],
      ['s-new', 's-17'],
    );
    expect(window['activeSessionId'], 's-new');
  });

  test('restoring happens once per run', () async {
    store = InMemoryWorkspaceSnapshotStore(_snapshot());
    agent = KitAgent(snapshots: store);
    await agent.workspace.restoreProject();
    final create = agent.next(sessionNewMethod);
    final connecting = agent.start();
    agent.respond(await create, {'sessionId': 's-new'});
    await connecting;

    agent.restartAgent();
    await agent.workspace.connect(
      const StdioProfile(id: 'agent', label: 'Agent', command: 'agent'),
      projectDirectory: '/work',
    );

    expect(sentMethods(), [initializeMethod]);
  });

  test('restoring sends no prompts and answers no approvals', () async {
    store = InMemoryWorkspaceSnapshotStore(_snapshot());
    agent = KitAgent(capabilities: _withLoad, snapshots: store);
    await agent.workspace.restoreProject();

    final load = agent.next(sessionLoadMethod);
    final connecting = agent.start();
    agent.respond(await load, const <String, Object?>{});
    await connecting;

    expect(sentMethods(), [initializeMethod, sessionLoadMethod]);
    expect(agent.transport.sentMessages.whereType<JsonRpcResponse>(), isEmpty);
  });
}
