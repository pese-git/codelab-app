import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'json_rpc.dart';
import 'protocol.dart';
import 'text.dart';

/// Настройки клиента, общие для серверов (design.md change
/// `add-agent-mcp-client`, D8).
///
/// Как использовать: хост передаёт значение коннектору; ключ конфигурации
/// `mcp.servers.*.call_timeout` появится в change `add-agent-configuration`
/// (8.5), до тех пор [callTimeout] — константа MVP.
final class McpClientOptions {
  const McpClientOptions({
    this.callTimeout = const Duration(minutes: 10),
    this.clientName = 'codelab-agent',
    this.clientVersion = coreAgentVersion,
  });

  /// Предел одного `tools/call` (D8).
  final Duration callTimeout;

  /// `clientInfo` modern-запросов и `initialize` (D2).
  final String clientName;
  final String clientVersion;
}

/// Эпоха HTTP-серверов по `origin` URL в памяти процесса (D2).
///
/// Почему: проба `server/discover` стоит запроса (а у молчаливого legacy —
/// до пяти секунд), а эпоха — свойство сервера, а не запроса
/// (`basic/versioning.md`). Кэш живёт в `McpClientConnector`, на диск не
/// пишется. Не подтвердившееся предположение клиент проверяет заново один
/// раз.
final class McpEraCache {
  final _eras = <String, McpEra>{};

  bool get isEmpty => _eras.isEmpty;

  McpEra? lookup(String origin) => _eras[origin];

  void store(String origin, McpEra era) => _eras[origin] = era;

  void forget(String origin) => _eras.remove(origin);
}

/// Подключение не удалось; [reason] уже записана в `mcp.server.failed`.
///
/// Причина формируется кодом клиента и не содержит секретов (D13).
final class McpConnectException implements Exception {
  const McpConnectException(this.reason);

  final String reason;

  @override
  String toString() => 'McpConnectException: $reason';
}

/// Итог `tools/call`: результат сервера или готовый текст ошибки для модели
/// (D8). Ошибки — значения, а не исключения хода (TOOL-3).
sealed class McpCallOutcome {
  const McpCallOutcome();
}

final class McpCallDone extends McpCallOutcome {
  const McpCallDone(this.result);

  final CallToolResult result;
}

final class McpCallError extends McpCallOutcome {
  const McpCallError(this.text);

  /// Фиксированный английский текст D8 для результата-ошибки.
  final String text;
}

// Внутренние исходы запроса.
final class _RpcError implements Exception {
  const _RpcError(this.error, this.method);

  final McpErrorResponse error;

  /// Метод запроса, на который пришла ошибка (для причин в логах).
  final String method;
}

final class _Timeout implements Exception {
  const _Timeout(this.method);

  final String method;
}

final class _Disconnected implements Exception {
  const _Disconnected(this.reason);

  final String reason;
}

final class _Aborted implements Exception {
  const _Aborted();
}

final class _Pending {
  final String method;
  final completer = Completer<Map<String, Object?>>();

  _Pending(this.method) {
    // Ошибку ждёт вызывающий позже, чем она может прийти (отмена во время
    // `send`): без этого Dart счёл бы её необработанной.
    completer.future.ignore();
  }
}

/// Соединение с одним MCP-сервером одной сессии (design.md change
/// `add-agent-mcp-client`, D2, D5, D8).
///
/// Почему отдельный класс: определение эпохи, рукопожатие, пагинация, отмена
/// и таймауты — протокол MCP, а ядро знает только порт [McpTransport]. Один
/// клиент — один сервер: сбой одного не затрагивает остальные (E-05).
///
/// Как использовать: [connect] укладывается в `server.connectTimeout`,
/// определяет эпоху пробой `server/discover` (или по [eraCache]), выполняет
/// рукопожатие эпохи и читает `tools/list`. Провал — [McpConnectException]
/// после лога `mcp.server.failed` и закрытия транспорта. Дальше
/// [callTool] исполняет вызовы, [close] закрывает соединение.
final class McpClient {
  McpClient._({
    required this.server,
    required McpTransport transport,
    required Clock clock,
    required Logger logger,
    required this.sessionId,
    required this.options,
    required McpEraCache? eraCache,
    required this.onToolsChanged,
  }) : _transport = transport,
       _clock = clock,
       _logger = logger,
       _eraCache = eraCache,
       _outbound = McpOutbound(
         clientName: options.clientName,
         clientVersion: options.clientVersion,
       );

