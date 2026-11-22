// Общие данные тестов панели Protocol (change `redesign-protocol-pane`,
// задачи 4.1–5.3): кадры ACP и записи журнала без транспорта и ядра.
//
// Почему отдельный файл: кадры и записи нужны фильтрам, маппере, Cubit,
// экспорту и виджет-тестам; одинаковые конструкторы держат примеры в тестах
// сопоставимыми (design.md D6, D8, D10).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';

/// Опорное время: локальное, чтобы `HH:mm:ss` не зависело от пояса машины.
final protocolBaseTime = DateTime(2026, 11, 22, 12);

/// Кадр ACP с разумными умолчаниями; `seq` задаёт порядок записи.
ProtocolFrame protocolFrame({
  int seq = 1,
  ProtocolFrameDirection direction = ProtocolFrameDirection.outbound,
  ProtocolFrameKind kind = ProtocolFrameKind.request,
  String? method,
  Object? id,
  String? sessionId,
  String? detail,
  int? errorCode,
  int size = 100,
  Map<String, Object?>? payload,
  ProtocolPayloadOmitted? omitted,
  int generation = 1,
  DateTime? time,
}) => ProtocolFrame(
  seq: seq,
  time: time ?? protocolBaseTime.add(Duration(seconds: seq)),
  direction: direction,
  connectionGeneration: generation,
  kind: kind,
  method: method,
  id: id == null ? null : JsonRpcId.fromJsonValue(id),
  sessionId: sessionId,
  detail: detail,
  errorCode: errorCode,
  size: size,
  payload: payload,
  payloadOmitted: omitted,
);

/// Запись встроенного журнала в том виде, как её отдаёт `LogBuffer`:
/// `level` — имя уровня, `timestamp` — ISO-строка, остальное — поля события.
Map<String, Object?> logRecord(
  String event, {
  String level = 'info',
  String? category,
  String? component,
  String? sessionId,
  Object? requestId,
  int? generation,
  DateTime? time,
  Map<String, Object?> extra = const {},
}) => {
  'timestamp': (time ?? protocolBaseTime).toIso8601String(),
  'level': level,
  'event': event,
  'category': ?category,
  'component': ?component,
  'session_id': ?sessionId,
  'request_id': ?requestId,
  'connection_generation': ?generation,
  ...extra,
};
