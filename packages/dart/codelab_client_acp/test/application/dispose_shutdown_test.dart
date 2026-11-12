// Закрытие ядра клиента при выходе из приложения (change
// `add-client-process-shutdown-on-exit`, D4, D6): завершение terminal-процессов
// и закрытие транспорта идут параллельно, `dispose` ждёт оба; событие журнала
// `terminal_processes_killed` не содержит команд, путей и идентификаторов.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

/// Обёртка над [FakeAcpTransport], запоминающая аргументы `close`.
///
/// `FakeAcpTransport` — `final`, поэтому наследование невозможно; делегат
/// нужен, чтобы увидеть `timeout` и момент вызова `close`.
final class _RecordingTransport implements AcpTransport {
  _RecordingTransport(this.inner);

  final FakeAcpTransport inner;
  final closeTimeouts = <Duration?>[];

  @override
  Stream<JsonRpcMessage> get inbound => inner.inbound;

  @override
  Stream<AcpTransportEvent> get events => inner.events;

  @override
  AcpTransportState get state => inner.state;

  @override
  Future<void> start() => inner.start();

  @override
  Future<void> send(JsonRpcMessage message) => inner.send(message);

  @override
  Future<void> close({Duration? timeout}) {
    closeTimeouts.add(timeout);
    return inner.close(timeout: timeout);
  }
}

/// Процесс, у которого `kill()` завершается по команде теста.
final class _ManualKillHandle implements TerminalProcessHandle {
  final killGate = Completer<void>();
  var killCalls = 0;

  @override
  String get output => '';

  @override
  bool get truncated => false;

  @override
  TerminalProcessState get state => const TerminalProcessState.running();

  @override
  Future<TerminalProcessState> waitForExit() =>
      Completer<TerminalProcessState>().future;

  @override
  Future<void> kill() {
    killCalls++;
    return killGate.future;
  }
}

final class _ManualKillRunner implements TerminalProcessRunner {
  final handle = _ManualKillHandle();

  @override
  Future<TerminalProcessHandle> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
    required String cwd,
    int? outputByteLimit,
  }) async => handle;
}

