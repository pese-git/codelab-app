import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'prompt_failure.freezed.dart';

/// Типизированная причина сорвавшегося prompt turn.
///
/// Почему: раньше ход хранил только `error.toString()`, и машиночитаемая
/// причина от агента CodeLab (`data.codelab`: `errorClass`, `message`,
/// `retryable`, §13.8 документа ядра) терялась на границе ACP. Без неё
/// клиент не может ни объяснить сбой человеку, ни решить, уместен ли повтор
/// (design D2 change `add-connection-and-error-states`).
///
/// Для чего: поле `PromptTurn.failure`; по нему ядро клиента строит заметку
/// о сбое и признак `canRetry`, а app — заголовок заметки.
///
/// Как использовать: протокольный клиент создаёт значение при сбое хода —
/// [PromptFailure.fromJsonRpcError] для ответа-ошибки на `session/prompt`,
/// [PromptFailure.connectionLost] для хода, прерванного обрывом транспорта;
/// потребители разбирают его исчерпывающим `switch`.
@freezed
sealed class PromptFailure with _$PromptFailure {
  const PromptFailure._();

  /// Ответ-ошибка агента с расширением `data.codelab`.
  ///
  /// [errorClass] — строка, а не enum: словарь классов принадлежит агенту и
  /// растёт, а незнакомое значение не должно ломать разбор (`AGENTS.md` §7).
  /// [retryable] равен `null`, если агент не прислал `bool`.
  const factory PromptFailure.agent({
    String? errorClass,
    required String message,
    bool? retryable,
  }) = AgentPromptFailure;

  /// JSON-RPC ошибка без расширения CodeLab — например, от стороннего агента.
  const factory PromptFailure.request({
    required int code,
    required String message,
  }) = RequestPromptFailure;

  /// Ход прерван неожиданным отказом транспорта текущего соединения.
  const factory PromptFailure.connectionLost() = ConnectionLostPromptFailure;

  /// Любой другой сбой: таймаут, ошибка декодирования, исключение клиента.
  const factory PromptFailure.unknown({required String message}) =
      UnknownPromptFailure;

  /// Разбирает ответ-ошибку агента; `data.codelab` — расширение CodeLab
  /// (spec `agent-acp-server` «Расширения протокола этапа 4»).
  ///
  /// Поле неожиданного типа считается отсутствующим: ответ агента не должен
  /// ломать показ сбоя (spec `acp-protocol-client` «Типизированный сбой
  /// prompt turn»).
  factory PromptFailure.fromJsonRpcError(JsonRpcError error) {
    final data = error.data;
    final codelab = data is Map ? data['codelab'] : null;
    if (codelab is! Map) {
      return PromptFailure.request(code: error.code, message: error.message);
    }
    final errorClass = codelab['errorClass'];
    final message = codelab['message'];
    final retryable = codelab['retryable'];
    return PromptFailure.agent(
      errorClass: errorClass is String ? errorClass : null,
      message: message is String && message.isNotEmpty
          ? message
          : error.message,
      retryable: retryable is bool ? retryable : null,
    );
  }
}
