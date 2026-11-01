import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';

/// Обработчик запроса агента к клиенту; результат уходит ответом на его id.
typedef AgentRequestHandler = FutureOr<Object?> Function(JsonRpcRequest);

/// ACP-клиент для тестов встроенного агента на клиентском конце пары.
///
/// Почему свой, а не `ClientWorkspace`: пакет `codelab_embedded` не зависит от
/// `codelab_client_*` (design.md change `add-embedded-agent-mode`, D1, D3), а
/// тесту нужен только кадровый уровень — что агент отправил клиенту и чего не
/// отправил (`fs/*`, `terminal/*`, D4).
///
/// Как использовать: `TestAcpClient(agent.clientTransport)`, затем `start()`;
/// [call] ждёт ответа на запрос, а запросы агента клиенту обслуживают
/// [handlers] по имени метода (без обработчика запрос получает ошибку
/// «метод не найден»). Все входящие кадры лежат в [received].
final class TestAcpClient {
  TestAcpClient(this._transport) {
    _subscription = _transport.inbound.listen(_onMessage);
  }

  final AcpTransport _transport;
  late final StreamSubscription<JsonRpcMessage> _subscription;
  final _pending = <JsonRpcId, Completer<JsonRpcResponse>>{};
  var _nextId = 0;

  /// Обработчики запросов агента по имени метода.
  final handlers = <String, AgentRequestHandler>{};

  /// Сколько ответов клиента не доставлено из-за закрытой пары (поздний
  /// ответ после выгрузки агента, D6); тест проверяет ожидаемое число.
  var droppedResponses = 0;

  /// Все кадры агента в порядке прихода.
  final received = <JsonRpcMessage>[];

  Future<void> start() => _transport.start();

  /// Запросы агента клиенту: методы в порядке прихода.
  List<String> get agentRequests => [
    for (final m in received)
      if (m is JsonRpcRequest) m.method,
  ];

  /// Содержимое `update` каждого `session/update` в порядке прихода.
  List<Map<String, Object?>> get updates {
    final result = <Map<String, Object?>>[];
    for (final m in received) {
      if (m is JsonRpcNotification && m.method == 'session/update') {
        final params = m.params;
        if (params is Map && params['update'] is Map<String, Object?>) {
          result.add(params['update']! as Map<String, Object?>);
        }
      }
    }
    return result;
  }

  /// Тексты `agent_message_chunk`, склеенные по порядку.
  String get agentText => [
    for (final update in updates)
      if (update case {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'text': final String text},
      })
        text,
  ].join();

  /// Последнее обновление инструмента с этим `toolCallId`.
  Map<String, Object?> lastUpdateOf(String toolCallId) => updates.lastWhere(
    (u) => u['toolCallId'] == toolCallId,
    orElse: () => throw StateError('нет обновлений $toolCallId'),
  );

  Future<Map<String, Object?>> call(String method, [Object? params]) async {
    final id = JsonRpcId.integer(_nextId++);
    final completer = _pending[id] = Completer<JsonRpcResponse>();
    await _transport.send(
      JsonRpcMessage.request(id: id, method: method, params: params),
    );
    final response = await completer.future.timeout(
      const Duration(seconds: 10),
    );
    if (response.error case final error?) {
      throw StateError('$method: ${error.code} ${error.message}');
    }
    return (response.result as Map<String, Object?>?) ?? const {};
  }

  /// `initialize` с `fs` и `terminal`: клиент разрешает агенту эти методы, но
  /// встроенный агент ими не пользуется (D4). Возвращает ответ.
  Future<Map<String, Object?>> initialize() => call('initialize', {
    'protocolVersion': 1,
    'clientCapabilities': {
      'fs': {'readTextFile': true, 'writeTextFile': true},
      'terminal': true,
    },
  });

  Future<String> newSession(String cwd) async {
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

  Future<void> close() async {
    await _subscription.cancel();
  }

  void _onMessage(JsonRpcMessage message) {
    received.add(message);
    switch (message) {
      case JsonRpcResponse():
        _pending.remove(message.id)?.complete(message);
      case JsonRpcRequest():
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
      // Поздний ответ после закрытия пары: агент уже ушёл, отправлять некому.
      // Это ожидаемо для клиента (design.md change `add-embedded-agent-mode`,
      // D6) и не должно становиться необработанной ошибкой теста.
      droppedResponses++;
    }
  }
}
