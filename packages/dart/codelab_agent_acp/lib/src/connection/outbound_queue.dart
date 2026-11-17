import 'dart:async';
import 'dart:collection';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Единая очередь исходящих кадров соединения (§13.1, `OutboundQueue`).
///
/// Почему одна очередь: ответ на `session/prompt` должен уйти после
/// последнего `session/update` хода, а ответ `session/load` — после
/// реплея (ACP-3). Когда все кадры соединения идут через одну цепочку,
/// порядок гарантирован конструкцией, а не дисциплиной обработчиков.
///
/// Почему буфер и один цикл отправки, а не цепочка `then`: реплей ставит
/// тысячи кадров синхронно, и цепочка длиной в число кадров висела бы
/// незавершённой. Под `Chain.capture` (`flutter test` всегда включает
/// `--chain-stack-traces`) каждый обратный вызов снимает стек, а VM при
/// снимке обходит всю цепочку: реплей шёл за O(N²) — 8000 кадров за 28,6 с
/// вместо 12 мс. У цикла глубина ожидания постоянная.
///
/// Как использовать: [enqueue] ставит кадр и возвращает `Future` его
/// отправки; порядок отправки — порядок вызовов [enqueue]. Сбой отправки не
/// останавливает очередь: он логируется, а соединение узнаёт о нём через
/// [onSendFailed]; `Future` кадра со сбоем завершается без ошибки.
final class OutboundQueue {
  OutboundQueue(this._transport, {required Logger logger, this.onSendFailed})
    : _logger = logger;

  final AcpTransport _transport;
  final Logger _logger;

  /// Транспорт не принял кадр — соединение переходит в `detached` (§13.10).
  final void Function(Object error)? onSendFailed;

  final _pending = Queue<(JsonRpcMessage, Completer<void>)>();

  /// Цикл [_drain] идёт; завершается, когда буфер опустел.
  Future<void>? _draining;

  /// Ставит [message] в конец очереди; `Future` завершается после его
  /// отправки, сбой отправки — тоже без ошибки (он в логе).
  Future<void> enqueue(JsonRpcMessage message) {
    final sent = Completer<void>();
    _pending.add((message, sent));
    // Цикл стартует в микрозадаче, как прежняя цепочка от завершённого
    // Future: `send` транспорта не вызывается изнутри `enqueue`, и кадры,
    // поставленные синхронно следом (ответ и `after` маршрутизатора), уходят
    // тем же циклом.
    _draining ??= Future.microtask(_drain);
    return sent.future;
  }

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        final (message, sent) = _pending.removeFirst();
        try {
          await _transport.send(message);
        } on Object catch (error, stack) {
          _logger.log(
            LogLevel.warning,
            'acp.send.failed',
            error: error,
            stack: stack,
          );
          _reportSendFailed(error);
        } finally {
          sent.complete();
        }
      }
    } finally {
      // Страховка: если цикл всё же оборвёт исключение (например, сбой
      // логгера), следующий [enqueue] запустит новый цикл, а не встанет за
      // мёртвым.
      _draining = null;
    }
  }

  /// Сообщает соединению о сбое отправки.
  ///
  /// Почему отдельный `try`: исключение обработчика оборвало бы цикл, и
  /// оставшиеся кадры с их `Future` ждали бы следующего [enqueue], а `close()`
  /// соединения — [idle] (AGENTS.md §12: ошибка не теряется, она в логе).
  void _reportSendFailed(Object error) {
    try {
      onSendFailed?.call(error);
    } on Object catch (handlerError, stack) {
      _logger.log(
        LogLevel.warning,
        'acp.send.failed_handler',
        error: handlerError,
        stack: stack,
      );
    }
  }

  /// Завершается, когда буфер опустел: отправлены все кадры, включая
  /// поставленные уже после вызова, пока цикл ещё шёл.
  ///
  /// Для чего: `close()` соединения ждёт [idle] перед закрытием транспорта,
  /// чтобы не оборвать хвост реплея или хода. Сбои отправки [idle] не
  /// пробрасывает — они в логе и [onSendFailed].
  Future<void> get idle => _draining ?? Future.value();
}
