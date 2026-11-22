// Устаревшая попытка `connect()`/`reconnect()` (требование «Явный автомат
// соединения» спецификации `acp-client-kit`; AGENTS.md §9: поздние события
// старого соединения не меняют актуальное состояние).
//
// Порядок событий задаётся `Completer`-ами и синхронными вызовами, без
// `Future.delayed`.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

void main() {
  group('replacing the transport while the old one is still closing', () {
    late _TrackedTransport old;
    late AcpClientApplication client;
    late Completer<void> closeGate;

    setUp(() {
      closeGate = Completer<void>();
      old = _TrackedTransport(closeGate: closeGate.future);
      client = AcpClientApplication(transport: old);
      addTearDown(client.dispose);
    });

    test('a second connect() closes the loser and binds only the '
        'winner', () async {
      final loser = _TrackedTransport();
      final winner = _TrackedTransport();

      final first = client.connect(loser);
      final second = client.connect(winner);
      // Оба ждут закрытие прежнего транспорта: вентиль открывается, только
      // когда `close` вызвали обе замены.
      await old.closeCalled(2);
      closeGate.complete();

      await expectLater(first, throwsA(isA<StateTransitionException>()));
      final state = await second;

      expect(state, isA<ClientConnectionReady>());
      expect(loser.closeCalls, greaterThan(0));
      expect(loser.hasInboundListener, isFalse);
      expect(loser.hasEventListener, isFalse);
      expect(winner.closeCalls, 0);
      expect(winner.hasInboundListener, isTrue);
      expect(winner.hasEventListener, isTrue);
    });

    test('a reconnect() closes the loser and binds only the '
        'winner', () async {
      final loser = _TrackedTransport();
      final winner = _TrackedTransport();

      final first = client.connect(loser);
      final second = client.reconnect(
        ReconnectCommand(transportFactory: () async => winner),
      );
      // Фабрика `reconnect` асинхронна: ждём, пока обе замены дошли до
      // `close` прежнего транспорта, а не считаем микрозадачи.
      await old.closeCalled(2);
      closeGate.complete();

      await expectLater(first, throwsA(isA<StateTransitionException>()));
      final state = await second;

      expect(state, isA<ClientConnectionReady>());
      expect(loser.closeCalls, greaterThan(0));
      expect(loser.hasInboundListener, isFalse);
      expect(winner.closeCalls, 0);
      expect(winner.hasInboundListener, isTrue);
    });
  });

  test('a failing close of the old transport still closes the unbound '
      'replacement', () async {
    final old = _TrackedTransport(closeError: StateError('close failed'));
    final client = AcpClientApplication(transport: old);
    addTearDown(client.dispose);
    final replacement = _TrackedTransport();

    await expectLater(client.connect(replacement), throwsA(isA<StateError>()));

    expect(replacement.closeCalls, greaterThan(0));
    expect(replacement.hasInboundListener, isFalse);
  });

  test(
    'a superseded attempt logs the failed close of the old transport',
    () async {
      final captured = <Map<String, dynamic>>[];
      configureCodeLabLogging(
        applicationOutput: (entry, level) => captured.add(entry),
        protocolTraceOutput: (entry, level) => captured.add(entry),
      );
      addTearDown(StructlogConfiguration.reset);
      final closeGate = Completer<void>();
      final old = _TrackedTransport(
        closeGate: closeGate.future,
        closeError: StateError('close failed'),
        closeFailures: 2,
      );
      final client = AcpClientApplication(transport: old);
      addTearDown(client.dispose);
      final loser = _TrackedTransport();
      final winner = _TrackedTransport();

      final first = client.connect(loser);
      final second = client.connect(winner);
      await old.closeCalled(2);
      closeGate.complete();

      await expectLater(first, throwsA(isA<StateTransitionException>()));
      await expectLater(second, throwsA(isA<StateError>()));

      expect(loser.closeCalls, greaterThan(0));
      final entry = captured.singleWhere(
        (e) => e['event'] == 'attempt_superseded',
      );
      expect(entry['phase'], 'replace');
      expect(entry['error'], contains('close failed'));
    },
  );

  group('connection state machine of a superseded attempt', () {
    late AcpClientApplication client;
    late List<ClientConnectionState> states;

    setUp(() {
      client = AcpClientApplication(transport: FakeAcpTransport());
      states = [];
      client.connectionStateChanges.listen(states.add);
      addTearDown(client.dispose);
    });

    test('a failure of the superseded attempt makes no transition', () async {
      final stale = FakeAcpTransport()..autoRespondToInitialize = false;
      final initialize = stale.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == initializeMethod,
      );
      final first = client.connect(stale);
      // Исход первой попытки наблюдаем заранее: ошибка не должна считаться
      // необработанной, пока тест ждёт второй `connect`.
      final firstOutcome = first.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      await initialize;

      // Вторая попытка заменяет транспорт: ожидающий `initialize` первой
      // падает с «transport was replaced».
      final second = await client.connect(FakeAcpTransport());
      expect(await firstOutcome, isA<StateTransitionException>());

      expect(second, isA<ClientConnectionReady>());
      expect(states.whereType<ClientConnectionFailed>(), isEmpty);
      expect(states.last, isA<ClientConnectionReady>());
    });

    test('a late ready of the superseded attempt is not published', () async {
      final stale = FakeAcpTransport()..autoRespondToInitialize = false;
      final request = stale.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == initializeMethod,
      );
      final first = client.connect(stale);
      final firstOutcome = first.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      final initialize = await request as JsonRpcRequest;

      // Ответ приходит и тут же, в том же такте, вторая попытка поднимает
      // поколение: продолжение первой выполнится уже при новом поколении.
      stale.emitInbound(
        encodeAcpResponse(
          id: initialize.id,
          method: initializeMethod,
          result: const InitializeResponse(protocolVersion: ProtocolVersion(1)),
        ),
      );
      final winner = FakeAcpTransport();
      final second = client.connect(winner);

      expect(await firstOutcome, isA<StateTransitionException>());
      await second;

      // Ровно один `ready` — второй попытки, и он замыкает её `initialize`.
      expect(states.whereType<ClientConnectionReady>(), hasLength(1));
      expect(states.last, isA<ClientConnectionReady>());
      expect(states[states.length - 2], isA<ClientConnectionInitializing>());
      expect(client.connectionState, isA<ClientConnectionReady>());
      expect(winner.state, AcpTransportState.connected);
    });
  });

  test(
    'logs why a superseded attempt ended, with the attempt generation',
    () async {
      final captured = <Map<String, dynamic>>[];
      configureCodeLabLogging(
        applicationOutput: (entry, level) => captured.add(entry),
        protocolTraceOutput: (entry, level) => captured.add(entry),
      );
      addTearDown(StructlogConfiguration.reset);
      final client = AcpClientApplication(transport: FakeAcpTransport());
      addTearDown(client.dispose);
      final stale = FakeAcpTransport()..autoRespondToInitialize = false;
      final sent = stale.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == initializeMethod,
      );
      final first = client.connect(stale);
      final outcome = first.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      await sent;
      final staleGeneration = client.generation;

      await client.connect(FakeAcpTransport());
      await outcome;

      final entry = captured.singleWhere(
        (e) => e['event'] == 'attempt_superseded',
      );
      expect(entry['connection_generation'], staleGeneration);
      expect(entry['phase'], 'initialize');
      expect(entry['error'], contains('transport was replaced'));
    },
  );
}

