import 'dart:async';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'mcp_client.dart';
import 'mcp_tool.dart';
import 'protocol.dart';
import 'text.dart';

/// Фабрики транспортов по ключам capability `mcp` (design.md change
/// `add-agent-mcp-client`, D3).
///
/// Как использовать: хост собирает значение один раз — `stdio` даёт
/// `codelab_agent_io`, `http` — `codelab_agent_mcp` на `http.Client` хоста;
/// профиль без процессов оставляет `stdio` пустым.
final class McpTransports {
  const McpTransports({this.stdio, this.http});

  final McpTransportFactory? stdio;
  final McpTransportFactory? http;

  /// Ключи транспортов, которые есть у хоста.
  Set<String> get keys => {
    if (stdio != null) ...stdio!.transports.intersection({'stdio'}),
    if (http != null) ...http!.transports.intersection({'http'}),
  };

  McpTransportFactory? operator [](String transport) => switch (transport) {
    'stdio' => stdio,
    'http' => http,
    _ => null,
  };
}

/// Предел `lastError` в сводке сервера, в рунах (D11).
const _lastErrorLimit = 200;

/// Верхняя граница задержки повтора (D11).
const _maxRetryDelay = Duration(seconds: 30);

/// Сколько должно прожить соединение, чтобы счётчик задержек начался
/// заново (D11): сервер, падающий сразу после подключения, не дёргается раз в
/// секунду.
const _stableConnection = Duration(seconds: 10);

/// Подключение MCP-серверов сессии — реализация порта ядра `McpConnector`
/// (`AgentCoreServices.mcp`; design.md change `add-agent-mcp-client`, D6, и
/// `add-config-writer-and-reload`, D11).
///
/// Почему здесь, а не в ядре: ядро не знает протокола MCP, а регистрация
/// требует `McpClient` и `McpTool`. Коннектор подключает серверы параллельно,
/// но регистрирует инструменты строго в порядке списка, поэтому при коллизии
/// имён побеждает сервер, стоящий раньше, независимо от порядка подключения
/// (HOST-5, E-05, детерминизм фикстур).
///
/// Для чего ещё: сессия коннектора — супервизор своих серверов (D11,
/// `agent-core-architecture` §17.5.7). Каждый сервер идёт по автомату
/// `connecting`, `connected`, `failed`, `disabled`; упавший сервер
/// переподключается с нарастающей задержкой, а его инструменты остаются в
/// реестре, чтобы схемы не менялись под моделью.
///
/// Ручной выбор человека (`setEnabled`) действует, пока элемент сервера в
/// конфиге не изменился; правка самого сервера (R6-2) начинает с состояния из
/// конфига.
///
/// Как использовать: хост создаёт один коннектор на процесс и передаёт его в
/// `AgentCoreServices.mcp`; ядро вызывает [connect] при создании и загрузке
/// сессии. [clock] и [random] приходят от хоста (PKG-6): таймеры повторов —
/// `Clock.timer`, джиттер — `Random`; в тестах — `FakeClock` и `Random(0)`.
/// Кэш эпохи HTTP-серверов ([eraCache]) живёт столько же, сколько коннектор,
/// и на диск не пишется (D2).
final class McpClientConnector implements McpConnector {
  McpClientConnector({
    required McpTransports transports,
    required this.clock,
    this.options = const McpClientOptions(),
    McpEraCache? eraCache,
    Random? random,
  }) : _factories = transports,
       eraCache = eraCache ?? McpEraCache(),
       // Умолчание нужно только вызывающим, которым джиттер безразличен;
       // хосты передают свой `Random` явно (PKG-6, задача 6.4).
       random = random ?? Random();

  final McpTransports _factories;
  final Clock clock;
  final McpClientOptions options;
  final McpEraCache eraCache;

  /// Источник джиттера задержки повтора: `r ∈ [0, 1)` (D11).
  final Random random;

  @override
  Set<String> get transports => _factories.keys;

  @override
  Future<McpSessionTools> connect(McpConnectRequest request) async {
    final session = _ConnectedSession(this, request);
    await session._start();
    return session;
  }
}

/// Почему сервер в состоянии `disabled`: от причины зависит, что с ним
/// делает `replaceServers` и `setEnabled` (D10, D11).
enum _Off {
  /// `enabled: false` в конфиге.
  config,

