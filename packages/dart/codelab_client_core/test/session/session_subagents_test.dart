// Список субагентов сессии `SessionView.subagents` (задача 5b.1 `[client]`
// change `add-subagents-and-tasks`; spec acp-client-kit «Список субагентов
// сессии» (сценарии «Строки ребёнка и внука», «Итог завершённого субагента»,
// «Отмена и отказ», «Ожидание одобрения потомка», «Одобрение без дерева»,
// «Пункты списка у субагента», «Реплей без дублей в списке», «Поздний кадр
// после завершения», «Запуск ждёт одобрения», «Время работающего субагента»,
// «Сторонний агент без признака») и «Отмена по признаку агента» («Отменённый
// субагент после загрузки», часть про строку панели); design.md, D33, D41
// п. 1, D49 Т2–Т6, D50 п. 1, п. 3).
//
// Кадры — сценарные `session/update` теста через `KitAgent`, по образцу
// `test/transcript/subagent_tool_tree_test.dart`. Фикстуры корпуса не
// меняются (D49 Т12): клиентский прогон сверяет кадры, а не `subagents`.
//
// Тесты красные до 5b.2: `SessionView.subagents` пока заглушка и всегда пуста.
// Тесты без `subagents` (характеристики слияния кадров, `ToolCallView`)
// зелёные уже сейчас и фиксируют поведение, которое 5b.2 менять не вправе.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

Map<String, Object?> _meta({
  String? parent,
  Map<String, Object?>? subagent,
  String? outcome,
}) => {
  'codelab': {
    'parentToolCallId': ?parent,
    'subagent': ?subagent,
    'outcome': ?outcome,
  },
};

/// Вызов `agent` (`think`, признак D28); [parent] — родитель на проводе.
Map<String, Object?> _agentCall(
  String id, {
  String? parent,
  String type = 'explore',
  String subagentId = 'sub_a1',
  String status = 'in_progress',
  String description = 'Find auth code',
  String? task,
  Map<String, Object?>? subagentExtra,
  String? outcome,
}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': 'Subagent $type: $description',
  'kind': 'think',
  'status': status,
  'rawInput': {'type': type, 'description': description, 'task': ?task},
  '_meta': _meta(
    parent: parent,
    subagent: {'id': subagentId, 'type': type, ...?subagentExtra},
    outcome: outcome,
  ),
};

/// Обычный вызов потомка с `parentToolCallId`.
Map<String, Object?> _call(
  String id, {
  String? parent,
  String kind = 'read',
  String status = 'in_progress',
  String? title,
}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': title ?? 'Read lib/${id.split('/').last}.dart',
  'kind': kind,
  'status': status,
  if (parent != null) '_meta': _meta(parent: parent),
};

/// Итоговое обновление вызова `agent`: [subagent] — `_meta.codelab.subagent`
/// (итог D24, `failure`), [outcome] — признак агента (`cancelled`).
Map<String, Object?> _end(
  String id, {
  String status = 'completed',
  Map<String, Object?>? subagent,
  String? outcome,
}) => {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': id,
  'status': status,
  if (subagent != null || outcome != null)
    '_meta': _meta(subagent: subagent, outcome: outcome),
};

/// Итог D24: 4 вызова, 15 200 + 3 000 токенов, 48 с.
Map<String, Object?> _summary({String id = 'sub_a1'}) => {
  'id': id,
  'summary': {
    'toolCalls': 4,
    'tokens': {'input': 15200, 'output': 3000},
    'durationMs': 48000,
  },
};

/// План с владельцами: `entries` — пары `(id, owner)`.
Map<String, Object?> _plan(List<(String, String?)> entries) => {
  'sessionUpdate': 'plan',
  'entries': [
    for (final (id, owner) in entries)
      {
        'content': 'Task $id',
        'status': 'pending',
        'priority': 'medium',
        '_meta': {
          'codelab': {
            'task': {'id': id, 'owner': ?owner},
          },
        },
      },
  ],
};

