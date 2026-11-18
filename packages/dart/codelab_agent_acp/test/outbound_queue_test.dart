import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_acp/src/connection/outbound_queue.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

/// Контракт [OutboundQueue] (§13.1, ACP-3) и линейность отправки длинной
/// серии кадров.
///
/// Почему линейность проверяется отдельно: реплей `session/load` ставит все
/// кадры синхронно. Пока очередь строила цепочку `then` длиной в число
/// кадров, под `flutter test` (он всегда включает `--chain-stack-traces`,
/// то есть `Chain.capture`) каждый обратный вызов снимал
/// `StackTrace.current`, а VM при снимке обходит всю незавершённую цепочку.
/// В сумме реплей шёл за O(N²): 8000 кадров — 28,6 с против 12 мс под
/// `dart test`. Тест воспроизводит это зоной, которая снимает стек на каждой
/// регистрации обратного вызова, и под `dart test`.
void main() {
  JsonRpcMessage frame(int i) =>
      JsonRpcMessage.notification(method: 'session/update', params: {'i': i});

  test('frames are sent in enqueue order; each future completes after its '
      'send', () async {
    final transport = _RecordingTransport();
    final queue = OutboundQueue(transport, logger: RecordingLogger());
    final completed = <int>[];
    final futures = [
      for (var i = 0; i < 5; i++)
        queue.enqueue(frame(i)).then((_) {
          // Свой кадр уже ушёл к моменту завершения Future.
          expect(transport.sent, hasLength(greaterThan(i)));
          completed.add(i);
        }),
    ];
    // `send` не вызывается изнутри `enqueue`: на этом держится порядок
    // «ответ, затем `after`» маршрутизатора.
    expect(transport.calls, 0);
    await Future.wait(futures);
    expect(
      [
        for (final m in transport.sent)
          ((m as JsonRpcNotification).params! as Map)['i'],
      ],
      [0, 1, 2, 3, 4],
    );
    expect(completed, [0, 1, 2, 3, 4]);
  });

  test(
    'a send failure is logged, reported, and does not stop the queue',
    () async {
      final transport = _RecordingTransport()..failOn = {1};
      final logger = RecordingLogger();
      final failures = <Object>[];
      final queue = OutboundQueue(
        transport,
        logger: logger,
        onSendFailed: failures.add,
      );
      // Future кадра со сбоем завершается без ошибки: сбой идёт в лог и
      // onSendFailed, а не вызывающему.
      await Future.wait([for (var i = 0; i < 3; i++) queue.enqueue(frame(i))]);
      expect(transport.sent, hasLength(2));
      expect(failures, hasLength(1));
      expect(logger.eventsOf('acp.send.failed'), hasLength(1));
    },
  );

  test(
    'a throwing onSendFailed is logged and does not stop the queue',
    () async {
      final transport = _RecordingTransport()..failOn = {0};
      final logger = RecordingLogger();
      final queue = OutboundQueue(
        transport,
        logger: logger,
        onSendFailed: (_) => throw StateError('handler failed'),
      );
      // Ни Future кадров, ни idle не висят и не завершаются ошибкой.
      await Future.wait([
        for (var i = 0; i < 3; i++) queue.enqueue(frame(i)),
      ]).timeout(const Duration(seconds: 5));
      await queue.idle.timeout(const Duration(seconds: 5));
      expect(transport.sent, hasLength(2));
      expect(logger.eventsOf('acp.send.failed'), hasLength(1));
      expect(logger.eventsOf('acp.send.failed_handler'), hasLength(1));
    },
  );

  test('idle completes after every enqueued frame is sent', () async {
    final transport = _RecordingTransport();
    final queue = OutboundQueue(transport, logger: RecordingLogger());
    await queue.idle;
    for (var i = 0; i < 3; i++) {
      unawaited(queue.enqueue(frame(i)));
    }
    await queue.idle;
    expect(transport.sent, hasLength(3));
    // idle, взятый во время отправки, ждёт и кадры, поставленные после него.
    unawaited(queue.enqueue(frame(3)));
    final idle = queue.idle;
    unawaited(queue.enqueue(frame(4)));
    await idle;
    expect(transport.sent, hasLength(5));
    // Кадр после опустевшей очереди снова отправляется.
    unawaited(queue.enqueue(frame(5)));
    await queue.idle;
    expect(transport.sent, hasLength(6));
  });

  test('sending 2N frames costs about twice N even when every callback '
      'captures a stack trace (flutter test, Chain.capture)', () async {
    Future<Duration> sendAll(int n) async {
      final link = InProcessAcpLink();
      final queue = OutboundQueue(link.agent, logger: RecordingLogger());
      var received = 0;
      final done = Completer<void>();
      link.client.inbound.listen((_) {
        if (++received == n) {
          done.complete();
        }
      });
      await link.agent.start();
      await link.client.start();
      final watch = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        unawaited(queue.enqueue(frame(i)));
      }
      await done.future;
      await queue.idle;
      watch.stop();
      await link.agent.close();
      await link.client.close();
      return watch.elapsed;
    }

    // Минимум из трёх замеров: одиночная пауза GC или вытеснение раннера на
    // CI не роняет тест (флейк — дефект, `docs/architecture/testing.md`).
    Future<Duration> measured(int n) async {
      Duration? best;
      for (var run = 0; run < 3; run++) {
        final elapsed = await _capturingStacks(() => sendAll(n));
        if (best == null || elapsed < best) {
          best = elapsed;
        }
      }
      return best!;
    }

    const n = 2000;
    await _capturingStacks(() => sendAll(n)); // прогрев JIT
    final single = await measured(n);
    final twice = await measured(2 * n);
    // Линейно — около 2×; квадратично — около 4× и больше (до правки:
    // 0,57 с против 2,23 с). Запас на шум малых времён — 50 мс.
    expect(
      twice.inMicroseconds,
      lessThan(3 * single.inMicroseconds + 50000),
      reason: 'N=$n: $single, 2N: $twice',
    );
  });
}

