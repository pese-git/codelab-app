import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import '../domain/secret_redaction.dart';
import 'protocol_frame.dart';
import 'standard_error_names.dart';

/// Результат записи одного сообщения: поля для трассы и сам кадр.
///
/// [frame] равен `null`, если построить кадр не удалось ([failure]); поля
/// [kind], [method], [requestId], [sessionId] при этом заполнены, пока их
/// удалось прочитать, а [size] — `null`: размер считается один раз для кадра
/// и трассы, и его сбой не должен ронять трассу (design.md D2).
final class RecordedMessage {
  const RecordedMessage({
    required this.kind,
    this.method,
    this.requestId,
    this.sessionId,
    this.size,
    this.frame,
    this.failure,
  });

  final ProtocolFrameKind kind;
  final String? method;

  /// Строка id (`id.toJsonValue().toString()`); у уведомления `null`.
  final String? requestId;
  final String? sessionId;
  final int? size;
  final ProtocolFrame? frame;
  final Object? failure;
}

/// Строит [ProtocolFrame] из сообщений провода и сопоставляет ответы с
/// запросами.
///
/// Почему: метод и сессия ответа в самом ответе не передаются — их знает
/// только запрос с тем же id из противоположного направления; сопоставление
/// нужно в одном месте, рядом с поколением (design.md change
/// `redesign-protocol-pane`, D2).
///
/// Для чего: внутренняя деталь `AcpClientApplication` (не экспортируется).
/// Держит карту `(направление запроса, id) → (метод, сессия)` текущего
/// поколения: ответ снимает запись, смена поколения очищает карту, размер
/// ограничен [maxPending] — самый старый запрос вытесняется.
///
/// Как использовать: [record] на каждое исходящее и входящее сообщение
/// текущего поколения. Исключения наружу не выходят: сбой — в
/// [RecordedMessage.failure].
final class ProtocolFrameRecorder {
  ProtocolFrameRecorder({required DateTime Function() clock}) : _clock = clock;

  /// Предел учёта запросов без ответа (D2).
  static const maxPending = 1024;

  /// Предел замаскированного payload в UTF-8 (D3): `fs/read_text_file` на
  /// мегабайты не должен съедать буфер.
  static const maxPayloadBytes = 256 * 1024;

  /// Предел текста ошибки в `detail` при `full` (D3).
  static const maxDetailLength = 120;

  static const _redactor = SecretRedactor();

  final DateTime Function() _clock;
  // Ключ — сам `JsonRpcId`, а не его строка: `1` и `"1"` — разные id (ревью).
  final _pending = <(ProtocolFrameDirection, JsonRpcId), (String, String?)>{};
  var _trackedGeneration = 0;
  var _nextSeq = 0;

  /// Записывает [message]; [payloads] — действующая политика кадров в
  /// момент построения (базовая или Trace, D17).
  RecordedMessage record(
    ProtocolFrameDirection direction,
    JsonRpcMessage message, {
    required int generation,
    required ProtocolPayloadPolicy payloads,
  }) {
    if (generation != _trackedGeneration) {
      // Запрос старого поколения не сопоставляется с ответом нового (D2).
      _pending.clear();
      _trackedGeneration = generation;
    }
    final kind = switch (message) {
      JsonRpcRequest() => ProtocolFrameKind.request,
      JsonRpcNotification() => ProtocolFrameKind.notification,
      JsonRpcResponse(:final error) =>
        error == null ? ProtocolFrameKind.result : ProtocolFrameKind.error,
    };
    String? method;
    String? requestId;
    String? sessionId;
    try {
      final id = switch (message) {
        JsonRpcRequest(:final id) || JsonRpcResponse(:final id) => id,
        JsonRpcNotification() => null,
      };
      requestId = id?.toJsonValue().toString();
      final tracked = _correlate(direction, message, id);
      method = clipText(tracked.method);
      sessionId = tracked.sessionId;

      final json = message.toJson();
      final size = utf8.encode(jsonEncode(json)).length;
      final (:detail, :errorCode) = _detail(message, method, payloads);
      Map<String, Object?>? payload;
      ProtocolPayloadOmitted? omitted;
      if (payloads == ProtocolPayloadPolicy.full) {
        // Исходный размер больше предела — маскировать нет смысла и опасно:
        // шаблоны `redactText` на мегабайтной строке без разделителей
        // работают минутами (квадратичный перебор), а хранить такой payload
        // всё равно нельзя (D3).
        if (size > maxPayloadBytes) {
          omitted = ProtocolPayloadOmitted.tooLarge;
        } else {
          final redacted = _redactor.redactMap(json);
          // Маскирование растёт не больше чем в 4 раза (минимальный секрет
          // `"k":1` в 5 байт становится `"k":"<redacted>"` в 17): у малых
          // сообщений — основной поток стриминга — повторное кодирование
          // ради проверки предела не нужно (design.md Risks, стоимость кадра).
          if (size * 4 > maxPayloadBytes &&
              utf8.encode(jsonEncode(redacted)).length > maxPayloadBytes) {
            omitted = ProtocolPayloadOmitted.tooLarge;
          } else {
            payload = redacted;
          }
        }
      } else {
        omitted = ProtocolPayloadOmitted.policy;
      }
      final frame = ProtocolFrame(
        seq: _nextSeq++,
        time: _clock(),
        direction: direction,
        connectionGeneration: generation,
        kind: kind,
        method: method,
        id: id,
        sessionId: sessionId,
        detail: detail,
        errorCode: errorCode,
        size: size,
        payload: payload,
        payloadOmitted: omitted,
      );
      return RecordedMessage(
        kind: kind,
        method: method,
        requestId: requestId,
        sessionId: sessionId,
        size: size,
        frame: frame,
      );
    } on Object catch (error) {
      return RecordedMessage(
        kind: kind,
        method: method ?? _ownMethod(message),
        requestId: requestId,
        sessionId: sessionId,
        failure: error,
      );
    }
  }

