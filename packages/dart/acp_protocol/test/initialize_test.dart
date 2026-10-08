import 'dart:convert';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('initialize DTOs', () {
    test('round-trips initialize request with capabilities and metadata', () {
      const request = InitializeRequest(
        protocolVersion: ProtocolVersion(1),
        clientCapabilities: ClientCapabilities(
          fs: FileSystemCapabilities(readTextFile: true),
          terminal: true,
          meta: {'custom': true},
        ),
        clientInfo: Implementation(
          name: 'codelab',
          version: '0.1.0',
          title: 'CodeLab',
        ),
        meta: {'traceparent': '00-abc-def-01'},
      );

      expect(InitializeRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'protocolVersion': 1,
        'clientCapabilities': {
          'fs': {'readTextFile': true, 'writeTextFile': false},
          'terminal': true,
          '_meta': {'custom': true},
        },
        'clientInfo': {
          'name': 'codelab',
          'version': '0.1.0',
          'title': 'CodeLab',
        },
        '_meta': {'traceparent': '00-abc-def-01'},
      });
    });

    test('applies initialize response defaults', () {
      final response = InitializeResponse.fromJson({'protocolVersion': 1});

      expect(response.protocolVersion, const ProtocolVersion(1));
      expect(response.agentCapabilities.loadSession, isFalse);
      expect(response.agentCapabilities.promptCapabilities.image, isFalse);
      expect(response.agentCapabilities.mcpCapabilities.http, isFalse);
      expect(response.agentCapabilities.sessionCapabilities.list, isNull);
      expect(response.authMethods, isEmpty);
    });

    test('round-trips initialize response with auth methods', () {
      const response = InitializeResponse(
        protocolVersion: ProtocolVersion(1),
        agentCapabilities: AgentCapabilities(
          loadSession: true,
          mcpCapabilities: McpCapabilities(http: true),
          promptCapabilities: PromptCapabilities(
            image: true,
            embeddedContext: true,
          ),
          sessionCapabilities: SessionCapabilities(
            list: SessionListCapabilities(),
          ),
        ),
        agentInfo: Implementation(name: 'codelab-agent', version: '1.0.0'),
        authMethods: [
          AuthMethod(
            id: 'agent',
            name: 'Agent auth',
            description: 'Handled by the agent',
          ),
        ],
      );

      expect(InitializeResponse.fromJson(response.toJson()), response);
      expect(response.toJson(), {
        'protocolVersion': 1,
        'agentCapabilities': {
          'loadSession': true,
          'mcpCapabilities': {'http': true, 'sse': false},
          'promptCapabilities': {
            'audio': false,
            'embeddedContext': true,
            'image': true,
          },
          'sessionCapabilities': {'list': {}},
        },
        'agentInfo': {'name': 'codelab-agent', 'version': '1.0.0'},
        'authMethods': [
          {
            'id': 'agent',
            'name': 'Agent auth',
            'description': 'Handled by the agent',
          },
        ],
      });
    });

    test('ignores unknown flags inside sessionCapabilities, as announced by a '
        'real agent (@zed-industries/claude-code-acp)', () {
      final response = InitializeResponse.fromJson(
        jsonDecode(
          '{"protocolVersion":1,"agentCapabilities":'
          '{"sessionCapabilities":{"fork":{},"list":{},"resume":{}}}}',
        ),
      );

      expect(
        response.agentCapabilities.sessionCapabilities.list,
        const SessionListCapabilities(),
      );
    });

    test('ignores unknown fields at every level of agentCapabilities', () {
      final response = InitializeResponse.fromJson({
        'protocolVersion': 1,
        'agentCapabilities': {
          'loadSession': true,
          'futureFlag': {'nested': true},
          'mcpCapabilities': {'http': true, 'websocket': true},
          'promptCapabilities': {'image': true, 'video': true},
          'sessionCapabilities': {
            'list': {'pagination': true},
          },
        },
      });

      final capabilities = response.agentCapabilities;
      expect(capabilities.loadSession, isTrue);
      expect(capabilities.mcpCapabilities.http, isTrue);
      expect(capabilities.promptCapabilities.image, isTrue);
      expect(capabilities.sessionCapabilities.list, isNotNull);
    });

    test('still rejects a capability object that is not a JSON object', () {
      expect(
        () => InitializeResponse.fromJson({
          'protocolVersion': 1,
          'agentCapabilities': {'sessionCapabilities': 'fork'},
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });

    test('still rejects unknown root fields outside capability objects', () {
      void expectInvalidShape(void Function() decode) {
        expect(
          decode,
          throwsA(
            isA<JsonRpcProtocolException>().having(
              (error) => error.kind,
              'kind',
              JsonRpcProtocolErrorKind.invalidShape,
            ),
          ),
        );
      }

      expectInvalidShape(
        () => InitializeResponse.fromJson({
          'protocolVersion': 1,
          'customRoot': true,
        }),
      );
      expectInvalidShape(
        () => InitializeRequest.fromJson({
          'protocolVersion': 1,
          'customRoot': true,
        }),
      );
      expectInvalidShape(
        () => Implementation.fromJson({
          'name': 'agent',
          'version': '1',
          'customRoot': true,
        }),
      );
      expectInvalidShape(
        () => decodeAcpParams(sessionPromptMethod, {
          'sessionId': 'session-1',
          'prompt': [
            {'type': 'text', 'text': 'hello'},
          ],
          'customRoot': true,
        }),
      );
    });

    test('rejects invalid protocol versions', () {
      expect(
        () => InitializeRequest.fromJson({'protocolVersion': -1}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => InitializeRequest.fromJson({'protocolVersion': 65536}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => InitializeRequest.fromJson({'protocolVersion': '1'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });

    test('rejects invalid auth method type', () {
      expect(
        () => AuthMethod.fromJson({
          'type': 'oauth',
          'id': 'oauth',
          'name': 'OAuth',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });
  });
}
