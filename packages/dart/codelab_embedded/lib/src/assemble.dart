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
///
/// [serve] — тестовый шов (D6, D10): запускает обслуживание соединения вместо
/// `AcpAgentServer.serve`, чтобы тест отказа `serve` (D6, «Отказ агента»)
/// мог воспроизвести ошибку, которую настоящий сервер извне не вызвать. Хосты
/// его не задают.
Future<EmbeddedAgent> assembleEmbeddedAgent({
  required EmbeddedAgentConfig config,
  required EmbeddedHostServices services,
  required StreamFunction streamFunction,
  required ModelCatalog models,
  Map<HostCapability, CapabilityState> extraNarrowing = const {},
  Future<void> Function(AcpAgentServer server, AcpTransport transport)? serve,
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
    return await _assemble(core, config, services, embedded, serve);
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
  Future<void> Function(AcpAgentServer server, AcpTransport transport)? serve,
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
  agent._serve(serve ?? (server, transport) => server.serve(transport));
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

  /// Зона агента: в ней живут `serve`, обработчики сервера, ходы и `dispose`
  /// (D6). Запоминается при запуске, чтобы вызов [dispose] из зоны приложения
  /// тоже исполнялся здесь: ошибки остановки агента не должны попадать в
  /// обработчик ошибок приложения.
  late final Zone _zone;

  /// Агент остановлен отказом (fail-stop), а не по закрытию клиентом.
  var _failed = false;

  /// Запускает `serve` в охраняемой зоне `runZonedGuarded` (D6, «Отказ
  /// агента»).
  ///
  /// Почему зона: ядро в процессе клиента, и необработанная асинхронная
  /// ошибка в нём дошла бы до `PlatformDispatcher.onError` приложения, где
  /// сломанный агент остался бы жить. Зона превращает её в fail-stop, как
  /// смерть процесса stdio-агента: клиент видит `disconnected` и показывает
  /// `ConnectionLost`. Остаточный риск — синхронный бесконечный цикл зона не
  /// прервёт (Risks, замер 7.8).
  ///
  /// `serve` завершается, когда клиент закрыл свой конец (агент не живёт дольше
  /// соединения) — тогда идёт обычный [dispose]. Завершение `serve` ошибкой —
  /// тот же отказ, что и ошибка зоны.
  void _serve(
    Future<void> Function(AcpAgentServer server, AcpTransport transport) serve,
  ) {
    runZonedGuarded(() {
      _zone = Zone.current;
      unawaited(
        serve(_server, _link.agent).then((_) => dispose(), onError: _fail),
      );
    }, (error, stack) => _fail(error));
  }

  /// Отказ агента: событие, закрытие агентского конца, `dispose` (D6).
  ///
  /// В событие идёт только класс ошибки: текст мог бы содержать ответ
  /// провайдера, путь или фрагмент файла (§16, CFG-2). Повторная ошибка зоны
  /// после начала остановки — не новый отказ, а запись `late_error`: агент уже
  /// останавливается, но ошибка не должна пропасть бесследно.
  void _fail(Object error) {
    final errorClass = '${error.runtimeType}';
    if (_failed || _disposing != null) {
      _services.logger.log(
        LogLevel.warning,
        'embedded.agent.late_error',
        fields: {'error_class': errorClass},
      );
      return;
    }
    _failed = true;
    _services.logger.log(
      LogLevel.error,
      'embedded.agent.failed',
      fields: {'error_class': errorClass},
    );
    unawaited(_failStop());
  }

  /// Сначала закрывается агентский конец: клиент немедленно получает
  /// `failed`/`disconnected` и не ждёт остановки ядра; затем обычный
  /// [dispose] (его шаг закрытия конца повторно безвреден).
  Future<void> _failStop() async {
    await _step('link', () => _link.agent.close());
    await dispose();
  }

  @override
  Future<void> dispose() => _disposing ??= _zone.run<Future<void>>(_dispose);

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
        LogLevel.error,
        'embedded.agent.dispose_failed',
        fields: {'step': name, 'error_class': '${error.runtimeType}'},
      );
    }
  }
}

/// Освобождает ядро и HTTP-клиент владельца при сбое сборки; ошибки шагов
/// не заменяют исходную, в журнал идут шаг и класс ошибки (как в `_Agent._step`).
Future<void> _releaseCore(
  BuiltAgentCore core,
  EmbeddedHostServices services,
) async {
  void failed(String step, Object error) => services.logger.log(
    LogLevel.error,
    'embedded.agent.dispose_failed',
    fields: {'step': step, 'error_class': '${error.runtimeType}'},
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
