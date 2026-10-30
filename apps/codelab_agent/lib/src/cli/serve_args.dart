import 'package:args/args.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show ConfigUsageException, checkConfigFileName, codelabHomeOf;

/// Транспорт команды `serve`.
enum ServeTransport { stdio, ws }

/// Провайдер из флага `--provider` (документ ядра §15.6).
enum ProviderKind {
  openaiCompatible('openai-compatible'),
  anthropic('anthropic');

  const ProviderKind(this.flag);

  /// Значение флага.
  final String flag;
}

/// Ошибка использования: неверные флаги или переменные окружения.
///
/// Почему отдельный тип: такой запуск не стартует сервер и завершается кодом
/// `64` с текстом в stderr (документ ядра §13.10), а не трассой исключения.
/// Текст никогда не содержит значения ключа провайдера.
final class UsageError implements Exception {
  const UsageError(this.message);

  final String message;

  @override
  String toString() => 'UsageError: $message';
}

/// Опции запуска `codelab-agent serve` после разбора флагов.
///
/// Почему: флаги и переменные этапа 4 больше не «весь конфиг» бинаря. С
/// этапа 8 (change `add-agent-configuration`, D4) конфигурацию собирает
/// `ConfigLoader` из файлов, переменных `CODELAB_*` и флагов, а здесь
/// остаётся то, что относится к запуску: транспорт, адрес WebSocket, путь
/// `--config`, сценарий `--llm-script` и слой флагов [flags].
///
/// Для чего: вход загрузки конфига (`loadServeConfig`) и сборки хоста
/// (`AgentHost.build`). Провайдер, адрес, режим, лимит шагов и ключ в полях
/// не хранятся: они целиком в слое [flags] (ключ — в [environment], слой
/// называет только переменную), а настройки ядру и хосту даёт результат
/// загрузки конфига. [logLevel], [logFile] и [models] нужны, пока конфиг не
/// загружен (лог при невалидном конфиге, модели сценария).
///
/// Как использовать: `parseServeArgs(args, environment: Platform.environment)`;
/// ошибка — [UsageError]. [environment] — все переменные процесса; в
/// [toString] их значений нет.
final class ServeOptions {
  const ServeOptions._({
    required this.transport,
    required this.host,
    required this.port,
    required this.tokenEnv,
    required this.models,
    required this.llmScript,
    required this.sessionsDir,
    required this.logLevel,
    required this.logFile,
    required this.codelabHome,
    required this.warnings,
    required this.configPath,
    required this.flags,
    required this.environment,
  });

  final ServeTransport transport;

  /// Адрес и порт `--ws`; по умолчанию `127.0.0.1:8765`.
  final String host;
  final int port;

  /// Имя переменной с токеном WebSocket.
  final String tokenEnv;

  /// Модели каталога: `cli/<id>` у провайдера, `scripted/<id>` у сценария;
  /// первая — модель по умолчанию. Пусто только у сценария: тогда модель —
  /// из `llm.model` файла.
  final List<ModelId> models;

  /// Путь к сценарию модели (только тесты, в справке скрыт).
  final String? llmScript;

  /// Корень журнала сессий сценария из `--sessions-dir` (только тесты, в
  /// справке скрыт). Почему отдельный флаг: со сценарием `$CODELAB_HOME` не
  /// трогается, а e2e клиентов нужны сессии, пережившие перезапуск процесса
  /// (D1 change `add-llm-script-session-store`). `null` — сессии в памяти.
  final String? sessionsDir;

  final LogLevel logLevel;

  /// Файл лога из `--log-file` или `CODELAB_LOG_FILE`; `null` — только stderr.
  final String? logFile;

  /// Корень состояния (`CODELAB_HOME`, по умолчанию `~/.codelab`).
  final String codelabHome;

  /// Предупреждения разбора (неизвестные `CODELAB_*`) для лога.
  final List<String> warnings;

  /// `--config <path>`: дополнительный файл конфигурации (слой 4а); `null` —
  /// флага нет (тогда действует `CODELAB_CONFIG`).
  final String? configPath;

  /// Слой флагов для `ConfigLoader`: провайдер `cli`, модель, режим, лимит
  /// шагов и логи из флагов (§15.6). Секретов в нём нет: ключ провайдера
  /// назван переменной `api_key_env`.
  final ConfigTree flags;

