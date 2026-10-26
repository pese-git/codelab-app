import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcMessage, JsonRpcNotification, JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «session/load и реплей» (задача 7.1; §13.5; ACP-3).
void main() {
  late ServerHarness h;
  ServerHarness? second;

  tearDown(() async {
    await second?.dispose();
    second = null;
    await h.dispose();
  });

  Future<JsonRpcResponse> load(
    TestClient client,
    String sessionId, {
    String cwd = '/work/demo',
  }) => client.request('session/load', {
    'sessionId': sessionId,
    'cwd': cwd,
    'mcpServers': <Object?>[],
  });

  List<Map<String, Object?>> updatesBefore(
    TestClient client,
    JsonRpcResponse response,
  ) => TestClient.updates(
    client.received.take(client.received.indexOf(response)),
  );

  Map<String, Object?> callStep(
    String id,
    String name,
    Map<String, Object?> args,
  ) => {
    'reply': [
      {
        'toolCall': {'id': id, 'name': name, 'arguments': args},
      },
    ],
  };

  test('an unknown session is -32002', () async {
    h = await ServerHarness.start();
    await h.initialize();

    final response = await load(h.client, '01JB8Q2W6R9T3M5K7N1P4X8Z0C');

    expect(response.errorCode, -32002);
  });

  test(
    'the replay of a turn in a new server: history, tail, answer last',
    () async {
      h = await ServerHarness.start(
        steps: [
          {
            'reply': [
              {'thinking': 'Plan first.'},
              {'text': 'Reading.'},
              {
                'toolCall': {
                  'id': 'call_1',
                  'name': 'read',
                  'arguments': {'path': 'README.md'},
                },
              },
            ],
          },
          callStep('call_2', 'update_plan', {
            'entries': [
              {'content': 'Fix', 'priority': 'high', 'status': 'pending'},
            ],
          }),
          // Пустой ответ: цикл добавляет служебную подсказку (§5.4.1).
          {'reply': <Object?>[]},
          {
            'reply': [
              {'text': 'Done.'},
            ],
          },
        ],
      );
      await h.initialize();
      final files = MemoryExecutionEnv(cwd: '/work/demo');
      await files.writeText('/work/demo/README.md', '# foo\n');
      h.client.serveFiles(files);
      final sessionId = await h.newSession();
      expect((await h.prompt(sessionId, 'Read README.md')).error, isNull);
      await h.client.drain();

      second = await ServerHarness.start(sessions: h.store);
      final s = second!;
      await s.initialize();
      final response = await load(s.client, sessionId);

      expect(s.client.received.last, response);
      final updates = updatesBefore(s.client, response);
      expect(
        [for (final u in updates) u['sessionUpdate']],
        [
          'user_message_chunk',
          'agent_thought_chunk',
          'agent_message_chunk',
          'tool_call',
          'tool_call',
          'agent_message_chunk',
          'plan',
          'current_mode_update',
          'config_option_update',
          'available_commands_update',
          'session_info_update',
        ],
      );
      expect(updates.first['content'], {
        'type': 'text',
        'text': 'Read README.md',
      });
      final read = updates[3];
      expect(read['toolCallId'], 'call_1');
      expect(read['status'], 'completed');
      expect(read['kind'], 'read');
      expect(read['rawInput'], {'path': 'README.md'});
      expect(read['locations'], [
        {'path': '/work/demo/README.md'},
      ]);
      expect(read['content'], isNotEmpty);
      expect(updates[5]['content'], {'type': 'text', 'text': 'Done.'});
      expect(updates[6]['entries'], [
        {'content': 'Fix', 'priority': 'high', 'status': 'pending'},
      ]);
      expect(updates[7]['currentModeId'], 'standard');
      expect(updates[9]['availableCommands'], isEmpty);
      expect(updates[10]['title'], 'Read README.md');
      final result = response.resultMap;
      expect((result['modes']! as Map)['currentModeId'], 'standard');
      expect(
        [for (final o in result['configOptions']! as List) (o! as Map)['id']],
        ['mode', 'model'],
      );
    },
  );

  test('a call without a result is failed with outcome interrupted', () async {
    h = await ServerHarness.start();
    await h.initialize();
    final id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
    final at = DateTime.utc(2026, 10, 25);
    await h.store.create(
      SessionHeader(
        id: id,
        cwd: '/work/demo',
        created: at,
        agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
      ),
    );
    await h.store.append(
      id,
      MessageRecord(
        id: 'r1',
        parentId: null,
        timestamp: at,
        message: UserMessage(const [TextContent('Run tests')], timestamp: at),
      ),
    );
    await h.store.append(
      id,
      MessageRecord(
        id: 'r2',
        parentId: 'r1',
        timestamp: at,
        message: AssistantMessage(
          content: [
            ToolCall(
              id: 'call_9',
              name: 'read',
              arguments: const {'path': 'a.txt'},
            ),
          ],
          model: scriptedModel,
          usage: Usage.zero,
          stopReason: StopReason.toolUse,
          timestamp: at,
        ),
      ),
    );

    final response = await load(h.client, id.value);

    final call = updatesBefore(
      h.client,
      response,
    ).singleWhere((u) => u['toolCallId'] == 'call_9');
    expect(call['sessionUpdate'], 'tool_call');
    expect(call['status'], 'failed');
    expect(call['_meta'], {
      'codelab': {'outcome': 'interrupted'},
    });
    expect(h.model.requests, isEmpty);
  });

  test('a session open in this server replays from its snapshot', () async {
    h = await ServerHarness.start(
      steps: [
        {
          'reply': [
            {'text': 'Hello.'},
          ],
        },
      ],
    );
    await h.initialize();
    final sessionId = await h.newSession();
    await h.prompt(sessionId, 'Hi');
    final other = await h.connect();

    final response = await load(other, sessionId);

    expect(response.error, isNull);
    expect(
      [
        for (final u in updatesBefore(other, response))
          if (u['sessionUpdate'] == 'agent_message_chunk')
            (u['content']! as Map)['text'],
      ],
      ['Hello.'],
    );
  });

  test('the cwd of the request wins and is recorded', () async {
    h = await ServerHarness.start();
    await h.initialize();
    final sessionId = await h.newSession();
    second = await ServerHarness.start(sessions: h.store);
    await second!.initialize();

    final response = await load(second!.client, sessionId, cwd: '/work/moved');

    expect(response.error, isNull);
    final last =
        jsonDecode(
              const LineSplitter()
                  .convert(h.store.inner.textOf(SessionId(sessionId))!)
                  .last,
            )
            as Map<String, Object?>;
    expect(last['customType'], 'codelab.cwd_changed');
  });

  test('a relative cwd is -32602', () async {
    h = await ServerHarness.start();
    await h.initialize();
    final sessionId = await h.newSession();

    expect((await load(h.client, sessionId, cwd: 'work')).errorCode, -32602);
  });

  test('a loaded session takes prompts on the new connection', () async {
    h = await ServerHarness.start(
      steps: [
        {
          'reply': [
            {'text': 'First.'},
          ],
        },
        {
          'reply': [
            {'text': 'Second.'},
          ],
        },
      ],
    );
    await h.initialize();
    final sessionId = await h.newSession();
    await h.prompt(sessionId, 'One');
    final other = await h.connect();
    await load(other, sessionId);

    final response = await other.request('session/prompt', {
      'sessionId': sessionId,
      'prompt': [
        {'type': 'text', 'text': 'Two'},
      ],
    });

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final notifications = <JsonRpcMessage>[
      for (final frame in other.received)
        if (frame is JsonRpcNotification) frame,
    ];
    expect(
      TestClient.updates(notifications).where(
        (u) =>
            u['sessionUpdate'] == 'agent_message_chunk' &&
            (u['content']! as Map)['text'] == 'Second.',
      ),
      hasLength(1),
    );
  });
}
