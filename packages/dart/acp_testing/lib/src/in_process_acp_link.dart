import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';

/// Пара соединённых транспортов в памяти: отправленное в один конец приходит
/// в `inbound` другого (`agent-core-architecture` §13.11).
///
/// Почему здесь, а не в `acp_transports`: это тестовая копия этапа 4 для
/// contract test клиента и агента и агентского прогона фикстур
/// (design.md change `add-dart-agent-acp-server`, D9). Окончательная версия
/// для встроенного режима переезжает в `acp_transports` на этапе 7, и эта
/// копия удаляется в том же PR.
///
/// Как использовать: `client` отдаётся клиенту (`AcpClientApplication`
/// или тестовому клиенту), `agent` — `AcpAgentServer.serve`. Оба конца
/// запускаются `start()`; сообщение, пришедшее до `start()` получателя,
/// буферизуется.
final class InProcessAcpLink {
  factory InProcessAcpLink({bool copyMessages = true}) {
    final client = InProcessAcpTransport._('client', copyMessages);
    final agent = InProcessAcpTransport._('agent', copyMessages);
    client._peer = agent;
    agent._peer = client;
    return InProcessAcpLink._(client, agent);
  }

  InProcessAcpLink._(this.client, this.agent);

  final InProcessAcpTransport client;
  final InProcessAcpTransport agent;
}

/// Один конец [InProcessAcpLink].
///
/// Доставка асинхронная (следующая микрозадача), по одному сообщению и в
/// порядке `send`: семантика та же, что у stdio-кадров, и обработчики
/// получателя не вызываются изнутри `send` отправителя. При
/// `copyMessages` (по умолчанию) каждое сообщение копируется как дерево
/// JSON, поэтому не-JSON значение даёт `sendFailed`, как на проводе.
final class InProcessAcpTransport implements AcpTransport {
  InProcessAcpTransport._(this._side, this._copy);

  final String _side;
  final bool _copy;
  late final InProcessAcpTransport _peer;

  final _inbound = StreamController<JsonRpcMessage>.broadcast();
  final _events = StreamController<AcpTransportEvent>.broadcast();

  /// Сообщения, пришедшие до `start()`: агент может ответить раньше, чем
  /// клиент запустил свой конец.
  final _beforeStart = <JsonRpcMessage>[];
  var _state = AcpTransportState.idle;

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => _state;

  bool get _isDown => const {
    AcpTransportState.closing,
    AcpTransportState.closed,
    AcpTransportState.failed,
  }.contains(_state);

  @override
  Future<void> start() async {
    if (_state == AcpTransportState.connected) {
      return;
    }
    if (_isDown) {
      throw _error(AcpTransportErrorCode.closed, 'is closed');
    }
    _setState(AcpTransportState.connecting);
    _setState(AcpTransportState.connected);
    final buffered = [..._beforeStart];
    _beforeStart.clear();
    for (final message in buffered) {
      scheduleMicrotask(() => _inbound.add(message));
    }
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (_state != AcpTransportState.connected) {
      throw _error(AcpTransportErrorCode.sendFailed, 'is not connected');
    }
    final JsonRpcMessage copy;
    try {
      copy = _copy ? _copyMessage(message) : message;
    } on ArgumentError catch (e) {
      throw _error(
        AcpTransportErrorCode.sendFailed,
        'got a non-JSON value: ${e.message}',
      );
    }
    scheduleMicrotask(() => _peer._deliver(copy));
  }

  void _deliver(JsonRpcMessage message) {
    if (_state == AcpTransportState.connected) {
      _inbound.add(message);
    } else if (!_isDown) {
      _beforeStart.add(message);
    } else if (!_events.isClosed) {
      _events.add(
        const AcpTransportEvent.diagnostic(
          message: 'Dropped in-process message after close.',
          severity: AcpTransportDiagnosticSeverity.warning,
          source: 'in_process',
        ),
      );
    }
  }

  @override
  Future<void> close({Duration? timeout}) async {
    if (_state == AcpTransportState.closed ||
        _state == AcpTransportState.closing) {
      return;
    }
    _setState(AcpTransportState.closing);
    _setState(AcpTransportState.closed);
    await _events.close();
    await _inbound.close();
    _peer._onPeerClosed();
  }

  void _onPeerClosed() {
    if (_isDown) {
      return;
    }
    _events.add(
      AcpTransportEvent.failure(
        _error(
          AcpTransportErrorCode.disconnected,
          'peer closed the connection',
        ),
      ),
    );
    _setState(AcpTransportState.failed);
    // Как EOF у stdio: поток входящих закрывается, сервер видит отсоединение.
    unawaited(_inbound.close());
  }

  void _setState(AcpTransportState next) {
    _state = next;
    if (!_events.isClosed) {
      _events.add(AcpTransportEvent.stateChanged(next));
    }
  }

  AcpTransportException _error(AcpTransportErrorCode code, String text) =>
      AcpTransportException(
        code: code,
        message: 'In-process $_side transport $text.',
      );
}

/// Глубокая копия JSON-дерева без строкового кодирования: стороны не делят
/// изменяемые `Map`/`List`, а не-JSON значения ловятся сразу, как на
/// проводе.
JsonRpcMessage _copyMessage(JsonRpcMessage m) => switch (m) {
  JsonRpcRequest(:final id, :final method, :final params) =>
    JsonRpcMessage.request(id: id, method: method, params: _copyJson(params)),
  JsonRpcNotification(:final method, :final params) =>
    JsonRpcMessage.notification(method: method, params: _copyJson(params)),
  JsonRpcResponse(:final id, :final result, :final error) =>
    JsonRpcMessage.response(id: id, result: _copyJson(result), error: error),
};

Object? _copyJson(Object? v) => switch (v) {
  null || bool() || num() || String() => v,
  List() => List<Object?>.unmodifiable(v.map(_copyJson)),
  Map() => Map<String, Object?>.unmodifiable({
    for (final MapEntry(:key, :value) in v.entries)
      (key is String
              ? key
              : throw ArgumentError.value(key, 'key', 'must be a String')):
          _copyJson(value),
  }),
  _ => throw ArgumentError.value(v, 'value', 'not JSON-compatible'),
};
