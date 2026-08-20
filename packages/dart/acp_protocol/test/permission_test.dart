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
          kind: 'execute',
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
    });

    test('preserves raw tool call update collections', () {
      const update = ToolCallUpdate(
        toolCallId: ToolCallId('call-1'),
        content: [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'done'},
          },
        ],
        locations: [
          {'path': 'lib/main.dart', 'line': 12},
        ],
        rawOutput: {'exitCode': 0},
      );

      expect(ToolCallUpdate.fromJson(update.toJson()), update);
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
