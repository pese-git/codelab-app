import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('session setup DTOs', () {
    test('round-trips new session request with stdio MCP server', () {
      const request = NewSessionRequest(
        cwd: '/workspace/project',
        mcpServers: [
          McpServer.stdio(
            name: 'filesystem',
            command: 'mcp-filesystem',
            args: ['--root', '/workspace/project'],
            env: [EnvVariable(name: 'LOG_LEVEL', value: 'debug')],
          ),
        ],
        meta: {'trace': 'new-session'},
      );

      expect(NewSessionRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'cwd': '/workspace/project',
        'mcpServers': [
          {
            'type': 'stdio',
            'name': 'filesystem',
            'command': 'mcp-filesystem',
            'args': ['--root', '/workspace/project'],
            'env': [
              {'name': 'LOG_LEVEL', 'value': 'debug'},
            ],
          },
        ],
        '_meta': {'trace': 'new-session'},
      });
    });

    test('round-trips new session response with modes and config options', () {
      const response = NewSessionResponse(
        sessionId: SessionId('session-1'),
        modes: SessionModeState(
          availableModes: [
            SessionMode(
              id: SessionModeId('ask'),
              name: 'Ask',
              description: 'Answer without editing',
            ),
            SessionMode(id: SessionModeId('code'), name: 'Code'),
          ],
          currentModeId: SessionModeId('ask'),
        ),
        configOptions: [
          SessionConfigOption.select(
            id: SessionConfigId('model'),
            name: 'Model',
            category: 'model',
            currentValue: SessionConfigValueId('gpt-5'),
            options: [
              SessionConfigSelectOption(
                value: SessionConfigValueId('gpt-5'),
                name: 'GPT-5',
              ),
            ],
          ),
        ],
      );

      expect(NewSessionResponse.fromJson(response.toJson()), response);
      expect(response.toJson(), {
        'sessionId': 'session-1',
        'modes': {
          'availableModes': [
            {
              'id': 'ask',
              'name': 'Ask',
              'description': 'Answer without editing',
            },
            {'id': 'code', 'name': 'Code'},
          ],
          'currentModeId': 'ask',
        },
        'configOptions': [
          {
            'type': 'select',
            'id': 'model',
            'name': 'Model',
            'currentValue': 'gpt-5',
            'options': [
              {'value': 'gpt-5', 'name': 'GPT-5'},
            ],
            'category': 'model',
          },
        ],
      });
    });

    test('round-trips load session request and response', () {
      const request = LoadSessionRequest(
        sessionId: SessionId('session-1'),
        cwd: '/workspace/project',
        mcpServers: [
          McpServer.http(
            name: 'remote tools',
            url: 'https://mcp.example.com',
            headers: [HttpHeader(name: 'Authorization', value: 'Bearer token')],
          ),
          McpServer.sse(name: 'events', url: 'https://mcp.example.com/sse'),
        ],
      );
      const response = LoadSessionResponse(
        modes: SessionModeState(
          availableModes: [SessionMode(id: SessionModeId('ask'), name: 'Ask')],
          currentModeId: SessionModeId('ask'),
        ),
      );

      expect(LoadSessionRequest.fromJson(request.toJson()), request);
      expect(LoadSessionResponse.fromJson(response.toJson()), response);
    });

    test('round-trips session list request and response', () {
      const request = ListSessionsRequest(
        cwd: '/workspace/project',
        cursor: 'opaque-cursor',
      );
      const response = ListSessionsResponse(
        sessions: [
          SessionInfo(
            sessionId: SessionId('session-1'),
            cwd: '/workspace/project',
            title: 'Implement DTOs',
            updatedAt: '2026-08-20T14:00:00Z',
          ),
        ],
        nextCursor: 'next-cursor',
      );

      expect(ListSessionsRequest.fromJson(request.toJson()), request);
      expect(ListSessionsResponse.fromJson(response.toJson()), response);
      expect(response.toJson(), {
        'sessions': [
          {
            'sessionId': 'session-1',
            'cwd': '/workspace/project',
            'title': 'Implement DTOs',
            'updatedAt': '2026-08-20T14:00:00Z',
          },
        ],
        'nextCursor': 'next-cursor',
      });
    });

    test('rejects invalid session and MCP server shapes', () {
      expect(
        () => SessionId.fromJson(''),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => McpServer.fromJson({'type': 'websocket'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => NewSessionRequest.fromJson({
          'cwd': '/workspace/project',
          'mcpServers': [
            {'type': 'stdio', 'name': 'tools', 'command': 'mcp', 'args': []},
          ],
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });
  });
}
