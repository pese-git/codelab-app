import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../tools/pairing.dart';
import 'loop_config.dart';

/// Payload одного запроса к модели (`agent-core-architecture` §5.2).
///
/// Почему отдельно от транскрипта: модель должна получать исправленный
/// запрос (без пустых ответов, с парными вызовами, с заметкой `Revise`), а
/// транскрипт остаётся фактом разговора и не меняется (LOOP-7).
///
/// Как использовать: цикл вызывает функцию перед каждым запросом, включая
/// повтор после ошибки парности. Шаги: [transform] или копия транскрипта;
/// удаление пустых ответов (шаг 1a); ремонт парности; [note] последним
/// `user`-сообщением (шаг 3). Отчёт ремонта цикл превращает в
/// `ToolPairingRepaired`.
Future<PairingRepair> buildPayload(
  List<Message> transcript, {
  required CancelToken cancel,
  TransformContextHook? transform,
  UserMessage? note,
}) async {
  final messages = transform == null
      ? List<Message>.of(transcript)
      : await transform(List.unmodifiable(transcript), cancel);
  // Провайдеры отвергают assistant без контента, а повторять модели её же
  // пустоту бесполезно (§5.4.1, LOOP-15).
  messages.removeWhere((m) => m is AssistantMessage && isEmptyCompletion(m));
  final repaired = repairToolPairing(messages);
  if (note == null) {
    return repaired;
  }
  return PairingRepair([...repaired.messages, note], repaired.report);
}

/// Пустой ответ модели (§5.4.1): `stop` или `toolUse`, без вызовов, и у
/// каждого текстового блока пустой `trim()`. Рассуждения не учитываются:
/// ответ «только thinking» не даёт ни текста, ни действия.
bool isEmptyCompletion(AssistantMessage message) =>
    (message.stopReason == StopReason.stop ||
        message.stopReason == StopReason.toolUse) &&
    message.toolCalls.isEmpty &&
    message.content.whereType<TextContent>().every(
      (b) => b.text.trim().isEmpty,
    );

final _pairingError = RegExp(
  r'tool[_ ]?(use|call|result)',
  caseSensitive: false,
);

/// A `badRequest` that describes a broken call/result pairing, as OpenAI
/// (`tool_call_id`) and Anthropic (`tool_use` / `tool_result`) word it
/// (design.md, D8).
bool isPairingError(String? message) =>
    message != null && _pairingError.hasMatch(message);
