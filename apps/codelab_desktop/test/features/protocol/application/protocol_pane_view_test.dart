// Маппер панели Protocol: состояние в данные кита (задача 4.3 change
// `redesign-protocol-pane`; spec agent-workbench-ui «Таблица кадров»
// («Подписи кадров», «Тег соединения»), «Выбранный кадр», «Вид Log панели
// Protocol», «Режим Trace панели Protocol» («Кадр до включения Trace»);
// design.md D8, D12, D13, D17).
//
// Красный до задачи 4.4: файла
// `lib/features/protocol/application/protocol_pane_view.dart` нет. Ожидаемый
// API (design.md D7 называет файл и «мапперы», сигнатур нет — они зафиксированы
// здесь; тексты берутся из каталога app, поэтому передаётся `l10n`):
//
// * `protocolMethodLabel(frame)` — подпись колонки `Method` по правилам D13;
// * `protocolFrameTitle(frame)` — `→ session/new · id 1`;
// * `protocolSizeLabel(bytes)` — `2.0 KB`;
// * `protocolFrameRow(frame, {selected})` — строка таблицы кита, `id` строки —
//   `seq` кадра строкой;
// * `protocolFrameDetail(frame, {basePolicy, traceEnabled, l10n, onCopy})`;
// * `protocolFrameCopyText(frame)` — ровно то, что показано телом: JSON
//   payload или поля кадра в JSON;
// * `protocolJsonSegments(payload)` — сегменты по `"<redacted>"`;
// * `protocolRecordEventText(record)`, `protocolRecordRow(record, {index,
//   selected})`, `protocolRecordDetail(record, {l10n, frameAvailable,
//   onShowFrame, onCopy})`, `protocolRecordCopyText(record)` — запись JSON-ом.
//
// Тексты кадров и записей не переводятся (spec app-settings, перечень
// непереводимого): методы, поля и JSON проверяются как есть.

import 'dart:convert';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_view.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixtures.dart';

const _in = ProtocolFrameDirection.inbound;
final _l10n = AppLocalizationsEn();

