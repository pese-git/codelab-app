// Буфер кадров протокола `ProtocolFrameLog` (задача 2.1 `[client]` change
// `redesign-protocol-pane`; design.md, D5, D6, D17; spec acp-client-kit
// «Буфер кадров протокола»).
//
// Красный тест: файл не компилируется, пока задача 2.2 не добавит
// `AgentBackend.protocolFrames`, `traceAvailable`, `setFrameTrace`,
// `ClientWorkspace.protocolFrames` и `ProtocolFrameLog` (`frames`, `changes`,
// `revision`, `clear`, `traceAvailable`, `traceEnabled`, `setTrace`). Имена
// членов буфера — из D5. Поведение `setTrace` при недоступном Trace spec не
// определяет, поэтому тест его не проверяет (см. отчёт этапа 1).
//
// Тест идёт на фейковом `AgentBackend`: кадры подаёт сам тест, транспорт и
// ядро клиента не нужны. Поток кадров бэкенда — `sync: false`, как у
// настоящего ядра (D2), поэтому после каждой подачи ждём очередь событий.

import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/usage_agent.dart' show RecordingLogger;

void main() {
  late _FakeBackend backend;
  late RecordingLogger logger;
  late ClientWorkspace workspace;

  Future<void> create({bool traceAvailable = true}) async {
    backend = _FakeBackend(traceAvailable: traceAvailable);
    logger = RecordingLogger();
    workspace = ClientWorkspace(
      backend: backend,
      resolvers: const [],
      logger: logger,
    );
  }

  Future<void> push(ProtocolFrame frame) async {
    backend.frames.add(frame);
    await pumpEventQueue();
  }

  tearDown(() async {
    await workspace.dispose();
    await backend.close();
  });

  group('пределы', () {
    setUp(create);

    test('2001-й кадр вытесняет первый, ревизия растёт', () async {
      final log = workspace.protocolFrames;
      for (var i = 0; i < 2000; i++) {
        backend.frames.add(_frame(i));
      }
      await pumpEventQueue();
      expect(log.frames, hasLength(2000));
      final before = log.revision;

      await push(_frame(2000));

      expect(log.frames, hasLength(2000));
      expect(log.frames.first.seq, 1);
      expect(log.frames.last.seq, 2000);
      expect(log.revision, greaterThan(before));
    });

    test('сумма payload не больше 8 MiB: вытесняются самые старые', () async {
      final log = workspace.protocolFrames;
      // Около 200 KB payload в каждом кадре: 60 кадров заведомо больше 8 MiB.
      for (var i = 0; i < 60; i++) {
        backend.frames.add(_frame(i, payload: {'text': 'x' * 200000}));
      }
      await pumpEventQueue();

      final total = log.frames.fold<int>(
        0,
        (sum, f) => sum + utf8.encode(jsonEncode(f.payload)).length,
      );
      expect(total, lessThanOrEqualTo(8 * 1024 * 1024));
      expect(log.frames.first.seq, greaterThan(0));
      expect(log.frames.last.seq, 59);
      // Вытеснено ровно столько, сколько нужно, а не весь буфер.
      expect(log.frames.length, greaterThan(30));
    });

    test('кадры без payload не расходуют лимит объёма', () async {
      final log = workspace.protocolFrames;
      for (var i = 0; i < 100; i++) {
        backend.frames.add(_frame(i));
      }
      await pumpEventQueue();
      expect(log.frames, hasLength(100));
    });
  });

  group('жизненный цикл', () {
    setUp(create);

    test('кадры переживают переподключение', () async {
      final log = workspace.protocolFrames;
      for (var i = 0; i < 10; i++) {
        backend.frames.add(_frame(i, generation: 1));
      }
      for (var i = 10; i < 13; i++) {
        backend.frames.add(_frame(i, generation: 2));
      }
      await pumpEventQueue();

      expect(log.frames.map((f) => f.seq), List.generate(13, (i) => i));
      expect(log.frames.map((f) => f.connectionGeneration).toSet(), {1, 2});
      expect(log.frames.first.connectionGeneration, 1);
      expect(log.frames.last.connectionGeneration, 2);
    });

    test(
      'clear удаляет всё и поднимает ревизию, запись продолжается',
      () async {
        final log = workspace.protocolFrames;
        for (var i = 0; i < 412; i++) {
          backend.frames.add(_frame(i));
        }
        await pumpEventQueue();
        final before = log.revision;
        final signals = <void>[];
        final sub = log.changes.listen(signals.add);
        addTearDown(sub.cancel);

        log.clear();
        await pumpEventQueue();

        expect(log.frames, isEmpty);
        expect(log.revision, greaterThan(before));
        expect(signals, isNotEmpty);

        await push(_frame(500));
        expect(log.frames.single.seq, 500);
      },
    );

    test('ревизия растёт на каждое изменение, снимок неизменяем', () async {
      final log = workspace.protocolFrames;
      final snapshot = log.frames;
      var revision = log.revision;
      for (var i = 0; i < 3; i++) {
        await push(_frame(i));
        expect(log.revision, greaterThan(revision));
        revision = log.revision;
      }
      expect(snapshot, isEmpty);
      expect(() => log.frames.add(_frame(99)), throwsUnsupportedError);
    });

    test('changes — сигнал без копии списка', () async {
      final log = workspace.protocolFrames;
      var signals = 0;
      final sub = log.changes.listen((_) => signals++);
      addTearDown(sub.cancel);

      await push(_frame(1));
      await push(_frame(2));

      expect(signals, 2);
    });

    test(
      'закрытие рабочего пространства отписывает и закрывает changes',
      () async {
        final log = workspace.protocolFrames;
        await push(_frame(1));
        final closed = log.changes.drain<void>();
        final revision = log.revision;

        await workspace.dispose();
        await closed.timeout(const Duration(seconds: 5));
        expect(backend.frames.hasListener, isFalse);

        // Бэкенд может публиковать и дальше: буфер уже не слушает.
        backend.frames.add(_frame(2));
        await pumpEventQueue();
        expect(log.frames.map((f) => f.seq), [1]);
        expect(log.revision, revision);
      },
    );
  });

  group('запрос session/new получает сессию из результата (D6)', () {
    setUp(create);

    test(
      'результат привязывает кадр запроса, seq и место сохраняются',
      () async {
        final log = workspace.protocolFrames;
        await push(
          _frame(
            10,
            generation: 2,
            kind: ProtocolFrameKind.request,
            method: sessionNewMethod,
            id: const JsonRpcId.integer(1),
          ),
        );
        await push(_frame(11, generation: 2));
        final before = log.revision;

        await push(
          _frame(
            12,
            generation: 2,
            direction: ProtocolFrameDirection.inbound,
            kind: ProtocolFrameKind.result,
            method: sessionNewMethod,
            id: const JsonRpcId.integer(1),
            sessionId: 's_91c0',
          ),
        );

        expect(log.frames.map((f) => f.seq), [10, 11, 12]);
        expect(log.frames[0].sessionId, 's_91c0');
        expect(log.frames[1].sessionId, isNull);
        expect(log.revision, greaterThan(before));
      },
    );

    test('запрос другого поколения с тем же id не привязывается', () async {
      final log = workspace.protocolFrames;
      await push(
        _frame(
          10,
          generation: 1,
          kind: ProtocolFrameKind.request,
          method: sessionNewMethod,
          id: const JsonRpcId.integer(1),
        ),
      );
      await push(
        _frame(
          11,
          generation: 2,
          direction: ProtocolFrameDirection.inbound,
          kind: ProtocolFrameKind.result,
          method: sessionNewMethod,
          id: const JsonRpcId.integer(1),
          sessionId: 's_91c0',
        ),
      );

      expect(log.frames[0].sessionId, isNull);
    });

    test('ошибка на session/new не привязывает запрос', () async {
      final log = workspace.protocolFrames;
      await push(
        _frame(
          10,
          kind: ProtocolFrameKind.request,
          method: sessionNewMethod,
          id: const JsonRpcId.integer(1),
        ),
      );
      await push(
        _frame(
          11,
          direction: ProtocolFrameDirection.inbound,
          kind: ProtocolFrameKind.error,
          method: sessionNewMethod,
          id: const JsonRpcId.integer(1),
          errorCode: -32603,
        ),
      );

      expect(log.frames[0].sessionId, isNull);
      expect(log.frames[1].sessionId, isNull);
    });
  });

  group('режим Trace при базовой metadataOnly (D17)', () {
    setUp(create);

    test(
      'выключение снимает payload со всех кадров и обнуляет объём',
      () async {
        final log = workspace.protocolFrames;
        expect(log.traceAvailable, isTrue);
        expect(log.traceEnabled, isFalse);

        log.setTrace(true);
        expect(log.traceEnabled, isTrue);
        expect(backend.traceCalls, [true]);
        for (var i = 0; i < 30; i++) {
          backend.frames.add(_frame(i, payload: {'text': 'x' * 1000}));
        }
        await pumpEventQueue();
        expect(log.frames.where((f) => f.payload != null), hasLength(30));
        final before = log.revision;
        final first = log.frames.first;

        log.setTrace(false);
        await pumpEventQueue();

        expect(log.traceEnabled, isFalse);
        expect(backend.traceCalls, [true, false]);
        expect(log.frames, hasLength(30));
        for (final f in log.frames) {
          expect(f.payload, isNull);
          expect(f.payloadOmitted, ProtocolPayloadOmitted.policy);
        }
        // Остальные поля прежние.
        expect(log.frames.first.seq, first.seq);
        expect(log.frames.first.size, first.size);
        expect(log.frames.first.method, first.method);
        expect(log.revision, greaterThan(before));
        final dropped = logger.where('protocol_frames.payloads_dropped').single;
        expect(dropped.level, 'debug');
        expect(dropped.context['count'], 30);

        // Объём payload обнулён: новый payload в режиме Trace снова помещается.
        log.setTrace(true);
        for (var i = 100; i < 140; i++) {
          backend.frames.add(_frame(i, payload: {'text': 'y' * 200000}));
        }
        await pumpEventQueue();
        expect(log.frames.where((f) => f.payload != null), isNotEmpty);
      },
    );

    test('кадр в пути после выключения сохраняется без payload', () async {
      final log = workspace.protocolFrames;
      log.setTrace(true);
      log.setTrace(false);

      // Кадр построен ядром, пока Trace был включён, а доставлен после.
      await push(_frame(1, payload: {'secret': 'masked-already'}));

      final stored = log.frames.single;
      expect(stored.payload, isNull);
      expect(stored.payloadOmitted, ProtocolPayloadOmitted.policy);
      expect(stored.seq, 1);
    });

    test(
      'при выключенном Trace входящий payload не попадает в буфер',
      () async {
        final log = workspace.protocolFrames;
        await push(_frame(1, payload: {'a': 1}));
        expect(log.frames.single.payload, isNull);
      },
    );
  });

  group('Trace недоступен при базовой full', () {
    setUp(() => create(traceAvailable: false));

    test(
      'буфер сообщает о недоступности, payload кадров сохраняется',
      () async {
        final log = workspace.protocolFrames;
        expect(log.traceAvailable, isFalse);
        expect(log.traceEnabled, isFalse);

        await push(_frame(1, payload: {'a': 1}));

        expect(log.frames.single.payload, {'a': 1});
        expect(backend.traceCalls, isEmpty);
      },
    );
  });
}

