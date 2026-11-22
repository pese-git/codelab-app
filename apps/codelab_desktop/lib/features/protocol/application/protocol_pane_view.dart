/// Маппер панели Protocol: кадры и записи журнала в данные кита `codelab_ui`
/// (design.md change `redesign-protocol-pane`, D7, D12, D13, D17).
///
/// Почему здесь, а не в виджете и не в kit: кит ничего не знает об ACP,
/// кадрах и журнале (`codelab_ui/AGENTS.md` §2), а виджет не разбирает
/// протокол (`AGENTS.md` §7). Маппер — чистые функции над готовыми
/// `ProtocolFrame` и записями журнала; решения о политике payload приходят
/// аргументами, а не читаются из режима сборки.
///
/// Содержимое кадров и записей (методы, id, поля, JSON) не переводится
/// (spec app-settings, перечень непереводимого); тексты InfoBar, заметок и
/// подсказок берутся из каталога app.
library;

import 'dart:convert';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_ui/codelab_ui.dart';

import '../../../l10n/app_localizations.dart';

const _redacted = '"<redacted>"';
const _indent = JsonEncoder.withIndent('  ');

String _two(int value) => value.toString().padLeft(2, '0');

String _clock(DateTime time) {
  final local = time.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

String _clockMillis(DateTime time) {
  final local = time.toLocal();
  return '${_clock(local)}.${local.millisecond.toString().padLeft(3, '0')}';
}

String _dateTimeMillis(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_clockMillis(local)}';
}

String _arrowOf(ProtocolFrameDirection direction) =>
    direction == ProtocolFrameDirection.outbound ? '→' : '←';

/// Подпись колонки `Method` (D13): запрос и уведомление — «метод» и
/// необязательная подробность через « · », результат — «метод · result»,
/// ошибка — «error код». Подробность добавляется последней.
String protocolMethodLabel(ProtocolFrame frame) {
  final detail = frame.detail;
  switch (frame.kind) {
    case ProtocolFrameKind.request:
    case ProtocolFrameKind.notification:
      // Метод провода может отсутствовать: тогда подпись — вид кадра.
      final method = frame.method ?? frame.kind.name;
      return detail == null ? method : '$method · $detail';
    case ProtocolFrameKind.result:
      final head = frame.method == null ? 'result' : '${frame.method} · result';
      return detail == null ? head : '$head · $detail';
    case ProtocolFrameKind.error:
      final head = frame.errorCode == null
          ? 'error'
          : 'error ${frame.errorCode}';
      return detail == null ? head : '$head · $detail';
  }
}

String _idOf(ProtocolFrame frame) => '${frame.id?.toJsonValue() ?? ''}';

/// Заголовок панели выбранного кадра: `→ session/new · id 1`.
String protocolFrameTitle(ProtocolFrame frame) {
  final id = _idOf(frame);
  final label = protocolMethodLabel(frame);
  return '${_arrowOf(frame.direction)} $label${id.isEmpty ? '' : ' · id $id'}';
}

/// Размер кадра: `512 B`, `2.0 KB` (единицы — часть содержимого панели).
String protocolSizeLabel(int bytes) =>
    bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';

/// Строка таблицы кадров; `id` строки — `seq` кадра (устойчив при вытеснении).
///
/// Тег `connection` ставится у элементов без сессии; перевод тега —
/// забота виджета.
CodeLabProtocolTableRow protocolFrameRow(
  ProtocolFrame frame, {
  required bool selected,
}) {
  final id = _idOf(frame);
  return CodeLabProtocolTableRow(
    id: '${frame.seq}',
    cells: [
      _arrowOf(frame.direction),
      protocolMethodLabel(frame),
      id.isEmpty ? '—' : id,
      _clock(frame.time),
    ],
    tone: frame.kind == ProtocolFrameKind.error ? CodeLabTone.danger : null,
    selected: selected,
    tag: frame.sessionId == null ? 'connection' : null,
  );
}

/// Поля кадра в порядке спецификации; `null` опущены. Они же — тело кадра без
/// payload и содержимое `Copy` в этом случае.
Map<String, Object?> _frameFields(ProtocolFrame frame) => {
  'direction': frame.direction.name,
  'kind': frame.kind.name,
  'method': frame.method,
  'id': frame.id?.toJsonValue(),
  'session_id': frame.sessionId,
  'connection_generation': frame.connectionGeneration,
  'error_code': frame.errorCode,
  'detail': frame.detail,
  'size': frame.size,
  'time': frame.time.toUtc().toIso8601String(),
}..removeWhere((_, value) => value == null);

/// Сегменты отформатированного JSON: значение `"<redacted>"` — отдельный
/// замаскированный сегмент (D12). Склейка текстов даёт исходный JSON.
List<CodeLabMaskedSegment> protocolJsonSegments(Map<String, Object?> payload) {
  final pieces = _indent.convert(payload).split(_redacted);
  return [
    for (var i = 0; i < pieces.length; i++) ...[
      if (i > 0) const CodeLabMaskedSegment(_redacted, masked: true),
      if (pieces[i].isNotEmpty) CodeLabMaskedSegment(pieces[i], masked: false),
    ],
  ];
}

/// Ровно то, что показано телом кадра: JSON payload или поля кадра в JSON.
String protocolFrameCopyText(ProtocolFrame frame) =>
    _indent.convert(frame.payload ?? _frameFields(frame));

