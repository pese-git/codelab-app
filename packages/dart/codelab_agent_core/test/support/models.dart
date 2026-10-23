import 'package:codelab_agent_core/codelab_agent_core.dart';

/// A model for tests that do not care about model metadata.
final testModel = ModelRef(
  provider: 'test',
  id: 'model-1',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 32000,
  maxOutputTokens: 4096,
);

AssistantMessage partialMessage({
  String? text,
  StopReason stopReason = StopReason.stop,
  LlmErrorClass? errorClass,
}) => AssistantMessage(
  content: [if (text != null) TextContent(text)],
  model: testModel,
  usage: Usage.zero,
  stopReason: stopReason,
  errorClass: errorClass,
  timestamp: DateTime.utc(2026),
);
