// Тесты записи снимка рабочего пространства (tasks 4.2 change
// `add-session-list-and-reload`; spec acp-client-kit «Восстановление после
// перезапуска»; design D6).

import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

const _withLoadAndList = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

/// Хранилище, запись в которое завершается только по команде теста.
final class _SlowStore implements WorkspaceSnapshotStore {
  final writes = <String>[];
  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();

  void release() => _gate?.complete();

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String snapshot) async {
    writes.add(snapshot);
    await _gate?.future;
  }

  @override
  Future<void> clear() async {}
}

final class _FailingStore implements WorkspaceSnapshotStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String snapshot) => Future.error(StateError('disk full'));

  @override
  Future<void> clear() async {}
}

Map<String, Object?> _window(String json) {
  final decoded = jsonDecode(json) as Map<String, Object?>;
  expect(decoded['version'], 1);
  return ((decoded['windows']! as Map)['main']! as Map).cast<String, Object?>();
}

void main() {
  late KitAgent agent;

  tearDown(() => agent.dispose());

  test('the snapshot follows new, loaded and activated sessions and the '
      'project', () async {
    final store = InMemoryWorkspaceSnapshotStore();
    agent = KitAgent(capabilities: _withLoadAndList, snapshots: store);
    await agent.workspace.restoreProject();
    agent.workspace.selectProject('/work');
    await agent.workspace.flushSnapshot();
    expect(_window(store.value!)['projectDirectory'], '/work');

    await agent.start(
      sessions: const ListSessionsResponse(
        sessions: [SessionInfo(sessionId: SessionId('s-old'), cwd: '/work')],
      ),
    );
    await agent.newSession('s-a');
    await agent.workspace.flushSnapshot();
    expect(_window(store.value!), {
      'projectDirectory': '/work',
      'activeSessionId': 's-a',
      'openSessions': [
        {'id': 's-a', 'cwd': '/work'},
      ],
    });

    final load = agent.next(sessionLoadMethod);
    final loading = agent.workspace.loadSession(
      const SessionId('s-old'),
      cwd: '/work',
    );
    agent.respond(await load, const <String, Object?>{});
    await loading;
    agent.workspace.activate(const SessionId('s-old'));
    await agent.workspace.flushSnapshot();

    final window = _window(store.value!);
    expect(window['activeSessionId'], 's-old');
    expect(
      [for (final session in window['openSessions']! as List) session['id']],
      ['s-old', 's-a'],
    );
  });

  test('a burst of changes is one write; changes during a write are '
      'coalesced into one next write; dispose waits for it', () async {
    final store = _SlowStore();
    agent = KitAgent(snapshots: store);
    await agent.workspace.restoreProject();

    store.hold();
    agent.workspace
      ..selectProject('/one')
      ..selectProject('/two');
    await Future<void>.delayed(Duration.zero);
    expect(store.writes.map((json) => _window(json)['projectDirectory']), [
      '/two',
    ]);

    agent.workspace
      ..selectProject('/three')
      ..selectProject('/four');
    store.release();
    await agent.workspace.flushSnapshot();
    expect(store.writes.map((json) => _window(json)['projectDirectory']), [
      '/two',
      '/four',
    ]);

    store.hold();
    agent.workspace.selectProject('/five');
    var disposed = false;
    final disposing = agent.workspace.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    store.release();
    await disposing;
    expect(_window(store.writes.last)['projectDirectory'], '/five');
  });

  test('a failed write is a diagnostic, not a failed operation', () async {
    agent = KitAgent(snapshots: _FailingStore());
    final diagnostics = <WorkspaceDiagnostic>[];
    final subscription = agent.workspace.diagnostics.listen(diagnostics.add);
    addTearDown(subscription.cancel);
    await agent.workspace.restoreProject();

    agent.workspace.selectProject('/work');
    await agent.workspace.flushSnapshot();

    expect(diagnostics.single.severity, DiagnosticSeverity.warning);
    expect(
      diagnostics.single.message,
      startsWith('Failed to save workspace snapshot: '),
    );
  });

  test('the snapshot holds no cursor, transcript, queue or secrets', () async {
    final store = InMemoryWorkspaceSnapshotStore();
    agent = KitAgent(capabilities: _withLoadAndList, snapshots: store);
    await agent.workspace.restoreProject();
    await agent.start(
      sessions: const ListSessionsResponse(
        sessions: [],
        nextCursor: 'opaque-cursor',
      ),
    );
    final session = await agent.newSession('s-a');
    final turn = await agent.prompt(session, 'secret prompt text');
    expect(turn.request.method, sessionPromptMethod);
    await session.send('queued prompt text');
    expect(session.current.queue, hasLength(1));
    await agent.workspace.flushSnapshot();

    final saved = store.value!;
    expect(saved, isNot(contains('opaque-cursor')));
    expect(saved, isNot(contains('secret prompt text')));
    expect(saved, isNot(contains('queued prompt text')));
    expect(saved, isNot(contains('agent')));
    expect(_window(saved).keys.toSet(), {
      'projectDirectory',
      'activeSessionId',
      'openSessions',
    });
  });
}
