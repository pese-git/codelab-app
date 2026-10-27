// Состояния соединения и сбои хода в рабочем месте (tasks 4.1, 4.4 change
// `add-connection-and-error-states`; spec agent-workbench-ui «Connection
// banner above a non-empty transcript», «Failed turn notice with Retry»,
// «Workbench честно отражает спонтанную потерю соединения»).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_cubit_characterization/harness.dart';

void main() {
  setUp(setUpCharacterization);

  /// Ответ-ошибка агента CodeLab на `session/prompt` с `data.codelab`.
  void failTurn(
    ShellHarness h,
    JsonRpcRequest prompt, {
    required String errorClass,
    required String message,
    required bool retryable,
  }) => h.agent.emitInbound(
    JsonRpcMessage.response(
      id: prompt.id,
      error: JsonRpcError(
        code: -32603,
        message: 'Turn failed',
        data: <String, Object?>{
          'codelab': <String, Object?>{
            'errorClass': errorClass,
            'message': message,
            'retryable': retryable,
          },
        },
      ),
    ),
  );

  CodeLabTranscriptEntry errorEntry(ShellHarness h) => h
      .cubit
      .state
      .transcriptEntries
      .lastWhere((entry) => entry.id.startsWith('prompt-error-'));

  group('failureTitleOf', () {
    test('maps each failure class to its title', () {
      String title(String? errorClass) => failureTitleOf(
        PromptFailure.agent(errorClass: errorClass, message: 'm'),
      );

      expect(
        title('auth'),
        'The agent could not sign in to the model provider',
      );
      expect(title('network'), 'The model provider is unavailable');
      expect(title('timeout'), 'The model provider is unavailable');
      expect(title('server'), 'The model provider is unavailable');
      expect(
        title('rateLimited'),
        "The model provider's rate limit was reached",
      );
      expect(title('overflow'), 'The conversation is too long for the model');
      expect(title('quantumFlux'), 'The agent could not complete the turn');
      expect(title(null), 'The agent could not complete the turn');
      expect(
        failureTitleOf(const PromptFailure.connectionLost()),
        'The connection to the agent was lost',
      );
      expect(
        failureTitleOf(const PromptFailure.request(code: -32603, message: 'x')),
        'The agent could not complete the turn',
      );
      expect(failureTitleOf(null), 'The agent could not complete the turn');
    });
  });

  test('the agent process exiting mid-turn marks the connection lost with its '
      'reason and notes the interrupted turn without Retry', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('hello agent');

    h.agent.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'Stdio ACP agent exited unexpectedly with code -9.',
      ),
    );
    await turn.done;
    await h.settle();

    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.lost);
    expect(
      h.cubit.state.connectionMessage,
      'Stdio ACP agent exited unexpectedly with code -9.',
    );
    expect(h.cubit.state.transcriptEntries.first.body, 'hello agent');
    final notice = errorEntry(h);
    expect(notice.title, 'The connection to the agent was lost');
    expect(notice.action, isNull);
  });

  test('a provider authentication failure reads as a sign-in problem with the '
      "agent's message and no Retry", () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('hello');

    failTurn(
      h,
      turn.request,
      errorClass: 'auth',
      message: '401 Unauthorized from openai: check api_key_env',
      retryable: false,
    );
    await turn.done;
    await h.settle();

    final notice = errorEntry(h);
    expect(notice.title, 'The agent could not sign in to the model provider');
    expect(notice.body, '401 Unauthorized from openai: check api_key_env');
    expect(notice.details, contains('Turn failed'));
    expect(notice.action, isNull);
  });

  test('Retry after a provider outage sends the same prompt as a new turn and '
      'keeps the failed turn above it', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('summarize the logs');
    failTurn(
      h,
      turn.request,
      errorClass: 'server',
      message: '503 Service Unavailable',
      retryable: true,
    );
    await turn.done;
    await h.settle();

    final notice = errorEntry(h);
    expect(notice.title, 'The model provider is unavailable');
    expect(notice.action?.label, 'Retry');

    final next = h.nextSent(sessionPromptMethod);
    notice.action!.onPressed!();
    final retried = await next as JsonRpcRequest;
    expect(PromptRequest.fromJson(retried.params).prompt, const [
      ContentBlock.text(text: 'summarize the logs'),
    ]);
    h.agentText('session-1', 'Here is the summary.');
    h.endTurn(retried);
    await h.settle();

    final entries = h.cubit.state.transcriptEntries;
    expect(
      entries.where((entry) => entry.body == 'summarize the logs'),
      hasLength(2),
    );
    expect(errorEntry(h).action, isNull);
    expect(entries.last.body, 'Here is the summary.');
  });

  test('an error from a third-party agent gets the general title, the '
      'JSON-RPC message and Retry', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('hello');

    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: turn.request.id,
        error: const JsonRpcError(code: -32603, message: 'Internal error'),
      ),
    );
    await turn.done;
    await h.settle();

    final notice = errorEntry(h);
    expect(notice.title, 'The agent could not complete the turn');
    expect(notice.body, 'Internal error');
    expect(notice.action?.label, 'Retry');
  });

  test(
    'Retry disappears when the connection is lost after the failure',
    () async {
      final h = ShellHarness();
      await h.connect();
      await h.createSession('session-1');
      final turn = await h.startTurn('hello');
      failTurn(
        h,
        turn.request,
        errorClass: 'network',
        message: 'connection reset by peer',
        retryable: true,
      );
      await turn.done;
      await h.settle();
      expect(errorEntry(h).action, isNotNull);

      h.agent.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.closed,
          message: 'agent process exited',
        ),
      );
      await h.settle();

      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.lost);
      expect(errorEntry(h).action, isNull);
    },
  );

  test('Reconnect after a lost connection goes through reconnecting to '
      'connected and clears the reason', () async {
    final first = FakeAcpTransport();
    final second = FakeAcpTransport();
    final transports = [first, second];
    var starts = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (_) => transports[starts++],
    );
    await h.connect();
    await h.createSession('session-1');
    first.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'agent process exited',
      ),
    );
    await h.settle();
    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.lost);
    final (states, _) = h.recordStates();

    await h.cubit.reconnect();
    await h.settle();

    expect(
      states.map((state) => state.connectionStatus),
      containsAllInOrder([
        CodeLabConnectionStatus.reconnecting,
        CodeLabConnectionStatus.connected,
      ]),
    );
    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
    expect(h.cubit.state.connectionMessage, isNull);
  });
}
