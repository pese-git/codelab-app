// Причина остановки по бюджету в итоге хода (задача 2.3 change
// `add-usage-extension`; spec acp-protocol-client «Причина остановки по
// бюджету»: «Бюджет по стоимости», «Незнакомая причина», «Сторонний агент
// без причины»; design.md, D10, D21 Т3).
//
// Красные тесты: `PromptTurn.budgetExceeded` ещё нет (задача 2.8) — файл не
// компилируется. Значение — открытая строка: известные `steps`, `tokens`,
// `cost`, `duration`, `deadline`, остальные сохраняются как есть.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    client = AcpClientApplication(transport: FakeAcpTransport());
    addTearDown(client.dispose);
    await client.connect(transport);

    transport.drainSentMessages();
    final created = client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );
    await pumpEventQueue();
    final request = transport.sentMessages.single as JsonRpcRequest;
    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(sessionId: _session).toJson(),
      ),
    );
    await created;
    transport.drainSentMessages();
  });

  /// Ход, на который агент отвечает [result]; возвращает итог хода.
  Future<PromptTurn> turnEndedWith(Map<String, Object?> result) async {
    final turn = client.sendPrompt(
      const SendPromptCommand(
        sessionId: _session,
        prompt: [ContentBlock.text(text: 'go')],
      ),
    );
    await pumpEventQueue();
    final request = transport.drainSentMessages().single as JsonRpcRequest;
    transport.emitInbound(
      JsonRpcMessage.response(id: request.id, result: result),
    );
    return turn;
  }

  Map<String, Object?> maxTurn([Object? meta, bool withMeta = true]) => {
    'stopReason': 'max_turn_requests',
    if (withMeta) '_meta': meta,
  };

  Map<String, Object?> codelab(Object? budgetExceeded) => {
    'codelab': {'budgetExceeded': budgetExceeded},
  };

  test(
    'max_turn_requests with budgetExceeded "cost" keeps the reason',
    () async {
      final turn = await turnEndedWith(maxTurn(codelab('cost')));

      expect(turn.stopReason, StopReason.maxTurnRequests);
      expect(turn.budgetExceeded, 'cost');
    },
  );

  test(
    'an unknown reason is kept as an open string without an error',
    () async {
      final turn = await turnEndedWith(maxTurn(codelab('energy')));

      expect(turn.budgetExceeded, 'energy');
    },
  );

  test('no _meta (a third-party agent) gives no reason', () async {
    final turn = await turnEndedWith(maxTurn(null, false));

    expect(turn.stopReason, StopReason.maxTurnRequests);
    expect(turn.budgetExceeded, isNull);
  });

  for (final (name, value) in <(String, Object?)>[
    ('a number', 7),
    ('a map', {'limit': 'cost'}),
    ('null', null),
  ]) {
    test(
      'a non-string budgetExceeded ($name) gives no reason and no error',
      () async {
        final turn = await turnEndedWith(maxTurn(codelab(value)));

        expect(turn.status, PromptTurnStatus.maxed);
        expect(turn.budgetExceeded, isNull);
      },
    );
  }

  test('_meta.codelab that is not an object gives no reason', () async {
    final turn = await turnEndedWith(maxTurn({'codelab': 'cost'}));

    expect(turn.budgetExceeded, isNull);
  });

  test('end_turn ignores budgetExceeded', () async {
    final turn = await turnEndedWith({
      'stopReason': 'end_turn',
      '_meta': codelab('cost'),
    });

    expect(turn.status, PromptTurnStatus.completed);
    expect(turn.budgetExceeded, isNull);
  });
}
