import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'outbound_queue.dart';
import 'pending_requests.dart';

/// Запросы агента к клиенту одного соединения (§13.9).
///
/// Почему отдельный объект: `AcpClientExecutionEnv` и `AcpPermissionGate`
/// одинаково ставят запрос в очередь, ждут ответ по id и прекращают
/// ожидание по таймауту или отмене; это поведение соединения, а не env или
/// gate.
///
/// Для чего: [request] отправляет запрос через [OutboundQueue] и ждёт ответ
/// в [PendingRequests]. Отказ — исключение [ClientCallFailure]: ошибка
/// JSON-RPC клиента, таймаут, отмена или разрыв соединения.
///
/// Как использовать: соединение создаёт один экземпляр на транспорт;
/// вызывающий код ловит [ClientCallFailure] и переводит её в свой результат
/// (`FileError`, `ExecError`, решение разрешения).
final class ClientRequests {
  ClientRequests({
    required OutboundQueue outbound,
    required PendingRequests pending,
    required Clock clock,
  }) : _outbound = outbound,
       _pending = pending,
       _clock = clock;

  final OutboundQueue _outbound;
  final PendingRequests _pending;
  final Clock _clock;

  /// Отправляет запрос [method] с id `<prefix>-<n>` и возвращает `result`
  /// ответа как JSON. [timeout] — `null` без собственного таймаута;
  /// [cancel] прекращает ожидание. Уже отменённый [cancel] — исключение без
  /// отправки кадра.
  Future<Object?> request<P extends Object>(
    acp.AcpMethodDefinition<P, Object> method,
    P params, {
    required String prefix,
    Duration? timeout,
    CancelToken? cancel,
  }) async {
    if (cancel != null && cancel.isCancelled) {
      throw const ClientCallCancelled();
    }
    if (_pending.isClosed) {
      throw const ClientDisconnected();
    }
    final id = _pending.nextId(prefix);
    final answer = _pending.expect(id);
    unawaited(
      _outbound.enqueue(
        acp.encodeAcpRequest(id: id, method: method.method, params: params),
      ),
    );
    final timer = timeout == null
        ? null
        : _clock.timer(
            timeout,
            () => _pending.fail(id, ClientTimedOut(method.method, timeout)),
          );
    // Ожидание прекращается, поздний ответ клиента станет «неизвестным id»
    // (PERM-4: решение принимается один раз).
    if (cancel != null) {
      unawaited(
        cancel.onCancel.then(
          (_) => _pending.fail(id, const ClientCallCancelled()),
        ),
      );
    }
    try {
      final response = await answer;
      if (response.error case final error?) {
        throw ClientRejected(error);
      }
      return response.result;
    } finally {
      timer?.cancel();
    }
  }
}

/// Сессия, от имени которой env и gate обращаются к клиенту.
///
/// Почему изменяемый: env и gate создаются до сессии — их передают в
/// `SessionSpec`, а id сессии появляется в ответе `createSession`; после
/// переподключения (§13.5, шаг 3b) запросы идут через новое соединение.
///
/// Как использовать: соединение создаёт связь в `session/new` с
/// [requests] и [capabilities] своего `initialize`, а [sessionId] ставит
/// сразу после создания сессии — до первого хода.
final class ClientLink {
  ClientLink({required this.requests, required this.capabilities});

  ClientRequests requests;
  acp.ClientCapabilities capabilities;
  late String sessionId;
}

/// Почему запрос агента не получил результата (§13.9).
sealed class ClientCallFailure implements Exception {
  const ClientCallFailure();
}

/// Клиент ответил ошибкой JSON-RPC.
final class ClientRejected extends ClientCallFailure {
  const ClientRejected(this.error);

  final acp.JsonRpcError error;

  @override
  String toString() => 'ClientRejected(${error.code}: ${error.message})';
}

/// Ответа нет дольше таймаута §13.9.
final class ClientTimedOut extends ClientCallFailure {
  const ClientTimedOut(this.method, this.after);

  final String method;
  final Duration after;

  @override
  String toString() =>
      'client did not answer $method in ${after.inSeconds} s (timed out)';
}

/// Ход отменён: ожидание прекращено, запрос клиенту не отзывается.
final class ClientCallCancelled extends ClientCallFailure {
  const ClientCallCancelled();

  @override
  String toString() => 'aborted';
}

/// Соединение закрыто до ответа.
final class ClientDisconnected extends ClientCallFailure {
  const ClientDisconnected();

  @override
  String toString() => 'client connection lost';
}