  /// `setEnabled(name, false)` (`/mcp disable`) — только эта сессия.
  command,

  /// Коллизия имён инструментов: сервер закрыт, пробуется заново при
  /// `enable` и `replaceServers`.
  collision,
}

/// Один сервер сессии: состояние автомата, соединение, таймер повтора и
/// набор инструментов (D11).
///
/// Реализует [McpToolCaller]: инструменты сервера вызывают его, а он решает,
/// отдать вызов текущему соединению или вернуть «не подключён». Так
/// `McpTool` не держит мёртвый клиент после переподключения.
final class _Server implements McpToolCaller {
  _Server(this._session, this.config);

  final _ConnectedSession _session;

  /// Описание сервера, как оно пришло коннектору (с шаблонами секретов:
  /// значения раскрываются на попытку и здесь не хранятся, D11).
  ///
  /// Не `final`: правка одних таймаутов (`call_timeout`, `connect_timeout`)
  /// не переподключает сервер, но следующая попытка берёт новые значения.
  McpServerConfig config;

  /// Состояние выбрано человеком (`setEnabled`): оно действует, пока элемент
  /// сервера в конфиге не изменился (R6-2).
  var manual = false;

  /// Сервер уходит из списка (`replaceServers`): его не находят `reconnect` и
  /// `setEnabled`, а результат идущей попытки закрывается.
  var removed = false;

  var state = McpServerState.connecting;
  _Off? off;

  /// Текущее соединение; `null` у `failed`, `disabled` и до первого успеха.
  McpClient? client;

  /// Растёт при каждой попытке, закрытии и выключении: результат с чужим
  /// номером устарел и закрывается без регистрации (счётчик поколений на
  /// сервер, D11).
  var generation = 0;

  /// Сбои подряд: номер следующей задержки (`attempt` формулы) и счётчик для
  /// логов `failed`/`retry`.
  var failures = 0;
  DateTime? connectedAt;
  DateTime? retryAt;
  ClockTimer? timer;
  String? lastError;

  /// Последний полный список определений сервера.
  List<McpToolDefinition> latest = const [];
  var dirty = false;

  /// Зарегистрированные инструменты, прошедшие проверку коллизий; у упавшего
  /// сервера остаются прежними.
  List<McpTool> tools = const [];
  List<McpTool>? built;

  @override
  Future<McpCallOutcome> callTool(
    String name,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
    String? toolCallId,
  }) {
    final current = client;
    if (state == McpServerState.connected && current != null) {
      return current.callTool(
        name,
        arguments,
        cancel: cancel,
        toolCallId: toolCallId,
      );
    }
    // Транспорт не трогаем: сервер недоступен, а ждать повтора внутри вызова
    // значило бы держать ход (D11).
    final left = retryAt?.difference(_session._now);
    final seconds = left == null
        ? 1
        : max(1, (left.inMilliseconds / 1000).round());
    return Future.value(
      McpCallError(
        'MCP server ${config.name} is not connected (retry in ${seconds}s). '
        'Continue without it or try later.',
      ),
    );
  }

  McpServerSummary summary() => McpServerSummary(
    name: config.name,
    toolCount: state == McpServerState.disabled ? 0 : tools.length,
    origin: config.origin,
    transport: config.transport,
    state: state,
    lastError: lastError,
    retryIn: state == McpServerState.failed && retryAt != null
        ? _nonNegative(retryAt!.difference(_session._now))
        : null,
  );
}

Duration _nonNegative(Duration value) =>
    value.isNegative ? Duration.zero : value;

final class _ConnectedSession implements McpSessionTools {
  _ConnectedSession(this._owner, this._request);

  final McpClientConnector _owner;
  final McpConnectRequest _request;

  /// Серверы в порядке списка — в любом состоянии (D11).
  var _servers = <_Server>[];
  var _closed = false;

  /// Закрытие сессии: обрывает рукопожатия, висящие до `connectTimeout`.
  final _abort = Completer<void>();

  /// Отмена сессии одним будущим: токен запроса (`close()` сессии рантайма,
  /// `dispose()`) или `close()` коннектора. Один подписчик на сессию, а не
  /// новые на каждую попытку: раскрытие секретов и рукопожатие ждут его через
  /// `Future.any`; сам `Future.any` оставляет по подписке на попытку до
  /// закрытия сессии (они ничего не держат, кроме замыкания), а подписок на
  /// токене запроса остаётся одна.
  late final Future<void> _cancelled = Future.any<void>([
    _request.cancel.onCancel,
    _abort.future,
  ]);