ProtocolFrame _frame(
  int seq, {
  int generation = 0,
  ProtocolFrameDirection direction = ProtocolFrameDirection.outbound,
  ProtocolFrameKind kind = ProtocolFrameKind.notification,
  String? method = 'session/update',
  JsonRpcId? id,
  String? sessionId,
  int? errorCode,
  Map<String, Object?>? payload,
}) => ProtocolFrame(
  seq: seq,
  time: DateTime.utc(2026, 11, 22, 14, 0, 0).add(Duration(milliseconds: seq)),
  direction: direction,
  connectionGeneration: generation,
  kind: kind,
  method: method,
  id: id,
  sessionId: sessionId,
  detail: null,
  errorCode: errorCode,
  size: payload == null ? 120 : utf8.encode(jsonEncode(payload)).length,
  payload: payload,
  payloadOmitted: payload == null ? ProtocolPayloadOmitted.policy : null,
);

/// Фейковый порт: кадры подаёт тест; всё остальное kit в этих тестах не
/// вызывает, поэтому `noSuchMethod` бросает при случайном обращении.
final class _FakeBackend implements AgentBackend {
  _FakeBackend({required this.traceAvailable});

  /// Как у ядра с базовой `metadataOnly`; `false` — базовая `full`.
  @override
  final bool traceAvailable;

  final traceCalls = <bool>[];

  /// `sync: false`, как у `AcpClientApplication.protocolFrames` (D2).
  final frames = StreamController<ProtocolFrame>.broadcast();
  final _connection = StreamController<ClientConnectionState>.broadcast();
  final _sessions = StreamController<AcpSession>.broadcast();
  final _usage = StreamController<UsageNotification>.broadcast();

  @override
  Stream<ProtocolFrame> get protocolFrames => frames.stream;

  @override
  void setFrameTrace(bool enabled) => traceCalls.add(enabled);

  @override
  Stream<ClientConnectionState> get connectionStates => _connection.stream;

  @override
  Stream<AcpSession> get sessionChanges => _sessions.stream;

  @override
  Stream<UsageNotification> get usageNotifications => _usage.stream;

  @override
  int get generation => 0;

  Future<void> close() async {
    await frames.close();
    await _connection.close();
    await _sessions.close();
    await _usage.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
