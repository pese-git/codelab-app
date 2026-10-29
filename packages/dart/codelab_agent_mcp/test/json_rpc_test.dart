import 'dart:convert';

// Тест кодека проверяет внутренние типы пакета, которых нет в барели.
// ignore: implementation_imports
import 'package:codelab_agent_mcp/src/json_rpc.dart';
// ignore: implementation_imports
import 'package:codelab_agent_mcp/src/protocol.dart';
import 'package:test/test.dart';

Map<String, Object?> _json(String text) =>
    jsonDecode(text) as Map<String, Object?>;

void main() {
  group('decode', () {
    test('request, notification, response and error round-trip', () {
      final out = McpOutbound(clientName: 'codelab-agent', clientVersion: '1');
      final request = out.request('tools/list', {'cursor': 'c'});
      final notification = out.notification('notifications/initialized');

      final decoded = [
        ...decodeMcpMessages(request.text),
        ...decodeMcpMessages(notification),
        ...decodeMcpMessages(out.response(7, {'ok': true})),
        ...decodeMcpMessages(out.errorResponse('x', -32601, 'nope')),
      ];

      expect(decoded[0], isA<McpRequest>());
      expect((decoded[0] as McpRequest).id, request.id);
      expect((decoded[0] as McpRequest).method, 'tools/list');
      expect((decoded[0] as McpRequest).params['cursor'], 'c');
      expect(
        (decoded[1] as McpNotification).method,
        'notifications/initialized',
      );
      expect((decoded[2] as McpResponse).id, 7);
      expect((decoded[2] as McpResponse).result, {'ok': true});
      final error = decoded[3] as McpErrorResponse;
      expect((error.id, error.code, error.message), ('x', -32601, 'nope'));
    });

    test('an id is an int or a string; null is a parse error', () {
      expect(
        decodeMcpMessages('{"jsonrpc":"2.0","id":"a","result":{}}').single,
        isA<McpResponse>(),
      );
      expect(
        decodeMcpMessages('{"jsonrpc":"2.0","id":null,"result":{}}').single,
        isA<McpMalformed>(),
      );
      expect(
        decodeMcpMessages('{"jsonrpc":"2.0","id":1.5,"result":{}}').single,
        isA<McpMalformed>(),
      );
    });

    test('not JSON and not an object are parse errors, never exceptions', () {
      expect(decodeMcpMessages('not json').single, isA<McpMalformed>());
      expect(decodeMcpMessages('42').single, isA<McpMalformed>());
      expect(
        decodeMcpMessages('{"jsonrpc":"2.0"}').single,
        isA<McpMalformed>(),
      );
      expect(
        decodeMcpMessages('{"jsonrpc":"1.0","id":1,"result":{}}').single,
        isA<McpMalformed>(),
      );
    });

    test('an array is a sequence of messages (2025-03-26)', () {
      final batch = jsonEncode([
        {'jsonrpc': '2.0', 'id': 1, 'result': {}},
        {'jsonrpc': '2.0', 'method': 'notifications/tools/list_changed'},
        'garbage',
      ]);

      final decoded = decodeMcpMessages(batch);

      expect(decoded, hasLength(3));
      expect(decoded[0], isA<McpResponse>());
      expect(decoded[1], isA<McpNotification>());
      expect(decoded[2], isA<McpMalformed>());
    });

    test('an empty array is a parse error', () {
      expect(decodeMcpMessages('[]').single, isA<McpMalformed>());
    });
  });

  group('outbound', () {
    test('ids grow without repeats', () {
      final out = McpOutbound(clientName: 'c', clientVersion: '1');

      final ids = [for (var i = 0; i < 5; i++) out.request('m').id];

      expect(ids, [1, 2, 3, 4, 5]);
    });

    test('modern requests carry _meta, legacy ones do not', () {
      final out = McpOutbound(
        clientName: 'codelab-agent',
        clientVersion: '9.9',
      );

      final modern = _json(out.request('tools/list').text);
      out.era = McpEra.legacy;
      final legacy = _json(out.request('tools/list').text);

      expect((modern['params'] as Map)['_meta'], {
        'io.modelcontextprotocol/protocolVersion': '2026-07-28',
        'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
        'io.modelcontextprotocol/clientInfo': {
          'name': 'codelab-agent',
          'version': '9.9',
        },
      });
      expect(legacy['params'], anyOf(isNull, isNot(contains('_meta'))));
    });

    test('_meta is added next to the own params of the request', () {
      final out = McpOutbound(clientName: 'c', clientVersion: '1');

      final params =
          _json(out.request('tools/call', {'name': 'echo'}).text)['params']
              as Map;

      expect(params['name'], 'echo');
      expect(params['_meta'], isA<Map>());
    });

    test('notifications never carry _meta', () {
      final out = McpOutbound(clientName: 'c', clientVersion: '1');

      final text = out.notification('notifications/cancelled', {
        'requestId': 3,
      });

      expect(_json(text)['params'], {'requestId': 3});
      expect(_json(text), isNot(contains('id')));
    });
  });

  group('protocol', () {
    test('modern error codes are recognized, others are not', () {
      expect(isModernErrorCode(-32020), isTrue);
      expect(isModernErrorCode(-32021), isTrue);
      expect(isModernErrorCode(-32022), isTrue);
      expect(isModernErrorCode(-32601), isFalse);
      expect(isModernErrorCode(-32602), isFalse);
    });

    test('-32022 exposes data.supported', () {
      final error =
          decodeMcpMessages(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': 1,
                  'error': {
                    'code': -32022,
                    'message': 'Unsupported protocol version',
                    'data': {
                      'supported': ['2027-01-01'],
                      'requested': '2026-07-28',
                    },
                  },
                }),
              ).single
              as McpErrorResponse;

      expect(error.supportedVersions, ['2027-01-01']);
    });

    test('resultType: absent is complete, unknown is a schema error', () {
      expect(parseResultType(<String, Object?>{}), ResultType.complete);
      expect(parseResultType({'resultType': 'complete'}), ResultType.complete);
      expect(
        parseResultType({'resultType': 'input_required'}),
        ResultType.inputRequired,
      );
      expect(
        () => parseResultType({'resultType': 'streaming'}),
        throwsA(isA<McpSchemaException>()),
      );
    });

    test('DiscoverResult reads versions, capabilities and server info', () {
      final result = DiscoverResult.fromJson({
        'resultType': 'complete',
        'supportedVersions': ['2026-07-28'],
        'capabilities': {
          'tools': {'listChanged': true},
        },
        '_meta': {
          'io.modelcontextprotocol/serverInfo': {'name': 's', 'version': '1'},
        },
      });

      expect(result.supportedVersions, ['2026-07-28']);
      expect(result.hasTools, isTrue);
      expect(result.toolsListChanged, isTrue);
      expect(result.serverInfo, {'name': 's', 'version': '1'});
    });

    test('a DiscoverResult without supportedVersions is a schema error', () {
      expect(
        () => DiscoverResult.fromJson({'capabilities': <String, Object?>{}}),
        throwsA(isA<McpSchemaException>()),
      );
    });

    test('CallToolResult reads content, structuredContent and isError', () {
      final result = CallToolResult.fromJson({
        'content': [
          {'type': 'text', 'text': 'a'},
        ],
        'structuredContent': {'k': 1},
        'isError': true,
      });

      expect(result.content, hasLength(1));
      expect(result.structuredContent, {'k': 1});
      expect(result.isError, isTrue);
      expect(
        () => CallToolResult.fromJson({'content': 'oops'}),
        throwsA(isA<McpSchemaException>()),
      );
    });

    test('tool definitions keep the raw schema and annotations', () {
      final tool = McpToolDefinition.fromJson({
        'name': 'echo',
        'title': 'Echo',
        'description': 'd',
        'inputSchema': {'type': 'object'},
        'annotations': {'readOnlyHint': true},
        'execution': {'taskSupport': 'required'},
      });

      expect(tool.name, 'echo');
      expect(tool.annotations, {'readOnlyHint': true});
      expect(tool.taskSupport, 'required');
      expect(tool.inputSchema, {'type': 'object'});
    });
  });
}
