import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'acp_error.dart';
import 'outbound_queue.dart';
import 'pending_requests.dart';

/// Ответ обработчика: результат уже в виде JSON (`encodeAcpResult`) и
/// действие после постановки ответа в очередь.
///
/// [after] нужен там, где уведомления обязаны идти после ответа: например,
/// `available_commands_update` после `session/new` — до ответа клиент не
/// знает `sessionId` (ACP-8).
final class Reply {
  const Reply(this.result, {this.after});

  final Object? result;
  final void Function()? after;
}

/// Обработчик запроса.
typedef RequestHandler = Future<Reply> Function(JsonRpcRequest request);

/// Обработчик уведомления клиента.
typedef NotificationHandler = Future<void> Function(JsonRpcNotification n);

/// Чтение входящих кадров соединения (§13.1, `InboundRouter`).
///
/// Почему отдельный цикл: обработчик `session/prompt` не должен блокировать
/// чтение — во время хода соединение принимает `session/cancel`, ответы на
/// запросы разрешений и запросы других сессий. Поэтому каждый запрос
/// обрабатывается своей задачей, а цикл сразу читает следующий кадр.
///
/// Для чего: запрос → [onRequest] и ответ в [OutboundQueue]; ответ клиента →
/// [PendingRequests]; уведомление → [onNotification]. Ошибки обработчика
/// становятся ответами JSON-RPC по таблице §13.10, а соединение и идущие
/// ходы живут (ACP-4).
///
/// Как использовать: соединение создаёт роутер со своими обработчиками и
/// ждёт [run] — он завершается, когда поток входящих кадров закрыт.
final class InboundRouter {
  InboundRouter({
    required AcpTransport transport,
    required OutboundQueue outbound,
    required PendingRequests pending,
    required Logger logger,
    required this.onRequest,
    required this.onNotification,
  }) : _transport = transport,
       _outbound = outbound,
       _pending = pending,
       _logger = logger;

  final AcpTransport _transport;
  final OutboundQueue _outbound;
  final PendingRequests _pending;
  final Logger _logger;
  final RequestHandler onRequest;
  final NotificationHandler onNotification;

  /// Задачи запросов, которые ещё не ответили.
  final _inFlight = <Future<void>>{};

  Future<void> run() async {
    final done = Completer<void>();
    _transport.inbound.listen(
      _route,
      onDone: done.complete,
      onError: (Object error, StackTrace stack) => _logger.log(
        LogLevel.warning,
        'acp.inbound.error',
        error: error,
        stack: stack,
      ),
    );
    await done.future;
  }

  /// Завершается, когда ответили все начатые запросы.
  Future<void> get drained => Future.wait([..._inFlight]);

  void _route(JsonRpcMessage message) {
    switch (message) {
      case JsonRpcRequest():
        final task = _answer(message);
        _inFlight.add(task);
        unawaited(task.whenComplete(() => _inFlight.remove(task)));
      case JsonRpcNotification():
        unawaited(_notify(message));
      case JsonRpcResponse():
        if (!_pending.complete(message)) {
          _logger.log(
            LogLevel.warning,
            'acp.frame.bad',
            fields: {'reason': 'unknown response id', 'id': '${message.id}'},
          );
        }
    }
  }

  Future<void> _answer(JsonRpcRequest request) async {
    JsonRpcMessage response;
    void Function()? after;
    try {
      final reply = await onRequest(request);
      after = reply.after;
      response = JsonRpcMessage.response(id: request.id, result: reply.result);
    } on AcpRequestError catch (error) {
      response = JsonRpcMessage.response(
        id: request.id,
        error: error.toJsonRpcError(),
      );
    } on JsonRpcProtocolException catch (error) {
      // Декодер codelab_acp_protocol не принял параметры (§13.10).
      response = JsonRpcMessage.response(
        id: request.id,
        error: JsonRpcError(
          code: jsonRpcInvalidParamsCode,
          message: 'Invalid params: ${error.message}',
        ),
      );
    } on Object catch (error, stack) {
      _logger.log(
        LogLevel.error,
        'acp.handler.failed',
        fields: {'method': request.method},
        error: error,
        stack: stack,
      );
      response = JsonRpcMessage.response(
        id: request.id,
        error: const JsonRpcError(
          code: jsonRpcInternalErrorCode,
          message: 'Internal error',
        ),
      );
    }
    final sent = _outbound.enqueue(response);
    after?.call();
    await sent;
  }

  Future<void> _notify(JsonRpcNotification notification) async {
    try {
      await onNotification(notification);
    } on Object catch (error, stack) {
      // Ответить на уведомление нечем: только лог (§13.10).
      _logger.log(
        LogLevel.warning,
        'acp.frame.bad',
        fields: {'method': notification.method},
        error: error,
        stack: stack,
      );
    }
  }
}
