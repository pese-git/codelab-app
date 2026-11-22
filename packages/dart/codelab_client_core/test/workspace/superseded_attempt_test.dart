// Гонка повторного подключения в `ClientWorkspace` (ревью итерации 4 change
// `add-embedded-agent-mode`; AGENTS.md §9: late events старого request не
// меняют актуальный state, race отмены и завершения обрабатывается явно).
//
// Порядок событий задаётся `Completer`-ами резолвера, без `Future.delayed`.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _stdio = StdioProfile(
  id: 'agent',
  label: 'Agent',
  command: 'codelab-agent',
  args: ['serve', '--stdio'],
);

void main() {
  late AcpClientApplication application;
  late _GatedResolver resolver;
  late ClientWorkspace workspace;
  late FakeAcpTransport first;
  late SessionHandle session;
  late List<ConnectionView> views;

  setUp(() async {
    first = FakeAcpTransport();
    application = AcpClientApplication(transport: FakeAcpTransport());
    resolver = _GatedResolver();
    workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [resolver],
    );
    resolver.next().complete(first);
    await workspace.connect(_stdio, projectDirectory: '/work');

    final requested = first.sent.firstWhere((m) => m is JsonRpcRequest);
    final created = workspace.newSession();
    final request = await requested as JsonRpcRequest;
    first.emitInbound(
      JsonRpcMessage.response(id: request.id, result: {'sessionId': 's-1'}),
    );
    session = await created;

    views = [];
    workspace.state.listen((state) => views.add(state.connection));
  });

  tearDown(() async {
    await workspace.dispose();
    await application.dispose();
  });

  /// Проверки, общие для обеих ручек: пока новая попытка идёт, сбой старой
  /// ничего не публикует и не возобновляет сессии.
  Future<void> expectStaleFailureIsInvisible(Future<void> stale) async {
    // Старая попытка завершилась без ошибки: вызывающий не получает ложного
    // `failed`, итог читает из `WorkspaceState`.
    await stale;

    expect(views.whereType<ConnectionFailed>(), isEmpty);
    expect(workspace.current.connection, isNot(isA<ConnectionFailed>()));
    // Сессия всё ещё приостановлена новой попыткой: промпт встаёт в очередь,
    // а не уходит в закрытый backend.
    expect(await session.send('later'), isA<PromptQueued>());
  }

  group('connect()', () {
    test('a failed first attempt does not disturb the second one', () async {
      final oldAttempt = resolver.next();
      final newAttempt = resolver.next();
      final stale = workspace.connect(_stdio, projectDirectory: '/work');
      final fresh = workspace.connect(_stdio, projectDirectory: '/work');

      oldAttempt.completeError(StateError('open cancelled'));
      await expectStaleFailureIsInvisible(stale);

      newAttempt.complete(FakeAcpTransport());
      await fresh;
      expect(workspace.current.connection, const ConnectionView.connected());
      expect(views.whereType<ConnectionFailed>(), isEmpty);
    });

    test('a late success of the first attempt publishes nothing and closes '
        'its transport', () async {
      final oldAttempt = resolver.next();
      final newAttempt = resolver.next();
      final stale = workspace.connect(_stdio, projectDirectory: '/work');
      final fresh = workspace.connect(_stdio, projectDirectory: '/work');
      final second = FakeAcpTransport();
      newAttempt.complete(second);
      await fresh;
      final generation = application.generation;
      final published = views.length;

      final late = FakeAcpTransport();
      oldAttempt.complete(late);
      await stale;

      expect(late.state, AcpTransportState.closed);
      expect(second.state, AcpTransportState.connected);
      expect(application.generation, generation);
      expect(views.length, published);
      expect(workspace.current.connection, const ConnectionView.connected());
    });
  });

  group('reconnect()', () {
    test('a failed first attempt does not disturb the second one', () async {
      final oldAttempt = resolver.next();
      final newAttempt = resolver.next();
      final stale = workspace.reconnect();
      final fresh = workspace.reconnect();

      oldAttempt.completeError(StateError('open cancelled'));
      await expectStaleFailureIsInvisible(stale);

      newAttempt.complete(FakeAcpTransport());
      await fresh;
      expect(workspace.current.connection, const ConnectionView.connected());
      expect(views.whereType<ConnectionFailed>(), isEmpty);
    });

    test('a late success of the first attempt publishes nothing and closes '
        'its transport', () async {
      final oldAttempt = resolver.next();
      final newAttempt = resolver.next();
      final stale = workspace.reconnect();
      final fresh = workspace.reconnect();
      final second = FakeAcpTransport();
      newAttempt.complete(second);
      await fresh;
      final generation = application.generation;
      final published = views.length;

      final late = FakeAcpTransport();
      oldAttempt.complete(late);
      await stale;

      expect(late.state, AcpTransportState.closed);
      expect(second.state, AcpTransportState.connected);
      expect(application.generation, generation);
      expect(views.length, published);
      expect(workspace.current.connection, const ConnectionView.connected());
    });
  });

  // Окно после передачи транспорта бэкенду (`_backend.connect`): ядро клиента
  // само ведёт устаревшую попытку до `initialize`, и её события приходят в
  // `connectionStates` во время новой попытки (§9, спецификация `acp-client-kit`,
  // «Явный автомат соединения»).
  group('superseded after the transport reached the backend', () {
    bool isInitialize(JsonRpcMessage m) =>
        m is JsonRpcRequest && m.method == initializeMethod;

    test('a failure of the old attempt is not published', () async {
      final oldGate = resolver.next();
      final newGate = resolver.next();
      final old = FakeAcpTransport()..autoRespondToInitialize = false;
      final initializing = old.sent.firstWhere(isInitialize);
      final stale = workspace.connect(_stdio, projectDirectory: '/work');
      oldGate.complete(old);
      await initializing;
      views.clear();

      // Новая попытка заменяет транспорт: ожидающий `initialize` старой
      // падает «transport was replaced».
      final fresh = workspace.connect(_stdio, projectDirectory: '/work');
      newGate.complete(FakeAcpTransport());
      await stale;
      await fresh;

      expect(views.whereType<ConnectionFailed>(), isEmpty);
      expect(workspace.current.connection, const ConnectionView.connected());
      expect(views.last, const ConnectionView.connected());
    });
  });

  // Окно, пока новая попытка ещё открывает транспорт (`resolver.open`: у
  // встроенного агента и `npx` это секунды): kit уже вытеснил старую попытку
  // (`_attempt`), а ядро ещё нет — оно идёт на прежнем поколении. Исход
  // явной попытки публикует сам её вызывающий, поэтому `ready`/`fail` ядра в
  // это окно не должны менять вид и возможности.
  group('while the new attempt is still opening its transport', () {
    bool isInitialize(JsonRpcMessage m) =>
        m is JsonRpcRequest && m.method == initializeMethod;

    List<ConnectionView> changes() {
      final result = <ConnectionView>[];
      for (final view in views) {
        if (result.isEmpty || result.last != view) {
          result.add(view);
        }
      }
      return result;
    }

    test('a ready of the old attempt is not published and does not set '
        'capabilities', () async {
      final oldGate = resolver.next();
      final newGate = resolver.next();
      final old = FakeAcpTransport()
        ..autoRespondToInitialize = false
        ..initializeAgentCapabilities = const AgentCapabilities(
          loadSession: true,
        );
      final request = old.sent.firstWhere(isInitialize);
      final stale = workspace.connect(_stdio, projectDirectory: '/work');
      oldGate.complete(old);
      final initialize = await request as JsonRpcRequest;
      views.clear();

      final fresh = workspace.connect(_stdio, projectDirectory: '/work');
      old.emitInbound(
        encodeAcpResponse(
          id: initialize.id,
          method: initializeMethod,
          result: InitializeResponse(
            protocolVersion: const ProtocolVersion(1),
            agentCapabilities: old.initializeAgentCapabilities,
          ),
        ),
      );
      // Старая попытка дошла до `ready` ядра (её `connect` вернулся), новая
      // всё ещё на `open`.
      await stale;
      expect(views.whereType<Connected>(), isEmpty);
      expect(views.whereType<ConnectionFailed>(), isEmpty);
      expect(workspace.current.connection, const ConnectionView.connecting());

      newGate.complete(FakeAcpTransport());
      await fresh;

      expect(changes().whereType<Connected>(), hasLength(1));
      expect(workspace.current.connection, const ConnectionView.connected());
      // Новый агент `loadSession` не объявил, возможности старого не остались.
      await expectLater(
        workspace.loadSession(const SessionId('s-1'), cwd: '/work'),
        throwsA(
          isA<ClientWorkspaceException>().having(
            (e) => e.message,
            'message',
            contains('cannot load sessions'),
          ),
        ),
      );
    });

    test('a failure of the old attempt is not published and the failed '
        'open reports its own error', () async {
      final oldGate = resolver.next();
      final newGate = resolver.next();
      final old = FakeAcpTransport()..autoRespondToInitialize = false;
      final initializing = old.sent.firstWhere(isInitialize);
      final stale = workspace.connect(_stdio, projectDirectory: '/work');
      oldGate.complete(old);
      await initializing;
      views.clear();

      final fresh = workspace.connect(_stdio, projectDirectory: '/work');
      final freshOutcome = fresh.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      old.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'old agent exited',
        ),
      );
      await stale;
      expect(views.whereType<ConnectionFailed>(), isEmpty);

      newGate.completeError(StateError('open boom'));
      expect(await freshOutcome, isA<StateError>());

      expect(
        workspace.current.connection,
        isA<ConnectionFailed>().having(
          (v) => v.message,
          'message',
          contains('open boom'),
        ),
      );
    });

    // Новая попытка уже завершилась сбоем `open` (`_transition == none`), а
    // ядро ещё ждёт `initialize` старой на прежнем поколении: исход старой
    // попытки не должен ни показать `Connected`, ни перезаписать сбой новой.
    Future<
      ({Future<void> stale, FakeAcpTransport old, JsonRpcRequest initialize})
    >
    startStaleThenFailOpen() async {
      final oldGate = resolver.next();
      final newGate = resolver.next();
      final old = FakeAcpTransport()
        ..autoRespondToInitialize = false
        ..initializeAgentCapabilities = const AgentCapabilities(
          loadSession: true,
        );
      final request = old.sent.firstWhere(isInitialize);
      final stale = workspace.connect(_stdio, projectDirectory: '/work');
      oldGate.complete(old);
      final initialize = await request as JsonRpcRequest;

      final fresh = workspace.connect(_stdio, projectDirectory: '/work');
      newGate.completeError(StateError('open boom'));
      await expectLater(fresh, throwsA(isA<StateError>()));
      views.clear();
      return (stale: stale, old: old, initialize: initialize);
    }

    void expectOpenFailureKept() {
      expect(views.whereType<Connected>(), isEmpty);
      expect(
        workspace.current.connection,
        isA<ConnectionFailed>().having(
          (v) => v.message,
          'message',
          contains('open boom'),
        ),
      );
    }

    test('a ready of the old attempt after the new open failed is not '
        'published', () async {
      final run = await startStaleThenFailOpen();

      run.old.emitInbound(
        encodeAcpResponse(
          id: run.initialize.id,
          method: initializeMethod,
          result: InitializeResponse(
            protocolVersion: const ProtocolVersion(1),
            agentCapabilities: run.old.initializeAgentCapabilities,
          ),
        ),
      );
      await run.stale;

      expectOpenFailureKept();
    });

    test('a failure of the old attempt after the new open failed does not '
        'overwrite the failure of the new one', () async {
      final run = await startStaleThenFailOpen();

      run.old.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'old agent exited',
        ),
      );
      await run.stale;

      expectOpenFailureKept();
    });

    test('the old attempt still starting its transport does not overwrite '
        'the failure of the new one', () async {
      final oldGate = resolver.next();
      final newGate = resolver.next();
      final startGate = Completer<void>();
      final old = _GatedStartTransport(startGate.future);
      final stale = workspace.connect(_stdio, projectDirectory: '/work');
      oldGate.complete(old);
      // Ядро старой попытки уже сделало `disconnect`/`connect` и ждёт `start`.
      await old.startRequested;

      final fresh = workspace.connect(_stdio, projectDirectory: '/work');
      newGate.completeError(StateError('open boom'));
      await expectLater(fresh, throwsA(isA<StateError>()));
      views.clear();

      // Ядро продолжает старую попытку: `initialize`, затем `ready`.
      startGate.complete();
      await stale;

      expect(views.whereType<Connecting>(), isEmpty);
      expect(views.whereType<Disconnected>(), isEmpty);
      expectOpenFailureKept();
    });

    test('the core failure of the new attempt keeps its reason', () async {
      final oldGate = resolver.next();
      final newGate = resolver.next();
      final old = FakeAcpTransport()..autoRespondToInitialize = false;
      final initializing = old.sent.firstWhere(isInitialize);
      final stale = workspace.connect(_stdio, projectDirectory: '/work');
      oldGate.complete(old);
      await initializing;

      final fresh = workspace.connect(_stdio, projectDirectory: '/work');
      final freshOutcome = fresh.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      newGate.complete(
        FakeAcpTransport()
          ..initializeProtocolVersion = const ProtocolVersion(99),
      );
      await stale;
      expect(await freshOutcome, isA<UnsupportedProtocolVersionException>());

      expect(
        workspace.current.connection,
        isA<ConnectionFailed>().having(
          (v) => v.reason,
          'reason',
          ConnectionFailureReason.unsupportedProtocolVersion,
        ),
      );
    });
  });
}

