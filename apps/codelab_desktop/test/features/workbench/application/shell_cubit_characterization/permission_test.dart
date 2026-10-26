// Характеризация одобрений `CodeLabShellCubit` (задача 5.0, tasks 1.6).
//
// Фиксирует запись с ожидающим одобрением по `toolCallId`, ответ выбранным
// `optionId` в запрос агента и независимость одобрений разных сессий
// (`AGENTS.md` §10, PERM-003). Текст тестов не меняется до конца change
// (design D1).

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Object? _selectedOption(JsonRpcResponse response) =>
    ((response.result! as Map)['outcome'] as Map)['optionId'];

void main() {
  setUp(setUpCharacterization);

  test('a permission request shows a pending approval for its tool call; '
      'the chosen optionId answers that request', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('run a command');

    h.requestPermission(
      id: 7,
      sessionId: 'session-1',
      toolCallId: 'tool-1',
      title: 'Run command',
    );

    expect(h.pendingApprovalTitles(), ['Run command']);
    final pending =
        h.cubit.state.transcriptEntries
                .singleWhere(
                  (entry) => entry.approval is CodeLabTranscriptApprovalPending,
                )
                .approval!
            as CodeLabTranscriptApprovalPending;
    expect(pending.command, 'echo hi');
    expect(pending.options.map((option) => option.id), [
      'allow-once',
      'reject-once',
    ]);
    expect(h.cubit.state.isPromptSubmitting, isTrue);
    expect(h.cubit.state.canCancel, isTrue);

    final responseFuture = h.nextResponse();
    final respond = h.cubit.respondToApproval(
      approvalId: const ApprovalRequestId('permission-7'),
      sessionId: const SessionId('session-1'),
      optionId: 'allow-once',
    );
    expect(h.cubit.state.isRespondingToApproval, isTrue);
    final response = await responseFuture;
    await respond;

    expect(response.id, const JsonRpcId.integer(7));
    expect(_selectedOption(response), 'allow-once');
    expect(h.cubit.state.isRespondingToApproval, isFalse);
    expect(h.pendingApprovalTitles(), isEmpty);
    expect(
      h.cubit.state.transcriptEntries
          .where((entry) => entry.approval is CodeLabTranscriptApprovalResolved)
          .map((entry) => entry.title),
      ['Run command'],
    );

    h.endTurn(turn.request);
    await turn.done;
  });

  test('answering an approval in one session leaves the other session '
      'pending', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-a');
    final turnA = await h.startTurn('task a');
    h.requestPermission(
      id: 1,
      sessionId: 'session-a',
      toolCallId: 'tool-a',
      title: 'Run in A',
    );

    await h.createSession('session-b');
    final turnB = await h.startTurn('task b');
    h.requestPermission(
      id: 2,
      sessionId: 'session-b',
      toolCallId: 'tool-b',
      title: 'Run in B',
    );
    expect(h.pendingApprovalTitles(), ['Run in B']);

    final responseFuture = h.nextResponse();
    await h.cubit.respondToApproval(
      approvalId: const ApprovalRequestId('permission-2'),
      sessionId: const SessionId('session-b'),
      optionId: 'reject-once',
    );
    final response = await responseFuture;
    expect(response.id, const JsonRpcId.integer(2));
    expect(_selectedOption(response), 'reject-once');
    expect(h.pendingApprovalTitles(), isEmpty);

    h.cubit.selectSession('session-a');
    expect(h.pendingApprovalTitles(), ['Run in A']);
    expect(h.cubit.state.isPromptSubmitting, isTrue);

    await h.cubit.respondToApproval(
      approvalId: const ApprovalRequestId('permission-1'),
      sessionId: const SessionId('session-a'),
      optionId: 'allow-once',
    );
    h
      ..endTurn(turnA.request)
      ..endTurn(turnB.request);
    await Future.wait([turnA.done, turnB.done]);
  });
}
