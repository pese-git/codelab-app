// Запрос одобрения от субагента в kit (задача 3.1 `[client]` change
// `add-subagents-and-tasks`; spec acp-client-kit «Запрос одобрения от
// субагента»: сценарии «Запрос ребёнка», «Путь внука без дерева», «Запрос
// ребёнка не делает вызов вызовом agent», «Запрос ребёнка без строки корня»,
// «Тип звена по умолчанию», «Запрос без сведений о субагенте»;
// design.md, D15, D27 п. 4, D43 п. 1, 2, 4).
//
// Красные тесты: у `PendingApprovalView` и `ToolCallView` нет поля
// `subagent`, нет типа `SubagentRequester`, у `ToolCallItem` нет
// `childApprovals` — файл не компилируется, пока задача 3.4 не добавит их.
// Имена, выбранные здесь, предложение этой задачи (spec их не задаёт, кроме
// `subagent`, `SubagentRequester` и `pathTypes`):
//   `SubagentRequester.pathText` — строка пути `review › explore`;
//   `ToolCallItem.childApprovals` — одобрения потомков, доступные у строки
//     вызова `agent` корня (ожидающие и решённые, в порядке прихода).
// Смысл ключа `_meta.codelab.subagent` задаёт вид кадра (D43 п. 1): здесь он
// стоит в `toolCall` запроса разрешения — спрашивает потомок.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

/// Первый кадр вызова `agent` корня; [type] — `rawInput.type` (`null` — без
/// типа), [subagentType] — `subagentCall.type` из `_meta.codelab.subagent`.
Map<String, Object?> _agentCall(
  String id, {
  String? type = 'review',
  String subagentType = 'review',
}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': 'Subagent $subagentType: Check the diff',
  'kind': 'think',
  'status': 'in_progress',
  'rawInput': {'type': ?type, 'description': 'Check the diff'},
  '_meta': {
    'codelab': {
      'subagent': {'id': 'sub_a1', 'type': subagentType},
    },
  },
};

