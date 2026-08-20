import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('permission DTOs', () {
    test('round-trips request permission request', () {
      const request = RequestPermissionRequest(
        sessionId: SessionId('session-1'),
        toolCall: ToolCallUpdate(
          toolCallId: ToolCallId('call-1'),
          title: 'Run tests',
          kind: ToolKind.execute,
          status: ToolCallStatus.pending,
          rawInput: {
            'command': 'fvm',
            'args': ['dart', 'test'],
          },
        ),
        options: [
          PermissionOption(
            optionId: PermissionOptionId('allow-once'),
            name: 'Allow once',
            kind: PermissionOptionKind.allowOnce,
          ),
          PermissionOption(
            optionId: PermissionOptionId('reject-once'),
            name: 'Reject',
            kind: PermissionOptionKind.rejectOnce,
          ),
        ],
        meta: {'trace': 'permission'},
      );

      expect(RequestPermissionRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'sessionId': 'session-1',
        'toolCall': {
          'toolCallId': 'call-1',
          'title': 'Run tests',
          'kind': 'execute',
          'status': 'pending',
          'rawInput': {
            'command': 'fvm',
            'args': ['dart', 'test'],
          },
        },
        'options': [
          {
            'optionId': 'allow-once',
            'name': 'Allow once',
            'kind': 'allow_once',
          },
          {'optionId': 'reject-once', 'name': 'Reject', 'kind': 'reject_once'},
        ],
        '_meta': {'trace': 'permission'},
      });
    });

    test('round-trips selected and cancelled outcomes', () {
      const selected = RequestPermissionResponse(
        outcome: RequestPermissionOutcome.selected(
          optionId: PermissionOptionId('allow-once'),
          meta: {'remember': false},
        ),
      );
      const cancelled = RequestPermissionResponse(
        outcome: RequestPermissionOutcome.cancelled(),
        meta: {'reason': 'turn-cancelled'},
      );

      expect(RequestPermissionResponse.fromJson(selected.toJson()), selected);
      expect(RequestPermissionResponse.fromJson(cancelled.toJson()), cancelled);
      expect(selected.toJson(), {
        'outcome': {
          'outcome': 'selected',
          'optionId': 'allow-once',
          '_meta': {'remember': false},
        },
      });
      expect(cancelled.toJson(), {
        'outcome': {'outcome': 'cancelled'},
        '_meta': {'reason': 'turn-cancelled'},
      });
    });

    test('round-trips all permission option kinds and tool statuses', () {
      expect(PermissionOptionKind.values.map((kind) => kind.toJson()), [
        'allow_once',
        'allow_always',
        'reject_once',
        'reject_always',
      ]);
      expect(ToolCallStatus.values.map((status) => status.toJson()), [
        'pending',
        'in_progress',
        'completed',
        'failed',
      ]);
      expect(ToolKind.values.map((kind) => kind.toJson()), [
        'read',
        'edit',
        'delete',
        'move',
        'search',
        'execute',
        'think',
        'fetch',
        'other',
      ]);
    });

    test('round-trips tool call and typed tool call update collections', () {
      const call = ToolCall(
        toolCallId: ToolCallId('call-1'),
        title: 'Edit config',
        kind: ToolKind.edit,
        status: ToolCallStatus.inProgress,
        content: [
          ToolCallContent.diff(
            diff: Diff(
              path: '/workspace/config.json',
              oldText: '{"debug": false}',
              newText: '{"debug": true}',
            ),
          ),
          ToolCallContent.terminal(terminalId: 'term-1'),
        ],
        locations: [ToolCallLocation(path: '/workspace/config.json', line: 4)],
        rawInput: {'path': '/workspace/config.json'},
      );
      const update = ToolCallUpdate(
        toolCallId: ToolCallId('call-1'),
        content: [
          ToolCallContent.content(
            content: ContentBlock.text(text: 'done'),
            meta: {'chunk': 1},
          ),
        ],
        locations: [ToolCallLocation(path: 'lib/main.dart', line: 12)],
        rawOutput: {'exitCode': 0},
      );

      expect(ToolCall.fromJson(call.toJson()), call);
      expect(ToolCallUpdate.fromJson(update.toJson()), update);
      expect(call.toJson(), {
        'toolCallId': 'call-1',
        'title': 'Edit config',
        'kind': 'edit',
        'status': 'in_progress',
        'content': [
          {
            'type': 'diff',
            'path': '/workspace/config.json',
            'oldText': '{"debug": false}',
            'newText': '{"debug": true}',
          },
          {'type': 'terminal', 'terminalId': 'term-1'},
        ],
        'locations': [
          {'path': '/workspace/config.json', 'line': 4},
        ],
        'rawInput': {'path': '/workspace/config.json'},
      });
    });

    test('rejects invalid permission and tool call shapes', () {
      expect(
        () => PermissionOptionKind.fromJson('allow_forever'),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => RequestPermissionOutcome.fromJson({'outcome': 'approved'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => RequestPermissionOutcome.fromJson({'outcome': 'selected'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ToolCallUpdate.fromJson({'title': 'missing id'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ToolKind.fromJson('mutate'),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ToolCall.fromJson({'toolCallId': 'call-1'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ToolCallContent.fromJson({'type': 'artifact'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ToolCallContent.fromJson({
          'type': 'content',
          'content': {'type': 'text'},
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => Diff.fromJson({'path': '/workspace/file.txt'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ToolCallLocation.fromJson({
          'path': '/workspace/file.txt',
          'line': -1,
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => RequestPermissionRequest.fromJson({
          'sessionId': 'session-1',
          'toolCall': {'toolCallId': 'call-1'},
          'options': {'optionId': 'allow-once'},
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });
  });
}