  /// Подключает [server] поверх уже открытого [transport].
  ///
  /// [onToolsChanged] получает новый полный список после
  /// `notifications/tools/list_changed` (D6). [eraCache] используется только
  /// для HTTP-серверов.
  static Future<McpClient> connect({
    required McpServerConfig server,
    required McpTransport transport,
    required Clock clock,
    required Logger logger,
    required SessionId sessionId,
    McpClientOptions options = const McpClientOptions(),
    McpEraCache? eraCache,
    void Function(List<McpToolDefinition> tools)? onToolsChanged,
  }) async {
    final client = McpClient._(
      server: server,
      transport: transport,
      clock: clock,
      logger: logger,
      sessionId: sessionId,
      options: options,
      eraCache: eraCache,
      onToolsChanged: onToolsChanged,
    );
    return client._start();
  }

  final McpServerConfig server;
  final SessionId sessionId;
  final McpClientOptions options;
  final void Function(List<McpToolDefinition> tools)? onToolsChanged;

  final McpTransport _transport;
  final Clock _clock;
  final Logger _logger;
  final McpEraCache? _eraCache;
  final McpOutbound _outbound;
  final _pending = <int, _Pending>{};
  late final DateTime _startedAt;

  var _tools = <McpToolDefinition>[];
  var _era = McpEra.modern;
  var _protocolVersion = '';
  var _connected = false;
  var _closing = false;
  McpTransportClosed? _closedReason;

  /// Идентификатор запроса `subscriptions/listen`, пока он жив: ему на stdio
  /// уходит `notifications/cancelled` при закрытии.
  int? _listenId;

  /// Подписка, уведомления которой принимаются; `null` — живём без обновлений.
  int? _subscriptionId;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Completer<bool>? _ack;
  var _refreshing = false;
  var _refreshAgain = false;
  Map<String, Object?>? _serverInfo;
  var _tasksForToolsCall = false;

  /// Инструменты сервера после фильтра D5 (шаг 4), в порядке `tools/list`.
  List<McpToolDefinition> get tools => List.unmodifiable(_tools);

  McpEra get era => _era;
  String get protocolVersion => _protocolVersion;

  /// Транспорт жив и клиент не закрыт.
  bool get isConnected => _connected && !_closing;

  String get _id => server.name;

  void _log(
    LogLevel level,
    String event, [
    Map<String, Object?> fields = const {},
  ]) {
    _logger.log(
      level,
      event,
      fields: {
        'session_id': sessionId.value,
        'server': _id,
        // Поле `transport` есть только у событий `mcp.server.*` (D13).
        if (event.startsWith('mcp.server.')) 'transport': _transport.kind,
        ...fields,
      },
    );
  }

  Duration _remaining() {
    final left = server.connectTimeout - _clock.now().difference(_startedAt);
    return left > Duration.zero ? left : Duration.zero;
  }

