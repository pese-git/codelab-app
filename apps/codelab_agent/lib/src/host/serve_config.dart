import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_io/testing.dart';

import '../cli/serve_args.dart';

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
    try {
      flags = withScriptedProviders(
        flags,
        LlmScript.modelsOf(path, models: options.models),
      );
    } on LlmScriptException catch (error) {
      // Сценарий разбирает `codelab_agent_io` (D8 change
      // `add-embedded-agent-mode`); для бинаря это ошибка использования.
      throw UsageError(error.message);
    }
  }
  try {
    return (loader ?? ConfigLoader()).load(
      cwd: cwd,
      environment: options.environment,
      flags: flags,
      extraConfig: options.configPath,
      scripted: options.llmScript != null,
      // Переменная токена WebSocket названа флагом — не опечатка (D13).
      knownVariables: {options.tokenEnv},
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
