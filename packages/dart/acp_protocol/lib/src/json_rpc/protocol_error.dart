const jsonRpcParseErrorCode = -32700;
const jsonRpcInvalidRequestCode = -32600;
const jsonRpcMethodNotFoundCode = -32601;
const jsonRpcInvalidParamsCode = -32602;
const jsonRpcInternalErrorCode = -32603;

enum JsonRpcProtocolErrorKind { invalidJson, invalidShape, unknownMethod }

enum AcpProtocolErrorKind {
  invalidJson,
  invalidJsonRpcMessage,
  unknownMethod,
  invalidAcpParams,
  invalidAcpResult,
  internalError,
}

enum AcpProtocolErrorPhase { jsonRpcMessage, params, result, internal }

final class AcpProtocolError {
  const AcpProtocolError({
    required this.kind,
    required this.message,
    this.method,
    this.cause,
  });

  factory AcpProtocolError.fromException(
    JsonRpcProtocolException exception, {
    AcpProtocolErrorPhase phase = AcpProtocolErrorPhase.jsonRpcMessage,
    String? method,
  }) {
    final kind = switch (exception.kind) {
      JsonRpcProtocolErrorKind.invalidJson => AcpProtocolErrorKind.invalidJson,
      JsonRpcProtocolErrorKind.unknownMethod =>
        AcpProtocolErrorKind.unknownMethod,
      JsonRpcProtocolErrorKind.invalidShape => switch (phase) {
        AcpProtocolErrorPhase.params => AcpProtocolErrorKind.invalidAcpParams,
        AcpProtocolErrorPhase.result => AcpProtocolErrorKind.invalidAcpResult,
        AcpProtocolErrorPhase.internal => AcpProtocolErrorKind.internalError,
        AcpProtocolErrorPhase.jsonRpcMessage =>
          AcpProtocolErrorKind.invalidJsonRpcMessage,
      },
    };

    return AcpProtocolError(
      kind: kind,
      message: exception.message,
      method: method,
      cause: exception,
    );
  }

  const AcpProtocolError.invalidJson(String message)
    : this(kind: AcpProtocolErrorKind.invalidJson, message: message);

  const AcpProtocolError.invalidJsonRpcMessage(String message)
    : this(kind: AcpProtocolErrorKind.invalidJsonRpcMessage, message: message);

  const AcpProtocolError.unknownMethod(String method)
    : this(
        kind: AcpProtocolErrorKind.unknownMethod,
        message: 'Method not found: $method.',
        method: method,
      );

  const AcpProtocolError.invalidAcpParams({
    required String method,
    required String message,
  }) : this(
         kind: AcpProtocolErrorKind.invalidAcpParams,
         message: message,
         method: method,
       );

  const AcpProtocolError.invalidAcpResult({
    required String method,
    required String message,
  }) : this(
         kind: AcpProtocolErrorKind.invalidAcpResult,
         message: message,
         method: method,
       );

  const AcpProtocolError.internalError(String message)
    : this(kind: AcpProtocolErrorKind.internalError, message: message);

  final AcpProtocolErrorKind kind;
  final String message;
  final String? method;
  final Object? cause;

  int get jsonRpcCode {
    return switch (kind) {
      AcpProtocolErrorKind.invalidJson => jsonRpcParseErrorCode,
      AcpProtocolErrorKind.invalidJsonRpcMessage => jsonRpcInvalidRequestCode,
      AcpProtocolErrorKind.unknownMethod => jsonRpcMethodNotFoundCode,
      AcpProtocolErrorKind.invalidAcpParams => jsonRpcInvalidParamsCode,
      AcpProtocolErrorKind.invalidAcpResult => jsonRpcInvalidParamsCode,
      AcpProtocolErrorKind.internalError => jsonRpcInternalErrorCode,
    };
  }

  String get jsonRpcMessage {
    return switch (kind) {
      AcpProtocolErrorKind.invalidJson => 'Parse error',
      AcpProtocolErrorKind.invalidJsonRpcMessage => 'Invalid Request',
      AcpProtocolErrorKind.unknownMethod => 'Method not found',
      AcpProtocolErrorKind.invalidAcpParams => 'Invalid params',
      AcpProtocolErrorKind.invalidAcpResult => 'Invalid params',
      AcpProtocolErrorKind.internalError => 'Internal error',
    };
  }

  Map<String, Object?> toJson() {
    return {
      'kind': kind.name,
      'message': message,
      if (method != null) 'method': method,
    };
  }

  @override
  String toString() => 'AcpProtocolError($kind): $message';
}

final class JsonRpcProtocolException implements FormatException {
  const JsonRpcProtocolException._({required this.kind, required this.message});

  const JsonRpcProtocolException.invalidJson(String message)
    : this._(kind: JsonRpcProtocolErrorKind.invalidJson, message: message);

  const JsonRpcProtocolException.invalidShape(String message)
    : this._(kind: JsonRpcProtocolErrorKind.invalidShape, message: message);

  const JsonRpcProtocolException.unknownMethod(String method)
    : this._(
        kind: JsonRpcProtocolErrorKind.unknownMethod,
        message: 'ACP method "$method" is not registered.',
      );

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

AcpProtocolError mapJsonRpcProtocolException(
  JsonRpcProtocolException exception, {
  AcpProtocolErrorPhase phase = AcpProtocolErrorPhase.jsonRpcMessage,
  String? method,
}) {
  return AcpProtocolError.fromException(
    exception,
    phase: phase,
    method: method,
  );
}
