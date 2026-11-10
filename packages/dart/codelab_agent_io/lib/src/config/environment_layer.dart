import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Ключи конфигурации, у которых есть переменная окружения, и имена этих
/// переменных — единственный источник для слоя окружения
/// ([buildEnvironmentLayer]) и для вывода `config get`, который вместо
/// значения печатает `<from env:NAME>` (`cli/config_output.dart`).
///
/// Почему таблица, а не два списка: новая переменная, добавленная в слой,
/// иначе не получила бы подпись в `config get`, и её значение могло бы
/// попасть в вывод (ревью итерации 4, arch L4; R0-2). Предконфигурация
/// провайдера (`CODELAB_PROVIDER_*`) подписывается именем своего источника
/// (`env:…`) и в таблицу не входит.
const environmentLayerVariables = {
  'agent.default_model': 'CODELAB_MODEL',
  'budget.max_steps': 'CODELAB_MAX_STEPS',
  'permissions.mode': 'CODELAB_PERMISSION_MODE',
  'logging.level': 'CODELAB_LOG_LEVEL',
  'logging.file': 'CODELAB_LOG_FILE',
};

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
///
/// Предконфигурация провайдера `CODELAB_PROVIDER_*` (L-25) — отдельный слой в
/// `provider_preconfig.dart` (`preconfigLayer`): он стоит перед этим слоем,
/// чтобы `CODELAB_MODEL` переопределял модель предконфигурации (design.md
/// change `add-config-writer-and-reload`, D3).
({ConfigTree? layer, List<ConfigIssue> issues}) buildEnvironmentLayer(
  Map<String, String> environment,
) {
  // Имя переменной берётся из таблицы по ключу, а не пишется второй раз.
  String variable(String key) => environmentLayerVariables[key]!;
  String? value(String name) {
    final raw = environment[name];
    return raw == null || raw.isEmpty ? null : raw;
  }

  final values = <String, Object?>{};
  final issues = <ConfigIssue>[];

  if (value(variable('agent.default_model')) case final model?) {
    values['agent'] = {'default_model': model};
  }
  if (value(variable('budget.max_steps')) case final raw?) {
    final steps = int.tryParse(raw);
    if (steps == null) {
      issues.add(
        ConfigIssue(
          kind: ConfigIssueKind.type,
          key: 'budget.max_steps',
          source: 'env',
          message: '${variable('budget.max_steps')} must be an integer',
        ),
      );
    } else {
      values['budget'] = {'max_steps': steps};
    }
  }
  if (value(variable('permissions.mode')) case final mode?) {
    values['permissions'] = {'mode': mode};
  }
  final logging = <String, Object?>{
    // Регистр не важен: профиль `codelab-app` передаёт `DEBUG`.
    'level': ?value(variable('logging.level'))?.toLowerCase(),
    'file': ?value(variable('logging.file')),
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
///
/// `CODELAB_SERVE_ALIAS_ACTIVE` — маркер переходного алиаса `codelab serve`:
/// алиас ставит его агенту при каждом запуске, поэтому без записи здесь
/// каждый такой запуск давал бы ложное предупреждение. Агент маркер не
/// читает (change `retire-python-agent`, Q10, D7). Запись временная: снимается
/// вместе с алиасом в change `remove-python-agent` (D13).
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
  'CODELAB_SERVE_ALIAS_ACTIVE',
  if (bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS'))
    'CODELAB_TEST_SECRET_STORE',
};

/// Путь `secrets.yaml` тестового хранилища секретов из окружения (`null` —
/// обычный выбор по `secrets.backend`).
///
/// Почему здесь: правило «переменная действует только в сборке с
/// `-DCODELAB_ALLOW_TEST_SECRETS=true`» одно и то же для загрузчика
/// ([_knownVariables]) и для хоста, который выбирает хранилище. Define
/// вычисляется при компиляции, поэтому в рабочей сборке ветка вычищена, а
/// переменная даёт `config.env.unknown` (change `add-embedded-agent-mode`,
/// D5; §12.4.13).
///
/// Как использовать: открыватель хоста передаёт результат в
/// `openHostSecrets(testStorePath:)`; каталог из переменной получает имя
/// `secrets.yaml`.
String? testSecretStorePath(Map<String, String> environment) {
  if (!const bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS')) {
    return null;
  }
  final directory = environment['CODELAB_TEST_SECRET_STORE'];
  return directory == null || directory.isEmpty
      ? null
      : '$directory/secrets.yaml';
}

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
