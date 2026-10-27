// Типизированный сбой prompt turn (tasks 1.1, 1.4 change
// `add-connection-and-error-states`; spec acp-protocol-client «Типизированный
// сбой prompt turn»; design D2).
//
// Ответ-ошибка агента на `session/prompt` сохраняется в ходе как
// `PromptFailure` с разобранным `data.codelab`, а ход, прерванный отказом
// транспорта, получает `connectionLost` и не остаётся `running`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');

void main() {
  group('PromptFailure.fromJsonRpcError', () {
    test('reads data.codelab of the provider-auth fixture', () {
      final failure = PromptFailure.fromJsonRpcError(
        const JsonRpcError(
          code: -32603,
          message: 'Turn failed: provider authentication error',
          data: {
            'codelab': {
              'errorClass': 'auth',
              'message': '401 Unauthorized from openai: check api_key_env',
              'retryable': false,
            },
          },
        ),
      );

      expect(
        failure,
        const PromptFailure.agent(
          errorClass: 'auth',
          message: '401 Unauthorized from openai: check api_key_env',
          retryable: false,
        ),
      );
    });

    test('an error without data is a request failure', () {
      expect(
        PromptFailure.fromJsonRpcError(
          const JsonRpcError(code: -32603, message: 'Internal error'),
        ),
        const PromptFailure.request(code: -32603, message: 'Internal error'),
      );
    });

    test('data.codelab that is not an object is a request failure', () {
      expect(
        PromptFailure.fromJsonRpcError(
          const JsonRpcError(
            code: -32603,
            message: 'Internal error',
            data: {'codelab': 'auth'},
          ),
        ),
        const PromptFailure.request(code: -32603, message: 'Internal error'),
      );
    });

    test('an unknown errorClass is kept and a non-bool retryable is null', () {
      expect(
        PromptFailure.fromJsonRpcError(
          const JsonRpcError(
            code: -32603,
            message: 'Turn failed',
            data: {
              'codelab': {
                'errorClass': 'quantumFlux',
                'message': 'flux capacitor drained',
                'retryable': 'maybe',
              },
            },
          ),
        ),
        const PromptFailure.agent(
          errorClass: 'quantumFlux',
          message: 'flux capacitor drained',
        ),
      );
    });

    test('an empty agent message falls back to the JSON-RPC message', () {
      expect(
        PromptFailure.fromJsonRpcError(
          const JsonRpcError(
            code: -32603,
            message: 'Turn failed',
            data: {
              'codelab': {'errorClass': 'server'},
            },
          ),
        ),
        const PromptFailure.agent(errorClass: 'server', message: 'Turn failed'),
      );
    });
  });

  group('AcpClientApplication.sendPrompt', () {
    late FakeAcpTransport transport;
    late AcpClientApplication client;

    setUp(() async {
      final initial = FakeAcpTransport();
      await initial.start();
      client = AcpClientApplication(transport: initial);
      transport = FakeAcpTransport();
      await client.connect(transport);
      await _createSession(client, transport);
      transport.drainSentMessages();
    });

    tearDown(() async {
      await client.dispose();
      await transport.close();
    });

    Future<PromptTurn> failedTurn(Future<PromptTurn> prompt) async {
      await expectLater(prompt, throwsA(isA<AcpClientApplicationException>()));
      return client.sessionById(_session)!.turns.last;
    }

    Future<PromptTurn> send() => client.sendPrompt(
      const SendPromptCommand(
        sessionId: _session,
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    );

    test('an agent error keeps the parsed failure in the turn', () async {
      final prompt = send();
      await _pump();
      final request = transport.drainSentMessages().single as JsonRpcRequest;
      transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          error: const JsonRpcError(
            code: -32603,
            message: 'Turn failed',
            data: {
              'codelab': {
                'errorClass': 'network',
                'message': 'connection reset by peer',
                'retryable': true,
              },
            },
          ),
        ),
      );

      final turn = await failedTurn(prompt);

      expect(turn.status, PromptTurnStatus.failed);
      expect(turn.failureMessage, isNotNull);
      expect(
        turn.failure,
        const PromptFailure.agent(
          errorClass: 'network',
          message: 'connection reset by peer',
          retryable: true,
        ),
      );
    });

    test(
      'a transport failure ends the running turn as connectionLost',
      () async {
        final prompt = send();
        await _pump();
        expect(
          client.sessionById(_session)!.activeTurn?.status,
          PromptTurnStatus.running,
        );

        transport.fail(
          const AcpTransportException(
            code: AcpTransportErrorCode.closed,
            message: 'agent process exited',
          ),
        );

        final turn = await failedTurn(prompt);

        expect(turn.status, PromptTurnStatus.failed);
        expect(turn.failure, const PromptFailure.connectionLost());
        expect(client.connectionState, isA<ClientConnectionFailed>());
      },
    );
  });
}

Future<void> _createSession(
  AcpClientApplication client,
  FakeAcpTransport transport,
) async {
  transport.drainSentMessages();
  final future = client.createSession(
    const CreateSessionCommand(cwd: '/workspace'),
  );
  await _pump();
  final request = transport.sentMessages.single as JsonRpcRequest;
  transport.emitInbound(
    JsonRpcMessage.response(
      id: request.id,
      result: const NewSessionResponse(sessionId: _session).toJson(),
    ),
  );
  await future;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