  /// Переменные процесса: из них загрузчик берёт `CODELAB_HOME`,
  /// `CODELAB_CONFIG`, слой окружения и значения `${ENV}`. Содержат секреты,
  /// поэтому в [toString] не попадают.
  final Map<String, String> environment;

  @override
  String toString() =>
      'ServeOptions(transport: ${transport.name}, '
      'models: ${models.map((m) => m.value).join(',')}, '
      'logLevel: ${logLevel.name}, logFile: $logFile, '
      'config: $configPath)';
}

const _cli = 'cli';
const _scripted = 'scripted';

/// Переменные `CODELAB_*`, которые знает ядро и его хосты (§15.6); другие
/// дают предупреждение — опечатка не должна молча игнорироваться.
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
  'CODELAB_TEST_SECRET_STORE',
};

/// Семейства переменных, известные целиком (§15.6).
const _knownFamilies = [
  'CODELAB_SECRET_',
  'CODELAB_PROVIDER_',
  'CODELAB_REDACTED_',
];

final ArgParser _serveParser = ArgParser()
  ..addFlag(
    'stdio',
    negatable: false,
    help: 'Serve one client over stdin/stdout.',
  )
  ..addFlag('ws', negatable: false, help: 'Serve clients over WebSocket.')
  ..addOption('host', defaultsTo: '127.0.0.1', help: 'WebSocket address.')
  ..addOption('port', defaultsTo: '8765', help: 'WebSocket port.')
  ..addOption(
    'token-env',
    defaultsTo: 'CODELAB_AGENT_TOKEN',
    help: 'Variable with the Bearer token for WebSocket clients.',
  )
  ..addOption(
    'provider',
    allowed: [for (final kind in ProviderKind.values) kind.flag],
    help: 'LLM provider; the key comes from CODELAB_API_KEY.',
  )
  ..addOption(
    'base-url',
    help: 'Provider endpoint (required for openai-compatible).',
  )
  ..addMultiOption(
    'model',
    splitCommas: false,
    help:
        'Model id; repeat for more models, the first is the default '
        '(CODELAB_MODEL). Without --provider: <provider>/<model> from the '
        'config.',
  )
  ..addOption(
    'permission-mode',
    help:
        'plan, ask, standard, accept-edits, bypass or autopilot '
        '(CODELAB_PERMISSION_MODE).',
  )
  ..addOption(
    'log-level',
    help: 'trace, debug, info, warning or error, any case (CODELAB_LOG_LEVEL).',
  )
  ..addOption('log-file', help: 'JSON Lines log file (CODELAB_LOG_FILE).')
  ..addOption(
    'config',
    help: 'Extra config.yaml, above config.local.yaml (CODELAB_CONFIG).',
  )
  ..addOption(
    'max-steps',
    help: 'Model steps per turn, a positive integer (CODELAB_MAX_STEPS).',
  )
  // Только тесты: сценарий модели вместо провайдера (§15.6, §14.7).
  ..addOption('llm-script', hide: true)
  // Только тесты: журнал сессий сценария на диске (D1 change
  // `add-llm-script-session-store`).
  ..addOption('sessions-dir', hide: true);

final ArgParser _parser = ArgParser()..addCommand('serve', _serveParser);

/// Текст справки `codelab-agent`; `--llm-script` и `--sessions-dir` в нём
/// нет.
String serveUsage() =>
    'Usage: codelab-agent serve (--stdio | --ws) [options]\n\n'
    '${_serveParser.usage}';

