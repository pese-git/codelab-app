// Характеризация сессий `CodeLabShellCubit` (задача 5.0, tasks 1.2).
//
// Фиксирует создание и выбор сессии, пересчёт флагов занятости при выборе
// и независимость очередей промптов разных сессий. Текст тестов не меняется
// до конца change (design D1).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import '../../../../support/transcript_rows.dart';

void main() {
  setUp(setUpCharacterization);

  test('createSession() sends session/new with the selected project as cwd '
      'and makes the session active', () async {
    final h = ShellHarness();
    await h.cubit.selectProject('/workspace');
    await h.connect();

    final request = await h.createSession('session-1');

    expect(request.params, containsPair('cwd', '/workspace'));
    expect(h.cubit.state.activeSessionId, 'session-1');
    expect(h.cubit.state.sessions.map((item) => item.id), ['session-1']);
    expect(h.cubit.state.currentSessionLabel, 'New session');
    expect(h.cubit.state.currentSessionDetail, '/workspace');
    expect(h.cubit.state.transcriptRows, isEmpty);
    expect(h.cubit.state.isPromptSubmitting, isFalse);
    expect(h.cubit.state.canCancel, isFalse);
  });

  test('a newer session is listed first and becomes active', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    await h.createSession('session-2');

    expect(h.cubit.state.sessions.map((item) => item.id), [
      'session-2',
      'session-1',
    ]);
    expect(h.cubit.state.activeSessionId, 'session-2');
  });

  test('createSession() before connecting sends nothing', () async {
    final h = ShellHarness();

    await h.cubit.createSession();

    expect(h.agent.sentMessages, isEmpty);
    expect(h.cubit.state.sessions, isEmpty);
    expect(
      h.logEvents,
      contains('Connect an ACP agent before creating a session.'),
    );
  });

  test('selectSession() recomputes isPromptSubmitting and canCancel from the '
      'selected session', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('long task');
    expect(h.cubit.state.isPromptSubmitting, isTrue);

    await h.createSession('session-2');
    expect(h.cubit.state.activeSessionId, 'session-2');
    expect(h.cubit.state.isPromptSubmitting, isFalse);
    expect(h.cubit.state.canCancel, isFalse);

    h.cubit.selectSession('session-1');
    expect(h.cubit.state.isPromptSubmitting, isTrue);
    expect(h.cubit.state.canCancel, isTrue);
    expect(h.cubit.state.transcriptRows.last.text, 'long task');

    h.cubit.selectSession('session-2');
    expect(h.cubit.state.isPromptSubmitting, isFalse);
    expect(h.cubit.state.transcriptRows, isEmpty);

    h.endTurn(turn.request);
    await turn.done;
    expect(h.cubit.state.sessions.map((item) => item.id), [
      'session-1',
      'session-2',
    ]);
    expect(h.cubit.state.activeSessionId, 'session-2');
  });

  test('a background session update does not change the active session '
      'view', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('in background');
    await h.createSession('session-2');

    h.agentText('session-1', 'background reply');

    expect(h.cubit.state.activeSessionId, 'session-2');
    expect(h.cubit.state.transcriptRows, isEmpty);

    h.endTurn(turn.request);
    await turn.done;
    h.cubit.selectSession('session-1');
    expect(h.cubit.state.transcriptRows.last.text, 'background reply');
  });

  test('each session has its own prompt queue', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('first');
    await h.cubit.submitPrompt('queued for session-1');
    expect(h.cubit.state.queuedPrompts.map((item) => item.content), [
      'queued for session-1',
    ]);

    await h.createSession('session-2');
    expect(h.cubit.state.queuedPrompts, isEmpty);

    h.cubit.selectSession('session-1');
    expect(h.cubit.state.queuedPrompts, hasLength(1));

    h.cubit.selectSession('session-2');
    final drained = h.nextSent(sessionPromptMethod);
    h.endTurn(turn.request);
    final next = await drained as JsonRpcRequest;
    expect(next.params, containsPair('sessionId', 'session-1'));
    expect(h.cubit.state.queuedPrompts, isEmpty);

    h.endTurn(next);
    await turn.done;
    h.cubit.selectSession('session-1');
    expect(h.cubit.state.queuedPrompts, isEmpty);
  });
}
