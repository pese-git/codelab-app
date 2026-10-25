import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart' show JsonRpcRequest;
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

/// Пара транспортов в памяти (`agent-core-architecture` §13.11; тестовая
/// копия — design.md change `add-dart-agent-acp-server`, D9).
void main() {
  JsonRpcMessage request(int id, [Object? params]) => JsonRpcMessage.request(
    id: JsonRpcId.integer(id),
    method: 'session/prompt',
    params: params,
  );

  Future<InProcessAcpLink> started() async {
    final link = InProcessAcpLink();
    await link.client.start();
    await link.agent.start();
    return link;
  }

  test('delivers asynchronously in send order', () async {
    final link = await started();
    final received = <JsonRpcMessage>[];
    link.agent.inbound.listen(received.add);

    await link.client.send(request(1));
    await link.client.send(request(2));
    await pumpEventQueue();

    expect(received.map((m) => (m as JsonRpcRequest).id), [
      const JsonRpcId.integer(1),
      const JsonRpcId.integer(2),
    ]);
  });

  test('the peer gets a deep copy of the JSON tree', () async {
    final link = await started();
    final received = Completer<JsonRpcMessage>();
    link.agent.inbound.listen(received.complete);
    final params = <String, Object?>{
      'prompt': [
        {'type': 'text', 'text': 'hi'},
      ],
    };

    await link.client.send(request(1, params));
    final got = (await received.future) as JsonRpcRequest;
    (params['prompt']! as List).clear();

    expect(got.params, {
      'prompt': [
        {'type': 'text', 'text': 'hi'},
      ],
    });
    expect(() => (got.params! as Map)['x'] = 1, throwsUnsupportedError);
  });

  test('a non-JSON value is sendFailed, as on the wire', () async {
    final link = await started();

    await expectLater(
      link.client.send(request(1, {'at': DateTime.utc(2026)})),
      throwsA(
        isA<AcpTransportException>().having(
          (e) => e.code,
          'code',
          AcpTransportErrorCode.sendFailed,
        ),
      ),
    );
  });

  test('a message before start() of the receiver is buffered', () async {
    final link = InProcessAcpLink();
    await link.agent.start();
    final received = <JsonRpcMessage>[];
    link.client.inbound.listen(received.add);

    await link.agent.send(request(7));
    await pumpEventQueue();
    expect(received, isEmpty);
    await link.client.start();
    await pumpEventQueue();

    expect(received, hasLength(1));
  });

  test('send before start() is sendFailed', () async {
    final link = InProcessAcpLink();

    await expectLater(
      link.client.send(request(1)),
      throwsA(isA<AcpTransportException>()),
    );
  });

  test('closing one end fails the other with disconnected', () async {
    final link = await started();
    final events = <AcpTransportEvent>[];
    link.agent.events.listen(events.add);

    await link.client.close();
    await pumpEventQueue();

    expect(link.client.state, AcpTransportState.closed);
    expect(link.agent.state, AcpTransportState.failed);
    expect(
      events.whereType<AcpTransportFailure>().single.error.code,
      AcpTransportErrorCode.disconnected,
    );
  });

  test('after the peer closed, send is sendFailed', () async {
    final link = await started();
    await link.agent.close();

    await expectLater(
      link.client.send(request(1)),
      throwsA(
        isA<AcpTransportException>().having(
          (e) => e.code,
          'code',
          AcpTransportErrorCode.sendFailed,
        ),
      ),
    );
    expect(link.agent.state, AcpTransportState.closed);
  });
}
