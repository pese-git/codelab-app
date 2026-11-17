// Запрос журнала usage `_codelab/session/usage/ledger` ядром клиента
// (задача 3.1 change `add-usage-ledger`; spec acp-protocol-client «Запрос
// журнала usage»: «Агент объявил журнал», «Агент без ключа», «Ошибка
// агента»; design.md, D7, D9).
//
// Формы, которые задаёт этот тест (design D9 имён не фиксирует):
//   * `requestUsageLedger(sessionId:, rebuild:)` возвращает
//     `UsageLedgerReply` (`result` — сырой объект, `generation`);
//   * отказ без ключа и ошибка агента — `AcpClientApplicationException`;
//     для ошибки JSON-RPC её `cause` — `JsonRpcError` с кодом, как у
//     остальных запросов приложения («как другие запросы приложения», D9).
//
// Гонки не нужны: порядок кадров задан прямыми `emitInbound`, без таймеров.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');
const _method = '_codelab/session/usage/ledger';

AgentCapabilities _caps(Object? usageLedger) => AgentCapabilities(
  meta: {
    'codelab': {'usageLedger': ?usageLedger},
  },
);

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  Future<ClientConnectionReady> connect([
    AgentCapabilities capabilities = const AgentCapabilities(),
  ]) async {
    transport = FakeAcpTransport()..initializeAgentCapabilities = capabilities;
    client = AcpClientApplication(transport: FakeAcpTransport());
    addTearDown(client.dispose);
    await client.connect(transport);
    transport.drainSentMessages();
    return client.connectionState as ClientConnectionReady;
  }

  Future<JsonRpcRequest> sentRequest() async {
    await pumpEventQueue();
    return transport.sentMessages.whereType<JsonRpcRequest>().single;
  }

  group('negotiation (D7)', () {
    for (final (name, value, expected) in <(String, Object?, bool)>[
      ('an integer version 1', {'version': 1}, true),
      ('version 2', {'version': 2}, false),
      ('a string version', {'version': '1'}, false),
      ('no version', <String, Object?>{}, false),
      ('not an object', true, false),
    ]) {
      test('usageLedger with $name -> $expected', () async {
        final ready = await connect(_caps(value));

        expect(ready.codelabExtensions.usageLedger, expected);
      });
    }

    test('no usageLedger key and no _meta: not negotiated', () async {
      final ready = await connect();

      expect(ready.codelabExtensions.usageLedger, isFalse);
    });

    test('the client never declares usageLedger (D7)', () {
      final codelab =
          codelabClientExtensionsMeta['codelab']! as Map<String, Object?>;

      expect(codelab, isNot(contains('usageLedger')));
    });
  });

  group('the request (D9)', () {
    setUp(() => connect(_caps({'version': 1})));

    test('with rebuild: true the frame carries rebuild, the raw result and '
        'the generation of the send', () async {
      final reply = client.requestUsageLedger(
        sessionId: _session,
        rebuild: true,
      );

      final request = await sentRequest();
      expect(request.method, _method);
      expect(request.params, {'sessionId': 'session-1', 'rebuild': true});
      final generation = client.generation;
      transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: const {'sessionId': 'session-1', 'seq': 12, 'extra': 'kept'},
        ),
      );

      final result = await reply;
      expect(result.result, {
        'sessionId': 'session-1',
        'seq': 12,
        'extra': 'kept',
      });
      expect(result.generation, generation);
    });

    test('without rebuild the field is absent from the frame, and false is '
        'not sent either', () async {
      final first = client.requestUsageLedger(sessionId: _session);
      final request = await sentRequest();
      expect(request.params, {'sessionId': 'session-1'});
      transport.emitInbound(
        JsonRpcMessage.response(id: request.id, result: const {'seq': 0}),
      );
      await first;
      transport.drainSentMessages();

      final second = client.requestUsageLedger(
        sessionId: _session,
        rebuild: false,
      );
      final again = await sentRequest();
      expect(again.params, {'sessionId': 'session-1'});
      transport.emitInbound(
        JsonRpcMessage.response(id: again.id, result: const {'seq': 0}),
      );
      await second;
    });

    test('the generation is the one of the send, not of the reply', () async {
      final reply = client.requestUsageLedger(sessionId: _session);
      final request = await sentRequest();
      final sentOn = client.generation;

      transport.emitInbound(
        JsonRpcMessage.response(id: request.id, result: const {'seq': 1}),
      );

      expect((await reply).generation, sentOn);
    });

    for (final code in [-32601, -32002]) {
      test('agent error $code: a typed failure with the code, the connection '
          'stays alive (scenario «Ошибка агента»)', () async {
        final reply = client.requestUsageLedger(sessionId: _session);
        final request = await sentRequest();

        transport.emitInbound(
          JsonRpcMessage.response(
            id: request.id,
            error: JsonRpcError(code: code, message: 'failed'),
          ),
        );

        await expectLater(
          reply,
          throwsA(
            isA<AcpClientApplicationException>().having(
              (e) => (e.cause as JsonRpcError?)?.code,
              'cause.code',
              code,
            ),
          ),
        );
        expect(client.connectionState, isA<ClientConnectionReady>());
      });
    }
  });

  group('without the declaration (scenario «Агент без ключа»)', () {
    for (final (name, caps) in <(String, AgentCapabilities)>[
      ('no codelab block', const AgentCapabilities()),
      ('version 2', _caps({'version': 2})),
      ('version 1.5', _caps({'version': 1.5})),
      ('string version', _caps({'version': '1'})),
    ]) {
      test('$name: refused, no frame is sent', () async {
        await connect(caps);

        await expectLater(
          client.requestUsageLedger(sessionId: _session),
          throwsA(isA<AcpClientApplicationException>()),
        );
        await pumpEventQueue();

        expect(transport.sentMessages, isEmpty);
      });
    }

    test('before initialize: refused, no frame is sent', () async {
      transport = FakeAcpTransport();
      client = AcpClientApplication(transport: FakeAcpTransport());
      addTearDown(client.dispose);

      await expectLater(
        client.requestUsageLedger(sessionId: _session),
        throwsA(isA<AcpClientApplicationException>()),
      );

      expect(transport.sentMessages, isEmpty);
    });
  });
}
