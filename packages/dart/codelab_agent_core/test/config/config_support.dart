import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Слой в памяти для тестов конфигурации: `ConfigTree` без файлов
/// (CFG-5, design.md change `add-agent-configuration`, D17).
ConfigTree layer(
  Map<String, Object?> values, {
  ConfigLayerKind kind = ConfigLayerKind.user,
  String? source,
  Map<String, ConfigPosition> positions = const {},
}) => ConfigTree(
  kind: kind,
  source: source ?? _defaultSource(kind),
  values: values,
  positions: positions,
);

String _defaultSource(ConfigLayerKind kind) => switch (kind) {
  ConfigLayerKind.defaults => 'defaults',
  ConfigLayerKind.user => '/home/u/.codelab/config.yaml',
  ConfigLayerKind.project => '/proj/.codelab/config.yaml',
  ConfigLayerKind.projectLocal => '/proj/.codelab/config.local.yaml',
  ConfigLayerKind.extra => '/tmp/extra.yaml',
  ConfigLayerKind.environment => 'env',
  ConfigLayerKind.flags => 'flags',
  ConfigLayerKind.appStorage => 'app-storage',
};

/// Минимальный валидный конфиг: один провайдер, одна модель, модель по
/// умолчанию. Остальные ключи тесты добавляют поверх.
Map<String, Object?> baseValues() => {
  'providers': {
    'p': {
      'kind': 'openai-compatible',
      'base_url': 'https://llm.test/v1',
      'models': {'m': <String, Object?>{}},
    },
  },
  'agent': {'default_model': 'p/m'},
};

/// Рекурсивное слияние карт — только для сборки входных данных тестов.
Map<String, Object?> withValues(
  Map<String, Object?> base,
  Map<String, Object?> extra,
) {
  final out = {...base};
  for (final MapEntry(:key, :value) in extra.entries) {
    final old = out[key];
    out[key] = old is Map<String, Object?> && value is Map<String, Object?>
        ? withValues(old, value)
        : value;
  }
  return out;
}

ConfigLoadResult load(
  List<ConfigTree> layers, {
  Map<String, String> environment = const {},
  String? projectRoot,
}) => CoreConfig.fromLayers(
  layers,
  environment: environment,
  projectRoot: projectRoot,
);

/// Проблемы с данным путём ключа.
List<ConfigIssue> issuesAt(ConfigLoadResult result, String key) => [
  for (final issue in result.issues)
    if (issue.key == key) issue,
];

/// Предупреждения загрузки с данным именем события.
List<ConfigIssue> warningsOf(ConfigLoadResult result, String event) => [
  for (final warning in result.warnings)
    if (warning.event == event) warning,
];