  Future<McpClient> _start() async {
    _startedAt = _clock.now();
    _subscriptions
      ..add(_transport.incoming.listen(_onText, onError: _onStreamError))
      ..add(
        _transport.abortedRequests.listen(_onAborted, onError: _onStreamError),
      );
    unawaited(_transport.done.then(_onClosed));
    try {
      await _handshake();
      _connected = true;
      _log(LogLevel.info, 'mcp.server.connect', {
        'era': _era.name,
        'protocol_version': _protocolVersion,
        if (_serverInfo != null) 'server_info': _serverInfoSummary(),
        'tools': _tools.length,
        'duration_ms': _clock.now().difference(_startedAt).inMilliseconds,
      });
      // `list_changed` мог прийти, пока читался список: перечитываем сейчас.
      if (_refreshAgain && !_refreshing) {
        unawaited(_refreshLoop());
      }
      return this;
    } on _Failure catch (failure) {
      return _fail(failure.reason);
    } on _Timeout catch (timeout) {
      return _fail(
        'no answer to ${timeout.method} within '
        '${server.connectTimeout.inSeconds} s',
      );
    } on _Disconnected catch (gone) {
      return _fail('disconnected: ${gone.reason}');
    } on _Aborted {
      return _fail('response stream closed');
    } on _RpcError catch (rpc) {
      return _fail('${rpc.method} failed (code ${rpc.error.code})');
    } on McpSchemaException catch (schema) {
      return _fail('invalid server answer: ${schema.message}');
    } on Object catch (error) {
      // Исключение реализации транспорта или клиента: тоже провал только
      // этого сервера, транспорт закрывается (D6).
      return _fail('unexpected error: ${error.runtimeType}');
    }
  }

  Future<McpClient> _fail(String reason) async {
    final text = truncateRunes(reason, 200);
    _log(LogLevel.warning, 'mcp.server.failed', {'reason': text});
    await close();
    throw McpConnectException(text);
  }

  Map<String, Object?> _serverInfoSummary() => {
    'name': _serverInfo?['name'],
    'version': _serverInfo?['version'],
  };

  /// Эпоха и рукопожатие (D2, D5, шаги 1–3).
  Future<void> _handshake() async {
    final origin = server is McpHttpServerConfig
        ? (server as McpHttpServerConfig).url.origin
        : null;
    final cache = origin == null ? null : _eraCache;
    final cached = origin == null ? null : cache?.lookup(origin);

    if (cached == McpEra.legacy) {
      // Кэшированный legacy: проба пропускается, сразу `initialize`.
      try {
        await _legacyHandshake(probe: 'cached');
        return;
      } on _RpcError {
        // Предположение не подтвердилось: эпоха определяется заново (D2).
        cache!.forget(origin!);
        _outbound.era = McpEra.modern;
      }
    }

    _outbound.era = McpEra.modern;
    final probe = _probeTimeout();
    DiscoverResult? discover;
    String? probeOutcome;
    try {
      final result = await _request(
        'server/discover',
        const {},
        timeout: probe,
      );
      parseResultType(result);
      discover = DiscoverResult.fromJson(result);
      probeOutcome = 'discover_result';
    } on _RpcError catch (rpc) {
      if (isModernErrorCode(rpc.error.code)) {
        _era = McpEra.modern;
        cache?.store(origin!, McpEra.modern);
        _log(LogLevel.info, 'mcp.server.era', {
          'era': 'modern',
          'probe': 'modern_error',
        });
        // `-32020`/`-32021` не про версии: «supports []» вводил бы в
        // заблуждение (`basic/versioning.md`, D13).
        throw _Failure(
          rpc.error.code == mcpUnsupportedProtocolVersion
              ? 'no common protocol version: server supports '
                    '[${_safeVersions(rpc.error.supportedVersions)}]'
              : 'server rejected the probe (code ${rpc.error.code})',
        );
      }
      probeOutcome = 'fallback_error';
    } on McpSchemaException {
      probeOutcome = 'fallback_error';
    } on _Timeout {
      probeOutcome = 'fallback_timeout';
    }

    if (discover == null) {
      cache?.store(origin!, McpEra.legacy);
      await _legacyHandshake(probe: probeOutcome);
      return;
    }
    await _modernHandshake(discover, probe: probeOutcome);
    cache?.store(origin!, McpEra.modern);
  }

  Duration _probeTimeout() {
    final half = Duration(
      microseconds: server.connectTimeout.inMicroseconds ~/ 2,
    );
    final limit = half < const Duration(seconds: 5)
        ? half
        : const Duration(seconds: 5);
    final left = _remaining();
    return limit < left ? limit : left;
  }

