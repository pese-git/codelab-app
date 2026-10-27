// Характеризация промптов и очереди `CodeLabShellCubit` (задача 5.0,
// tasks 1.3).
//
// Фиксирует флаги хода, транскрипт, постановку в очередь во время хода,
// операции очереди по id и её слив после конца хода. Текст тестов не
// меняется до конца change (design D1).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import '../../../../support/transcript_rows.dart';

void main() {
  setUp(setUpCharacterization);

  test('a turn is busy until stopReason and records the exchange', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');

    final turn = await h.startTurn('  hello agent  ');
    expect(turn.request.params, containsPair('sessionId', 'session-1'));
    expect(
      turn.request.params,
      containsPair('prompt', [
        {'type': 'text', 'text': 'hello agent'},
      ]),
    );
    expect(h.cubit.state.isPromptSubmitting, isTrue);
    expect(h.cubit.state.canCancel, isTrue);
    expect(h.cubit.state.transcriptRows.last.kind, 'user');
    expect(h.cubit.state.transcriptRows.last.text, 'hello agent');

    h
      ..agentText('session-1', 'hi ')
      ..agentText('session-1', 'there');
    expect(h.cubit.state.transcriptRows.last.kind, 'agent');
    expect(h.cubit.state.transcriptRows.last.text, 'hi there');
    expect(h.cubit.state.isPromptSubmitting, isTrue);

    h.endTurn(turn.request);
    await turn.done;

    expect(h.cubit.state.isPromptSubmitting, isFalse);
    expect(h.cubit.state.canCancel, isFalse);
    expect(h.cubit.state.transcriptRows.map((entry) => entry.kind), [
      'user',
      'agent',
    ]);
    expect(h.logEvents, contains('Prompt completed with stopReason endTurn.'));
  });

  test('a blank prompt is ignored', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final sentBefore = h.agent.sentMessages.length;

    await h.cubit.submitPrompt('   ');

    expect(h.agent.sentMessages, hasLength(sentBefore));
    expect(h.cubit.state.transcriptRows, isEmpty);
  });

  test('a prompt without an active session is not sent', () async {
    final h = ShellHarness();
    await h.connect();

    await h.cubit.submitPrompt('hello');

    expect(h.sentAfterInitialize(), isEmpty);
    expect(
      h.logEvents,
      contains('Create or select a session before sending a prompt.'),
    );
  });

  test('prompts submitted during a turn are queued and edited, deleted, '
      'sent and cleared by id', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('first');
    final sentDuringTurn = h.agent.sentMessages.length;

    for (final text in ['one', 'two', 'three', 'four']) {
      await h.cubit.submitPrompt(text);
    }
    expect(h.agent.sentMessages, hasLength(sentDuringTurn));
    final queue = h.cubit.state.queuedPrompts;
    expect(queue.map((item) => item.content), ['one', 'two', 'three', 'four']);
    expect(queue.map((item) => item.id).toSet(), hasLength(4));
    String idOf(String text) => h.cubit.state.queuedPrompts
        .firstWhere((item) => item.content == text)
        .id;

    h.cubit.editQueuedPrompt(idOf('one'));
    expect(h.cubit.state.composerDraft, 'one');
    expect(h.cubit.state.queuedPrompts.map((item) => item.content), [
      'two',
      'three',
      'four',
    ]);

    h.cubit.deleteQueuedPrompt(idOf('three'));
    expect(h.cubit.state.queuedPrompts.map((item) => item.content), [
      'two',
      'four',
    ]);

    // Сессия занята: «отправить сейчас» ничего не делает и не двигает элемент.
    await h.cubit.sendQueuedPromptNow(idOf('four'));
    expect(h.cubit.state.queuedPrompts.map((item) => item.content), [
      'two',
      'four',
    ]);
    expect(h.agent.sentMessages, hasLength(sentDuringTurn));

    final drained = h.nextSent(sessionPromptMethod);
    h.endTurn(turn.request);
    final second = await drained as JsonRpcRequest;
    expect(
      second.params,
      containsPair('prompt', [
        {'type': 'text', 'text': 'two'},
      ]),
    );
    expect(h.cubit.state.queuedPrompts.map((item) => item.content), ['four']);
    expect(h.cubit.state.isPromptSubmitting, isTrue);

    h.cubit.clearQueuedPrompts();
    expect(h.cubit.state.queuedPrompts, isEmpty);

    final sentBeforeEnd = h.agent.sentMessages.length;
    h.endTurn(second);
    await turn.done;
    expect(h.agent.sentMessages, hasLength(sentBeforeEnd));
    expect(h.cubit.state.isPromptSubmitting, isFalse);
  });

  test('the queue drains one prompt per turn in FIFO order', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('first');
    await h.cubit.submitPrompt('second');
    await h.cubit.submitPrompt('third');

    final sentTexts = <String>[];
    var current = turn.request;
    for (var i = 0; i < 2; i++) {
      final next = h.nextSent(sessionPromptMethod);
      h.endTurn(current);
      current = await next as JsonRpcRequest;
      final prompt = (current.params! as Map)['prompt'] as List;
      sentTexts.add((prompt.single as Map)['text'] as String);
    }
    h.endTurn(current);
    await turn.done;

    expect(sentTexts, ['second', 'third']);
    expect(h.cubit.state.queuedPrompts, isEmpty);
    expect(h.cubit.state.isPromptSubmitting, isFalse);
  });

  test('a send failure is reported and leaves the session free', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');

    final turn = await h.startTurn('will fail');
    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: turn.request.id,
        error: const JsonRpcError(code: -32603, message: 'agent crashed'),
      ),
    );
    await turn.done;

    expect(h.cubit.state.isPromptSubmitting, isFalse);
    expect(h.cubit.state.canCancel, isFalse);
    expect(h.logEvents, contains(startsWith('Failed to send prompt')));
  });
}
