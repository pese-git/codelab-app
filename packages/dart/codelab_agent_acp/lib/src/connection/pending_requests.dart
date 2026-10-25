import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart';

/// Исходящие запросы агента к клиенту и ожидание ответов (§13.1,
/// `PendingRequests`; §13.9).
///
/// Почему свой реестр: ответ клиента приходит в общий поток входящих кадров
/// соединения вперемешку с его запросами, и только по id можно отдать его
/// тому, кто ждёт: `AcpClientExecutionEnv`, `AcpPermissionGate`.
///
/// Как использовать: [nextId] выдаёт id с префиксом `perm`, `fs` или
/// `term` и счётчиком на соединение — строки не пересекаются с числовыми id
/// клиента. [expect] регистрирует ожидание, [complete] отдаёт пришедший
/// ответ; `false` — ответа никто не ждёт (поздний или чужой).
final class PendingRequests {
  final _waiting = <JsonRpcId, Completer<JsonRpcResponse>>{};
  var _counter = 0;

  JsonRpcId nextId(String prefix) => JsonRpcId.string('$prefix-${++_counter}');

  /// Ожидание ответа на запрос [id]; завершается ответом клиента или
  /// ошибкой из [fail].
  Future<JsonRpcResponse> expect(JsonRpcId id) {
    final completer = Completer<JsonRpcResponse>();
    _waiting[id] = completer;
    return completer.future;
  }

  bool complete(JsonRpcResponse response) {
    final completer = _waiting.remove(response.id);
    if (completer == null) {
      return false;
    }
    completer.complete(response);
    return true;
  }

  /// Ожидание [id] прекращается ошибкой (таймаут, отмена); поздний ответ
  /// клиента после этого — «неизвестный id».
  void fail(JsonRpcId id, Object error) {
    _waiting.remove(id)?.completeError(error);
  }

  /// Разрыв соединения: все ожидания завершаются ошибкой.
  void failAll(Object error) {
    final all = [..._waiting.values];
    _waiting.clear();
    for (final completer in all) {
      completer.completeError(error);
    }
  }
}