  Future<void> _modernHandshake(
    DiscoverResult discover, {
    required String probe,
  }) async {
    if (!discover.supportedVersions.contains(modernProtocolVersion)) {
      _log(LogLevel.info, 'mcp.server.era', {'era': 'modern', 'probe': probe});
      throw _Failure(
        'no common protocol version: server supports '
        '[${_safeVersions(discover.supportedVersions)}]',
      );
    }
    _era = McpEra.modern;
    _protocolVersion = modernProtocolVersion;
    _serverInfo = discover.serverInfo;
    _log(LogLevel.info, 'mcp.server.era', {
      'era': 'modern',
      'protocol_version': _protocolVersion,
      'probe': probe,
    });
    if (!discover.hasTools) {
      return;
    }
    if (discover.toolsListChanged) {
      await _subscribe();
    }
    _tools = _filter(await _listAll());
  }

  /// `subscriptions/listen` и ожидание подтверждения (D5, шаг 2).
  ///
  /// Подписка — необязательное удобство: ошибка, результат или обрыв ответа
  /// на `subscriptions/listen` до подтверждения, а также молчание дольше
  /// `min(5 с, connectTimeout / 2)` означают «сервер подключён, живём без
  /// обновлений».
  Future<void> _subscribe() async {
    final encoded = _outbound.request('subscriptions/listen', {
      'notifications': {'toolsListChanged': true},
    });
    final entry = _Pending('subscriptions/listen');
    _pending[encoded.id] = entry;
    final ack = _ack = Completer<bool>();
    ack.future.ignore();
    _listenId = encoded.id;
    // Ответ на `subscriptions/listen` приходит только при закрытии подписки
    // (`subscriptions.md`, «Graceful Closure») или как ошибка.
    entry.completer.future.then(
      (_) {
        final before = !ack.isCompleted;
        _endSubscription();
        _log(LogLevel.debug, 'mcp.message.ignored', {
          'kind': before ? 'subscription_failed' : 'subscription_closed',
          if (before) 'method': 'subscriptions/listen',
        });
        if (before) {
          ack.complete(false);
        }
      },
      onError: (Object error) {
        if (error is _Disconnected) {
          return;
        }
        _endSubscription();
        _log(LogLevel.debug, 'mcp.message.ignored', {
          'kind': 'subscription_failed',
          'method': 'subscriptions/listen',
          if (error is _RpcError) 'code': error.error.code,
        });
        if (!ack.isCompleted) {
          ack.complete(false);
        }
      },
    );
    await _send(encoded.text, 'subscriptions/listen');
    var timedOut = false;
    final timer = _clock.timer(_probeTimeout(), () {
      if (!ack.isCompleted) {
        timedOut = true;
        _log(LogLevel.debug, 'mcp.message.ignored', {
          'kind': 'subscription_failed',
          'method': 'subscriptions/listen',
        });
        ack.complete(false);
      }
    });
    try {
      await ack.future;
    } finally {
      timer.cancel();
      _ack = null;
    }
    if (timedOut) {
      // Молчание дольше предела: живём без обновлений, а запрос подписки
      // отменяется сигналом своего транспорта (`cancellation.md`, Timeouts;
      // D8). Окончание подписки до сигнала — `close()` не пошлёт второй.
      _pending.remove(encoded.id);
      _endSubscription();
      await _signalCancel(encoded.id, 'timeout');
    }
  }

  /// Подписка закончилась: уведомления не принимаются, отменять нечего.
  void _endSubscription() {
    _subscriptionId = null;
    _listenId = null;
  }

