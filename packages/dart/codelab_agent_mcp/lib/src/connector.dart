import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'mcp_client.dart';
import 'mcp_tool.dart';
import 'protocol.dart';

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

/// Подключение MCP-серверов сессии — реализация порта ядра `McpConnector`
/// (`AgentCoreServices.mcp`; design.md change `add-agent-mcp-client`, D6).
///
/// Почему здесь, а не в ядре: ядро не знает протокола MCP, а регистрация
/// требует `McpClient` и `McpTool`. Коннектор подключает серверы параллельно,
/// но регистрирует инструменты строго в порядке списка, поэтому при коллизии
/// имён побеждает сервер, стоящий раньше, независимо от порядка подключения
/// (HOST-5, E-05, детерминизм фикстур).
///
/// Как использовать: хост создаёт один коннектор на процесс и передаёт его в
/// `AgentCoreServices.mcp`; ядро вызывает [connect] при создании и загрузке
/// сессии. Кэш эпохи HTTP-серверов ([eraCache]) живёт столько же, сколько
/// коннектор, и на диск не пишется (D2).
final class McpClientConnector implements McpConnector {
  McpClientConnector({
    required McpTransports transports,
    required this.clock,
    this.options = const McpClientOptions(),
    McpEraCache? eraCache,
  }) : _factories = transports,
       eraCache = eraCache ?? McpEraCache();

  final McpTransports _factories;
  final Clock clock;
  final McpClientOptions options;
  final McpEraCache eraCache;

  @override
  Set<String> get transports => _factories.keys;

  @override
  Future<McpSessionTools> connect(McpConnectRequest request) async {
    final connecting = await Future.wait([
      for (final server in request.servers) _connectOne(request, server),
    ]);
    final session = _ConnectedSession(request, _connectOne);
    for (final state in connecting) {
      if (state != null) {
        session._states.add(state);
      }
    }
    final rejected = session._resolve();
    await Future.wait([for (final state in rejected) state.client.close()]);
    return session;
  }

  /// Подключает один сервер; `null` — он не подключён и причина уже в логе.
  Future<_ServerState?> _connectOne(
    McpConnectRequest request,
    McpServerConfig server,
  ) async {
    void failed(String reason) => request.logger.log(
      LogLevel.warning,
      'mcp.server.failed',
      fields: {
        'session_id': request.sessionId.value,
        'server': server.name,
        'transport': server.transport,
        'reason': reason,
      },
    );

    final factory = _factories[server.transport];
    if (factory == null) {
      failed('transport ${server.transport} is not available');
      return null;
    }
    McpTransport? transport;
    final state = _ServerState(server);
    try {
      transport = await factory.open(
        server,
        cwd: request.cwd,
        cancel: request.cancel,
        // Транспорт не знает сессии: `session_id` записей — от логгера (D13).
        logger: BoundLogger(request.logger, {
          'session_id': request.sessionId.value,
        }),
      );
      final connecting = McpClient.connect(
        server: server,
        transport: transport,
        clock: clock,
        logger: request.logger,
        sessionId: request.sessionId,
        options: options,
        eraCache: eraCache,
        onToolsChanged: (definitions) {
          state
            ..latest = definitions
            ..dirty = true;
        },
      );
      // Отмена сессии (`close()`, `dispose()`) прерывает рукопожатие: сервер,
      // зависший до `connectTimeout`, не должен держать закрытие сессии.
      final client = await Future.any<McpClient?>([
        connecting,
        request.cancel.onCancel.then<McpClient?>((_) => null),
      ]);
      if (client == null) {
        await transport.close();
        // Клиент, который достроится или упадёт позже, никому не нужен.
        unawaited(
          connecting.then<void>((late) => late.close(), onError: (Object _) {}),
        );
        return null;
      }
      state.client = client;
    } on McpConnectException {
      // Клиент уже записал `mcp.server.failed` и закрыл транспорт.
      return null;
    } on McpTransportException catch (error) {
      failed(error.message);
      return null;
    } on Object catch (error) {
      // Чужое исключение фабрики или клиента не должно лишить сессию
      // остальных серверов (D6): сбой — только этого сервера.
      failed('unexpected error: ${error.runtimeType}');
      try {
        await transport?.close();
      } on Object {
        // Транспорт уже сломан: закрывать нечего.
      }
      return null;
    }
    state.latest = state.client.tools;
    return state;
  }
}

