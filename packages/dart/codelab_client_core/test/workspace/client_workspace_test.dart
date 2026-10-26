// Тесты `ClientWorkspace` поверх `AcpClientBackend` (tasks 2.3; spec
// acp-client-kit «Общий клиентский слой без UI», «Явный автомат соединения»,
// «Профили и резолверы транспорта»).

import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

const _stdio = StdioProfile(
  id: 'agent',
  label: 'Agent',
  command: 'codelab-agent',
  args: ['serve', '--stdio'],
);

void main() {
  late AcpClientApplication application;

  setUp(
    () => application = AcpClientApplication(transport: FakeAcpTransport()),
  );
  tearDown(() => application.dispose());

  ClientWorkspace workspaceWith(List<TransportResolver> resolvers) {
    final workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: resolvers,
    );
    addTearDown(workspace.dispose);
    return workspace;
  }

  group('connection', () {
    test(
      'connect() goes Connecting → Connected through the resolver',
      () async {
        final agent = FakeAcpTransport();
        final resolver = _TestResolver([agent]);
        final workspace = workspaceWith([resolver]);
        final connections = <ConnectionView>[];
        workspace.state.listen((state) => connections.add(state.connection));

        expect(
          workspace.current.connection,
          const ConnectionView.disconnected(),
        );
        await workspace.connect(_stdio, projectDirectory: '/work');

        expect(connections.first, const ConnectionView.connecting());
        expect(workspace.current.connection, const ConnectionView.connected());
        expect(workspace.current.profile, _stdio);
        expect(workspace.current.projectDirectory, '/work');
        expect(resolver.opened, [(_stdio, '/work')]);
        expect(agent.state, AcpTransportState.connected);
      },
    );

    test('a profile without a resolver fails without opening a '
        'transport', () async {
      final resolver = _TestResolver([FakeAcpTransport()]);
      final workspace = workspaceWith([resolver]);
      final profile = WebSocketProfile(
        id: 'remote',
        label: 'Remote',
        uri: Uri.parse('wss://agent.example.test/acp'),
      );

      await expectLater(
        workspace.connect(profile, projectDirectory: '/work'),
        throwsA(isA<UnsupportedConnectionProfileException>()),
      );

      final connection = workspace.current.connection;
      expect(connection, isA<ConnectionFailed>());
      expect(
        (connection as ConnectionFailed).message,
        contains('No transport resolver supports'),
      );
      expect(resolver.opened, isEmpty);
    });

    test('a transport that cannot start leaves ConnectionFailed and '
        'rethrows', () async {
      final workspace = workspaceWith([
        _TestResolver([_ThrowingStartTransport()]),
      ]);

      await expectLater(
        workspace.connect(_stdio, projectDirectory: '/work'),
        throwsA(isA<AcpClientApplicationException>()),
      );

      expect(
        workspace.current.connection,
        isA<ConnectionFailed>().having(
          (failed) => failed.reason,
          'reason',
          ConnectionFailureReason.startFailed,
        ),
      );
    });

    test('an unexpected transport failure is published as '
        'ConnectionFailed', () async {
      final agent = FakeAcpTransport();
      final workspace = workspaceWith([
        _TestResolver([agent]),
      ]);
      await workspace.connect(_stdio, projectDirectory: '/work');

      agent.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'agent exited',
        ),
      );

      expect(
        workspace.current.connection,
        isA<ConnectionFailed>().having(
          (failed) => failed.message,
          'message',
          'agent exited',
        ),
      );
    });

    test('reconnect() is one attempt through the resolver of the given '
        'profile', () async {
      final first = FakeAcpTransport();
      final second = FakeAcpTransport();
      final resolver = _TestResolver([first, second]);
      final workspace = workspaceWith([resolver]);
      await workspace.connect(_stdio, projectDirectory: '/work');
      final generation = application.generation;
      final connections = <ConnectionView>[];
      workspace.state.listen((state) => connections.add(state.connection));
      final edited = _stdio.copyWith(runInProjectDirectory: true);

      await workspace.reconnect(profile: edited, projectDirectory: '/other');

      expect(connections.first, const ConnectionView.reconnecting(attempt: 1));
      expect(connections.whereType<Connecting>(), isEmpty);
      expect(workspace.current.connection, const ConnectionView.connected());
      expect(workspace.current.profile, edited);
      expect(workspace.current.projectDirectory, '/other');
      expect(resolver.opened.last, (edited, '/other'));
      expect(application.generation, generation + 1);
      expect(first.state, AcpTransportState.closed);
    });

    test(
      'reconnect() without arguments reuses the connected profile',
      () async {
        final resolver = _TestResolver([
          FakeAcpTransport(),
          FakeAcpTransport(),
        ]);
        final workspace = workspaceWith([resolver]);
        await workspace.connect(_stdio, projectDirectory: '/work');

        await workspace.reconnect();

        expect(resolver.opened, [(_stdio, '/work'), (_stdio, '/work')]);
      },
    );

    test('a failed reconnect() leaves ConnectionFailed and rethrows', () async {
      final workspace = workspaceWith([
        _TestResolver([FakeAcpTransport(), _ThrowingStartTransport()]),
      ]);
      await workspace.connect(_stdio, projectDirectory: '/work');

      await expectLater(
        workspace.reconnect(),
        throwsA(isA<AcpClientApplicationException>()),
      );

      expect(workspace.current.connection, isA<ConnectionFailed>());
    });

    test('reconnect() before any connect() is rejected', () async {
      final workspace = workspaceWith([_TestResolver([])]);

      await expectLater(
        workspace.reconnect(),
        throwsA(isA<ClientWorkspaceException>()),
      );
      expect(workspace.current.connection, const ConnectionView.disconnected());
    });
  });

  group('sessions', () {
    late FakeAcpTransport agent;
    late ClientWorkspace workspace;

    setUp(() async {
      agent = FakeAcpTransport();
      workspace = workspaceWith([
        _TestResolver([agent, FakeAcpTransport()]),
      ]);
      await workspace.connect(_stdio, projectDirectory: '/work');
    });

    Future<SessionHandle> newSession(String id, {String? cwd}) async {
      final requestFuture = agent.sent.firstWhere(
        (message) =>
            message is JsonRpcRequest && message.method == sessionNewMethod,
      );
      final handleFuture = workspace.newSession(cwd: cwd);
      final request = await requestFuture as JsonRpcRequest;
      agent.emitInbound(
        JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
      );
      return handleFuture;
    }

    test('newSession() uses the project directory and activates the '
        'session', () async {
      final requestFuture = agent.sent.firstWhere(
        (message) => message is JsonRpcRequest,
      );
      final handleFuture = workspace.newSession();
      final request = await requestFuture as JsonRpcRequest;
      expect(request.params, containsPair('cwd', '/work'));
      agent.emitInbound(
        JsonRpcMessage.response(id: request.id, result: {'sessionId': 's-1'}),
      );
      final handle = await handleFuture;

      expect(handle.id, const SessionId('s-1'));
      expect(handle.cwd, '/work');
      expect(handle.current.status, SessionStatusView.idle);
      expect(workspace.current.activeSessionId, const SessionId('s-1'));
      expect(workspace.current.sessions.single.id, const SessionId('s-1'));
      expect(workspace.session(const SessionId('s-1')), same(handle));
    });

    test('a newer session is listed first; activate() switches the active '
        'session and ignores unknown ids', () async {
      await newSession('s-1');
      await newSession('s-2', cwd: '/elsewhere');

      expect(workspace.current.sessions.map((session) => session.id), const [
        SessionId('s-2'),
        SessionId('s-1'),
      ]);
      expect(workspace.current.sessions.first.cwd, '/elsewhere');
      expect(workspace.current.activeSessionId, const SessionId('s-2'));

      workspace.activate(const SessionId('s-1'));
      expect(workspace.current.activeSessionId, const SessionId('s-1'));

      workspace.activate(const SessionId('missing'));
      expect(workspace.current.activeSessionId, const SessionId('s-1'));
    });

    test('session status follows the turn and the revision grows', () async {
      final handle = await newSession('s-1');
      final revision = handle.current.revision;

      final promptFuture = agent.sent.firstWhere(
        (message) =>
            message is JsonRpcRequest && message.method == sessionPromptMethod,
      );
      final turn = application.sendPrompt(
        SendPromptCommand(
          sessionId: handle.id,
          prompt: const [ContentBlock.text(text: 'hello')],
        ),
      );
      final prompt = await promptFuture as JsonRpcRequest;

      expect(handle.current.status, SessionStatusView.running);
      expect(handle.current.revision, greaterThan(revision));
      expect(
        workspace.current.sessions.single.status,
        SessionStatusView.running,
      );

      agent.emitInbound(
        JsonRpcMessage.response(
          id: prompt.id,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await turn;

      expect(handle.current.status, SessionStatusView.idle);
      expect(workspace.current.sessions.single.status, SessionStatusView.idle);
    });

    test('the session view carries the projected transcript, updated '
        'synchronously with the session change', () async {
      final handle = await newSession('s-1');
      final promptFuture = agent.sent.firstWhere(
        (message) =>
            message is JsonRpcRequest && message.method == sessionPromptMethod,
      );
      final turn = application.sendPrompt(
        SendPromptCommand(
          sessionId: handle.id,
          prompt: const [ContentBlock.text(text: 'hello')],
        ),
      );
      final prompt = await promptFuture as JsonRpcRequest;

      agent.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: const {
            'sessionId': 's-1',
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'hi'},
            },
          },
        ),
      );

      expect(handle.current.transcript.map((item) => item.runtimeType), [
        UserItem,
        AgentTextItem,
      ]);

      agent.emitInbound(
        JsonRpcMessage.response(
          id: prompt.id,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await turn;
    });

    test('newSession() without a connection is rejected', () async {
      final idle = workspaceWith([_TestResolver([])]);

      await expectLater(
        idle.newSession(),
        throwsA(isA<ClientWorkspaceException>()),
      );
    });
  });

  test('a late session/update from the previous connection changes '
      'nothing', () async {
    final old = FakeAcpTransport();
    final workspace = workspaceWith([
      _TestResolver([_LingeringTransport(old), FakeAcpTransport()]),
    ]);
    await workspace.connect(_stdio, projectDirectory: '/work');
    final requestFuture = old.sent.firstWhere(
      (message) => message is JsonRpcRequest,
    );
    final handleFuture = workspace.newSession();
    final request = await requestFuture as JsonRpcRequest;
    old.emitInbound(
      JsonRpcMessage.response(id: request.id, result: {'sessionId': 's-1'}),
    );
    final handle = await handleFuture;
    await workspace.reconnect();
    final before = workspace.current;
    final revision = handle.current.revision;
    final published = <WorkspaceState>[];
    workspace.state.listen(published.add);

    old.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: const {
          'sessionId': 's-1',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'late'},
          },
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(published, isEmpty);
    expect(workspace.current, before);
    expect(handle.current.revision, revision);
  });

  test('dispose() closes the state stream', () async {
    final workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: const [],
    );
    final done = Completer<void>();
    workspace.state.listen(null, onDone: done.complete);

    await workspace.dispose();

    await done.future.timeout(const Duration(seconds: 1));
  });
}