  Future<void> _legacyHandshake({required String probe}) async {
    _outbound.era = McpEra.legacy;
    final result = await _request('initialize', {
      'protocolVersion': legacyRequestedVersion,
      'capabilities': <String, Object?>{},
      'clientInfo': {
        'name': options.clientName,
        'version': options.clientVersion,
      },
    }, timeout: _remaining());
    final init = InitializeResult.fromJson(result);
    if (!legacyAcceptedVersions.contains(init.protocolVersion)) {
      throw _Failure(
        'unsupported protocol version ${_safeVersion(init.protocolVersion)}',
      );
    }
    _era = McpEra.legacy;
    _protocolVersion = init.protocolVersion;
    _serverInfo = init.serverInfo;
    _tasksForToolsCall = init.tasksForToolsCall;
    // `initialized` — после ответа на `initialize` (lifecycle.md).
    await _send(
      _outbound.notification('notifications/initialized'),
      'notifications/initialized',
    );
    _log(LogLevel.info, 'mcp.server.era', {
      'era': 'legacy',
      'protocol_version': _protocolVersion,
      'probe': probe,
    });
    if (!init.hasTools) {
      return;
    }
    _tools = _filter(await _listAll());
  }

  /// Страницы `tools/list`, не больше 100 (D5, шаг 4).
  Future<List<McpToolDefinition>> _listAll() async {
    final all = <McpToolDefinition>[];
    String? cursor;
    var pages = 0;
    do {
      if (pages >= _maxPages) {
        throw const _Failure('tools/list pagination did not end');
      }
      pages++;
      final result = await _request(
        'tools/list',
        {'cursor': ?cursor},
        timeout: _connected ? server.connectTimeout : _remaining(),
        retryOnAbort: true,
        // На живом соединении таймаут запроса — отмена по таблице D8
        // (`cancellation.md`, Timeouts); при подключении сервер закрывается.
        signalCancel: _connected,
      );
      if (parseResultType(result) != ResultType.complete) {
        throw const McpSchemaException('tools/list asked for client input');
      }
      final page = ListToolsResult.fromJson(result);
      all.addAll(page.tools);
      cursor = page.nextCursor;
    } while (cursor != null);
    return all;
  }

  static const _maxPages = 100;

  /// Инструмент, которым клиент заведомо не воспользуется, пропускается с
  /// `mcp.tool.invalid`, остальные регистрируются (D5, шаг 4).
  List<McpToolDefinition> _filter(List<McpToolDefinition> tools) {
    final kept = <McpToolDefinition>[];
    for (final tool in tools) {
      if (_era == McpEra.legacy &&
          _tasksForToolsCall &&
          tool.taskSupport == 'required') {
        _log(LogLevel.warning, 'mcp.tool.invalid', {
          'tool': tool.name,
          'reason': 'task support required',
        });
        continue;
      }
      kept.add(tool);
    }
    return kept;
  }

  // --- запросы ---------------------------------------------------------

  Future<void> _send(
    String text,
    String method, {
    Map<String, String> headers = const {},
  }) async {
    try {
      await _transport.send(text, headers: headers);
    } on McpTransportException catch (error) {
      throw _Disconnected(error.message);
    }
  }

  Future<Map<String, Object?>> _request(
    String method,
    Map<String, Object?> params, {
    Duration? timeout,
    CancelToken? cancel,
    bool retryOnAbort = false,
    bool signalCancel = false,
    void Function(int id)? onId,
  }) async {
    var retried = false;
    while (true) {
      try {
        return await _requestOnce(
          method,
          params,
          timeout: timeout,
          cancel: cancel,
          signalCancel: signalCancel,
          onId: onId,
        );
      } on _Aborted {
        // Повторяются только запросы без побочных эффектов (D8).
        if (!retryOnAbort || retried) {
          throw const _Disconnected('response stream closed');
        }
        retried = true;
      }
    }
  }