final class _ServerState {
  _ServerState(this.config);

  final McpServerConfig config;
  late McpClient client;

  /// Последний полный список определений сервера.
  List<McpToolDefinition> latest = const [];
  var dirty = false;
  var disabled = false;

  /// Инструменты, прошедшие проверку коллизий, в порядке `tools/list`.
  List<McpTool> tools = const [];
  List<McpTool>? _built;
}

final class _ConnectedSession implements McpSessionTools {
  _ConnectedSession(this._request, this._connectOne);

  final McpConnectRequest _request;

  /// Подключение одного сервера коннектора — им же `replaceServers`
  /// подключает новые серверы, чтобы у них были те же правила и логи.
  final Future<_ServerState?> Function(McpConnectRequest, McpServerConfig)
  _connectOne;
  final _states = <_ServerState>[];
  var _closed = false;

  @override
  List<AgentTool> get tools => [
    for (final state in _states)
      if (!state.disabled) ...state.tools,
  ];

  @override
  List<McpServerSummary> get servers => [
    for (final state in _states)
      if (!state.disabled)
        McpServerSummary(
          name: state.config.name,
          toolCount: state.tools.length,
        ),
  ];

  /// Строит `McpTool` сервера, если определения ещё не превращались в
  /// инструменты (логи `mcp.tool.invalid` — один раз на набор).
  List<McpTool> _build(_ServerState state) => state._built ??= [
    for (final definition in state.latest)
      ?McpTool.create(
        server: state.config.name,
        definition: definition,
        client: state.client,
        logger: _request.logger,
        sessionId: _request.sessionId,
      ),
  ];

  /// Регистрация в порядке списка: сервер, чей инструмент пришёл позже,
  /// отключается целиком (D6). Возвращает отключённые на этом проходе.
  ///
  /// [changed] — серверы, чей набор только что обновлён: они занимают имена
  /// последними, поэтому коллизию обновления отключает сервер, приславший
  /// обновление, а не более поздний по списку.
  List<_ServerState> _resolve([Set<_ServerState> changed = const {}]) {
    final owners = <String, String>{};
    final rejected = <_ServerState>[];
    final order = [
      ..._states.where((s) => !s.disabled && !changed.contains(s)),
      ..._states.where((s) => !s.disabled && changed.contains(s)),
    ];
    for (final state in order) {
      final built = _build(state);
      final claims = <String>{};
      String? reason;
      for (final tool in built) {
        final name = tool.name;
        if (_request.reservedNames.contains(name)) {
          reason = 'tool name $name collides with built-in tool $name';
        } else if (owners[name] case final other?) {
          reason = 'tool name $name collides with MCP server "$other"';
        } else if (!claims.add(name)) {
          reason =
              'tool name $name collides with another tool of MCP server '
              '"${state.config.name}"';
        }
        if (reason != null) {
          break;
        }
      }
      if (reason != null) {
        state
          ..disabled = true
          ..tools = const [];
        rejected.add(state);
        _request.logger.log(
          LogLevel.warning,
          'mcp.server.failed',
          fields: {
            'session_id': _request.sessionId.value,
            'server': state.config.name,
            'transport': state.config.transport,
            'reason': reason,
          },
        );
        continue;
      }
      state.tools = built;
      for (final name in claims) {
        owners[name] = state.config.name;
      }
    }
    return rejected;
  }

