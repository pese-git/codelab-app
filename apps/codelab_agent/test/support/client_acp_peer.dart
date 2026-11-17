import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';

/// Обработчик запроса агента к клиенту; результат уходит ответом на его id.
typedef ClientRequestHandler = FutureOr<Object?> Function(JsonRpcRequest);

/// Клиентская сторона ACP, которая обслуживает запросы агента (`fs/*`,
/// `terminal/*`, `session/request_permission`).
///
/// Почему отдельный класс, а не правка `AcpPeer`: `AcpPeer` намеренно не
/// отвечает на запросы агента (сценарии бинаря обходятся без них), а тестам
/// навыков нужно видеть, *какие* запросы агент отправил клиенту и чего не
/// отправил (`fs/read_text_file`, `terminal/create`; agent-skills
/// «Сопутствующие файлы и скрипты навыка», решение Q23).
///
/// Как использовать: `ClientAcpPeer(link.client)` после `start()` транспорта;
/// ответы на запросы агента задаёт [handlers] по имени метода (нет
/// обработчика — ошибка «метод не найден»); [requests] хранит все запросы
/// агента в порядке прихода, [call] ждёт ответа не дольше 10 секунд.
final class ClientAcpPeer {
  ClientAcpPeer(this._transport) {
    _subscription = _transport.inbound.listen(_onMessage);
  }

  final AcpTransport _transport;
  late final StreamSubscription<JsonRpcMessage> _subscription;
  final _pending = <int, Completer<JsonRpcResponse>>{};
  var _nextId = 0;

  /// Обработчики запросов агента клиенту по имени метода.
  final handlers = <String, ClientRequestHandler>{};

  /// Запросы агента клиенту в порядке прихода.
  final requests = <JsonRpcRequest>[];

  /// Уведомления агента в порядке прихода.
  final notifications = <JsonRpcNotification>[];

  /// Методы запросов агента в порядке прихода.
  List<String> get requestMethods => [for (final r in requests) r.method];

  /// Параметры запросов агента с этим [method].
  List<Map<String, Object?>> paramsOf(String method) => [
    for (final r in requests)
      if (r.method == method) r.params! as Map<String, Object?>,
  ];

  /// Содержимое `update` каждого `session/update` в порядке прихода.
  List<Map<String, Object?>> get updates => [
    for (final n in notifications)
      if (n.method == 'session/update' &&
          n.params is Map &&
          (n.params! as Map)['update'] is Map<String, Object?>)
        (n.params! as Map)['update']! as Map<String, Object?>,
  ];

  Future<Map<String, Object?>> call(String method, [Object? params]) async {
    final id = _nextId++;
    final completer = _pending[id] = Completer<JsonRpcResponse>();
    unawaited(
      _transport.send(
        JsonRpcMessage.request(
          id: JsonRpcId.integer(id),
          method: method,
          params: params,
        ),
      ),
    );
    final response = await completer.future.timeout(
      const Duration(seconds: 10),
    );
    if (response.error case final error?) {
      throw StateError('$method: ${error.code} ${error.message}');
    }
    return (response.result as Map<String, Object?>?) ?? const {};
  }

  /// `initialize` с `fs` и `terminal`, затем `session/new` в [cwd]; id сессии.
  Future<String> openSession(String cwd) async {
    await call('initialize', {
      'protocolVersion': 1,
      'clientCapabilities': {
        'fs': {'readTextFile': true, 'writeTextFile': true},
        'terminal': true,
      },
    });
    final result = await call('session/new', {
      'cwd': cwd,
      'mcpServers': <Object?>[],
    });
    return result['sessionId']! as String;
  }

  Future<String> prompt(String sessionId, String text) async {
    final result = await call('session/prompt', {
      'sessionId': sessionId,
      'prompt': [
        {'type': 'text', 'text': text},
      ],
    });
    return result['stopReason']! as String;
  }

  Future<void> dispose() => _subscription.cancel();

  void _onMessage(JsonRpcMessage message) {
    switch (message) {
      case JsonRpcResponse(id: JsonRpcIntId(:final value)):
        _pending.remove(value)?.complete(message);
      case JsonRpcNotification():
        notifications.add(message);
      case JsonRpcRequest():
        requests.add(message);
        unawaited(_answer(message));
      default:
    }
  }

  Future<void> _answer(JsonRpcRequest request) async {
    final handler = handlers[request.method];
    final JsonRpcMessage response;
    if (handler == null) {
      response = JsonRpcMessage.response(
        id: request.id,
        error: JsonRpcError(code: -32601, message: 'no handler'),
      );
    } else {
      response = JsonRpcMessage.response(
        id: request.id,
        result: await handler(request),
      );
    }
    try {
      await _transport.send(response);
    } on AcpTransportException {
      // Поздний ответ после закрытия пары: отправлять некому.
    }
  }
}