/// Транспорт-обёртка: считает `close`, держит закрытие за вентилем и
/// показывает, остались ли подписчики у `inbound` и `events`.
///
/// Нужна, чтобы проверить «подписки одни» и «проигравший закрыт», чего
/// `FakeAcpTransport` не раскрывает.
final class _TrackedTransport implements AcpTransport {
  _TrackedTransport({
    Future<void>? closeGate,
    this.closeError,
    this.closeFailures = 1,
  }) : _closeGate = closeGate {
    _inbound = StreamController<JsonRpcMessage>.broadcast(
      sync: true,
      onListen: () => hasInboundListener = true,
      onCancel: () => hasInboundListener = false,
    );
    _events = StreamController<AcpTransportEvent>.broadcast(
      sync: true,
      onListen: () => hasEventListener = true,
      onCancel: () => hasEventListener = false,
    );
    _inner.inbound.listen(_inbound.add);
    _inner.events.listen(_events.add);
  }

  final _inner = FakeAcpTransport();
  final Future<void>? _closeGate;
  late final StreamController<JsonRpcMessage> _inbound;
  late final StreamController<AcpTransportEvent> _events;

  /// Ошибка первых [closeFailures] вызовов `close`; следующие (в `dispose`
  /// ядра) проходят.
  final Object? closeError;
  int closeFailures;
  var closeCalls = 0;
  final _closeWaiters = <(int, Completer<void>)>[];
  var hasInboundListener = false;
  var hasEventListener = false;

  /// Завершается, когда `close` вызвали [count] раз: детерминированная точка
  /// ожидания вместо счёта микрозадач.
  Future<void> closeCalled(int count) {
    if (closeCalls >= count) {
      return Future.value();
    }
    final waiter = Completer<void>();
    _closeWaiters.add((count, waiter));
    return waiter.future;
  }

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => _inner.state;

  @override
  Future<void> start() => _inner.start();

  @override
  Future<void> send(JsonRpcMessage message) => _inner.send(message);

  @override
  Future<void> close({Duration? timeout}) async {
    closeCalls++;
    for (final (count, waiter) in _closeWaiters) {
      if (closeCalls >= count && !waiter.isCompleted) {
        waiter.complete();
      }
    }
    await _closeGate;
    final error = closeError;
    if (error != null && closeFailures > 0) {
      closeFailures--;
      throw error;
    }
    await _inner.close(timeout: timeout);
  }
}
