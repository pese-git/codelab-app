import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';

/// Клиентская сторона ACP для тестов бинаря: запросы с id по порядку и
/// накопленные уведомления.
///
/// Как использовать: `AcpPeer(link.client)` после `start()` транспорта;
/// [call] ждёт ответа и возвращает `result`, ошибка JSON-RPC —
/// [AcpCallFailed]. Запросы агента к клиенту здесь не обслуживаются:
/// сценарии тестов бинаря обходятся без `fs/*` и `terminal/*`.
final class AcpPeer {
  AcpPeer(this._transport) {
    _subscription = _transport.inbound.listen(_onMessage);
  }

  final AcpTransport _transport;
  late final StreamSubscription<JsonRpcMessage> _subscription;
  final _pending = <int, Completer<JsonRpcResponse>>{};
  var _nextId = 0;

  /// Уведомления агента в порядке прихода.
  final notifications = <JsonRpcNotification>[];

  /// Тексты `agent_message_chunk` сессии [sessionId], склеенные по порядку.
  String agentText(String sessionId) => [
    for (final n in notifications)
      if (n.params case {
        'sessionId': final String id,
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'text': final String text},
        },
      } when id == sessionId)
        text,
  ].join();

  Future<Map<String, Object?>> call(String method, [Object? params]) async {
    final response = await send(method, params);
    if (response.error case final error?) {
      throw AcpCallFailed(method, error);
    }
    return (response.result as Map<String, Object?>?) ?? const {};
  }

  Future<JsonRpcResponse> send(String method, [Object? params]) {
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
    return completer.future.timeout(const Duration(seconds: 10));
  }

  /// `initialize` с fs и terminal, затем `session/new` в [cwd]; id сессии.
  Future<String> openSession(String cwd) async {
    await call('initialize', {
      'protocolVersion': 1,
      'clientCapabilities': {
        'fs': {'readTextFile': true, 'writeTextFile': true},
        'terminal': true,
      },
    });
    return newSession(cwd);
  }

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

  Future<void> dispose() => _subscription.cancel();

  void _onMessage(JsonRpcMessage message) {
    switch (message) {
      case JsonRpcResponse(id: JsonRpcIntId(:final value)):
        _pending.remove(value)?.complete(message);
      case JsonRpcNotification():
        notifications.add(message);
      default:
    }
  }
}

final class AcpCallFailed implements Exception {
  const AcpCallFailed(this.method, this.error);

  final String method;
  final JsonRpcError error;

  @override
  String toString() => 'AcpCallFailed($method): ${error.code} ${error.message}';
}
