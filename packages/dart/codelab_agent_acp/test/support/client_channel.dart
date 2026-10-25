import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart' hide SessionId;
import 'package:acp_testing/acp_testing.dart';
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_acp/src/acp_client_env.dart';
import 'package:codelab_agent_acp/src/connection/client_requests.dart';
import 'package:codelab_agent_acp/src/connection/inbound_router.dart';
import 'package:codelab_agent_acp/src/connection/outbound_queue.dart';
import 'package:codelab_agent_acp/src/connection/pending_requests.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';

/// Агентский конец соединения без сервера и fake-клиент на другом конце:
/// для тестов `AcpClientExecutionEnv` и `AcpPermissionGate` (задачи 3.3,
/// 3.5).
///
/// Агентский конец собран так же, как в `_Connection`: очередь, реестр
/// запросов и маршрутизатор; конец входящего потока — разрыв, ожидания
/// завершаются [ClientDisconnected].
final class ClientChannel {
  ClientChannel._(
    this.link,
    this.clock,
    this.logger,
    this.requests,
    this.client,
  );

  static Future<ClientChannel> open({
    ClientCapabilities capabilities = const ClientCapabilities(
      fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
      terminal: true,
    ),
  }) async {
    final transports = InProcessAcpLink();
    final clock = FakeClock();
    final logger = RecordingLogger();
    final pending = PendingRequests();
    final outbound = OutboundQueue(transports.agent, logger: logger);
    final router = InboundRouter(
      transport: transports.agent,
      outbound: outbound,
      pending: pending,
      logger: logger,
      onRequest: (request) =>
          throw StateError('unexpected client request ${request.method}'),
      onNotification: (_) async {},
    );
    await transports.agent.start();
    unawaited(
      router.run().then((_) => pending.failAll(const ClientDisconnected())),
    );
    final requests = ClientRequests(
      outbound: outbound,
      pending: pending,
      clock: clock,
    );
    final link = ClientLink(requests: requests, capabilities: capabilities)
      ..sessionId = 'sess_1';
    final client = FakeClient(transports.client);
    await client.start();
    return ClientChannel._(link, clock, logger, requests, client);
  }

  final ClientLink link;
  final FakeClock clock;
  final RecordingLogger logger;
  final ClientRequests requests;
  final FakeClient client;

  AcpClientExecutionEnvFactory get env =>
      ({String cwd = '/work', AcpTimeouts timeouts = const AcpTimeouts()}) =>
          AcpClientExecutionEnv(
            link: link,
            cwd: cwd,
            timeouts: timeouts,
            clock: clock,
            logger: logger,
          );
}

typedef AcpClientExecutionEnvFactory =
    AcpClientExecutionEnv Function({String cwd, AcpTimeouts timeouts});

/// Ответ клиента ошибкой JSON-RPC.
final class ClientFailure implements Exception {
  const ClientFailure(this.code, this.message);

  final int code;
  final String message;
}

typedef ClientHandler = FutureOr<Object?> Function(JsonRpcRequest request);

/// Fake ACP-клиент: записывает запросы агента и отвечает обработчиком
/// метода; запрос без обработчика ждёт ответа теста ([respond]).
final class FakeClient {
  FakeClient(this.transport);

  final AcpTransport transport;
  final handlers = <String, ClientHandler>{};

  /// Запросы агента в порядке прихода.
  final requests = <JsonRpcRequest>[];
  final _held = <String, List<JsonRpcRequest>>{};
  final _arrivals = StreamController<JsonRpcRequest>.broadcast();

  Future<void> start() async {
    transport.inbound.listen(_onMessage);
    await transport.start();
  }

  List<String> get methods => [for (final r in requests) r.method];

  Map<String, Object?> paramsOf(String method) =>
      requests.lastWhere((r) => r.method == method).params!
          as Map<String, Object?>;

  /// Следующий запрос метода [method], уже пришедший или будущий.
  Future<JsonRpcRequest> arrival(String method) {
    final held = _held[method];
    if (held != null && held.isNotEmpty) {
      return Future.value(held.first);
    }
    return _arrivals.stream
        .firstWhere((r) => r.method == method)
        .timeout(const Duration(seconds: 5));
  }

  /// Ответ на ожидающий запрос [request].
  Future<void> respond(JsonRpcRequest request, Object? result) {
    _held[request.method]?.remove(request);
    return transport.send(
      JsonRpcMessage.response(id: request.id, result: result),
    );
  }

  Future<void> close() => transport.close();

  void _onMessage(JsonRpcMessage message) {
    if (message is! JsonRpcRequest) {
      return;
    }
    requests.add(message);
    final handler = handlers[message.method];
    if (handler == null) {
      (_held[message.method] ??= []).add(message);
      _arrivals.add(message);
      return;
    }
    unawaited(_answer(message, handler));
  }

  Future<void> _answer(JsonRpcRequest request, ClientHandler handler) async {
    JsonRpcMessage response;
    try {
      response = JsonRpcMessage.response(
        id: request.id,
        result: await handler(request),
      );
    } on ClientFailure catch (failure) {
      response = JsonRpcMessage.response(
        id: request.id,
        error: JsonRpcError(code: failure.code, message: failure.message),
      );
    }
    await transport.send(response);
  }

  /// Файлы клиента в памяти: `fs/*` по семантике codelab-app, «не найдено»
  /// — `-32002`, прочие отказы — `-32603` с текстом.
  void serveFiles(MemoryExecutionEnv files) {
    handlers[fsReadTextFileMethod] = (request) async {
      final params = request.params! as Map<String, Object?>;
      final result = await files.readText(
        params['path']! as String,
        line: params['line'] as int?,
        limit: params['limit'] as int?,
      );
      return switch (result) {
        Ok(:final value) => {'content': value},
        Err(:final error) => throw _failure(error),
      };
    };
    handlers[fsWriteTextFileMethod] = (request) async {
      final params = request.params! as Map<String, Object?>;
      final result = await files.writeText(
        params['path']! as String,
        params['content']! as String,
      );
      return switch (result) {
        Ok() => <String, Object?>{},
        Err(:final error) => throw _failure(error),
      };
    };
  }

  /// Терминалы клиента: `terminal/create` отдаёт `term_<n>`, ожидание
  /// выхода — [exit], вывод — [output].
  void serveTerminals({
    int? exitCode = 0,
    String output = '',
    bool holdExit = false,
  }) {
    var next = 0;
    handlers[terminalCreateMethod] = (_) => {'terminalId': 'term_${++next}'};
    if (!holdExit) {
      handlers[terminalWaitForExitMethod] = (_) => {'exitCode': exitCode};
    }
    handlers[terminalOutputMethod] = (_) => {
      'output': output,
      'truncated': false,
      'exitStatus': {'exitCode': exitCode},
    };
    handlers[terminalKillMethod] = (_) => <String, Object?>{};
    handlers[terminalReleaseMethod] = (_) => <String, Object?>{};
  }

  static ClientFailure _failure(FileError error) =>
      error.code == FileErrorCode.notFound
      ? ClientFailure(-32002, 'Resource not found: ${error.path}')
      : ClientFailure(-32603, '${error.code.name}: ${error.path}');
}
