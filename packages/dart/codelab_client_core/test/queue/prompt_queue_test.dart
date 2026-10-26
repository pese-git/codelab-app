// Тесты очереди промптов и отмены хода (tasks 4.1; spec acp-client-kit
// «Очередь промптов на сессию», design D7).

import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

void main() {
  late _Harness h;

  setUp(() async {
    h = _Harness();
    await h.start();
  });
  tearDown(() => h.dispose());

  test('queued prompt is sent after the turn ends', () async {
    final session = await h.newSession('s-1');
    final first = h.next(sessionPromptMethod);
    final sent = session.send('first');
    final firstRequest = await first;

    final queued = await session.send('second');
    expect(queued, isA<PromptQueued>());
    expect(session.current.queue.map((item) => item.text), ['second']);
    expect(session.queue.items, session.current.queue);

    final second = h.next(sessionPromptMethod);
    h.endTurn(firstRequest);
    final secondRequest = await second;
    expect(_promptText(secondRequest), 'second');
    expect(session.current.queue, isEmpty);

    h.endTurn(secondRequest);
    final outcome = await sent;
    expect(outcome, isA<PromptCompleted>());
    expect(h.outcomes.whereType<PromptCompleted>(), hasLength(2));
    expect(session.current.status, SessionStatusView.idle);
  });

  test('send() completes after the whole queue of its session has '
      'drained', () async {
    final session = await h.newSession('s-1');
    final first = h.next(sessionPromptMethod);
    var done = false;
    unawaited(session.send('first').then((_) => done = true));
    final firstRequest = await first;
    await session.send('second');

    final second = h.next(sessionPromptMethod);
    h.endTurn(firstRequest);
    final secondRequest = await second;
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);

    h.endTurn(secondRequest);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(done, isTrue);
  });

  test('queues of different sessions are independent', () async {
    final a = await h.newSession('s-a');
    final firstA = h.next(sessionPromptMethod);
    final sentA = a.send('a1');
    final requestA = await firstA;
    await a.send('a2');

    final b = await h.newSession('s-b');
    expect(b.current.queue, isEmpty);

    final drained = h.next(sessionPromptMethod);
    h.endTurn(requestA);
    final next = await drained;
    expect(next.params, containsPair('sessionId', 's-a'));
    expect(_promptText(next), 'a2');
    expect(b.current.queue, isEmpty);

    h.endTurn(next);
    await sentA;
  });

  test('remove() and clear() work by stable id; ids are never '
      'reused', () async {
    final session = await h.newSession('s-1');
    final first = h.next(sessionPromptMethod);
    final sent = session.send('first');
    final request = await first;
    for (final text in ['one', 'two', 'three']) {
      await session.send(text);
    }
    final ids = session.queue.items.map((item) => item.id).toList();
    expect(ids.toSet(), hasLength(3));

    final removed = session.queue.remove(ids[1]);
    expect(removed?.text, 'two');
    expect(session.queue.remove(ids[1]), isNull);
    expect(session.current.queue.map((item) => item.text), ['one', 'three']);

    await session.send('four');
    expect(ids, isNot(contains(session.queue.items.last.id)));

    session.queue.clear();
    expect(session.current.queue, isEmpty);

    final sentAfterClear = h.transport.sentMessages.length;
    h.endTurn(request);
    await sent;
    expect(h.transport.sentMessages, hasLength(sentAfterClear));
  });

  test('sendNow() of a busy session leaves the item in place', () async {
    final session = await h.newSession('s-1');
    final first = h.next(sessionPromptMethod);
    final sent = session.send('first');
    final request = await first;
    await session.send('queued');
    final id = session.queue.items.single.id;
    final sentBefore = h.transport.sentMessages.length;

    expect(await session.queue.sendNow(id), isNull);
    expect(await session.queue.sendNow('missing'), isNull);

    expect(session.queue.items.single.id, id);
    expect(h.transport.sentMessages, hasLength(sentBefore));

    final drained = h.next(sessionPromptMethod);
    h.endTurn(request);
    h.endTurn(await drained);
    await sent;
  });

  test('cancel() sends session/cancel; the session stays cancelling until '
      'the agent answers, then the queue drains', () async {
    final session = await h.newSession('s-1');
    final first = h.next(sessionPromptMethod);
    final sent = session.send('cancel me');
    final request = await first;
    await session.send('after cancel');

    final cancelFrame = h.transport.sent.firstWhere(
      (message) =>
          message is JsonRpcNotification &&
          message.method == sessionCancelMethod,
    );
    await session.cancel();
    expect(await cancelFrame, isA<JsonRpcNotification>());
    expect(session.current.status, SessionStatusView.cancelling);
    expect(session.current.queue, hasLength(1));

    final drained = h.next(sessionPromptMethod);
    h.endTurn(request, stopReason: 'cancelled');
    final next = await drained;
    expect(_promptText(next), 'after cancel');

    h.endTurn(next);
    await sent;
    expect(session.current.status, SessionStatusView.idle);
  });

  test('a failed prompt is a PromptFailed outcome and frees the '
      'session', () async {
    final session = await h.newSession('s-1');
    final first = h.next(sessionPromptMethod);
    final sent = session.send('fails');
    final request = await first;
    h.transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        error: const JsonRpcError(code: -32603, message: 'agent crashed'),
      ),
    );

    final outcome = await sent;
    expect(outcome, isA<PromptFailed>());
    expect(h.outcomes.single, same(outcome));
    expect(session.current.status, isNot(SessionStatusView.running));
  });
}

String _promptText(JsonRpcRequest request) {
  final prompt = (request.params! as Map)['prompt'] as List;
  return (prompt.single as Map)['text'] as String;
}

/// Рабочее пространство поверх `FakeAcpTransport` с подписью на исходы
/// промптов.
final class _Harness {
  final transport = FakeAcpTransport();
  final application = AcpClientApplication(transport: FakeAcpTransport());
  late final ClientWorkspace workspace = ClientWorkspace(
    backend: AcpClientBackend(application),
    resolvers: [ConfigTransportResolver(stdio: (_) => transport)],
  );
  final outcomes = <PromptOutcome>[];
  StreamSubscription<PromptOutcome>? _subscription;

  Future<void> start() async {
    _subscription = workspace.promptOutcomes.listen(outcomes.add);
    await workspace.connect(
      const StdioProfile(id: 'agent', label: 'Agent', command: 'agent'),
      projectDirectory: '/work',
    );
  }

  Future<SessionHandle> newSession(String id) async {
    final request = next(sessionNewMethod);
    final handle = workspace.newSession();
    transport.emitInbound(
      JsonRpcMessage.response(
        id: (await request).id,
        result: {'sessionId': id},
      ),
    );
    return handle;
  }

  Future<JsonRpcRequest> next(String method) async =>
      await transport.sent.firstWhere(
            (message) => message is JsonRpcRequest && message.method == method,
          )
          as JsonRpcRequest;

  void endTurn(JsonRpcRequest request, {String stopReason = 'end_turn'}) =>
      transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: {'stopReason': stopReason},
        ),
      );

  Future<void> dispose() async {
    await _subscription?.cancel();
    await workspace.dispose();
    await application.dispose();
  }
}
