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
/// неизвестные `CODELAB_*` хост называет предупреждением `config.env.unknown`.
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
