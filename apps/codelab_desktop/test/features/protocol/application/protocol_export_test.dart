// Экспорт панели Protocol в JSON Lines (задача 4.7 change
// `redesign-protocol-pane`; spec agent-workbench-ui «Pause, Clear и Export
// панели Protocol» — все сценарии экспорта; «Режим Trace панели Protocol» —
// «Экспорт в режиме Trace»; approval-safety «Секрет скрыт и в режиме Trace»;
// design.md D10, D14, D17).
//
// Красный до задачи 4.8: нет `protocol_export.dart`, экспорта в Cubit и порта
// `ProtocolExportSaver`. Ожидаемый API (design.md D10 называет порт, исходы
// и имя файла, но не сигнатуры):
//
// * чистые функции `protocol_export.dart`:
//   `protocolExportFileName(ProtocolView, DateTime)`,
//   `buildFramesExport({frames, exportedAt, debugBuild, appVersion, platform,
//   sessionId})` и `buildRecordsExport({records, …те же})` — текст JSON Lines,
//   каждая строка заканчивается LF, `exportHasPayload(frames)`;
// * `ProtocolPaneCubit.exportNeedsConfirmation` (getter) и
//   `Future<void> exportActive({required Future<bool> Function() confirm})`:
//   подтверждение (`confirm`) вызывается, только если в видимом наборе Frames
//   есть кадр с payload; после него строится текст и вызывается порт;
// * порт — `test/core/platform/protocol_export_saver_test.dart`.
//
// В файл попадают только уже замаскированные данные буфера (D10): повторного
// маскирования нет, тест проверяет, что в файле нет исходного секрета, когда
// его нет в буфере, и что `payload` отсутствует при `metadataOnly`.

import 'dart:convert';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_desktop/core/platform/protocol_export_saver.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_export.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_cubit.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_log_record_source.dart';
import '../../../support/fake_protocol_export_saver.dart';
import '../../../support/fake_protocol_workspace.dart';
import '../../../support/protocol_fixtures.dart';
import '../../../support/recording_logger.dart';

final _exportedAt = DateTime.utc(2026, 11, 22, 14, 2, 41);

List<Map<String, Object?>> _lines(String text) => [
  for (final line in const LineSplitter().convert(text))
    jsonDecode(line) as Map<String, Object?>,
];

