import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';

import 'acp_client_application.dart';
import 'standard_error_names.dart';

/// Описание сбоя без текста агента — для журнала при `metadataOnly`.
///
/// Почему: `JsonRpcError.message` и `data` ответа агента — payload (пути,
/// фрагменты файлов, вывод команд), а `toString()` исключения, в которое они
/// вложены (`AcpClientApplicationException`), цитирует их целиком. Различать
/// «безопасные» шаблоны сообщений по строке нельзя, поэтому сообщение
/// исключения здесь не используется вовсе (design.md change
/// `redesign-protocol-pane`, D3, «Текст ошибки агента»).
///
/// Для чего: единое правило текста сбоя для `DiagnosticEntry` ядра,
/// `WorkspaceDiagnostic` kit и журнала app. Текст для пользователя
/// (`describeFailure`, `PromptTurn.failureMessage`) этим правилом НЕ
/// строится — он несёт текст агента при любой политике.
///
/// Как использовать: вызывать, когда `AcpClientApplication.protocolPayloads`
/// равна `metadataOnly`; при `full` в журнал идёт замаскированный текст.
/// Результат:
/// - `JsonRpcError` → `JSON-RPC error <code> (<имя>)`, у незнакомого кода без
///   скобок;
/// - исключение с `cause` типа `JsonRpcError` →
///   `<класс>: JSON-RPC error <code> (<имя>)`;
/// - `AcpTransportException` → `AcpTransportException(<code.name>)`;
/// - прочее — `runtimeType`.
String describeFailureMetadata(Object error) {
  if (error is JsonRpcError) {
    return _describeJsonRpcError(error);
  }
  if (error is AcpClientApplicationException) {
    final cause = error.cause;
    if (cause is JsonRpcError) {
      return '${error.runtimeType}: ${_describeJsonRpcError(cause)}';
    }
  }
  if (error is AcpTransportException) {
    return 'AcpTransportException(${error.code.name})';
  }
  return error.runtimeType.toString();
}

String _describeJsonRpcError(JsonRpcError error) {
  final name = standardErrorName(error.code);
  return name == null
      ? 'JSON-RPC error ${error.code}'
      : 'JSON-RPC error ${error.code} ($name)';
}

/// Код ответа-ошибки агента внутри [error] или `null` (D3).
///
/// Нужен записям журнала, которые при `metadataOnly` пишут `error_code`
/// вместо текста ошибки: код — метаданные, а не payload.
int? jsonRpcErrorCodeOf(Object error) => switch (error) {
  JsonRpcError(:final code) => code,
  AcpClientApplicationException(cause: JsonRpcError(:final code)) => code,
  _ => null,
};