  /// Набор инструментов изменился без нового подключения (выключение,
  /// коллизия): следующий `takeUpdate` вернёт его.
  var _refreshPending = false;

  /// Идёт первое подключение: наборы инструментов регистрирует `_start` одним
  /// проходом в порядке списка, поэтому `takeUpdate` по ним не нужен.
  var _starting = false;

  DateTime get _now => _owner.clock.now();

  /// Сессия закрыта или токен запроса отменён (`close()` сессии,
  /// `dispose()` рантайма): новые попытки и таймеры не создаются.
  bool get _dead => _closed || _request.cancel.isCancelled;

  /// Первое подключение: серверы параллельно, ответ ждёт только первую
  /// попытку каждого (D11); затем регистрация в порядке списка.
  Future<void> _start() async {
    _servers = [for (final c in _request.servers) _server(c)];
    _starting = true;
    await Future.wait([
      for (final s in _servers)
        if (s.state == McpServerState.connecting) _attempt(s),
    ]);
    _starting = false;
    if (_dead) {
      // Токен отменён во время первых попыток: подключившиеся до отмены
      // серверы без владельца закрываются, возвращать их незачем.
      await close();
      return;
    }
    final rejected = _resolve();
    await Future.wait([for (final s in rejected) _closeClient(s)]);
  }

  _Server _server(McpServerConfig config) {
    final server = _Server(this, config);
    if (!config.enabled) {
      // Без подключения и без процесса (D10); начальное состояние не
      // логируется как переход.
      server
        ..state = McpServerState.disabled
        ..off = _Off.config;
    }
    return server;
  }

  void _log(
    LogLevel level,
    String event,
    _Server server,
    Map<String, Object?> fields,
  ) => _request.logger.log(
    level,
    event,
    fields: {
      'session_id': _request.sessionId.value,
      'server': server.config.name,
      ...fields,
    },
  );

  void _setState(_Server server, McpServerState next) {
    final previous = server.state;
    if (previous == next) {
      return;
    }
    server.state = next;
    _log(LogLevel.debug, 'mcp.server.state', server, {
      'from': previous.name,
      'to': next.name,
    });
  }

  // --- автомат -----------------------------------------------------------

  /// Одна попытка подключения [server]: раскрытие секретов, транспорт,
  /// рукопожатие. Не бросает: итог — состояние `connected` или `failed` с
  /// таймером повтора (D11).
  ///
  /// [register] — зарегистрировать инструменты сразу (`reconnect`,
  /// `setEnabled`, `replaceServers`: ход не идёт); без него новый набор ждёт
  /// `takeUpdate` на границе шага (таймерный повтор).
  Future<void> _attempt(_Server server, {bool register = false}) async {
    if (_dead) {
      return;
    }
    server.timer?.cancel();
    server
      ..timer = null
      ..retryAt = null
      ..off = null;
    final generation = ++server.generation;
    bool stale() => _dead || server.removed || server.generation != generation;
    _setState(server, McpServerState.connecting);
    try {
      final (client, failure) = await _connectOnce(server, stale);
      if (client != null) {
        if (stale()) {
          // `close()` пришёл, пока подключались (или подключение заменено
          // более новым): соединение без владельца закрываем сразу.
          await _closeQuietly(client);
          return;
        }
        _connected(server, client, register: register);
      } else if (failure != null && !stale()) {
        _fail(server, failure);
      } else if (failure == null && server.generation == generation) {
        // Попытка прервана отменой токена сессии: повтора не будет, а
        // состояние не должно застрять в `connecting`.
        server.lastError = 'connection cancelled';
        _setState(server, McpServerState.failed);
      }
    } on Object catch (error) {
      if (!stale()) {
        _fail(server, 'unexpected error: ${error.runtimeType}');
      }
    }
  }

