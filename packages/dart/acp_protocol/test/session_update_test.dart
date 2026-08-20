import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('session update DTOs', () {
    test('round-trips message chunk updates', () {
      const updates = [
        SessionUpdate.userMessageChunk(
          content: ContentBlock.text(text: 'Show me the issue'),
        ),
        SessionUpdate.agentMessageChunk(
          content: ContentBlock.text(text: 'I found it.'),
          meta: {'chunk': 'agent'},
        ),
        SessionUpdate.agentThoughtChunk(
          content: ContentBlock.text(text: 'Need to inspect tests.'),
        ),
      ];

      for (final update in updates) {
        expect(SessionUpdate.fromJson(update.toJson()), update);
      }
      expect(updates[1].toJson(), {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'I found it.'},
        '_meta': {'chunk': 'agent'},
      });
    });

    test('round-trips tool call updates', () {
      const toolCall = SessionUpdate.toolCall(
        toolCall: ToolCall(
          toolCallId: ToolCallId('call-1'),
          title: 'Read file',
          kind: ToolKind.read,
          status: ToolCallStatus.pending,
          locations: [ToolCallLocation(path: '/workspace/lib/main.dart')],
        ),
      );
      const toolCallUpdate = SessionUpdate.toolCallUpdate(
        toolCallUpdate: ToolCallUpdate(
          toolCallId: ToolCallId('call-1'),
          status: ToolCallStatus.completed,
          content: [
            ToolCallContent.content(
              content: ContentBlock.text(text: 'Read complete.'),
            ),
          ],
        ),
      );

      expect(SessionUpdate.fromJson(toolCall.toJson()), toolCall);
      expect(SessionUpdate.fromJson(toolCallUpdate.toJson()), toolCallUpdate);
      expect(toolCall.toJson(), {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'Read file',
        'kind': 'read',
        'status': 'pending',
        'locations': [
          {'path': '/workspace/lib/main.dart'},
        ],
      });
    });

    test('round-trips plan update', () {
      const update = SessionUpdate.plan(
        entries: [
          PlanEntry(
            content: 'Inspect protocol schema',
            priority: PlanEntryPriority.high,
            status: PlanEntryStatus.completed,
          ),
          PlanEntry(
            content: 'Add DTOs',
            priority: PlanEntryPriority.medium,
            status: PlanEntryStatus.inProgress,
          ),
        ],
      );

      expect(SessionUpdate.fromJson(update.toJson()), update);
      expect(PlanEntryPriority.values.map((priority) => priority.toJson()), [
        'high',
        'medium',
        'low',
      ]);
      expect(PlanEntryStatus.values.map((status) => status.toJson()), [
        'pending',
        'in_progress',
        'completed',
      ]);
    });

    test('round-trips commands, mode, config, and session info updates', () {
      const commands = SessionUpdate.availableCommandsUpdate(
        availableCommands: [
          AvailableCommand(
            name: 'plan',
            description: 'Create an implementation plan',
            input: AvailableCommandInput(hint: 'what to plan'),
          ),
        ],
      );
      const mode = SessionUpdate.currentModeUpdate(
        currentModeId: SessionModeId('ask'),
      );
      const config = SessionUpdate.configOptionUpdate(
        configOptions: [
          SessionConfigOption.select(
            id: SessionConfigId('model'),
            name: 'Model',
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
      const info = SessionUpdate.sessionInfoUpdate(
        title: 'Implement session updates',
        updatedAt: '2026-08-20T12:00:00Z',
        meta: {'source': 'agent'},
      );

      for (final update in [commands, mode, config, info]) {
        expect(SessionUpdate.fromJson(update.toJson()), update);
      }
      expect(commands.toJson(), {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': [
          {
            'name': 'plan',
            'description': 'Create an implementation plan',
            'input': {'hint': 'what to plan'},
          },
        ],
      });
    });

    test('round-trips session notification', () {
      const notification = SessionNotification(
        sessionId: SessionId('session-1'),
        update: SessionUpdate.agentMessageChunk(
          content: ContentBlock.text(text: 'Working on it.'),
        ),
        meta: {'trace': 'session-update'},
      );

      expect(SessionNotification.fromJson(notification.toJson()), notification);
      expect(notification.toJson(), {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Working on it.'},
        },
        '_meta': {'trace': 'session-update'},
      });
    });

    test('rejects invalid discriminators and shapes', () {
      expect(
        () => SessionUpdate.fromJson({'sessionUpdate': 'progress'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => SessionUpdate.fromJson({'sessionUpdate': 'agent_message_chunk'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => SessionUpdate.fromJson({
          'sessionUpdate': 'current_mode_update',
          'modeId': 'ask',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => PlanEntryPriority.fromJson('urgent'),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => PlanEntryStatus.fromJson('skipped'),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => AvailableCommand.fromJson({
          'name': 'plan',
          'input': {'hint': 'missing description'},
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => SessionNotification.fromJson({
          'sessionId': 'session-1',
          'update': [],
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });
  });
}