  Future<Map<String, Object?>> _requestOnce(
    String method,
    Map<String, Object?> params, {
    Duration? timeout,
    CancelToken? cancel,
    bool signalCancel = false,
    void Function(int id)? onId,
  }) async {
    if (_closedReason case final closed?) {
      throw _Disconnected(closed.reason);
    }
    if (cancel != null && cancel.isCancelled) {
      throw CancelledException(cancel.reason);
    }
    final encoded = _outbound.request(method, params);
    final entry = _Pending(method);
    _pending[encoded.id] = entry;
    onId?.call(encoded.id);
    ClockTimer? timer;
    if (timeout != null) {
      timer = _clock.timer(timeout, () {
        if (!entry.completer.isCompleted) {
          entry.completer.completeError(_Timeout(method));
        }
      });
    }
    cancel?.onCancel.then((_) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(CancelledException(cancel.reason));
      }
    });
    try {
      await _send(encoded.text, method);
      return await entry.completer.future;
    } on _Timeout {
      if (signalCancel) {
        await _signalCancel(encoded.id, 'timeout');
      }
      rethrow;
    } on CancelledException {
      if (signalCancel) {
        await _signalCancel(encoded.id, 'cancelled by the client');
      }
      rethrow;
    } finally {
      timer?.cancel();
      _pending.remove(encoded.id);
    }
  }

  /// Сигнал отмены своего транспорта и эпохи, не больше одного раза на
  /// запрос (D8, `basic/patterns/cancellation.md`).
  Future<void> _signalCancel(int id, String reason) async {
    final http = _transport.kind == 'http';
    try {
      if (!http || _era == McpEra.legacy) {
        await _transport.send(
          _outbound.notification('notifications/cancelled', {
            'requestId': id,
            'reason': reason,
          }),
        );
      }
      if (http) {
        await _transport.abandon(id);
      }
    } on McpTransportException {
      // Транспорт уже закрыт: сигналить некому.
    }
  }

  /// Вызов инструмента сервера (D8): `tools/call {name, arguments}` с
  /// исходным именем инструмента.
  ///
  /// Возвращает [McpCallDone] или [McpCallError] с готовым английским
  /// текстом для модели — ошибки сервера, таймаут и обрыв не прерывают ход
  /// (TOOL-3). Отмена [cancel] снимает ожидание сразу, подаёт сигнал своего
  /// транспорта и эпохи один раз и бросает [CancelledException]; поздний
  /// ответ игнорируется (`AGENTS.md` §9). Обрыв не повторяется: у вызова
  /// могли быть побочные эффекты. [toolCallId] — только для логов.
  Future<McpCallOutcome> callTool(
    String name,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
    String? toolCallId,
  }) async {
    if (!isConnected) {
      return McpCallError(
        'MCP server $_id is not connected. Continue without it.',
      );
    }
    int? requestId;
    try {
      final result = await _request(
        'tools/call',
        {'name': name, 'arguments': arguments},
        timeout: options.callTimeout,
        cancel: cancel,
        signalCancel: true,
        onId: (id) => requestId = id,
      );
      if (parseResultType(result) == ResultType.inputRequired) {
        return McpCallError(
          'MCP server $_id asked for client input, which is not supported.',
        );
      }
      return McpCallDone(CallToolResult.fromJson(result));
    } on CancelledException {
      _log(LogLevel.info, 'mcp.call.cancelled', {
        'tool_call_id': ?toolCallId,
        'request_id': ?requestId,
      });
      rethrow;
    } on _Timeout {
      _log(LogLevel.info, 'mcp.call.timeout', {
        'tool_call_id': ?toolCallId,
        'request_id': ?requestId,
      });
      return McpCallError(
        'MCP server $_id did not answer tools/call within '
        '${options.callTimeout.inSeconds} s.',
      );
    } on _Disconnected catch (gone) {
      return McpCallError(
        'MCP server $_id disconnected during the call: ${gone.reason}',
      );
    } on _RpcError catch (rpc) {
      return McpCallError(
        'MCP server $_id returned an error: ${rpc.error.message} '
        '(code ${rpc.error.code})',
      );
    } on McpSchemaException {
      return McpCallError(
        'MCP server $_id returned an invalid tools/call result.',
      );
    }
  }

  // --- входящие --------------------------------------------------------

  void _onText(String text) {
    try {
      // В `2026-07-28` пакетов JSON-RPC нет; массив принимается только до
      // того, как подтверждена modern-эпоха (пробу мог ответить legacy
      // `2025-03-26`).
      final modern =
          _era == McpEra.modern && _protocolVersion == modernProtocolVersion;
      if (modern && text.trimLeft().startsWith('[')) {
        _log(LogLevel.debug, 'mcp.message.ignored', {'kind': 'parse_error'});
        return;
      }
      for (final message in decodeMcpMessages(text)) {
        _dispatch(message);
      }
    } on Object {
      // Исключение разбора или обработки одного сообщения не должно ронять
      // процесс агента (`AGENTS.md` §9).
      _log(LogLevel.debug, 'mcp.message.ignored', {'kind': 'parse_error'});
    }
  }

  void _onStreamError(Object error) {
    if (_closedReason == null) {
      _onClosed(const McpTransportClosed('transport error'));
      unawaited(_transport.close());
    }
  }

  void _dispatch(McpIncoming message) {
    switch (message) {
      case McpResponse(:final id, :final result):
        _settle(id, (p) => p.completer.complete(result));
      case McpErrorResponse(:final id):
        _settle(
          id,
          (p) => p.completer.completeError(_RpcError(message, p.method)),
        );
      case McpRequest(:final id, :final method):
        _answerServerRequest(id, method);
      case McpNotification(:final method, :final params):
        _onNotification(method, params);
      case McpMalformed():
        _log(LogLevel.debug, 'mcp.message.ignored', {'kind': 'parse_error'});
    }
  }

  void _settle(Object id, void Function(_Pending) complete) {
    final entry = id is int ? _pending[id] : null;
    if (entry == null || entry.completer.isCompleted) {
      // Поздний ответ на отменённый запрос, просроченную пробу или чужой id
      // (D5, `AGENTS.md` §9): состояние не меняется.
      _log(LogLevel.debug, 'mcp.message.ignored', {'kind': 'late_response'});
      return;
    }
    complete(entry);
  }

  /// Запрос сервера клиенту (`ping`, `sampling/createMessage`, ...).
  ///
  /// Modern: клиент НЕ пишет JSON-RPC-ответов (`stdio.md`; `streamable-http.md`,
  /// п. 4), запрос только логируется. Legacy: `ping` — пустой результат
  /// (`2025-11-25/basic/utilities/ping.md`), остальное — `-32601`. Ветка
  /// выбирается по `_outbound.era` — она фиксируется с отправки `initialize`,
  /// а `_era` становится legacy лишь после ответа, то есть `ping` в окне
  /// рукопожатия иначе получил бы `-32601`.
  void _answerServerRequest(Object id, String method) {
    if (_outbound.era != McpEra.legacy) {
      // Метод — строка сервера: обрезается, чтобы не раздувать лог (D13).
      _log(LogLevel.debug, 'mcp.message.ignored', {
        'kind': 'server_request',
        'method': truncateRunes(method, 64),
      });
      return;
    }
    final reply = method == 'ping'
        ? _outbound.response(id, const {})
        : _outbound.errorResponse(
            id,
            jsonRpcMethodNotFound,
            'Method not found',
          );
    unawaited(
      _transport.send(reply).catchError((Object _) {
        // Транспорт закрыт: ответ уже не нужен.
      }),
    );
  }

  void _onNotification(String method, Map<String, Object?> params) {
    final meta = params['_meta'];
    final subscription = meta is Map
        ? meta['io.modelcontextprotocol/subscriptionId']
        : null;
    switch (method) {
      case 'notifications/subscriptions/acknowledged':
        final ack = _ack;
        if (ack != null && !ack.isCompleted && subscription == _listenId) {
          final filter = params['notifications'];
          final accepted = filter is Map && filter['toolsListChanged'] == true;
          // Подтверждение без toolsListChanged: живём без обновлений (D5).
          _subscriptionId = accepted ? _listenId : null;
          ack.complete(accepted);
        }
      case 'notifications/tools/list_changed':
        // Modern: только с `subscriptionId` нашей подписки; legacy — с
        // общего канала (D5).
        final ours = _era == McpEra.legacy
            ? true
            : subscription != null && subscription == _subscriptionId;
        if (ours) {
          _onToolsListChanged();
        } else {
          _log(LogLevel.debug, 'mcp.message.ignored', {
            'kind': 'unknown_notification',
          });
        }
      case 'notifications/cancelled':
        // Сервер MUST слать его при снятии подписки с id запроса
        // `subscriptions/listen` и ни для чего другого (`cancellation.md`).
        final listen = _listenId;
        if (listen != null && params['requestId'] == listen) {
          _pending.remove(listen);
          _endSubscription();
          _log(LogLevel.debug, 'mcp.message.ignored', {
            'kind': 'subscription_closed',
          });
          if (_ack case final ack? when !ack.isCompleted) {
            ack.complete(false);
          }
        } else {
          _log(LogLevel.debug, 'mcp.message.ignored', {
            'kind': 'unknown_notification',
          });
        }
      default:
        _log(LogLevel.debug, 'mcp.message.ignored', {
          'kind': 'unknown_notification',
        });
    }
  }

  /// Повторное уведомление во время перечитывания ставит флаг, а не
  /// запускает параллельный `tools/list` (D6).
  void _onToolsListChanged() {
    if (_closing || _closedReason != null) {
      return;
    }
    // Во время подключения набор читается самим подключением: помечаем
    // перечитывание на момент его окончания.
    if (!_connected) {
      _refreshAgain = true;
      return;
    }
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    unawaited(_refreshLoop());
  }

  Future<void> _refreshLoop() async {
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final fresh = _filter(await _listAll());
        _tools = fresh;
        onToolsChanged?.call(List.unmodifiable(fresh));
      } while (_refreshAgain);
    } on Object catch (error) {
      // Прежний набор остаётся; причина — только наш код, без тела ответа.
      _log(LogLevel.warning, 'mcp.tools.refresh_failed', {
        'reason': _describe(error),
      });
    } finally {
      _refreshing = false;
    }
  }

  String _describe(Object error) => switch (error) {
    _Failure(:final reason) => reason,
    _Timeout(:final method) => 'no answer to $method',
    _Disconnected(:final reason) => 'disconnected: $reason',
    _RpcError(:final error, :final method) =>
      '$method failed (code ${error.code})',
    McpSchemaException(:final message) => message,
    _ => 'unexpected error',
  };

  void _onAborted(Object id) {
    final entry = id is int ? _pending[id] : null;
    if (entry != null && !entry.completer.isCompleted) {
      entry.completer.completeError(const _Aborted());
    }
  }

  void _onClosed(McpTransportClosed closed) {
    if (_closedReason != null) {
      return;
    }
    _closedReason = closed;
    final wasConnected = _connected;
    _connected = false;
    for (final entry in [..._pending.values]) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(_Disconnected(closed.reason));
      }
    }
    if (_ack case final ack? when !ack.isCompleted) {
      ack.completeError(_Disconnected(closed.reason));
    }
    if (wasConnected && !_closing) {
      _log(LogLevel.warning, 'mcp.server.failed', {
        'reason': 'disconnected: ${closed.reason}',
      });
    }
  }

  /// Идемпотентно; ожидающие запросы отменяются без
  /// `notifications/cancelled`, кроме подписки на stdio (D5).
  Future<void> close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    final subscription = _listenId;
    if (subscription != null &&
        _transport.kind == 'stdio' &&
        _closedReason == null) {
      try {
        await _transport.send(
          _outbound.notification('notifications/cancelled', {
            'requestId': subscription,
          }),
        );
      } on McpTransportException {
        // Процесс уже вышел.
      }
    }
    for (final entry in [..._pending.values]) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(const _Disconnected('client closed'));
      }
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _transport.close();
  }
}

final _versionPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Версия сервера в причине провала — только если она похожа на дату
/// ревизии: строки сервера в логи не попадают (D13).
String _safeVersion(String version) =>
    _versionPattern.hasMatch(version) ? version : '(unrecognized)';

String _safeVersions(List<String> versions) =>
    versions.where(_versionPattern.hasMatch).take(10).join(', ');

/// Провал подключения с готовой причиной.
final class _Failure implements Exception {
  const _Failure(this.reason);

  final String reason;
}