  /// Открывает транспорт и подключает клиента. Результат — клиент или
  /// причина сбоя; `(null, null)` — попытка отброшена (сессия закрыта).
  Future<(McpClient?, String?)> _connectOnce(
    _Server server,
    bool Function() stale,
  ) async {
    final generation = server.generation;
    var effective = server.config;
    // Только серверы конфига: `${secret:…}` в серверах `session/new` —
    // литерал, функция раскрытия для них не вызывается (agent-secrets;
    // защита в глубину поверх фильтра ядра).
    if (_request.expandSecrets case final expand?
        when server.config.origin == McpServerOrigin.config &&
            server.config.secretValues.isNotEmpty) {
      // Секреты раскрываются заново перед каждой попыткой; значение живёт
      // только в `effective` этой попытки (D11).
      // Ожидание ограничено отменой сессии: хранилище, зависшее на ключе,
      // не должно держать `dispose()` и `close()`; позднее значение
      // отбрасывается.
      final expanding = expand(server.config);
      try {
        final expanded = await Future.any<McpServerConfig?>([
          expanding,
          _cancelled.then<McpServerConfig?>((_) => null),
        ]);
        if (expanded == null) {
          unawaited(expanding.then<void>((_) {}, onError: (Object _) {}));
          return (null, null);
        }
        effective = expanded;
      } on McpSecretsException catch (error) {
        return (null, error.reason);
      }
      if (stale()) {
        return (null, null);
      }
    }
    final factory = _owner._factories[effective.transport];
    if (factory == null) {
      return (null, 'transport ${effective.transport} is not available');
    }
    McpTransport? transport;
    try {
      transport = await factory.open(
        effective,
        cwd: _request.cwd,
        cancel: _request.cancel,
        // Транспорт не знает сессии: `session_id` записей — от логгера (D13).
        logger: BoundLogger(_request.logger, {
          'session_id': _request.sessionId.value,
        }),
      );
      if (stale()) {
        await transport.close();
        return (null, null);
      }
      final connecting = McpClient.connect(
        server: effective,
        transport: transport,
        clock: _owner.clock,
        logger: _request.logger,
        sessionId: _request.sessionId,
        options: _owner.options,
        eraCache: _owner.eraCache,
        // Записи `failed`/`retry` ведёт супервизор: он считает сбои подряд.
        logFailures: false,
        onToolsChanged: (definitions) {
          if (server.generation == generation) {
            server
              ..latest = definitions
              ..dirty = true;
          }
        },
        onClosed: (closed) {
          if (server.generation == generation && !_dead) {
            _dropped(server, closed);
          }
        },
      );
      // Отмена сессии (`close()`, `dispose()`) прерывает рукопожатие: сервер,
      // зависший до `connectTimeout`, не должен держать закрытие сессии.
      final client = await Future.any<McpClient?>([
        connecting,
        _cancelled.then<McpClient?>((_) => null),
      ]);
      if (client == null) {
        await transport.close();
        // Клиент, который достроится или упадёт позже, никому не нужен.
        unawaited(
          connecting.then<void>((late) => late.close(), onError: (Object _) {}),
        );
        return (null, null);
      }
      return (client, null);
    } on McpConnectException catch (error) {
      // Клиент уже закрыл транспорт; причина — без текстов сервера (D13).
      return (null, error.reason);
    } on McpTransportException catch (error) {
      return (null, error.message);
    } on Object catch (error) {
      // Чужое исключение фабрики или клиента не должно лишить сессию
      // остальных серверов (D6): сбой — только этого сервера.
      await _closeTransportQuietly(transport);
      return (null, 'unexpected error: ${error.runtimeType}');
    }
  }

  void _connected(_Server server, McpClient client, {required bool register}) {
    server
      ..client = client
      ..connectedAt = _now
      ..lastError = null;
    final fresh = client.tools;
    final same = _sameDefinitions(server.latest, fresh);
    server.latest = fresh;
    _setState(server, McpServerState.connected);
    if (register) {
      server
        ..dirty = false
        ..built = null;
      final rejected = _resolve({server});
      for (final s in rejected) {
        unawaited(_closeClient(s));
      }
      _refreshPending = true;
    } else if (!same && !_starting) {
      // Новый набор после переподключения доходит до реестра через
      // `takeUpdate` на границе шага (D11).
      server.dirty = true;
    }
  }

  /// Соединение оборвалось само (процесс вышел, транспорт закрыт).
  void _dropped(_Server server, McpTransportClosed closed) {
    final lived = server.connectedAt == null
        ? null
        : _now.difference(server.connectedAt!);
    final dead = server.client;
    server.client = null;
    if (dead != null) {
      unawaited(_closeQuietly(dead));
    }
    _fail(server, closed.reason, lived: lived);
  }

