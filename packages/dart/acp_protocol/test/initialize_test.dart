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
