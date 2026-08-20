import 'dart:convert';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('JSON-RPC codec', () {
    test('round-trips a request with object params', () {
      const message = JsonRpcMessage.request(
        id: JsonRpcId.integer(1),
        method: 'initialize',
        params: {
          'protocolVersion': 1,
          '_meta': {'traceparent': '00-abc-def-01'},
        },
      );

      final encoded = encodeJsonRpcMessage(message);
      final decoded = decodeJsonRpcMessage(encoded);

      expect(decoded, isA<JsonRpcRequest>());
      expect(jsonDecode(encoded), {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': 1,
          '_meta': {'traceparent': '00-abc-def-01'},
        },
      });
    });

    test('decodes a notification without id', () {
      final decoded = decodeJsonRpcMessage(
        '{"jsonrpc":"2.0","method":"session/update","params":[]}',
      );

      expect(
        decoded,
        isA<JsonRpcNotification>()
            .having((message) => message.method, 'method', 'session/update')
            .having((message) => message.params, 'params', []),
      );
    });

    test('round-trips a result response with null result', () {
      const message = JsonRpcMessage.response(
        id: JsonRpcId.string('request-1'),
        result: null,
      );

      expect(decodeJsonRpcMessage(encodeJsonRpcMessage(message)), message);
      expect(message.toJson(), {
        'jsonrpc': '2.0',
        'id': 'request-1',
        'result': null,
      });
    });

    test('round-trips an error response', () {
      const message = JsonRpcMessage.response(
        id: JsonRpcId.nullValue(),
        error: JsonRpcError(
          code: -32601,
          message: 'Method not found',
          data: {'method': '_unknown'},
        ),
      );

      final decoded = decodeJsonRpcMessage(encodeJsonRpcMessage(message));

      expect(
        decoded,
        isA<JsonRpcResponse>()
            .having((message) => message.id, 'id', const JsonRpcId.nullValue())
            .having((message) => message.error?.code, 'error code', -32601)
            .having(
              (message) => message.error?.message,
              'error message',
              'Method not found',
            ),
      );
    });

    test('maps invalid JSON to a typed error', () {
      expect(
        () => decodeJsonRpcMessage('{'),
        throwsA(
          isA<JsonRpcProtocolException>().having(
            (error) => error.kind,
            'kind',
            JsonRpcProtocolErrorKind.invalidJson,
          ),
        ),
      );
    });

    test('maps invalid JSON-RPC shape to a typed error', () {
      expect(
        () => decodeJsonRpcMessage('{"jsonrpc":"2.0","id":1}'),
        throwsA(
          isA<JsonRpcProtocolException>().having(
            (error) => error.kind,
            'kind',
            JsonRpcProtocolErrorKind.invalidShape,
          ),
        ),
      );
    });

    test('rejects invalid id values', () {
      expect(
        () => decodeJsonRpcMessage(
          '{"jsonrpc":"2.0","id":1.5,"method":"initialize"}',
        ),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });

    test('rejects responses with both result and error', () {
      expect(
        () => decodeJsonRpcMessage(
          '{"jsonrpc":"2.0","id":1,"result":null,'
          '"error":{"code":-32603,"message":"boom"}}',
        ),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });
  });
}
