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
