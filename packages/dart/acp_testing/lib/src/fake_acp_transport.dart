import 'dart:async';

import 'package:acp_transports/acp_transports.dart';

final class FakeAcpTransport implements AcpTransport {
  FakeAcpTransport({AcpTransportState initialState = AcpTransportState.idle})
    : _state = initialState;

  final _inboundController = StreamController<JsonRpcMessage>.broadcast(
    sync: true,
  );
  final _eventController = StreamController<AcpTransportEvent>.broadcast(
    sync: true,
  );
  final _sentController = StreamController<JsonRpcMessage>.broadcast(
    sync: true,
  );
  final _sentMessages = <JsonRpcMessage>[];

  AcpTransportState _state;
  var _isClosed = false;

  @override
  Stream<JsonRpcMessage> get inbound => _inboundController.stream;

  @override
  Stream<AcpTransportEvent> get events => _eventController.stream;

  Stream<JsonRpcMessage> get sent => _sentController.stream;

  List<JsonRpcMessage> get sentMessages => List.unmodifiable(_sentMessages);

  @override
  AcpTransportState get state => _state;

  @override
  Future<void> start() async {
    _ensureUsable();

    if (_state == AcpTransportState.connected ||
        _state == AcpTransportState.connecting) {
      return;
    }

    _setState(AcpTransportState.connecting);
    _setState(AcpTransportState.connected);
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    _ensureUsable();

    if (_state != AcpTransportState.connected) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'Fake ACP transport is not connected.',
      );
    }

    _sentMessages.add(message);
    _sentController.add(message);
  }

  void emitInbound(JsonRpcMessage message) {
    _ensureUsable();
    _inboundController.add(message);
  }

  void emitDiagnostic({
    required String message,
    AcpTransportDiagnosticSeverity severity =
        AcpTransportDiagnosticSeverity.info,
    String? source,
  }) {
    emitEvent(
      AcpTransportEvent.diagnostic(
        message: message,
        severity: severity,
        source: source,
      ),
    );
  }

  void emitEvent(AcpTransportEvent event) {
    _ensureUsable();
    _eventController.add(event);
  }

  void fail(AcpTransportException error) {
    if (_isClosed) {
      return;
    }

    _setState(AcpTransportState.failed);
    _eventController.add(AcpTransportEvent.failure(error));
  }

  List<JsonRpcMessage> drainSentMessages() {
    final messages = List<JsonRpcMessage>.unmodifiable(_sentMessages);
    _sentMessages.clear();
    return messages;
  }

  @override
  Future<void> close({Duration? timeout}) async {
    if (_isClosed) {
      return;
    }

    _setState(AcpTransportState.closing);
    _isClosed = true;
    _setState(AcpTransportState.closed);
    await _inboundController.close();
    await _eventController.close();
    await _sentController.close();
  }

  void _setState(AcpTransportState state) {
    _state = state;
    _eventController.add(AcpTransportEvent.stateChanged(state));
  }

  void _ensureUsable() {
    if (_isClosed || _state == AcpTransportState.closed) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'Fake ACP transport is closed.',
      );
    }

    if (_state == AcpTransportState.failed) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'Fake ACP transport has failed.',
      );
    }
  }
}