  @override
  McpToolsUpdate? takeUpdate() {
    final dirty = [
      for (final state in _states)
        if (state.dirty && !state.disabled) state,
    ];
    if (dirty.isEmpty) {
      return null;
    }
    final before = {
      for (final state in dirty) state: {for (final t in state.tools) t.name},
    };
    for (final state in dirty) {
      state
        ..dirty = false
        .._built = null;
    }
    final rejected = _resolve(dirty.toSet());
    for (final state in rejected) {
      unawaited(
        state.client.close().catchError((Object error) {
          _request.logger.log(
            LogLevel.warning,
            'mcp.server.failed',
            fields: {
              'session_id': _request.sessionId.value,
              'server': state.config.name,
              'transport': state.config.transport,
              'reason': 'closing failed: ${error.runtimeType}',
            },
          );
        }),
      );
    }
    for (final state in dirty) {
      if (state.disabled) {
        continue;
      }
      final now = {for (final t in state.tools) t.name};
      final was = before[state]!;
      _request.logger.log(
        LogLevel.info,
        'mcp.tools.changed',
        fields: {
          'session_id': _request.sessionId.value,
          'server': state.config.name,
          'added': (now.difference(was).toList()..sort()),
          'removed': (was.difference(now).toList()..sort()),
        },
      );
    }
    return McpToolsUpdate(tools: tools, servers: servers);
  }

  /// Приводит серверы к [servers] (D11; порт `McpSessionTools`).
  ///
  /// Почему сравнение по `sameConnection`: сервер с тем же `name`, но другими
  /// `command`, `args`, `env` или `url`, — другой сервер, и держать процесс
  /// со старыми параметрами нельзя (в `env` могут быть новые секреты).
  /// Совпавший остаётся как есть: перезапуск процесса стёр бы его состояние и
  /// отнял бы инструменты у модели без причины.
  ///
  /// Порядок: сначала закрываются исчезнувшие и изменившиеся, затем
  /// параллельно подключаются новые; список строится в порядке [servers].
  /// Новые серверы занимают имена инструментов последними (как обновление
  /// `list_changed`, D6): коллизия отключает новый сервер, а не работающий.
  /// Сервер, отключённый ранее коллизией или не подключившийся, в
  /// подключённых не числится и пробуется снова, если он есть в списке: то,
  /// что его вытесняло, могло исчезнуть.
  @override
  Future<void> replaceServers(List<McpServerConfig> servers) async {
    if (_closed) {
      return;
    }
    final live = {
      for (final state in _states)
        if (!state.disabled) state.config.name: state,
    };
    final kept = <String, _ServerState>{};
    final fresh = <McpServerConfig>[];
    final names = <String>{};
    for (final server in servers) {
      if (!names.add(server.name)) {
        continue;
      }
      final current = live[server.name];
      if (current != null && current.config.sameConnection(server)) {
        kept[server.name] = current;
      } else {
        fresh.add(server);
      }
    }
    final leaving = [
      for (final state in _states)
        if (!state.disabled && kept[state.config.name] != state) state,
    ];
    await Future.wait([for (final state in leaving) _closeLogged(state)]);
    final connected = await Future.wait([
      for (final server in fresh) _connectOne(_request, server),
    ]);
    final added = <String, _ServerState>{
      for (final state in connected) ?state?.config.name: ?state,
    };
    if (_closed) {
      // `close()` пришёл, пока подключались: новые процессы без владельца
      // не оставляем.
      await Future.wait([for (final s in added.values) _closeLogged(s)]);
      return;
    }
    _states
      ..clear()
      ..addAll([
        for (final server in servers)
          if (names.remove(server.name))
            ?(kept[server.name] ?? added[server.name]),
      ]);
    final rejected = _resolve(added.values.toSet());
    await Future.wait([for (final state in rejected) _closeLogged(state)]);
  }

  /// Закрывает сервер; сбой закрытия — запись в лог, а не исключение: смена
  /// набора не должна падать из-за процесса, который уже мёртв.
  Future<void> _closeLogged(_ServerState state) =>
      state.client.close().catchError((Object error) {
        _request.logger.log(
          LogLevel.warning,
          'mcp.server.failed',
          fields: {
            'session_id': _request.sessionId.value,
            'server': state.config.name,
            'transport': state.config.transport,
            'reason': 'closing failed: ${error.runtimeType}',
          },
        );
      });

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await Future.wait([for (final state in _states) state.client.close()]);
  }
}
