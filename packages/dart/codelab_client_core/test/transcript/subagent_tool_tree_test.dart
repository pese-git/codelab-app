// Дерево вызовов потомков в kit (задача 5.1 `[client]` change
// `add-subagents-and-tasks`; spec acp-client-kit «Дерево вызовов потомков»
// (сценарии «Вложенность по parentToolCallId», «Неизвестный родитель»,
// «Реплей без дублей», «Запрос в дереве»), «Запрос одобрения от субагента»
// (путь вопроса при дереве без `…`), «Итог и хвост субагента» («Хвост из
// пяти вызовов», счётчик поддерева), «Операции со списком задач в ленте»
// («Операции ребёнка в дереве»); design.md, D21, D25, D27 п. 4, D43 п. 4,
// D47 Т9, D48 п. 3).
//
// Кадры — сценарные `session/update` теста; фикстуры корпуса
// `acp/prompt-subagent-tool-tree` и `acp/session-load-subagent-tool-tree`
// клиентский прогон подхватывает сам.
//
// Что проверяется в kit:
//   `ToolCallView.parentToolCallId` — родитель вызова на проводе;
//   `ToolCallItem.children` — вложенные `ToolCallItem`/`TaskOpsItem` строки
//     вызова в порядке прихода (D47 Т9);
//   `ToolCallItem.tail` (`SubagentTailView.calls`, `.moreCount`) — хвост
//     работающего `agent` (D25);
//   `ToolCallItem.subtreeCalls` — число вызовов поддерева для счётчика
//     `N tool calls` (вложенные `agent` и операции считаются, как в
//     `summary.toolCalls`).
// Верхний уровень `SessionView.transcript` не содержит вызовов с известным
// родителем; вызов с неизвестным родителем остаётся на верхнем уровне.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

Map<String, Object?> _meta({String? parent, Map<String, Object?>? subagent}) =>
    {
      'codelab': {'parentToolCallId': ?parent, 'subagent': ?subagent},
    };

/// Вызов `agent` (`think`, признак D28); [parent] — родитель на проводе.
Map<String, Object?> _agentCall(
  String id, {
  String? parent,
  String type = 'explore',
  String subagentId = 'sub_a1',
  String status = 'in_progress',
}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': 'Subagent $type: Find auth code',
  'kind': 'think',
  'status': status,
  'rawInput': {'type': type, 'description': 'Find auth code'},
  '_meta': _meta(parent: parent, subagent: {'id': subagentId, 'type': type}),
};

/// Обычный вызов потомка (`read`/`execute`) с `parentToolCallId`.
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

Map<String, Object?> _finish(
  String id, {
  String status = 'completed',
  Map<String, Object?>? subagent,
  List<Map<String, Object?>>? content,
}) => {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': id,
  'status': status,
  'content': ?content,
  if (subagent != null) '_meta': _meta(subagent: subagent),
};

