// `EmbeddedTransportResolver` CLI (tasks 3.3; spec codelab-cli «Встроенный
// агент в CLI»; design.md change `add-embedded-agent-mode`, D6 «Резолвер
// клиента», `AGENTS.md` §12): сериализация `open`, `dispose()` устаревшего
// результата, `close()` ждёт `dispose`.
//
// Порядок событий задаётся `Completer`-ами и пропуском микрозадач, без
// `Future.delayed`.

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:test/test.dart';

const _profile = ConnectionProfile.embedded(
  id: 'embedded',
  label: 'Embedded agent',
  hostProfile: 'embedded-cli',
);

/// Агент с управляемым `dispose`: пока [disposeGate] не завершён, `dispose`
/// висит.
final class _FakeAgent implements EmbeddedAgent {
  // Статус MCP в этом тесте не нужен: фейк сессий не открывает.
  @override
  McpStatusPort? mcpStatus(String sessionId) => null;

  _FakeAgent(this.name);

  final String name;
  final disposeGate = Completer<void>();
  final _transport = FakeAcpTransport();
  int disposeCalls = 0;

  @override
  AcpTransport get clientTransport => _transport;

  @override
  Future<void> get closed => disposeGate.future;

  @override
  bool get secretsInConfig => false;

  @override
  Future<void> dispose() {
    disposeCalls++;
    return disposeGate.future;
  }
}

/// Открыватель, который отдаёт заранее заготовленные ответы по порядку и
/// запоминает вызовы; каждый ответ — `Completer`, поэтому тест решает, когда
/// открыватель «возвращается».
final class _Opener {
  final calls = <({String cwd, String hostProfile})>[];
  final results = <Completer<EmbeddedAgent>>[];

  Future<EmbeddedAgent> call({
    required String cwd,
    required String hostProfile,
  }) {
    calls.add((cwd: cwd, hostProfile: hostProfile));
    final result = Completer<EmbeddedAgent>();
    results.add(result);
    return result.future;
  }
}

/// Пропускает очередь микрозадач: все уже готовые продолжения успевают
/// выполниться.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

