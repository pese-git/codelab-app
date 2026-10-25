import 'package:acp_protocol/acp_protocol.dart'
    show JsonRpcNotification, JsonRpcRequest, JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «Отсоединение, переподключение и завершение» (задача
/// 8.1; §13.5, шаги 3b, 8, 9; §13.10; D7; PERM-4).
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  final writeCall = {
    'reply': [
      {
        'toolCall': {
          'id': 'call_5',
          'name': 'write',
          'arguments': {'path': 'a.txt', 'content': 'a'},
        },
      },
    ],
  };
  final written = {
    'reply': [
      {'text': 'Written.'},
    ],
  };

  Future<JsonRpcRequest> nextRequest(TestClient client, String method) async {
    while (true) {
      final frame = await client.next();
      if (frame case JsonRpcRequest(method: final m) when m == method) {
        return frame;
      }
    }
  }

  Future<Map<String, Object?>> nextUpdate(
    TestClient client,
    bool Function(Map<String, Object?> update) test,
  ) async {
    while (true) {
      final frame = await client.next();
      if (frame is JsonRpcNotification) {
        final update = TestClient.updates([frame]).single;
        if (test(update)) {
          return update;
        }
      }
    }
  }

  Future<JsonRpcResponse> load(TestClient client, String sessionId) =>
      client.request('session/load', {
        'sessionId': sessionId,
        'cwd': '/work/demo',
        'mcpServers': <Object?>[],
      });

  /// Ход ждёт ответа на запрос разрешения первого соединения.
  Future<(String, JsonRpcRequest)> waitingForPermission({
    Duration detachGrace = const Duration(seconds: 30),
  }) async {
    h = await ServerHarness.start(
      steps: [writeCall, written],
      detachGrace: detachGrace,
    );
    await h.initialize();
    h.client.serveFiles(MemoryExecutionEnv(cwd: '/work/demo'));
    final sessionId = await h.newSession();
    final turn = h.prompt(sessionId, 'Write a.txt');
    // Ответ хода первому соединению не придёт: оно закроется.
    turn.ignore();
    final permission = await nextRequest(
      h.client,
      'session/request_permission',
    );
    return (sessionId, permission);
  }

  String journalOf(String sessionId) =>
      h.store.inner.textOf(SessionId(sessionId))!;

  test(
    'reconnect during a permission: replay, the same toolCallId again',
    () async {
      final (sessionId, first) = await waitingForPermission();
      await h.client.transport.close();
      await pumpEventQueue();

      final other = await h.connect();
      other.serveFiles(MemoryExecutionEnv(cwd: '/work/demo'));
      final response = await load(other, sessionId);
      final again = await nextRequest(other, 'session/request_permission');

      expect(response.error, isNull);
      expect(
        other.received.indexOf(response),
        lessThan(other.received.indexOf(again)),
      );
      final params = again.params! as Map<String, Object?>;
      final firstParams = first.params! as Map<String, Object?>;
      expect(
        (params['toolCall']! as Map)['toolCallId'],
        (firstParams['toolCall']! as Map)['toolCallId'],
      );
      await other.respond(again, {
        'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
      });
      final ended = await nextUpdate(
        other,
        (u) =>
            u['sessionUpdate'] == 'session_info_update' && u['_meta'] != null,
      );
      expect(ended['_meta'], {
        'codelab': {
          'turnEnded': {'stopReason': 'end_turn'},
        },
      });
    },
  );

  test(
    'grace expired: the turn is cancelled and the journal is complete',
    () async {
      final (sessionId, _) = await waitingForPermission();
      await h.client.transport.close();
      await pumpEventQueue();
      expect(journalOf(sessionId), isNot(contains('"outcome":"cancelled"')));

      await h.clock.elapse(const Duration(seconds: 30));
      await pumpEventQueue();

      expect(journalOf(sessionId), contains('"outcome":"cancelled"'));
    },
  );

  test('detachGrace zero cancels at once', () async {
    final (sessionId, _) = await waitingForPermission(
      detachGrace: Duration.zero,
    );

    await h.client.transport.close();
    await pumpEventQueue();

    expect(journalOf(sessionId), contains('"outcome":"cancelled"'));
  });

  test(
    'session/load during a turn of a live connection is sessionBusy',
    () async {
      final (sessionId, _) = await waitingForPermission();
      final other = await h.connect();

      final response = await load(other, sessionId);

      expect(response.errorCode, -32602);
      expect(response.error!.data, {
        'codelab': {'reason': 'sessionBusy'},
      });
      await h.client.notify('session/cancel', {'sessionId': sessionId});
    },
  );

  test(
    'shutdown: new requests -32603, turns cancelled, transports closed',
    () async {
      h = await ServerHarness.start(
        steps: [
          {'waitForCancel': true},
        ],
      );
      await h.initialize();
      final sessionId = await h.newSession();
      final turn = h.prompt(sessionId, 'Wait');
      await pumpEventQueue();

      final stopping = h.server.shutdown();
      final late = h.client.request('session/list', {});

      expect((await turn).resultMap, {'stopReason': 'cancelled'});
      expect((await late).errorCode, -32603);
      await stopping;
      await h.client.closed;
    },
  );
}
