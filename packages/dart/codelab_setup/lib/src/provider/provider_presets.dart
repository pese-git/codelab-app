/// Пресеты провайдеров мастера (`dart-agent-and-clients` §12.4.4, шаг 1;
/// design.md change `add-provider-setup-ui`, D2).
library;

/// Нужен ли пресету ключ.
enum KeyRequirement {
  /// Без ключа провайдер не работает (OpenAI, Anthropic, OpenRouter).
  required,

  /// Ключ допустим, но не обязателен (шлюзы «Custom …»).
  optional,

  /// Ключ не нужен (локальный Ollama): по умолчанию выбран `NoKey`.
  none,
}

/// Готовая заготовка провайдера: вид, адрес и подсказка про переменную ключа.
///
/// Почему таблица моста: список один на app и CLI (SETUP-8, «артборд
/// `CliSetup`»); переход таблицы в ядро (§17.10.2) после MVP не меняет
/// потребителей — `ProviderPreset` станет реэкспортом. Адреса — общеизвестные
/// адреса API провайдеров, а не чужой код (`AGENTS.md` §5).
///
/// Как использовать: мастер берёт пресеты из `ProviderPresets.all` (или из
/// параметра `presets`) и выбирает по [id] событием `PresetChosen`.
final class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.label,
    required this.kind,
    required this.baseUrl,
    required this.key,
    this.suggestedEnvVar,
  });

  /// `openai` | `anthropic` | `openrouter` | `ollama` | `custom-openai` |
  /// `custom-anthropic`. Для не-custom пресетов это же и id провайдера.
  final String id;

  /// Подпись в списке (одни слова в CLI и app, D7).
  final String label;

  /// Значение `providers.<id>.kind`: `openai-compatible` | `anthropic`.
  final String kind;

  /// Адрес по умолчанию; `null` — пользователь вводит сам.
  final String? baseUrl;
  final KeyRequirement key;

  /// Подсказка для `UseEnvVar` (`OPENAI_API_KEY`, …).
  final String? suggestedEnvVar;

  /// Пресет «Custom …»: id провайдера строится из хоста адреса.
  bool get isCustom => id.startsWith('custom-');

  @override
  String toString() => 'ProviderPreset($id)';
}

/// Таблица пресетов MVP (решение Q5): ровно список артборда `CliSetup`.
abstract final class ProviderPresets {
  static const all = <ProviderPreset>[
    ProviderPreset(
      id: 'openai',
      label: 'OpenAI',
      kind: 'openai-compatible',
      baseUrl: 'https://api.openai.com/v1',
      key: KeyRequirement.required,
      suggestedEnvVar: 'OPENAI_API_KEY',
    ),
    ProviderPreset(
      id: 'anthropic',
      label: 'Anthropic',
      kind: 'anthropic',
      baseUrl: 'https://api.anthropic.com',
      key: KeyRequirement.required,
      suggestedEnvVar: 'ANTHROPIC_API_KEY',
    ),
    ProviderPreset(
      id: 'openrouter',
      label: 'OpenRouter',
      kind: 'openai-compatible',
      baseUrl: 'https://openrouter.ai/api/v1',
      key: KeyRequirement.required,
      suggestedEnvVar: 'OPENROUTER_API_KEY',
    ),
    ProviderPreset(
      id: 'ollama',
      label: 'Ollama (local, no key)',
      kind: 'openai-compatible',
      baseUrl: 'http://localhost:11434/v1',
      key: KeyRequirement.none,
    ),
    ProviderPreset(
      id: 'custom-openai',
      label: 'Custom OpenAI-compatible endpoint',
      kind: 'openai-compatible',
      baseUrl: null,
      key: KeyRequirement.optional,
    ),
    ProviderPreset(
      id: 'custom-anthropic',
      label: 'Custom Anthropic-compatible endpoint',
      kind: 'anthropic',
      baseUrl: null,
      key: KeyRequirement.optional,
    ),
  ];
}