/// Разбирает [args] и [environment] по правилам §15.6: флаг сильнее
/// переменной, `--model` повторяется, `--stdio` и `--ws`, `--provider` и
/// `--llm-script` взаимоисключающие, `--sessions-dir` — только со сценарием.
/// Ошибка — [UsageError].
ServeOptions parseServeArgs(
  List<String> args, {
  required Map<String, String> environment,
}) {
  final ArgResults top;
  try {
    top = _parser.parse(args);
  } on ArgParserException catch (error) {
    throw UsageError(error.message);
  }
  final serve = top.command;
  if (serve == null || serve.name != 'serve') {
    throw const UsageError('missing command: codelab-agent serve');
  }
  if (serve.rest.isNotEmpty) {
    throw UsageError('unexpected arguments: ${serve.rest.join(' ')}');
  }

  final stdio = serve.flag('stdio');
  final ws = serve.flag('ws');
  if (stdio == ws) {
    throw const UsageError('pass exactly one of --stdio or --ws');
  }

  final port = int.tryParse(serve.option('port')!);
  if (port == null || port < 0 || port > 65535) {
    throw UsageError(
      '--port must be a number 0..65535: ${serve.option('port')}',
    );
  }

  final llmScript = serve.option('llm-script');
  final provider = switch (serve.option('provider')) {
    null => null,
    final flag => ProviderKind.values.firstWhere((k) => k.flag == flag),
  };
  if (provider != null && llmScript != null) {
    throw const UsageError(
      '--provider and --llm-script are mutually exclusive',
    );
  }
  final sessionsDir = serve.option('sessions-dir');
  // Корень журнала провайдера задаёт `sessions.dir` конфигурации
  // (по умолчанию `$CODELAB_HOME/sessions`); флаг нужен только сценарию,
  // у которого конфиг-слои 2–4 не читаются (D1 change
  // `add-llm-script-session-store`).
  if (sessionsDir != null && llmScript == null) {
    throw const UsageError('--sessions-dir requires --llm-script');
  }
  final rawModels = serve.multiOption('model');
  final envModel = _nonEmpty(environment['CODELAB_MODEL']);
  final List<ModelId> models;
  if (provider != null || llmScript != null) {
    // Провайдер запуска: `--model` — id модели этого провайдера (`cli` или
    // `scripted`); `CODELAB_MODEL` подменяет отсутствующий флаг (§15.6).
    final modelValues = rawModels.isNotEmpty ? rawModels : [?envModel];
    final providerId = provider == null ? _scripted : _cli;
    models = [for (final value in modelValues) _modelId(value, providerId)];
    if (provider != null && models.isEmpty) {
      throw const UsageError('--provider needs --model (or CODELAB_MODEL)');
    }
  } else {
    // Без провайдера запуска модель выбирает конфиг (D4): `--model` называет
    // `<провайдер>/<модель>` из `providers`, а `CODELAB_MODEL` попадает в
    // слой окружения загрузчика, не сюда.
    if (rawModels.length > 1) {
      throw const UsageError(
        '--model can be repeated only together with --provider',
      );
    }
    models = [for (final value in rawModels) _configModelId(value)];
  }

  Uri? baseUrl;
  if (provider != null) {
    final raw = serve.option('base-url');
    baseUrl = switch ((provider, raw)) {
      (_, final String url) => Uri.tryParse(url),
      // §15.4: у anthropic есть адрес по умолчанию.
      (ProviderKind.anthropic, null) => Uri.parse('https://api.anthropic.com'),
      (ProviderKind.openaiCompatible, null) => throw const UsageError(
        '--provider openai-compatible needs --base-url',
      ),
    };
    if (baseUrl == null || !baseUrl.hasScheme) {
      throw UsageError('--base-url must be an absolute URL: $raw');
    }
  }

  // Имя режима проверяется здесь, чтобы опечатка дала код `64` до загрузки
  // файлов; сам режим уходит в слой флагов строкой.
  _checkMode(
    serve.option('permission-mode'),
    environment['CODELAB_PERMISSION_MODE'],
  );

  final levelName =
      serve.option('log-level') ?? environment['CODELAB_LOG_LEVEL'] ?? 'info';
  // Регистр не важен: профиль codelab-app по умолчанию передаёт
  // `CODELAB_LOG_LEVEL=DEBUG` (так понимал Python-агент).
  final normalizedLevel = levelName.toLowerCase();
  final logLevel =
      LogLevel.values.where((l) => l.name == normalizedLevel).firstOrNull ??
      (throw UsageError('unknown log level: $levelName'));

  final home = codelabHomeOf(environment);

  final configPath = serve.option('config');
  if (configPath != null) {
    try {
      checkConfigFileName(configPath, origin: '--config');
    } on ConfigUsageException catch (error) {
      throw UsageError(error.message);
    }
  }
  final maxStepsText = serve.option('max-steps');
  int? maxSteps;
  if (maxStepsText != null) {
    maxSteps = int.tryParse(maxStepsText);
    if (maxSteps == null || maxSteps < 1) {
      throw UsageError('--max-steps must be a positive integer: $maxStepsText');
    }
  }

  final flags = _flagsLayer(
    provider: provider,
    scripted: llmScript != null,
    baseUrl: baseUrl,
    apiKeyEnv: _nonEmpty(environment['CODELAB_API_KEY']) != null,
    models: models,
    permissionMode: serve.option('permission-mode'),
    maxSteps: maxSteps,
    logLevel: serve.option('log-level')?.toLowerCase(),
    logFile: serve.option('log-file'),
  );

  return ServeOptions._(
    transport: stdio ? ServeTransport.stdio : ServeTransport.ws,
    host: serve.option('host')!,
    port: port,
    tokenEnv: serve.option('token-env')!,
    models: models,
    llmScript: llmScript,
    sessionsDir: sessionsDir,
    logLevel: logLevel,
    logFile:
        serve.option('log-file') ?? _nonEmpty(environment['CODELAB_LOG_FILE']),
    codelabHome: home,
    configPath: configPath,
    flags: flags,
    environment: Map.unmodifiable(environment),
    warnings: [
      for (final name in environment.keys.toList()..sort())
        if (name.startsWith('CODELAB_') &&
            !_knownVariables.contains(name) &&
            !_knownFamilies.any(name.startsWith) &&
            name != serve.option('token-env'))
          'unknown environment variable $name',
    ],
  );
}