Map<String, Object?> _plan(
  List<String> ids, {
  required String op,
  required String call,
  List<String> changed = const [],
}) => {
  'sessionUpdate': 'plan',
  'entries': [
    for (final id in ids)
      {
        'content': 'Task $id',
        'status': 'pending',
        'priority': 'medium',
        '_meta': {
          'codelab': {
            'task': {'id': id},
          },
        },
      },
  ],
  '_meta': {
    'codelab': {
      'taskChange': {
        'op': op,
        'actor': 'main',
        'toolCallId': call,
        'changed': changed,
        'deleted': const <String>[],
      },
    },
  },
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
  late JsonRpcRequest prompt;
  var nextRequestId = 7;

  setUp(() async {
    agent = KitAgent(capabilities: const AgentCapabilities(loadSession: true));
    await agent.start();
    session = await agent.newSession('s1');
    prompt = (await agent.prompt(session, 'go')).request;
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

  List<TranscriptItem> top() => session.current.transcript;

  Iterable<ToolCallItem> topCalls() => top().whereType<ToolCallItem>();

  ToolCallItem topCall(String id) =>
      topCalls().singleWhere((item) => item.toolCallId == ToolCallId(id));

  /// Вложенные вызовы строки [item], без операций.
  List<String> childIds(ToolCallItem item) => [
    for (final child in item.children.whereType<ToolCallItem>())
      child.toolCallId.value,
  ];

  /// Вложенная строка [id]; её отсутствие — падение утверждения, а не
  /// исключение поиска.
  ToolCallItem child(ToolCallItem item, String id) {
    final found = item.children
        .whereType<ToolCallItem>()
        .where((c) => c.toolCallId == ToolCallId(id))
        .toList();
    expect(found, hasLength(1), reason: 'вложенная строка $id');
    return found.single;
  }

  group('the tree by parentToolCallId (D21, D47 Т9)', () {
    test('«Вложенность по parentToolCallId»: child and grandchild are nested '
        'rows, even when call_1/call_2 comes before its own child', () async {
      await emitAll([
        _agentCall('call_1', type: 'review'),
        _call('call_1/call_1', parent: 'call_1'),
        _agentCall('call_1/call_2', parent: 'call_1', subagentId: 'sub_b2'),
        _call('call_1/call_2/call_1', parent: 'call_1/call_2'),
      ]);

      // Верхний уровень — только вызов корня.
      expect(topCalls().map((c) => c.toolCallId.value), ['call_1']);
      final root = topCall('call_1');
      expect(childIds(root), ['call_1/call_1', 'call_1/call_2']);
      expect(childIds(child(root, 'call_1/call_2')), ['call_1/call_2/call_1']);
      // Родитель на проводе доступен у вызова и в дереве.
      expect(child(root, 'call_1/call_1').details?.parentToolCallId, 'call_1');
      expect(
        child(
          child(root, 'call_1/call_2'),
          'call_1/call_2/call_1',
        ).details?.parentToolCallId,
        'call_1/call_2',
      );
      expect(root.details?.parentToolCallId, isNull);
    });

    test('«Неизвестный родитель»: the call stays at the top level, no '
        'error', () async {
      await emit(_call('call_5', parent: 'call_9'));

      expect(topCalls().map((c) => c.toolCallId.value), ['call_5']);
      expect(topCall('call_5').details?.parentToolCallId, 'call_9');
      expect(agent.diagnostics, isEmpty);
    });

    test('repeated frames of the same call do not duplicate children '
        '(idempotence by toolCallId, §9)', () async {
      final frames = [
        _agentCall('call_1'),
        _call('call_1/call_1', parent: 'call_1'),
        _call('call_1/call_2', parent: 'call_1'),
      ];
      await emitAll(frames);
      await emitAll(frames);

      expect(topCalls().map((c) => c.toolCallId.value), ['call_1']);
      expect(childIds(topCall('call_1')), ['call_1/call_1', 'call_1/call_2']);
    });

    test('«Реплей без дублей»: loading the session twice in a row keeps '
        'the same number of children', () async {
      Future<SessionHandle> load() async {
        final request = agent.next(sessionLoadMethod);
        final loading = agent.workspace.loadSession(
          const SessionId('s-tree'),
          cwd: '/work',
        );
        final sent = await request;
        for (final frame in [
          {
            'sessionUpdate': 'user_message_chunk',
            'content': {'type': 'text', 'text': 'review it'},
          },
          _agentCall('call_1', type: 'review', status: 'completed'),
          _call('call_1/call_1', parent: 'call_1', status: 'completed'),
          _agentCall(
            'call_1/call_2',
            parent: 'call_1',
            subagentId: 'sub_b2',
            status: 'completed',
          ),
          _call(
            'call_1/call_2/call_1',
            parent: 'call_1/call_2',
            status: 'completed',
          ),
        ]) {
          agent.update('s-tree', frame);
        }
        await pumpEventQueue();
        agent.respond(sent, const <String, Object?>{});
        return loading;
      }

      void expectTree(SessionHandle loaded) {
        final calls = loaded.current.transcript
            .whereType<ToolCallItem>()
            .toList();
        expect(calls.map((c) => c.toolCallId.value), ['call_1']);
        expect(childIds(calls.single), ['call_1/call_1', 'call_1/call_2']);
        expect(childIds(child(calls.single, 'call_1/call_2')), [
          'call_1/call_2/call_1',
        ]);
      }

      expectTree(await load());
      expectTree(await load());
    });
  });

  group('«Запрос в дереве» (D27 п. 4, D47 Т9)', () {
    Future<int> ask(String toolCallId, Map<String, Object?> meta) async {
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
              kind: ToolKind.execute,
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

    PendingApprovalView pending() => session.current.pendingApprovals.single;

    Future<void> grandchildCall() => emitAll([
      _agentCall('call_1', type: 'review'),
      _agentCall(
        'call_1/call_2',
        parent: 'call_1',
        type: 'explore',
        subagentId: 'sub_b2',
      ),
      _call(
        'call_1/call_2/call_1',
        parent: 'call_1/call_2',
        kind: 'execute',
        status: 'pending',
        title: 'Run dart test',
      ),
    ]);

    tearDown(() async {
      // Ход закрывается, чтобы ожидающие запросы не пережили тест.
      agent.respond(prompt, const {'stopReason': 'end_turn'});
      await pumpEventQueue();
    });

    test('the approval is at the root row (childApprovals) and at the nested '
        'row, there is no top-level item, the panel is single', () async {
      await grandchildCall();
      await ask(
        'call_1/call_2/call_1',
        _requester(id: 'sub_b2', type: 'explore', depth: 2),
      );

      expect(topCalls().map((c) => c.toolCallId.value), ['call_1']);
      final root = topCall('call_1');
      expect(root.childApprovals, hasLength(1));
      final waiting = root.childApprovals.single as PendingApprovalView;
      final nested = child(
        child(root, 'call_1/call_2'),
        'call_1/call_2/call_1',
      );
      expect(nested.approval, isA<PendingApprovalView>());
      expect(
        (nested.approval! as PendingApprovalView).approvalId,
        waiting.approvalId,
      );
      // Ожидающее одобрение в сессии одно: решение принимается в одном месте
      // (блок под строкой корня), PERM-4.
      expect(session.current.pendingApprovals, hasLength(1));
    });

    test('the path goes through the tree without `…`', () async {
      await grandchildCall();
      await ask(
        'call_1/call_2/call_1',
        _requester(id: 'sub_b2', type: 'explore', depth: 2),
      );

      expect(pending().subagent!.pathTypes, ['review', 'explore']);
      expect(pending().subagent!.pathText, 'review › explore');
    });

    test('a great-grandchild: the middle link is the type of the agent call '
        'found by climbing parentToolCallId (depth 3, no `…`)', () async {
      await emitAll([
        _agentCall('call_1', type: 'review'),
        _agentCall(
          'call_1/call_2',
          parent: 'call_1',
          type: 'general',
          subagentId: 'sub_b2',
        ),
        _agentCall(
          'call_1/call_2/call_3',
          parent: 'call_1/call_2',
          type: 'explore',
          subagentId: 'sub_c3',
        ),
        _call(
          'call_1/call_2/call_3/call_1',
          parent: 'call_1/call_2/call_3',
          kind: 'execute',
          status: 'pending',
        ),
      ]);
      await ask(
        'call_1/call_2/call_3/call_1',
        _requester(id: 'sub_c3', type: 'explore', depth: 3),
      );

      expect(pending().subagent!.pathTypes, ['review', 'general', 'explore']);
      expect(pending().subagent!.pathText, 'review › general › explore');
    });

    test('a link the tree does not know stays `…`', () async {
      await emitAll([
        _agentCall('call_1', type: 'review'),
        // Вызова `call_1/call_2` (agent) в ходе нет, родитель неизвестен.
        _call(
          'call_1/call_2/call_3/call_1',
          parent: 'call_1/call_2/call_3',
          kind: 'execute',
          status: 'pending',
        ),
      ]);
      await ask(
        'call_1/call_2/call_3/call_1',
        _requester(id: 'sub_c3', type: 'explore', depth: 3),
      );

      expect(pending().subagent!.pathText, 'review › … › explore');
    });

    test('the answer goes once to this request; the outcome is visible at '
        'both rows after the decision', () async {
      await grandchildCall();
      final requestId = await ask(
        'call_1/call_2/call_1',
        _requester(id: 'sub_b2', type: 'explore', depth: 2),
      );

      await session.respond(
        pending().approvalId,
        const PermissionOptionId('allow-once'),
      );
      await pumpEventQueue();

      final responses = [
        for (final m in agent.transport.sentMessages)
          if (m is JsonRpcResponse && m.id == JsonRpcId.integer(requestId)) m,
      ];
      expect(responses, hasLength(1));
      expect(responses.single.result, {
        'outcome': {'outcome': 'selected', 'optionId': 'allow-once'},
      });

      final root = topCall('call_1');
      expect(root.childApprovals, hasLength(1));
      final resolvedAtRoot = root.childApprovals.single as ResolvedApprovalView;
      expect(resolvedAtRoot.outcome, ApprovalOutcomeView.allowed);
      final nested = child(
        child(root, 'call_1/call_2'),
        'call_1/call_2/call_1',
      );
      expect(nested.approval, isA<ResolvedApprovalView>());
      expect(
        (nested.approval! as ResolvedApprovalView).outcome,
        ApprovalOutcomeView.allowed,
      );
    });
  });

  group('«Хвост из пяти вызовов» (D25, Q15, D47 Т9)', () {
    Future<void> runningWithCalls(int count) async {
      await emit(_agentCall('call_1'));
      for (var i = 1; i <= count; i++) {
        await emit(_call('call_1/call_$i', parent: 'call_1'));
      }
      // Строка прогресса несёт токены: kit их не разбирает.
      await emit({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1',
        'content': [
          {
            'type': 'content',
            'content': {
              'type': 'text',
              'text': 'explore · $count tool calls · 12.3k tokens · 9s',
            },
          },
        ],
      });
    }

    test('five calls: the tail is the last three in order of arrival, '
        'moreCount is 2, no tokens', () async {
      await runningWithCalls(5);

      final root = topCall('call_1');
      expect(root.tail.calls.map((c) => c.toolCallId.value), [
        'call_1/call_3',
        'call_1/call_4',
        'call_1/call_5',
      ]);
      expect(root.tail.moreCount, 2);
      expect(root.subtreeCalls, 5);
      for (final call in root.tail.calls) {
        final row = ToolRowFormatter.format(call, cwd: '/work');
        expect('${row.label} ${row.detail}', isNot(contains('tokens')));
        expect('${row.label} ${row.detail}', isNot(contains('12.3k')));
      }
    });

    test('three calls or fewer: all in the tail, moreCount is 0', () async {
      await runningWithCalls(3);

      final root = topCall('call_1');
      expect(root.tail.calls, hasLength(3));
      expect(root.tail.moreCount, 0);
      expect(root.subtreeCalls, 3);
    });

    test('without calls of children the tail is empty (the progress line '
        'is shown instead)', () async {
      await runningWithCalls(0);

      final root = topCall('call_1');
      expect(root.tail.calls, isEmpty);
      expect(root.tail.moreCount, 0);
      expect(root.subtreeCalls, 0);
    });

    test('the tail is ordered by tool_call arrival, not by later updates '
        'of an earlier call', () async {
      await runningWithCalls(4);
      await emit(_finish('call_1/call_1'));

      expect(topCall('call_1').tail.calls.map((c) => c.toolCallId.value), [
        'call_1/call_2',
        'call_1/call_3',
        'call_1/call_4',
      ]);
    });

    test('the subtree counts nested agent calls, their children and '
        'operations, so the counter does not jump on completion', () async {
      await emitAll([
        _agentCall('call_1'),
        _call('call_1/call_1', parent: 'call_1'),
        _agentCall('call_1/call_2', parent: 'call_1', subagentId: 'sub_b2'),
        _call('call_1/call_2/call_1', parent: 'call_1/call_2'),
        // Операция со списком задач потомка — тоже вызов поддерева.
        _call('call_1/call_3', parent: 'call_1', kind: 'think'),
        _plan(['1'], op: 'create', call: 'call_1/call_3', changed: ['1']),
        _finish('call_1/call_3'),
      ]);

      // read + nested agent + its read + operation = 4 (как `toolCalls`
      // итога, D24).
      final running = topCall('call_1').subtreeCalls;
      expect(running, 4);

      await emit(
        _finish(
          'call_1',
          subagent: {
            'id': 'sub_a1',
            'summary': {
              'toolCalls': 4,
              'tokens': {'input': 1000, 'output': 200},
              'durationMs': 5000,
            },
          },
        ),
      );
      expect(topCall('call_1').subtreeCalls, running);
      expect(topCall('call_1').details?.subagentSummary?.toolCalls, running);
    });
  });

  group('«Операции ребёнка в дереве» (D27, D35, D47 Т9, D48 п. 3)', () {
    Future<void> op(
      String id, {
      String? parent,
      required String taskId,
      required List<String> plan,
    }) async {
      await emit(_call(id, parent: parent, kind: 'think'));
      await emit(_plan(plan, op: 'create', call: id, changed: [taskId]));
      await emit(_finish(id));
    }

    test('the operations of the child merge under its agent row; the root '
        'operation between them stays a separate top-level item', () async {
      await emit(_agentCall('call_1'));
      await op('call_1/call_2', parent: 'call_1', taskId: '1', plan: ['1']);
      await op('call_4', taskId: '2', plan: ['1', '2']);
      await op(
        'call_1/call_3',
        parent: 'call_1',
        taskId: '3',
        plan: ['1', '2', '3'],
      );

      // Верхний уровень: строка `agent` и тихая строка операции корня.
      expect(top().map((i) => i.runtimeType), [
        UserItem,
        ToolCallItem,
        TaskOpsItem,
      ]);
      final rootOps = top().whereType<TaskOpsItem>().single;
      expect(rootOps.added, ['2']);
      expect(rootOps.text, 'Task #2 added to the plan');

      // Под `call_1` — один вложенный элемент с обоими изменениями.
      final nested = topCall('call_1').children;
      expect(nested.whereType<ToolCallItem>(), isEmpty);
      expect(nested, hasLength(1));
      final childOps = nested.single as TaskOpsItem;
      expect(childOps.added, ['1', '3']);
      expect(childOps.text, 'Tasks #1, #3 added to the plan');
    });

    test('the operations of a child and of its grandchild do not merge '
        '(different parents)', () async {
      await emit(_agentCall('call_1'));
      await emit(
        _agentCall('call_1/call_2', parent: 'call_1', subagentId: 'sub_b2'),
      );
      await op(
        'call_1/call_2/call_1',
        parent: 'call_1/call_2',
        taskId: '1',
        plan: ['1'],
      );
      await op(
        'call_1/call_3',
        parent: 'call_1',
        taskId: '2',
        plan: ['1', '2'],
      );

      final root = topCall('call_1');
      final grandchildOps = child(root, 'call_1/call_2').children;
      expect(grandchildOps.whereType<TaskOpsItem>(), hasLength(1));
      expect((grandchildOps.single as TaskOpsItem).added, ['1']);
      final rootChildren = root.children;
      expect(rootChildren.whereType<TaskOpsItem>(), hasLength(1));
      expect(rootChildren.whereType<TaskOpsItem>().single.added, [
        '2',
      ], reason: 'операция ребёнка не сливается с операцией внука');
    });

    test(
      'a failed operation of a child stays an ordinary nested call',
      () async {
        await emit(_agentCall('call_1'));
        await emit(_call('call_1/call_2', parent: 'call_1', kind: 'think'));
        await emit(_finish('call_1/call_2', status: 'failed'));

        final root = topCall('call_1');
        expect(root.children.whereType<TaskOpsItem>(), isEmpty);
        expect(
          child(root, 'call_1/call_2').details?.status,
          ToolCallStatusView.failed,
        );
      },
    );
  });
}
