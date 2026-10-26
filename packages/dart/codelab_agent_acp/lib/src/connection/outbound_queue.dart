import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Единая очередь исходящих кадров соединения (§13.1, `OutboundQueue`).
///
/// Почему одна очередь: ответ на `session/prompt` должен уйти после
/// последнего `session/update` хода, а ответ `session/load` — после
/// реплея (ACP-3). Когда все кадры соединения идут через одну цепочку,
/// порядок гарантирован конструкцией, а не дисциплиной обработчиков.
///
/// Как использовать: [enqueue] ставит кадр и возвращает `Future` его
/// отправки; порядок отправки — порядок вызовов [enqueue]. Сбой отправки не
/// останавливает очередь: он логируется, а соединение узнаёт о нём через
/// [onSendFailed].
final class OutboundQueue {
  OutboundQueue(this._transport, {required Logger logger, this.onSendFailed})
    : _logger = logger;

  final AcpTransport _transport;
  final Logger _logger;

  /// Транспорт не принял кадр — соединение переходит в `detached` (§13.10).
  final void Function(Object error)? onSendFailed;
  Future<void> _tail = Future.value();

  Future<void> enqueue(JsonRpcMessage message) {
    final sent = _tail.then((_) => _transport.send(message));
    _tail = sent.then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _logger.log(
          LogLevel.warning,
          'acp.send.failed',
          error: error,
          stack: stack,
        );
        onSendFailed?.call(error);
      },
    );
    return _tail;
  }

  /// Завершается, когда отправлены все поставленные кадры.
  Future<void> get idle => _tail;
}
