import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'acp_client_env.dart';
import 'acp_permission_gate.dart';
import 'config_options.dart';
import 'connection/acp_error.dart';
import 'connection/client_requests.dart';
import 'connection/inbound_router.dart';
import 'connection/outbound_queue.dart';
import 'connection/pending_requests.dart';
import 'prompt_content.dart';
import 'session_bridge.dart';

/// Таймауты запросов агента к клиенту (§13.9).
final class AcpTimeouts {
  const AcpTimeouts({
    this.fs = const Duration(seconds: 30),
    this.terminalCreate = const Duration(seconds: 30),
    this.terminalOutput = const Duration(seconds: 30),
    this.terminalKill = const Duration(seconds: 10),
    this.terminalRelease = const Duration(seconds: 10),
  });

  final Duration fs;
  final Duration terminalCreate;
  final Duration terminalOutput;
  final Duration terminalKill;
  final Duration terminalRelease;
}

/// Настройки ACP-сервера, которые задаёт хост (§13.1).
///
/// Как использовать: бинарь по stdio передаёт [localListing] — клиент и
/// агент на одной машине, `ls` и `search` идут по локальной ФС; по
/// WebSocket его нет, и хост выключает `fileListing` при сборке ядра
/// (design.md change `add-dart-agent-acp-server`, D5).
final class AcpServerConfig {
  const AcpServerConfig({
    required this.agentInfo,
    this.detachGrace = const Duration(seconds: 30),
    this.timeouts = const AcpTimeouts(),
    this.localListing,
  });

  /// `agentInfo` ответа `initialize`.
  final acp.Implementation agentInfo;

  /// Сколько отсоединённая сессия ждёт переподключения (§13.10).
  final Duration detachGrace;
  final AcpTimeouts timeouts;

  /// Локальный env для `listDir` сессии с рабочей папкой `cwd`.
  final ExecutionEnv Function(String cwd)? localListing;
}

/// ACP-сервер Dart-агента: проекция `AgentRuntime` в ACP
/// (`agent-core-architecture` §13).
///
/// Почему отдельный пакет над ядром: ядро не знает протокола (LOOP-6), а
/// клиенты говорят только по ACP (`AGENTS.md` §5). Сервер переводит кадры
/// в вызовы `AgentRuntime` / `AgentSession`, а события ядра — в
/// `session/update`.
///
/// Как использовать: хост собирает ядро `buildAgentCore`, создаёт сервер и
/// вызывает [serve] для каждого транспорта; [serve] завершается, когда
/// соединение закрыто. [shutdown] — при выходе хоста.
final class AcpAgentServer {
  AcpAgentServer({
    required BuiltAgentCore core,
    required this.config,
    required Logger logger,
    required this.clock,
  }) : _core = core,
       _logger = logger {
    // Реестр инструментов общий на ядро, а локальный листинг — свойство
    // хоста: они должны совпадать (design.md, D5).
    if (core.plan.profile.isOn(HostCapability.fileListing) &&
        config.localListing == null) {
      throw const HostWiringException(
        'capability fileListing требует AcpServerConfig.localListing: '
        'без него ls и search некуда направить',
      );
    }
  }

  final BuiltAgentCore _core;
  final AcpServerConfig config;
  final Logger _logger;

  /// Часы хоста: таймауты запросов и окно переподключения (§13.10).
  final Clock clock;
  final _connections = <_Connection>{};

  /// Сессии всех соединений по `sessionId`.
  final _sessions = <String, SessionBridge>{};
  var _shuttingDown = false;

  AgentRuntime get _runtime => _core.runtime;

  /// Принимает ли план ядра HTTP-серверы MCP (`mcpCapabilities.http`).
  bool get _mcpHttp => switch (_core.plan.profile.states[HostCapability.mcp]) {
    CapabilityTransport(:final transports) => transports.contains('http'),
    _ => false,
  };

  bool get _persistent =>
      _core.plan.profile.isOn(HostCapability.sessionPersistence);

