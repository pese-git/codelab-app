import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../acp_transport.dart';
import '../transport_configs.dart';

/// Проверяет значения заголовков до отправки, не раскрывая их.
///
/// Почему: `HttpHeaders.set` при недопустимом символе (например `\n` в токене)
/// бросает `FormatException`, чей текст содержит само значение заголовка, то
/// есть секрет попал бы в ошибку и логи.
///
/// Для чего: заменить такую ошибку типизированной, где есть только имя
/// заголовка. Это защита в глубину и она строже `dart:io`: отклоняются код
/// < 32 (кроме табуляции), 127 и любой код > 127 (только ASCII), чтобы
/// управляющие и не-ASCII символы не дошли до `dart:io` и его ошибки со
/// значением.
void _validateHeaders(Map<String, String> headers) {
  for (final MapEntry(:key, :value) in headers.entries) {
    final valid = value.codeUnits.every(
      (c) => c <= 127 && (c >= 32 || c == 9) && c != 127,
    );
    if (key.isEmpty || !valid) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.startFailed,
        message: 'Invalid header value for $key.',
      );
    }
  }
}

/// Приводит ошибку подключения к исходной, а отказ рукопожатия — к типу.
///
/// Почему: `IOWebSocketChannel` оборачивает ошибку в
/// `WebSocketChannelException`, а `dart:io` кладёт HTTP-статус отказа в
/// `WebSocketException.httpStatusCode` (Dart >= 3.10); разбирать текст
/// запрещено (design.md change `add-app-settings-shell`, D12).
///
/// Для чего: 401/403 отличается от недоступного агента через
/// `AcpWebSocketHandshakeRejected(statusCode)`. Токен в такую ошибку не
/// попадает: берётся только число.
Object _unwrapConnectError(Object error) {
  final inner = error is WebSocketChannelException ? error.inner : error;
  if (inner is WebSocketException && inner.httpStatusCode != null) {
    return AcpWebSocketHandshakeRejected(inner.httpStatusCode!);
  }
  return inner ?? error;
}

final class WebSocketAcpTransport implements AcpTransport {
  WebSocketAcpTransport(this.config);

  final WebSocketAcpTransportConfig config;

  final _inboundController = StreamController<JsonRpcMessage>.broadcast(
    sync: true,
  );
  final _eventController = StreamController<AcpTransportEvent>.broadcast(
    sync: true,
  );

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  AcpTransportState _state = AcpTransportState.idle;
  var _isClosed = false;

  @override
  Stream<JsonRpcMessage> get inbound => _inboundController.stream;

  @override
  Stream<AcpTransportEvent> get events => _eventController.stream;

  @override
  AcpTransportState get state => _state;

  @override
  Future<void> start() async {
    _ensureNotClosed();

    if (_state == AcpTransportState.connected ||
        _state == AcpTransportState.connecting) {
      return;
    }

    _setState(AcpTransportState.connecting);

    try {
      _validateHeaders(config.effectiveHeaders);
      final channel = IOWebSocketChannel.connect(
        config.uri,
        headers: config.effectiveHeaders,
      );
      try {
        await channel.ready;
      } on Object catch (error) {
        // `FormatException` из заголовков несёт их значение: не передаём её.
        if (error is WebSocketChannelException &&
            error.inner is FormatException) {
          throw const AcpTransportException(
            code: AcpTransportErrorCode.startFailed,
            message: 'Invalid WebSocket handshake request.',
          );
        }
        throw _unwrapConnectError(error);
      }
      if (_isClosed) {
        // close() вызван во время рукопожатия: сокет открылся уже после
        // него, поэтому закрываем его здесь, иначе он повиснет.
        unawaited(channel.sink.close().catchError((Object _) {}));
        return;
      }
      _channel = channel;
      _listenToChannel(channel);
      // Подписка после `ready`: при отказе рукопожатия поток канала тоже
      // отдаёт ошибку, и подписка раньше дала бы второй сбой `receiveFailed`.
      // Сервер мог закрыть сокет до этой строки: тогда `_handleDone` уже
      // перевёл транспорт в failed, затирать его connected нельзя.
      if (_state == AcpTransportState.connecting) {
        _setState(AcpTransportState.connected);
      }
    } on Object catch (error, stackTrace) {
      _fail(
        error is AcpTransportException
            ? error
            : AcpTransportException(
                code: AcpTransportErrorCode.startFailed,
                message: 'Failed to connect WebSocket ACP agent.',
                cause: error,
                stackTrace: stackTrace,
              ),
      );
      if (error is AcpTransportException) rethrow;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    _ensureConnected();

    try {
      _channel!.sink.add(encodeJsonRpcMessage(message));
    } on Object catch (error, stackTrace) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'Failed to send ACP message over WebSocket.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> close({Duration? timeout}) async {
    if (_isClosed) {
      return;
    }

    _setState(AcpTransportState.closing);
    _isClosed = true;

    await _subscription?.cancel();
    _subscription = null;

    final closeFuture = _channel?.sink.close();
    if (closeFuture != null) {
      await closeFuture.timeout(timeout ?? const Duration(seconds: 5));
    }
    _channel = null;

    _setState(AcpTransportState.closed);
    await _inboundController.close();
    await _eventController.close();
  }

  void _listenToChannel(WebSocketChannel channel) {
    _subscription = channel.stream.listen(
      _handleInbound,
      onError: (Object error, StackTrace stackTrace) {
        _fail(
          AcpTransportException(
            code: AcpTransportErrorCode.receiveFailed,
            message: 'Failed to read ACP WebSocket stream.',
            cause: error,
            stackTrace: stackTrace,
          ),
        );
      },
      onDone: _handleDone,
    );
  }

  void _handleInbound(Object? data) {
    if (_isClosed) {
      return;
    }

    if (data is! String) {
      _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.protocolViolation,
          message: 'Agent wrote non-text ACP data to WebSocket.',
        ),
      );
      return;
    }

    try {
      _inboundController.add(decodeJsonRpcMessage(data));
    } on JsonRpcProtocolException catch (error, stackTrace) {
      _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.protocolViolation,
          message: 'Agent wrote invalid ACP JSON-RPC to WebSocket.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void _handleDone() {
    if (_isClosed || _state == AcpTransportState.failed) {
      return;
    }

    _fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'WebSocket ACP agent disconnected unexpectedly.',
      ),
    );
  }

  void _ensureConnected() {
    _ensureNotClosed();

    if (_state != AcpTransportState.connected || _channel == null) {
      throw const AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'WebSocket ACP transport is not connected.',
      );
    }
  }

  void _ensureNotClosed() {
    if (_isClosed || _state == AcpTransportState.closed) {
      throw const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'WebSocket ACP transport is closed.',
      );
    }
  }

  void _fail(AcpTransportException error) {
    if (_isClosed) {
      return;
    }

    _setState(AcpTransportState.failed);
    _eventController.add(AcpTransportEvent.failure(error));
  }

  void _setState(AcpTransportState state) {
    _state = state;
    _eventController.add(AcpTransportEvent.stateChanged(state));
  }
}