void main() {
  group('чистая сборка', () {
    final error = protocolFrame(
      seq: 3,
      direction: ProtocolFrameDirection.inbound,
      kind: ProtocolFrameKind.error,
      method: 'session/prompt',
      id: 5,
      sessionId: 's_7f3a',
      errorCode: -32603,
      detail: 'Internal error',
      size: 80,
      omitted: ProtocolPayloadOmitted.policy,
      generation: 2,
      time: DateTime.utc(2026, 11, 22, 12, 0, 3),
    );
    final withPayload = protocolFrame(
      seq: 4,
      method: 'session/new',
      id: 1,
      payload: {
        'method': 'session/new',
        'params': {'apiKey': '<redacted>'},
      },
      time: DateTime.utc(2026, 11, 22, 12, 0, 4),
    );

    String frames(List<ProtocolFrame> list, {String? session = 's_7f3a'}) =>
        buildFramesExport(
          frames: list,
          exportedAt: _exportedAt,
          debugBuild: false,
          appVersion: '1.2.3',
          platform: 'macOS arm64',
          sessionId: session,
        );

    test('заголовок: тип, формат, вид, сборка, версия, платформа, время, '
        'сессия, число', () {
      final header = _lines(frames([error, withPayload])).first;

      expect(header, {
        'type': 'codelab.protocol_export',
        'format': 1,
        'view': 'frames',
        'build': 'release',
        'app_version': '1.2.3',
        'platform': 'macOS arm64',
        'exported_at': '2026-11-22T14:02:41.000Z',
        'session_id': 's_7f3a',
        'count': 2,
      });
    });

    test('сборка debug отражается в заголовке', () {
      final text = buildFramesExport(
        frames: [error],
        exportedAt: _exportedAt,
        debugBuild: true,
        appVersion: '1',
        platform: 'p',
        sessionId: null,
      );

      expect(_lines(text).first['build'], 'debug');
    });

    test('без сессии в фокусе session_id заголовка — null', () {
      final header = _lines(frames([error], session: null)).first;

      expect(header.containsKey('session_id'), isTrue);
      expect(header['session_id'], isNull);
    });

    test('по строке на кадр; поля null опущены', () {
      final lines = _lines(frames([error]));
      final line = lines[1];

      expect(lines, hasLength(2));
      expect(line['type'], 'frame');
      expect(line['seq'], 3);
      expect(line['time'], '2026-11-22T12:00:03.000Z');
      expect(line['direction'], 'inbound');
      expect(line['connection_generation'], 2);
      expect(line['kind'], 'error');
      expect(line['method'], 'session/prompt');
      expect(line['id'], 5);
      expect(line['session_id'], 's_7f3a');
      expect(line['error_code'], -32603);
      expect(line['detail'], 'Internal error');
      expect(line['size'], 80);
      expect(line['payload_omitted'], 'policy');
      expect(line.containsKey('payload'), isFalse);
    });

    test('опущенные поля: у кадра без метода, id и сессии их нет в строке', () {
      final bare = protocolFrame(
        kind: ProtocolFrameKind.notification,
        omitted: ProtocolPayloadOmitted.policy,
      );

      final line = _lines(frames([bare])).last;

      for (final key in [
        'method',
        'id',
        'session_id',
        'error_code',
        'detail',
        'payload',
      ]) {
        expect(line.containsKey(key), isFalse, reason: key);
      }
    });

    test('кадр с payload (full или Trace) — payload в строке как в буфере', () {
      final line = _lines(frames([withPayload])).last;

      expect(line['payload'], withPayload.payload);
      expect(line.containsKey('payload_omitted'), isFalse);
    });

    test('payload, не сохранённый из-за размера, помечен', () {
      final big = protocolFrame(omitted: ProtocolPayloadOmitted.tooLarge);

      // Значение — имя enum (design.md D10).
      expect(_lines(frames([big])).last['payload_omitted'], 'tooLarge');
    });

    test('строковый id остаётся строкой', () {
      final line = _lines(frames([protocolFrame(method: 'x', id: 'a9')])).last;

      expect(line['id'], 'a9');
    });

    test('UTF-8 без BOM, LF, последняя строка тоже оканчивается LF', () {
      final text = frames([error, withPayload]);
      final bytes = utf8.encode(text);

      expect(bytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
      expect(text.contains('\r'), isFalse);
      expect(text.endsWith('\n'), isTrue);
      expect(text.split('\n'), hasLength(4)); // 3 строки + пустой хвост
    });

    test('записи журнала: строки {"type":"record"} с полями как в буфере', () {
      final records = [
        logRecord('connection_state_changed', category: 'connection'),
        logRecord('tool_failed', level: 'error', sessionId: 's_7f3a'),
      ];

      final lines = _lines(
        buildRecordsExport(
          records: records,
          exportedAt: _exportedAt,
          debugBuild: false,
          appVersion: '1',
          platform: 'p',
          sessionId: 's_7f3a',
        ),
      );

      expect(lines.first['view'], 'log');
      expect(lines.first['count'], 2);
      expect(lines[1], {'type': 'record', ...records[0]});
      expect(lines[2], {'type': 'record', ...records[1]});
    });

    test('exportHasPayload: хоть один кадр с payload', () {
      expect(exportHasPayload([error]), isFalse);
      expect(exportHasPayload([error, withPayload]), isTrue);
      expect(exportHasPayload(const []), isFalse);
    });

    test('имя файла: codelab-protocol-<вид>-<yyyyMMdd-HHmmss>.jsonl', () {
      final now = DateTime(2026, 11, 22, 14, 2, 41);

      expect(
        protocolExportFileName(ProtocolView.frames, now),
        'codelab-protocol-frames-20261122-140241.jsonl',
      );
      expect(
        protocolExportFileName(ProtocolView.log, now),
        'codelab-protocol-log-20261122-140241.jsonl',
      );
    });
  });

  group('экспорт через Cubit', () {
    late FakeProtocolWorkspace workspace;
    late FakeLogRecordSource logs;
    late FakeProtocolExportSaver saver;
    late RecordingLogger logger;
    late ProtocolPaneCubit cubit;
    var seq = 0;

    ProtocolPaneCubit makeCubit(
      ProtocolPayloadPolicy base, {
      ProtocolExportSaver? exportSaver,
    }) => ProtocolPaneCubit(
      workspace: workspace,
      logRecords: logs,
      exportSaver: exportSaver ?? saver,
      basePolicy: base,
      logger: logger,
      appVersion: '1.2.3',
      platform: 'macOS arm64',
      clock: () => DateTime(2026, 11, 22, 14, 2, 41),
    );

    ProtocolFrame frame({
      String? session = 's1',
      ProtocolFrameKind kind = ProtocolFrameKind.request,
      Map<String, Object?>? payload,
      ProtocolPayloadOmitted? omitted,
      int? errorCode,
    }) => protocolFrame(
      seq: ++seq,
      method: 'session/prompt',
      id: seq,
      sessionId: session,
      kind: kind,
      payload: payload,
      omitted: omitted,
      errorCode: errorCode,
    );

    // Cubit создаётся в теле `testWidgets` (см. `protocol_pane_cubit_test`):
    // таймеры склейки должны идти по поддельным часам `tester.pump`.
    void bootstrap() {
      workspace = FakeProtocolWorkspace();
      logs = FakeLogRecordSource();
      saver = FakeProtocolExportSaver();
      logger = RecordingLogger();
      cubit = makeCubit(ProtocolPayloadPolicy.metadataOnly);
      workspace.focus('s1');
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

    Future<void> settle(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 120));

    Map<String, Object?> exportEvent() =>
        logger.entries.singleWhere((e) => e['event'] == 'protocol_pane.export');

    testCubit('release: три видимые ошибки — без подтверждения, файл без '
        'payload, событие saved с числом 3', (tester) async {
      workspace.pushAll([
        frame(omitted: ProtocolPayloadOmitted.policy),
        for (var i = 0; i < 3; i++)
          frame(
            kind: ProtocolFrameKind.error,
            errorCode: -32603,
            omitted: ProtocolPayloadOmitted.policy,
          ),
      ]);
      cubit.setErrorsOnly(true);
      await settle(tester);
      var confirmed = 0;

      expect(cubit.exportNeedsConfirmation, isFalse);
      await cubit.exportActive(
        confirm: () async {
          confirmed++;
          return true;
        },
      );

      expect(confirmed, 0);
      final file = saver.saved.single;
      expect(
        file.suggestedName,
        'codelab-protocol-frames-20261122-140241.jsonl',
      );
      final lines = _lines(file.text);
      expect(lines.first['view'], 'frames');
      expect(lines.first['build'], 'release');
      expect(lines.first['count'], 3);
      expect(lines.first['session_id'], 's1');
      expect(lines.skip(1).every((l) => l['type'] == 'frame'), isTrue);
      expect(lines.skip(1), hasLength(3));
      expect(lines.skip(1).any((l) => l.containsKey('payload')), isFalse);
      final event = exportEvent();
      expect(event['view'], 'frames');
      expect(event['outcome'], 'saved');
      expect(event['count'], 3);
      expect(event['level'], 'info');
    });

    testCubit('экспортируется видимое: область сессии и фильтры, а не весь '
        'буфер', (tester) async {
      workspace.pushAll([
        frame(session: 's1'),
        frame(session: 's2'),
        frame(session: null),
      ]);
      await settle(tester);

      await cubit.exportActive(confirm: () async => true);

      final lines = _lines(saver.saved.single.text);
      expect(lines.first['count'], 2);
      expect(lines.skip(1).map((l) => l['session_id']), ['s1', null]);
    });

    testCubit('без фокуса session_id заголовка — null', (tester) async {
      workspace.pushAll([frame(session: null)]);
      workspace.focus(null);
      await settle(tester);

      await cubit.exportActive(confirm: () async => true);

      final header = _lines(saver.saved.single.text).first;
      expect(header['session_id'], isNull);
    });

    testCubit('вид на паузе: экспортируется замороженный список', (
      tester,
    ) async {
      workspace.pushAll([frame(), frame()]);
      await settle(tester);
      cubit.togglePause();
      workspace.pushAll([frame(), frame(), frame()]);
      await settle(tester);

      await cubit.exportActive(confirm: () async => true);

      expect(_lines(saver.saved.single.text).first['count'], 2);
    });

    testCubit('debug: кадры с payload — подтверждение; отказ ничего не '
        'пишет, диалог сохранения не открывается, исход cancelled', (
      tester,
    ) async {
      await tester.runAsync(cubit.close);
      // Базовая `full`: у ядра Trace недоступен, payload хранится всегда.
      await tester.runAsync(workspace.dispose);
      workspace = FakeProtocolWorkspace(traceAvailable: false)..focus('s1');
      cubit = makeCubit(ProtocolPayloadPolicy.full);
      workspace.pushAll([
        frame(payload: {'method': 'session/prompt'}),
      ]);
      await settle(tester);

      expect(cubit.exportNeedsConfirmation, isTrue);
      await cubit.exportActive(confirm: () async => false);

      expect(saver.saved, isEmpty);
      expect(cubit.state.saveFailed, isFalse);
      final event = exportEvent();
      expect(event['outcome'], 'cancelled');
      expect(event['view'], 'frames');
    });

    testCubit('debug: подтверждение даёт запись с payload в строках', (
      tester,
    ) async {
      await tester.runAsync(cubit.close);
      // Базовая `full`: у ядра Trace недоступен, payload хранится всегда.
      await tester.runAsync(workspace.dispose);
      workspace = FakeProtocolWorkspace(traceAvailable: false)..focus('s1');
      cubit = makeCubit(ProtocolPayloadPolicy.full);
      workspace.pushAll([
        frame(
          payload: {
            'params': {'apiKey': '<redacted>'},
          },
        ),
      ]);
      await settle(tester);

      await cubit.exportActive(confirm: () async => true);

      final lines = _lines(saver.saved.single.text);
      expect(lines.first['build'], 'debug');
      expect(lines[1]['payload'], {
        'params': {'apiKey': '<redacted>'},
      });
      expect(saver.saved.single.text, isNot(contains('ghp_')));
    });

    testCubit('release в режиме Trace: кадры с payload — подтверждение '
        '(сценарий «Экспорт в режиме Trace»)', (tester) async {
      cubit.setTrace(true);
      workspace.pushAll([
        frame(payload: {'method': 'session/prompt'}),
      ]);
      await settle(tester);

      var asked = 0;
      expect(cubit.exportNeedsConfirmation, isTrue);
      await cubit.exportActive(
        confirm: () async {
          asked++;
          return true;
        },
      );

      expect(asked, 1);
      expect(saver.saved, hasLength(1));
    });

    testCubit('Trace включён, но кадры без payload — подтверждения нет', (
      tester,
    ) async {
      cubit.setTrace(true);
      workspace.pushAll([frame(omitted: ProtocolPayloadOmitted.policy)]);
      await settle(tester);

      expect(cubit.exportNeedsConfirmation, isFalse);
    });

    testCubit('текст строится в момент подтверждения: выключение Trace '
        'во время диалога сохранения набор не меняет', (tester) async {
      final hook = _TraceOffDuringSave(() => cubit.setTrace(false));
      await tester.runAsync(cubit.close);
      cubit = makeCubit(ProtocolPayloadPolicy.metadataOnly, exportSaver: hook);
      cubit.setTrace(true);
      workspace.pushAll([
        frame(payload: {'method': 'session/prompt'}),
      ]);
      await settle(tester);

      await cubit.exportActive(confirm: () async => true);

      expect(cubit.state.traceEnabled, isFalse);
      expect(_lines(hook.text!)[1]['payload'], {'method': 'session/prompt'});
    });

    testCubit('вид Log: подтверждения нет даже в debug, строки record', (
      tester,
    ) async {
      await tester.runAsync(cubit.close);
      // Базовая `full`: у ядра Trace недоступен, payload хранится всегда.
      await tester.runAsync(workspace.dispose);
      workspace = FakeProtocolWorkspace(traceAvailable: false)..focus('s1');
      cubit = makeCubit(ProtocolPayloadPolicy.full);
      logs.add(logRecord('a', sessionId: 's1'));
      logs.add(logRecord('b', sessionId: 's2'));
      logs.add(logRecord('c'));
      cubit.selectView(ProtocolView.log);
      await settle(tester);
      var asked = 0;

      expect(cubit.exportNeedsConfirmation, isFalse);
      await cubit.exportActive(
        confirm: () async {
          asked++;
          return true;
        },
      );

      expect(asked, 0);
      final saved = saver.saved.single;
      expect(saved.suggestedName, startsWith('codelab-protocol-log-'));
      final lines = _lines(saved.text);
      expect(lines.first['view'], 'log');
      expect(lines.first['count'], 2);
      expect(lines.skip(1).map((l) => l['event']), ['a', 'c']);
      expect(lines.skip(1).every((l) => l['type'] == 'record'), isTrue);
    });

    testCubit('отказ в диалоге сохранения: без заметки, исход cancelled', (
      tester,
    ) async {
      saver.result = const ProtocolExportCancelled();
      workspace.pushAll([frame(omitted: ProtocolPayloadOmitted.policy)]);
      await settle(tester);

      await cubit.exportActive(confirm: () async => true);

      expect(cubit.state.saveFailed, isFalse);
      expect(exportEvent()['outcome'], 'cancelled');
    });

    testCubit('сбой записи: заметка в состоянии, исход failed с '
        'error_class, без путей и текста', (tester) async {
      saver.result = const ProtocolExportFailed('FileSystemException');
      workspace.pushAll([frame(omitted: ProtocolPayloadOmitted.policy)]);
      await settle(tester);

      await cubit.exportActive(confirm: () async => true);

      expect(cubit.state.saveFailed, isTrue);
      final event = exportEvent();
      expect(event['outcome'], 'failed');
      expect(event['error_class'], 'FileSystemException');
      expect(event.keys.toSet(), {
        'event',
        'level',
        'view',
        'outcome',
        'count',
        'error_class',
      });
    });

    testCubit('заметка сбоя сбрасывается следующим действием', (tester) async {
      saver.result = const ProtocolExportFailed('FileSystemException');
      workspace.pushAll([frame(omitted: ProtocolPayloadOmitted.policy)]);
      await settle(tester);
      await cubit.exportActive(confirm: () async => true);
      expect(cubit.state.saveFailed, isTrue);

      cubit.togglePause();

      expect(cubit.state.saveFailed, isFalse);
    });

    testCubit('событие экспорта не содержит имени файла, payload и '
        'фильтров', (tester) async {
      workspace.pushAll([frame(omitted: ProtocolPayloadOmitted.policy)]);
      cubit.setFrameQuery('prompt');
      await settle(tester);
      workspace.push(frame(omitted: ProtocolPayloadOmitted.policy));

      await cubit.exportActive(confirm: () async => true);

      final event = exportEvent();
      expect(event.keys.toSet(), {
        'event',
        'level',
        'view',
        'outcome',
        'count',
      });
    });

    testCubit('пустой вид: экспорт ничего не делает', (tester) async {
      var asked = 0;

      await cubit.exportActive(
        confirm: () async {
          asked++;
          return true;
        },
      );

      expect(asked, 0);
      expect(saver.saved, isEmpty);
      expect(
        logger.entries.where((e) => e['event'] == 'protocol_pane.export'),
        isEmpty,
      );
    });
  });
}

/// Порт, который во время «диалога сохранения» выключает Trace (D10).
final class _TraceOffDuringSave implements ProtocolExportSaver {
  _TraceOffDuringSave(this._beforeReturn);

  final void Function() _beforeReturn;
  String? text;

  @override
  Future<ProtocolExportSaveResult> save({
    required String suggestedName,
    required String text,
  }) async {
    this.text = text;
    _beforeReturn();
    return const ProtocolExportSaved();
  }
}
