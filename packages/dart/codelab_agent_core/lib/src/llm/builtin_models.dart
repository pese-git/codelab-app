import 'model_catalog.dart';
import 'model_ref.dart';

/// Окно контекста, когда его не назвал ни конфиг, ни встроенная таблица
/// (`agent-core-architecture` §2.12.2). Публично, чтобы мастер провайдера
/// клиентов (`codelab_setup`) предлагал то же значение, что применит каталог
/// (design.md change `add-provider-setup-ui`, D7 «Окно контекста»).
const safeDefaultContextWindow = 32000;

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
///   100 000 tokens); adaptive thinking — the thinking table of
///   https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking
///   (`budget_tokens` is rejected with 400 on Claude 5.x).
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
    thinkingMode: ThinkingMode.adaptive,
  ),
  'claude-opus-5-5': ModelInfo(
    contextWindow: 1000000,
    maxOutputTokens: 128000,
    cost: ModelCost(input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5),
    supportsImages: true,
    supportsReasoning: true,
    thinkingMode: ThinkingMode.adaptive,
  ),
  'claude-sonnet-5-5': ModelInfo(
    contextWindow: 1000000,
    maxOutputTokens: 128000,
    cost: ModelCost(input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5),
    supportsImages: true,
    supportsReasoning: true,
    thinkingMode: ThinkingMode.adaptive,
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
    thinkingMode: ThinkingMode.adaptive,
  ),
};

/// Ищет модель [model] во встроенной таблице [builtinModels].
///
/// Почему публичная функция: правило поиска одно — его используют
/// `StaticModelCatalog` и мастер провайдера клиентов, а второй копии не должно
/// быть (design.md change `add-provider-setup-ui`, D7, задача 3.0a).
///
/// Правило: точное имя; затем самый длинный ключ таблицы, являющийся
/// префиксом имени, за которым идёт `-` или конец (`claude-opus-5-5` находит
/// запись для `claude-opus-5-5-20260101`); затем то же для части после
/// последнего `/` (id шлюза вида `anthropic/claude-sonnet-5-5`). Неизвестная
/// модель — `null`: вызывающий берёт [safeDefaultContextWindow].
ModelInfo? builtinModelInfo(String model) =>
    lookupModelInfo(builtinModels, model);

/// Тот же поиск по произвольной таблице [table]: `StaticModelCatalog` принимает
/// свою таблицу (тесты), правило остаётся общим. Не экспортируется из барелей.
ModelInfo? lookupModelInfo(Map<String, ModelInfo> table, String model) {
  for (final candidate in {
    model,
    model.substring(model.lastIndexOf('/') + 1),
  }) {
    if (table[candidate] case final info?) {
      return info;
    }
    String? best;
    for (final key in table.keys) {
      final fits =
          candidate.startsWith(key) &&
          (candidate.length == key.length || candidate[key.length] == '-');
      if (fits && (best == null || key.length > best.length)) {
        best = key;
      }
    }
    if (best != null) {
      return table[best];
    }
  }
  return null;
}
