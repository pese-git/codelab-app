// Потеря соединения и повтор сорвавшегося хода (tasks 2.1, 2.4 change
// `add-connection-and-error-states`; spec acp-client-kit «Явный автомат
// соединения», «Повтор сорвавшегося хода»; design D1, D4).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

void main() {
  late KitAgent agent;

  tearDown(() => agent.dispose());

  /// Ответ-ошибка агента CodeLab с `data.codelab`.
  void failWithClass(
    JsonRpcRequest request, {
    required String errorClass,
    required bool retryable,
  }) => agent.transport.emitInbound(
    JsonRpcMessage.response(
      id: request.id,
      error: JsonRpcError(
        code: -32603,
        message: 'Turn failed',
        data: <String, Object?>{
          'codelab': <String, Object?>{
            'errorClass': errorClass,
            'message': '$errorClass failure',
            'retryable': retryable,
          },
        },
      ),
    ),
  );

  void dropTransport() => agent.transport.fail(
    const AcpTransportException(
      code: AcpTransportErrorCode.closed,
      message: 'agent process exited',
    ),
  );

  group('ConnectionView', () {
    test(
      'an unexpected transport failure in Connected is ConnectionLost',
      () async {
        agent = KitAgent();
        await agent.start();

        dropTransport();

        expect(
          agent.workspace.current.connection,
          isA<ConnectionLost>().having(
            (view) => view.message,
            'message',
            'agent process exited',
          ),
        );
      },
    );

    test('reconnect() from ConnectionLost goes through Reconnecting(1) to '
        'Connected', () async {
      agent = KitAgent();
      await agent.start();
      dropTransport();
      final connections = <ConnectionView>[];
      final subscription = agent.workspace.state.listen(
        (state) => connections.add(state.connection),
      );
      addTearDown(subscription.cancel);

      agent.restartAgent();
      await agent.workspace.reconnect();

      expect(connections.first, const ConnectionView.reconnecting(attempt: 1));
      expect(agent.workspace.current.connection, isA<Connected>());
    });
  });

  group('retry', () {
    test('a turn failed with a retryable class can be retried with the same '
        'prompt, keeping the failed turn', () async {
      agent = KitAgent();
      await agent.start();
      final handle = await agent.newSession('s-1');
      final first = await agent.prompt(handle, 'hello');
      failWithClass(first.request, errorClass: 'network', retryable: true);
      await first.done;

      expect(handle.current.canRetry, isTrue);
      final notice = handle.current.transcript.whereType<NoticeItem>().single;
      expect(
        notice.failure,
        const PromptFailure.agent(
          errorClass: 'network',
          message: 'network failure',
          retryable: true,
        ),
      );

      final second = agent.next(sessionPromptMethod);
      final retried = handle.retry();
      final request = await second;
      expect(PromptRequest.fromJson(request.params).prompt, const [
        ContentBlock.text(text: 'hello'),
      ]);
      expect(handle.current.canRetry, isFalse);
      agent.respond(request, const {'stopReason': 'end_turn'});
      await retried;

      expect(
        handle.current.transcript.whereType<UserItem>().map((i) => i.text),
        ['hello', 'hello'],
      );
      expect(
        handle.current.transcript.whereType<NoticeItem>().where(
          (notice) => notice.kind == NoticeKind.error,
        ),
        hasLength(1),
      );
      expect(handle.current.canRetry, isFalse);
    });

    test('retryable: false forbids retry without sending a request', () async {
      agent = KitAgent();
      await agent.start();
      final handle = await agent.newSession('s-1');
      final first = await agent.prompt(handle, 'hello');
      failWithClass(first.request, errorClass: 'auth', retryable: false);
      await first.done;
      agent.transport.drainSentMessages();

      expect(handle.current.canRetry, isFalse);
      await expectLater(
        handle.retry(),
        throwsA(isA<ClientWorkspaceException>()),
      );
      expect(agent.transport.drainSentMessages(), isEmpty);
    });

    test('an error without the CodeLab extension can be retried', () async {
      agent = KitAgent();
      await agent.start();
      final handle = await agent.newSession('s-1');
      final first = await agent.prompt(handle, 'hello');
      agent.fail(first.request, 'Internal error');
      await first.done;

      expect(handle.current.canRetry, isTrue);
    });

    test('a turn interrupted by a lost connection is not retried', () async {
      agent = KitAgent();
      await agent.start();
      final handle = await agent.newSession('s-1');
      final first = await agent.prompt(handle, 'hello');

      dropTransport();
      await first.done;

      final notice = handle.current.transcript.whereType<NoticeItem>().single;
      expect(notice.failure, const PromptFailure.connectionLost());
      expect(handle.current.canRetry, isFalse);
    });

    test('a running session cannot retry', () async {
      agent = KitAgent();
      await agent.start();
      final handle = await agent.newSession('s-1');
      final first = await agent.prompt(handle, 'hello');
      failWithClass(first.request, errorClass: 'server', retryable: true);
      await first.done;
      await agent.prompt(handle, 'next');

      expect(handle.current.status, SessionStatusView.running);
      expect(handle.current.canRetry, isFalse);
    });
  });
}