  /// Обслуживает одно соединение до его закрытия.
  ///
  /// Вход закрыт (EOF stdin, закрытый сокет) — соединение отвечает на уже
  /// прочитанные запросы, отправляет очередь и закрывает транспорт; только
  /// после этого [serve] завершается (§13.10). У stdio выход живёт дольше
  /// входа: `echo '{…}' | codelab-agent serve --stdio` ждёт ответа после EOF.
  Future<void> serve(AcpTransport transport) async {
    final connection = _Connection(this, transport);
    _connections.add(connection);
    try {
      await connection.run();
      await connection.close();
    } finally {
      _connections.remove(connection);
    }
  }

  /// Безопасное завершение (§13.10): новые запросы получают `-32603`,
  /// ходы отменяются и дожидаются `TurnEnded` не дольше [grace], сессии
  /// закрываются (журналы дописаны), затем закрываются транспорты.
  Future<void> shutdown({Duration grace = const Duration(seconds: 5)}) async {
    _shuttingDown = true;
    final bridges = [..._sessions.values];
    final turns = [
      for (final bridge in bridges)
        if (bridge.cancel()) bridge.idle,
    ];
    if (turns.isNotEmpty && grace > Duration.zero) {
      await Future.any([Future.wait(turns), clock.delay(grace)]);
    }
    for (final bridge in bridges) {
      await bridge.close();
    }
    _sessions.clear();
    for (final connection in [..._connections]) {
      await connection.close();
    }
  }

  /// Соединение закрыто: его сессии ждут переподключения (D7).
  void _detach(_Connection connection) {
    for (final bridge in _sessions.values) {
      if (identical(bridge.owner, connection)) {
        bridge.detach(config.detachGrace);
      }
    }
  }
}

/// Одно соединение: маршрутизатор, очередь, запросы агента и состояние
/// `initialize` (§13.1, §13.2).
final class _Connection {
  _Connection(this._server, this._transport) : _pending = PendingRequests() {
    _outbound = OutboundQueue(_transport, logger: _server._logger);
    _requests = ClientRequests(
      outbound: _outbound,
      pending: _pending,
      clock: _server.clock,
    );
    _router = InboundRouter(
      transport: _transport,
      outbound: _outbound,
      pending: _pending,
      logger: _server._logger,
      onRequest: _onRequest,
      onNotification: _onNotification,
    );
  }

  final AcpAgentServer _server;
  final AcpTransport _transport;
  final PendingRequests _pending;
  late final OutboundQueue _outbound;
  late final ClientRequests _requests;
  late final InboundRouter _router;

  /// Возможности клиента из `initialize`; `null` — `initialize` не было.
  acp.ClientCapabilities? _client;

  Logger get _logger => _server._logger;

  Future<void> run() async {
    await _transport.start();
    await _router.run();
    _pending.failAll(const ClientDisconnected());
    _server._detach(this);
  }

  Future<void>? _closing;

  /// Ответы на начатые запросы, затем отправка очереди и закрытие
  /// транспорта. Повторный вызов — та же операция: закрывают и `serve`
  /// после конца входа, и `shutdown`.
  Future<void> close() => _closing ??= () async {
    await _router.drained;
    await _outbound.idle;
    await _transport.close();
  }();

  Future<Reply> _onRequest(acp.JsonRpcRequest request) async {
    if (_server._shuttingDown) {
      throw const AcpRequestError(
        acp.jsonRpcInternalErrorCode,
        'shutting down',
      );
    }
    final method = request.method;
    if (method == acp.initializeMethod) {
      return _initialize(request.params);
    }
    if (_client == null && method.startsWith('session/')) {
      throw const AcpRequestError.invalidRequest('initialize required');
    }
    return switch (method) {
      acp.sessionNewMethod => _sessionNew(request.params),
      acp.sessionListMethod => _sessionList(request.params),
      acp.sessionLoadMethod => _sessionLoad(request.params),
      acp.sessionPromptMethod => _sessionPrompt(request.params),
      acp.sessionSetConfigOptionMethod => _setConfigOption(request.params),
      acp.sessionSetModeMethod => _setMode(request.params),
      // Терпимость: уведомление, присланное запросом, получает ещё и ответ
      // null (§13.7, шаг 6).
      acp.sessionCancelMethod => _cancelRequest(request.params),
      _ => throw AcpRequestError.methodNotFound('Method not found: $method'),
    };
  }