  /// Сбой попытки или соединения: состояние `failed`, лог и таймер повтора
  /// `min(30 с, 2^attempt с × (1 + 0.2·r))` (D11).
  ///
  /// [lived] — сколько прожило оборвавшееся соединение: только если оно
  /// продержалось не меньше 10 с, счётчик начинается заново.
  void _fail(_Server server, String reason, {Duration? lived}) {
    if (lived != null && lived >= _stableConnection) {
      server.failures = 0;
    }
    server.generation++;
    final text = truncateRunes(reason, _lastErrorLimit);
    server.lastError = text;
    final attempt = server.failures;
    server.failures++;
    final failures = server.failures;
    final jitter = _owner.random.nextDouble();
    // Показатель ограничен заранее: 2^attempt при долгой серии сбоев не
    // должен переполнять число до взятия минимума.
    final base = pow(2, min(attempt, 10)) * 1000 * (1 + 0.2 * jitter);
    final delay = Duration(
      milliseconds: min(_maxRetryDelay.inMilliseconds, base.round()),
    );
    server.retryAt = _now.add(delay);
    _setState(server, McpServerState.failed);
    if (failures == 1 || failures % 10 == 0) {
      _log(LogLevel.warning, 'mcp.server.failed', server, {
        'transport': server.config.transport,
        'reason': text,
      });
    } else {
      _log(LogLevel.info, 'mcp.server.retry', server, {
        'attempt': failures,
        'delay_ms': delay.inMilliseconds,
      });
    }
    server.timer?.cancel();
    server.timer = _owner.clock.timer(delay, () {
      if (!_dead && server.state == McpServerState.failed) {
        unawaited(_attempt(server));
      }
    });
  }

  /// Выключает сервер: транспорт закрыт, таймер снят, инструменты убраны.
  Future<void> _disable(_Server server, _Off why, String? error) async {
    server.timer?.cancel();
    server.generation++;
    server
      ..timer = null
      ..retryAt = null
      ..off = why
      ..lastError = error
      ..tools = const []
      ..latest = const []
      ..built = null
      ..dirty = false;
    _setState(server, McpServerState.disabled);
    _refreshPending = true;
    await _closeClient(server);
  }

  Future<void> _closeClient(_Server server) async {
    final client = server.client;
    server.client = null;
    if (client != null) {
      await _closeLogged(server, client);
    }
  }

  Future<void> _closeQuietly(McpClient client) async {
    try {
      await client.close();
    } on Object {
      // Клиент уже сломан: закрывать нечего.
    }
  }

  Future<void> _closeTransportQuietly(McpTransport? transport) async {
    try {
      await transport?.close();
    } on Object {
      // Транспорт уже сломан: закрывать нечего.
    }
  }

  /// Закрывает клиента; сбой закрытия — запись в лог, а не исключение: смена
  /// набора не должна падать из-за процесса, который уже мёртв.
  Future<void> _closeLogged(_Server server, McpClient client) =>
      client.close().catchError((Object error) {
        _log(LogLevel.warning, 'mcp.server.failed', server, {
          'transport': server.config.transport,
          'reason': 'closing failed: ${error.runtimeType}',
        });
      });

  // --- порт ---------------------------------------------------------------

  @override
  List<AgentTool> get tools => [
    for (final server in _servers)
      if (server.state != McpServerState.disabled) ...server.tools,
  ];

  @override
  List<McpServerSummary> get servers => [
    for (final server in _servers) server.summary(),
  ];

  /// Строит `McpTool` сервера, если определения ещё не превращались в
  /// инструменты (логи `mcp.tool.invalid` — один раз на набор).
  List<McpTool> _build(_Server server) => server.built ??= [
    for (final definition in server.latest)
      ?McpTool.create(
        server: server.config.name,
        definition: definition,
        client: server,
        logger: _request.logger,
        sessionId: _request.sessionId,
      ),
  ];

