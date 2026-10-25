import 'package:acp_protocol/acp_protocol.dart'
    show JsonRpcRequest, JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «session/cancel» (задача 5.1; §13.7; ACP-5, ENV-7,
/// PERM-4, PERM-7).
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  Future<String> ready(List<Map<String, Object?>> steps) async {
    h = await ServerHarness.start(steps: steps);
    await h.initialize();
    return h.newSession();
  }

  Map<String, Object?> call(
    String id,
    String name,
    Map<String, Object?> args,
  ) => {
    'reply': [
      {
        'toolCall': {'id': id, 'name': name, 'arguments': args},
      },
    ],
  };

  Future<JsonRpcRequest> nextRequest(String method) async {
    while (true) {
      final frame = await h.client.next();
      if (frame case JsonRpcRequest(method: final m) when m == method) {
        return frame;
      }
    }
  }

  Future<void> cancel(String sessionId) =>
      h.client.notify('session/cancel', {'sessionId': sessionId});

  Map<String, Object?> lastUpdateOf(JsonRpcResponse response, String id) {
    final index = h.client.received.indexOf(response);
    return TestClient.updates(
      h.client.received.take(index),
    ).lastWhere((u) => u['toolCallId'] == id);
  }

  test('cancel during the model stream answers cancelled', () async {
    final sessionId = await ready([
      {'waitForCancel': true},
    ]);

    final turn = h.prompt(sessionId, 'Hi');
    await pumpEventQueue();
    await cancel(sessionId);

    expect((await turn).resultMap, {'stopReason': 'cancelled'});
  });

  test('cancel during a permission request: the call is cancelled', () async {
    final sessionId = await ready([
      call('call_2', 'write', {'path': 'a.txt', 'content': 'a'}),
    ]);
    h.client.serveFiles(MemoryExecutionEnv(cwd: '/work/demo'));

    final turn = h.prompt(sessionId, 'Write a.txt');
    final permission = await nextRequest('session/request_permission');
    await cancel(sessionId);
    final response = await turn;

    expect(response.resultMap, {'stopReason': 'cancelled'});
    final finished = lastUpdateOf(response, 'call_2');
    expect(finished['status'], 'failed');
    expect(finished['_meta'], {
      'codelab': {'outcome': 'cancelled'},
    });
    // Поздний ответ клиента на отменённый запрос не меняет решения (PERM-4).
    await h.client.respond(permission, {
      'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
    });
    await pumpEventQueue();
    final after = TestClient.updates(
      h.client.received.skip(h.client.received.indexOf(response) + 1),
    );
    expect(after.where((u) => u['toolCallId'] == 'call_2'), isEmpty);
  });

  test('cancel during terminal/wait_for_exit: kill, output, release', () async {
    final sessionId = await ready([
      call('call_3', 'exec', {'command': 'sleep 60'}),
    ]);
    // Отдельные присваивания: стрелочное тело поглотило бы каскад.
    final handlers = h.client.handlers;
    handlers['session/request_permission'] = (_) => {
      'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
    };
    handlers['terminal/create'] = (_) => {'terminalId': 'term_1'};
    handlers['terminal/kill'] = (_) => <String, Object?>{};
    handlers['terminal/output'] = (_) => {
      'output': 'zzz\n',
      'truncated': false,
    };
    handlers['terminal/release'] = (_) => <String, Object?>{};

    final turn = h.prompt(sessionId, 'Sleep');
    await nextRequest('terminal/wait_for_exit');
    await cancel(sessionId);
    final response = await turn;

    expect(response.resultMap, {'stopReason': 'cancelled'});
    final terminal = [
      for (final frame in h.client.received)
        if (frame case JsonRpcRequest(
          :final method,
        ) when method.startsWith('terminal/'))
          method,
    ];
    expect(terminal, [
      'terminal/create',
      'terminal/wait_for_exit',
      'terminal/kill',
      'terminal/output',
      'terminal/release',
    ]);
    final finished = lastUpdateOf(response, 'call_3');
    expect(finished['status'], 'failed');
    expect(finished['_meta'], {
      'codelab': {'outcome': 'cancelled'},
    });
    final index = h.client.received.indexOf(response);
    final terminalContent = [
      for (final u in TestClient.updates(h.client.received.take(index)))
        if (u['toolCallId'] == 'call_3')
          for (final c in (u['content'] as List<Object?>?) ?? const [])
            if ((c! as Map)['type'] == 'terminal') c,
    ];
    expect(terminalContent, [
      {'type': 'terminal', 'terminalId': 'term_1'},
    ]);
  });

  test('cancel without a turn is logged and sends nothing', () async {
    final sessionId = await ready(const []);

    await cancel(sessionId);
    final frames = await h.client.drain();

    expect(frames, isEmpty);
    expect(h.logger.eventsOf('acp.cancel.no_turn'), hasLength(1));
  });

  test('session/cancel sent as a request is also answered with null', () async {
    final sessionId = await ready([
      {'waitForCancel': true},
    ]);

    final turn = h.prompt(sessionId, 'Hi');
    await pumpEventQueue();
    final answer = await h.client.request('session/cancel', {
      'sessionId': sessionId,
    });

    expect(answer.error, isNull);
    expect(answer.result, isNull);
    expect((await turn).resultMap, {'stopReason': 'cancelled'});
  });
}
