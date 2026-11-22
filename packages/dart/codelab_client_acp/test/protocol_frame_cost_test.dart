// Стоимость кадров на потоке стриминга (задача 1.7 `[client]` change
// `redesign-protocol-pane`; design.md, Risks «Стоимость `jsonEncode` на каждый
// кадр»).
//
// 10 000 входящих `agent_message_chunk` обрабатываются ядром при
// `metadataOnly` и при `full` не дольше чем в 1,5 раза по сравнению с прогоном
// без подписчиков кадров на той же машине. Время — минимум из нескольких
// прогонов каждого режима, чтобы разовый всплеск сборщика мусора не давал
// ложного провала; порог — отношение, а не абсолютные миллисекунды.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _chunks = 10000;
const _runs = 5;

Future<Duration> _run({
  required ProtocolPayloadPolicy policy,
  required bool subscribe,
}) async {
  final transport = FakeAcpTransport();
  await transport.start();
  final client = AcpClientApplication(
    transport: transport,
    protocolPayloads: policy,
  );
  var seen = 0;
  if (subscribe) {
    client.protocolFrames.listen((_) => seen++);
  }
  final created = client.createSession(
    const CreateSessionCommand(cwd: '/workspace'),
  );
  await pumpEventQueue();
  transport.emitInbound(
    JsonRpcMessage.response(
      id: (transport.sentMessages.single as JsonRpcRequest).id,
      result: const NewSessionResponse(sessionId: SessionId('s1')).toJson(),
    ),
  );
  await created;
  await client
      .sendPrompt(
        const SendPromptCommand(
          sessionId: SessionId('s1'),
          prompt: [ContentBlock.text(text: 'go')],
        ),
      )
      .then<void>((_) {}, onError: (_) {})
      .timeout(const Duration(milliseconds: 1), onTimeout: () {});

  final watch = Stopwatch()..start();
  for (var i = 0; i < _chunks; i++) {
    transport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: {
          'sessionId': 's1',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'chunk number $i of the reply'},
          },
        },
      ),
    );
  }
  await pumpEventQueue();
  watch.stop();
  if (subscribe) {
    expect(seen, greaterThanOrEqualTo(_chunks));
  }
  await client.dispose();
  await transport.close();
  return watch.elapsed;
}

Future<int> _best({
  required ProtocolPayloadPolicy policy,
  required bool subscribe,
}) async {
  var best = 1 << 62;
  for (var i = 0; i < _runs; i++) {
    final elapsed = (await _run(
      policy: policy,
      subscribe: subscribe,
    )).inMicroseconds;
    if (elapsed < best) best = elapsed;
  }
  return best;
}

void main() {
  test('10 000 agent_message_chunk: кадры не дороже 1,5 раза', () async {
    final baseline = await _best(
      policy: ProtocolPayloadPolicy.metadataOnly,
      subscribe: false,
    );
    final metadata = await _best(
      policy: ProtocolPayloadPolicy.metadataOnly,
      subscribe: true,
    );
    final full = await _best(
      policy: ProtocolPayloadPolicy.full,
      subscribe: true,
    );

    // ignore: avoid_print
    print(
      'baseline=${baseline}us metadataOnly=${metadata}us '
      '(${(metadata / baseline).toStringAsFixed(2)}x) full=${full}us '
      '(${(full / baseline).toStringAsFixed(2)}x)',
    );
    expect(metadata, lessThanOrEqualTo(baseline * 1.5));
    expect(full, lessThanOrEqualTo(baseline * 1.5));
    // Отношение времён шумит под параллельной нагрузкой (CI, `melos test`):
    // повтор отличает шум от настоящей регрессии, порог 1,5× не ослабляется.
  }, retry: 2);
}