  /// Регистрация в порядке списка: сервер, чей инструмент пришёл позже,
  /// отключается целиком (D6). Возвращает отключённые на этом проходе; их
  /// клиентов закрывает вызывающий.
  ///
  /// [changed] — серверы, чей набор только что обновлён или подключён: они
  /// занимают имена последними, поэтому коллизию обновления отключает сервер,
  /// приславший обновление, а не более поздний по списку.
  List<_Server> _resolve([Set<_Server> changed = const {}]) {
    final owners = <String, String>{};
    final rejected = <_Server>[];
    final live = [
      for (final s in _servers)
        if (s.state != McpServerState.disabled) s,
    ];
    final order = [
      ...live.where((s) => !changed.contains(s)),
      ...live.where(changed.contains),
    ];
    for (final server in order) {
      final built = _build(server);
      final claims = <String>{};
      String? reason;
      String? collided;
      for (final tool in built) {
        final name = tool.name;
        if (_request.reservedNames.contains(name)) {
          reason = 'tool name $name collides with built-in tool $name';
        } else if (owners[name] case final other?) {
          reason = 'tool name $name collides with MCP server "$other"';
        } else if (!claims.add(name)) {
          reason =
              'tool name $name collides with another tool of MCP server '
              '"${server.config.name}"';
        }
        if (reason != null) {
          collided = name;
          break;
        }
      }
      if (reason != null) {
        server.timer?.cancel();
        server.generation++;
        server
          ..timer = null
          ..retryAt = null
          ..off = _Off.collision
          ..lastError = truncateRunes(
            'tool name collision: $collided',
            _lastErrorLimit,
          )
          ..tools = const []
          ..built = null
          ..dirty = false;
        _setState(server, McpServerState.disabled);
        rejected.add(server);
        _log(LogLevel.warning, 'mcp.server.failed', server, {
          'transport': server.config.transport,
          'reason': reason,
        });
        continue;
      }
      server.tools = built;
      for (final name in claims) {
        owners[name] = server.config.name;
      }
    }
    return rejected;
  }

  @override
  McpToolsUpdate? takeUpdate() {
    final dirty = [
      for (final server in _servers)
        if (server.dirty && server.state != McpServerState.disabled) server,
    ];
    if (dirty.isEmpty && !_refreshPending) {
      return null;
    }
    _refreshPending = false;
    final before = {
      for (final server in dirty)
        server: {for (final t in server.tools) t.name},
    };
    for (final server in dirty) {
      server
        ..dirty = false
        ..built = null;
    }
    final rejected = _resolve(dirty.toSet());
    for (final server in rejected) {
      unawaited(_closeClient(server));
    }
    for (final server in dirty) {
      if (server.state == McpServerState.disabled) {
        continue;
      }
      final now = {for (final t in server.tools) t.name};
      final was = before[server]!;
      _log(LogLevel.info, 'mcp.tools.changed', server, {
        'added': (now.difference(was).toList()..sort()),
        'removed': (was.difference(now).toList()..sort()),
      });
    }
    return McpToolsUpdate(tools: tools, servers: servers);
  }

