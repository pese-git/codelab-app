// `ToolCallRecord.parentToolCallId` из `_meta.codelab.parentToolCallId`
// (задача 5.1, часть kit `[client]`, change `add-subagents-and-tasks`; spec
// acp-client-kit «Дерево вызовов потомков»; design.md, D21, D47 Т9; реализация
// — задача 5.4).
//
// Красный тест: поле есть как заглушка (всегда `null`), разбор не написан, и
// тесты падают на сравнениях. Правило терпимое, как у `outcome`: не строка —
// `null` без отказа обработки; поздний кадр без поля родителя не стирает его.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');
const _turn = PromptTurn(
  id: PromptTurnId('turn-1'),
  sessionId: _session,
  prompt: [ContentBlock.text(text: 'go')],
);

const _child = ToolCallId('call_1/call_1');

Map<String, Object?> _meta(Object? parent) => {
  'codelab': {'parentToolCallId': parent},
};

SessionUpdate _call({Map<String, Object?>? meta, ToolCallStatus? status}) =>
    SessionUpdate.toolCall(
      toolCall: ToolCall(
        toolCallId: _child,
        title: 'Read lib/a.dart',
        status: status ?? ToolCallStatus.inProgress,
        meta: meta,
      ),
    );

SessionUpdate _update({Map<String, Object?>? meta, ToolCallStatus? status}) =>
    SessionUpdate.toolCallUpdate(
      toolCallUpdate: ToolCallUpdate(
        toolCallId: _child,
        status: status,
        meta: meta,
      ),
    );

ToolCallRecord? _apply(List<SessionUpdate> updates) {
  var session = SessionStateMachine.startTurn(
    const AcpSession(id: _session, cwd: '/workspace'),
    _turn,
  ).stateOrThrow;
  for (final update in updates) {
    session = SessionStateMachine.applyUpdate(session, update).stateOrThrow;
  }
  return session.turns.last.toolCalls[_child];
}

void main() {
  group('parentToolCallId of a tool call record (D21, D47 Т9)', () {
    test('tool_call takes the parent from _meta.codelab.parentToolCallId', () {
      final record = _apply([_call(meta: _meta('call_1'))]);

      expect(record?.parentToolCallId, 'call_1');
    });

    test('a frame without _meta gives no parent (a root call)', () {
      final record = _apply([_call()]);

      expect(record, isNotNull);
      expect(record?.parentToolCallId, isNull);
    });

    test('a wrong shape gives null without failing the update', () {
      for (final bad in <Object?>[
        5,
        true,
        ['call_1'],
        {'a': 1},
        '',
      ]) {
        final record = _apply([_call(meta: _meta(bad))]);

        expect(record, isNotNull, reason: '$bad');
        expect(record?.parentToolCallId, isNull, reason: '$bad');
      }
    });

    test('tool_call_update before tool_call also sets the parent', () {
      final record = _apply([
        _update(meta: _meta('call_1'), status: ToolCallStatus.inProgress),
      ]);

      expect(record?.parentToolCallId, 'call_1');
    });

    test('a later update without the field keeps the parent', () {
      final record = _apply([
        _call(meta: _meta('call_1')),
        _update(status: ToolCallStatus.completed),
      ]);

      expect(record?.parentToolCallId, 'call_1');
      expect(record?.status, ToolCallStatus.completed);
    });

    test(
      'a repeated tool_call (replay) without the field keeps the parent',
      () {
        final record = _apply([
          _call(meta: _meta('call_1')),
          _call(status: ToolCallStatus.completed),
        ]);

        expect(record?.parentToolCallId, 'call_1');
      },
    );
  });
}
