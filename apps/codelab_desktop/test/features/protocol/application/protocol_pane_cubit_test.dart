// `ProtocolPaneCubit` (задача 4.5 change `redesign-protocol-pane`; spec
// agent-workbench-ui «Панель Protocol: виды Frames и Log», «Таблица кадров»,
// «Выбранный кадр», «Вид Log панели Protocol», «Pause, Clear и Export…»,
// «Режим Trace панели Protocol», «Клавиатура панели Protocol»; design.md D6,
// D7, D8, D10, D11, D14, D17).
//
// Красный до задачи 4.6: нет `ProtocolPaneCubit`, `ProtocolPaneState` и порта
// `LogRecordSource`. Ожидаемый публичный API фиксируют эти тесты (design.md D7
// перечисляет содержимое состояния, но не имена):
//
// * `LogRecordSource { List<Map<String, Object?>> get records;
//   Stream<void> get changes; void clear(); }` — как в D7;
// * `ProtocolPaneCubit({workspace, logRecords, exportSaver, basePolicy,
//   logger, publishInterval = 100 мс, appVersion = '', platform = '',
//   clock = DateTime.now})` (последние три — для экспорта, тест 4.7); начальное состояние строится из
//   текущего буфера, поэтому кадры, пришедшие до создания Cubit, видны;
// * `ProtocolPaneState`: `view` (`ProtocolView.frames | log`),
//   `focusedSessionId`, `frameFilter` (`ProtocolFrameFilter`), `logFilter`
//   (`LogRecordFilter`), `framesPaused`, `logPaused`, `visibleFrames`,
//   `visibleRecords` (область, фильтры и пауза применены), `framesCount`,
//   `logCount` (область без фильтров и паузы), `selectedFrame`,
//   `selectedRecord` (копии объектов, не индексы), `framesSplit`, `logSplit`
//   (`null` — доля по умолчанию), `traceAvailable`, `traceEnabled`,
//   `saveFailed`;
// * методы: `selectView`, `openLog` (для `/logs`), `setFrameQuery`,
//   `setShowRequests`, `setShowNotifications`, `setErrorsOnly`,
//   `setLogQuery`, `setLogCategory`, `setLogMinLevel`, `selectFrame`,
//   `selectRecord`, `selectNext`, `selectPrevious`, `togglePause`, `clear`,
//   `setTrace`, `setSplit`, `frameOfRecord`, `showFrameOfRecord`; экспорт —
//   в `protocol_export_test.dart`.
//
// Время — fake: `testWidgets` и `tester.pump(Duration)`; пакет `fake_async` в
// app не подключён (как в тестах терминала и onboarding), поэтому пункт 4.5
// про `fake_async` выполнен средствами `testWidgets`.

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_desktop/features/protocol/application/log_record_filter.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_frame_filter.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_cubit.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart' show LogLevel;

import '../../../support/fake_log_record_source.dart';
import '../../../support/fake_protocol_export_saver.dart';
import '../../../support/fake_protocol_workspace.dart';
import '../../../support/protocol_fixtures.dart';
import '../../../support/recording_logger.dart';

const _out = ProtocolFrameDirection.outbound;
const _in = ProtocolFrameDirection.inbound;
const _tick = Duration(milliseconds: 120);