/// `_meta.codelab.subagent` запроса потомка (D8).
Map<String, Object?> _requester({
  required String id,
  required String type,
  required int depth,
  String parent = 'call_1',
}) => {
  'codelab': {
    'subagent': {
      'id': id,
      'type': type,
      'description': 'Check the diff',
      'depth': depth,
      'path': const <String>[],
      'parentToolCallId': parent,
    },
  },
};

void main() {
  late KitAgent agent;
  late SessionHandle session;
  var nextRequestId = 7;
  var now = DateTime.utc(2026, 11, 16, 10);

  setUp(() async {
    now = DateTime.utc(2026, 11, 16, 10);
    // Поддельные часы kit (D49 Т3): тест двигает `now` сам, без таймеров.
    agent = KitAgent(
      capabilities: const AgentCapabilities(loadSession: true),
      clock: () => now,
    );
    await agent.start();
    session = await agent.newSession('s1');
    await agent.prompt(session, 'go');
    nextRequestId = 7;
  });
  tearDown(() => agent.dispose());

  Future<void> emit(Map<String, Object?> update) async {
    agent.update('s1', update);
    await pumpEventQueue();
  }

  Future<void> emitAll(Iterable<Map<String, Object?>> updates) async {
    for (final update in updates) {
      await emit(update);
    }
  }

  List<SubagentRowView> rows() => session.current.subagents;

  SubagentRowView row(String toolCallId) =>
      rows().singleWhere((r) => r.toolCallId == ToolCallId(toolCallId));

  List<String> rowIds() => [for (final r in rows()) r.toolCallId.value];

  /// Запрос разрешения вызова [toolCallId] с `_meta` [meta]; возвращает id
  /// запроса JSON-RPC.
  Future<int> ask(
    String toolCallId,
    Map<String, Object?> meta, {
    ToolKind kind = ToolKind.execute,
  }) async {
    final id = nextRequestId++;
    agent.transport.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: const SessionId('s1'),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(toolCallId),
            title: 'Run dart test',
            kind: kind,
            status: ToolCallStatus.pending,
            rawInput: const {'command': 'dart test'},
            meta: meta,
          ),
          options: const [
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
        ).toJson(),
      ),
    );
    await pumpEventQueue();
    return id;
  }

  /// Отвечает на единственный (или [approvalId]) запрос «Allow once».
  Future<void> allow(ApprovalRequestId approvalId) async {
    await session.respond(approvalId, const PermissionOptionId('allow-once'));
    await pumpEventQueue();
  }

  /// Ребёнок `call_1` (`review`, `sub_a1`) с внуком `call_1/call_2`
  /// (`explore`, `sub_b2`) и его вызовом `ls`.
  Future<void> childAndGrandchild() => emitAll([
    _agentCall('call_1', type: 'review', description: 'Check the diff'),
    _call('call_1/call_1', parent: 'call_1'),
    _agentCall('call_1/call_2', parent: 'call_1', subagentId: 'sub_b2'),
    _call(
      'call_1/call_2/call_1',
      parent: 'call_1/call_2',
      kind: 'search',
      title: 'List lib',
    ),
  ]);

  /// Загрузка сессии [id]: [frames] проигрываются как реплей, затем ответ
  /// на `session/load` (образец «Реплей без дублей» дерева вызовов).
  Future<SessionHandle> load(
    String id,
    List<Map<String, Object?>> frames,
  ) async {
    final request = agent.next(sessionLoadMethod);
    final loading = agent.workspace.loadSession(SessionId(id), cwd: '/work');
    final sent = await request;
    for (final frame in frames) {
      agent.update(id, frame);
    }
    await pumpEventQueue();
    agent.respond(sent, const <String, Object?>{});
    return loading;
  }

  group('«Строки ребёнка и внука» (D33, D49 Т2)', () {
    test('two rows: child (depth 1) and grandchild under it (depth 2), both '
        'running, subtree call counts, last action is the title of the last '
        'subtree call', () async {
      await childAndGrandchild();

      expect(rowIds(), ['call_1', 'call_1/call_2']);
      final child = row('call_1');
      expect(child.subagentId, 'sub_a1');
      expect(child.type, 'review');
      expect(child.title, 'Check the diff');
      expect(child.depth, 1);
      expect(child.state, SubagentRowState.running);
      // Вызовы поддерева: read, вложенный agent и его ls.
      expect(child.toolCalls, 3);
      expect(child.lastAction, 'List lib');

      final grandchild = row('call_1/call_2');
      expect(grandchild.subagentId, 'sub_b2');
      expect(grandchild.type, 'explore');
      expect(grandchild.depth, 2);
      expect(grandchild.state, SubagentRowState.running);
      expect(grandchild.toolCalls, 1);
      expect(grandchild.lastAction, 'List lib');
      // Нет итога и токенов у работающего (Q15).
      expect(grandchild.summary, isNull);
      expect(session.current.subagentCount(SubagentRowState.running), 2);
    });

    test('the title falls back to the call title when rawInput.description '
        'is missing', () async {
      await emit({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call_1',
        'title': 'Subagent explore: Find auth code',
        'kind': 'think',
        'status': 'in_progress',
        '_meta': _meta(subagent: {'id': 'sub_a1', 'type': 'explore'}),
      });

      expect(row('call_1').title, 'Subagent explore: Find auth code');
    });

    test('depth: a great-grandchild is 3; a call with an unknown parent is '
        '1 (the rule of the D21 tree)', () async {
      await emitAll([
        _agentCall('call_1', type: 'review'),
        _agentCall('call_1/call_2', parent: 'call_1', subagentId: 'sub_b2'),
        _agentCall(
          'call_1/call_2/call_3',
          parent: 'call_1/call_2',
          subagentId: 'sub_c3',
        ),
        _agentCall('call_7', parent: 'call_9', subagentId: 'sub_z9'),
      ]);

      expect(row('call_1').depth, 1);
      expect(row('call_1/call_2').depth, 2);
      expect(row('call_1/call_2/call_3').depth, 3);
      expect(row('call_7').depth, 1);
    });

    test('the order is a depth-first walk in arrival order: children stand '
        'under the parent row, even when a sibling root arrives between '
        'them', () async {
      await emitAll([
        _agentCall('call_1', type: 'review'),
        _agentCall('call_2', subagentId: 'sub_c3'),
        _agentCall('call_1/call_1', parent: 'call_1', subagentId: 'sub_b2'),
      ]);

      expect(rowIds(), ['call_1', 'call_1/call_1', 'call_2']);
    });

    test('the element path of the grandchild row is the ids of transcript '
        'items from the top-level row to the row itself (D49 Т2)', () async {
      await childAndGrandchild();

      final root = session.current.transcript
          .whereType<ToolCallItem>()
          .singleWhere((item) => item.toolCallId == const ToolCallId('call_1'));
      final nested = root.children.whereType<ToolCallItem>().singleWhere(
        (item) => item.toolCallId == const ToolCallId('call_1/call_2'),
      );

      expect(row('call_1').path, [root.id]);
      expect(row('call_1/call_2').path, [root.id, nested.id]);
    });
  });

  group('«Итог завершённого субагента»', () {
    test('completed with the summary: 4 calls, 18.2k tokens, 48s, no last '
        'action; the counter completed is 1', () async {
      await emitAll([
        _agentCall('call_1'),
        _call('call_1/call_1', parent: 'call_1'),
        _end('call_1', subagent: _summary()),
      ]);

      final done = row('call_1');
      expect(done.state, SubagentRowState.completed);
      // Терминальная строка берёт число вызовов из итога, а не из дерева.
      expect(done.toolCalls, 4);
      expect(done.summary!.totalTokens, 18200);
      expect(done.summary!.durationText, '48s');
      expect(done.lastAction, isNull);
      expect(session.current.subagentCount(SubagentRowState.completed), 1);
      expect(session.current.subagentCount(SubagentRowState.running), 0);
    });

    test('a terminal row without the summary has no time and no tokens '
        '(a replay of an interrupted call, a third-party agent)', () async {
      await emitAll([_agentCall('call_1'), _end('call_1')]);

      final done = row('call_1');
      expect(done.state, SubagentRowState.completed);
      expect(done.summary, isNull);
      // Без дерева и без итога числа вызовов нет.
      expect(done.toolCalls, isNull);
    });
  });

  group('«Отмена и отказ»', () {
    test('failed with a failure is `failed` with the last action = failure; '
        'failed with outcome cancelled is `cancelled`', () async {
      await emitAll([
        _agentCall('call_1'),
        _agentCall('call_2', subagentId: 'sub_c3'),
        _end(
          'call_1',
          status: 'failed',
          subagent: {'id': 'sub_a1', 'failure': 'budget_exceeded:steps'},
        ),
        _end('call_2', status: 'failed', outcome: 'cancelled'),
      ]);

      expect(row('call_1').state, SubagentRowState.failed);
      expect(row('call_1').lastAction, 'budget_exceeded:steps');
      expect(row('call_2').state, SubagentRowState.cancelled);
      expect(session.current.subagentCount(SubagentRowState.failed), 1);
      expect(session.current.subagentCount(SubagentRowState.cancelled), 1);
    });
  });

  group('«Ожидание одобрения потомка» (D33, D49 Т5)', () {
    test('the grandchild is awaitingApproval with this approvalId, the '
        'child stays running; after the answer the grandchild is running '
        'again', () async {
      await childAndGrandchild();
      await ask(
        'call_1/call_2/call_1',
        _requester(id: 'sub_b2', type: 'explore', depth: 2),
      );

      final approvalId = session.current.pendingApprovals.single.approvalId;
      expect(row('call_1/call_2').state, SubagentRowState.awaitingApproval);
      expect(row('call_1/call_2').approvalId, approvalId);
      expect(row('call_1').state, SubagentRowState.running);
      expect(row('call_1').approvalId, isNull);
      expect(
        session.current.subagentCount(SubagentRowState.awaitingApproval),
        1,
      );

      await allow(approvalId);

      expect(row('call_1/call_2').state, SubagentRowState.running);
      expect(row('call_1/call_2').approvalId, isNull);
    });
  });

  group('«Одобрение без дерева»', () {
    test('without the grandchild row the mark goes to the root row by '
        'parentToolCallId, and no extra row appears', () async {
      await emit(_agentCall('call_1', type: 'review'));
      await ask(
        'call_1/call_2/call_1',
        _requester(id: 'sub_b2', type: 'explore', depth: 2),
      );

      final approvalId = session.current.pendingApprovals.single.approvalId;
      expect(rowIds(), ['call_1']);
      expect(row('call_1').state, SubagentRowState.awaitingApproval);
      expect(row('call_1').approvalId, approvalId);
    });
  });

  group('«Запуск ждёт одобрения» (D50 п. 3)', () {
    test('both the asker and the row being launched are awaitingApproval '
        'with the same approvalId; the counter counts rows (2), not '
        'approvals; after the answer both are running', () async {
      await emitAll([
        _agentCall('call_1', type: 'review'),
        // Запуск внука: вызов ещё `pending`, спрашивает ребёнок `sub_a1`.
        _agentCall(
          'call_1/call_2',
          parent: 'call_1',
          subagentId: 'sub_b2',
          status: 'pending',
        ),
      ]);
      await ask(
        'call_1/call_2',
        _requester(id: 'sub_a1', type: 'review', depth: 1),
        kind: ToolKind.think,
      );

      final approvalId = session.current.pendingApprovals.single.approvalId;
      expect(row('call_1').state, SubagentRowState.awaitingApproval);
      expect(row('call_1').approvalId, approvalId);
      expect(row('call_1/call_2').state, SubagentRowState.awaitingApproval);
      expect(row('call_1/call_2').approvalId, approvalId);
      expect(
        session.current.subagentCount(SubagentRowState.awaitingApproval),
        2,
      );

      await allow(approvalId);

      expect(row('call_1').state, SubagentRowState.running);
      expect(row('call_1/call_2').state, SubagentRowState.running);
    });

    test('several approvals of one row: approvalId is the earliest one '
        '(the order of the keyboard focus)', () async {
      await emitAll([
        _agentCall('call_1', type: 'review'),
        _agentCall(
          'call_1/call_2',
          parent: 'call_1',
          subagentId: 'sub_b2',
          status: 'pending',
        ),
        _call(
          'call_1/call_2/call_1',
          parent: 'call_1/call_2',
          kind: 'execute',
          status: 'pending',
        ),
      ]);
      // Сначала вопрос внука о своём `exec`, затем запрос запуска внука.
      await ask(
        'call_1/call_2/call_1',
        _requester(id: 'sub_b2', type: 'explore', depth: 2),
      );
      await ask(
        'call_1/call_2',
        _requester(id: 'sub_a1', type: 'review', depth: 1),
        kind: ToolKind.think,
      );

      final pending = session.current.pendingApprovals;
      expect(pending, hasLength(2));
      expect(row('call_1/call_2').approvalId, pending.first.approvalId);
    });
  });

  group('«Пункты списка у субагента» (D49 Т6)', () {
    test('the item with the owner and the same id in rawInput.task are '
        'one item `2`', () async {
      await emitAll([
        _agentCall('call_1', task: '2'),
        _plan([('1', 'main'), ('2', 'sub_a1')]),
      ]);

      expect(row('call_1').taskIds, ['2']);
    });

    test('the union without repeats: plan owners first, then '
        'rawInput.task', () async {
      await emitAll([
        _agentCall('call_1', task: '5'),
        _agentCall('call_2', subagentId: 'sub_c3', task: '3'),
        _plan([('3', 'sub_a1'), ('4', 'sub_c3'), ('1', null)]),
      ]);

      // plan: `3` (owner sub_a1), затем `5` из rawInput.task.
      expect(row('call_1').taskIds, ['3', '5']);
      // plan: `4`; rawInput.task `3` уже принадлежит другому, но у этой
      // строки он указан в `task` и попадает в её объединение.
      expect(row('call_2').taskIds, ['4', '3']);
    });

    test('no owner and no task: the list is empty', () async {
      await emit(_agentCall('call_1'));

      expect(row('call_1').taskIds, isEmpty);
    });
  });

  group('«Реплей без дублей в списке»', () {
    test('two agent calls, one with a grandchild call, loaded twice in a '
        'row into one workspace: exactly three terminal rows with the '
        'summary', () async {
      final frames = [
        {
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'review it'},
        },
        _agentCall('call_1', type: 'review', status: 'completed'),
        _agentCall(
          'call_1/call_2',
          parent: 'call_1',
          subagentId: 'sub_b2',
          status: 'completed',
        ),
        _agentCall('call_3', subagentId: 'sub_c3', status: 'completed'),
        _end('call_1', subagent: _summary()),
        _end('call_1/call_2', subagent: _summary(id: 'sub_b2')),
        _end('call_3', subagent: _summary(id: 'sub_c3')),
      ];

      Future<void> expectThree() async {
        final loaded = await load('s-replay', frames);
        final subagents = loaded.current.subagents;
        expect(
          [for (final r in subagents) r.toolCallId.value],
          ['call_1', 'call_1/call_2', 'call_3'],
        );
        for (final r in subagents) {
          expect(r.state, SubagentRowState.completed);
          expect(r.toolCalls, 4);
          expect(r.summary!.durationText, '48s');
        }
      }

      await expectThree();
      await expectThree();
    });

    test('repeated frames of the live call do not duplicate rows', () async {
      final frames = [_agentCall('call_1'), _agentCall('call_1')];
      await emitAll(frames);
      await emitAll(frames);

      expect(rowIds(), ['call_1']);
    });
  });

  group('«Отменённый субагент после загрузки» (D41 п. 1)', () {
    test('session/load replays a failed agent call with outcome cancelled: '
        'the row of the panel is `cancelled`, ToolCallView.status is '
        '`cancelled`, the summary is parsed', () async {
      final loaded = await load('s-cancelled', [
        {
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'explore it'},
        },
        _agentCall(
          'call_1',
          status: 'failed',
          outcome: 'cancelled',
          subagentExtra: {
            'summary': {
              'toolCalls': 2,
              'tokens': {'input': 900, 'output': 100},
              'durationMs': 4000,
            },
          },
        ),
      ]);

      final call = loaded.current.transcript
          .whereType<ToolCallItem>()
          .single
          .details!;
      expect(call.status, ToolCallStatusView.cancelled);
      expect(call.subagentSummary!.toolCalls, 2);
      final only = loaded.current.subagents.single;
      expect(only.state, SubagentRowState.cancelled);
      expect(only.toolCalls, 2);
      expect(only.summary!.durationText, '4s');
    });
  });

  group('«Поздний кадр после завершения» (D49 Т4, D50 п. 1)', () {
    test('after completed an in_progress frame leaves the panel row '
        'completed with its summary', () async {
      await emitAll([
        _agentCall('call_1'),
        _end('call_1', subagent: _summary()),
        _end('call_1', status: 'in_progress'),
      ]);

      expect(row('call_1').state, SubagentRowState.completed);
      expect(row('call_1').toolCalls, 4);
      expect(session.current.subagentCount(SubagentRowState.running), 0);
      expect(session.current.subagentCount(SubagentRowState.completed), 1);
    });

    test('characterization: ToolCallView.status follows the general frame '
        'merge — the late frame returns it to running (до F.1 the transcript '
        'is unchanged)', () async {
      await emitAll([
        _agentCall('call_1'),
        _end('call_1', subagent: _summary()),
        _end('call_1', status: 'in_progress'),
      ]);

      final call = session.current.transcript
          .whereType<ToolCallItem>()
          .single
          .details!;
      expect(call.status, ToolCallStatusView.running);
    });

    test('the latch holds for failed and cancelled too, and a late '
        '`pending` frame does not revive the row', () async {
      await emitAll([
        _agentCall('call_1'),
        _agentCall('call_2', subagentId: 'sub_c3'),
        _end('call_1', status: 'failed'),
        _end('call_2', status: 'failed', outcome: 'cancelled'),
        _end('call_1', status: 'pending'),
        _end('call_2', status: 'in_progress'),
      ]);

      expect(row('call_1').state, SubagentRowState.failed);
      expect(row('call_2').state, SubagentRowState.cancelled);
    });

    test('a final status replaced by another final status follows the '
        'transcript: the final completed after cancelled makes the row '
        'completed', () async {
      await emitAll([
        _agentCall('call_1'),
        _end('call_1', status: 'failed', outcome: 'cancelled'),
        _end('call_1'),
      ]);

      expect(row('call_1').state, SubagentRowState.completed);
    });
  });

  group('«Время работающего субагента» (D49 Т3)', () {
    test('startedAt is the first appearance of the call by the injected '
        'clock; a repeated frame does not shift it', () async {
      now = DateTime.utc(2026, 11, 16, 10, 0, 0);
      await emit(_agentCall('call_1'));
      now = DateTime.utc(2026, 11, 16, 10, 0, 30);
      await emit(_agentCall('call_1'));

      expect(row('call_1').startedAt, DateTime.utc(2026, 11, 16, 10, 0, 0));
      // Формат длительности общий с итогом D24: 41 с — `41s`.
      expect(formatSubagentDuration(const Duration(seconds: 41)), '41s');
    });

    test('a later update of the same call does not shift startedAt', () async {
      now = DateTime.utc(2026, 11, 16, 10, 0, 0);
      await emit(_agentCall('call_1'));
      now = DateTime.utc(2026, 11, 16, 10, 5, 0);
      await emit(_call('call_1/call_1', parent: 'call_1'));
      await emit(_end('call_1', status: 'in_progress'));

      expect(row('call_1').startedAt, DateTime.utc(2026, 11, 16, 10, 0, 0));
    });

    test('after completion the time of the row is 48s from the summary, '
        'not the clock', () async {
      now = DateTime.utc(2026, 11, 16, 10, 0, 0);
      await emit(_agentCall('call_1'));
      now = DateTime.utc(2026, 11, 16, 10, 30, 0);
      await emit(_end('call_1', subagent: _summary()));

      expect(row('call_1').state, SubagentRowState.completed);
      expect(row('call_1').summary!.durationText, '48s');
    });

    test('rows of one call in different sessions remember their own '
        'startedAt', () async {
      now = DateTime.utc(2026, 11, 16, 10, 0, 0);
      await emit(_agentCall('call_1'));
      final other = await agent.newSession('s2');
      // Кадры принимает только сессия с идущим ходом (как s1 в setUp).
      await agent.prompt(other, 'go');
      now = DateTime.utc(2026, 11, 16, 11, 0, 0);
      agent.update('s2', _agentCall('call_1'));
      await pumpEventQueue();

      expect(row('call_1').startedAt, DateTime.utc(2026, 11, 16, 10, 0, 0));
      expect(
        other.current.subagents.single.startedAt,
        DateTime.utc(2026, 11, 16, 11, 0, 0),
      );
    });
  });

  group('«Сторонний агент без признака»', () {
    test('a `think` call titled "Subagent explore: …" without '
        '_meta.codelab.subagent gives no rows', () async {
      await emit({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call_1',
        'title': 'Subagent explore: Find auth code',
        'kind': 'think',
        'status': 'in_progress',
      });

      expect(rows(), isEmpty);
      expect(agent.diagnostics, isEmpty);
    });

    test('a malformed subagent meta gives an empty field, not a failure of '
        'the update', () async {
      await emit({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call_1',
        'title': 'Subagent explore: Find auth code',
        'kind': 'think',
        'status': 'in_progress',
        'rawInput': {'type': 'explore', 'task': 7, 'description': 5},
        '_meta': _meta(subagent: {'id': 'sub_a1', 'type': 'explore'}),
      });

      final only = row('call_1');
      expect(only.taskIds, isEmpty);
      expect(only.title, 'Subagent explore: Find auth code');
      expect(agent.diagnostics, isEmpty);
    });
  });

  group('счётчики по состояниям', () {
    test('five rows, one in each state: every counter is 1, and the '
        'sum equals the number of rows', () async {
      await emitAll([
        _agentCall('call_1', subagentId: 'sub_1'),
        _agentCall('call_2', subagentId: 'sub_2'),
        _agentCall('call_3', subagentId: 'sub_3'),
        _agentCall('call_4', subagentId: 'sub_4'),
        _agentCall('call_5', subagentId: 'sub_5'),
        _end('call_2', subagent: _summary(id: 'sub_2')),
        _end('call_3', status: 'failed'),
        _end('call_4', status: 'failed', outcome: 'cancelled'),
      ]);
      await ask(
        'call_5/call_1',
        _requester(id: 'sub_5', type: 'explore', depth: 1, parent: 'call_5'),
      );

      final view = session.current;
      for (final state in SubagentRowState.values) {
        expect(view.subagentCount(state), 1, reason: '$state');
      }
      expect(view.subagents, hasLength(5));
    });
  });
}
