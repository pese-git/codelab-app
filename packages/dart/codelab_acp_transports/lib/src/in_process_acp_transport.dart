import 'dart:async';
import 'dart:collection';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import 'acp_transport.dart';

/// Пара соединённых транспортов в памяти: отправленное в один конец приходит
/// в `inbound` другого объектом [JsonRpcMessage], без кодирования в текст
/// (`agent-core-architecture` §13.11; design.md change
/// `add-in-process-acp-transport`, D1–D4).
///
/// Почему в основном бареле: пара нужна встроенному режиму агента (этап 7) и
/// web, где isolate нет, а также тестам клиента и агента. Она не зависит от
/// стороны соединения и не использует `dart:io`, поэтому живёт в общем слое
/// транспортов и остаётся web-безопасной (D1, D6).
///
/// Для чего: оба конца реализуют порт [AcpTransport], поэтому
/// `AcpClientApplication` и `AcpAgentServer` не отличают их от stdio или
/// WebSocket.
///
/// Как использовать: `client` отдаётся клиенту, `agent` — `AcpAgentServer`;
/// каждая сторона сама вызывает `start()` своего конца и в конце `close()`.
/// Сообщение, пришедшее на не запущенный конец или на конец, у `inbound`
/// которого ещё не было ни одного подписчика, буферизуется до первой
/// подписки (D4, п. 2); после неё без подписчиков сообщение выбрасывается,
/// как у broadcast. Публичного конструктора у конца нет: конец без пары не
/// существует (D7).
final class InProcessAcpLink {
  /// Создаёт пару и связывает концы друг с другом (D9: без параметров,
  /// сообщения копируются всегда).
  factory InProcessAcpLink() {
    final client = InProcessAcpTransport._('client');
    final agent = InProcessAcpTransport._('agent');
    client._peer = agent;
    agent._peer = client;
    return InProcessAcpLink._(client, agent);
  }

  InProcessAcpLink._(this.client, this.agent);

  /// Конец клиента: его `send` попадает в `inbound` конца [agent].
  final InProcessAcpTransport client;

  /// Конец агента: его `send` попадает в `inbound` конца [client].
  final InProcessAcpTransport agent;
}

/// Один конец [InProcessAcpLink]; создаётся только вместе с парой.
///
/// Почему: семантика должна совпадать с проводными транспортами, чтобы
/// встроенный режим не прятал ошибки, видимые на проводе: доставка
/// асинхронная и упорядоченная, не-JSON значение даёт `sendFailed`, закрытие
/// одного конца отсоединяет второй (D3–D4).
///
/// Для чего: единственная реализация [AcpTransport] в памяти; публичных
/// членов сверх порта нет (D7), вызывающий держит конец как [AcpTransport].
///
/// Как использовать: см. [InProcessAcpLink]. Доставка идёт в следующей
/// микрозадаче, по одному сообщению и в порядке `send` (очередь микрозадач
/// FIFO), поэтому обработчики получателя не вызываются изнутри `send`
/// отправителя. `send` копирует дерево JSON на стороне отправителя (D3),
/// поэтому ошибка копирования достаётся тому, кто её сделал.
final class InProcessAcpTransport implements AcpTransport {
  InProcessAcpTransport._(this._side) {
    _inbound = StreamController<JsonRpcMessage>.broadcast(onListen: _onListen);
  }

  final String _side;
  late final InProcessAcpTransport _peer;
  late final StreamController<JsonRpcMessage> _inbound;
  final _events = StreamController<AcpTransportEvent>.broadcast();

  /// Сообщения, которые некому выдать: конец ещё не запущен или у `inbound`
  /// ещё не было подписчика (D4, п. 2). Агент может ответить раньше, чем
  /// клиент запустил конец, а `AcpAgentServer.serve` подписывается на
  /// `inbound` только после `await start()`.
  final _pending = Queue<JsonRpcMessage>();

  /// Была ли хоть одна подписка на `inbound`. Буфер нужен только до неё:
  /// после первой подписки поведение как у broadcast, без подписчиков
  /// сообщение выбрасывается, а не копится без границы (D4, п. 2).
  var _hadListener = false;
  var _state = AcpTransportState.idle;

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => _state;

