import 'dart:convert';

import 'json_rpc_message.dart';
import 'json_value.dart';
import 'protocol_error.dart';

JsonRpcMessage decodeJsonRpcMessage(String source) {
  final Object? decoded;

  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw JsonRpcProtocolException.invalidJson(error.message);
  }

  return jsonRpcMessageFromJson(
    requireJsonObject(decoded, path: 'JSON-RPC message'),
  );
}

String encodeJsonRpcMessage(JsonRpcMessage message) {
  return jsonEncode(message.toJson());
}
