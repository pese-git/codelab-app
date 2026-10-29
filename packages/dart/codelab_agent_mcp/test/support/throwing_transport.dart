import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Обёртка над транспортом, которая бросает не-MCP исключение на `send`
/// сообщения с методом [method] (сбой реализации транспорта, а не протокола).
final class ThrowingTransport implements McpTransport {
  ThrowingTransport(this.inner, this.method);

  final McpTransport inner;
  final String method;

  @override
  String get kind => inner.kind;

  @override
  Stream<String> get incoming => inner.incoming;

  @override
  Stream<McpRequestAbort> get abortedRequests => inner.abortedRequests;

  @override
  Future<McpTransportClosed> get done => inner.done;

  @override
  Future<void> send(String message, {Map<String, String> headers = const {}}) {
    if (message.contains('"method":"$method"')) {
      throw StateError('send failed');
    }
    return inner.send(message, headers: headers);
  }

  @override
  Future<void> abandon(Object requestId) => inner.abandon(requestId);

  @override
  Future<void> close() => inner.close();
}

/// Фабрика, оборачивающая транспорты выбранных серверов.
final class ThrowingFactory implements McpTransportFactory {
  ThrowingFactory(this.inner, this.throwingFor, this.method);

  final McpTransportFactory inner;
  final Set<String> throwingFor;
  final String method;

  /// Бросать уже при открытии.
  var failOpen = false;

  @override
  Set<String> get transports => inner.transports;

  @override
  Future<McpTransport> open(
    McpServerConfig server, {
    required String cwd,
    required CancelToken cancel,
    required Logger logger,
  }) async {
    final transport = await inner.open(
      server,
      cwd: cwd,
      cancel: cancel,
      logger: logger,
    );
    if (failOpen && throwingFor.contains(server.name)) {
      throw StateError('open failed');
    }
    return throwingFor.contains(server.name)
        ? ThrowingTransport(transport, method)
        : transport;
  }
}
