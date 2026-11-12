// Ответ на `terminal/*` уходит только в соединение запроса и только пока ядро
// не закрыто (change `add-client-process-shutdown-on-exit`, D15;
// acp-terminal-client «Ответ на terminal-запрос только в соединение запроса»),
// а сбой журнала не оставляет процессы живыми (D15, находка F).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');

/// Процесс, чьими `kill` и `waitForExit` управляет тест.
final class _GatedHandle implements TerminalProcessHandle {
  final killGate = Completer<void>();
  final exitGate = Completer<TerminalProcessState>();
  var killCalls = 0;

  @override
  String get output => '';

  @override
  bool get truncated => false;

  @override
  TerminalProcessState get state => const TerminalProcessState.running();

  @override
  Future<TerminalProcessState> waitForExit() => exitGate.future;

  @override
  Future<void> kill() {
    killCalls++;
    return killGate.future;
  }
}

final class _SingleHandleRunner implements TerminalProcessRunner {
  _SingleHandleRunner(this.handle);

  final _GatedHandle handle;

  @override
  Future<TerminalProcessHandle> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
    required String cwd,
    int? outputByteLimit,
  }) async => handle;
}

/// Runner, выдающий заготовленные процессы по очереди (по одному на старт).
final class _QueueRunner implements TerminalProcessRunner {
  _QueueRunner(this.handles);

  final List<TerminalProcessHandle> handles;
  var _next = 0;

  @override
  Future<TerminalProcessHandle> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
    required String cwd,
    int? outputByteLimit,
  }) async => handles[_next++];
}

/// Runner, чей `start` завершается по команде теста.
final class _GatedStartRunner implements TerminalProcessRunner {
  final startGate = Completer<TerminalProcessHandle>();

  @override
  Future<TerminalProcessHandle> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
    required String cwd,
    int? outputByteLimit,
  }) => startGate.future;
}

/// Процесс, чьё чтение `output` выполняет действие теста: так ответ
/// `terminal/output` становится устаревшим между разбором запроса и отправкой.
final class _OutputHookHandle extends _GatedHandle {
  void Function()? onOutput;

  @override
  String get output {
    onOutput?.call();
    return '';
  }
}

/// Логгер, бросающий на заданном событии (D15: сбой журнала при выходе).
final class _ThrowingLogger implements Logger {
  _ThrowingLogger(this.failingEvent);

  final String failingEvent;

  @override
  Logger bind(Map<String, Object?> context) => this;

  @override
  Logger withCorrelation({
    String? sessionId,
    String? requestId,
    int? connectionGeneration,
    String? toolCallId,
    String? messageId,
    String? operationId,
  }) => this;

  void _maybeThrow(String? event) {
    if (event == failingEvent) {
      throw StateError('log sink failed');
    }
  }

  @override
  void trace(String? event, {Map<String, Object?>? context}) {}

  @override
  void debug(String? event, {Map<String, Object?>? context}) {}

  @override
  void info(String? event, {Map<String, Object?>? context}) =>
      _maybeThrow(event);

  @override
  void warning(String? event, {Map<String, Object?>? context}) =>
      _maybeThrow(event);

  @override
  void error(String? event, {Map<String, Object?>? context}) =>
      _maybeThrow(event);

  @override
  void critical(String? event, {Map<String, Object?>? context}) =>
      _maybeThrow(event);
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAcpTransport fake;
  late _GatedHandle handle;
  late AcpClientApplication client;
  late List<Map<String, dynamic>> captured;

  setUp(() {
    captured = <Map<String, dynamic>>[];
    configureCodeLabLogging(
      applicationOutput: (entry, level) => captured.add(entry),
      protocolTraceOutput: (entry, level) => captured.add(entry),
    );
  });

  tearDown(StructlogConfiguration.reset);

