import 'protocol_error.dart';

typedef JsonObject = Map<String, Object?>;
typedef JsonArray = List<Object?>;

bool isJsonValue(Object? value) {
  return switch (value) {
    null || bool() || String() || num() => true,
    List<Object?>() => value.every(isJsonValue),
    Map<String, Object?>() => value.values.every(isJsonValue),
    _ => false,
  };
}

JsonObject requireJsonObject(Object? value, {required String path}) {
  if (value is Map<String, Object?> && isJsonValue(value)) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape('$path must be a JSON object.');
}

Object? optionalJsonRpcParams(JsonObject source) {
  if (!source.containsKey('params')) {
    return null;
  }

  final value = source['params'];
  if (value == null || value is JsonObject || value is JsonArray) {
    if (isJsonValue(value)) {
      return value;
    }
  }

  throw JsonRpcProtocolException.invalidShape(
    'params must be a JSON object, JSON array, or null.',
  );
}

Object? optionalJsonRpcResult(JsonObject source) {
  if (!source.containsKey('result')) {
    return null;
  }

  final value = source['result'];
  if (isJsonValue(value)) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape('result must be a JSON value.');
}