  /// Обрезает строку до [maxDetailLength] кодовых единиц, не разрезая
  /// суррогатную пару: одинокий суррогат ломает кодирование в UTF-8 и вывод.
  static String? clipText(String? text) {
    if (text == null || text.length <= maxDetailLength) return text;
    var end = maxDetailLength;
    final last = text.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return text.substring(0, end);
  }

  static String? _ownMethod(JsonRpcMessage message) => switch (message) {
    JsonRpcRequest(:final method) ||
    JsonRpcNotification(:final method) => method,
    JsonRpcResponse() => null,
  };

  /// Метод и сессия кадра; запрос регистрируется, ответ снимает запись.
  ({String? method, String? sessionId}) _correlate(
    ProtocolFrameDirection direction,
    JsonRpcMessage message,
    JsonRpcId? id,
  ) {
    switch (message) {
      case JsonRpcRequest(:final method, :final params):
        final sessionId = _sessionIdOf(params);
        _pending.remove((direction, id!));
        _pending[(direction, id)] = (method, sessionId);
        if (_pending.length > maxPending) {
          _pending.remove(_pending.keys.first);
        }
        return (method: method, sessionId: sessionId);
      case JsonRpcNotification(:final method, :final params):
        return (method: method, sessionId: _sessionIdOf(params));
      case JsonRpcResponse(:final result):
        final requestDirection = direction == ProtocolFrameDirection.inbound
            ? ProtocolFrameDirection.outbound
            : ProtocolFrameDirection.inbound;
        final request = _pending.remove((requestDirection, id!));
        var sessionId = request?.$2;
        if (request?.$1 == sessionNewMethod && result is Map) {
          final created = result['sessionId'];
          if (created is String) {
            sessionId = created;
          }
        }
        return (method: request?.$1, sessionId: sessionId);
    }
  }

  static String? _sessionIdOf(Object? params) {
    if (params is Map) {
      final value = params['sessionId'];
      if (value is String) return value;
    }
    return null;
  }

  /// `detail` и код ошибки по D2 и D3; незнакомая форма — без подробности.
  ({String? detail, int? errorCode}) _detail(
    JsonRpcMessage message,
    String? method,
    ProtocolPayloadPolicy payloads,
  ) {
    switch (message) {
      case JsonRpcNotification(:final method, :final params):
        if (method == sessionUpdateMethod && params is Map) {
          final update = params['update'];
          if (update is Map && update['sessionUpdate'] is String) {
            return (
              detail: clipText(update['sessionUpdate'] as String),
              errorCode: null,
            );
          }
        }
        return (detail: null, errorCode: null);
      case JsonRpcResponse(:final error?):
        final String? detail;
        if (payloads == ProtocolPayloadPolicy.full) {
          detail = clipText(_redactor.redactText(error.message));
        } else {
          // Текст ошибки агента может содержать пути и фрагменты данных:
          // при `metadataOnly` — только стандартное имя кода (D3).
          detail = standardErrorName(error.code);
        }
        return (detail: detail, errorCode: error.code);
      case JsonRpcResponse(:final result):
        if (method == sessionRequestPermissionMethod && result is Map) {
          final outcome = result['outcome'];
          if (outcome is Map) {
            if (outcome['outcome'] == 'cancelled') {
              return (detail: 'cancelled', errorCode: null);
            }
            if (outcome['optionId'] is String) {
              return (
                detail: clipText(outcome['optionId'] as String),
                errorCode: null,
              );
            }
          }
        }
        return (detail: null, errorCode: null);
      case JsonRpcRequest():
        return (detail: null, errorCode: null);
    }
  }
}
