import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ACP method codec registry', () {
    test('registers current MVP methods', () {
      expect(acpMethodRegistry.keys, {
        initializeMethod,
        sessionNewMethod,
        sessionLoadMethod,
        sessionListMethod,
        sessionPromptMethod,
        sessionCancelMethod,
        sessionSetConfigOptionMethod,
        sessionRequestPermissionMethod,
        sessionUpdateMethod,
      });
    });

    test('decodes request params by method name', () {
      expect(
        decodeAcpParams(initializeMethod, {'protocolVersion': 1}),
        const InitializeRequest(protocolVersion: ProtocolVersion(1)),
      );
      expect(
        decodeAcpParams(sessionNewMethod, {
          'cwd': '/workspace/project',
          'mcpServers': <Object?>[],
        }),
        const NewSessionRequest(cwd: '/workspace/project', mcpServers: []),
      );
      expect(
        decodeAcpParams(sessionLoadMethod, {
          'sessionId': 'session-1',
          'cwd': '/workspace/project',
          'mcpServers': <Object?>[],
        }),
        const LoadSessionRequest(
          sessionId: SessionId('session-1'),
          cwd: '/workspace/project',
          mcpServers: [],
        ),
      );
      expect(
        decodeAcpParams(sessionSetConfigOptionMethod, {
          'sessionId': 'session-1',
          'configId': 'model',
          'value': 'gpt-5',
        }),
        const SetSessionConfigOptionRequest(
          sessionId: SessionId('session-1'),
          configId: SessionConfigId('model'),
          value: SessionConfigValueId('gpt-5'),
        ),
      );
      expect(
        decodeAcpParams(sessionListMethod, {'cursor': 'next'}),
        const ListSessionsRequest(cursor: 'next'),
      );
      expect(
        decodeAcpParams(sessionPromptMethod, {
          'sessionId': 'session-1',
          'prompt': [
            {'type': 'text', 'text': 'hello'},
          ],
        }),
        const PromptRequest(
          sessionId: SessionId('session-1'),
          prompt: [ContentBlock.text(text: 'hello')],
        ),
      );
      expect(
        decodeAcpParams(sessionRequestPermissionMethod, {
          'sessionId': 'session-1',
          'toolCall': {
            'toolCallId': 'call-1',
            'title': 'Run tests',
            'kind': 'execute',
            'status': 'pending',
          },
          'options': [
            {
              'optionId': 'allow-once',
              'name': 'Allow once',
              'kind': 'allow_once',
            },
          ],
        }),
        const RequestPermissionRequest(
          sessionId: SessionId('session-1'),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId('call-1'),
            title: 'Run tests',
            kind: ToolKind.execute,
            status: ToolCallStatus.pending,
          ),
          options: [
            PermissionOption(
              optionId: PermissionOptionId('allow-once'),
              name: 'Allow once',
              kind: PermissionOptionKind.allowOnce,
            ),
          ],
        ),
      );
    });

    test('decodes notification params by method name', () {
      expect(
        decodeAcpNotificationParams(
          const JsonRpcMessage.notification(
                method: sessionCancelMethod,
                params: {'sessionId': 'session-1'},
              )
              as JsonRpcNotification,
        ),
        const CancelNotification(sessionId: SessionId('session-1')),
      );
      expect(
        decodeAcpNotificationParams(
          const JsonRpcMessage.notification(
                method: sessionUpdateMethod,
                params: {
                  'sessionId': 'session-1',
                  'update': {
                    'sessionUpdate': 'agent_message_chunk',
                    'content': {'type': 'text', 'text': 'done'},
                  },
                },
              )
              as JsonRpcNotification,
        ),
        const SessionNotification(
          sessionId: SessionId('session-1'),
          update: SessionUpdate.agentMessageChunk(
            content: ContentBlock.text(text: 'done'),
          ),
        ),
      );
    });

    test('decodes response results by expected method', () {
      expect(
        decodeAcpResult(initializeMethod, {'protocolVersion': 1}),
        const InitializeResponse(protocolVersion: ProtocolVersion(1)),
      );
      expect(
        decodeAcpResult(sessionNewMethod, {'sessionId': 'session-1'}),
        const NewSessionResponse(sessionId: SessionId('session-1')),
      );
      expect(
        decodeAcpResult(sessionLoadMethod, <String, Object?>{}),
        const LoadSessionResponse(),
      );
      expect(
        decodeAcpResult(sessionListMethod, {'sessions': <Object?>[]}),
        const ListSessionsResponse(sessions: []),
      );
      expect(
        decodeAcpResult(sessionPromptMethod, {'stopReason': 'end_turn'}),
        const PromptResponse(stopReason: StopReason.endTurn),
      );
      expect(
        decodeAcpResult(sessionSetConfigOptionMethod, {
          'configOptions': <Object?>[],
        }),
        const SetSessionConfigOptionResponse(configOptions: []),
      );
      expect(
        decodeAcpResult(sessionRequestPermissionMethod, {
          'outcome': {'outcome': 'cancelled'},
        }),
        const RequestPermissionResponse(
          outcome: RequestPermissionOutcome.cancelled(),
        ),
      );
    });

    test('encodes request, notification, and response payloads', () {
      final request = encodeAcpRequest(
        id: const JsonRpcId.integer(1),
        method: initializeMethod,
        params: const InitializeRequest(protocolVersion: ProtocolVersion(1)),
      );
      final notification = encodeAcpNotification(
        method: sessionCancelMethod,
        params: const CancelNotification(sessionId: SessionId('session-1')),
      );
      final response = encodeAcpResponse(
        id: const JsonRpcId.string('prompt-1'),
        method: sessionPromptMethod,
        result: const PromptResponse(stopReason: StopReason.cancelled),
      );

      expect(request.toJson(), {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': 1,
          'clientCapabilities': {
            'fs': {'readTextFile': false, 'writeTextFile': false},
            'terminal': false,
          },
        },
      });
      expect(notification.toJson(), {
        'jsonrpc': '2.0',
        'method': 'session/cancel',
        'params': {'sessionId': 'session-1'},
      });
      expect(response.toJson(), {
        'jsonrpc': '2.0',
        'id': 'prompt-1',
        'result': {'stopReason': 'cancelled'},
      });
    });

    test('rejects unknown methods', () {
      expect(
        () => decodeAcpParams('session/unknown', {}),
        throwsA(
          isA<JsonRpcProtocolException>().having(
            (error) => error.kind,
            'kind',
            JsonRpcProtocolErrorKind.unknownMethod,
          ),
        ),
      );
    });

    test('rejects request and notification direction mismatches', () {
      expect(
        () => decodeAcpRequestParams(
          const JsonRpcMessage.request(
                id: JsonRpcId.integer(1),
                method: sessionCancelMethod,
                params: {'sessionId': 'session-1'},
              )
              as JsonRpcRequest,
        ),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => decodeAcpNotificationParams(
          const JsonRpcMessage.notification(
                method: initializeMethod,
                params: {'protocolVersion': 1},
              )
              as JsonRpcNotification,
        ),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });

    test('rejects wrong params and result shapes', () {
      expect(
        () => decodeAcpParams(initializeMethod, {'protocolVersion': '1'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => decodeAcpResult(sessionPromptMethod, {'stopReason': 'done'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => decodeAcpResult(sessionCancelMethod, {}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => encodeAcpParams(sessionPromptMethod, const ProtocolVersion(1)),
        throwsA(isA<TypeError>()),
      );
    });

    test('allows _meta as the ACP extension point', () {
      final request = decodeAcpParams(initializeMethod, {
        'protocolVersion': 1,
        '_meta': {
          'traceparent': '00-abc-def-01',
          'custom': {'feature': true},
        },
      });

      expect(
        request,
        const InitializeRequest(
          protocolVersion: ProtocolVersion(1),
          meta: {
            'traceparent': '00-abc-def-01',
            'custom': {'feature': true},
          },
        ),
      );
    });

    test('rejects unsupported root fields in ACP params', () {
      expect(
        () => decodeAcpParams(initializeMethod, {
          'protocolVersion': 1,
          'requestId': 'custom-outside-meta',
        }),
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
                contains('use _meta for extensions'),
              ),
        ),
      );
    });

    test('maps unsupported root fields to typed ACP protocol errors', () {
      late final JsonRpcProtocolException exception;
      try {
        decodeAcpParams(sessionPromptMethod, {
          'sessionId': 'session-1',
          'prompt': [
            {'type': 'text', 'text': 'hello'},
          ],
          'customRoot': true,
        });
      } on JsonRpcProtocolException catch (error) {
        exception = error;
      }

      final error = mapJsonRpcProtocolException(
        exception,
        phase: AcpProtocolErrorPhase.params,
        method: sessionPromptMethod,
      );

      expect(error.kind, AcpProtocolErrorKind.invalidAcpParams);
      expect(error.method, sessionPromptMethod);
      expect(error.message, contains('customRoot'));
      expect(error.message, contains('use _meta for extensions'));
    });

    test(
      'keeps nested JSON payloads open inside rawInput rawOutput and _meta',
      () {
        final update = decodeAcpNotificationParams(
          const JsonRpcMessage.notification(
                method: sessionUpdateMethod,
                params: {
                  'sessionId': 'session-1',
                  'update': {
                    'sessionUpdate': 'tool_call_update',
                    'toolCallId': 'call-1',
                    'rawInput': {
                      'customRoot': {
                        'deeply': ['nested', 'agent-owned'],
                      },
                    },
                    'rawOutput': {
                      'unknown': {'status': 'ok'},
                    },
                    '_meta': {
                      'vendor': {'extension': true},
                    },
                  },
                },
              )
              as JsonRpcNotification,
        );

        expect(
          update,
          const SessionNotification(
            sessionId: SessionId('session-1'),
            update: SessionUpdate.toolCallUpdate(
              toolCallUpdate: ToolCallUpdate(
                toolCallId: ToolCallId('call-1'),
                rawInput: {
                  'customRoot': {
                    'deeply': ['nested', 'agent-owned'],
                  },
                },
                rawOutput: {
                  'unknown': {'status': 'ok'},
                },
                meta: {
                  'vendor': {'extension': true},
                },
              ),
            ),
          ),
        );
      },
    );
  });
}
