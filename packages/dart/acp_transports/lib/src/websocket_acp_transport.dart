import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'acp_transport.dart';

part 'websocket_acp_transport.freezed.dart';

@freezed
abstract class WebSocketAcpTransportConfig with _$WebSocketAcpTransportConfig {
  const WebSocketAcpTransportConfig._();

  const factory WebSocketAcpTransportConfig({
    required Uri uri,
    @Default({}) Map<String, String> headers,
    String? token,
    @Default('Authorization') String tokenHeader,
    @Default('Bearer') String tokenPrefix,
  }) = _WebSocketAcpTransportConfig;

  Map<String, String> get effectiveHeaders {
    final token = this.token;
    if (token == null || token.isEmpty) {
      return headers;
    }

    final value = tokenPrefix.isEmpty ? token : '$tokenPrefix $token';
    return {...headers, tokenHeader: value};
  }
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
      final channel = IOWebSocketChannel.connect(
        config.uri,
        headers: config.effectiveHeaders,
      );
      _channel = channel;
      _listenToChannel(channel);
      await channel.ready;
      _setState(AcpTransportState.connected);
    } on Object catch (error, stackTrace) {
      _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.startFailed,
          message: 'Failed to connect WebSocket ACP agent.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      rethrow;
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
