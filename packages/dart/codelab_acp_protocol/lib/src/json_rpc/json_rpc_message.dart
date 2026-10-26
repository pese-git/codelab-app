import 'package:freezed_annotation/freezed_annotation.dart';

import 'json_rpc_error.dart';
import 'json_rpc_id.dart';
import 'json_value.dart';
import 'protocol_error.dart';

part 'json_rpc_message.freezed.dart';

const jsonRpcVersion = '2.0';

@freezed
sealed class JsonRpcMessage with _$JsonRpcMessage {
  const JsonRpcMessage._();

  const factory JsonRpcMessage.request({
    required JsonRpcId id,
    required String method,
    Object? params,
  }) = JsonRpcRequest;

  const factory JsonRpcMessage.notification({
    required String method,
    Object? params,
  }) = JsonRpcNotification;

  const factory JsonRpcMessage.response({
    required JsonRpcId id,
    Object? result,
    JsonRpcError? error,
  }) = JsonRpcResponse;
}

extension JsonRpcMessageWire on JsonRpcMessage {
  JsonObject toJson() {
    return switch (this) {
      JsonRpcRequest(:final id, :final method, :final params) => {
        'jsonrpc': jsonRpcVersion,
        'id': id.toJsonValue(),
        'method': method,
        'params': ?params,
      },
      JsonRpcNotification(:final method, :final params) => {
        'jsonrpc': jsonRpcVersion,
        'method': method,
        'params': ?params,
      },
      JsonRpcResponse(:final id, :final result, :final error) => {
        'jsonrpc': jsonRpcVersion,
        'id': id.toJsonValue(),
        if (error case final JsonRpcError error) 'error': error.toJson(),
        if (error == null) 'result': result,
      },
    };
  }
}

extension JsonRpcResponseState on JsonRpcResponse {
  bool get isError => error != null;
}

JsonRpcMessage jsonRpcMessageFromJson(JsonObject source) {
  _requireJsonRpcVersion(source);

  final hasMethod = source.containsKey('method');
  final hasId = source.containsKey('id');
  final hasResult = source.containsKey('result');
  final hasError = source.containsKey('error');

  if (hasMethod) {
    final method = source['method'];
    if (method is! String || method.isEmpty) {
      throw JsonRpcProtocolException.invalidShape(
        'method must be a non-empty string.',
      );
    }

    final params = optionalJsonRpcParams(source);
    if (hasId) {
      return JsonRpcMessage.request(
        id: requireJsonRpcId(source),
        method: method,
        params: params,
      );
    }

    return JsonRpcMessage.notification(method: method, params: params);
  }

  if (!hasId) {
    throw JsonRpcProtocolException.invalidShape(
      'response messages must include id.',
    );
  }

  if (hasResult == hasError) {
    throw JsonRpcProtocolException.invalidShape(
      'response messages must include exactly one of result or error.',
    );
  }

  final id = requireJsonRpcId(source);
  if (hasError) {
    return JsonRpcMessage.response(
      id: id,
      error: JsonRpcError.fromJson(source['error']),
    );
  }

  return JsonRpcMessage.response(id: id, result: optionalJsonRpcResult(source));
}

void _requireJsonRpcVersion(JsonObject source) {
  if (source['jsonrpc'] != jsonRpcVersion) {
    throw JsonRpcProtocolException.invalidShape(
      'jsonrpc must equal "$jsonRpcVersion".',
    );
  }
}
