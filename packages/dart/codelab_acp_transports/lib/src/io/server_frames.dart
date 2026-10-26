import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

/// Итог разбора одного сырого кадра серверным транспортом.
///
/// Почему отдельный тип: клиентский разбор (`decodeJsonRpcMessage`) бросает
/// исключение, и клиентский транспорт переводит соединение в `failed`. Агент
/// так не может: плохой кадр клиента не должен рвать соединение и ходы
/// (ACP-4), а сервер получает только разобранные сообщения (D12 change
/// `add-dart-agent-acp-server`). Поэтому транспорт сам отвечает ошибкой
/// JSON-RPC и сообщает о кадре диагностикой.
sealed class ServerFrame {
  const ServerFrame();
}

/// Корректное сообщение для `inbound`.
final class ServerFrameMessage extends ServerFrame {
  const ServerFrameMessage(this.message);

  final JsonRpcMessage message;
}

/// Плохой кадр: [answer] уходит отправителю, [reason] — в диагностику.
final class ServerFrameRejected extends ServerFrame {
  const ServerFrameRejected(this.answer, this.reason);

  final JsonRpcResponse answer;
  final String reason;
}

/// Разбирает текст одного кадра по правилам документа ядра §13.10:
/// неразбираемый JSON — `-32700` с `id: null`; JSON не JSON-RPC 2.0 —
/// `-32600` с `id` кадра, если он читается, иначе `null`.
ServerFrame decodeServerFrame(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    return _rejected(
      const JsonRpcId.nullValue(),
      jsonRpcParseErrorCode,
      'Parse error',
      'unparsable JSON: ${error.message}',
    );
  }
  if (decoded is! Map<String, Object?>) {
    return _rejected(
      const JsonRpcId.nullValue(),
      jsonRpcInvalidRequestCode,
      'Invalid Request',
      'a JSON-RPC message must be an object',
    );
  }
  try {
    return ServerFrameMessage(jsonRpcMessageFromJson(decoded));
  } on JsonRpcProtocolException catch (error) {
    return _rejected(
      _readableId(decoded['id']),
      jsonRpcInvalidRequestCode,
      'Invalid Request',
      error.message,
    );
  }
}

/// Ответ на кадр, который не текст (бинарный кадр WebSocket).
ServerFrameRejected rejectBinaryFrame() => _rejected(
  const JsonRpcId.nullValue(),
  jsonRpcInvalidRequestCode,
  'Invalid Request',
  'binary frames are not supported',
);

ServerFrameRejected _rejected(
  JsonRpcId id,
  int code,
  String message,
  String reason,
) => ServerFrameRejected(
  JsonRpcResponse(
    id: id,
    // Причина — в тексте: поле `data` без `codelab` было бы расширением
    // ACP, не введённым OpenSpec change (ACP-2).
    error: JsonRpcError(code: code, message: '$message: $reason'),
  ),
  reason,
);

JsonRpcId _readableId(Object? raw) => switch (raw) {
  final String value => JsonRpcId.string(value),
  final int value => JsonRpcId.integer(value),
  _ => const JsonRpcId.nullValue(),
};