/// Резолвер теста: отдаёт заранее подготовленные транспорты по очереди и
/// поддерживает только stdio-профили.
final class _TestResolver implements TransportResolver {
  _TestResolver(this._transports);

  final List<AcpTransport> _transports;
  final opened = <(ConnectionProfile, String)>[];

  @override
  bool supports(ConnectionProfile profile) => profile is StdioProfile;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    opened.add((profile, projectDirectory));
    return _transports.removeAt(0);
  }
}

/// Транспорт, `start()` которого падает: агент не запустился.
final class _ThrowingStartTransport implements AcpTransport {
  final _inbound = StreamController<JsonRpcMessage>.broadcast();
  final _events = StreamController<AcpTransportEvent>.broadcast();

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => AcpTransportState.idle;

  @override
  Future<void> start() async => throw const AcpTransportException(
    code: AcpTransportErrorCode.startFailed,
    message: 'agent binary missing',
  );

  @override
  Future<void> send(JsonRpcMessage message) async =>
      throw StateError('not started');

  @override
  Future<void> close({Duration? timeout}) async {
    await _inbound.close();
    await _events.close();
  }
}

/// Транспорт, который после `close()` продолжает доставлять кадры: так
/// приходят поздние события старого соединения (`AGENTS.md` §9).
final class _LingeringTransport implements AcpTransport {
  _LingeringTransport(this._inner);

  final FakeAcpTransport _inner;

  @override
  Stream<JsonRpcMessage> get inbound => _inner.inbound;

  @override
  Stream<AcpTransportEvent> get events => _inner.events;

  @override
  AcpTransportState get state => _inner.state;

  @override
  Future<void> start() => _inner.start();

  @override
  Future<void> send(JsonRpcMessage message) => _inner.send(message);

  @override
  Future<void> close({Duration? timeout}) async {}
}
