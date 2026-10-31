import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Слой окружения: переменные `CODELAB_*`, у которых есть ключ конфигурации
/// (`agent-core-architecture` §15.6; design.md change
/// `add-agent-configuration`, D4).
///
/// Почему в `codelab_agent_io`: окружение процесса читает хост, а ядро получает
/// готовое дерево (CFG-5). Слой стоит выше файлов и ниже флагов (§15.2).
///
/// Для чего: превращает `CODELAB_MODEL`, `CODELAB_MAX_STEPS`,
/// `CODELAB_PERMISSION_MODE`, `CODELAB_LOG_LEVEL` и `CODELAB_LOG_FILE` в
/// `agent.default_model`, `budget.max_steps`, `permissions.mode`,
/// `logging.level` и `logging.file`. Остальные переменные ключей не имеют:
/// `CODELAB_HOME` и `CODELAB_CONFIG` читает загрузчик, `CODELAB_API_KEY` —
/// ссылка `api_key_env` провайдера `cli` (её ставит слой флагов), а
/// неизвестные `CODELAB_*` называет предупреждением `config.env.unknown`
/// [unknownEnvironmentWarnings] (его зовёт загрузчик).
///
/// Как использовать: `buildEnvironmentLayer(environment)`. Пустое значение
/// переменной равно её отсутствию. Нечисловой `CODELAB_MAX_STEPS` — проблема
/// `type` без значения переменной (оно не должно попадать в текст ошибок);
/// `autopilot` из `CODELAB_PERMISSION_MODE` отклоняет валидатор ядра: режим
/// включается только флагом (CFG-4). Пустой слой возвращается как `null`.
({ConfigTree? layer, List<ConfigIssue> issues}) buildEnvironmentLayer(
  Map<String, String> environment,
) {
  String? value(String name) {
    final raw = environment[name];
    return raw == null || raw.isEmpty ? null : raw;
  }

  final values = <String, Object?>{};
  final issues = <ConfigIssue>[];

  if (value('CODELAB_MODEL') case final model?) {
    values['agent'] = {'default_model': model};
  }
  if (value('CODELAB_MAX_STEPS') case final raw?) {
    final steps = int.tryParse(raw);
    if (steps == null) {
      issues.add(
        const ConfigIssue(
          kind: ConfigIssueKind.type,
          key: 'budget.max_steps',
          source: 'env',
          message: 'CODELAB_MAX_STEPS must be an integer',
        ),
      );
    } else {
      values['budget'] = {'max_steps': steps};
    }
  }
  if (value('CODELAB_PERMISSION_MODE') case final mode?) {
    values['permissions'] = {'mode': mode};
  }
  final logging = <String, Object?>{
    // Регистр не важен: профиль `codelab-app` передаёт `DEBUG`.
    'level': ?value('CODELAB_LOG_LEVEL')?.toLowerCase(),
    'file': ?value('CODELAB_LOG_FILE'),
  };
  if (logging.isNotEmpty) {
    values['logging'] = logging;
  }

  return (
    layer: values.isEmpty
        ? null
        : ConfigTree(
            kind: ConfigLayerKind.environment,
            source: 'env',
            values: values,
          ),
    issues: issues,
  );
}

/// Переменные `CODELAB_*`, которые знают ядро и его хосты (`agent-core-
/// architecture` §15.6). Другие дают предупреждение: опечатка не должна
/// молча игнорироваться.
///
/// `CODELAB_TEST_SECRET_STORE` (каталог тестового хранилища секретов) известен
/// только в сборке с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`: в
/// обычной сборке переменная не читается, каталог не создаётся, а
/// `config.env.unknown` называет её имя (§15.6; design.md change
/// `add-agent-secret-store`, D14). Условие вычисляется при компиляции:
/// окружением процесса его не включить (§12.4.13).
const _knownVariables = {
  'CODELAB_HOME',
  'CODELAB_CONFIG',
  'CODELAB_MODEL',
  'CODELAB_API_KEY',
  'CODELAB_PERMISSION_MODE',
  'CODELAB_PROFILE',
  'CODELAB_LOG_LEVEL',
  'CODELAB_LOG_FILE',
  'CODELAB_TOOLS',
  'CODELAB_MAX_STEPS',
  'CODELAB_DEBUG_SECRETS',
  'CODELAB_DEBUG_LLM_SNAPSHOT',
  'CODELAB_AGENT_TOKEN',
  'CODELAB_POWER_HELPER',
  if (bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS'))
    'CODELAB_TEST_SECRET_STORE',
};

/// Семейства переменных, известные целиком (§15.6).
const _knownFamilies = [
  'CODELAB_SECRET_',
  'CODELAB_PROVIDER_',
  'CODELAB_REDACTED_',
];

/// Предупреждения `config.env.unknown` о неизвестных `CODELAB_*`
/// (design.md change `add-agent-configuration`, D13, D16).
///
/// Почему здесь, а не в разборе флагов `serve`: правило должно быть одно для
/// `serve`, `codelab-agent config check` и `codelab config check`, иначе
/// `check` промолчит об опечатке, которую `serve` покажет в логе.
///
/// Как использовать: [extraKnown] — имена, которые хост назвал сам
/// (переменная токена `--token-env`). Имена идут по алфавиту; значение
/// переменной не читается и в текст не попадает (она может быть секретом,
/// CFG-2) — только имя.
List<ConfigIssue> unknownEnvironmentWarnings(
  Map<String, String> environment, {
  Set<String> extraKnown = const {},
}) => [
  for (final name in environment.keys.toList()..sort())
    if (name.startsWith('CODELAB_') &&
        !_knownVariables.contains(name) &&
        !extraKnown.contains(name) &&
        !_knownFamilies.any(name.startsWith))
      ConfigIssue(
        kind: ConfigIssueKind.semantic,
        key: '',
        source: 'env',
        message: 'unknown environment variable $name',
        event: 'config.env.unknown',
        fields: {'name': name},
      ),
];