/// `<id>` или `<провайдер>/<id>` с провайдером этого запуска: у `--provider`
/// это `cli`, у `--llm-script` — `scripted`. Другие провайдеры живут в
/// конфиге и выбираются без `--provider` (D4).
ModelId _modelId(String value, String provider) {
  final slash = value.indexOf('/');
  if (slash < 0) {
    return ModelId('$provider/$value');
  }
  if (value.substring(0, slash) == provider && slash < value.length - 1) {
    return ModelId(value);
  }
  throw UsageError(
    '--model $value: with ${provider == _cli ? '--provider' : '--llm-script'} '
    'the model is <id> or $provider/<id>; to choose a provider from the '
    'config, drop the flag that fixes the provider',
  );
}

/// `--model <provider>/<model>` без `--provider` (D4).
ModelId _configModelId(String value) {
  final slash = value.indexOf('/');
  if (slash <= 0 || slash == value.length - 1) {
    throw const UsageError(
      '--model needs <provider>/<model> without --provider',
    );
  }
  return ModelId(value);
}

/// Слой флагов (`ConfigLayerKind.flags`, §15.6): только то, что запуск
/// назвал явно. Переменные окружения сюда не входят — их слой строит
/// загрузчик, и приоритет «флаг сильнее переменной» обеспечивает порядок
/// слоёв. Ключ провайдера в слой не попадает: `api_key_env` называет
/// переменную `CODELAB_API_KEY` (CFG-2).
ConfigTree _flagsLayer({
  required ProviderKind? provider,
  required bool scripted,
  required Uri? baseUrl,
  required bool apiKeyEnv,
  required List<ModelId> models,
  required String? permissionMode,
  required int? maxSteps,
  required String? logLevel,
  required String? logFile,
}) {
  final values = <String, Object?>{};
  if (provider != null) {
    values['providers'] = {
      _cli: {
        'kind': provider.flag,
        'base_url': baseUrl.toString(),
        // Только при непустой переменной: иначе ключ «не найден» и ход
        // упал бы, хотя локальному серверу ключ не нужен.
        if (apiKeyEnv) 'api_key_env': 'CODELAB_API_KEY',
        'models': {for (final id in models) id.model: <String, Object?>{}},
      },
    };
  }
  // Модели сценария (`--model scripted/<id>`) принадлежат сценарию, не
  // конфигу: слой для них дополняет `loadServeConfig`.
  if (models.isNotEmpty && (provider != null || !scripted)) {
    values['agent'] = {'default_model': models.first.value};
  }
  if (permissionMode != null) {
    values['permissions'] = {'mode': permissionMode};
  }
  if (maxSteps != null) {
    values['budget'] = {'max_steps': maxSteps};
  }
  final logging = <String, Object?>{'level': ?logLevel, 'file': ?logFile};
  if (logging.isNotEmpty) {
    values['logging'] = logging;
  }
  return ConfigTree(
    kind: ConfigLayerKind.flags,
    source: 'flags',
    values: values,
  );
}

/// Проверяет имя режима; `autopilot` допустим только флагом (CFG-4).
void _checkMode(String? flag, String? variable) {
  if (flag == 'autopilot') {
    return;
  }
  final value = flag ?? _nonEmpty(variable);
  if (value != null && !ModeId.values.any((m) => m.value == value)) {
    throw UsageError('unknown permission mode: $value');
  }
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