/// Выполняет [body] в зоне, которая, как `Chain.capture`, снимает
/// `StackTrace.current` на каждой регистрации обратного вызова.
Future<T> _capturingStacks<T>(Future<T> Function() body) => Zone.current
    .fork(
      specification: ZoneSpecification(
        registerCallback: <R>(self, parent, zone, fn) {
          StackTrace.current;
          return parent.registerCallback(zone, fn);
        },
        registerUnaryCallback: <R, A>(self, parent, zone, fn) {
          StackTrace.current;
          return parent.registerUnaryCallback(zone, fn);
        },
        registerBinaryCallback: <R, A, B>(self, parent, zone, fn) {
          StackTrace.current;
          return parent.registerBinaryCallback(zone, fn);
        },
      ),
    )
    .run(body);

/// Транспорт, который записывает отправленные кадры и бросает на кадрах с
/// индексами из [failOn].
final class _RecordingTransport implements AcpTransport {
  final sent = <JsonRpcMessage>[];
  var failOn = <int>{};

  /// Число вызовов [send], включая неудачные.
  var calls = 0;

  @override
  Future<void> send(JsonRpcMessage message) async {
    final index = calls++;
    // Отправка асинхронна, как у настоящих транспортов.
    await Future<void>.delayed(Duration.zero);
    if (failOn.contains(index)) {
      throw StateError('send failed');
    }
    sent.add(message);
  }

  @override
  Stream<JsonRpcMessage> get inbound => const Stream.empty();

  @override
  Stream<AcpTransportEvent> get events => const Stream.empty();

  @override
  AcpTransportState get state => AcpTransportState.connected;

  @override
  Future<void> start() async {}

  @override
  Future<void> close({Duration? timeout}) async {}
}
