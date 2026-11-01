import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Дополняет слой флагов провайдерами и моделью сценария.
///
/// Почему: схема конфига требует `agent.default_model` из каталога
/// провайдеров, а у сценария каталог — его собственные модели. Каждая модель
/// становится моделью провайдера `openai-compatible` с адресом
/// `scripted.invalid`, окном контекста и лимитом ответа, поэтому конфигу не
/// нужны ни ключ, ни сеть. Функция общая у бинаря `--llm-script` и
/// встроенного агента (design.md change `add-embedded-agent-mode`, D8).
///
/// Как использовать: [flags] — слой флагов хоста, [models] — результат
/// `LlmScript.modelsOf`/`LlmScript.models` (не пустой: первая модель
/// становится моделью по умолчанию). Возвращает новый слой того же вида и
/// источника; значения [flags] сохраняются, кроме `providers` и `agent`.
ConfigTree withScriptedProviders(ConfigTree flags, List<ModelRef> models) {
  final providers = <String, Map<String, Object?>>{};
  for (final model in models) {
    final entry = providers.putIfAbsent(
      model.provider,
      () => {
        'kind': 'openai-compatible',
        'base_url': model.baseUrl.toString(),
        'models': <String, Object?>{},
      },
    );
    (entry['models']! as Map<String, Object?>)[model.id] = {
      'context_window': model.contextWindow,
      'max_output_tokens': model.maxOutputTokens,
    };
  }
  return ConfigTree(
    kind: flags.kind,
    source: flags.source,
    values: {
      ...flags.values,
      'providers': providers,
      'agent': {'default_model': '${models.first.provider}/${models.first.id}'},
    },
    positions: flags.positions,
  );
}
