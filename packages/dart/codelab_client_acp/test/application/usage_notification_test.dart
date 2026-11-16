// Приём уведомления `_codelab/session/usage` ядром клиента (задача 2.2
// change `add-usage-extension`; spec acp-protocol-client «Приём уведомления
// `_codelab/session/usage`»: «Снимок во время хода», «Снимок после ответа на
// prompt», «Уведомление старого соединения»; design.md, D7, D8, D14,
// D21 Т2, Т5).
//
// Красные тесты: публичного потока `AcpClientApplication.usageNotifications`
// ещё нет (задача 2.8) — файл не компилируется. Имя потока и форма записи
// (`sessionId`, `params`, `generation`) — предложение этой задачи: D21 Т2
// требует лишь «публичный broadcast-поток с записью "sessionId, params,
// поколение"». Гонки собраны принудительным порядком кадров, без таймеров.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');

/// Маркер утечки: ни одна запись журнала, кроме трассировки протокола, не
/// должна содержать payload уведомления (D14: payload — только в
/// трассировке `category=protocol`).
const _leak = 'sk-test-leak-0123456789';

/// Транспорт «прежнего соединения»: после замены его подписка на `inbound`
/// не снимается, и кадр доходит до ядра клиента позже замены. Это модель
/// позднего события (`streaming.md` §9): защита по поколению в
/// `_bindTransport` должна отбросить кадр до маршрутизации.
///
/// `FakeAcpTransport` — `final class`, поэтому это обёртка над ним, а не
/// наследник.
final class _LateTransport implements AcpTransport {
  final inner = FakeAcpTransport();

  @override
  Stream<JsonRpcMessage> get inbound => _NoCancelStream(inner.inbound);

  @override
  Stream<AcpTransportEvent> get events => inner.events;

  @override
  AcpTransportState get state => inner.state;

  @override
  Future<void> start() => inner.start();

  @override
  Future<void> send(JsonRpcMessage message) => inner.send(message);

  /// Не закрывает транспорт: кадры прежнего агента ещё «в пути».
  @override
  Future<void> close({Duration? timeout}) async {}

  void emitInbound(JsonRpcMessage message) => inner.emitInbound(message);
}

final class _NoCancelStream extends Stream<JsonRpcMessage> {
  _NoCancelStream(this._source);

  final Stream<JsonRpcMessage> _source;