  /// Клиент с сессией и одним зарегистрированным terminal-процессом
  /// `term-1` (запрос `terminal/create` с id 1).
  Future<AcpClientApplication> startClient({
    Logger? logger,
    _GatedHandle? firstHandle,
    TerminalProcessRunner? runner,
    bool createTerminal = true,
  }) async {
    fake = FakeAcpTransport();
    await fake.start();
    handle = firstHandle ?? _GatedHandle();
    final app = AcpClientApplication(
      transport: fake,
      terminalProcessRunner: runner ?? _SingleHandleRunner(handle),
      logger: logger,
    );
    final created = CreateSession(app)(
      const CreateSessionCommand(cwd: '/workspace'),
    ).run();
    await _pump();
    final request = fake.sentMessages.single as JsonRpcRequest;
    fake.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(sessionId: _session).toJson(),
      ),
    );
    await created;
    if (createTerminal) {
      fake.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(1),
          method: terminalCreateMethod,
          params: const CreateTerminalRequest(
            sessionId: _session,
            command: 'cmd',
          ).toJson(),
        ),
      );
      await _pump();
    }
    fake.drainSentMessages();
    return app;
  }

  void sendTerminalRequest(int id, String method, Map<String, Object?> extra) {
    fake.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: method,
        params: {'sessionId': _session.value, 'terminalId': 'term-1', ...extra},
      ),
    );
  }

  /// Заменяет транспорт; возвращает новый. Ответы старого соединения ждут
  /// своих `Completer` и завершатся уже после замены.
  Future<FakeAcpTransport> replaceTransport() async {
    final replacement = FakeAcpTransport();
    addTearDown(replacement.close);
    await client.reconnect(
      ReconnectCommand(transportFactory: () => replacement),
    );
    replacement.drainSentMessages();
    return replacement;
  }

  void expectNoResponseTo(FakeAcpTransport transport, int id) {
    expect(
      transport.sentMessages.whereType<JsonRpcResponse>().where(
        (r) => r.id == JsonRpcId.integer(id),
      ),
      isEmpty,
      reason: 'a response of the old connection must not reach the new one',
    );
  }

  void expectStaleTerminalResponseLogged() {
    final entries = captured.where(
      (e) =>
          e['reason'] == 'stale_generation' && e['kind'] == 'terminal_response',
    );
    expect(entries, hasLength(1));
    expect(entries.single['event'], 'event_ignored');
    expect(entries.single['connection_generation'], 0);
  }

  group('response after the transport was replaced', () {
    test('terminal/kill does not answer the new connection', () async {
      client = await startClient();
      sendTerminalRequest(2, terminalKillMethod, {});
      await _pump();
      final replacement = await replaceTransport();

      handle.killGate.complete();
      await _pump();

      expectNoResponseTo(replacement, 2);
      expectStaleTerminalResponseLogged();
      await client.dispose();
    });

    test('terminal/wait_for_exit does not answer the new connection', () async {
      client = await startClient();
      sendTerminalRequest(2, terminalWaitForExitMethod, {});
      await _pump();
      final replacement = await replaceTransport();

      handle.exitGate.complete(const TerminalProcessState.exited(exitCode: 0));
      await _pump();

      expectNoResponseTo(replacement, 2);
      expectStaleTerminalResponseLogged();
      // Замена транспорта уже вызвала `kill()` процесса; без завершения
      // этого `kill()` dispose ждал бы его до таймаута теста.
      handle.killGate.complete();
      await client.dispose();
    });

    test('terminal/release does not answer the new connection', () async {
      client = await startClient();
      sendTerminalRequest(2, terminalReleaseMethod, {});
      await _pump();
      final replacement = await replaceTransport();

      handle.killGate.complete();
      await _pump();

      expectNoResponseTo(replacement, 2);
      expectStaleTerminalResponseLogged();
      await client.dispose();
    });

    test('an error result is not sent to the new connection either', () async {
      client = await startClient();
      sendTerminalRequest(2, terminalKillMethod, {});
      await _pump();
      final replacement = await replaceTransport();

      handle.killGate.completeError(
        const UnknownTerminalFailure(TerminalId('term-1')),
      );
      await _pump();

      expectNoResponseTo(replacement, 2);
      expectStaleTerminalResponseLogged();
      await client.dispose();
    });
  });

  group('response after dispose', () {
    test('is not sent and no send-failure diagnostic is written', () async {
      client = await startClient();
      sendTerminalRequest(2, terminalKillMethod, {});
      await _pump();
      handle.killGate.complete();
      // Транспорт не принимает отправку после закрытия: любая попытка ответа
      // стала бы диагностикой об ошибке отправки.
      fake.failNextSend(
        const AcpTransportException(
          code: AcpTransportErrorCode.closed,
          message: 'closed',
        ),
      );

      await client.dispose();
      await _pump();

      expectNoResponseTo(fake, 2);
      expect(
        client.diagnostics.where((d) => d.message.contains('Failed to send')),
        isEmpty,
      );
    });
  });

  // 7.2 (D15, §9): поздний `terminal/release` старого соединения не должен
  // удалять из реестра процесс нового агента с тем же `terminalId`.
  test('a late terminal/release of the old connection keeps the new process '
      'with the same terminalId registered', () async {
    final oldHandle = _GatedHandle();
    final newHandle = _GatedHandle();
    client = await startClient(
      firstHandle: oldHandle,
      runner: _QueueRunner([oldHandle, newHandle]),
    );
    sendTerminalRequest(2, terminalReleaseMethod, {});
    await _pump();
    expect(oldHandle.killCalls, 1, reason: 'release waits for kill');

    final replacement = await replaceTransport();
    // Новый агент создаёт процесс; id запроса тот же, поэтому тот же terminalId.
    replacement.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(1),
        method: terminalCreateMethod,
        params: const CreateTerminalRequest(
          sessionId: _session,
          command: 'cmd',
        ).toJson(),
      ),
    );
    await _pump();
    expect(
      replacement.sentMessages.whereType<JsonRpcResponse>().single.error,
      isNull,
      reason: 'terminal/create of the new connection succeeded',
    );
    replacement.drainSentMessages();

    oldHandle.killGate.complete();
    await _pump();

    replacement.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(3),
        method: terminalOutputMethod,
        params: {'sessionId': _session.value, 'terminalId': 'term-1'},
      ),
    );
    await _pump();
    final answer = replacement.sentMessages.whereType<JsonRpcResponse>().single;
    expect(answer.error, isNull, reason: 'the new process is still registered');
    newHandle.killGate.complete();
    await client.dispose();
  });

  // 7.3 (D15, §9, §16): terminal/create, ответ которому не нужен.
  test('terminal/create finished after Reconnect: the process is killed, no '
      'response goes to the new connection, event_ignored carries the '
      'method and request_id', () async {
    final runner = _GatedStartRunner();
    client = await startClient(runner: runner, createTerminal: false);
    fake.emitInbound(
      JsonRpcMessage.request(
        id: const JsonRpcId.integer(5),
        method: terminalCreateMethod,
        params: const CreateTerminalRequest(
          sessionId: _session,
          command: 'cmd',
        ).toJson(),
      ),
    );
    await _pump();
    final replacement = await replaceTransport();

    final late = _GatedHandle();
    runner.startGate.complete(late);
    await _pump();

    expect(late.killCalls, 1, reason: 'the late process must not live on');
    expectNoResponseTo(replacement, 5);
    final entries = captured.where(
      (e) =>
          e['event'] == 'event_ignored' &&
          e['kind'] == 'terminal_create_result',
    );
    expect(entries, hasLength(1));
    expect(entries.single['reason'], 'stale_generation');
    expect(entries.single['connection_generation'], 0);
    expect(entries.single['method'], terminalCreateMethod);
    expect(entries.single['request_id'], '5');
    late.killGate.complete();
    await client.dispose();
  });

  test('terminal/output made stale while the response is being built is not '
      'sent; event_ignored carries the method and request_id', () async {
    final hooked = _OutputHookHandle();
    client = await startClient(firstHandle: hooked);
    // Закрытие ядра посреди формирования ответа — самый короткий
    // детерминированный способ сделать ответ устаревшим.
    hooked.onOutput = () {
      hooked.onOutput = null;
      unawaited(client.dispose());
    };
    sendTerminalRequest(4, terminalOutputMethod, {});
    await _pump();

    expectNoResponseTo(fake, 4);
    final entries = captured.where(
      (e) => e['event'] == 'event_ignored' && e['kind'] == 'terminal_response',
    );
    expect(entries, hasLength(1));
    expect(entries.single['method'], terminalOutputMethod);
    expect(entries.single['request_id'], '4');
    hooked.killGate.complete();
    await client.dispose();
  });

  test('a logger failing on terminal_processes_killed does not leave '
      'processes alive and dispose does not throw', () async {
    client = await startClient(
      logger: _ThrowingLogger('terminal_processes_killed'),
    );
    handle.killGate.complete();

    await client.dispose();

    expect(handle.killCalls, greaterThanOrEqualTo(1));
  });
}
