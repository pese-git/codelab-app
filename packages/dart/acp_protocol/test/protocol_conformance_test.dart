import 'dart:convert';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ACP protocol conformance', () {
    test(
      'round-trips request params through JSON-RPC wire and typed codecs',
      () {
        const request = InitializeRequest(
          protocolVersion: ProtocolVersion(1),
          clientInfo: Implementation(name: 'CodeLab', version: '0.1.0'),
          meta: {
            'traceparent': '00-abc-def-01',
            'vendor': {'requestId': 'init-1'},
          },
        );

        final encoded = encodeJsonRpcMessage(
          encodeAcpRequest(
            id: const JsonRpcId.integer(1),
            method: initializeMethod,
            params: request,
          ),
        );
        final decoded = decodeJsonRpcMessage(encoded) as JsonRpcRequest;

        expect(decoded.method, initializeMethod);
        expect(decodeAcpRequestParams(decoded), request);
        expect(jsonDecode(encoded), {
          'jsonrpc': '2.0',
          'id': 1,
          'method': initializeMethod,
          'params': request.toJson(),
        });
      },
    );

    test(
      'round-trips notification params through JSON-RPC wire and typed codecs',
      () {
        const notification = SessionNotification(
          sessionId: SessionId('session-1'),
          update: SessionUpdate.toolCallUpdate(
            toolCallUpdate: ToolCallUpdate(
              toolCallId: ToolCallId('call-1'),
              status: ToolCallStatus.completed,
              rawOutput: {
                'custom': {
                  'nested': ['value'],
                },
              },
            ),
          ),
          meta: {'sequence': 3},
        );

        final encoded = encodeJsonRpcMessage(
          encodeAcpNotification(
            method: sessionUpdateMethod,
            params: notification,
          ),
        );
        final decoded = decodeJsonRpcMessage(encoded) as JsonRpcNotification;

        expect(decoded.method, sessionUpdateMethod);
        expect(decodeAcpNotificationParams(decoded), notification);
      },
    );

    test(
      'round-trips response results through JSON-RPC wire and typed codecs',
      () {
        const response = PromptResponse(
          stopReason: StopReason.cancelled,
          meta: {'reason': 'user'},
        );

        final encoded = encodeJsonRpcMessage(
          encodeAcpResponse(
            id: const JsonRpcId.string('prompt-1'),
            method: sessionPromptMethod,
            result: response,
          ),
        );
        final decoded = decodeJsonRpcMessage(encoded) as JsonRpcResponse;

        expect(
          decodeAcpResponseResult(
            method: sessionPromptMethod,
            response: decoded,
          ),
          response,
        );
      },
    );

    test('rejects unknown custom root fields outside _meta', () {
      final decoded =
          decodeJsonRpcMessage(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': 1,
                  'method': sessionPromptMethod,
                  'params': {
                    'sessionId': 'session-1',
                    'prompt': [
                      {'type': 'text', 'text': 'hello'},
                    ],
                    'xVendor': true,
                  },
                }),
              )
              as JsonRpcRequest;

      expect(
        () => decodeAcpRequestParams(decoded),
        throwsA(
          isA<JsonRpcProtocolException>()
              .having(
                (error) => error.kind,
                'kind',
                JsonRpcProtocolErrorKind.invalidShape,
              )
              .having(
                (error) => error.message,
                'message',
                allOf(contains('xVendor'), contains('use _meta')),
              ),
        ),
      );
    });

    test('maps invalid inbound JSON-RPC and ACP payloads to typed errors', () {
      late final JsonRpcProtocolException invalidJsonRpc;
      try {
        decodeJsonRpcMessage('{"jsonrpc":"2.0","id":1}');
      } on JsonRpcProtocolException catch (error) {
        invalidJsonRpc = error;
      }

      final jsonRpcError = mapJsonRpcProtocolException(invalidJsonRpc);
      expect(jsonRpcError.kind, AcpProtocolErrorKind.invalidJsonRpcMessage);
      expect(jsonRpcError.jsonRpcCode, jsonRpcInvalidRequestCode);

      late final JsonRpcProtocolException invalidParams;
      try {
        decodeAcpParams(initializeMethod, {'protocolVersion': '1'});
      } on JsonRpcProtocolException catch (error) {
        invalidParams = error;
      }

      final paramsError = mapJsonRpcProtocolException(
        invalidParams,
        phase: AcpProtocolErrorPhase.params,
        method: initializeMethod,
      );
      expect(paramsError.kind, AcpProtocolErrorKind.invalidAcpParams);
      expect(paramsError.method, initializeMethod);
      expect(paramsError.toJsonRpcError().code, jsonRpcInvalidParamsCode);
    });

    test('does not decode result payloads from JSON-RPC error responses', () {
      const response =
          JsonRpcMessage.response(
                id: JsonRpcId.integer(1),
                error: JsonRpcError(code: -32603, message: 'boom'),
              )
              as JsonRpcResponse;

      expect(
        () => decodeAcpResponseResult(
          method: sessionPromptMethod,
          response: response,
        ),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });
  });
}