  @override
  StreamSubscription<JsonRpcMessage> listen(
    void Function(JsonRpcMessage event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _NoCancelSubscription(
    _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
  );
}

/// Подписка, у которой `cancel` ничего не снимает.
final class _NoCancelSubscription
    implements StreamSubscription<JsonRpcMessage> {
  _NoCancelSubscription(this._inner);

  final StreamSubscription<JsonRpcMessage> _inner;

  @override
  Future<void> cancel() => Future<void>.value();

  @override
  void onData(void Function(JsonRpcMessage data)? handleData) =>
      _inner.onData(handleData);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  bool get isPaused => _inner.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}

/// Запись журнала: уровень, событие и контекст вместе с привязанным.
typedef _Entry = ({String level, String? event, Map<String, Object?> context});

/// Журнал, который копит записи всех дочерних логгеров (`bind`,
/// `withCorrelation`) в общий список: тесту нужен состав записей, а не
/// их вывод.
final class _RecordingLogger implements Logger {
  _RecordingLogger([List<_Entry>? entries, Map<String, Object?>? context])
    : entries = entries ?? <_Entry>[],
      _context = context ?? const {};

  final List<_Entry> entries;
  final Map<String, Object?> _context;

  @override
  Logger bind(Map<String, Object?> context) =>
      _RecordingLogger(entries, {..._context, ...context});

  @override
  Logger withCorrelation({
    String? sessionId,
    String? requestId,
    int? connectionGeneration,
    String? toolCallId,
    String? messageId,
    String? operationId,
  }) => _RecordingLogger(entries, {
    ..._context,
    'session_id': ?sessionId,
    'request_id': ?requestId,
    'connection_generation': ?connectionGeneration,
    'tool_call_id': ?toolCallId,
    'message_id': ?messageId,
    'operation_id': ?operationId,
  });

  void _add(String level, String? event, Map<String, Object?>? context) =>
      entries.add((
        level: level,
        event: event,
        context: {..._context, ...?context},
      ));

  @override
  void trace(String? event, {Map<String, Object?>? context}) =>
      _add('trace', event, context);

  @override
  void debug(String? event, {Map<String, Object?>? context}) =>
      _add('debug', event, context);

  @override
  void info(String? event, {Map<String, Object?>? context}) =>
      _add('info', event, context);

  @override
  void warning(String? event, {Map<String, Object?>? context}) =>
      _add('warning', event, context);

  @override
  void error(String? event, {Map<String, Object?>? context}) =>
      _add('error', event, context);

  @override
  void critical(String? event, {Map<String, Object?>? context}) =>
      _add('critical', event, context);
}

Map<String, Object?> _snapshot({
  required int seq,
  String trigger = 'turn',
  Object? sessionId = 'session-1',
  Map<String, Object?> extra = const {},
}) => {
  'sessionId': ?sessionId,
  'seq': seq,
  'trigger': trigger,
  'turnId': 'turn-1',
  'turn': {
    'steps': 1,
    'tokens': {'input': 10, 'output': 5, 'cacheRead': 0, 'cacheWrite': 0},
  },
  'session': {
    'turns': 1,
    'steps': 1,
    'tokens': {'input': 10, 'output': 5, 'cacheRead': 0, 'cacheWrite': 0},
  },
  ...extra,
};

JsonRpcMessage _usageFrame(Map<String, Object?> params) =>
    JsonRpcMessage.notification(
      method: '_codelab/session/usage',
      params: params,
    );

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;
  late _RecordingLogger logger;
  late List<dynamic> delivered;

  Future<void> createSession() async {
    transport.drainSentMessages();
    final future = client.createSession(
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
    await future;
    transport.drainSentMessages();
  }

  /// [connectWith] — обёртка вокруг [agent], если тест подменяет транспорт.
  Future<void> start(
    FakeAcpTransport agent, {
    AcpTransport? connectWith,
  }) async {
    transport = agent;
    logger = _RecordingLogger();
    client = AcpClientApplication(
      transport: FakeAcpTransport(),
      logger: logger,
    );
    addTearDown(client.dispose);
    delivered = <dynamic>[];
    final subscription = client.usageNotifications.listen(delivered.add);
    addTearDown(subscription.cancel);
    await client.connect(connectWith ?? transport);
    await createSession();
  }

  /// Отправляет prompt; возвращает его запрос и будущий ход.
  Future<(JsonRpcRequest, Future<PromptTurn>)> sendPrompt() async {
    final turn = client.sendPrompt(
      const SendPromptCommand(
        sessionId: _session,
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    );
    await pumpEventQueue();
    final request = transport.drainSentMessages().single as JsonRpcRequest;
    return (request, turn);
  }

  void expectNoPayloadInLogs() {
    // Трассировка протокола — единственное место payload (D14).
    for (final e in logger.entries.where((e) => e.level != 'trace')) {
      expect('${e.event}${e.context}', isNot(contains(_leak)));
    }
  }

  group('a snapshot of the live connection', () {
    setUp(() => start(FakeAcpTransport()));

    test('during a turn is delivered and the turn stays running', () async {
      final (request, turn) = await sendPrompt();
      final params = _snapshot(seq: 1, trigger: 'step');

      transport.emitInbound(_usageFrame(params));

      expect(delivered, hasLength(1));
      expect(delivered.single.sessionId, _session);
      expect(delivered.single.params, params);
      expect(delivered.single.generation, client.generation);
      expect(
        client.sessionById(_session)!.activeTurn?.status,
        PromptTurnStatus.running,
      );

      transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
        ),
      );
      await turn;
    });

    test('after the prompt response is delivered and the completed turn is '
        'unchanged', () async {
      final (request, turn) = await sendPrompt();
      transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
        ),
      );
      expect((await turn).status, PromptTurnStatus.completed);

      transport.emitInbound(_usageFrame(_snapshot(seq: 2)));

      expect(delivered, hasLength(1));
      expect(delivered.single.params['seq'], 2);
      expect(
        client.sessionById(_session)!.turns.last.status,
        PromptTurnStatus.completed,
      );
      expect(client.sessionById(_session)!.activeTurn, isNull);
    });

    test('the client never answers the notification', () async {
      transport.emitInbound(_usageFrame(_snapshot(seq: 1)));
      transport.emitInbound(_usageFrame(_snapshot(seq: 2, sessionId: null)));

      // У уведомления нет id: ответа быть не должно.
      expect(transport.sentMessages, isEmpty);
    });

    test('a delivered snapshot is logged as usage.received without payload '
        '(D14)', () async {
      transport.emitInbound(
        _usageFrame(_snapshot(seq: 7, trigger: 'step', extra: {'note': _leak})),
      );

      final entry = logger.entries.singleWhere(
        (e) => e.event == 'usage.received',
      );
      expect(entry.level, 'debug');
      expect(entry.context['seq'], 7);
      expect(entry.context['trigger'], 'step');
      expect(entry.context['session_id'], _session.value);
      expectNoPayloadInLogs();
    });

    for (final (name, sessionId) in <(String, Object?)>[
      ('missing', null),
      ('a number', 42),
      ('a map', {'id': 'session-1'}),
    ]) {
      test('params.sessionId $name is not delivered, DEBUG without payload '
          '(D14, D21 Т2)', () async {
        transport.emitInbound(
          _usageFrame(
            _snapshot(seq: 1, sessionId: sessionId, extra: {'note': _leak}),
          ),
        );

        expect(delivered, isEmpty);
        expect(
          logger.entries.where(
            (e) => e.level == 'debug' && (e.event ?? '').contains('usage'),
          ),
          isNotEmpty,
          reason: 'отброс без sessionId оставляет запись DEBUG',
        );
        expectNoPayloadInLogs();
      });
    }
  });

  group('after reconnect', () {
    test('a frame of the previous transport is dropped as stale, a frame of '
        'the new one carries the new generation', () async {
      final previous = _LateTransport();
      await start(previous.inner, connectWith: previous);
      final generationBefore = client.generation;

      final replacement = FakeAcpTransport();
      addTearDown(replacement.close);
      await client.reconnect(
        ReconnectCommand(transportFactory: () => replacement),
      );
      expect(client.generation, generationBefore + 1);
      logger.entries.clear();

      // Кадр прежнего агента доходит уже после замены.
      previous.emitInbound(_usageFrame(_snapshot(seq: 9)));

      expect(delivered, isEmpty);
      final ignored = logger.entries.where(
        (e) =>
            e.event == 'event_ignored' &&
            e.context['reason'] == 'stale_generation',
      );
      expect(ignored, hasLength(1));
      expect(ignored.single.level, 'debug');
      expect(ignored.single.context['connection_generation'], generationBefore);

      // Кадр нового соединения передан с номером его поколения.
      replacement.emitInbound(_usageFrame(_snapshot(seq: 1)));

      expect(delivered, hasLength(1));
      expect(delivered.single.generation, client.generation);
      expect(delivered.single.params['seq'], 1);
    });
  });
}