void main() {
  group('подписи Method (сценарий «Подписи кадров»)', () {
    test('запрос — метод', () {
      expect(
        protocolMethodLabel(protocolFrame(method: 'session/new', id: 1)),
        'session/new',
      );
    });

    test('уведомление с подробностью — «метод · подробность»', () {
      expect(
        protocolMethodLabel(
          protocolFrame(
            direction: _in,
            kind: ProtocolFrameKind.notification,
            method: 'session/update',
            detail: 'tool_call',
          ),
        ),
        'session/update · tool_call',
      );
    });

    test('запрос или уведомление без метода — подпись по виду кадра', () {
      expect(protocolMethodLabel(protocolFrame(id: 1)), 'request');
      expect(
        protocolMethodLabel(
          protocolFrame(
            kind: ProtocolFrameKind.notification,
            direction: _in,
            detail: 'plan',
          ),
        ),
        'notification · plan',
      );
    });

    test('результат — «метод · result»', () {
      expect(
        protocolMethodLabel(
          protocolFrame(
            direction: _in,
            kind: ProtocolFrameKind.result,
            method: 'session/new',
            id: 1,
          ),
        ),
        'session/new · result',
      );
    });

    test('результат с подробностью — «метод · result · подробность»', () {
      expect(
        protocolMethodLabel(
          protocolFrame(
            kind: ProtocolFrameKind.result,
            method: 'session/request_permission',
            id: 'a9',
            detail: 'allow_once',
          ),
        ),
        'session/request_permission · result · allow_once',
      );
    });

    test('результат с неизвестным методом — просто result', () {
      expect(
        protocolMethodLabel(
          protocolFrame(kind: ProtocolFrameKind.result, id: 9),
        ),
        'result',
      );
    });

    test('ошибка — «error <код> · <подробность>», ASCII-минус', () {
      expect(
        protocolMethodLabel(
          protocolFrame(
            direction: _in,
            kind: ProtocolFrameKind.error,
            method: 'session/prompt',
            id: 5,
            errorCode: -32603,
            detail: 'Internal error',
          ),
        ),
        'error -32603 · Internal error',
      );
    });

    test('ошибка без подробности — «error <код>»', () {
      expect(
        protocolMethodLabel(
          protocolFrame(
            kind: ProtocolFrameKind.error,
            id: 5,
            errorCode: -32000,
          ),
        ),
        'error -32000',
      );
    });
  });

  group('строка таблицы', () {
    test('ячейки: направление, подпись, id, локальное время', () {
      final row = protocolFrameRow(
        protocolFrame(
          seq: 3,
          direction: _in,
          kind: ProtocolFrameKind.notification,
          method: 'session/update',
          sessionId: 's1',
          detail: 'tool_call',
          time: DateTime(2026, 11, 22, 12, 0, 1),
        ),
        selected: false,
      );

      expect(row.id, '3');
      expect(row.cells, ['←', 'session/update · tool_call', '—', '12:00:01']);
      expect(row.tone, isNull);
      expect(row.tag, isNull);
      expect(row.selected, isFalse);
    });

    test('исходящий запрос: стрелка → и id', () {
      final row = protocolFrameRow(
        protocolFrame(method: 'session/new', id: 1, sessionId: 's1'),
        selected: true,
      );

      expect(row.cells[0], '→');
      expect(row.cells[2], '1');
      expect(row.selected, isTrue);
    });

    test('ошибка красится тоном опасности', () {
      final row = protocolFrameRow(
        protocolFrame(
          kind: ProtocolFrameKind.error,
          id: 5,
          errorCode: -32603,
          detail: 'Internal error',
          sessionId: 's1',
        ),
        selected: false,
      );

      expect(row.tone, CodeLabTone.danger);
    });

    test(
      'элемент без сессии несёт тег connection (сценарий «Тег соединения»)',
      () {
        final connection = protocolFrameRow(
          protocolFrame(method: 'initialize', id: 0),
          selected: false,
        );
        final session = protocolFrameRow(
          protocolFrame(method: 'session/prompt', id: 2, sessionId: 's1'),
          selected: false,
        );

        expect(connection.tag, 'connection');
        expect(session.tag, isNull);
      },
    );
  });

  group('заголовок и размер', () {
    test('«→ метод · id N»', () {
      expect(
        protocolFrameTitle(protocolFrame(method: 'session/new', id: 1)),
        '→ session/new · id 1',
      );
    });

    test('без id — без «· id»', () {
      expect(
        protocolFrameTitle(
          protocolFrame(
            direction: _in,
            kind: ProtocolFrameKind.notification,
            method: 'session/update',
            detail: 'plan',
          ),
        ),
        '← session/update · plan',
      );
    });

    test('размер: байты и килобайты с десятыми', () {
      expect(protocolSizeLabel(2048), '2.0 KB');
      expect(protocolSizeLabel(1536), '1.5 KB');
      expect(protocolSizeLabel(512), '512 B');
    });
  });

  group('сегменты JSON', () {
    test('замаскированное значение — отдельный сегмент', () {
      final segments = protocolJsonSegments({
        'name': 'Authorization',
        'value': '<redacted>',
      });

      final masked = segments.where((s) => s.masked).toList();
      expect(masked, hasLength(1));
      expect(masked.single.text, '<redacted>');
      expect(
        segments.where((s) => !s.masked).map((s) => s.text).join(),
        isNot(contains('<redacted>')),
      );
    });

    test('сегменты без потерь склеиваются в отформатированный JSON', () {
      final payload = <String, Object?>{
        'method': 'session/new',
        'params': {
          'mcpServers': [
            {'name': 'Authorization', 'value': '<redacted>'},
          ],
          '_meta': {'apiKey': '<redacted>'},
        },
      };

      final segments = protocolJsonSegments(payload);

      expect(
        segments.map((s) => s.text).join(),
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      expect(segments.where((s) => s.masked), hasLength(2));
    });

    test('без маскирования — один немаскированный сегмент', () {
      final segments = protocolJsonSegments({'a': 1});

      expect(segments.every((s) => !s.masked), isTrue);
      expect(segments.map((s) => s.text).join(), contains('"a": 1'));
    });
  });

  group('выбранный кадр: debug-сборка (политика full)', () {
    final frame = protocolFrame(
      method: 'session/new',
      id: 1,
      size: 2048,
      payload: {
        'method': 'session/new',
        'params': {
          'mcpServers': [
            {'name': 'Authorization', 'value': '<redacted>'},
          ],
        },
      },
    );

    CodeLabProtocolDetail detail({VoidCallback? onCopy}) => protocolFrameDetail(
      frame,
      basePolicy: ProtocolPayloadPolicy.full,
      traceEnabled: false,
      l10n: _l10n,
      onCopy: onCopy,
    );

    test('заголовок, теги направления и размера', () {
      final d = detail();

      expect(d.title, '→ session/new · id 1');
      expect(d.tags.map((t) => t.label), ['client → agent', '2.0 KB']);
    });

    test('InfoBar — предупреждение «Debug build: full payloads.»', () {
      final info = detail().info!;

      expect(info.title, 'Debug build: full payloads.');
      expect(
        info.message,
        'Release builds keep metadata only. Secrets are masked before a '
        'frame is stored.',
      );
      expect(info.tone, CodeLabTone.warning);
    });

    test('тело — сегменты JSON, полей нет', () {
      final d = detail();

      expect(d.segments, isNotNull);
      expect(d.segments!.where((s) => s.masked), hasLength(1));
      expect(d.fields, isNull);
      expect(d.note, isNull);
    });

    test('Copy копирует показанное тело и только его', () {
      final text = protocolFrameCopyText(frame);

      expect(jsonDecode(text), frame.payload);
      expect(text, contains('<redacted>'));
    });

    test('onCopy передаётся киту как есть', () {
      var copied = 0;
      detail(onCopy: () => copied++).onCopy!();

      expect(copied, 1);
    });

    test('входящий кадр: тег agent → client', () {
      final d = protocolFrameDetail(
        protocolFrame(
          direction: _in,
          kind: ProtocolFrameKind.notification,
          method: 'session/update',
          payload: {'a': 1},
        ),
        basePolicy: ProtocolPayloadPolicy.full,
        traceEnabled: false,
        l10n: _l10n,
      );

      expect(d.tags.first.label, 'agent → client');
    });
  });

  group('выбранный кадр: release-сборка (metadataOnly)', () {
    final frame = protocolFrame(
      seq: 4,
      method: 'session/prompt',
      id: 2,
      sessionId: 's_7f3a',
      generation: 3,
      size: 300,
      omitted: ProtocolPayloadOmitted.policy,
      time: DateTime(2026, 11, 22, 12, 0, 4),
    );

    CodeLabProtocolDetail detail({bool trace = false}) => protocolFrameDetail(
      frame,
      basePolicy: ProtocolPayloadPolicy.metadataOnly,
      traceEnabled: trace,
      l10n: _l10n,
    );

    test('InfoBar — информационный «Release build: metadata only.»', () {
      final info = detail().info!;

      expect(info.title, 'Release build: metadata only.');
      expect(
        info.message,
        'Payloads are not stored. Secrets are masked before a frame is '
        'stored.',
      );
      expect(info.tone, CodeLabTone.neutral);
    });

    test('тело — поля кадра по порядку спецификации, без JSON', () {
      final d = detail();

      expect(d.segments, isNull);
      expect(d.fields!.map((f) => f.label), [
        'direction',
        'kind',
        'method',
        'id',
        'session_id',
        'connection_generation',
        'size',
        'time',
      ]);
      final values = {for (final f in d.fields!) f.label: f.value};
      expect(values['direction'], 'outbound');
      expect(values['kind'], 'request');
      expect(values['method'], 'session/prompt');
      expect(values['id'], '2');
      expect(values['session_id'], 's_7f3a');
      expect(values['connection_generation'], '3');
      expect(values['size'], '300');
    });

    test('у ошибки в полях есть error_code и detail', () {
      final d = protocolFrameDetail(
        protocolFrame(
          direction: _in,
          kind: ProtocolFrameKind.error,
          id: 5,
          errorCode: -32603,
          detail: 'Internal error',
          omitted: ProtocolPayloadOmitted.policy,
        ),
        basePolicy: ProtocolPayloadPolicy.metadataOnly,
        traceEnabled: false,
        l10n: _l10n,
      );

      final values = {for (final f in d.fields!) f.label: f.value};
      expect(values['error_code'], '-32603');
      expect(values['detail'], 'Internal error');
    });

    test('Copy копирует только поля кадра в JSON', () {
      final text = protocolFrameCopyText(frame);
      final decoded = jsonDecode(text) as Map<String, Object?>;

      expect(decoded['method'], 'session/prompt');
      expect(decoded['session_id'], 's_7f3a');
      expect(decoded.containsKey('payload'), isFalse);
    });

    test('без Trace строки «Recorded before Trace…» нет', () {
      expect(detail().note, isNull);
    });
  });

  group('выбранный кадр: режим Trace (D17)', () {
    CodeLabProtocolDetail detail(ProtocolFrame frame) => protocolFrameDetail(
      frame,
      basePolicy: ProtocolPayloadPolicy.metadataOnly,
      traceEnabled: true,
      l10n: _l10n,
    );

    test('InfoBar — предупреждение «Trace on: full payloads.»', () {
      final info = detail(
        protocolFrame(method: 'session/new', id: 1, payload: {'a': 1}),
      ).info!;

      expect(info.title, 'Trace on: full payloads.');
      expect(
        info.message,
        'Prompts, file contents and tool output are kept in memory until '
        'Trace is turned off. Secrets are masked.',
      );
      expect(info.tone, CodeLabTone.warning);
    });

    test('кадр с payload показывает JSON', () {
      final d = detail(
        protocolFrame(method: 'session/new', id: 1, payload: {'a': 1}),
      );

      expect(d.segments, isNotNull);
      expect(d.fields, isNull);
    });

    test('кадр до включения Trace — поля и строка про метаданные', () {
      final d = detail(
        protocolFrame(
          method: 'session/new',
          id: 1,
          omitted: ProtocolPayloadOmitted.policy,
        ),
      );

      expect(d.segments, isNull);
      expect(d.fields, isNotEmpty);
      expect(d.note, 'Recorded before Trace was turned on: metadata only.');
    });
  });

  group('payload не сохранён из-за размера', () {
    test('вместо JSON — заметка и поля кадра', () {
      final d = protocolFrameDetail(
        protocolFrame(
          method: 'session/prompt',
          id: 2,
          size: 600000,
          omitted: ProtocolPayloadOmitted.tooLarge,
        ),
        basePolicy: ProtocolPayloadPolicy.full,
        traceEnabled: false,
        l10n: _l10n,
      );

      expect(d.segments, isNull);
      expect(d.note, 'The payload is larger than 256 KB and was not stored.');
      expect(d.fields, isNotEmpty);
    });
  });

  group('вид Log', () {
    test('protocol_message — «<стрелка> <метод> · id <id>»', () {
      final record = logRecord(
        'protocol_message',
        level: 'trace',
        sessionId: 's1',
        requestId: 2,
        extra: {'direction': 'outbound', 'method': 'session/prompt'},
      );

      expect(protocolRecordEventText(record), '→ session/prompt · id 2');
    });

    test('входящее protocol_message — стрелка ←, без id — без «· id»', () {
      final record = logRecord(
        'protocol_message',
        level: 'trace',
        extra: {'direction': 'inbound', 'method': 'session/update'},
      );

      expect(protocolRecordEventText(record), '← session/update');
    });

    test('обычное событие — его текст', () {
      expect(
        protocolRecordEventText(logRecord('connection_state_changed')),
        'connection_state_changed',
      );
    });

    test('строка: время HH:mm:ss.SSS, уровень, категория, событие', () {
      final row = protocolRecordRow(
        logRecord(
          'tool_failed',
          level: 'error',
          category: 'session',
          sessionId: 's1',
          time: DateTime(2026, 11, 22, 12, 0, 1, 234),
        ),
        index: 7,
        selected: false,
      );

      expect(row.id, '7');
      expect(row.cells, ['12:00:01.234', 'ERROR', 'session', 'tool_failed']);
      expect(row.tag, isNull);
    });

    test('теги уровней: TRACE и DEBUG нейтральные, INFO акцентный, '
        'WARNING предупреждающий, ERROR и CRITICAL опасные', () {
      final expected = {
        'trace': null,
        'debug': null,
        'info': CodeLabTone.accent,
        'warning': CodeLabTone.warning,
        'error': CodeLabTone.danger,
        'critical': CodeLabTone.danger,
      };
      for (final entry in expected.entries) {
        final row = protocolRecordRow(
          logRecord('e', level: entry.key, sessionId: 's1'),
          index: 0,
          selected: false,
        );
        expect(
          row.tone ?? CodeLabTone.neutral,
          entry.value ?? CodeLabTone.neutral,
          reason: entry.key,
        );
      }
    });

    test('запись без сессии несёт тег connection', () {
      final connection = protocolRecordRow(
        logRecord('transport_closed', category: 'connection'),
        index: 0,
        selected: false,
      );
      final session = protocolRecordRow(
        logRecord('prompt_sent', sessionId: 's1'),
        index: 1,
        selected: false,
      );

      expect(connection.tag, 'connection');
      expect(session.tag, isNull);
    });

    group('панель записи', () {
      final record = logRecord(
        'tool_failed',
        level: 'error',
        category: 'session',
        sessionId: 's1',
        requestId: 5,
        generation: 2,
        time: DateTime(2026, 11, 22, 12, 0, 1, 234),
        extra: {'detail': 'Overflow'},
      );

      CodeLabProtocolDetail detail({
        bool frameAvailable = true,
        VoidCallback? onShowFrame,
      }) => protocolRecordDetail(
        record,
        l10n: _l10n,
        frameAvailable: frameAvailable,
        onShowFrame: onShowFrame,
      );

      test('заголовок — текст события, теги — уровень и категория', () {
        final d = detail();

        expect(d.title, 'tool_failed');
        expect(d.tags.map((t) => t.label), ['ERROR', 'session']);
      });

      test('InfoBar «Same buffer as /logs and Expand.»', () {
        final info = detail().info!;

        expect(info.title, 'Same buffer as /logs and Expand.');
        expect(
          info.message,
          'Secrets are masked before a record is stored; protocol_message '
          'records carry the full frame only in debug builds.',
        );
        expect(info.tone, CodeLabTone.neutral);
      });

      test(
        'поля: time с датой первым, далее по порядку записи, без уровня',
        () {
          final fields = detail().fields!;

          expect(fields.first.label, 'time');
          expect(fields.first.value, startsWith('2026-11-22 12:00:01'));
          expect(fields.map((f) => f.label), [
            'time',
            'event',
            'category',
            'session_id',
            'request_id',
            'connection_generation',
            'detail',
          ]);
          expect(fields.map((f) => f.label), isNot(contains('level')));
          expect(fields.map((f) => f.label), isNot(contains('timestamp')));
        },
      );

      test('у request_id — ссылка «Show frame in Frames»', () {
        var shown = 0;
        final field = detail(
          onShowFrame: () => shown++,
        ).fields!.firstWhere((f) => f.label == 'request_id');

        expect(field.linkLabel, 'Show frame in Frames');
        field.onLink!();
        expect(shown, 1);
        expect(
          detail().fields!.where((f) => f.linkLabel != null),
          hasLength(1),
        );
      });

      test('кадра нет — ссылка недоступна, подсказка про буфер', () {
        final field = detail(
          frameAvailable: false,
        ).fields!.firstWhere((f) => f.label == 'request_id');

        expect(field.linkLabel, 'Show frame in Frames');
        expect(field.onLink, isNull);
        expect(
          field.linkUnavailableHint,
          'The frame is no longer in the buffer.',
        );
      });

      test('Copy записи — JSON записи', () {
        final text = protocolRecordCopyText(record);

        expect(jsonDecode(text), record);
      });
    });
  });

  group('ревью после ручного смока', () {
    test('<redacted> внутри строки JSON — замаскированный сегмент', () {
      final payload = <String, Object?>{
        'text': '1| API_TOKEN=<redacted>',
        'value': '<redacted>',
      };

      final segments = protocolJsonSegments(payload);

      expect(segments.where((s) => s.masked), hasLength(2));
      expect(
        segments.map((s) => s.text).join(),
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      // Текст до маркера внутри строки остаётся обычным сегментом.
      expect(
        segments.where((s) => !s.masked).map((s) => s.text).join(),
        contains('1| API_TOKEN='),
      );
      expect(
        segments.where((s) => !s.masked).map((s) => s.text).join(),
        isNot(contains('<redacted>')),
      );
    });

    test('поле time кадра — местное время «yyyy-MM-dd HH:mm:ss.SSS», как у '
        'записи журнала', () {
      final frame = protocolFrame(
        method: 'session/new',
        id: 1,
        omitted: ProtocolPayloadOmitted.policy,
        time: DateTime(2026, 11, 22, 12, 0, 4, 7),
      );

      final detail = protocolFrameDetail(
        frame,
        basePolicy: ProtocolPayloadPolicy.metadataOnly,
        traceEnabled: false,
        l10n: _l10n,
      );

      final time = detail.fields!.firstWhere((f) => f.label == 'time');
      expect(time.value, '2026-11-22 12:00:04.007');
      expect(
        (jsonDecode(protocolFrameCopyText(frame))
            as Map<String, Object?>)['time'],
        '2026-11-22 12:00:04.007',
      );
    });

    test('поле payload записи журнала — JSON, а не Map.toString', () {
      final record = logRecord(
        'protocol_message',
        level: 'trace',
        extra: {
          'payload': {'jsonrpc': '2.0', 'id': 7},
        },
      );

      final detail = protocolRecordDetail(
        record,
        l10n: _l10n,
        frameAvailable: false,
      );

      final payload = detail.fields!.firstWhere((f) => f.label == 'payload');
      expect(jsonDecode(payload.value), {'jsonrpc': '2.0', 'id': 7});
      expect(payload.value, startsWith('{"jsonrpc"'));
    });
  });
}
