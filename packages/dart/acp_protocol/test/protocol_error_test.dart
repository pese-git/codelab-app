import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ACP protocol errors', () {
    test('maps invalid JSON to JSON-RPC parse error', () {
      const exception = JsonRpcProtocolException.invalidJson(
        'Unexpected end of input',
      );
      final error = mapJsonRpcProtocolException(exception);

      expect(error.kind, AcpProtocolErrorKind.invalidJson);
      expect(error.jsonRpcCode, jsonRpcParseErrorCode);
      expect(error.toJsonRpcError().toJson(), {
        'code': -32700,
        'message': 'Parse error',
        'data': {'kind': 'invalidJson', 'message': 'Unexpected end of input'},
      });
    });

    test('maps invalid JSON-RPC message shape to invalid request', () {
      const exception = JsonRpcProtocolException.invalidShape(
        'response messages must include id.',
      );
      final error = mapJsonRpcProtocolException(exception);

      expect(error.kind, AcpProtocolErrorKind.invalidJsonRpcMessage);
      expect(error.jsonRpcCode, jsonRpcInvalidRequestCode);
      expect(error.toJsonRpcError().message, 'Invalid Request');
    });

    test('maps unknown ACP methods to method not found', () {
      final error = mapJsonRpcProtocolException(
        const JsonRpcProtocolException.unknownMethod('session/unknown'),
        method: 'session/unknown',
      );

      expect(error.kind, AcpProtocolErrorKind.unknownMethod);
      expect(error.method, 'session/unknown');
      expect(error.jsonRpcCode, jsonRpcMethodNotFoundCode);
      expect(error.toJsonRpcError().toJson(), {
        'code': -32601,
        'message': 'Method not found',
        'data': {
          'kind': 'unknownMethod',
          'message': 'ACP method "session/unknown" is not registered.',
          'method': 'session/unknown',
        },
      });
    });

    test('maps invalid ACP params and results to invalid params', () {
      const paramsException = JsonRpcProtocolException.invalidShape(
        'protocolVersion must be an integer from 0 to 65535.',
      );
      const resultException = JsonRpcProtocolException.invalidShape(
        'stopReason has an unsupported value.',
      );

      final paramsError = mapJsonRpcProtocolException(
        paramsException,
        phase: AcpProtocolErrorPhase.params,
        method: initializeMethod,
      );
      final resultError = mapJsonRpcProtocolException(
        resultException,
        phase: AcpProtocolErrorPhase.result,
        method: sessionPromptMethod,
      );

      expect(paramsError.kind, AcpProtocolErrorKind.invalidAcpParams);
      expect(paramsError.method, initializeMethod);
      expect(paramsError.jsonRpcCode, jsonRpcInvalidParamsCode);
      expect(resultError.kind, AcpProtocolErrorKind.invalidAcpResult);
      expect(resultError.method, sessionPromptMethod);
      expect(resultError.jsonRpcCode, jsonRpcInvalidParamsCode);
    });

    test('maps real decode failures without losing typed exception causes', () {
      late final JsonRpcProtocolException exception;
      try {
        decodeAcpParams('session/unknown', <String, Object?>{});
      } on JsonRpcProtocolException catch (error) {
        exception = error;
      }

      final protocolError = mapJsonRpcProtocolException(
        exception,
        method: 'session/unknown',
      );

      expect(exception.kind, JsonRpcProtocolErrorKind.unknownMethod);
      expect(protocolError.cause, same(exception));
      expect(protocolError.toJsonRpcError().code, jsonRpcMethodNotFoundCode);
    });
  });
}