/// `_meta.codelab.subagent` запроса разрешения потомка (D8, D43 п. 1).
Map<String, Object?> _requesterMeta({
  String id = 'sub_a1',
  String type = 'review',
  int depth = 1,
  String parent = 'call_3',
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
    agent = KitAgent();
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

  /// Запрос разрешения потомка; [meta] — `toolCall._meta` (`null` — без).
  Future<int> ask(String toolCallId, {Map<String, Object?>? meta}) async {
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

  List<ToolCallItem> calls() =>
      session.current.transcript.whereType<ToolCallItem>().toList();

  ToolCallItem call(String id) =>
      calls().singleWhere((item) => item.toolCallId == ToolCallId(id));

  tearDown(() async {
    // Ход нужно закрыть: незавершённый ход держит ожидающие запросы.
    agent.respond(prompt, const {'stopReason': 'end_turn'});
    await pumpEventQueue();
  });

  group('SubagentRequester from the permission request (D15, D43 p. 1)', () {
    test('a child request gives subagent with the path `review`; the answer '
        'goes to this request (PERM-4)', () async {
      await emit(_agentCall('call_3'));
      final requestId = await ask('call_3/call_1', meta: _requesterMeta());

      expect(
        pending().subagent,
        const SubagentRequester(
          id: 'sub_a1',
          type: 'review',
          description: 'Check the diff',
          depth: 1,
          parentToolCallId: 'call_3',
        ),
      );
      expect(pending().subagent!.pathTypes, ['review']);
      expect(pending().subagent!.pathText, 'review');

      final answered = agent.transport.sent
          .where((m) => m is JsonRpcResponse)
          .cast<JsonRpcResponse>()
          .first;
      await session.respond(
        pending().approvalId,
        const PermissionOptionId('reject-once'),
      );
      final response = await answered;
      expect(response.id, JsonRpcId.integer(requestId));
      expect(response.result, {
        'outcome': {'outcome': 'selected', 'optionId': 'reject-once'},
      });
    });

    test('a grandchild without a tree: `review › explore`, at depth 3 '
        '`review › … › explore`', () async {
      await emit(_agentCall('call_3'));
      await ask(
        'call_3/call_1/call_1',
        meta: _requesterMeta(id: 'sub_b2', type: 'explore', depth: 2),
      );
      expect(pending().subagent!.pathTypes, ['review', 'explore']);
      expect(pending().subagent!.pathText, 'review › explore');

      await ask(
        'call_3/call_1/call_2/call_1',
        meta: _requesterMeta(id: 'sub_c3', type: 'explore', depth: 3),
      );
      final deep = session.current.pendingApprovals.last.subagent!;
      expect(deep.pathTypes, ['review', '…', 'explore']);
      expect(deep.pathText, 'review › … › explore');
      expect(deep.pathTypes, hasLength(deep.depth));
    });

    test('the first link falls back to rawInput.type, then to `…` '
        '(D43 p. 4)', () async {
      // Вызов `agent` с `subagentCall.type`, но без `rawInput.type`: берём
      // `subagentCall.type` (в нём уже учтён тип `general` по умолчанию).
      await emit(_agentCall('call_3', type: null, subagentType: 'general'));
      await ask(
        'call_3/call_1/call_1',
        meta: _requesterMeta(type: 'explore', depth: 2),
      );
      expect(pending().subagent!.pathText, 'general › explore');
    });

    test('subagentCall.type of the root wins over rawInput.type '
        '(D43 p. 4)', () async {
      // Оба источника заданы и различаются: порядок `subagentCall.type` →
      // `rawInput.type` не должен поменяться местами.
      await emit(_agentCall('call_3', type: 'review', subagentType: 'general'));
      await ask(
        'call_3/call_1/call_1',
        meta: _requesterMeta(type: 'explore', depth: 2),
      );
      expect(pending().subagent!.pathText, 'general › explore');
    });

    test('a first link of an unknown call is `…`', () async {
      // Строки `call_9` в ходе нет: ни `subagentCall`, ни `rawInput`.
      await ask(
        'call_9/call_1/call_1',
        meta: _requesterMeta(type: 'explore', depth: 2, parent: 'call_9'),
      );
      expect(pending().subagent!.pathText, '… › explore');
    });

    test('a request without _meta.codelab.subagent has subagent == null even '
        'with `/` in the id; the id stays an opaque string', () async {
      await emit(_agentCall('call_3'));
      await ask('call_3/call_1');

      expect(pending().subagent, isNull);
      expect(
        calls().map((c) => c.toolCallId.value),
        contains('call_3/call_1'),
        reason: 'без сведений о субагенте запрос — обычный, со своей строкой',
      );
      expect(call('call_3/call_1').details?.subagent, isNull);
    });

    test(
      'a wrong shape of the request meta gives null without failing',
      () async {
        await emit(_agentCall('call_3'));
        await ask(
          'call_3/call_1',
          meta: {
            'codelab': {'subagent': 'sub_a1'},
          },
        );
        await ask(
          'call_3/call_2',
          meta: {
            'codelab': {
              'subagent': {'id': 5, 'type': 'review'},
            },
          },
        );

        for (final approval in session.current.pendingApprovals) {
          expect(approval.subagent, isNull);
        }
        expect(agent.diagnostics, isEmpty);
      },
    );
  });

  group('a child request is not an agent call (D43 p. 1)', () {
    test('subagentCall and subagentSummary of the child record stay null, '
        'the requester is kept separately', () async {
      await emit(_agentCall('call_1', subagentType: 'review'));
      await ask('call_1/call_1', meta: _requesterMeta(parent: 'call_1'));

      // Запись ребёнка: `exec` не становится строкой «Subagent …».
      final child = session.current.pendingApprovals.single;
      expect(child.subagent?.type, 'review');
      final root = call('call_1');
      expect(root.details?.subagentCall?.id, 'sub_a1');
      expect(root.details?.subagentSummary, isNull);
    });

    test('the request does not change the root agent call', () async {
      await emit(_agentCall('call_1', subagentType: 'review'));
      final before = call('call_1').details;
      await ask('call_1/call_1', meta: _requesterMeta(parent: 'call_1'));

      expect(call('call_1').details, before);
    });
  });

  group('the title of the child call (review: D8 prefix)', () {
    test(
      'the pending child approval carries the title of its tool call',
      () async {
        await emit(_agentCall('call_1', subagentType: 'review'));
        await ask('call_1/call_1', meta: _requesterMeta(parent: 'call_1'));

        expect(pending().toolTitle, 'Run dart test');
        final child =
            call('call_1').childApprovals.single as PendingApprovalView;
        expect(child.toolTitle, 'Run dart test');
      },
    );
  });

  group('no separate item while the root row exists (D43 p. 2)', () {
    test('the child call has no transcript item; the approval is at the root '
        'row and its outcome stays there after the decision', () async {
      await emit(_agentCall('call_1', subagentType: 'review'));
      await ask('call_1/call_1', meta: _requesterMeta(parent: 'call_1'));

      expect(calls().map((c) => c.toolCallId.value), [
        'call_1',
      ], reason: 'отдельной строки у call_1/call_1 нет');
      final waiting = call('call_1').childApprovals.single;
      expect(waiting, isA<PendingApprovalView>());
      expect((waiting as PendingApprovalView).subagent?.type, 'review');

      await session.respond(
        pending().approvalId,
        const PermissionOptionId('reject-once'),
      );

      expect(calls().map((c) => c.toolCallId.value), ['call_1']);
      final resolved = call('call_1').childApprovals.single;
      expect(resolved, isA<ResolvedApprovalView>());
      expect(
        (resolved as ResolvedApprovalView).outcome,
        ApprovalOutcomeView.rejected,
      );
    });

    test('an announced child call keeps its approval on its own row '
        '(D43 p. 2)', () async {
      // Под строку корня переезжает только вызов «только запрос» (без кадра
      // `tool_call`). Если вызов потомка объявлен (будущий режим дерева), у
      // него своя строка, и одобрение остаётся на ней, а не дублируется
      // в `childApprovals` корня.
      await emit(_agentCall('call_3'));
      await emit({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call_3/call_1',
        'title': 'Run dart test',
        'kind': 'execute',
        'status': 'pending',
      });
      await ask('call_3/call_1', meta: _requesterMeta());

      expect(call('call_3/call_1').approval, isA<PendingApprovalView>());
      expect(call('call_3').childApprovals, isEmpty);
    });

    test('without the root row the call is shown by the old item at the end '
        'of the turn, with subagent and the path', () async {
      await emit({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'before'},
      });
      await ask('call_9/call_1', meta: _requesterMeta(parent: 'call_9'));

      final item = calls().single;
      expect(item.toolCallId.value, 'call_9/call_1');
      expect(session.current.transcript.last, same(item));
      expect(item.details?.subagent?.type, 'review');
      expect(item.details?.subagent?.pathText, 'review');
      expect((item.approval! as PendingApprovalView).subagent?.type, 'review');
      expect(item.details?.subagentCall, isNull);
    });

    test('subagent info stays on the record after the decision', () async {
      await emit({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'x'},
      });
      await ask('call_9/call_1', meta: _requesterMeta(parent: 'call_9'));
      await session.respond(
        pending().approvalId,
        const PermissionOptionId('allow-once'),
      );

      expect(calls().single.details?.subagent?.id, 'sub_a1');
    });
  });
}