void main() {
  late _Opener opener;
  late EmbeddedTransportResolver resolver;

  setUp(() {
    opener = _Opener();
    resolver = EmbeddedTransportResolver(opener.call);
  });

  test('supports only the embedded profile', () {
    expect(resolver.supports(_profile), isTrue);
    expect(
      resolver.supports(
        const ConnectionProfile.stdio(id: 'a', label: 'a', command: 'x'),
      ),
      isFalse,
    );
    expect(
      resolver.supports(
        ConnectionProfile.webSocket(
          id: 'w',
          label: 'w',
          uri: Uri.parse('ws://x'),
        ),
      ),
      isFalse,
    );
  });

  test('open passes the project directory and the host profile of the '
      'profile and returns the client end', () async {
    final agent = _FakeAgent('a')..disposeGate.complete();

    final opening = resolver.open(_profile, projectDirectory: '/work');
    await _settle();
    expect(opener.calls, [(cwd: '/work', hostProfile: 'embedded-cli')]);
    opener.results.single.complete(agent);

    expect(await opening, same(agent.clientTransport));
  });

  test('a second open waits for dispose of the previous agent before it '
      'calls the opener (D6: two agents never write one journal)', () async {
    final first = _FakeAgent('first');
    final second = _FakeAgent('second');
    final firstOpening = resolver.open(_profile, projectDirectory: '/work');
    await _settle();
    opener.results[0].complete(first);
    await firstOpening;

    final secondOpening = resolver.open(_profile, projectDirectory: '/work');
    await _settle();

    expect(first.disposeCalls, 1);
    expect(opener.calls, hasLength(1), reason: 'dispose of first is pending');

    first.disposeGate.complete();
    await _settle();
    expect(opener.calls, hasLength(2));
    opener.results[1].complete(second);
    expect(await secondOpening, same(second.clientTransport));
  });

  test('a result that returns after close() is disposed at once and never '
      'becomes current (stale result, AGENTS.md §12)', () async {
    final stale = _FakeAgent('stale')..disposeGate.complete();
    final opening = resolver.open(_profile, projectDirectory: '/work');
    await _settle();
    final expectation = expectLater(
      opening,
      throwsA(isA<EmbeddedOpenCancelledException>()),
    );

    final closing = resolver.close();
    await _settle();
    expect(stale.disposeCalls, 0, reason: 'the opener has not returned yet');
    opener.results.single.complete(stale);
    await closing;
    await expectation;

    expect(stale.disposeCalls, 1);
    // Закрытый резолвер больше не открывает агентов.
    await expectLater(
      resolver.open(_profile, projectDirectory: '/work'),
      throwsA(isA<EmbeddedOpenCancelledException>()),
    );
    expect(opener.calls, hasLength(1));
  });

  test('a newer open cancels the running one: the stale agent is disposed, '
      'only the newer becomes current', () async {
    final stale = _FakeAgent('stale')..disposeGate.complete();
    final fresh = _FakeAgent('fresh');
    final staleOpening = resolver.open(_profile, projectDirectory: '/a');
    await _settle();
    final staleExpectation = expectLater(
      staleOpening,
      throwsA(isA<EmbeddedOpenCancelledException>()),
    );
    final freshOpening = resolver.open(_profile, projectDirectory: '/b');
    await _settle();
    expect(opener.calls, hasLength(1), reason: 'opens are serialized');

    opener.results[0].complete(stale);
    await staleExpectation;
    expect(stale.disposeCalls, 1);
    await _settle();
    expect(opener.calls.last.cwd, '/b');
    opener.results[1].complete(fresh);
    expect(await freshOpening, same(fresh.clientTransport));

    // Текущий — только `fresh`: `close()` освобождает его, `stale` не
    // трогает повторно.
    final closing = resolver.close();
    await _settle();
    expect(fresh.disposeCalls, 1);
    expect(stale.disposeCalls, 1);
    fresh.disposeGate.complete();
    await closing;
  });

  test('an open superseded before it starts never calls the opener', () async {
    final first = _FakeAgent('first');
    final second = _FakeAgent('second');
    final firstOpening = resolver.open(_profile, projectDirectory: '/1');
    await _settle();
    final firstExpectation = expectLater(
      firstOpening,
      throwsA(isA<EmbeddedOpenCancelledException>()),
    );
    // Второй и третий open приходят, пока первый ещё в открывателе.
    final secondOpening = resolver.open(_profile, projectDirectory: '/2');
    final thirdOpening = resolver.open(_profile, projectDirectory: '/3');
    final secondExpectation = expectLater(
      secondOpening,
      throwsA(isA<EmbeddedOpenCancelledException>()),
    );
    await _settle();

    first.disposeGate.complete();
    opener.results[0].complete(first);
    await firstExpectation;
    await secondExpectation;
    await _settle();

    expect(opener.calls.map((call) => call.cwd), ['/1', '/3']);
    opener.results[1].complete(second);
    expect(await thirdOpening, same(second.clientTransport));
  });

  test('close() waits for dispose of the current agent', () async {
    final agent = _FakeAgent('a');
    final opening = resolver.open(_profile, projectDirectory: '/work');
    await _settle();
    opener.results.single.complete(agent);
    await opening;

    var closed = false;
    final closing = resolver.close().then((_) => closed = true);
    await _settle();

    expect(agent.disposeCalls, 1);
    expect(closed, isFalse, reason: 'dispose is still running');
    agent.disposeGate.complete();
    await closing;
    expect(closed, isTrue);
  });

  test('close() is idempotent and works without any agent', () async {
    await resolver.close();
    await resolver.close();

    expect(opener.calls, isEmpty);
  });

  test(
    'an opener failure reaches the caller and the next open works',
    () async {
      final failing = resolver.open(_profile, projectDirectory: '/work');
      await _settle();
      final expectation = expectLater(failing, throwsA(isA<StateError>()));
      opener.results.single.completeError(StateError('boom'));
      await expectation;

      final agent = _FakeAgent('a')..disposeGate.complete();
      final next = resolver.open(_profile, projectDirectory: '/work');
      await _settle();
      opener.results[1].complete(agent);

      expect(await next, same(agent.clientTransport));
    },
  );
}