  Future<void> _onNotification(acp.JsonRpcNotification notification) async {
    switch (notification.method) {
      case acp.sessionCancelMethod:
        _cancel(notification.params);
      default:
        _logger.log(
          LogLevel.info,
          'acp.notification.unknown',
          fields: {'method': notification.method},
        );
    }
  }

  /// `initialize` (§13.2): версия всегда 1, возможности — по профилю.
  Future<Reply> _initialize(Object? params) async {
    if (_client != null) {
      throw const AcpRequestError.invalidRequest('already initialized');
    }
    final request = acp.acpInitialize.decodeParams(params);
    final raw = params is Map ? params : const <String, Object?>{};
    if (!raw.containsKey('clientCapabilities')) {
      // Иначе пропажа инструментов выглядит как поведение модели.
      _logger.log(LogLevel.warning, 'acp.client_capabilities.absent');
    }
    _client = request.clientCapabilities;
    final persistent = _server._persistent;
    final response = acp.InitializeResponse(
      protocolVersion: const acp.ProtocolVersion(1),
      agentCapabilities: acp.AgentCapabilities(
        loadSession: persistent,
        promptCapabilities: const acp.PromptCapabilities(
          image: true,
          embeddedContext: true,
        ),
        // `http` — по плану ядра: capability `mcp` с транспортом `http`;
        // `sse` всегда `false` (MCP объявил его устаревшим). Флага stdio в
        // ACP нет: он обязателен (`02-Initialization.md#mcp-capabilities`;
        // design.md change `add-agent-mcp-client`, D11).
        mcpCapabilities: acp.McpCapabilities(http: _server._mcpHttp),
        sessionCapabilities: acp.SessionCapabilities(
          list: persistent ? const acp.SessionListCapabilities() : null,
        ),
      ),
      agentInfo: _server.config.agentInfo,
    );
    return Reply(acp.acpInitialize.encodeResult(response));
  }

  /// `session/new` (§13.4) в объёме этапа 4.
  Future<Reply> _sessionNew(Object? params) async {
    final request = acp.acpSessionNew.decodeParams(params);
    final cwd = request.cwd;
    await _checkCwd(cwd);
    final mapped = _mapMcpServers(request.mcpServers);
    final wiring = _wire(cwd);
    final session = await _server._runtime.createSession(
      SessionSpec(cwd: cwd, ports: wiring.ports, mcpServers: mapped.servers),
    );
    // Пропуски пишутся после создания: id сессии известен только теперь.
    _logMcpSkips(session.id.value, mapped.skips);
    wiring.link.sessionId = session.id.value;
    wiring.bridge.attach(session);
    _server._sessions[session.id.value] = wiring.bridge;
    final sessionId = acp.SessionId(session.id.value);
    final response = acp.NewSessionResponse(
      sessionId: sessionId,
      modes: sessionModes(session),
      configOptions: wiring.bridge.configOptions,
    );
    return Reply(
      acp.acpSessionNew.encodeResult(response),
      // Встроенных slash-команд на этапе 4 нет (§13.4, шаг 6).
      after: () => _update(
        sessionId,
        const acp.SessionUpdate.availableCommandsUpdate(availableCommands: []),
      ),
    );
  }

