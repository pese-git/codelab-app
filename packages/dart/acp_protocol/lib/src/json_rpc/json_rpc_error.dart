import 'package:freezed_annotation/freezed_annotation.dart';

import 'json_value.dart';
import 'protocol_error.dart';

part 'json_rpc_error.freezed.dart';

@freezed
sealed class JsonRpcError with _$JsonRpcError {
  const JsonRpcError._();

  const factory JsonRpcError({
    required int code,
    required String message,
    Object? data,
  }) = _JsonRpcError;

  factory JsonRpcError.fromJson(Object? value) {
    final source = requireJsonObject(value, path: 'error');
    final code = source['code'];
    final message = source['message'];
    final data = source['data'];

    if (code is! int) {
      throw JsonRpcProtocolException.invalidShape(
        'error.code must be an integer.',
      );
    }

    if (message is! String) {
      throw JsonRpcProtocolException.invalidShape(
        'error.message must be a string.',
      );
    }

    if (source.containsKey('data') && !isJsonValue(data)) {
      throw JsonRpcProtocolException.invalidShape(
        'error.data must be a JSON value.',
      );
    }

    return JsonRpcError(code: code, message: message, data: data);
  }

  JsonObject toJson() {
    return {'code': code, 'message': message, if (data != null) 'data': data};
  }
}

extension AcpProtocolErrorJsonRpc on AcpProtocolError {
  JsonRpcError toJsonRpcError() {
    return JsonRpcError(
      code: jsonRpcCode,
      message: jsonRpcMessage,
      data: toJson(),
    );
  }
}
