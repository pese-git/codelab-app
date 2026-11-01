import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show Implementation;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'embedded_agent.dart';
import 'embedded_agent_config.dart';

/// Версия пакета в `agentInfo`: тот же агент, что у бинаря `codelab-agent`.
///
/// Парная константа — `agentVersion` в
/// `apps/codelab_agent/lib/src/host/agent_host.dart`; значения должны
/// совпадать. Импортировать её отсюда нельзя (пакет не зависит от приложений),
/// поэтому равенство проверит фикстура `initialize-capabilities` через
/// `test-scenario --agent embedded` (change `add-embedded-agent-mode`,
/// итерация 3).
const embeddedAgentVersion = '0.1.0';

/// Собирает ядро, ACP-сервер и пару транспортов (design.md change
/// `add-embedded-agent-mode`, D2, D4, D6).
///
/// Почему внутренняя функция, а не публичный параметр: основной барель и
/// `io.dart` НЕ принимают функцию модели и сценарий (D8), поэтому
/// [streamFunction] и [models] передают только `createEmbeddedAgent`
/// (провайдеры конфига) и `lib/src/testing/` (сценарий). В публичный барель
/// файл не экспортируется.
///
/// Как использовать: [extraNarrowing] — сужение профиля сверх
/// `profile.<hostProfile>.*` конфига (хранилище в памяти у сценария).
/// Профили `embedded-*` получают `services.localEnv` как
/// `AcpServerConfig.localEnv` — файлы и команды исполняет хост, `fs/*` и
/// `terminal/*` клиенту не уходят. Другие профили (`agent-serve` в тестах)
/// отдают `localEnv` как локальный листинг, как бинарь по stdio.
Future<EmbeddedAgent> assembleEmbeddedAgent({
  required EmbeddedAgentConfig config,
  required EmbeddedHostServices services,
  required StreamFunction streamFunction,
  required ModelCatalog models,
  Map<HostCapability, CapabilityState> extraNarrowing = const {},
}) async {
  final embedded = config.hostProfile.startsWith('embedded-');
  // HOST-6: ядро только через `buildAgentCore`. Сужение из конфига — первым,
  // сужение сборки — вторым; расширить профиль нельзя (HOST-2).
  final core = buildAgentCore(
    profile: HostProfile.of(config.hostProfile)
        .narrowed(config.host.profileNarrowing[config.hostProfile] ?? const {})
        .narrowed(extraNarrowing),
    services: AgentCoreServices(
      baseEnv: services.baseEnv,
      // Включает `interactiveApproval`; вопросы задаёт `AcpPermissionGate`
      // соединения каждой сессии (как у бинаря).
      gate: const _ConnectionGate(),
      logger: services.logger,
      clock: services.clock,
      ids: services.ids,
      sessions: services.sessions,
      platform: services.platform,
      models: models,
      secrets: services.secrets,
      mcp: services.mcp,
      projectFiles: services.projectFiles,
    ),
    config: config.core,
    streamFunction: streamFunction,
  );
  // Ядро уже собрано: любая ошибка до готовности агента (конструктор сервера,
  // например HostWiringException, или start пары) без освобождения утекла бы
  // ресурсами ядра и HTTP-клиентом, хотя вызывающий агента не получит.
  try {
    return await _assemble(core, config, services, embedded);
  } catch (_) {
    await _releaseCore(core, services);
    rethrow;
  }
}

Future<EmbeddedAgent> _assemble(
  BuiltAgentCore core,
  EmbeddedAgentConfig config,
  EmbeddedHostServices services,
  bool embedded,
) async {
  final link = InProcessAcpLink();
  final server = AcpAgentServer(
    core: core,
    logger: services.logger,
    clock: services.clock,
    config: AcpServerConfig(
      // Один агент в другом хосте: протокол режим не различает, его различает
      // лог (`host.plan`, профиль) — D4.
      agentInfo: const Implementation(
        name: 'codelab-agent',
        title: 'CodeLab Agent',
        version: embeddedAgentVersion,
      ),
      // Переподключаться к прежнему агенту некому: kit открывает нового (D4).
      detachGrace: Duration.zero,
      localEnv: embedded ? services.localEnv : null,
      localListing: embedded ? null : services.localEnv,
    ),
  );
  final agent = _Agent(
    link: link,
    server: server,
    core: core,
    services: services,
  );
  await link.agent.start();
  agent._serve();
  return agent;
}

final class _Agent implements EmbeddedAgent {
  _Agent({
    required InProcessAcpLink link,
    required AcpAgentServer server,
    required BuiltAgentCore core,
    required EmbeddedHostServices services,
  }) : _link = link,
       _server = server,
       _core = core,
       _services = services;

  final InProcessAcpLink _link;
  final AcpAgentServer _server;
  final BuiltAgentCore _core;
  final EmbeddedHostServices _services;
  final _closed = Completer<void>();
  Future<void>? _disposing;

  @override
  AcpTransport get clientTransport => _link.client;

  @override
  Future<void> get closed => _closed.future;

  /// `serve` завершается, когда клиент закрыл свой конец: агент не живёт
  /// дольше соединения (D6). Ошибка `serve` не глотается молча: в журнал идёт
  /// только тип (текст исключения может содержать данные). Полноценное
  /// `embedded.agent.failed` и охраняемая зона — задачи 2.5, 2.6.
  void _serve() {
    unawaited(
      _server
          .serve(_link.agent)
          .then(
            (_) => dispose(),
            onError: (Object error) {
              _services.logger.log(
                LogLevel.warning,
                'embedded.agent.serve_failed',
                fields: {'errorType': '${error.runtimeType}'},
              );
              return dispose();
            },
          ),
    );
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  /// Каждый шаг в своём `try`: сбой одного не должен оставить остальные
  /// ресурсы открытыми, а [closed] — незавершённым (D6). Исключение наружу не
  /// идёт, в журнал — шаг и тип ошибки без её текста.
  Future<void> _dispose() async {
    try {
      await _step(
        'shutdown',
        () => _server.shutdown(grace: const Duration(seconds: 5)),
      );
      await _step('runtime', () => _core.runtime.dispose());
      await _step('link', () => _link.agent.close());
      if (_services.closeHttpOnDispose) {
        await _step('http', () async => _services.http.close());
      }
    } finally {
      _closed.complete();
    }
  }

  Future<void> _step(String name, FutureOr<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _services.logger.log(
        LogLevel.warning,
        'embedded.agent.dispose_failed',
        fields: {'step': name, 'errorType': '${error.runtimeType}'},
      );
    }
  }
}

/// Освобождает ядро и HTTP-клиент владельца при сбое сборки; ошибки шагов
/// не заменяют исходную, в журнал идут шаг и тип (как в `_Agent._step`).
Future<void> _releaseCore(
  BuiltAgentCore core,
  EmbeddedHostServices services,
) async {
  void failed(String step, Object error) => services.logger.log(
    LogLevel.warning,
    'embedded.agent.dispose_failed',
    fields: {'step': step, 'errorType': '${error.runtimeType}'},
  );
  try {
    await core.runtime.dispose();
  } catch (error) {
    failed('runtime', error);
  }
  if (services.closeHttpOnDispose) {
    try {
      services.http.close();
    } catch (error) {
      failed('http', error);
    }
  }
}

/// Gate сборки: включает `interactiveApproval`, а вопросы задаёт
/// `AcpPermissionGate` соединения (design.md change `add-dart-agent-acp-server`,
/// D6).
final class _ConnectionGate implements PermissionGate {
  const _ConnectionGate();

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) => throw StateError('the ACP server asks through AcpPermissionGate');
}
