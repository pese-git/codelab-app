/// Оценка размера контекста в токенах (`agent-core-architecture` §9.3).
///
/// Почему эвристика: точного токенайзера для всех провайдеров в Dart нет,
/// а на web он слишком тяжёл. «4 символа UTF-16 ≈ 1 токен» ошибается на
/// коде и не-латинице, поэтому [estimateContextTokens] якорится на точном
/// `usage` последнего ответа провайдера и оценивает только хвост после
/// него; недооценку ловит аварийный путь `overflow` (CMP-8).
///
/// Как использовать: порог сжатия, проверка payload перед запросом и
/// `ModelRequested.estimatedTokens` считают окно одной функцией
/// [effectiveContextWindow] (CMP-6).
library;

import 'dart:convert';

import '../llm/messages.dart';
import '../llm/model_ref.dart';
import '../llm/stream_function.dart';

/// Стоимость картинки — константа: размер base64 не говорит о числе
/// токенов изображения у провайдера (§9.3).
const imageTokens = 1200;

/// Служебные поля сообщения (роль, разделители).
const _messageOverhead = 4;

int _chars(int length) => (length / 4).ceil();

int _block(ContentBlock block) => switch (block) {
  TextContent(:final text) => _chars(text.length),
  ThinkingContent(:final thinking, :final signature, :final redacted) => _chars(
    redacted ? (signature ?? '').length : thinking.length,
  ),
  ToolCall(:final name, :final arguments) => _chars(
    name.length + jsonEncode(arguments).length,
  ),
  ImageContent() => imageTokens,
};

/// Оценка одного сообщения: блоки, `+4` на сообщение, у результата
/// инструмента — ещё имя инструмента.
int estimateMessageTokens(Message message) {
  final blocks = message.content.fold(0, (sum, b) => sum + _block(b));
  return switch (message) {
    ToolResultMessage(:final toolName) =>
      blocks + _chars(toolName.length) + _messageOverhead,
    _ => blocks + _messageOverhead,
  };
}

/// Оценка по символам: сообщения, системный промпт и схемы инструментов.
int estimateTokens(
  List<Message> messages, {
  String? systemPrompt,
  List<ToolSchema> tools = const [],
}) =>
    _chars(systemPrompt?.length ?? 0) +
    (tools.isEmpty ? 0 : _chars(_schemasJson(tools).length)) +
    messages.fold(0, (sum, m) => sum + estimateMessageTokens(m));

/// Оценка контекста с якорем на `usage` (§9.3).
///
/// Якорь — последний ответ модели с ненулевым
/// `input + cacheRead + cacheWrite`: `input` провайдера уже включает
/// системный промпт, схемы и все сообщения до него. Ответы до сжатия в
/// проекции несут `Usage.zero` (§8.7) и якорем не служат — иначе оценка
/// помнила бы размер несжатого контекста.
int estimateContextTokens(
  List<Message> messages, {
  required String systemPrompt,
  required List<ToolSchema> tools,
}) {
  final anchor = messages.lastIndexWhere(
    (m) =>
        m is AssistantMessage &&
        m.usage.input + m.usage.cacheRead + m.usage.cacheWrite > 0,
  );
  if (anchor < 0) {
    return estimateTokens(messages, systemPrompt: systemPrompt, tools: tools);
  }
  final usage = (messages[anchor] as AssistantMessage).usage;
  return usage.input +
      usage.cacheRead +
      usage.cacheWrite +
      usage.output +
      estimateTokens(messages.sublist(anchor + 1));
}

/// Оценка payload запроса — оценщик цикла (`AgentLoopConfig.estimateTokens`).
int estimateLlmContext(LlmContext context) => estimateContextTokens(
  context.messages,
  systemPrompt: context.systemPrompt,
  tools: context.tools,
);

/// Окно для порога, проверки перед запросом и индикатора (CMP-6).
int effectiveContextWindow(ModelRef model, {int? cap}) =>
    cap == null || cap > model.contextWindow ? model.contextWindow : cap;

String _schemasJson(List<ToolSchema> tools) => jsonEncode([
  for (final t in tools)
    {'name': t.name, 'description': t.description, 'parameters': t.parameters},
]);
