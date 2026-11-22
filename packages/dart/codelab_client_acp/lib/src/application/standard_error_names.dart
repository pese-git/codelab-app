import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

/// Стандартные имена кодов JSON-RPC, известные пакету протокола (D3).
const _standardErrorNames = <int, String>{
  jsonRpcParseErrorCode: 'Parse error',
  jsonRpcInvalidRequestCode: 'Invalid Request',
  jsonRpcMethodNotFoundCode: 'Method not found',
  jsonRpcInvalidParamsCode: 'Invalid params',
  jsonRpcInternalErrorCode: 'Internal error',
  acpResourceNotFoundCode: 'Resource not found',
};

/// Стандартное имя кода ошибки (`Internal error`) или `null` у незнакомого.
///
/// Почему: при политике `metadataOnly` текст `error.message` агента не
/// хранится — он может содержать пути и фрагменты данных (D3); остаётся
/// только имя кода. Внутреннее правило пакета: им пользуются recorder (при
/// построении кадра) и `ProtocolFrame.withoutPayload`; хостам оно не нужно —
/// они зовут `withoutPayload`.
String? standardErrorName(int code) => _standardErrorNames[code];
