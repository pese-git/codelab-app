import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
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

    // У stdio-сервера в ACP нет поля `type`: дискриминатор есть только у
    // `http` и `sse` (`03-Session Setup.md`, «Stdio Transport»;
    // `17-Schema.md`, McpServer). Так его присылает Zed.
    test('parses a stdio MCP server without type', () {
      final request = NewSessionRequest.fromJson({
        'cwd': '/workspace/project',
        'mcpServers': [
          {
            'name': 'filesystem',
            'command': '/path/to/mcp-server',
            'args': ['--stdio'],
            'env': [
              {'name': 'API_KEY', 'value': 'secret123'},
            ],
          },
        ],
      });

      expect(
        request.mcpServers.single,
        const McpServer.stdio(
          name: 'filesystem',
          command: '/path/to/mcp-server',
          args: ['--stdio'],
          env: [EnvVariable(name: 'API_KEY', value: 'secret123')],
        ),
      );
    });

    test('still parses a stdio MCP server with type "stdio"', () {
      expect(
        McpServer.fromJson({
          'type': 'stdio',
          'name': 'filesystem',
          'command': 'mcp-filesystem',
          'args': <Object?>[],
          'env': <Object?>[],
        }),
        isA<McpServerStdio>(),
      );
    });

    // design.md change `add-agent-mcp-client`, D11: неизвестный `type`
    // не роняет весь `session/new`, а сохраняется как вариант `unknown`.
    test('an MCP server of unknown type is kept as McpServerUnknown', () {
      final raw = <String, Object?>{
        'type': 'websocket',
        'name': 'future',
        'extra': 1,
      };
      final server = McpServer.fromJson(raw);

      expect(server, isA<McpServerUnknown>());
      final unknown = server as McpServerUnknown;
      expect(unknown.type, 'websocket');
      expect(unknown.name, 'future');
      expect(server.toJson(), raw);
    });

    test('an unknown MCP server without a string name keeps name null', () {
      final server = McpServer.fromJson({
        'type': 'websocket',
        'url': 'wss://x',
      });

      expect(server, isA<McpServerUnknown>());
      expect((server as McpServerUnknown).name, isNull);
    });

    test('a new session request with an unknown MCP server round-trips', () {
      final json = <String, Object?>{
        'cwd': '/workspace/project',
        'mcpServers': [
          {'type': 'websocket', 'name': 'future', 'url': 'wss://x'},
        ],
      };
      final request = NewSessionRequest.fromJson(json);

      expect(request.mcpServers.single, isA<McpServerUnknown>());
      expect(request.toJson()['mcpServers'], json['mcpServers']);
    });

    test('known MCP types stay strict: extra key, missing field', () {
      expect(
        () => McpServer.fromJson({
          'type': 'http',
          'name': 'web',
          'url': 'https://x',
          'headers': <Object?>[],
          'extra': 1,
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => McpServer.fromJson({'type': 'http', 'name': 'web'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => McpServer.fromJson({
          'type': 'sse',
          'name': 'e',
          'url': 'https://x',
          'extra': 1,
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });

    test('an MCP server without type and command is rejected', () {
      expect(
        () => McpServer.fromJson({
          'name': 'api-server',
          'url': 'https://api.example.com/mcp',
          'headers': <Object?>[],
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
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

    test('ignores a config option with an unrecognized type instead of '
        'rejecting the whole configOptions list', () {
      final response = NewSessionResponse.fromJson({
        'sessionId': 'session-1',
        'configOptions': [
          {
            'type': 'multiselect',
            'id': 'tags',
            'name': 'Tags',
            'currentValue': 'a',
            'options': [
              {'value': 'a', 'name': 'A'},
            ],
          },
          {
            'type': 'select',
            'id': 'model',
            'name': 'Model',
            'currentValue': 'gpt-5',
            'options': [
              {'value': 'gpt-5', 'name': 'GPT-5'},
            ],
          },
        ],
      });

      expect(response.configOptions, hasLength(1));
      expect(response.configOptions!.single.id, SessionConfigId('model'));
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

    test('decodes a null session/load result as an empty response', () {
      // Пример ответа в `03-Session Setup.md#loading-a-session` — `"result": null`.
      expect(LoadSessionResponse.fromJson(null), const LoadSessionResponse());
      expect(
        decodeAcpResult(sessionLoadMethod, null),
        const LoadSessionResponse(),
      );
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

    test('round-trips set session config option request and response', () {
      const request = SetSessionConfigOptionRequest(
        sessionId: SessionId('session-1'),
        configId: SessionConfigId('model'),
        value: SessionConfigValueId('gpt-5'),
      );
      const response = SetSessionConfigOptionResponse(
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

      expect(SetSessionConfigOptionRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'sessionId': 'session-1',
        'configId': 'model',
        'value': 'gpt-5',
      });

      expect(
        SetSessionConfigOptionResponse.fromJson(response.toJson()),
        response,
      );
      expect(response.toJson(), {
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

    test('rejects invalid set session config option shapes', () {
      expect(
        () => SetSessionConfigOptionRequest.fromJson({
          'sessionId': 'session-1',
          'value': 'gpt-5',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => SetSessionConfigOptionRequest.fromJson({
          'sessionId': 'session-1',
          'configId': 'model',
          'value': 42,
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => SetSessionConfigOptionResponse.fromJson({}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });

    test('rejects invalid session and MCP server shapes', () {
      expect(
        () => SessionId.fromJson(''),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => McpServer.fromJson({'type': 42, 'name': 'x'}),
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
