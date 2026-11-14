import '../cancel/cancel_token.dart';
import 'event_stream.dart';
import 'messages.dart';
import 'model_ref.dart';

/// One model request (`agent-core-architecture` §2.5). Contract for every
/// adapter and decorator:
///
/// 1. returns the stream synchronously and never throws — neither
///    synchronously nor through `result`; any failure is an `ErrorEvent`
///    (LLM-1);
/// 2. starts working not earlier than the next microtask;
/// 3. the stream has exactly one terminal event, and it is the last
///    (LLM-2);
/// 4. [cancel] yields `ErrorEvent` with `stopReason: aborted` (LLM-7).
typedef StreamFunction =
    AssistantMessageEventStream Function(
      ModelRef model,
      LlmContext context, {
      CancelToken? cancel,
    });

final class ToolSchema {
  ToolSchema({
    required this.name,
    required this.description,
    required Map<String, Object?> parameters,
  }) : parameters = Map.unmodifiable(parameters);

  final String name, description;

  /// JSON Schema of an object (§6.3.2).
  final Map<String, Object?> parameters;
}

final class LlmContext {
  LlmContext({
    required this.systemPrompt,
    required List<Message> messages,
    List<ToolSchema> tools = const [],
    this.cacheKey,
  }) : messages = List.unmodifiable(messages),
       tools = List.unmodifiable(tools);

  final String systemPrompt;
  final List<Message> messages;
  final List<ToolSchema> tools;

  /// Prompt cache key (§2.12.1): the session id; `null` — not sent.
  final String? cacheKey;
}
