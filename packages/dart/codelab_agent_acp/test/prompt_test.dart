import 'package:acp_protocol/acp_protocol.dart' show JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «session/prompt, проекция и итог хода» (задача 4.2;
/// §13.4, §13.7, §13.8; ACP-3, ACP-7).
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  Future<String> ready({
    List<Map<String, Object?>> steps = const [],
    TurnBudget budget = const TurnBudget(),
    bool slow = false,
  }) async {
    h = await ServerHarness.start(steps: steps, budget: budget, slow: slow);
    await h.initialize();
    return h.newSession();
  }

  Map<String, Object?> text(String text) => {
    'reply': [
      {'text': text},
    ],
  };

  List<Map<String, Object?>> updatesBefore(JsonRpcResponse response) {
    final index = h.client.received.indexOf(response);
    return TestClient.updates(h.client.received.take(index));
  }

  test('the turn streams chunks and ends with end_turn', () async {
    final sessionId = await ready(steps: [text('Hello from the agent')]);

    final response = await h.prompt(sessionId, 'Hi');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final chunks = [
      for (final u in updatesBefore(response))
        if (u['sessionUpdate'] == 'agent_message_chunk')
          (u['content']! as Map)['text'],
    ];
    expect(chunks.join(), 'Hello from the agent');
  });

  test('the connection answers other requests during the turn', () async {
    final sessionId = await ready(
      steps: [
        {
          'delayMs': 1000,
          'reply': [
            {'text': 'late'},
          ],
        },
      ],
    );

    final turn = h.prompt(sessionId, 'Hi');
    final list = await h.client.request('session/list', {});
    await h.clock.elapse(const Duration(seconds: 1));
    final response = await turn;

    expect(list.error, isNull);
    expect(
      h.client.received.indexOf(list),
      lessThan(h.client.received.indexOf(response)),
    );
  });

  test('a second prompt during the turn is turnActive', () async {
    final sessionId = await ready(
      steps: [
        {'waitForCancel': true},
      ],
    );

    final turn = h.prompt(sessionId, 'first');
    await pumpEventQueue();
    final second = await h.prompt(sessionId, 'second');

    expect(second.errorCode, -32602);
    expect(second.error!.data, {
      'codelab': {'reason': 'turnActive'},
    });
    expect(h.logger.eventsOf('acp.prompt.rejected'), hasLength(1));
    await h.client.notify('session/cancel', {'sessionId': sessionId});
    expect((await turn).resultMap, {'stopReason': 'cancelled'});
  });

  test('unknown session, empty prompt and audio are rejected', () async {
    final sessionId = await ready();

    final unknown = await h.prompt('01JB8Q2W6R9T3M5K7N1P4X8Z0C', 'x');
    final empty = await h.client.request('session/prompt', {
      'sessionId': sessionId,
      'prompt': <Object?>[],
    });
    final audio = await h.client.request('session/prompt', {
      'sessionId': sessionId,
      'prompt': [
        {'type': 'audio', 'data': 'AAAA', 'mimeType': 'audio/wav'},
      ],
    });

    expect(unknown.errorCode, -32002);
    expect(empty.errorCode, -32602);
    expect(audio.errorCode, -32602);
  });

  test(
    'resource and resource_link become text for the model (§13.4)',
    () async {
      final sessionId = await ready(steps: [text('ok')]);

      await h.client.request('session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': 'Look'},
          {
            'type': 'resource',
            'resource': {
              'uri': 'file:///work/demo/a.dart',
              'text': 'void a() {}',
            },
          },
          {
            'type': 'resource',
            'resource': {'uri': 'file:///work/demo/logo.png', 'blob': 'AAAA'},
          },
          {
            'type': 'resource_link',
            'uri': 'file:///work/demo/b.dart',
            'name': 'b.dart',
          },
        ],
      });

      final prompt = h.model.requests.single.messages.last as UserMessage;
      expect(
        [for (final b in prompt.content) (b as TextContent).text],
        [
          'Look',
          '<resource uri="file:///work/demo/a.dart">void a() {}</resource>',
          'Binary resource file:///work/demo/logo.png, 3 bytes, not passed',
          'Resource link file:///work/demo/b.dart (b.dart)',
        ],
      );
    },
  );

  test('a read tool call: pending → in_progress → completed', () async {
    final files = MemoryExecutionEnv(cwd: '/work/demo');
    await files.writeText('/work/demo/README.md', '# foo\n');
    final sessionId = await ready(
      steps: [
        {
          'reply': [
            {
              'toolCall': {
                'id': 'call_1',
                'name': 'read',
                'arguments': {'path': 'README.md'},
              },
            },
          ],
        },
        text('Read it'),
      ],
    );
    h.client.serveFiles(files);

    final response = await h.prompt(sessionId, 'Read README.md');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final calls = [
      for (final u in updatesBefore(response))
        if (u['toolCallId'] == 'call_1') '${u['sessionUpdate']} ${u['status']}',
    ];
    expect(calls, [
      'tool_call pending',
      'tool_call_update in_progress',
      'tool_call_update completed',
    ]);
  });

  test(
    'a rejected edit is failed with outcome rejected, the turn goes on',
    () async {
      final files = MemoryExecutionEnv(cwd: '/work/demo');
      await files.writeText('/work/demo/README.md', '# foo\n');
      final sessionId = await ready(
        steps: [
          {
            'reply': [
              {
                'toolCall': {
                  'id': 'call_2',
                  'name': 'edit',
                  'arguments': {
                    'path': 'README.md',
                    'oldText': 'foo',
                    'newText': 'bar',
                  },
                },
              },
            ],
          },
          text('Understood'),
        ],
      );
      h.client
        ..serveFiles(files)
        ..handlers['session/request_permission'] = (_) => {
          'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
        };

      final response = await h.prompt(sessionId, 'Edit README.md');

      expect(response.resultMap, {'stopReason': 'end_turn'});
      final finished = updatesBefore(
        response,
      ).lastWhere((u) => u['toolCallId'] == 'call_2');
      expect(finished['status'], 'failed');
      expect(finished['_meta'], {
        'codelab': {'outcome': 'rejected'},
      });
      expect(
        updatesBefore(response).where(
          (u) => u['toolCallId'] == 'call_2' && u['status'] == 'in_progress',
        ),
        isEmpty,
      );
      expect(
        await files.readText('/work/demo/README.md'),
        const Ok<String, FileError>('# foo\n'),
      );
    },
  );

  group('turn result (§13.8)', () {
    test('step budget → max_turn_requests with budgetExceeded', () async {
      final sessionId = await ready(
        budget: const TurnBudget(maxSteps: 1),
        steps: [
          {
            'reply': [
              {
                'toolCall': {
                  'id': 'call_1',
                  'name': 'update_plan',
                  'arguments': {
                    'entries': [
                      {
                        'content': 'Read',
                        'priority': 'high',
                        'status': 'pending',
                      },
                    ],
                  },
                },
              },
            ],
          },
        ],
      );

      final response = await h.prompt(sessionId, 'Plan');

      expect(response.resultMap, {
        'stopReason': 'max_turn_requests',
        '_meta': {
          'codelab': {'budgetExceeded': 'steps'},
        },
      });
    });

    test('length → max_tokens', () async {
      final sessionId = await ready(
        steps: [
          {
            'reply': [
              {'text': 'cut'},
            ],
            'stopReason': 'length',
          },
        ],
      );

      expect((await h.prompt(sessionId, 'x')).resultMap, {
        'stopReason': 'max_tokens',
      });
    });

    test('terminalFinish → refusal', () async {
      final sessionId = await ready(
        steps: [
          {
            'error': {'class': 'terminalFinish', 'message': 'content_filter'},
          },
        ],
      );

      expect((await h.prompt(sessionId, 'x')).resultMap, {
        'stopReason': 'refusal',
      });
    });

    test(
      'a provider failure is -32603 with data.codelab, not end_turn',
      () async {
        final sessionId = await ready(
          steps: [
            {
              'error': {
                'class': 'auth',
                'message': '401 Unauthorized from openai: check api_key_env',
              },
            },
          ],
        );

        final response = await h.prompt(sessionId, 'x');

        expect(response.result, isNull);
        expect(response.errorCode, -32603);
        expect(response.error!.data, {
          'codelab': {
            'errorClass': 'auth',
            'message': '401 Unauthorized from openai: check api_key_env',
            'retryable': false,
          },
        });
      },
    );
  });

  test(
    '1 000 deltas on a slow transport: the answer is the last frame',
    () async {
      // 16 символов на дельту (§14.7): 16 000 символов — 1 000 дельт.
      final sessionId = await ready(slow: true, steps: [text('x' * 16000)]);

      final response = await h.prompt(sessionId, 'Long answer');

      final chunks = updatesBefore(
        response,
      ).where((u) => u['sessionUpdate'] == 'agent_message_chunk').length;
      expect(chunks, 1000);
      await pumpEventQueue();
      // После ответа — только события сессии: автозаголовок пишется после
      // хода (§8.10), кадров хода там нет.
      final after = TestClient.updates(
        h.client.received.skip(h.client.received.indexOf(response) + 1),
      );
      expect(
        [for (final u in after) u['sessionUpdate']],
        ['session_info_update'],
      );
    },
  );
}
