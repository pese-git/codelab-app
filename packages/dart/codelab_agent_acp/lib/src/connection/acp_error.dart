import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

/// Отказ обработчика запроса с кодом JSON-RPC (§13.10, «Коды ошибок»).
///
/// Почему исключение, а не значение: обработчик метода — обычный
/// асинхронный код, и ранний выход из любой глубины проще бросить, чем
/// протаскивать через возвраты. Маршрутизатор ловит его и ставит в очередь
/// ответ с этим кодом; всё остальное, что бросил обработчик, — `-32603`.
///
/// Как использовать: `throw AcpRequestError.invalidParams('cwd must be an
/// absolute path')`. Причину уточняет [data] (`{"codelab": {"reason": …}}`),
/// своих кодов в диапазоне `-32000…-32099` нет.
final class AcpRequestError implements Exception {
  const AcpRequestError(this.code, this.message, {this.data});

  /// `-32600`: повторный `initialize`, `session/*` до `initialize`.
  const AcpRequestError.invalidRequest(String message)
    : this(jsonRpcInvalidRequestCode, message);

  /// `-32601`: метод не реализован.
  const AcpRequestError.methodNotFound(String message)
    : this(jsonRpcMethodNotFoundCode, message);

  /// `-32602`: параметры не проходят проверку.
  const AcpRequestError.invalidParams(String message, {Object? data})
    : this(jsonRpcInvalidParamsCode, message, data: data);

  /// `-32002`: неизвестный `sessionId`.
  const AcpRequestError.notFound(String message)
    : this(acpResourceNotFoundCode, message);

  final int code;
  final String message;
  final Object? data;

  JsonRpcError toJsonRpcError() =>
      JsonRpcError(code: code, message: message, data: data);

  @override
  String toString() => 'AcpRequestError($code): $message';
}
