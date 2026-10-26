import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import '../acp_transport.dart';
import 'server_frames.dart';

/// Серверный WebSocket-транспорт агента: ACP поверх уже принятого
/// `WebSocket`.
///
/// Почему: `codelab-agent serve --ws` принимает подключения сам — HTTP
/// upgrade и проверка Bearer-токена делаются до транспорта (R-12), а
/// транспорт только переносит кадры. Плохие кадры, как у stdio, получают
/// ответ `-32700` / `-32600` и не рвут соединение (ACP-4; design.md change
/// `add-codelab-agent-binary`, D2).
///
/// Для чего: порт `AcpTransport` для `AcpAgentServer.serve`; один текстовый
/// кадр — одно сообщение, бинарный кадр — `-32600`; закрытие сокета
/// клиентом закрывает [inbound] и переводит транспорт в `closed`.
///
/// Как использовать: после `WebSocketTransformer.upgrade(request)` —
/// `WebSocketServerAcpTransport(socket)`, затем `server.serve(transport)`.
final class WebSocketServerAcpTransport implements AcpTransport {
  WebSocketServerAcpTransport(this._socket);

  final WebSocket _socket;

  final _inbound = StreamController<JsonRpcMessage>();
  final _events = StreamController<AcpTransportEvent>.broadcast(sync: true);
  StreamSubscription<Object?>? _subscription;
  AcpTransportState _state = AcpTransportState.idle;

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => _state;

  @override
  Future<void> start() async {
    if (_state != AcpTransportState.idle) {
      return;
    }
    _setState(AcpTransportState.connected);
    _subscription = _socket.listen(
      _onFrame,
      onError: (Object error, StackTrace stack) => _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.receiveFailed,
          message: 'Failed to read the ACP WebSocket.',
          cause: error,
          stackTrace: stack,
        ),
      ),
      onDone: () => unawaited(_finish()),
    );
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (_state != AcpTransportState.connected) {
      throw const AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'WebSocket ACP server transport is not connected.',
      );
    }
    try {
      _socket.add(encodeJsonRpcMessage(message));
    } on Object catch (error, stack) {
      final failure = AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'Failed to send an ACP message over WebSocket.',
        cause: error,
        stackTrace: stack,
      );
      _fail(failure);
      throw failure;
    }
  }

  @override
  Future<void> close({Duration? timeout}) async {
    if (_state == AcpTransportState.closed) {
      return;
    }
    _setState(AcpTransportState.closing);
    await _socket.close().timeout(
      timeout ?? const Duration(seconds: 5),
      onTimeout: () {},
    );
    await _subscription?.cancel();
    _subscription = null;
    await _finish();
  }

  void _onFrame(Object? frame) {
    final result = switch (frame) {
      final String text => decodeServerFrame(text),
      _ => rejectBinaryFrame(),
    };
    switch (result) {
      case ServerFrameMessage(:final message):
        _inbound.add(message);
      case ServerFrameRejected(:final answer, :final reason):
        _events.add(
          AcpTransportEvent.diagnostic(
            message: 'Rejected an ACP frame: $reason',
            severity: AcpTransportDiagnosticSeverity.warning,
            source: 'websocket',
          ),
        );
        unawaited(send(answer).catchError((_) {}));
    }
  }

  Future<void> _finish() async {
    if (_state == AcpTransportState.closed) {
      return;
    }
    _setState(AcpTransportState.closed);
    await _inbound.close();
    await _events.close();
  }

  void _fail(AcpTransportException error) {
    if (_state == AcpTransportState.closed ||
        _state == AcpTransportState.failed) {
      return;
    }
    _setState(AcpTransportState.failed);
    _events.add(AcpTransportEvent.failure(error));
  }

  void _setState(AcpTransportState state) {
    _state = state;
    if (!_events.isClosed) {
      _events.add(AcpTransportEvent.stateChanged(state));
    }
  }
}