  /// Отображает `mcpServers` запроса в `McpServerConfig` с `origin: session`
  /// (§13.4, шаг 2; design.md change `add-agent-mcp-client`, D11).
  ///
  /// Почему здесь пропускаются только `sse` и неизвестный `type`: это
  /// решение протокольного слоя (транспорт не поддерживается ACP-адаптером);
  /// capability, транспорт профиля, дубликаты и коллизии имён решает ядро
  /// (D6), поэтому правила одинаковы для ACP, встроенного режима и конфига.
  /// Пропуск — не ошибка запроса: остальные серверы и сессия живут.
  /// `_meta` серверов игнорируется.
  ({List<McpServerConfig> servers, List<_McpSkip> skips}) _mapMcpServers(
    List<acp.McpServer> servers,
  ) {
    final skips = <_McpSkip>[];
    void skip(String server, String transport, String reason) =>
        skips.add(_McpSkip(server, transport, reason));
    final result = <McpServerConfig>[];
    for (final server in servers) {
      switch (server) {
        case acp.McpServerStdio(:final name, :final command, :final args):
          result.add(
            McpStdioServerConfig(
              name: name,
              command: command,
              args: args,
              // При повторе имени переменной побеждает последняя (D11).
              env: {for (final v in server.env) v.name: v.value},
            ),
          );
        case acp.McpServerHttp(:final name, :final url, :final headers):
          final uri = Uri.tryParse(url);
          if (uri == null) {
            skip(name, 'http', 'invalid url');
            continue;
          }
          result.add(
            McpHttpServerConfig(
              name: name,
              url: uri,
              headers: [for (final h in headers) (h.name, h.value)],
            ),
          );
        case acp.McpServerSse(:final name):
          skip(name, 'sse', 'transport sse is not supported');
        case acp.McpServerUnknown(:final type, :final name):
          // Совместимость вперёд (`AGENTS.md` §7): неизвестный транспорт не
          // роняет запрос.
          skip(name ?? '', type, 'unknown transport');
      }
    }
    return (servers: result, skips: skips);
  }

  /// Пишет пропуски `mcp.server.skipped` с `session_id`. `name` и `type`
  /// пришли от клиента, поэтому в лог идут обрезанными до 64 рун (как
  /// `method` в D13).
  void _logMcpSkips(String sessionId, List<_McpSkip> skips) {
    for (final skip in skips) {
      _logger.log(
        LogLevel.info,
        'mcp.server.skipped',
        fields: {
          'session_id': sessionId,
          'server': _capRunes(skip.server),
          'transport': _capRunes(skip.transport),
          'reason': skip.reason,
        },
      );
    }
  }

  /// Env, gate и мост сессии этого соединения (D5, D6): файлы и команды —
  /// через клиента, листинг — локально, если хост его дал.
  ({ClientLink link, SessionBridge bridge, SessionHostPorts ports}) _wire(
    String cwd,
  ) {
    final link = ClientLink(requests: _requests, capabilities: _client!);
    final clientEnv = AcpClientExecutionEnv(
      link: link,
      cwd: cwd,
      timeouts: _server.config.timeouts,
      clock: _server.clock,
      logger: _logger,
    );
    final listing = _server.config.localListing;
    final bridge = SessionBridge(
      owner: this,
      sink: _notify,
      link: link,
      catalog: _server._runtime.models,
      clock: _server.clock,
      logger: _logger,
      clientEnv: clientEnv,
    );
    final ports = SessionHostPorts(
      env: listing == null
          ? clientEnv
          : ListingOverlayEnv(clientEnv, listing(cwd)),
      gate: AcpPermissionGate(
        link,
        logger: _logger,
        waitForReconnect: bridge.waitForReconnect,
        announced: bridge.announced,
      ),
      extraBeforeToolCall: [bridge.markInProgress],
    );
    clientEnv.terminalShown = bridge.terminalShown;
    return (link: link, bridge: bridge, ports: ports);
  }