/// Резолвер, у которого завершением каждого `open` управляет тест.
final class _GatedResolver implements TransportResolver {
  final _gates = <Completer<AcpTransport>>[];
  var _opened = 0;

  /// Заводит вентиль для очередного `open` (порядок вызова = порядок `next`).
  Completer<AcpTransport> next() {
    final gate = Completer<AcpTransport>();
    _gates.add(gate);
    return gate;
  }

  @override
  bool supports(ConnectionProfile profile) => profile is StdioProfile;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) => _gates[_opened++].future;
}

/// Транспорт, чей `start` держится за вентилем: старая попытка остаётся в
/// ядре на ожидании запуска, пока тест вытесняет её новой.
final class _GatedStartTransport implements AcpTransport {
  _GatedStartTransport(this._startGate);

  final Future<void> _startGate;
  final _inner = FakeAcpTransport();
  final _requested = Completer<void>();

  /// Завершается, когда ядро вызвало `start`.
  Future<void> get startRequested => _requested.future;

  @override
  Stream<JsonRpcMessage> get inbound => _inner.inbound;

  @override
  Stream<AcpTransportEvent> get events => _inner.events;

  @override
  AcpTransportState get state => _inner.state;

  @override
  Future<void> start() async {
    _requested.complete();
    await _startGate;
    await _inner.start();
  }

  @override
  Future<void> send(JsonRpcMessage message) => _inner.send(message);

  @override
  Future<void> close({Duration? timeout}) => _inner.close(timeout: timeout);
}
