import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Реплей вызова `agent`, завершённого по лимиту ответа (agent-acp-server
/// «Проекция субагентов и списка задач»; design.md change
/// `add-subagents-and-tasks` D41 п. 6, §17.3.6; задача 2.20).
///
/// Почему отдельный файл: значение `failure: max_tokens` итоговой записи
/// `subagent` появляется вместе с `SubagentFailure.maxTokens` ядра; до этого
/// реплей не знает значения, а файл красный, не затрагивая остальные тесты.
/// Журнал собирается записями `subagent` (как в
/// `session_load_subagent_test.dart`), чтобы проверить именно проекцию реплея.
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  final at = DateTime.utc(2026, 11, 14);
  final sessionId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  Future<JsonRpcResponse> load() => h.client.request('session/load', {
    'sessionId': sessionId.value,
    'cwd': '/work/demo',
    'mcpServers': <Object?>[],
  });

  Map<String, Object?> replayedCall(JsonRpcResponse response, String id) =>
      TestClient.updates(
        h.client.received.take(h.client.received.indexOf(response)),
      ).singleWhere(
        (u) => u['sessionUpdate'] == 'tool_call' && u['toolCallId'] == id,
      );

  Map<String, Object?> codelab(Map<String, Object?> update) =>
      ((update['_meta']! as Map)['codelab']! as Map).cast<String, Object?>();

  /// Журнал: вопрос пользователя, вызов `agent` (`call_1`), записи
  /// `subagent` [records] и результат вызова [result] (`null` — результата
  /// нет, сбой между вызовом и результатом, §8.8).
  Future<void> journal(
    List<Map<String, Object?>> records, {
    required ({String outcome, String text, bool isError})? result,
    Map<String, Object?> arguments = const {
      'type': 'explore',
      'description': 'Find auth code',
      'prompt': 'Find where authentication is implemented.',
    },
  }) async {
    await h.store.create(
      SessionHeader(
        id: sessionId,
        cwd: '/work/demo',
        created: at,
        agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
      ),
    );
    await h.store.append(
      sessionId,
      MessageRecord(
        id: 'r1',
        parentId: null,
        timestamp: at,
        message: UserMessage(const [
          TextContent('Where is auth?'),
        ], timestamp: at),
      ),
    );
    await h.store.append(
      sessionId,
      MessageRecord(
        id: 'r2',
        parentId: 'r1',
        timestamp: at,
        message: AssistantMessage(
          content: [
            ToolCall(id: 'call_1', name: 'agent', arguments: arguments),
          ],
          model: scriptedModel,
          usage: Usage.zero,
          stopReason: StopReason.toolUse,
          timestamp: at,
        ),
      ),
    );
    var parent = 'r2';
    for (final (i, record) in records.indexed) {
      final id = 's${i + 1}';
      await h.store.append(
        sessionId,
        SessionRecord.fromJson({
          'type': 'subagent',
          'id': id,
          'parentId': parent,
          'timestamp': at.toIso8601String(),
          'subagentId': 'sub_k3f9a1c2',
          'toolCallId': 'call_1',
          'agent': 'explore',
          'description': 'Find auth code',
          ...record,
        }),
      );
      parent = id;
    }
    if (result != null) {
      await h.store.append(
        sessionId,
        MessageRecord(
          id: 'r3',
          parentId: parent,
          timestamp: at,
          outcome: result.outcome,
          toolMeta: ToolMeta(
            title: 'Subagent explore: Find auth code',
            kind: ToolKind.think,
          ),
          message: ToolResultMessage(
            toolCallId: 'call_1',
            toolName: 'agent',
            content: [TextContent(result.text)],
            isError: result.isError,
            timestamp: at,
          ),
        ),
      );
    }
  }

  test('a completed child: {id, type} and the summary of the final record '
      '(D24, D28)', () async {
    h = await ServerHarness.start();
    await h.initialize();
    await journal(
      [
        {'status': 'running'},
        {
          'status': 'completed',
          'report': 'Auth is in lib/auth/session.dart:12-80.',
          'usage': {
            'input': 15200,
            'output': 3000,
            'cacheRead': 0,
            'cacheWrite': 0,
          },
          'toolCalls': 4,
          'durationMs': 48000,
        },
      ],
      result: (
        outcome: 'completed',
        // Обёртка §17.3.5 лежит в журнале как результат для модели; клиенту
        // уходит тело отчёта без неё.
        text:
            '<subagent-report agent="explore" status="completed">\n'
            'Auth is in lib/auth/session.dart:12-80.\n'
            '</subagent-report>',
        isError: false,
      ),
    );

    final response = await load();

    final call = replayedCall(response, 'call_1');
    expect(call['kind'], 'think');
    expect(call['title'], 'Subagent explore: Find auth code');
    expect(call['status'], 'completed');
    expect(codelab(call), {
      'subagent': {
        'id': 'sub_k3f9a1c2',
        'type': 'explore',
        'summary': {
          'toolCalls': 4,
          'tokens': {'input': 15200, 'output': 3000},
          'durationMs': 48000,
        },
      },
    });
    final text =
        (((call['content']! as List).single as Map)['content'] as Map)['text'];
    expect(text, 'Auth is in lib/auth/session.dart:12-80.');
  });

  test('an empty report cut by the limit replays failed with failure '
      'max_tokens', () async {
    h = await ServerHarness.start();
    await h.initialize();
    await journal(
      [
        {'status': 'running'},
        {
          'status': 'failed',
          'failure': 'max_tokens',
          'report': '',
          'usage': {
            'input': 900,
            'output': 4096,
            'cacheRead': 0,
            'cacheWrite': 0,
          },
          'toolCalls': 2,
          'durationMs': 12000,
        },
      ],
      result: (
        outcome: 'failed',
        text:
            '<subagent-report agent="explore" status="failed" reason="max_tokens">\n'
            'Subagent stopped: it hit the output token limit before writing a report.\n'
            '</subagent-report>',
        isError: true,
      ),
    );

    final response = await load();

    final call = replayedCall(response, 'call_1');
    expect(call['status'], 'failed');
    expect((codelab(call)['subagent']! as Map)['failure'], 'max_tokens');
  });

  test(
    'a truncated non-empty report replays completed without failure',
    () async {
      h = await ServerHarness.start();
      await h.initialize();
      await journal(
        [
          {'status': 'running'},
          {
            'status': 'completed',
            'report':
                'Found three callers: a.dart, b.dart\n'
                '[report truncated: the subagent hit the output token limit]',
            'usage': {
              'input': 900,
              'output': 4096,
              'cacheRead': 0,
              'cacheWrite': 0,
            },
            'toolCalls': 2,
            'durationMs': 12000,
          },
        ],
        result: (
          outcome: 'completed',
          text:
              '<subagent-report agent="explore" status="completed" truncated="true">\n'
              'Found three callers: a.dart, b.dart\n'
              '[report truncated: the subagent hit the output token limit]\n'
              '</subagent-report>',
          isError: false,
        ),
      );

      final response = await load();

      final call = replayedCall(response, 'call_1');
      expect(call['status'], 'completed');
      expect(codelab(call)['subagent'], isNot(contains('failure')));
      final text =
          (((call['content']! as List).single as Map)['content'] as Map)['text']
              as String;
      expect(
        text,
        contains('[report truncated: the subagent hit the output token limit]'),
      );
    },
  );
}
