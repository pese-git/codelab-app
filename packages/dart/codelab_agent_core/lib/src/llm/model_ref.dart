/// A resolved model: everything an adapter needs to call it
/// (`agent-core-architecture` §2.2). Produced by the model catalog
/// (§2.12.2).
library;

/// Wire dialect of a provider.
enum ProviderApi { openaiChat, anthropicMessages, gemini }

enum ReasoningEffort { low, medium, high }

/// Dollars per 1 000 000 tokens.
final class ModelCost {
  const ModelCost({
    required this.input,
    required this.output,
    this.cacheRead = 0,
    this.cacheWrite = 0,
  });

  final double input, output, cacheRead, cacheWrite;

  @override
  bool operator ==(Object other) =>
      other is ModelCost &&
      other.input == input &&
      other.output == output &&
      other.cacheRead == cacheRead &&
      other.cacheWrite == cacheWrite;

  @override
  int get hashCode => Object.hash(input, output, cacheRead, cacheWrite);
}

final class ModelRef {
  const ModelRef({
    required this.provider,
    required this.id,
    required this.api,
    required this.baseUrl,
    required this.contextWindow,
    required this.maxOutputTokens,
    this.cost,
    this.supportsImages = false,
    this.supportsReasoning = false,
    this.reasoningEffort,
    this.hiddenReasoning = false,
    this.supportsTools = true,
  });

  /// Name of the provider entry of the config, e.g. `openrouter`.
  final String provider;

  /// Model id at the provider.
  final String id;
  final ProviderApi api;
  final Uri baseUrl;
  final int contextWindow, maxOutputTokens;

  /// `null` — prices are unknown.
  final ModelCost? cost;
  final bool supportsImages, supportsReasoning;

  /// `null` — reasoning is off (§2.12.3).
  final ReasoningEffort? reasoningEffort;

  /// The model reasons without bytes in the stream before the answer
  /// (§2.10.5).
  final bool hiddenReasoning;

  /// After MVP: `false` — tool calls through the prompt (§17.10.11).
  final bool supportsTools;

  @override
  bool operator ==(Object other) =>
      other is ModelRef &&
      other.provider == provider &&
      other.id == id &&
      other.api == api &&
      other.baseUrl == baseUrl &&
      other.contextWindow == contextWindow &&
      other.maxOutputTokens == maxOutputTokens &&
      other.cost == cost &&
      other.supportsImages == supportsImages &&
      other.supportsReasoning == supportsReasoning &&
      other.reasoningEffort == reasoningEffort &&
      other.hiddenReasoning == hiddenReasoning &&
      other.supportsTools == supportsTools;

  @override
  int get hashCode => Object.hash(
    provider,
    id,
    api,
    baseUrl,
    contextWindow,
    maxOutputTokens,
    cost,
    supportsImages,
    supportsReasoning,
    reasoningEffort,
    hiddenReasoning,
    supportsTools,
  );

  @override
  String toString() => 'ModelRef($provider/$id)';
}
