import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'standard_error_names.dart';

part 'protocol_frame.freezed.dart';

/// Направление кадра относительно клиента.
enum ProtocolFrameDirection {
  /// Клиент → агент.
  outbound,

  /// Агент → клиент.
  inbound,
}

/// Вид сообщения JSON-RPC, из которого построен кадр.
enum ProtocolFrameKind { request, notification, result, error }

/// Политика хранения payload кадров (design.md change `redesign-protocol-pane`,
/// D3).
///
/// Почему: пакет — чистый Dart и не знает режима сборки; решение «хранить
/// ли промпты и содержимое файлов» принимает composition root хоста.
/// [full] — payload после маскирования, [metadataOnly] — только метаданные.
enum ProtocolPayloadPolicy { full, metadataOnly }

/// Почему у кадра нет payload.
enum ProtocolPayloadOmitted {
  /// Действующая политика — `metadataOnly`.
  policy,

  /// Payload не хранится из-за размера (D3): замаскированный больше 256 KiB
  /// либо исходное сообщение больше 256 KiB — тогда его не маскируют вообще
  /// (маскирование мегабайтной строки дорого, а хранить результат нельзя).
  tooLarge,
}

/// Кадр ACP: проекция одного сообщения JSON-RPC для показа и разбора.
///
/// Почему: хосту (панель Protocol, экспорт) нужны метаданные провода — метод,
/// id, сессия, поколение, размер — без разбора ACP у хоста
/// (`acp-boundary.md` §10; design.md change `redesign-protocol-pane`, D2).
///
/// Для чего: единица потока `AcpClientApplication.protocolFrames`, хранится
/// буфером `ProtocolFrameLog` kit. Поля читаются только из схемы ACP; payload
/// замаскирован `SecretRedactor` до того, как попал в кадр (D3, D4).
///
/// Как использовать: кадры строит только ядро (`ProtocolFrameRecorder`);
/// хост их читает. [sessionId] — строка с провода, а не `SessionId`: кадр —
/// проекция провода, сравнение с фокусом — по `SessionId.value`.
@freezed
sealed class ProtocolFrame with _$ProtocolFrame {
  const factory ProtocolFrame({
    /// Номер кадра в пределах экземпляра ядра; растёт через поколения.
    required int seq,

    /// Время записи по часам ядра.
    required DateTime time,
    required ProtocolFrameDirection direction,

    /// Поколение соединения на момент записи.
    required int connectionGeneration,
    required ProtocolFrameKind kind,

    /// Метод запроса или уведомления; у ответа — метод запроса с тем же id.
    String? method,
    JsonRpcId? id,
    String? sessionId,

    /// `session/update` — `sessionUpdate`; результат `request_permission` —
    /// `optionId` или `cancelled`; ошибка — стандартное имя кода (при
    /// `metadataOnly`) или замаскированный текст (при `full`).
    String? detail,
    int? errorCode,

    /// Длина сообщения в байтах UTF-8 до маскирования.
    required int size,

    /// Замаскированный JSON-объект сообщения или `null`.
    Map<String, Object?>? payload,
    ProtocolPayloadOmitted? payloadOmitted,
  }) = _ProtocolFrame;
}

/// Операции над кадром, общие для ядра, буфера kit и хоста.
extension ProtocolFrameRedaction on ProtocolFrame {
  /// Копия кадра без payload (выключение Trace, D17).
  ///
  /// Почему: payload снимается «задним числом» у кадров, построенных при
  /// `full`; у ошибки `detail` в этом случае — замаскированный, но всё же текст
  /// агента (`error.message`), поэтому он заменяется стандартным именем кода,
  /// как у кадра, построенного при `metadataOnly` (D3).
  ///
  /// Как использовать: буфер kit вызывает при выключении Trace и для кадров в
  /// пути; хост, который держит кадр у себя (выбранный, снимок паузы),
  /// вызывает то же самое при выключении Trace. Размер, поля и `seq` не
  /// меняются; `tooLarge` остаётся `tooLarge`.
  ProtocolFrame withoutPayload() => copyWith(
    payload: null,
    payloadOmitted: payloadOmitted ?? ProtocolPayloadOmitted.policy,
    detail: kind == ProtocolFrameKind.error
        ? (errorCode == null ? null : standardErrorName(errorCode!))
        : detail,
  );
}
