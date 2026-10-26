// Характеризация отмены хода `CodeLabShellCubit` (задача 5.0, tasks 1.4).
//
// Фиксирует отправку `session/cancel`, флаги до и после ответа агента,
// слив очереди после отмены и отказ без активной сессии. Текст тестов не
// меняется до конца change (design D1).

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUp(setUpCharacterization);

  test('cancelTurn() sends session/cancel; the session stays busy until the '
      'agent answers the prompt', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('cancel this');
    h.sessionUpdate('session-1', {
      'sessionUpdate': 'tool_call',
      'toolCallId': 'call-1',
      'title': 'dart test',
      'kind': 'execute',
      'status': 'in_progress',
    });

    final cancelFuture = h.nextSent(sessionCancelMethod);
    await h.cubit.cancelTurn();
    final cancel = await cancelFuture as JsonRpcNotification;

    expect(cancel.params, containsPair('sessionId', 'session-1'));
    expect(h.cubit.state.canCancel, isFalse);
    expect(h.cubit.state.isPromptSubmitting, isTrue);
    expect(
      h.cubit.state.transcriptEntries
          .singleWhere((entry) => entry.toolCall != null)
          .toolCall
          ?.status,
      AcpToolCallStatus.cancelled,
    );

    h.endTurn(turn.request, stopReason: 'cancelled');
    await turn.done;

    expect(h.cubit.state.isPromptSubmitting, isFalse);
    expect(h.cubit.state.canCancel, isFalse);
  });

  test('a prompt queued while cancelling is sent after the cancelled turn '
      'ends', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('cancel this');
    await h.cubit.cancelTurn();

    final sentBefore = h.agent.sentMessages.length;
    await h.cubit.submitPrompt('next');
    expect(h.cubit.state.queuedPrompts.map((item) => item.content), ['next']);
    expect(h.agent.sentMessages, hasLength(sentBefore));

    final nextFuture = h.nextSent(sessionPromptMethod);
    h.endTurn(turn.request, stopReason: 'cancelled');
    final next = await nextFuture as JsonRpcRequest;
    expect(
      next.params,
      containsPair('prompt', [
        {'type': 'text', 'text': 'next'},
      ]),
    );
    expect(h.cubit.state.queuedPrompts, isEmpty);

    h.endTurn(next);
    await turn.done;
    expect(h.cubit.state.isPromptSubmitting, isFalse);
  });

  test('cancelTurn() without an active session sends nothing', () async {
    final h = ShellHarness();
    await h.connect();

    await h.cubit.cancelTurn();

    expect(h.sentAfterInitialize(), isEmpty);
    expect(
      h.logEvents,
      contains('Select a session before cancelling a prompt turn.'),
    );
  });
}
