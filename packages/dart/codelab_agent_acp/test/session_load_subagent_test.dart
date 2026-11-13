import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Реплей вызова `agent` при `session/load` (agent-acp-server «Итог
/// субагента», «Вызов agent»; design.md change `add-subagents-and-tasks` D24,
/// D28; §13.5, §17.3.6; задачи 2.1 и 2.8).
///
/// Почему отдельный файл: журналы здесь собираются записями `subagent`
/// (§8.2.4), а не прогоном сервера, чтобы проверить именно проекцию реплея:
/// первый `tool_call` вызова `agent` несёт `{id, type}` из записи, итог
/// `summary` — из итоговой записи `subagent` (`usage`, `toolCalls`,
/// `durationMs`), `failure` — у `failed`. Красный до задачи 2.8: сегодня запись
/// `subagent` — неизвестный тип журнала, реплей её пропускает.
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
            ToolCall(
              id: 'call_1',
              name: 'agent',
              arguments: const {
                'type': 'explore',
                'description': 'Find auth code',
                'prompt': 'Find where authentication is implemented.',
              },
            ),
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

  test('a failed child carries failure next to the summary', () async {
    h = await ServerHarness.start();
    await h.initialize();
    await journal(
      [
        {'status': 'running'},
        {
          'status': 'failed',
          'failure': 'budget_exceeded:max_steps',
          'report': 'Partial findings.',
          'usage': {
            'input': 9000,
            'output': 800,
            'cacheRead': 0,
            'cacheWrite': 0,
          },
          'toolCalls': 30,
          'durationMs': 61000,
        },
      ],
      result: (
        outcome: 'failed',
        text:
            '<subagent-report agent="explore" status="failed">\n'
            'Partial findings.\n'
            '</subagent-report>',
        isError: true,
      ),
    );

    final response = await load();

    final call = replayedCall(response, 'call_1');
    expect(call['status'], 'failed');
    final subagent = codelab(call)['subagent']! as Map;
    expect(subagent['failure'], 'budget_exceeded:max_steps');
    expect(subagent['summary'], {
      'toolCalls': 30,
      'tokens': {'input': 9000, 'output': 800},
      'durationMs': 61000,
    });
  });

  // §17.3.6: прерванный вызов реплеится `failed` с `outcome: interrupted`;
  // признак вызова `agent` {id, type} берётся из записи `subagent` с тем же
  // `toolCallId` и в этом случае (D28).
  test(
    'an interrupted child keeps {id, type} and outcome interrupted',
    () async {
      h = await ServerHarness.start();
      await h.initialize();
      await journal([
        {'status': 'running'},
      ], result: null);

      final response = await load();

      final call = replayedCall(response, 'call_1');
      expect(call['status'], 'failed');
      final meta = codelab(call);
      expect(meta['outcome'], 'interrupted');
      expect(meta['subagent'], containsPair('id', 'sub_k3f9a1c2'));
      expect(meta['subagent'], containsPair('type', 'explore'));
    },
  );
}