void main() {
  late FakeAcpTransport fake;
  late _RecordingTransport transport;
  late _ManualKillRunner runner;
  late List<Map<String, dynamic>> captured;

  setUp(() async {
    captured = <Map<String, dynamic>>[];
    configureCodeLabLogging(
      applicationOutput: (entry, level) => captured.add(entry),
      protocolTraceOutput: (entry, level) => captured.add(entry),
    );
    fake = FakeAcpTransport();
    await fake.start();
    transport = _RecordingTransport(fake);
    runner = _ManualKillRunner();
  });

  tearDown(StructlogConfiguration.reset);

  Future<AcpClientApplication> clientWithRunningTerminal() async {
    final client = AcpClientApplication(
      transport: transport,
      terminalProcessRunner: runner,
    );
    final created = CreateSession(client)(
      const CreateSessionCommand(cwd: '/workspace'),
    ).run();
    await _pump();
    final request = fake.sentMessages.single as JsonRpcRequest;
    fake.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(
          sessionId: SessionId('session-1'),
        ).toJson(),
      ),
    );
    await created;
    fake.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(1),
        method: terminalCreateMethod,
        params: const CreateTerminalRequest(
          sessionId: SessionId('session-1'),
          command: 'secret-command',
        ).toJson(),
      ),
    );
    await _pump();
    return client;
  }

  List<Map<String, dynamic>> killedEvents() => [
    for (final entry in captured)
      if (entry['event'] == 'terminal_processes_killed') entry,
  ];

  test(
    'dispose passes closeTimeout to the transport; without it null',
    () async {
      final withTimeout = AcpClientApplication(transport: transport);
      await withTimeout.dispose(closeTimeout: const Duration(seconds: 2));
      expect(transport.closeTimeouts, [const Duration(seconds: 2)]);

      final fake2 = FakeAcpTransport();
      await fake2.start();
      final transport2 = _RecordingTransport(fake2);
      await AcpClientApplication(transport: transport2).dispose();
      expect(transport2.closeTimeouts, [null]);
    },
  );

  test('transport close starts without waiting for terminal kill; dispose '
      'completes after both', () async {
    final client = await clientWithRunningTerminal();

    var disposed = false;
    final disposing = client
        .dispose(closeTimeout: const Duration(seconds: 2))
        .then((_) => disposed = true);
    await _pump();

    expect(runner.handle.killCalls, 1);
    expect(transport.closeTimeouts, [const Duration(seconds: 2)]);
    expect(disposed, isFalse, reason: 'kill is still pending');

    runner.handle.killGate.complete();
    await disposing;
    expect(disposed, isTrue);
  });

  test('dispose logs terminal_processes_killed with count and reason only, '
      'and a repeated dispose does not kill again', () async {
    final client = await clientWithRunningTerminal();
    runner.handle.killGate.complete();

    await client.dispose();
    await client.dispose();

    expect(runner.handle.killCalls, 1);
    final events = killedEvents();
    expect(events, hasLength(1));
    expect(events.single['count'], 1);
    expect(events.single['reason'], 'dispose');
    final dump = events.single.toString();
    expect(dump, isNot(contains('secret-command')));
    expect(dump, isNot(contains('/workspace')));
    expect(dump, isNot(contains('term-')));
  });

  test('no event is logged when the registry is empty', () async {
    final client = AcpClientApplication(
      transport: transport,
      terminalProcessRunner: runner,
    );
    await client.dispose();
    expect(killedEvents(), isEmpty);
  });

  test('a connection failure logs reason connection_closed', () async {
    final fresh = FakeAcpTransport()
      ..initializeProtocolVersion =
          AcpClientApplication.supportedProtocolVersion;
    final client = AcpClientApplication(
      transport: FakeAcpTransport(),
      terminalProcessRunner: runner,
    );
    await client.connect(fresh);
    fresh.drainSentMessages();
    final created = CreateSession(client)(
      const CreateSessionCommand(cwd: '/workspace'),
    ).run();
    await _pump();
    final request = fresh.sentMessages.single as JsonRpcRequest;
    fresh.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(
          sessionId: SessionId('session-1'),
        ).toJson(),
      ),
    );
    await created;
    fresh.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(1),
        method: terminalCreateMethod,
        params: const CreateTerminalRequest(
          sessionId: SessionId('session-1'),
          command: 'x',
        ).toJson(),
      ),
    );
    await _pump();
    runner.handle.killGate.complete();

    fresh.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'gone',
      ),
    );
    await _pump();

    final events = killedEvents();
    expect(events, hasLength(1));
    expect(events.single['reason'], 'connection_closed');
    expect(events.single['count'], 1);
    await client.dispose();
  });
  // 7.1 (D4, D12): массовое завершение, запущенное разрывом соединения, тоже
  // должно быть дождано в `dispose`, иначе SIGKILL процессу, игнорирующему
  // SIGTERM, не уйдёт, если выход пришёл вскоре после падения агента.
  test(
    'dispose waits for the mass kill started by a connection failure',
    () async {
      // Событие падения доходит до ядра только от транспорта, привязанного
      // через `connect`, поэтому соединение открывается явно.
      final fresh = FakeAcpTransport()
        ..initializeProtocolVersion =
            AcpClientApplication.supportedProtocolVersion;
      final client = AcpClientApplication(
        transport: FakeAcpTransport(),
        terminalProcessRunner: runner,
      );
      await client.connect(fresh);
      fresh.drainSentMessages();
      final created = CreateSession(client)(
        const CreateSessionCommand(cwd: '/workspace'),
      ).run();
      await _pump();
      final request = fresh.sentMessages.single as JsonRpcRequest;
      fresh.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: const NewSessionResponse(
            sessionId: SessionId('session-1'),
          ).toJson(),
        ),
      );
      await created;
      fresh.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(1),
          method: terminalCreateMethod,
          params: const CreateTerminalRequest(
            sessionId: SessionId('session-1'),
            command: 'x',
          ).toJson(),
        ),
      );
      await _pump();

      fresh.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'gone',
        ),
      );
      await _pump();
      expect(runner.handle.killCalls, 1, reason: 'kill started by the failure');

      var disposed = false;
      final disposing = client.dispose().then((_) => disposed = true);
      await _pump();
      expect(
        disposed,
        isFalse,
        reason: 'the failure-time kill is still pending',
      );

      runner.handle.killGate.complete();
      await disposing;
      expect(disposed, isTrue);
      expect(runner.handle.killCalls, 1, reason: 'no second kill');
    },
  );

  // D12: закрытие ядра во время Connect/Reconnect и старта terminal-процесса.
  group('dispose during connect, reconnect and terminal start (D12)', () {
    late _ManualTransport current;
    late AcpClientApplication client;

    setUp(() {
      current = _ManualTransport();
      client = AcpClientApplication(
        transport: current,
        terminalProcessRunner: runner,
      );
    });

    /// Результат операции без ожидания: красный тест падает по флагу `done`,
    /// а не зависает до таймаута запроса (60 s).
    ({bool Function() done, Object? Function() error}) track(Future<void> f) {
      var done = false;
      Object? error;
      f.then<void>(
        (_) => done = true,
        onError: (Object e) {
          error = e;
          done = true;
        },
      );
      return (done: () => done, error: () => error);
    }

    test('reconnect waiting for the factory: transport returned after dispose '
        'is closed, not started and not bound', () async {
      final factoryGate = Completer<AcpTransport>();
      final reconnect = track(
        client.reconnect(
          ReconnectCommand(transportFactory: () => factoryGate.future),
        ),
      );
      await _pump();

      final disposing = client.dispose();
      await _pump();
      final late = _ManualTransport();
      factoryGate.complete(late);
      await _pump();
      await disposing;

      expect(late.startCalls, 0, reason: 'a disposed core must not spawn');
      expect(late.closeCalls, 1);
      expect(late.inboundController.hasListener, isFalse);
      expect(late.eventsController.hasListener, isFalse);
      expect(reconnect.done(), isTrue);
      expect(reconnect.error(), isA<AcpClientApplicationException>());
    });

    test('reconnect waiting for close of the previous transport: the new one '
        'is closed, not bound and not started', () async {
      final closeGate = Completer<void>();
      current.closeGate = closeGate;
      final replacement = _ManualTransport();
      final reconnect = track(
        client.reconnect(ReconnectCommand(transportFactory: () => replacement)),
      );
      await _pump();
      expect(current.closeCalls, 1);

      final disposing = client.dispose();
      await _pump();
      closeGate.complete();
      await _pump();
      await disposing;

      expect(replacement.startCalls, 0);
      expect(replacement.closeCalls, 1);
      expect(replacement.inboundController.hasListener, isFalse);
      expect(replacement.eventsController.hasListener, isFalse);
      expect(reconnect.done(), isTrue);
      expect(reconnect.error(), isA<AcpClientApplicationException>());
    });

    test('connect waiting for start: dispose closes the transport and connect '
        'fails after start completes', () async {
      final target = _ManualTransport()..startGate = Completer<void>();
      final connect = track(client.connect(target).then((_) {}));
      await _pump();
      expect(target.startCalls, 1);

      final disposing = client.dispose();
      await _pump();
      expect(target.closeCalls, 1, reason: 'dispose closes the bound one');
      target.startGate!.complete();
      await _pump();
      await disposing;

      expect(connect.done(), isTrue);
      expect(connect.error(), isA<AcpClientApplicationException>());
      expect(target.sent, isEmpty, reason: 'no initialize after dispose');
    });

    test('repeated dispose returns the same Future and closes the transport '
        'once', () async {
      final first = client.dispose();
      final second = client.dispose();

      expect(identical(first, second), isTrue);
      await first;
      expect(current.closeCalls, 1);
    });

    test('terminal/create starting during dispose: the process is killed, '
        'not registered, no response, dispose waits for kill', () async {
      final startGate = Completer<TerminalProcessHandle>();
      final delayedRunner = _DelayedStartRunner(startGate);
      final target = FakeAcpTransport();
      await target.start();
      final app = AcpClientApplication(
        transport: target,
        terminalProcessRunner: delayedRunner,
      );
      final created = CreateSession(app)(
        const CreateSessionCommand(cwd: '/workspace'),
      ).run();
      await _pump();
      final newSession = target.sentMessages.single as JsonRpcRequest;
      target.emitInbound(
        JsonRpcMessage.response(
          id: newSession.id,
          result: const NewSessionResponse(
            sessionId: SessionId('session-1'),
          ).toJson(),
        ),
      );
      await created;
      target.drainSentMessages();
      target.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(7),
          method: terminalCreateMethod,
          params: const CreateTerminalRequest(
            sessionId: SessionId('session-1'),
            command: 'sleep',
          ).toJson(),
        ),
      );
      await _pump();
      expect(delayedRunner.startCalls, 1);

      var disposed = false;
      final disposing = app.dispose().then((_) => disposed = true);
      await _pump();
      final handle = _ManualKillHandle();
      startGate.complete(handle);
      await _pump();

      expect(handle.killCalls, 1, reason: 'the late process must not live on');
      expect(disposed, isFalse, reason: 'dispose waits for the kill');
      handle.killGate.complete();
      await disposing;
      expect(disposed, isTrue);
      expect(
        target.sentMessages.whereType<JsonRpcResponse>(),
        isEmpty,
        reason: 'no terminal/create response after dispose',
      );
    });
  });
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// Транспорт, чьими `start` и `close` управляет тест (D12).
///
/// Нужен вместо [FakeAcpTransport], потому что тестам важно видеть число
/// вызовов `start`/`close`, наличие подписчиков на потоках и держать
/// завершение `start`/`close` на ручных `Completer`.
final class _ManualTransport implements AcpTransport {
  final inboundController = StreamController<JsonRpcMessage>.broadcast();
  final eventsController = StreamController<AcpTransportEvent>.broadcast();
  final sent = <JsonRpcMessage>[];
  Completer<void>? startGate;
  Completer<void>? closeGate;
  var startCalls = 0;
  var closeCalls = 0;

  @override
  Stream<JsonRpcMessage> get inbound => inboundController.stream;

  @override
  Stream<AcpTransportEvent> get events => eventsController.stream;

  @override
  AcpTransportState get state => AcpTransportState.idle;

  @override
  Future<void> start() {
    startCalls++;
    return startGate?.future ?? Future<void>.value();
  }

  @override
  Future<void> send(JsonRpcMessage message) async => sent.add(message);

  @override
  Future<void> close({Duration? timeout}) {
    closeCalls++;
    return closeGate?.future ?? Future<void>.value();
  }
}

/// Runner, чей `start` завершается по команде теста (D12).
final class _DelayedStartRunner implements TerminalProcessRunner {
  _DelayedStartRunner(this.gate);

  final Completer<TerminalProcessHandle> gate;
  var startCalls = 0;

  @override
  Future<TerminalProcessHandle> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
    required String cwd,
    int? outputByteLimit,
  }) {
    startCalls++;
    return gate.future;
  }
}