  /// `session/load` (§13.5) в объёме MVP: реплей, хвост, затем ответ;
  /// переподключение идущего хода (шаги 3b, 8, 9).
  Future<Reply> _sessionLoad(Object? params) async {
    final request = acp.acpSessionLoad.decodeParams(params);
    final cwd = request.cwd;
    await _checkCwd(cwd);
    final id = request.sessionId.value;
    final mapped = _mapMcpServers(request.mcpServers);
    _logMcpSkips(id, mapped.skips);
    final mcpServers = mapped.servers;
    var reconnect = false;
    var bridge = _server._sessions[id];
    if (bridge != null) {
      // MVP: второй живой клиент идущего хода не подключается (шаг 3c).
      if (bridge.turnActive && !bridge.detached) {
        throw const AcpRequestError.invalidParams(
          'the session is busy in another connection',
          data: {
            'codelab': {'reason': 'sessionBusy'},
          },
        );
      }
      // Сначала проверка и `reattach` без `await` между ними: пока набор
      // серверов применяется (подключение бывает долгим), сессия уже
      // принадлежит этому соединению, и параллельный `session/load` другого
      // соединения упрётся в `sessionBusy` (шаг 3c), а не перехватит ход.
      reconnect = bridge.reattach(
        owner: this,
        requests: _requests,
        capabilities: _client!,
        sink: _notify,
      );
      // Открытая сессия: серверы клиента заменяются без пересоздания (D11).
      // Без хода набор применяется до ответа; во время хода метод
      // возвращается сразу, набор применит ядро после `TurnEnded`.
      try {
        await bridge.session.setMcpServers(mcpServers);
      } on Object catch (error) {
        // Сбой замены не должен ронять `session/load`, но и теряться не может.
        _logger.log(
          LogLevel.warning,
          'mcp.servers.replace_failed',
          fields: {'session_id': id, 'error': error.runtimeType.toString()},
        );
      }
    } else {
      final wiring = _wire(cwd)..link.sessionId = id;
      final AgentSession session;
      try {
        session = await _server._runtime.loadSession(
          SessionId(id),
          wiring.ports,
          cwd: cwd,
          mcpServers: mcpServers,
        );
      } on SessionNotFound {
        throw AcpRequestError.notFound('Session not found: $id');
      }
      bridge = wiring.bridge..attach(session);
      _server._sessions[id] = bridge;
    }
    for (final update in bridge.replay()) {
      _update(request.sessionId, update);
    }
    final response = acp.LoadSessionResponse(
      modes: sessionModes(bridge.session),
      configOptions: bridge.configOptions,
    );
    return Reply(
      acp.acpSessionLoad.encodeResult(response),
      after: reconnect ? bridge.resume : null,
    );
  }

  /// `session/set_config_option` (§13.6): сначала сессия, затем значение;
  /// ответ — полный список опций без дублирующего уведомления (ACP-11).
  Future<Reply> _setConfigOption(Object? params) async {
    final request = acp.acpSessionSetConfigOption.decodeParams(params);
    final bridge = _bridge(request.sessionId);
    final value = request.value.value;
    switch (request.configId.value) {
      case 'mode':
        await bridge.setMode(_mode(value));
      case 'model'
          when _server._runtime.models.models.any((m) => m.id.value == value):
        await bridge.setModel(ModelId(value));
      case 'effort' when bridge.session.model.supportsReasoning:
        await bridge.session.setEffort(
          parseEffort(value) ??
              (throw AcpRequestError.invalidParams('unknown value: $value')),
        );
      case 'model':
        throw AcpRequestError.invalidParams('unknown value: $value');
      default:
        throw AcpRequestError.invalidParams(
          'unknown config option: ${request.configId.value}',
        );
    }
    return Reply(
      acp.acpSessionSetConfigOption.encodeResult(
        acp.SetSessionConfigOptionResponse(configOptions: bridge.configOptions),
      ),
    );
  }

  /// `session/set_mode` (§13.6): та же смена, что `configId: "mode"`;
  /// ответ `{}` после `current_mode_update`.
  Future<Reply> _setMode(Object? params) async {
    final request = acp.acpSessionSetMode.decodeParams(params);
    final bridge = _bridge(request.sessionId);
    await bridge.setMode(_mode(request.modeId.value));
    return Reply(
      acp.acpSessionSetMode.encodeResult(const acp.SetSessionModeResponse()),
    );
  }

  static ModeId _mode(String value) =>
      parseModeId(value) ??
      (throw AcpRequestError.invalidParams('unknown mode: $value'));

  /// `session/list` (§13.5): страница хранилища.
  Future<Reply> _sessionList(Object? params) async {
    final request = acp.acpSessionList.decodeParams(params);
    final cwd = request.cwd;
    if (cwd != null && !_isAbsolute(cwd)) {
      throw const AcpRequestError.invalidParams('cwd must be an absolute path');
    }
    final SessionPage page;
    try {
      page = await _server._runtime.listSessions(
        cwd: cwd,
        cursor: request.cursor,
      );
    } on InvalidCursor {
      throw const AcpRequestError.invalidParams('invalid cursor');
    }
    final response = acp.ListSessionsResponse(
      sessions: [
        for (final summary in page.items)
          acp.SessionInfo(
            sessionId: acp.SessionId(summary.id.value),
            cwd: summary.cwd,
            title: summary.title,
            updatedAt: formatJournalTime(summary.updatedAt),
          ),
      ],
      nextCursor: page.nextCursor,
    );
    return Reply(acp.acpSessionList.encodeResult(response));
  }