  bool get _isDown =>
      _state == AcpTransportState.closing ||
      _state == AcpTransportState.closed ||
      _state == AcpTransportState.failed;

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
    scheduleMicrotask(_drain);
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (_state != AcpTransportState.connected) {
      throw _error(AcpTransportErrorCode.sendFailed, 'is not connected');
    }
    final JsonRpcMessage copy;
    try {
      copy = _copyMessage(message);
    } on Object catch (_, st) {
      // Любая ошибка копирования (не-JSON значение, цикл со
      // StackOverflowError, Map с падающим итератором) даёт один исход.
      // Ни значение, ни исходная ошибка в исключение не попадают: в params
      // бывают пути и содержимое файлов (AGENTS.md §10, §16; D3, п. 5).
      Error.throwWithStackTrace(
        _error(
          AcpTransportErrorCode.sendFailed,
          'got a value that cannot be copied as JSON',
        ),
        st,
      );
    }
    scheduleMicrotask(() => _peer._deliver(copy));
  }

  void _deliver(JsonRpcMessage message) {
    // Доставка была запланирована до закрытия получателя: сообщение молча
    // выбрасывается, отправитель исключения не получает (D4, п. 7).
    if (_isDown) {
      return;
    }
    _pending.add(message);
    _drain();
  }

  /// Первый подписчик `inbound` (или новый после отписки последнего).
  ///
  /// Выдача откладывается в микрозадачу, чтобы `listen` не вызывал
  /// обработчик синхронно (D4, п. 1–2).
  void _onListen() {
    _hadListener = true;
    scheduleMicrotask(_drain);
  }

  /// Выдаёт буфер по порядку, пока конец в `connected` и есть подписчик.
  ///
  /// Запущенный конец, у которого подписка уже была, но подписчиков нет,
  /// ничего не копит: остаток буфера выбрасывается (D4, п. 2).
  void _drain() {
    if (_state == AcpTransportState.connected &&
        _hadListener &&
        !_inbound.hasListener) {
      _pending.clear();
      return;
    }
    while (_state == AcpTransportState.connected &&
        _inbound.hasListener &&
        _pending.isNotEmpty) {
      _inbound.add(_pending.removeFirst());
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
    _pending.clear();
    // Уведомление второго конца идёт в микрозадаче после уже запланированных
    // доставок: сообщения до close() приходят раньше done (D4, п. 6).
    scheduleMicrotask(_peer._onPeerClosed);
    await _events.close();
    await _inbound.close();
  }

  void _onPeerClosed() {
    if (_isDown) {
      return;
    }
    _drain();
    if (_pending.isNotEmpty) {
      // Выдать буфер уже некому (подписки не было или конец не запущен):
      // сообщения выбрасываются, но потеря должна быть видна в
      // диагностике. Содержимое не пишется: в нём бывают пути и данные
      // файлов (AGENTS.md §10, §16; D4, п. 6).
      _events.add(
        AcpTransportEvent.diagnostic(
          message:
              'Dropped ${_pending.length} undelivered in-process message(s) '
              'because the peer closed.',
          severity: AcpTransportDiagnosticSeverity.warning,
          source: 'in_process',
        ),
      );
      _pending.clear();
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

/// Глубокая копия сообщения без строкового кодирования: стороны не делят
/// изменяемые `Map`/`List`, а не-JSON значения ловятся сразу, как на проводе
/// (D3, п. 1). Любая ошибка копирования обрабатывается в `send`.
JsonRpcMessage _copyMessage(JsonRpcMessage m) => switch (m) {
  JsonRpcRequest(:final id, :final method, :final params) =>
    JsonRpcMessage.request(id: id, method: method, params: _copyJson(params)),
  JsonRpcNotification(:final method, :final params) =>
    JsonRpcMessage.notification(method: method, params: _copyJson(params)),
  JsonRpcResponse(:final id, :final result, :final error) =>
    JsonRpcMessage.response(
      id: id,
      result: _copyJson(result),
      error: error == null
          ? null
          : JsonRpcError(
              code: error.code,
              message: error.message,
              data: _copyJson(error.data),
            ),
    ),
};

/// Копирует дерево JSON в неизменяемые `List`/`Map`; всё, что не JSON,
/// отвергает `ArgumentError` (D3, п. 2–4).
///
/// Число проверяется через `num` и `isFinite`, а не через `int`/`double`: на
/// web `double.infinity is int` может быть истинным, а `NaN` и `±Infinity`
/// не кодируются `jsonEncode` (D3, п. 3).
Object? _copyJson(Object? v) => switch (v) {
  null || bool() || String() => v,
  num() when v.isFinite => v,
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
