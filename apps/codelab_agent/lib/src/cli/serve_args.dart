import 'package:args/args.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

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

/// Опции запуска `codelab-agent serve` после разбора флагов и переменных.
///
/// Почему: до этапа 8 файлов конфига нет, и весь конфиг бинаря — флаги и
/// переменные окружения §15.6 (design.md change `add-codelab-agent-binary`,
/// D4). Этот тип — их единственное разобранное представление.
///
/// Для чего: вход сборки хоста (`AgentHost.build`) и выбора транспорта.
///
/// Как использовать: `parseServeArgs(args, environment: Platform.environment)`;
/// ошибка — [UsageError]. [apiKey] — значение `CODELAB_API_KEY`; в
/// [toString] его нет.
final class ServeOptions {
  const ServeOptions._({
    required this.transport,
    required this.host,
    required this.port,
    required this.tokenEnv,
    required this.provider,
    required this.baseUrl,
    required this.models,
    required this.apiKey,
    required this.llmScript,
    required this.sessionsDir,
    required this.mode,
    required this.autopilot,
    required this.logLevel,
    required this.logFile,
    required this.codelabHome,
    required this.warnings,
  });

  final ServeTransport transport;

  /// Адрес и порт `--ws`; по умолчанию `127.0.0.1:8765`.
  final String host;
  final int port;

  /// Имя переменной с токеном WebSocket.
  final String tokenEnv;

  /// `null` — сценарий `--llm-script`.
  final ProviderKind? provider;
  final Uri? baseUrl;

  /// Модели каталога: `cli/<id>` у провайдера, `scripted/<id>` у сценария;
  /// первая — модель по умолчанию. Пусто только у сценария: тогда модель —
  /// из `llm.model` файла.
  final List<ModelId> models;

  /// Значение `CODELAB_API_KEY`; не печатается.
  final String? apiKey;

  /// Путь к сценарию модели (только тесты, в справке скрыт).
  final String? llmScript;

  /// Корень журнала сессий сценария из `--sessions-dir` (только тесты, в
  /// справке скрыт). Почему отдельный флаг: со сценарием `$CODELAB_HOME` не
  /// трогается, а e2e клиентов нужны сессии, пережившие перезапуск процесса
  /// (D1 change `add-llm-script-session-store`). `null` — сессии в памяти.
  final String? sessionsDir;

  /// Режим сессий по умолчанию; `null` — режим профиля.
  final ModeId? mode;

  /// `--permission-mode autopilot` — переопределение режима только флагом.
  final bool autopilot;

  final LogLevel logLevel;

  /// Файл лога из `--log-file` или `CODELAB_LOG_FILE`; `null` — только stderr.
  final String? logFile;

  /// Корень состояния (`CODELAB_HOME`, по умолчанию `~/.codelab`).
  final String codelabHome;

  /// Предупреждения разбора (неизвестные `CODELAB_*`) для лога.
  final List<String> warnings;

  @override
  String toString() =>
      'ServeOptions(transport: ${transport.name}, '
      'provider: ${provider?.flag ?? 'scripted'}, baseUrl: $baseUrl, '
      'models: ${models.map((m) => m.value).join(',')}, '
      'apiKey: ${apiKey == null ? 'unset' : 'set'}, mode: '
      '${autopilot ? 'autopilot' : mode?.value ?? 'default'}, '
      'logLevel: ${logLevel.name}, logFile: $logFile)';
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
        '(CODELAB_MODEL).',
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
  // У провайдера журнал уже в `$CODELAB_HOME/sessions`; второй способ задать
  // корень до конфига этапа 8 не нужен (D1).
  if (sessionsDir != null && llmScript == null) {
    throw const UsageError('--sessions-dir requires --llm-script');
  }
  if (provider == null && llmScript == null) {
    throw const UsageError(
      'no model source: pass --provider with --model, or --llm-script '
      '(config files are read from stage 8)',
    );
  }

  final rawModels = serve.multiOption('model');
  final modelValues = rawModels.isNotEmpty
      ? rawModels
      : [?_nonEmpty(environment['CODELAB_MODEL'])];
  final providerId = provider == null ? _scripted : _cli;
  final models = [for (final value in modelValues) _modelId(value, providerId)];
  if (provider != null && models.isEmpty) {
    throw const UsageError('--provider needs --model (or CODELAB_MODEL)');
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

  final (mode, autopilot) = _mode(
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

  final home =
      _nonEmpty(environment['CODELAB_HOME']) ??
      '${environment['HOME'] ?? environment['USERPROFILE'] ?? '.'}/.codelab';

  return ServeOptions._(
    transport: stdio ? ServeTransport.stdio : ServeTransport.ws,
    host: serve.option('host')!,
    port: port,
    tokenEnv: serve.option('token-env')!,
    provider: provider,
    baseUrl: baseUrl,
    models: models,
    apiKey: _nonEmpty(environment['CODELAB_API_KEY']),
    llmScript: llmScript,
    sessionsDir: sessionsDir,
    mode: mode,
    autopilot: autopilot,
    logLevel: logLevel,
    logFile:
        serve.option('log-file') ?? _nonEmpty(environment['CODELAB_LOG_FILE']),
    codelabHome: home,
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

/// `<id>` или `<провайдер>/<id>` с провайдером этого запуска (D4): других
/// провайдеров до конфига этапа 8 нет.
ModelId _modelId(String value, String provider) {
  final slash = value.indexOf('/');
  if (slash < 0) {
    return ModelId('$provider/$value');
  }
  if (value.substring(0, slash) == provider && slash < value.length - 1) {
    return ModelId(value);
  }
  throw UsageError(
    '--model $value: only $provider/<model> is known in this launch; '
    'named providers come with the config of stage 8',
  );
}

(ModeId?, bool) _mode(String? flag, String? variable) {
  if (flag == 'autopilot') {
    return (null, true);
  }
  final value = flag ?? _nonEmpty(variable);
  if (value == null) {
    return (null, false);
  }
  final mode = ModeId.values.where((m) => m.value == value).firstOrNull;
  if (mode == null) {
    // autopilot — только флагом (CFG-4).
    throw UsageError('unknown permission mode: $value');
  }
  return (mode, false);
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
