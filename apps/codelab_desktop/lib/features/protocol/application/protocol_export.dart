/// Сборка файла экспорта панели Protocol в JSON Lines (design.md change
/// `redesign-protocol-pane`, D10).
///
/// Почему отдельный файл: формат — контракт для `jq` и `grep`, его проверяют
/// тесты без Cubit и без файловой системы; запись файла — порт
/// `ProtocolExportSaver` в `lib/core/platform/`.
///
/// Как использовать: Cubit вызывает [buildFramesExport] или
/// [buildRecordsExport] в момент подтверждения и передаёт текст порту. В файл
/// идут уже замаскированные данные буфера; повторного маскирования нет.
library;

import 'dart:convert';

import 'package:codelab_client_acp/codelab_client_acp.dart';

import 'protocol_pane_state.dart' show ProtocolView;

const _lineEncoder = JsonEncoder();

/// Есть ли среди [frames] кадр с payload (debug-сборка или Trace) — тогда
/// экспорт Frames сначала спрашивает подтверждение (D10, `observability.md`
/// §50).
bool exportHasPayload(Iterable<ProtocolFrame> frames) =>
    frames.any((frame) => frame.payload != null);

/// Имя файла по умолчанию: `codelab-protocol-<frames|log>-<yyyyMMdd-HHmmss>.jsonl`.
String protocolExportFileName(ProtocolView view, DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return 'codelab-protocol-${view.name}-$stamp.jsonl';
}

String _lines(List<Map<String, Object?>> lines) =>
    '${lines.map(_lineEncoder.convert).join('\n')}\n';

Map<String, Object?> _header({
  required String view,
  required int count,
  required DateTime exportedAt,
  required bool debugBuild,
  required String appVersion,
  required String platform,
  required String? sessionId,
}) => {
  'type': 'codelab.protocol_export',
  'format': 1,
  'view': view,
  'build': debugBuild ? 'debug' : 'release',
  'app_version': appVersion,
  'platform': platform,
  'exported_at': exportedAt.toUtc().toIso8601String(),
  'session_id': sessionId,
  'count': count,
};

Map<String, Object?> _frameLine(ProtocolFrame frame) => {
  'type': 'frame',
  'seq': frame.seq,
  'time': frame.time.toUtc().toIso8601String(),
  'direction': frame.direction.name,
  'connection_generation': frame.connectionGeneration,
  'kind': frame.kind.name,
  'method': frame.method,
  'id': frame.id?.toJsonValue(),
  'session_id': frame.sessionId,
  'error_code': frame.errorCode,
  'detail': frame.detail,
  'size': frame.size,
  'payload': frame.payload,
  // Имя enum (`policy`, `tooLarge`), как в D10.
  'payload_omitted': frame.payloadOmitted?.name,
}..removeWhere((_, value) => value == null);

/// Текст экспорта вида Frames: заголовок и по строке на кадр.
String buildFramesExport({
  required List<ProtocolFrame> frames,
  required DateTime exportedAt,
  required bool debugBuild,
  required String appVersion,
  required String platform,
  required String? sessionId,
}) => _lines([
  _header(
    view: 'frames',
    count: frames.length,
    exportedAt: exportedAt,
    debugBuild: debugBuild,
    appVersion: appVersion,
    platform: platform,
    sessionId: sessionId,
  ),
  for (final frame in frames) _frameLine(frame),
]);

/// Текст экспорта вида Log: заголовок и по строке на запись журнала.
String buildRecordsExport({
  required List<Map<String, Object?>> records,
  required DateTime exportedAt,
  required bool debugBuild,
  required String appVersion,
  required String platform,
  required String? sessionId,
}) => _lines([
  _header(
    view: 'log',
    count: records.length,
    exportedAt: exportedAt,
    debugBuild: debugBuild,
    appVersion: appVersion,
    platform: platform,
    sessionId: sessionId,
  ),
  for (final record in records) {'type': 'record', ...record},
]);