  /// Приводит серверы к [servers] (D10, D11; порт `McpSessionTools`).
  ///
  /// Почему сравнение по `sameConnection`: сервер с тем же `name`, но другими
  /// `command`, `args`, `env` или `url`, — другой сервер, и держать процесс
  /// со старыми параметрами нельзя (в `env` могут быть новые секреты).
  /// Совпавший остаётся как есть: перезапуск процесса стёр бы его состояние и
  /// отнял бы инструменты у модели без причины. Смена `enabled` — тоже другой
  /// сервер: `true → false` закрывает, `false → true` подключает новый.
  ///
  /// Совпавший сервер в `failed` будится сразу (OQ8), а отключённый
  /// коллизией пробуется заново: то, что его вытесняло, могло исчезнуть.
  /// Отключённый командой `/mcp disable` остаётся выключенным, пока элемент
  /// этого сервера в конфиге не изменился (R6-2): правка самого сервера — в
  /// том числе одних таймаутов — начинает с состояния из конфига, то есть
  /// сервер, которого касался человек, при правке таймаутов переподключается.
  /// Правка таймаутов нетронутого сервера соединение не сбрасывает.
  ///
  /// Порядок: сначала закрываются исчезнувшие и изменившиеся, затем
  /// параллельно подключаются новые; список строится в порядке [servers].
  /// Новые серверы занимают имена инструментов последними (как обновление
  /// `list_changed`, D6): коллизия отключает новый сервер, а не работающий.
  @override
  Future<void> replaceServers(List<McpServerConfig> servers) async {
    if (_closed) {
      return;
    }
    final current = {for (final s in _servers) s.config.name: s};
    final next = <_Server>[];
    final toStart = <_Server>[];
    final kept = <_Server>{};
    final names = <String>{};
    for (final config in servers) {
      if (!names.add(config.name)) {
        continue;
      }
      final old = current[config.name];
      // R6-2: ручной выбор действует, пока элемент сервера не изменился —
      // ни параметры соединения, ни `enabled`, ни таймауты. Правка одних
      // таймаутов у сервера, которого человек не трогал, соединение не
      // сбрасывает.
      final sameElement =
          old != null &&
          old.config.sameConnection(config) &&
          old.config.enabled == config.enabled;
      final sameTimeouts =
          old != null &&
          old.config.callTimeout == config.callTimeout &&
          old.config.connectTimeout == config.connectTimeout;
      if (old != null && sameElement && (sameTimeouts || !old.manual)) {
        old.config = config;
        kept.add(old);
        next.add(old);
        if (old.state == McpServerState.failed || old.off == _Off.collision) {
          toStart.add(old);
        }
      } else {
        final fresh = _server(config);
        next.add(fresh);
        if (fresh.state == McpServerState.connecting) {
          toStart.add(fresh);
        }
      }
    }
    final leaving = [
      for (final s in _servers)
        if (!kept.contains(s)) s,
    ];
    for (final s in leaving) {
      // Флаг до первого `await`: параллельные `setEnabled`/`reconnect` и
      // идущая попытка видят, что сервер уходит, и не оживляют его.
      s.removed = true;
      s.timer?.cancel();
      s
        ..timer = null
        ..generation += 1;
    }
    await Future.wait([for (final s in leaving) _closeClient(s)]);
    _servers = next;
    await Future.wait([for (final s in toStart) _attempt(s, register: false)]);
    if (_closed) {
      // `close()` пришёл, пока подключались: процессы без владельца не
      // оставляем (результат устаревших попыток закрыт в `_attempt`).
      await Future.wait([for (final s in _servers) _closeClient(s)]);
      return;
    }
    final fresh = toStart.toSet();
    for (final s in fresh) {
      s
        ..dirty = false
        ..built = null;
    }
    final rejected = _resolve(fresh);
    await Future.wait([for (final s in rejected) _closeClient(s)]);
    _refreshPending = true;
  }

  _Server? _find(String name) {
    for (final server in _servers) {
      if (server.config.name == name && !server.removed) {
        return server;
      }
    }
    return null;
  }

  @override
  Future<void> reconnect(String name) async {
    final server = _find(name);
    if (_dead || server == null || server.state == McpServerState.disabled) {
      return;
    }
    server.timer?.cancel();
    server
      ..timer = null
      ..generation += 1;
    await _closeClient(server);
    await _attempt(server, register: true);
  }

  @override
  Future<void> setEnabled(String name, bool enabled) async {
    final server = _find(name);
    if (_dead || server == null) {
      return;
    }
    if (!enabled) {
      if (server.state != McpServerState.disabled) {
        server.manual = true;
        await _disable(server, _Off.command, 'disabled by /mcp disable');
      }
      return;
    }
    if (server.state == McpServerState.disabled) {
      // Действие человека: R0-1 к нему не относится (D11).
      server.manual = true;
      await _attempt(server, register: true);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (!_abort.isCompleted) {
      _abort.complete();
    }
    for (final server in _servers) {
      server.timer?.cancel();
      server
        ..timer = null
        ..generation += 1;
      if (server.state == McpServerState.connecting) {
        // Прерванная попытка не оставляет `connecting`. Перехода в лог
        // `mcp.server.state` нет намеренно: сессия закрыта, а логгер сессии
        // к этому моменту может принадлежать уже закрытому хосту; повтора
        // нет тоже.
        server
          ..state = McpServerState.failed
          ..lastError = 'connection cancelled';
      }
    }
    await Future.wait([for (final s in _servers) _closeClient(s)]);
  }
}

/// Одинаковы ли два набора определений: после переподключения неизменный
/// набор не обновляет реестр и не ломает кэш префикса (§17.5.12).
bool _sameDefinitions(List<McpToolDefinition> a, List<McpToolDefinition> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (canonicalJson(a[i].raw) != canonicalJson(b[i].raw)) {
      return false;
    }
  }
  return true;
}
