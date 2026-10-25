import 'dart:io';
import 'dart:math';

import 'package:acp_protocol/acp_protocol.dart' show Implementation;
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:http/http.dart' as http;

import '../cli/serve_args.dart';
import 'llm_script.dart';

/// Версия бинаря в `agentInfo` ответа `initialize`.
const agentVersion = '0.1.0';

/// Хост ядра в бинаре `codelab-agent`: собранное ядро и конфиг ACP-сервера.
///
/// Почему: хост решает, откуда модель (провайдер из флагов или сценарий),
/// где журнал (`JsonlSessionStore` или память) и что умеет транспорт
/// (листинг только по stdio), а ядро собирается только через
/// `buildAgentCore` (HOST-6; design.md change `add-codelab-agent-binary`, D3).
///
/// Для чего: одно ядро на процесс; `serve --stdio` и `serve --ws` создают на
/// нём сервер [createServer] и обслуживают им соединения.
///
/// Как использовать: `await AgentHost.build(options, logger: …)` —
/// невалидный сценарий даёт [UsageError]; затем [createServer] и
/// `server.serve(transport)`; в конце — [shutdown].
final class AgentHost {
  AgentHost._({
    required this.core,
    required this.serverConfig,
    required Logger logger,
    required Clock clock,
    required http.Client? httpClient,
  }) : _logger = logger,
       _clock = clock,
       _httpClient = httpClient;

  final BuiltAgentCore core;
  final AcpServerConfig serverConfig;
  final Logger _logger;
  final Clock _clock;
  final http.Client? _httpClient;
  final _servers = <AcpAgentServer>[];

  static Future<AgentHost> build(
    ServeOptions options, {
    required Logger logger,
    Clock clock = const SystemClock(),
  }) async {
    for (final warning in options.warnings) {
      logger.log(
        LogLevel.warning,
        'config.env.unknown',
        fields: {'message': warning},
      );
    }
    final stdio = options.transport == ServeTransport.stdio;
    final narrowing = <HostCapability, CapabilityState>{
      // По WebSocket клиент может быть на другой машине: локальный листинг
      // показал бы не его файлы (§10.4).
      if (!stdio)
        HostCapability.fileListing: const CapabilityOff(
          'WebSocket: клиент может быть не на этой машине',
        ),
    };

    final ModelCatalog catalog;
    final StreamFunction streamFunction;
    final SessionStore sessions;
    http.Client? httpClient;
    if (options.llmScript case final path?) {
      final store = CwdTrackingStore();
      final script = LlmScript.load(
        path,
        models: options.models,
        clock: clock,
        cwdOf: store.cwdOf,
      );
      catalog = FixedModelCatalog(script.models);
      streamFunction = script.function.call;
      sessions = store;
      narrowing[HostCapability.sessionPersistence] = const CapabilityOff(
        '--llm-script: сессии в памяти',
      );
    } else {
      final provider = ProviderConfig(
        name: 'cli',
        api: options.provider == ProviderKind.anthropic
            ? ProviderApi.anthropicMessages
            : ProviderApi.openaiChat,
        baseUrl: options.baseUrl!,
        apiKey: options.apiKey,
      );
      catalog = StaticModelCatalog([
        CatalogProvider(
          provider,
          models: {
            for (final id in options.models) id.model: const ModelInfo(),
          },
        ),
      ], logger: logger);
      httpClient = http.Client();
      streamFunction = createStreamFunction(
        provider,
        CoreLlmServices(
          httpClient: httpClient,
          clock: clock,
          random: Random.secure(),
          logger: logger,
        ),
      );
      sessions = JsonlSessionStore(
        root: '${options.codelabHome}/sessions',
        clock: clock,
        logger: logger,
      );
    }
    final defaultModel = catalog.resolve(catalog.models.first.id)!;
    logger.log(
      LogLevel.info,
      'host.config',
      fields: {
        'transport': options.transport.name,
        'provider': options.provider?.flag ?? 'scripted',
        'models': [for (final m in catalog.models) m.id.value],
        // Ключ — только признак: значение в лог не попадает.
        'api_key_env': 'CODELAB_API_KEY',
        'api_key_set': options.apiKey != null,
      },
    );

    final core = buildAgentCore(
      profile: HostProfile.of('agent-serve').narrowed(narrowing),
      services: AgentCoreServices(
        baseEnv: LocalExecutionEnv(cwd: Directory.current.path),
        gate: const _ConnectionGate(),
        logger: logger,
        clock: clock,
        ids: RandomIdGenerator(Random.secure()),
        sessions: sessions,
        platform: Platform.operatingSystem,
        models: catalog,
      ),
      config: CoreConfig(
        defaultModel: defaultModel,
        permissions: PermissionsConfig(
          mode: options.mode,
          modeOverride: options.autopilot ? PermissionMode.autopilot : null,
        ),
      ),
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
        // Отсоединение stdio — конец процесса, ждать некого (§13.10).
        detachGrace: stdio ? Duration.zero : const Duration(seconds: 30),
        localListing: stdio ? (cwd) => LocalExecutionEnv(cwd: cwd) : null,
      ),
      logger: logger,
      clock: clock,
      httpClient: httpClient,
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
  /// [grace], соединения закрываются, HTTP-клиент провайдера освобождается.
  Future<void> shutdown({Duration grace = const Duration(seconds: 5)}) async {
    for (final server in _servers) {
      await server.shutdown(grace: grace);
    }
    _servers.clear();
    await core.runtime.dispose();
    _httpClient?.close();
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