  /// `session/prompt` (§13.7): ход в фоне, ответ — по `TurnEnded`.
  Future<Reply> _sessionPrompt(Object? params) async {
    final request = acp.acpSessionPrompt.decodeParams(params);
    final bridge = _bridge(request.sessionId);
    final content = promptContent(request.prompt);
    if (bridge.turnActive) {
      _logger.log(
        LogLevel.info,
        'acp.prompt.rejected',
        fields: {'session_id': request.sessionId.value, 'reason': 'turnActive'},
      );
      throw const AcpRequestError.invalidParams(
        'a turn is already running',
        data: {
          'codelab': {'reason': 'turnActive'},
        },
      );
    }
    final response = await bridge.prompt(content);
    return Reply(acp.acpSessionPrompt.encodeResult(response));
  }

  Future<Reply> _cancelRequest(Object? params) async {
    _cancel(params);
    return const Reply(null);
  }

  /// `session/cancel` (§13.7): без хода — только лог, ничего не уходит.
  void _cancel(Object? params) {
    final cancel = acp.acpSessionCancel.decodeParams(params);
    final bridge = _server._sessions[cancel.sessionId.value];
    if (bridge == null || !bridge.cancel()) {
      _logger.log(
        LogLevel.info,
        'acp.cancel.no_turn',
        fields: {'session_id': cancel.sessionId.value},
      );
      return;
    }
    _logger.log(
      LogLevel.info,
      'acp.cancel',
      fields: {'session_id': cancel.sessionId.value},
    );
  }

  SessionBridge _bridge(acp.SessionId id) =>
      _server._sessions[id.value] ??
      (throw AcpRequestError.notFound('Session not found: ${id.value}'));

  /// Абсолютный путь; при локальном листинге — существующий каталог.
  /// Без листинга проверить каталог нечем: в ACP нет stat каталога
  /// (design.md, D5).
  Future<void> _checkCwd(String cwd) async {
    if (!_isAbsolute(cwd)) {
      throw const AcpRequestError.invalidParams('cwd must be an absolute path');
    }
    final listing = _server.config.localListing;
    if (listing == null) {
      return;
    }
    final env = listing(cwd);
    // Рабочая папка может быть ссылкой на каталог (/tmp на macOS): stat —
    // по разрешённому пути.
    var target = cwd;
    if (env case final PathResolver resolver) {
      if (await resolver.realpath(cwd) case Ok(:final value)) {
        target = value;
      }
    }
    final stat = await env.stat(target);
    if (stat case Ok(value: FileStat(type: FileType.directory))) {
      return;
    }
    throw AcpRequestError.invalidParams('cwd does not exist: $cwd');
  }

  void _update(acp.SessionId sessionId, acp.SessionUpdate update) =>
      _notify(acp.SessionNotification(sessionId: sessionId, update: update));

  /// Очередь уведомлений соединения: мосты его сессий ставят сюда кадры
  /// в порядке событий ядра (D6).
  void _notify(acp.SessionNotification notification) {
    unawaited(
      _outbound.enqueue(
        acp.encodeAcpNotification(
          method: acp.sessionUpdateMethod,
          params: notification,
        ),
      ),
    );
  }

  static bool _isAbsolute(String path) => path.startsWith('/');
}

/// Пропущенный MCP-сервер до записи в лог: `session_id` на `session/new`
/// появляется только после `createSession`.
final class _McpSkip {
  const _McpSkip(this.server, this.transport, this.reason);

  final String server;
  final String transport;
  final String reason;
}

String _capRunes(String value, [int max = 64]) {
  final runes = value.runes;
  return runes.length <= max ? value : String.fromCharCodes(runes.take(max));
}
