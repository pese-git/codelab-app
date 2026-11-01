import 'dart:io';
import 'dart:math';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show Implementation;
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:http/http.dart' as http;

import '../cli/serve_args.dart';
import 'llm_script.dart';
import 'serve_config.dart';

/// Версия бинаря в `agentInfo` ответа `initialize`.
const agentVersion = '0.1.0';

/// Хост ядра в бинаре `codelab-agent`: собранное ядро и конфиг ACP-сервера.
///
/// Почему: хост решает, откуда модель (провайдеры конфигурации или сценарий),
/// где журнал (`JsonlSessionStore` или память; у сценария — память или
/// каталог `--sessions-dir`) и что умеет транспорт
/// (листинг только по stdio), а ядро собирается только через
/// `buildAgentCore` (HOST-6; design.md change `add-codelab-agent-binary`, D3).
///
/// Для чего: одно ядро на процесс; `serve --stdio` и `serve --ws` создают на
/// нём сервер [createServer] и обслуживают им соединения. Настройки ядра
/// приходят из результата `ConfigLoader` (файлы, переменные, флаги): каталог
/// моделей, маршрут провайдеров, журнал сессий, сужение профиля и MCP-серверы
/// конфигурации (design.md change `add-agent-configuration`, D4, D10, D11).
///
/// Как использовать: `await AgentHost.build(options, logger: …, loaded: …)` —
/// [loaded] обязателен: это результат `loadServeConfig(options, cwd: …)`, и
/// хост не выбирает каталог проекта сам (тесты не должны читать `.codelab/`
/// рабочего каталога).
/// Невалидный сценарий даёт [UsageError], невалидный конфиг —
/// `ConfigException`; затем [createServer] и `server.serve(transport)`; в
/// конце — [shutdown]. [httpClient] — шов тестов (`MockClient`); без него
/// создаётся один `http.Client` на процесс (PKG-6).
final class AgentHost {
  AgentHost._({
    required this.core,
    required this.serverConfig,
    required Logger logger,
    required Clock clock,
    required http.Client httpClient,
  }) : _logger = logger,
       _clock = clock,
       _httpClient = httpClient;

  final BuiltAgentCore core;
  final AcpServerConfig serverConfig;
  final Logger _logger;
  final Clock _clock;
  final http.Client _httpClient;
  final _servers = <AcpAgentServer>[];

