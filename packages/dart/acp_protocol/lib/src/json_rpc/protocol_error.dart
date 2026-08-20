enum JsonRpcProtocolErrorKind { invalidJson, invalidShape }

final class JsonRpcProtocolException implements FormatException {
  const JsonRpcProtocolException._({required this.kind, required this.message});

  const JsonRpcProtocolException.invalidJson(String message)
    : this._(kind: JsonRpcProtocolErrorKind.invalidJson, message: message);

  const JsonRpcProtocolException.invalidShape(String message)
    : this._(kind: JsonRpcProtocolErrorKind.invalidShape, message: message);

  final JsonRpcProtocolErrorKind kind;

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'JsonRpcProtocolException($kind): $message';
}
