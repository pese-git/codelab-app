import 'dart:async';
import 'dart:collection';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcError, JsonRpcNotification, JsonRpcRequest, JsonRpcResponse;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:test/test.dart';

/// Пара транспортов в памяти (`agent-transports` «Пара транспортов в
/// памяти»; design.md change `add-in-process-acp-transport`, D3–D4).
///
/// Тест импортирует только основной барель: так проверяется и то, что пара
/// доступна без `io.dart`.
void main() {
  JsonRpcMessage request(int id, [Object? params]) => JsonRpcMessage.request(
    id: JsonRpcId.integer(id),
    method: 'session/prompt',
    params: params,
  );

  JsonRpcMessage notification(int n) =>
      JsonRpcMessage.notification(method: 'session/update', params: {'n': n});

  /// Создаёт пару и закрывает оба конца в tearDown, чтобы тесты не делили
  /// контроллеры и не оставляли открытых потоков.
  InProcessAcpLink newLink() {
    final link = InProcessAcpLink();
    addTearDown(() async {
      await link.client.close();
      await link.agent.close();
    });
    return link;
  }

  Future<InProcessAcpLink> started() async {
    final link = newLink();
    await link.client.start();
    await link.agent.start();
    return link;
  }

  TypeMatcher<AcpTransportException> sendFailed() =>
      isA<AcpTransportException>().having(
        (e) => e.code,
        'code',
        AcpTransportErrorCode.sendFailed,
      );

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

  test('delivers 1000 messages in send order', () async {
    final link = await started();
    final received = <JsonRpcMessage>[];
    link.agent.inbound.listen(received.add);

    final sends = [
      for (var i = 1; i <= 1000; i++) link.client.send(request(i)),
    ];
    await Future.wait(sends);
    await pumpEventQueue();

    expect(received.map((m) => (m as JsonRpcRequest).id), [
      for (var i = 1; i <= 1000; i++) JsonRpcId.integer(i),
    ]);
  });

  test('delivery is not reentrant', () async {
    final link = await started();
    final received = <JsonRpcMessage>[];
    link.agent.inbound.listen(received.add);

    await link.client.send(request(1));
    expect(received, isEmpty);
    await pumpEventQueue();

    expect(received, hasLength(1));
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
    params['extra'] = 1;
    (params['prompt']! as List).clear();
    final got = (await received.future) as JsonRpcRequest;

    expect(got.params, {
      'prompt': [
        {'type': 'text', 'text': 'hi'},
      ],
    });
    expect(() => (got.params! as Map)['x'] = 1, throwsUnsupportedError);
  });

  test('error.data of a response is copied and immutable', () async {
    final link = await started();
    final received = Completer<JsonRpcMessage>();
    link.client.inbound.listen(received.complete);
    final data = <String, Object?>{
      'codelab': {'reason': 'r'},
    };

    await link.agent.send(
      JsonRpcMessage.response(
        id: const JsonRpcId.integer(1),
        error: JsonRpcError(code: -32603, message: 'x', data: data),
      ),
    );
    (data['codelab']! as Map)['reason'] = 'changed';
    final got = (await received.future) as JsonRpcResponse;

    expect(got.error!.data, {
      'codelab': {'reason': 'r'},
    });
    expect(() => (got.error!.data! as Map)['x'] = 1, throwsUnsupportedError);
  });

  test(
    'result of a response is copied and immutable, nested lists too',
    () async {
      final link = await started();
      final received = Completer<JsonRpcMessage>();
      link.client.inbound.listen(received.complete);
      final inner = <Object?>[1, 2];
      final result = <String, Object?>{
        'grid': [
          inner,
          [3],
        ],
      };

      await link.agent.send(
        JsonRpcMessage.response(id: const JsonRpcId.integer(1), result: result),
      );
      inner.add(99);
      (result['grid']! as List).clear();
      final got = (await received.future) as JsonRpcResponse;

      expect(got.result, {
        'grid': [
          [1, 2],
          [3],
        ],
      });
      final grid = (got.result! as Map)['grid']! as List;
      expect(() => grid.add(1), throwsUnsupportedError);
      expect(() => (grid[0] as List).add(1), throwsUnsupportedError);
      expect(() => (got.result! as Map)['x'] = 1, throwsUnsupportedError);
    },
  );

  test('a cyclic params tree is sendFailed without cause or value', () async {
    final link = await started();
    final cyclic = <String, Object?>{'secret-key': 'secret-value'};
    cyclic['self'] = cyclic;

    await expectLater(
      link.client.send(request(1, cyclic)),
      throwsA(
        sendFailed()
            .having((e) => e.cause, 'cause', isNull)
            .having((e) => e.message, 'message', isNot(contains('secret'))),
      ),
    );
    expect(link.client.state, AcpTransportState.connected);
  });

  test(
    'an iterator error while copying is sendFailed with the same text',
    () async {
      final link = await started();
      final received = <JsonRpcMessage>[];
      link.agent.inbound.listen(received.add);

      Future<AcpTransportException> failure(Object? params) async {
        try {
          await link.client.send(request(1, params));
        } on AcpTransportException catch (e) {
          return e;
        }
        throw StateError('send did not fail');
      }

      final reference = await failure({'at': DateTime.utc(2026)});
      final got = await failure(_ThrowingMap());

      expect(got.code, AcpTransportErrorCode.sendFailed);
      expect(got.message, reference.message);
      expect(got.message, isNot(contains('secret-42')));
      expect(got.cause, isNull);
      expect(link.client.state, AcpTransportState.connected);

      await link.client.send(request(2));
      await pumpEventQueue();
      expect(received.map((m) => (m as JsonRpcRequest).id), [
        const JsonRpcId.integer(2),
      ]);
    },
  );

  test('a non-JSON value is sendFailed, as on the wire', () async {
    final link = await started();
    final received = <JsonRpcMessage>[];
    link.agent.inbound.listen(received.add);

    Object? thrown;
    try {
      await link.client.send(request(1, {'at': DateTime.utc(2026)}));
    } on AcpTransportException catch (e) {
      thrown = e;
    }

    expect(thrown, sendFailed());
    expect((thrown! as AcpTransportException).message, isNot(contains('2026')));
    expect(link.client.state, AcpTransportState.connected);

    await link.client.send(request(2));
    await pumpEventQueue();
    expect(received.map((m) => (m as JsonRpcRequest).id), [
      const JsonRpcId.integer(2),
    ]);
  });

  test('a non-String key, NaN and infinity are sendFailed', () async {
    final link = await started();
    final received = <JsonRpcMessage>[];
    link.agent.inbound.listen(received.add);

    for (final params in <Object?>[
      {12345: 'x'},
      {'v': double.nan},
      {'v': double.infinity},
      {'v': double.negativeInfinity},
    ]) {
      await expectLater(
        link.client.send(request(1, params)),
        throwsA(
          sendFailed()
              .having((e) => e.cause, 'cause', isNull)
              .having((e) => e.message, 'message', isNot(contains('12345')))
              .having((e) => e.message, 'message', isNot(contains('NaN')))
              .having((e) => e.message, 'message', isNot(contains('nfinity'))),
        ),
      );
    }
    await pumpEventQueue();

    expect(received, isEmpty);
  });

  test('a message before start() of the receiver is buffered', () async {
    final link = newLink();
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

  test('a message before the first subscriber is buffered', () async {
    final link = await started();

    await link.client.send(request(1));
    await link.client.send(request(2));
    await pumpEventQueue();
    final received = <JsonRpcMessage>[];
    link.agent.inbound.listen(received.add);
    await pumpEventQueue();

    expect(received.map((m) => (m as JsonRpcRequest).id), [
      const JsonRpcId.integer(1),
      const JsonRpcId.integer(2),
    ]);
  });

  test('after the first subscription there is no buffering', () async {
    final link = await started();
    final first = link.agent.inbound.listen((_) {});
    await pumpEventQueue();
    await first.cancel();

    await link.client.send(request(1));
    await pumpEventQueue();
    final received = <JsonRpcMessage>[];
    link.agent.inbound.listen(received.add);
    await pumpEventQueue();

    expect(received, isEmpty);
  });

  test('a late subscriber of a live inbound gets only new messages', () async {
    final link = await started();
    final early = <JsonRpcMessage>[];
    link.agent.inbound.listen(early.add);

    await link.client.send(request(1));
    await pumpEventQueue();
    final late = <JsonRpcMessage>[];
    link.agent.inbound.listen(late.add);
    await link.client.send(request(2));
    await pumpEventQueue();

    expect(early, hasLength(2));
    expect(late.map((m) => (m as JsonRpcRequest).id), [
      const JsonRpcId.integer(2),
    ]);
  });

  test('an undelivered buffer is dropped when the peer closes: '
      'one warning without content, before the failure', () async {
    final link = await started();
    final events = <AcpTransportEvent>[];
    link.client.events.listen(events.add);
    await link.agent.send(notification(1));
    await link.agent.send(
      JsonRpcMessage.notification(
        method: 'session/update',
        params: {'text': 'confidential-42'},
      ),
    );
    await link.agent.close();
    await pumpEventQueue();

    final received = <JsonRpcMessage>[];
    var done = false;
    link.client.inbound.listen(received.add, onDone: () => done = true);
    await pumpEventQueue();

    expect(received, isEmpty);
    expect(done, isTrue);
    final diagnostics = events.whereType<AcpTransportDiagnostic>().toList();
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.severity, AcpTransportDiagnosticSeverity.warning);
    expect(diagnostics.single.message, contains('2'));
    expect(diagnostics.single.message, isNot(contains('confidential')));
    expect(
      events.indexWhere((e) => e is AcpTransportDiagnostic),
      lessThan(events.indexWhere((e) => e is AcpTransportFailure)),
    );
  });

  test('closing own end drops the buffer without a diagnostic', () async {
    final link = await started();
    final events = <AcpTransportEvent>[];
    link.client.events.listen(events.add);
    await link.agent.send(notification(1));
    await pumpEventQueue();

    await link.client.close();
    await pumpEventQueue();

    expect(events.whereType<AcpTransportDiagnostic>(), isEmpty);
  });

  test(
    'a not started receiver gets the warning when the peer closes',
    () async {
      final link = newLink();
      await link.agent.start();
      final events = <AcpTransportEvent>[];
      link.client.events.listen(events.add);
      await link.agent.send(notification(1));
      await link.agent.close();
      await pumpEventQueue();

      expect(events.whereType<AcpTransportDiagnostic>(), hasLength(1));
      expect(events.whereType<AcpTransportFailure>(), hasLength(1));
      expect(link.client.state, AcpTransportState.failed);
    },
  );

  test('send before start() is sendFailed', () async {
    final link = newLink();

    await expectLater(link.client.send(request(1)), throwsA(sendFailed()));
  });

  test('send after its own close() is sendFailed', () async {
    final link = await started();
    await link.client.close();

    await expectLater(link.client.send(request(1)), throwsA(sendFailed()));
  });

  test('closing one end fails the other with disconnected', () async {
    final link = await started();
    final events = <AcpTransportEvent>[];
    final done = Completer<void>();
    link.agent.events.listen(events.add);
    link.agent.inbound.listen((_) {}, onDone: done.complete);

    await link.client.close();
    await pumpEventQueue();

    expect(link.client.state, AcpTransportState.closed);
    expect(link.agent.state, AcpTransportState.failed);
    expect(done.isCompleted, isTrue);
    expect(
      events.whereType<AcpTransportFailure>().single.error.code,
      AcpTransportErrorCode.disconnected,
    );
    final failureAt = events.indexWhere((e) => e is AcpTransportFailure);
    final failedAt = events.indexWhere(
      (e) =>
          e is AcpTransportStateChanged && e.state == AcpTransportState.failed,
    );
    expect(failureAt, isNonNegative);
    expect(failedAt, greaterThan(failureAt), reason: 'D4 п. 6');
  });

  test('after the peer closed, send is sendFailed', () async {
    final link = await started();
    await link.agent.close();

    await expectLater(link.client.send(request(1)), throwsA(sendFailed()));
    expect(link.agent.state, AcpTransportState.closed);
  });

  test('messages sent before close() arrive before done', () async {
    final link = await started();
    final seen = <String>[];
    link.client.inbound.listen(
      (m) => seen.add('${(m as JsonRpcNotification).params}'),
      onDone: () => seen.add('done'),
    );

    await link.agent.send(notification(1));
    await link.agent.send(notification(2));
    await link.agent.send(notification(3));
    await link.agent.close();
    await pumpEventQueue();

    expect(seen, ['{n: 1}', '{n: 2}', '{n: 3}', 'done']);
    expect(link.client.state, AcpTransportState.failed);
  });

  test('a repeated close() is a no-op: one failure on the peer', () async {
    final link = await started();
    final events = <AcpTransportEvent>[];
    final clientEvents = <AcpTransportEvent>[];
    link.agent.events.listen(events.add);
    link.client.events.listen(clientEvents.add);

    await link.client.close();
    await pumpEventQueue();
    final clientAfterFirst = clientEvents.length;
    await link.client.close();
    await pumpEventQueue();

    expect(clientEvents, hasLength(clientAfterFirst));
    expect(events.whereType<AcpTransportFailure>(), hasLength(1));
  });

  test('state changes follow start() and close()', () async {
    final link = newLink();
    final states = <AcpTransportState>[];
    link.client.events.listen((e) {
      if (e is AcpTransportStateChanged) {
        states.add(e.state);
      }
    });

    await link.client.start();
    await link.client.close();
    await pumpEventQueue();

    expect(states, [
      AcpTransportState.connecting,
      AcpTransportState.connected,
      AcpTransportState.closing,
      AcpTransportState.closed,
    ]);
  });

  test('close() of a failed end gives closed; start() then throws', () async {
    final link = await started();
    await link.client.close();
    expect(link.agent.state, AcpTransportState.failed);

    await link.agent.close();

    expect(link.agent.state, AcpTransportState.closed);
    await expectLater(
      link.agent.start(),
      throwsA(
        isA<AcpTransportException>().having(
          (e) => e.code,
          'code',
          AcpTransportErrorCode.closed,
        ),
      ),
    );
  });

  test('delivery to a closed end does not fail the sender', () async {
    final link = await started();
    final received = <JsonRpcMessage>[];
    link.agent.inbound.listen(received.add);

    final sent = link.client.send(request(1));
    await link.agent.close();
    await sent;
    await pumpEventQueue();

    expect(received, isEmpty);
  });
}

/// Map, чей обход `entries` бросает `StateError` с «секретом»: `_copyJson`
/// обходит Map именно через `entries`.
class _ThrowingMap extends MapBase<String, Object?> {
  @override
  Iterable<MapEntry<String, Object?>> get entries =>
      throw StateError('secret-42');

  @override
  Object? operator [](Object? key) => null;
  @override
  void operator []=(String key, Object? value) {}
  @override
  void clear() {}
  @override
  Iterable<String> get keys => const [];
  @override
  Object? remove(Object? key) => null;
}
