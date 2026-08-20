import 'package:freezed_annotation/freezed_annotation.dart';

import 'json_value.dart';
import 'protocol_error.dart';

part 'json_rpc_id.freezed.dart';

@freezed
sealed class JsonRpcId with _$JsonRpcId {
  const JsonRpcId._();

  const factory JsonRpcId.string(String value) = JsonRpcStringId;

  const factory JsonRpcId.integer(int value) = JsonRpcIntId;

  const factory JsonRpcId.nullValue() = JsonRpcNullId;

  factory JsonRpcId.fromJsonValue(Object? value) {
    return switch (value) {
      String() => JsonRpcId.string(value),
      int() => JsonRpcId.integer(value),
      null => const JsonRpcId.nullValue(),
      _ => throw JsonRpcProtocolException.invalidShape(
        'id must be a string, integer, or null.',
      ),
    };
  }

  Object? toJsonValue() {
    return switch (this) {
      JsonRpcStringId(:final value) => value,
      JsonRpcIntId(:final value) => value,
      JsonRpcNullId() => null,
    };
  }
}

JsonRpcId requireJsonRpcId(JsonObject source) {
  if (!source.containsKey('id')) {
    throw JsonRpcProtocolException.invalidShape('id is required.');
  }

  return JsonRpcId.fromJsonValue(source['id']);
}
