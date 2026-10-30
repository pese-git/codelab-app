import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';

import '../cli/serve_args.dart';
import 'llm_script.dart';

/// Загружает конфигурацию `serve`: файлы, переменные и флаги (`agent-core-
/// architecture` §15.2, §15.6; design.md change `add-agent-configuration`,
/// D4, D9).
///
/// Почему отдельная функция: загрузка нужна до сборки хоста — по её
/// результату выбираются уровень и файл лога, а невалидный конфиг должен
/// завершить процесс кодом `64` до старта транспорта. `AgentHost.build`
/// принимает готовый результат или зовёт эту же функцию.
///
/// Как использовать: `loadServeConfig(options, cwd: Directory.current.path)`;
/// [cwd] — корень проектных слоёв, обязателен: так тест не читает `.codelab/`
/// каталога, из которого его запустили, а бинарь передаёт каталог процесса
/// (тот же получает `LocalExecutionEnv`). Проблемы конфига приходят в `issues` результата, а
/// ошибка использования (`CODELAB_CONFIG=x.toml`, невалидный сценарий) —
/// [UsageError]. Со сценарием `--llm-script` слои 2–4 не читаются, а сам
/// сценарий описывается провайдером в слое флагов: модели берутся из файла,
/// и конфигу не нужны ни ключ, ни сеть (`kind: openai-compatible` с адресом
/// `scripted.invalid`, как у моделей сценария).
ConfigLoadResult loadServeConfig(
  ServeOptions options, {
  required String cwd,
  ConfigLoader? loader,
}) {
  var flags = options.flags;
  if (options.llmScript case final path?) {
    flags = _withScriptedProviders(
      flags,
      LlmScript.modelsOf(path, models: options.models),
    );
  }
  try {
    return (loader ?? ConfigLoader()).load(
      cwd: cwd,
      environment: options.environment,
      flags: flags,
      extraConfig: options.configPath,
      scripted: options.llmScript != null,
    );
  } on ConfigUsageException catch (error) {
    throw UsageError(error.message);
  }
}

/// Уровень и файл лога после загрузки конфига: флаг сильнее переменной,
/// переменная сильнее `logging.*` (agent-binary «Логи бинаря»).
///
/// Почему из результата загрузки: слои уже слиты в `HostSettings`. При
/// невалидном конфиге результата нет, и действуют только флаги и
/// переменные: проблемы конфига надо записать в тот же лог. Файл лога по
/// умолчанию не создаётся (OQ5 (а)): `file` равен `null`, пока ключ не задан.
({LogLevel level, String? file}) logSettings(
  ServeOptions options,
  ConfigLoadResult loaded,
) {
  final host = loaded.host;
  if (host == null) {
    return (level: options.logLevel, file: options.logFile);
  }
  return (level: host.logLevel ?? LogLevel.info, file: host.logFile);
}

/// Дополняет слой флагов провайдерами и моделью сценария.
///
/// Схема требует `agent.default_model` из каталога провайдеров; у сценария
/// каталог — его собственные модели, поэтому каждая становится моделью
/// провайдера с её окном контекста и лимитом ответа.
ConfigTree _withScriptedProviders(ConfigTree flags, List<ModelRef> models) {
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

/// Пишет предупреждения запуска в лог: неизвестные `CODELAB_*` и
/// предупреждения загрузки конфига.
///
/// Почему одна функция: валидный конфиг пишет их при сборке хоста, а
/// невалидный — при отчёте об ошибках, и оба пути обязаны давать одни и те же
/// события (D16). Неизвестная переменная — `config.env.unknown`; предупреждение
/// загрузки — событие со своим именем. В `message` нет значений ключей, для
/// `config.legacy_found` там ссылка на таблицу переноса (§15.7).
void logStartupWarnings(
  Logger logger,
  ServeOptions options,
  ConfigLoadResult loaded,
) {
  for (final warning in options.warnings) {
    logger.log(
      LogLevel.warning,
      'config.env.unknown',
      fields: {'message': warning},
    );
  }
  for (final warning in loaded.warnings) {
    logger.log(
      warning.level,
      warning.event ?? 'config.warning',
      fields: {...warning.fields, 'message': warning.message},
    );
  }
}