/// Панель выбранного кадра (spec «Выбранный кадр», D13, D17).
///
/// [basePolicy] — базовая политика хоста (`full` — debug-сборка),
/// [traceEnabled] — режим Trace; по ним выбирается один из трёх InfoBar.
CodeLabProtocolDetail protocolFrameDetail(
  ProtocolFrame frame, {
  required ProtocolPayloadPolicy basePolicy,
  required bool traceEnabled,
  required AppLocalizations l10n,
  void Function()? onCopy,
}) {
  final info = basePolicy == ProtocolPayloadPolicy.full
      ? CodeLabProtocolInfo(
          title: l10n.protocolInfoDebugTitle,
          message: l10n.protocolInfoDebugMessage,
          tone: CodeLabTone.warning,
        )
      : traceEnabled
      ? CodeLabProtocolInfo(
          title: l10n.protocolInfoTraceTitle,
          message: l10n.protocolInfoTraceMessage,
          tone: CodeLabTone.warning,
        )
      : CodeLabProtocolInfo(
          title: l10n.protocolInfoReleaseTitle,
          message: l10n.protocolInfoReleaseMessage,
        );
  final payload = frame.payload;
  String? note;
  if (payload == null) {
    if (frame.payloadOmitted == ProtocolPayloadOmitted.tooLarge) {
      note = l10n.protocolNoteTooLarge;
    } else if (traceEnabled) {
      note = l10n.protocolNoteBeforeTrace;
    }
  }
  return CodeLabProtocolDetail(
    title: protocolFrameTitle(frame),
    tags: [
      CodeLabProtocolTag(
        label: frame.direction == ProtocolFrameDirection.outbound
            ? l10n.protocolDirectionOut
            : l10n.protocolDirectionIn,
      ),
      CodeLabProtocolTag(
        label: protocolSizeLabel(frame.size),
        tone: CodeLabTone.accent,
      ),
    ],
    info: info,
    segments: payload == null ? null : protocolJsonSegments(payload),
    fields: payload == null
        ? [
            for (final entry in _frameFields(frame).entries)
              CodeLabProtocolField(label: entry.key, value: '${entry.value}'),
          ]
        : null,
    note: note,
    onCopy: onCopy,
  );
}

// ---------------------------------------------------------------------------
// Вид Log.

/// Текст события записи: у `protocol_message` — `→ session/prompt · id 2`.
String protocolRecordEventText(Map<String, Object?> record) {
  final event = '${record['event'] ?? ''}';
  if (event != 'protocol_message') return event;
  final arrow = record['direction'] == 'outbound' ? '→' : '←';
  final method = record['method'] ?? event;
  final id = record['request_id'];
  return '$arrow $method${id == null ? '' : ' · id $id'}';
}

DateTime? _timeOf(Map<String, Object?> record) {
  final raw = record['timestamp'];
  return raw is String ? DateTime.tryParse(raw) : null;
}

String _levelNameOf(Map<String, Object?> record) =>
    '${record['level'] ?? ''}'.toUpperCase();

/// Тон тега уровня: TRACE и DEBUG нейтральные, INFO акцентный, WARNING
/// предупреждающий, ERROR и CRITICAL опасные (D8).
CodeLabTone? _levelTone(Map<String, Object?> record) =>
    switch ('${record['level']}') {
      'info' => CodeLabTone.accent,
      'warning' => CodeLabTone.warning,
      'error' || 'critical' => CodeLabTone.danger,
      _ => null,
    };

/// Строка таблицы журнала; `id` — индекс в опубликованном списке видимых
/// записей (адрес строки для `onRowSelected`, D7).
CodeLabProtocolTableRow protocolRecordRow(
  Map<String, Object?> record, {
  required int index,
  required bool selected,
}) {
  final time = _timeOf(record);
  return CodeLabProtocolTableRow(
    id: '$index',
    cells: [
      time == null ? '—' : _clockMillis(time),
      _levelNameOf(record),
      '${record['category'] ?? '—'}',
      protocolRecordEventText(record),
    ],
    tone: _levelTone(record),
    selected: selected,
    tag: record['session_id'] == null ? 'connection' : null,
  );
}

/// Запись журнала в JSON: то, что копирует `Copy` вида Log.
String protocolRecordCopyText(Map<String, Object?> record) =>
    _indent.convert(record);

/// Панель выбранной записи (D8): поля, InfoBar буфера и ссылка `request_id`.
///
/// [frameAvailable] — кадр с этим `request_id` есть в области; без него ссылка
/// недоступна и несёт подсказку про буфер. [onShowFrame] — переход к кадру.
CodeLabProtocolDetail protocolRecordDetail(
  Map<String, Object?> record, {
  required AppLocalizations l10n,
  required bool frameAvailable,
  void Function()? onShowFrame,
  void Function()? onCopy,
}) {
  final time = _timeOf(record);
  final category = record['category'];
  return CodeLabProtocolDetail(
    title: protocolRecordEventText(record),
    tags: [
      CodeLabProtocolTag(
        label: _levelNameOf(record),
        tone: _levelTone(record) ?? CodeLabTone.neutral,
      ),
      if (category != null) CodeLabProtocolTag(label: '$category'),
    ],
    info: CodeLabProtocolInfo(
      title: l10n.protocolInfoLogTitle,
      message: l10n.protocolInfoLogMessage,
    ),
    fields: [
      if (time != null)
        CodeLabProtocolField(label: 'time', value: _dateTimeMillis(time)),
      for (final entry in record.entries)
        if (entry.key != 'level' && entry.key != 'timestamp')
          if (entry.key == 'request_id')
            CodeLabProtocolField(
              label: entry.key,
              value: '${entry.value}',
              linkLabel: l10n.protocolShowFrame,
              onLink: frameAvailable ? onShowFrame : null,
              linkUnavailableHint: frameAvailable
                  ? null
                  : l10n.protocolFrameGone,
            )
          else
            CodeLabProtocolField(label: entry.key, value: '${entry.value}'),
    ],
    onCopy: onCopy,
  );
}
