// Характеризация сессий `CodeLabShellCubit` (задача 5.0, tasks 1.2).
//
// Фиксирует создание и выбор сессии, пересчёт флагов занятости при выборе
// и независимость очередей промптов разных сессий. Текст тестов не меняется
// до конца change (design D1).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
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

  // D20 change `require-project-folder`: при выбранном проекте «New session»
  // стартует агента (D13). Прежний смысл — «до готовности соединения агенту
  // ничего не уходит» — сохранён: `session/new` не уходит до ответа на
  // `initialize`, после него уходит ровно один.
  test('createSession() sends session/new only after the agent answered '
      'initialize, and exactly one', () async {
    final agent = FakeAcpTransport()..autoRespondToInitialize = false;
    final h = ShellHarness(agent: agent);
    await h.projectReady();
    final initialize = h.nextSent(initializeMethod);

    final creating = h.cubit.createSession();
    final init = await initialize as JsonRpcRequest;
    await pumpEventQueue();
    expect(
      agent.sentMessages.whereType<JsonRpcRequest>().where(
        (r) => r.method == sessionNewMethod,
      ),
      isEmpty,
    );
    expect(h.cubit.state.sessions, isEmpty);

    final sessionNew = h.nextSent(sessionNewMethod);
    agent.emitInbound(
      JsonRpcMessage.response(
        id: init.id,
        result: InitializeResponse(
          protocolVersion: const ProtocolVersion(1),
          agentCapabilities: const AgentCapabilities(),
        ).toJson(),
      ),
    );
    final request = await sessionNew as JsonRpcRequest;
    agent.emitInbound(
      JsonRpcMessage.response(id: request.id, result: {'sessionId': 's1'}),
    );
    await creating;

    expect(
      agent.sentMessages.whereType<JsonRpcRequest>().where(
        (r) => r.method == sessionNewMethod,
      ),
      hasLength(1),
    );
    expect(h.cubit.state.activeSessionId, 's1');
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