  static Future<AgentHost> build(
    ServeOptions options, {
    required Logger logger,
    required ConfigLoadResult loaded,
    Clock clock = const SystemClock(),
    http.Client? httpClient,
  }) async {
    // Невалидный конфиг — `ConfigException` со всеми проблемами; значения
    // секретов в них нет (CFG-2).
    final loadedConfig = loaded;
    final config = loadedConfig.orThrow();
    final settings = loadedConfig.host!;
    logStartupWarnings(logger, loadedConfig);

    final stdio = options.transport == ServeTransport.stdio;
    final narrowing = <HostCapability, CapabilityState>{
      // По WebSocket клиент может быть на другой машине: локальный листинг
      // показал бы не его файлы (§10.4).
      if (!stdio)
        HostCapability.fileListing: const CapabilityOff(
          'WebSocket: клиент может быть не на этой машине',
        ),
      // По WebSocket клиент может быть на другой машине, а описание stdio-
      // сервера пришло бы из сети: запускать по нему процессы на машине
      // агента нельзя (решение по ревью PR #158). Профиль выключает `mcp`
      // целиком, поэтому `initialize` не обещает и `http`. По stdio клиент —
      // локальный хозяин процесса: профиль `agent-serve` оставляет `stdio` и
      // `http`, и `initialize` объявляет `mcpCapabilities.http: true`
      // (задача 9.6, change `add-agent-mcp-client`, D3). Серверы конфигурации
      // пропускаются так же, как серверы клиента (D10): держатель токена
      // WebSocket не должен запускать процессы и со стороны конфига.
      if (!stdio)
        HostCapability.mcp: const CapabilityOff(
          'stdio MCP servers are disabled over WebSocket',
        ),
    };

    final ModelCatalog catalog;
    final StreamFunction streamFunction;
    final SessionStore sessions;
    // Один резолвер на процесс: им пользуются функция модели (ключ и заголовки
    // провайдеров, при первом запросе) и ядро (MCP-серверы конфигурации, перед
    // подключением; D4). Хранилище выбирает `openHostSecrets` по
    // `secrets.backend` загруженного конфига (D11, D15). Сценарий `--llm-script`
    // всегда использует `env` независимо от конфига: он не читает
    // `$CODELAB_HOME`, а тесты не должны открывать `secrets.yaml`
    // разработчика; секреты сценария задаются `CODELAB_SECRET_<…>` (D11).
    final SecretResolver secrets;
    try {
      secrets = openHostSecrets(
        codelabHome: options.codelabHome,
        environment: options.environment,
        backend: options.llmScript != null ? 'env' : settings.secretsBackend,
        debug: options.debugSecrets,
        logger: logger,
        selectionReason: options.llmScript != null
            ? 'forced by --llm-script'
            : null,
      );
    } on SecretStoreUnavailableException catch (error) {
      // Недопустимый `secrets.backend` загрузка конфига уже отвергла; сюда
      // попадает только расхождение платформы (защита в глубину, D7): код `64`
      // до старта транспорта.
      throw UsageError('secrets.backend: ${error.reason}');
    }
    // Клиент создаётся после хранилища секретов: ошибка выше (код `64`) не должна
    // оставлять открытый сокетный клиент.
    // HTTP-клиент хоста: один на процесс, им пользуются провайдеры LLM и
    // streamable HTTP MCP-серверов; закрывается в `shutdown` (PKG-6).
    final client = httpClient ?? http.Client();
    if (options.llmScript case final path?) {
      // Сценарий не трогает `$CODELAB_HOME`: журнал на диске — только в
      // каталоге `--sessions-dir` (D1 change `add-llm-script-session-store`),
      // а `sessions.dir` и `sessions.fsync` конфигурации к сценарию не
      // применяются (о заданном ключе хост сообщает ниже).
      for (final key in [
        if (settings.sessionsDir != null) 'sessions.dir',
        if (settings.fsync != null) 'sessions.fsync',
      ]) {
        // Со сценарием читается только файл `--config` / `CODELAB_CONFIG`,
        // поэтому он и есть источник ключа.
        logger.log(
          LogLevel.warning,
          'config.key.not_applied',
          fields: {
            'key': key,
            'source':
                options.configPath ?? options.environment['CODELAB_CONFIG'],
          },
        );
      }
      final store = CwdTrackingStore(switch (options.sessionsDir) {
        final root? => JsonlSessionStore(
          root: root,
          clock: clock,
          logger: logger,
        ),
        null => MemorySessionStore(),
      });
      final script = LlmScript.load(
        path,
        models: options.models,
        clock: clock,
        cwdOf: store.cwdOf,
      );
      catalog = FixedModelCatalog(script.models);
      streamFunction = script.function.call;
      sessions = store;
      // `buildAgentCore` не видит память под обёрткой, поэтому capability
      // сужает хост (D2).
      if (options.sessionsDir == null) {
        narrowing[HostCapability.sessionPersistence] = const CapabilityOff(
          '--llm-script: сессии в памяти',
        );
      }
    } else {
      // Каталог — модели всех провайдеров конфигурации, запрос уходит
      // провайдеру выбранной модели (D11).
      catalog = StaticModelCatalog(config.providers, logger: logger);
      streamFunction = createRoutedStreamFunction(
        [for (final provider in config.providers) provider.config],
        CoreLlmServices(
          httpClient: client,
          clock: clock,
          random: Random.secure(),
          logger: logger,
        ),
        unavailable: config.providerProblems,
        keys: {
          for (final provider in config.providers)
            provider.config.name: ?provider.key,
        },
        headerTemplates: {
          for (final provider in config.providers)
            if (provider.headerTemplates.isNotEmpty)
              provider.config.name: provider.headerTemplates,
        },
        secrets: secrets,
      );
      sessions = JsonlSessionStore(
        root: settings.sessionsDir ?? '${options.codelabHome}/sessions',
        fsync: switch (settings.fsync) {
          final String name => FsyncPolicy.values.byName(name),
          null => FsyncPolicy.checkpoints,
        },
        clock: clock,
        logger: logger,
      );
    }
    logger.log(
      LogLevel.info,
      'host.config.loaded',
      fields: {
        'sources': loadedConfig.sources,
        'warnings': loadedConfig.warnings.length,
        'project_root': config.projectRoot,
        'transport': options.transport.name,
        'models': [for (final m in catalog.models) m.id.value],
      },
    );

    // Сужение из `profile.agent-serve.*` применяется первым, сужение
    // транспорта — вторым: повторное сужение допустимо, расширить профиль
    // нельзя (HOST-2).
    // Один локальный env хоста: и базовое окружение инструментов, и чтение
    // файлов проекта идут через один и тот же экземпляр.
    final localEnv = LocalExecutionEnv(cwd: Directory.current.path);
    // По WebSocket клиент сам выбирает `cwd`, а читать пришлось бы с ФС
    // машины агента: чужой каталог попал бы в промпт (change
    // `add-agent-project-files`, D2). Файлы проекта и `$CODELAB_HOME/AGENTS.md`
    // не читаются; пропуск пишется один раз на процесс, как `mcp.server.skipped`.
    if (!stdio) {
      logger.log(
        LogLevel.info,
        'project_files.skipped',
        fields: {
          'reason': 'project files are not read over WebSocket',
          'transport': options.transport.name,
        },
      );
    }

    final profile = HostProfile.of('agent-serve')
        .narrowed(settings.profileNarrowing['agent-serve'] ?? const {})
        .narrowed(narrowing);
    final core = buildAgentCore(
      profile: profile,
      services: AgentCoreServices(
        baseEnv: localEnv,
        gate: const _ConnectionGate(),
        logger: logger,
        clock: clock,
        ids: RandomIdGenerator(Random.secure()),
        sessions: sessions,
        platform: Platform.operatingSystem,
        models: catalog,
        secrets: secrets,
        // Файлы проекта сессии: `AGENTS.md`/`CLAUDE.md` в системный промпт.
        // Читаются с локальной ФС процесса только по stdio: по WebSocket
        // загрузчик не передаётся (D2). Сценарий `--llm-script` не трогает `$CODELAB_HOME`
        // (`home: null`) и читает только контекст проекта: так прогон
        // детерминирован и не зависит от файлов разработчика (D16).
        projectFiles: stdio
            ? ProjectFilesLoader(
                home: options.llmScript == null ? options.codelabHome : null,
                local: localEnv,
              )
            : null,
        // MCP-серверы сессии: процессы stdio запускает `codelab_agent_io`,
        // streamable HTTP — `codelab_agent_mcp` на HTTP-клиенте хоста;
        // закрываются они вместе с сессией (design.md change
        // `add-agent-mcp-client`, D3, D6, D9, D10).
        mcp: McpClientConnector(
          transports: McpTransports(
            stdio: StdioMcpTransportFactory(),
            http: StreamableHttpTransportFactory(client: client, clock: clock),
          ),
          clock: clock,
        ),
      ),
      config: config,
      streamFunction: streamFunction,
    );
    return AgentHost._(
      core: core,
      serverConfig: AcpServerConfig(
        agentInfo: const Implementation(
          name: 'codelab-agent',
          title: 'CodeLab Agent',
          version: agentVersion,
        ),
        // Отсоединение отменяет ход у обоих транспортов: у stdio это конец
        // процесса, а у WebSocket ход без клиента не может исполнять `fs/*`
        // и `terminal/*`. Возобновление хода после переподключения — после
        // MVP (change `cancel-turn-on-ws-disconnect`, D1; §13.10).
        detachGrace: Duration.zero,
        localListing: stdio ? (cwd) => LocalExecutionEnv(cwd: cwd) : null,
      ),
      logger: logger,
      clock: clock,
      httpClient: client,
    );
  }

  /// Сервер на ядре хоста; у WebSocket — один на все подключения.
  AcpAgentServer createServer() {
    final server = AcpAgentServer(
      core: core,
      config: serverConfig,
      logger: _logger,
      clock: _clock,
    );
    _servers.add(server);
    return server;
  }

  /// Безопасное завершение (§13.10): ходы отменяются и ждутся не дольше
  /// [grace], соединения закрываются, общий HTTP-клиент хоста (провайдер LLM
  /// и streamable HTTP MCP-серверов) освобождается после закрытия сессий.
  Future<void> shutdown({Duration grace = const Duration(seconds: 5)}) async {
    for (final server in _servers) {
      await server.shutdown(grace: grace);
    }
    _servers.clear();
    await core.runtime.dispose();
    _httpClient.close();
  }
}

/// Gate сборки: включает `interactiveApproval`, а вопросы задаёт
/// `AcpPermissionGate` соединения каждой сессии (D6 change
/// `add-dart-agent-acp-server`).
final class _ConnectionGate implements PermissionGate {
  const _ConnectionGate();

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) => throw StateError('the ACP server asks through AcpPermissionGate');
}
