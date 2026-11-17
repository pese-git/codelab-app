// Агент по требованию хоста: `ensureAgent`, корень процесса `agentDirectory`,
// перезапуск без смены проекта, `newSession(activate:)` (tasks B0.1 change
// `require-project-folder`; spec acp-client-kit «Агент по требованию хоста»;
// design D15, Q25).
//
// Порядок завершений задаётся `Completer`-ами резолвера (`concurrency.md`
// §69–§70), без `Future.delayed`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/gated_workspace.dart';

const _withList = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

// Агент без `session/list`: тест не отвечает на список там, где он не предмет.
const _loadOnly = AgentCapabilities(loadSession: true);

void main() {
  late GatedWorkspace host;

  ClientWorkspace workspaceOf(AgentCapabilities capabilities) {
    host = GatedWorkspace(capabilities: capabilities);
    return host.workspace;
  }

  tearDown(() => host.dispose());

  test('is a no-op when connected, whatever the directory is', () async {
    final workspace = workspaceOf(_withList);
    await workspace.ensureAgent('/work/a', profile: gatedProfile);
    final sentBefore = host.transport.sentMessages.length;

    await workspace.ensureAgent('/work/b');

    expect(host.resolver.directories, ['/work/a']);
    expect(workspace.current.agentDirectory, '/work/a');
    expect(host.transport.sentMessages, hasLength(sentBefore));
  });

  test('the first start sets agentDirectory, keeps projectDirectory and '
      'lists the project sessions', () async {
    final workspace = workspaceOf(_withList)..selectProject('/work/p');
    final agent = host.resolver.next();
    final transport = host.resolver.transport();
    final listed = host.nextRequest(sessionListMethod, transport);

    final starting = workspace.ensureAgent('/work/a', profile: gatedProfile);
    agent.complete(transport);
    final request = await listed;
    host.respond(transport, request, const {'sessions': <Object?>[]});
    await starting;

    expect(host.resolver.directories, ['/work/a']);
    expect(workspace.current.agentDirectory, '/work/a');
    expect(workspace.current.projectDirectory, '/work/p');
    expect(workspace.current.connection, const ConnectionView.connected());
    expect(ListSessionsRequest.fromJson(request.params).cwd, '/work/p');
  });

  test('without a project no session/list is sent', () async {
    final workspace = workspaceOf(_withList);

    await workspace.ensureAgent('/work/a', profile: gatedProfile);

    expect(workspace.current.projectDirectory, isNull);
    expect(host.requests(sessionListMethod), isEmpty);
  });

  test('a repeated call during the attempt shares it: one open with the '
      'first call directory', () async {
    final workspace = workspaceOf(_withList);
    final gate = host.resolver.next();

    final first = workspace.ensureAgent('/work/a', profile: gatedProfile);
    final second = workspace.ensureAgent('/work/b');
    expect(workspace.current.connection, const ConnectionView.connecting());
    gate.complete(host.resolver.transport());
    await Future.wait([first, second]);

    expect(host.resolver.directories, ['/work/a']);
    expect(workspace.current.agentDirectory, '/work/a');
    expect(workspace.current.connection, const ConnectionView.connected());
  });

  test('without a profile it throws and never calls the resolver', () async {
    final workspace = workspaceOf(_withList);

    await expectLater(
      workspace.ensureAgent('/work/a'),
      throwsA(isA<ClientWorkspaceException>()),
    );

    expect(host.resolver.directories, isEmpty);
  });

  test('after ConnectionFailed the next call starts a new attempt', () async {
    final workspace = workspaceOf(_withList);
    final gate = host.resolver.next();
    final failing = workspace.ensureAgent('/work/a', profile: gatedProfile);
    gate.completeError(StateError('spawn failed'));
    await expectLater(failing, throwsA(isA<StateError>()));
    expect(workspace.current.connection, isA<ConnectionFailed>());

    await workspace.ensureAgent('/work/a');

    expect(host.resolver.directories, ['/work/a', '/work/a']);
    expect(workspace.current.connection, const ConnectionView.connected());
  });

  test('after ConnectionLost a new attempt reloads the open sessions with '
      'their own cwd', () async {
    final workspace = workspaceOf(_withList);
    await workspace.ensureAgent('/work/a', profile: gatedProfile);
    final first = host.transport;
    final created = host.nextRequest(sessionNewMethod, first);
    final opening = workspace.newSession(cwd: '/work/b');
    host.respond(first, await created, const {'sessionId': 's-1'});
    await opening;
    first.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'agent process exited',
      ),
    );
    expect(workspace.current.connection, isA<ConnectionLost>());

    final fresh = host.resolver.transport();
    host.resolver.next().complete(fresh);
    final loaded = host.nextRequest(sessionLoadMethod, fresh);
    final restarting = workspace.ensureAgent('/work/a');
    final load = await loaded;
    host.respond(fresh, load, const <String, Object?>{});
    await restarting;

    expect(LoadSessionRequest.fromJson(load.params).cwd, '/work/b');
    expect(
      workspace.session(const SessionId('s-1'))!.current.status,
      SessionStatusView.idle,
    );
  });

  test('reconnect(agentDirectory:) restarts in the session folder and '
      'leaves the project and its list alone', () async {
    final workspace = workspaceOf(_withList)..selectProject('/work/a');
    final firstTransport = host.resolver.transport();
    host.resolver.next().complete(firstTransport);
    final firstList = host.nextRequest(sessionListMethod, firstTransport);
    final starting = workspace.ensureAgent('/work/a', profile: gatedProfile);
    host.respond(firstTransport, await firstList, const {
      'sessions': <Object?>[],
    });
    await starting;
    final fresh = host.resolver.transport();
    host.resolver.next().complete(fresh);
    final listed = host.nextRequest(sessionListMethod, fresh);

    final restarting = workspace.reconnect(agentDirectory: '/work/b');
    final list = await listed;
    host.respond(fresh, list, const {'sessions': <Object?>[]});
    await restarting;

    expect(host.resolver.directories, ['/work/a', '/work/b']);
    expect(workspace.current.agentDirectory, '/work/b');
    expect(workspace.current.projectDirectory, '/work/a');
    expect(ListSessionsRequest.fromJson(list.params).cwd, '/work/a');
  });

  test('CLI path: connect sets both folders, reconnect() keeps the root and '
      'reloads every session', () async {
    final workspace = workspaceOf(_loadOnly);
    await workspace.connect(gatedProfile, projectDirectory: '/work/app');
    expect(workspace.current.agentDirectory, '/work/app');
    expect(workspace.current.projectDirectory, '/work/app');
    final first = host.transport;
    for (final id in ['s-1', 's-2']) {
      final created = host.nextRequest(
        sessionNewMethod,
        first,
        index: id == 's-1' ? 0 : 1,
      );
      final opening = workspace.newSession();
      host.respond(first, await created, {'sessionId': id});
      expect((await opening).cwd, '/work/app');
    }

    final fresh = host.resolver.transport();
    host.resolver.next().complete(fresh);
    final loadFirst = host.nextRequest(sessionLoadMethod, fresh);
    final loadSecond = host.nextRequest(sessionLoadMethod, fresh, index: 1);
    final reconnecting = workspace.reconnect();
    host.respond(fresh, await loadFirst, const <String, Object?>{});
    host.respond(fresh, await loadSecond, const <String, Object?>{});
    await reconnecting;

    expect(host.resolver.directories, ['/work/app', '/work/app']);
    expect(workspace.current.agentDirectory, '/work/app');
    expect(
      [for (final s in workspace.current.sessions) s.status],
      [SessionStatusView.idle, SessionStatusView.idle],
    );
  });

  test('newSession(activate: false) lists the session and keeps the active '
      'one', () async {
    final workspace = workspaceOf(_loadOnly)..selectProject('/work/a');
    await workspace.ensureAgent('/work/a', profile: gatedProfile);
    final transport = host.transport;
    final first = host.nextRequest(sessionNewMethod, transport);
    final opening = workspace.newSession();
    host.respond(transport, await first, const {'sessionId': 's1'});
    await opening;
    expect(workspace.current.activeSessionId, const SessionId('s1'));

    final second = host.nextRequest(sessionNewMethod, transport, index: 1);
    final background = workspace.newSession(cwd: '/work/b', activate: false);
    host.respond(transport, await second, const {'sessionId': 's2'});
    await background;

    expect(workspace.current.activeSessionId, const SessionId('s1'));
    expect(
      [for (final s in workspace.current.sessions) (s.id.value, s.cwd)],
      [('s2', '/work/b'), ('s1', '/work/a')],
    );
  });

  test('reconnect(agentDirectory:) during an ensureAgent attempt supersedes '
      'it: first transport closed, no ConnectionFailed, ensureAgent ends '
      'without an error (Q25)', () async {
    final workspace = workspaceOf(_withList);
    final views = <ConnectionView>[];
    workspace.state.listen((state) => views.add(state.connection));
    final firstGate = host.resolver.next();
    final secondGate = host.resolver.next();

    final starting = workspace.ensureAgent('/work/a', profile: gatedProfile);
    final restarting = workspace.reconnect(agentDirectory: '/work/a');
    final stale = host.resolver.transport();
    firstGate.complete(stale);
    await starting;

    expect(stale.state, AcpTransportState.closed);
    expect(views.whereType<ConnectionFailed>(), isEmpty);

    secondGate.complete(host.resolver.transport());
    await restarting;
    expect(workspace.current.connection, const ConnectionView.connected());
    expect(views.whereType<ConnectionFailed>(), isEmpty);
  });
}
