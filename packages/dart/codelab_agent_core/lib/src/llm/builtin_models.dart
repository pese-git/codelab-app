import 'model_catalog.dart';
import 'model_ref.dart';

/// Built-in model metadata (`agent-core-architecture` §2.12.2, design.md
/// D10): the source after explicit config values and before the safe
/// defaults.
///
/// Facts about the providers' products, taken from their public pages and
/// checked on 2026-10-23:
/// * OpenAI — https://developers.openai.com/api/docs/models and
///   https://developers.openai.com/api/docs/pricing (standard tier; cache
///   write is the 30-minute rate);
/// * Anthropic — https://platform.claude.com/docs/en/models/overview and
///   https://platform.claude.com/docs/en/about-claude/pricing (cache write
///   is the 5-minute rate; Claude Haiku 5.5 — the rate for prompts up to
///   100 000 tokens).
///
/// The table changes as an ordinary code change with
/// `builtin_models_test.dart`.
const builtinModels = <String, ModelInfo>{
  'gpt-6-astra': ModelInfo(
    contextWindow: 1050000,
    maxOutputTokens: 128000,
    cost: ModelCost(input: 10, output: 50, cacheRead: 1, cacheWrite: 12.5),
    supportsImages: true,
    supportsReasoning: true,
    hiddenReasoning: true,
  ),
  'gpt-6.1-sol': ModelInfo(
    contextWindow: 1050000,
    maxOutputTokens: 128000,
    cost: ModelCost(input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5),
    supportsImages: true,
    supportsReasoning: true,
    hiddenReasoning: true,
  ),
  'gpt-6-luna': ModelInfo(
    contextWindow: 1050000,
    maxOutputTokens: 128000,
    cost: ModelCost(
      input: 0.1,
      output: 0.5,
      cacheRead: 0.01,
      cacheWrite: 0.125,
    ),
    supportsImages: true,
    supportsReasoning: true,
    hiddenReasoning: true,
  ),
  'claude-fable-5-1': ModelInfo(
    contextWindow: 1000000,
    maxOutputTokens: 128000,
    cost: ModelCost(input: 10, output: 50, cacheRead: 0.25, cacheWrite: 12.5),
    supportsImages: true,
    supportsReasoning: true,
  ),
  'claude-opus-5-5': ModelInfo(
    contextWindow: 1000000,
    maxOutputTokens: 128000,
    cost: ModelCost(input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5),
    supportsImages: true,
    supportsReasoning: true,
  ),
  'claude-sonnet-5-5': ModelInfo(
    contextWindow: 1000000,
    maxOutputTokens: 128000,
    cost: ModelCost(input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5),
    supportsImages: true,
    supportsReasoning: true,
  ),
  'claude-haiku-5-5': ModelInfo(
    contextWindow: 1000000,
    maxOutputTokens: 128000,
    cost: ModelCost(
      input: 0.1,
      output: 0.5,
      cacheRead: 0.01,
      cacheWrite: 0.125,
    ),
    supportsImages: true,
    supportsReasoning: true,
  ),
};