void main() {
  late FakeProtocolWorkspace workspace;
  late FakeLogRecordSource logs;
  late FakeProtocolExportSaver saver;
  late RecordingLogger logger;
  late ProtocolPaneCubit cubit;

  ProtocolPaneCubit makeCubit({
    ProtocolPayloadPolicy base = ProtocolPayloadPolicy.metadataOnly,
  }) => ProtocolPaneCubit(
    workspace: workspace,
    logRecords: logs,
    exportSaver: saver,
    basePolicy: base,
    logger: logger,
  );

  // Cubit создаётся в теле `testWidgets`, а не в `setUp`: подписки на потоки
  // выполняют обработчики в зоне, где вызван `listen`, и таймер склейки
  // публикаций, созданный из `setUp`, жил бы по настоящему времени, а не по
  // поддельным часам `tester.pump(Duration)` (design.md change
  // `redesign-protocol-pane`, D7).
  void bootstrap() {
    workspace = FakeProtocolWorkspace();
    logs = FakeLogRecordSource();
    saver = FakeProtocolExportSaver();
    logger = RecordingLogger();
    cubit = makeCubit();
  }

  void testCubit(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) => testWidgets(description, (tester) async {
    bootstrap();
    await body(tester);
    // Отложенная публикация — таймер: в конце теста Cubit закрывается.
    await tester.runAsync(cubit.close);
  });

  tearDown(() async {
    await cubit.close();
    await workspace.dispose();
    await logs.dispose();
  });

  int seq = 0;
  ProtocolFrame frame({
    String? method,
    Object? id,
    String? session,
    ProtocolFrameKind kind = ProtocolFrameKind.request,
    ProtocolFrameDirection direction = _out,
    Map<String, Object?>? payload,
    ProtocolPayloadOmitted? omitted,
    int generation = 1,
    int? errorCode,
    String? detail,
  }) => protocolFrame(
    seq: ++seq,
    method: method ?? 'session/update',
    id: id,
    sessionId: session,
    kind: kind,
    direction: direction,
    payload: payload,
    omitted: omitted,
    generation: generation,
    errorCode: errorCode,
    detail: detail,
  );

  Future<void> settle(WidgetTester tester) => tester.pump(_tick);

  List<int> seqs(Iterable<ProtocolFrame> frames) => [
    for (final f in frames) f.seq,
  ];

  group('начальное состояние', () {
    testCubit('вид Frames, фокуса нет, Trace выключен, фильтры по умолчанию', (
      tester,
    ) async {
      final state = cubit.state;

      expect(state.view, ProtocolView.frames);
      expect(state.focusedSessionId, isNull);
      expect(state.frameFilter, const ProtocolFrameFilter());
      expect(state.logFilter, const LogRecordFilter());
      expect(state.framesPaused, isFalse);
      expect(state.logPaused, isFalse);
      expect(state.selectedFrame, isNull);
      expect(state.selectedRecord, isNull);
      expect(state.framesSplit, isNull);
      expect(state.logSplit, isNull);
      expect(state.traceEnabled, isFalse);
      expect(state.traceAvailable, isTrue);
      expect(state.saveFailed, isFalse);
    });

    testCubit('кадры, пришедшие до создания Cubit, видны', (tester) async {
      await tester.runAsync(cubit.close);
      workspace.push(frame(method: 'initialize', id: 0));
      workspace.push(frame(method: 'session/list', id: 1));
      cubit = makeCubit();

      expect(cubit.state.framesCount, 2);
      expect(cubit.state.visibleFrames, hasLength(2));
    });

    testCubit('сессия в фокусе берётся из WorkspaceState', (tester) async {
      await tester.runAsync(cubit.close);
      workspace.focus('s1');
      cubit = makeCubit();

      expect(cubit.state.focusedSessionId, 's1');
    });

    testCubit('traceAvailable повторяет возможность буфера', (tester) async {
      await tester.runAsync(cubit.close);
      await tester.runAsync(workspace.dispose);
      workspace = FakeProtocolWorkspace(traceAvailable: false);
      cubit = makeCubit(base: ProtocolPayloadPolicy.full);

      expect(cubit.state.traceAvailable, isFalse);
    });
  });

  group('виды', () {
    testCubit('openLog (/logs) делает активным вид Log, Frames — обратно', (
      tester,
    ) async {
      cubit.openLog();
      expect(cubit.state.view, ProtocolView.log);

      cubit.selectView(ProtocolView.frames);
      expect(cubit.state.view, ProtocolView.frames);
    });

    testCubit('смена вида — событие protocol_pane.view без значений', (
      tester,
    ) async {
      cubit.selectView(ProtocolView.log);

      final events = logger.entries.where(
        (e) => e['event'] == 'protocol_pane.view',
      );
      expect(events, hasLength(1));
      expect(events.single['view'], 'log');
      expect(events.single['level'], 'debug');
    });

    testCubit('повторный выбор того же вида события не пишет', (tester) async {
      cubit.selectView(ProtocolView.frames);

      expect(
        logger.entries.where((e) => e['event'] == 'protocol_pane.view'),
        isEmpty,
      );
    });

    testCubit('фильтры и выбор переживают смену вида и обратно '
        '(закрытие вкладки — только показ, состояние в Cubit)', (tester) async {
      final selected = frame(method: 'session/prompt', id: 1, session: 's1');
      workspace.focus('s1');
      workspace.push(selected);
      await settle(tester);

      cubit.setFrameQuery('prompt');
      cubit.selectFrame(selected);
      cubit.selectView(ProtocolView.log);
      cubit.selectView(ProtocolView.frames);
      await settle(tester);

      expect(cubit.state.frameFilter.query, 'prompt');
      expect(cubit.state.selectedFrame, selected);
      expect(seqs(cubit.state.visibleFrames), [selected.seq]);
    });

    testCubit('доля разделителя хранится отдельно у каждого вида', (
      tester,
    ) async {
      cubit.setSplit(0.4);
      cubit.selectView(ProtocolView.log);
      expect(cubit.state.logSplit, isNull);

      cubit.setSplit(0.7);
      expect(cubit.state.framesSplit, 0.4);
      expect(cubit.state.logSplit, 0.7);

      cubit.selectView(ProtocolView.frames);
      expect(cubit.state.framesSplit, 0.4);
    });
  });

  group('область и фокус (D6)', () {
    late ProtocolFrame init;
    late ProtocolFrame a1;
    late ProtocolFrame b1;

    setUp(() {
      init = frame(method: 'initialize', id: 0);
      a1 = frame(method: 'session/prompt', id: 1, session: 's_7f3a');
      b1 = frame(method: 'session/prompt', id: 2, session: 's_91c0');
    });

    testCubit('сессия в фокусе и соединение; чужих кадров нет', (tester) async {
      workspace.pushAll([init, a1, b1]);
      workspace.focus('s_7f3a');
      await settle(tester);

      expect(seqs(cubit.state.visibleFrames), [init.seq, a1.seq]);
    });

    testCubit('панель следует за фокусом: поиск сохранён, выбор снят', (
      tester,
    ) async {
      workspace.pushAll([init, a1, b1]);
      workspace.focus('s_7f3a');
      cubit.setFrameQuery('prompt');
      cubit.selectFrame(a1);
      await settle(tester);

      workspace.focus('s_91c0');
      await settle(tester);

      expect(cubit.state.focusedSessionId, 's_91c0');
      expect(seqs(cubit.state.visibleFrames), [b1.seq]);
      expect(cubit.state.frameFilter.query, 'prompt');
      expect(cubit.state.selectedFrame, isNull);
    });

    testCubit('выбранный элемент соединения переживает смену фокуса', (
      tester,
    ) async {
      workspace.pushAll([init, a1, b1]);
      workspace.focus('s_7f3a');
      cubit.selectFrame(init);
      await settle(tester);

      workspace.focus('s_91c0');
      await settle(tester);

      expect(cubit.state.selectedFrame, init);
    });

    testCubit('без фокуса — только элементы соединения', (tester) async {
      workspace.pushAll([init, a1, b1]);
      workspace.focus('s_7f3a');
      await settle(tester);

      workspace.focus(null);
      await settle(tester);

      expect(cubit.state.focusedSessionId, isNull);
      expect(seqs(cubit.state.visibleFrames), [init.seq]);
      expect(cubit.state.framesCount, 1);
    });

    testCubit('запрос session/new относится к своей сессии', (tester) async {
      final request = frame(method: 'session/new', id: 1);
      workspace.push(request);
      workspace.focus('s_7f3a');
      await settle(tester);
      // До ответа запрос — элемент соединения и виден в любой сессии.
      expect(seqs(cubit.state.visibleFrames), [request.seq]);

      workspace.push(
        frame(
          method: 'session/new',
          id: 1,
          session: 's_91c0',
          kind: ProtocolFrameKind.result,
          direction: _in,
        ),
      );
      await settle(tester);

      expect(cubit.state.visibleFrames, isEmpty);
      workspace.focus('s_91c0');
      await settle(tester);
      expect(cubit.state.visibleFrames, hasLength(2));
      expect(
        cubit.state.visibleFrames.every((f) => f.sessionId != null),
        isTrue,
      );
    });

    testCubit('счётчики считают область без фильтров', (tester) async {
      workspace.pushAll([init, a1, b1]);
      workspace.focus('s_7f3a');
      logs.add(logRecord('a', sessionId: 's_7f3a'));
      logs.add(logRecord('b', sessionId: 's_91c0'));
      logs.add(logRecord('c'));
      cubit.setFrameQuery('prompt');
      cubit.setLogQuery('zzz');
      await settle(tester);

      expect(cubit.state.framesCount, 2);
      expect(cubit.state.logCount, 2);
      expect(seqs(cubit.state.visibleFrames), [a1.seq]);
      expect(cubit.state.visibleRecords, isEmpty);
    });

    testCubit('записи журнала: область по session_id', (tester) async {
      logs.add(logRecord('a', sessionId: 's_7f3a'));
      logs.add(logRecord('b', sessionId: 's_91c0'));
      logs.add(logRecord('c'));
      workspace.focus('s_91c0');
      await settle(tester);

      expect(cubit.state.visibleRecords.map((r) => r['event']), ['b', 'c']);
    });

    testCubit('фильтры Log: категория и уровень', (tester) async {
      logs.add(logRecord('a', category: 'x', level: 'debug'));
      logs.add(logRecord('b', category: 'x', level: 'error'));
      logs.add(logRecord('c', category: 'y', level: 'error'));
      cubit.setLogCategory('x');
      cubit.setLogMinLevel(LogLevel.warning);
      await settle(tester);

      expect(cubit.state.visibleRecords.map((r) => r['event']), ['b']);
    });

    testCubit('переключатели Frames', (tester) async {
      final note = frame(
        method: 'session/update',
        kind: ProtocolFrameKind.notification,
      );
      final request = frame(method: 'session/prompt', id: 1);
      final error = frame(
        method: 'session/prompt',
        id: 2,
        kind: ProtocolFrameKind.error,
        errorCode: -32603,
        detail: 'Internal error',
      );
      workspace.pushAll([note, request, error]);
      cubit.setShowRequests(false);
      await settle(tester);
      expect(seqs(cubit.state.visibleFrames), [note.seq]);

      cubit.setShowRequests(true);
      cubit.setShowNotifications(false);
      await settle(tester);
      expect(seqs(cubit.state.visibleFrames), [request.seq, error.seq]);

      cubit.setErrorsOnly(true);
      await settle(tester);
      expect(seqs(cubit.state.visibleFrames), [error.seq]);
    });
  });

  group('пауза', () {
    testCubit('пауза замораживает список, счётчик растёт, Resume показывает '
        'накопленное', (tester) async {
      workspace.pushAll([for (var i = 0; i < 3; i++) frame()]);
      await settle(tester);

      cubit.togglePause();
      expect(cubit.state.framesPaused, isTrue);
      workspace.pushAll([for (var i = 0; i < 20; i++) frame()]);
      await settle(tester);

      expect(cubit.state.visibleFrames, hasLength(3));
      expect(cubit.state.framesCount, 23);

      cubit.togglePause();
      await settle(tester);

      expect(cubit.state.framesPaused, isFalse);
      expect(cubit.state.visibleFrames, hasLength(23));
    });

    testCubit('пауза вида Log не затрагивает Frames', (tester) async {
      cubit.selectView(ProtocolView.log);
      cubit.togglePause();
      workspace.push(frame());
      logs.add(logRecord('x'));
      await settle(tester);

      expect(cubit.state.logPaused, isTrue);
      expect(cubit.state.framesPaused, isFalse);
      expect(cubit.state.visibleRecords, isEmpty);
      expect(cubit.state.logCount, 1);
      expect(cubit.state.visibleFrames, hasLength(1));
    });

    testCubit('смена фокуса на паузе: пауза сохранена, снимок получает '
        'новую область', (tester) async {
      final init = frame(method: 'initialize', id: 0);
      final a = frame(method: 'session/prompt', id: 1, session: 'a');
      final b = frame(method: 'session/prompt', id: 2, session: 'b');
      workspace.pushAll([init, a, b]);
      workspace.focus('a');
      await settle(tester);
      cubit.togglePause();

      final after = frame(method: 'session/prompt', id: 3, session: 'b');
      workspace.push(after);
      workspace.focus('b');
      await settle(tester);

      expect(cubit.state.framesPaused, isTrue);
      // Снимок сделан в момент паузы: поздний кадр в нём не появился.
      expect(seqs(cubit.state.visibleFrames), [init.seq, b.seq]);
    });
  });

  group('выбранный кадр', () {
    testCubit('остаётся в панели после вытеснения из буфера', (tester) async {
      final f = frame(method: 'session/prompt', id: 1, session: 's1');
      workspace.focus('s1');
      workspace.push(f);
      await settle(tester);
      cubit.selectFrame(f);

      workspace.protocolFrames.clear();
      await settle(tester);

      expect(cubit.state.visibleFrames, isEmpty);
      expect(cubit.state.selectedFrame, f);
    });

    testCubit('Alt+→ без выбора выбирает первый видимый, Alt+← — '
        'последний', (tester) async {
      final frames = [for (var i = 0; i < 3; i++) frame(session: 's1')];
      workspace.focus('s1');
      workspace.pushAll(frames);
      await settle(tester);

      cubit.selectNext();
      expect(cubit.state.selectedFrame, frames.first);

      cubit.selectFrame(null);
      cubit.selectPrevious();
      expect(cubit.state.selectedFrame, frames.last);
    });

    testCubit('навигация идёт по видимым элементам и стоит на краю', (
      tester,
    ) async {
      final frames = [for (var i = 0; i < 4; i++) frame(session: 's1')];
      workspace.focus('s1');
      workspace.pushAll(frames);
      await settle(tester);

      cubit.selectFrame(frames[2]);
      cubit.selectNext();
      expect(cubit.state.selectedFrame, frames[3]);
      cubit.selectNext();
      expect(cubit.state.selectedFrame, frames[3]);

      cubit.selectFrame(frames[0]);
      cubit.selectPrevious();
      expect(cubit.state.selectedFrame, frames[0]);
    });

    testCubit('навигация пропускает то, что скрыл фильтр', (tester) async {
      final a = frame(method: 'session/prompt', id: 1, session: 's1');
      final hidden = frame(method: 'session/update', session: 's1');
      final b = frame(method: 'session/prompt', id: 2, session: 's1');
      workspace.focus('s1');
      workspace.pushAll([a, hidden, b]);
      cubit.setFrameQuery('prompt');
      await settle(tester);

      cubit.selectFrame(a);
      cubit.selectNext();

      expect(cubit.state.selectedFrame, b);
    });

    testCubit('в виде Log навигация идёт по записям', (tester) async {
      logs.add(logRecord('first'));
      logs.add(logRecord('second'));
      cubit.selectView(ProtocolView.log);
      await settle(tester);

      cubit.selectNext();
      expect(cubit.state.selectedRecord!['event'], 'first');
      cubit.selectNext();
      expect(cubit.state.selectedRecord!['event'], 'second');
      cubit.selectNext();
      expect(cubit.state.selectedRecord!['event'], 'second');
      cubit.selectPrevious();
      expect(cubit.state.selectedRecord!['event'], 'first');
    });

    testCubit('в пустой области навигация ничего не выбирает', (tester) async {
      cubit.selectNext();
      cubit.selectPrevious();

      expect(cubit.state.selectedFrame, isNull);
    });
  });

  group('Clear', () {
    testCubit('Frames: очищает буфер кадров целиком, снимает выбор и '
        'паузу, пишет protocol_pane.clear', (tester) async {
      final a = frame(session: 'a');
      workspace.pushAll([a, frame(session: 'b'), frame()]);
      workspace.focus('a');
      await settle(tester);
      cubit.selectFrame(a);
      cubit.togglePause();

      cubit.clear();
      await settle(tester);

      expect(workspace.protocolFrames.frames, isEmpty);
      expect(cubit.state.selectedFrame, isNull);
      expect(cubit.state.framesPaused, isFalse);
      expect(cubit.state.framesCount, 0);
      final event = logger.entries.singleWhere(
        (e) => e['event'] == 'protocol_pane.clear',
      );
      expect(event['view'], 'frames');
      expect(event['count'], 3);
      expect(event['level'], 'info');
    });

    testCubit('Log: чистит журнал, буфер кадров не меняется', (tester) async {
      workspace.push(frame());
      logs.add(logRecord('a'));
      logs.add(logRecord('b'));
      cubit.selectView(ProtocolView.log);
      await settle(tester);
      cubit.selectRecord(cubit.state.visibleRecords.first);
      cubit.togglePause();

      cubit.clear();
      await settle(tester);

      expect(logs.clearCalls, 1);
      expect(cubit.state.selectedRecord, isNull);
      expect(cubit.state.logPaused, isFalse);
      expect(cubit.state.logCount, 0);
      expect(workspace.protocolFrames.frames, hasLength(1));
      final event = logger.entries.singleWhere(
        (e) => e['event'] == 'protocol_pane.clear',
      );
      expect(event['view'], 'log');
      expect(event['count'], 2);
    });

    testCubit('записи protocol_pane.clear не содержат payload и фильтров', (
      tester,
    ) async {
      workspace.push(frame(payload: {'secret': 'x'}));
      cubit.setFrameQuery('needle');
      cubit.clear();

      final event = logger.entries.singleWhere(
        (e) => e['event'] == 'protocol_pane.clear',
      );
      expect(event.keys.toSet(), {'event', 'level', 'view', 'count'});
    });
  });

  group('переход Log → Frames', () {
    late ProtocolFrame gen1;
    late ProtocolFrame gen2;

    setUp(() {
      gen1 = frame(method: 'session/prompt', id: 5, session: 's1');
      gen2 = frame(
        method: 'session/prompt',
        id: 5,
        session: 's1',
        generation: 2,
      );
    });

    testCubit('кадр с тем же id и поколением выбирается, вид Frames', (
      tester,
    ) async {
      workspace.focus('s1');
      workspace.pushAll([gen1, gen2]);
      await settle(tester);
      cubit.selectView(ProtocolView.log);
      final record = logRecord(
        'tool_failed',
        sessionId: 's1',
        requestId: 5,
        generation: 2,
      );

      expect(cubit.frameOfRecord(record), gen2);
      cubit.showFrameOfRecord(record);

      expect(cubit.state.view, ProtocolView.frames);
      expect(cubit.state.selectedFrame, gen2);
    });

    testCubit('без поколения в записи — последний такой кадр', (tester) async {
      workspace.focus('s1');
      workspace.pushAll([gen1, gen2]);
      await settle(tester);

      final record = logRecord('x', sessionId: 's1', requestId: 5);

      expect(cubit.frameOfRecord(record), gen2);
    });

    testCubit('скрывающие фильтры Frames сбрасываются к умолчанию', (
      tester,
    ) async {
      workspace.focus('s1');
      workspace.pushAll([gen1]);
      cubit.setFrameQuery('zzz');
      cubit.setErrorsOnly(true);
      cubit.setShowRequests(false);
      await settle(tester);

      cubit.showFrameOfRecord(
        logRecord('x', sessionId: 's1', requestId: 5, generation: 1),
      );
      await settle(tester);

      expect(cubit.state.frameFilter, const ProtocolFrameFilter());
      expect(cubit.state.visibleFrames, contains(gen1));
    });

    testCubit('фильтры, которые кадр не скрывают, сохраняются', (tester) async {
      workspace.focus('s1');
      workspace.pushAll([gen1]);
      cubit.setFrameQuery('prompt');
      await settle(tester);

      cubit.showFrameOfRecord(
        logRecord('x', sessionId: 's1', requestId: 5, generation: 1),
      );

      expect(cubit.state.frameFilter.query, 'prompt');
    });

    testCubit('кадра нет в буфере — frameOfRecord пуст, переход недоступен', (
      tester,
    ) async {
      workspace.focus('s1');
      workspace.pushAll([gen1]);
      await settle(tester);
      workspace.protocolFrames.clear();
      cubit.selectView(ProtocolView.log);
      await settle(tester);
      final record = logRecord('x', sessionId: 's1', requestId: 5);

      expect(cubit.frameOfRecord(record), isNull);
      cubit.showFrameOfRecord(record);

      expect(cubit.state.view, ProtocolView.log);
      expect(cubit.state.selectedFrame, isNull);
    });

    testCubit('кадр другой сессии не находится (область D6)', (tester) async {
      workspace.focus('s2');
      workspace.pushAll([gen1]);
      await settle(tester);

      expect(
        cubit.frameOfRecord(logRecord('x', sessionId: 's1', requestId: 5)),
        isNull,
      );
    });

    testCubit('запись без request_id — перехода нет', (tester) async {
      workspace.pushAll([gen1]);
      await settle(tester);

      expect(cubit.frameOfRecord(logRecord('x')), isNull);
    });
  });

  group('данные панели, которые раньше считал build()', () {
    testCubit('категории Log — по области без фильтров, а не по видимому', (
      tester,
    ) async {
      logs.add(logRecord('a', category: 'session', sessionId: 's1'));
      logs.add(logRecord('b', category: 'connection'));
      logs.add(logRecord('c', category: 'other', sessionId: 's2'));
      workspace.focus('s1');
      await settle(tester);
      expect(cubit.state.logCategories, ['connection', 'session']);

      cubit.setLogCategory('session');
      cubit.setLogQuery('zzz');
      await settle(tester);

      // Список для выпадающего выбора не сужается выбором категории.
      expect(cubit.state.visibleRecords, isEmpty);
      expect(cubit.state.logCategories, ['connection', 'session']);
    });

    testCubit('доступность кадра выбранной записи считает Cubit', (
      tester,
    ) async {
      final frame1 = frame(method: 'session/prompt', id: 5, session: 's1');
      workspace.focus('s1');
      workspace.push(frame1);
      logs.add(logRecord('x', sessionId: 's1', requestId: 5, generation: 1));
      await settle(tester);
      expect(cubit.state.selectedRecordHasFrame, isFalse);

      cubit.selectRecord(cubit.state.visibleRecords.single);
      expect(cubit.state.selectedRecordHasFrame, isTrue);

      workspace.protocolFrames.clear();
      await settle(tester);
      expect(cubit.state.selectedRecordHasFrame, isFalse);
    });
  });

  group('ошибки действий панели не теряются (§12)', () {
    testCubit('сбой действия пишется событием с классом ошибки, без '
        'исключения наружу', (tester) async {
      await cubit.guarded(
        'copy',
        () async => throw StateError('clipboard secret path /tmp/x'),
      );

      final event = logger.entries.singleWhere(
        (e) => e['event'] == 'protocol_pane.action_failed',
      );
      expect(event['action'], 'copy');
      expect(event['error_class'], 'StateError');
      expect(event['level'], 'error');
      // Ни текста ошибки, ни путей в записи нет.
      expect(event.keys.toSet(), {'event', 'level', 'action', 'error_class'});
    });

    testCubit('успешное действие событий не пишет', (tester) async {
      await cubit.guarded('copy', () async {});

      expect(
        logger.entries.where(
          (e) => e['event'] == 'protocol_pane.action_failed',
        ),
        isEmpty,
      );
    });
  });

  group('Trace (D17)', () {
    testCubit('включение и выключение идут через буфер кадров, пишется '
        'protocol_pane.trace', (tester) async {
      cubit.setTrace(true);
      expect(cubit.state.traceEnabled, isTrue);
      expect(workspace.backend.traceCalls, [true]);

      cubit.setTrace(false);
      expect(cubit.state.traceEnabled, isFalse);
      expect(workspace.backend.traceCalls, [true, false]);

      final events = logger.entries
          .where((e) => e['event'] == 'protocol_pane.trace')
          .toList();
      expect(events.map((e) => e['enabled']), [true, false]);
      expect(events.every((e) => e['level'] == 'info'), isTrue);
      expect(
        events.every((e) => e.keys.toSet().length == 3),
        isTrue,
        reason: 'без payload и путей: только event, level, enabled',
      );
    });

    testCubit('повторное значение — без события и без вызова ядра', (
      tester,
    ) async {
      cubit.setTrace(false);

      expect(workspace.backend.traceCalls, isEmpty);
      expect(
        logger.entries.where((e) => e['event'] == 'protocol_pane.trace'),
        isEmpty,
      );
    });

    testCubit('Trace недоступен (базовая full) — переключение без эффекта', (
      tester,
    ) async {
      await tester.runAsync(cubit.close);
      await tester.runAsync(workspace.dispose);
      workspace = FakeProtocolWorkspace(traceAvailable: false);
      cubit = makeCubit(base: ProtocolPayloadPolicy.full);

      cubit.setTrace(true);

      expect(cubit.state.traceEnabled, isFalse);
      expect(workspace.backend.traceCalls, isEmpty);
    });

    testCubit('выключение снимает payload с выбранного кадра и со снимка '
        'паузы', (tester) async {
      cubit.setTrace(true);
      final f = frame(
        method: 'session/new',
        id: 1,
        session: 's1',
        payload: {'method': 'session/new'},
      );
      workspace.focus('s1');
      workspace.push(f);
      await settle(tester);
      cubit.selectFrame(f);
      cubit.togglePause();
      expect(cubit.state.visibleFrames.single.payload, isNotNull);

      cubit.setTrace(false);
      await settle(tester);

      expect(cubit.state.selectedFrame!.payload, isNull);
      expect(
        cubit.state.selectedFrame!.payloadOmitted,
        ProtocolPayloadOmitted.policy,
      );
      expect(cubit.state.visibleFrames.single.payload, isNull);
      expect(cubit.state.visibleFrames.every((f) => f.payload == null), isTrue);
    });

    testCubit('выбранный кадр после выключения Trace — тот же, что хранит '
        'буфер (его правила снятия payload)', (tester) async {
      cubit.setTrace(true);
      final f = frame(
        method: 'session/prompt',
        id: 1,
        session: 's1',
        payload: {'method': 'session/prompt'},
      );
      workspace.focus('s1');
      workspace.push(f);
      await settle(tester);
      cubit.selectFrame(f);

      cubit.setTrace(false);

      final inBuffer = workspace.protocolFrames.frames.singleWhere(
        (b) => b.seq == f.seq,
      );
      expect(cubit.state.selectedFrame, inBuffer);
    });

    testCubit('вытесненный кадр-ошибка: после выключения Trace текст ошибки '
        'заменён стандартным именем кода у выбранного и у снимка паузы', (
      tester,
    ) async {
      cubit.setTrace(true);
      final error = frame(
        method: 'session/prompt',
        id: 5,
        session: 's1',
        kind: ProtocolFrameKind.error,
        direction: _in,
        errorCode: -32603,
        detail: 'secret path /tmp/user/key',
        payload: {'error': 'secret path /tmp/user/key'},
      );
      workspace.focus('s1');
      workspace.push(error);
      await settle(tester);
      cubit.selectFrame(error);
      cubit.togglePause();
      // Кадр вытеснен из буфера: заменить его там уже некому, кроме Cubit.
      workspace.protocolFrames.clear();

      cubit.setTrace(false);
      await settle(tester);

      final selected = cubit.state.selectedFrame!;
      expect(selected.payload, isNull);
      expect(selected.detail, 'Internal error');
      expect(selected.payloadOmitted, ProtocolPayloadOmitted.policy);
      final frozen = cubit.state.visibleFrames.single;
      expect(frozen.payload, isNull);
      expect(frozen.detail, 'Internal error');
      expect(frozen.seq, error.seq);
    });

    testCubit('кадр-ошибка с payload, не сохранённым из-за размера: текст '
        'ошибки заменяется и у вытесненного кадра', (tester) async {
      cubit.setTrace(true);
      final error = frame(
        method: 'session/prompt',
        id: 6,
        session: 's1',
        kind: ProtocolFrameKind.error,
        direction: _in,
        errorCode: -32603,
        detail: 'secret path /tmp/user/key',
        omitted: ProtocolPayloadOmitted.tooLarge,
      );
      workspace.focus('s1');
      workspace.push(error);
      await settle(tester);
      cubit.selectFrame(error);
      workspace.protocolFrames.clear();

      cubit.setTrace(false);

      final selected = cubit.state.selectedFrame!;
      expect(selected.detail, 'Internal error');
      expect(selected.payloadOmitted, ProtocolPayloadOmitted.tooLarge);
    });

    testCubit('после перезапуска (новый Cubit над новым рабочим '
        'пространством) Trace выключен', (tester) async {
      cubit.setTrace(true);
      await tester.runAsync(cubit.close);
      await tester.runAsync(workspace.dispose);

      workspace = FakeProtocolWorkspace();
      cubit = makeCubit();

      expect(cubit.state.traceEnabled, isFalse);
      expect(workspace.backend.traceCalls, isEmpty);
    });
  });

  group('публикация и жизненный цикл (D7)', () {
    testCubit('500 кадров в секунду — не больше 10 публикаций за секунду, '
        'последний кадр виден после последней', (tester) async {
      final states = <ProtocolPaneState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      for (var i = 0; i < 499; i++) {
        workspace.push(frame());
        await tester.pump(const Duration(milliseconds: 2));
      }
      workspace.push(frame());

      expect(states.length, lessThanOrEqualTo(10));

      await tester.pump(const Duration(milliseconds: 150));

      expect(cubit.state.framesCount, 500);
      expect(cubit.state.visibleFrames, hasLength(500));
    });

    testCubit('после close() таймер отменён, подписки сняты', (tester) async {
      workspace.focus('s1');
      workspace.push(frame());
      logs.add(logRecord('x'));
      // Публикация ещё отложена таймером склейки.
      await tester.runAsync(cubit.close);

      expect(workspace.hasStateListeners, isFalse);
      expect(logs.hasListener, isFalse);

      // Событие после close не должно ни падать, ни публиковаться.
      workspace.push(frame());
      logs.add(logRecord('y'));
      await tester.pump(const Duration(seconds: 1));
      // Тест не завершится, если в зоне остался активный таймер.
    });

    testCubit('close() не закрывает буфер и порт — их владельцы другие', (
      tester,
    ) async {
      await tester.runAsync(cubit.close);

      workspace.push(frame());
      expect(workspace.protocolFrames.frames, hasLength(1));
      expect(() => logs.add(logRecord('x')), returnsNormally);
    });
  });
}
