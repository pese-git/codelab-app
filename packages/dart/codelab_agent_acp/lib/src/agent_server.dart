import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart' as acp;
import 'package:acp_transports/acp_transports.dart';
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

  bool get _persistent =>
      _core.plan.profile.isOn(HostCapability.sessionPersistence);

  /// Обслуживает одно соединение до его закрытия.
  Future<void> serve(AcpTransport transport) async {
    final connection = _Connection(this, transport);
    _connections.add(connection);
    try {
      await connection.run();
    } finally {
      _connections.remove(connection);
    }
  }

  /// Безопасное завершение (§13.10): новые запросы получают `-32603`,
  /// сессии закрываются, транспорты закрываются.
  Future<void> shutdown({Duration grace = const Duration(seconds: 5)}) async {
    _shuttingDown = true;
    for (final bridge in [..._sessions.values]) {
      await bridge.close();
    }
    _sessions.clear();
    for (final connection in [..._connections]) {
      await connection.close();
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
  }

  Future<void> close() async {
    await _outbound.idle;
    await _transport.close();
  }

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
      acp.sessionPromptMethod => _sessionPrompt(request.params),
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
        // MCP — этап 8: до него серверы из session/new не подключаются.
        mcpCapabilities: const acp.McpCapabilities(),
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
    for (final server in request.mcpServers) {
      _logger.log(
        LogLevel.info,
        'mcp.server.skipped',
        fields: {'name': server.name, 'reason': 'MCP is not available yet'},
      );
    }
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
      sink: _notify,
      logger: _logger,
      clientEnv: clientEnv,
    );
    final session = await _server._runtime.createSession(
      SessionSpec(
        cwd: cwd,
        ports: SessionHostPorts(
          env: listing == null
              ? clientEnv
              : ListingOverlayEnv(clientEnv, listing(cwd)),
          gate: AcpPermissionGate(link, logger: _logger),
        ),
        extraBeforeToolCall: [bridge.markInProgress],
      ),
    );
    link.sessionId = session.id.value;
    bridge.attach(session);
    _server._sessions[session.id.value] = bridge;
    final sessionId = acp.SessionId(session.id.value);
    final response = acp.NewSessionResponse(
      sessionId: sessionId,
      modes: sessionModes(session),
      configOptions: sessionConfigOptions(session),
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
    final stat = await listing(cwd).stat(cwd);
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
