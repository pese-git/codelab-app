import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'protocol.dart';

/// Какой эпохи притворяется [FakeMcpServer] (design.md change
/// `add-agent-mcp-client`, D15).
enum FakeMcpEra {
  /// `2026-07-28`: `server/discover`, `_meta` в каждом запросе.
  modern,

  /// `initialize`/`initialized`; на `server/discover` — ошибка или молчание.
  legacy,

  /// Отвечает на `server/discover` как modern и на `initialize` как legacy.
  dualEra,
}

/// Реакция legacy-сервера на пробу `server/discover` (D2, D15).
enum FakeLegacyProbe { methodNotFound, invalidParams, silent }

/// Реакция fake-сервера на `subscriptions/listen` (D5).
enum FakeListen {
  /// Подтверждение `acknowledged` сразу.
  acknowledge,

  /// Молчание: подтверждение можно послать позже через `sendAck`.
  withhold,

  /// Ошибка JSON-RPC вместо подтверждения.
  error,

  /// Успешный ответ (закрытие подписки) вместо подтверждения.
  close,

  /// Поток ответа оборван без ответа.
  abort,
}

/// Описание инструмента fake-сервера.
final class FakeMcpTool {
  const FakeMcpTool(
    this.name, {
    this.description,
    this.inputSchema = const {'type': 'object'},
    this.annotations,
    this.taskSupport,
    this.title,
    this.extra = const {},
  });

  final String name;
  final String? title;
  final String? description;
  final Object? inputSchema;
  final Map<String, Object?>? annotations;
  final String? taskSupport;

  /// Поля поверх остальных, в том числе заведомо неверного типа.
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    'name': name,
    'title': ?title,
    'description': ?description,
    'inputSchema': inputSchema,
    'annotations': ?annotations,
    if (taskSupport != null) 'execution': {'taskSupport': taskSupport},
    ...extra,
  };
}

/// Ответ fake-сервера на `tools/call` по имени инструмента.
sealed class FakeToolResponse {
  const FakeToolResponse();

  /// Обычный `CallToolResult` (без `resultType` — его добавляет эпоха).
  const factory FakeToolResponse.result(Map<String, Object?> result) =
      _FakeResult;

  /// Текстовый `CallToolResult` из одного блока.
  factory FakeToolResponse.text(String text, {bool isError = false}) =>
      _FakeResult({
        'content': [
          {'type': 'text', 'text': text},
        ],
        if (isError) 'isError': true,
      });

  /// Ошибка JSON-RPC.
  const factory FakeToolResponse.error(int code, String message) = _FakeError;

  /// Сырой `result` как есть: ответ не по схеме, `input_required` и т. п.
  const factory FakeToolResponse.raw(Map<String, Object?> result) = _FakeRaw;

  /// Отвечает после завершения [gate] (задержка под управлением теста);
  /// отмена клиента гасит ответ сервера, как требует `cancellation.md`.
  factory FakeToolResponse.gated(Completer<Map<String, Object?>> gate) =>
      _FakeGated(gate);

  /// Сервер падает на этом вызове: транспорт закрывается без ответа.
  const factory FakeToolResponse.crash() = _FakeCrash;
}

final class _FakeResult extends FakeToolResponse {
  const _FakeResult(this.result);

  final Map<String, Object?> result;
}

final class _FakeError extends FakeToolResponse {
  const _FakeError(this.code, this.message);

  final int code;
  final String message;
}

final class _FakeRaw extends FakeToolResponse {
  const _FakeRaw(this.result);

  final Map<String, Object?> result;
}

final class _FakeGated extends FakeToolResponse {
  _FakeGated(this.gate);

  final Completer<Map<String, Object?>> gate;
}

final class _FakeCrash extends FakeToolResponse {
  const _FakeCrash();
}

/// MCP-сервер в памяти для тестов клиента, ядра и фикстур (design.md change
/// `add-agent-mcp-client`, D15).
///
/// Почему свой код: готовые серверы тянут `dart:io` или чужие SDK, а тесты
/// должны быть детерминированы и без сети (PKG-6). Сервер пишется по тексту
/// спецификации MCP: modern `2026-07-28` и legacy `2025-11-25`.
///
/// Как использовать: создать с [era] и инструментами, взять
/// [connect] — клиентскую половину пары транспортов в памяти — и передать её
/// в `McpClient.connect`. Принятые сообщения и сигналы отмены лежат в
/// [requests], [calls], [cancelledRequestIds], [abandoned]; нарушения порядка
/// legacy-рукопожатия — в [violations].
final class FakeMcpServer {
  FakeMcpServer({
    this.era = FakeMcpEra.modern,
    List<FakeMcpTool> tools = const [],
    Map<String, FakeToolResponse> responses = const {},
    this.pageSize = 0,
    this.endlessPages = false,
    this.emptyStringFirstCursor = false,
    this.listChanged = false,
    this.advertiseTools = true,
    this.acknowledgeToolsListChanged = true,
    this.listen = FakeListen.acknowledge,
    this.duplicateAck = false,
    this.notifyDuringFirstList,
    this.supportedVersions = const [modernProtocolVersion],
    this.refuseWithUnsupportedVersion = false,
    this.legacyVersion = legacyRequestedVersion,
    this.legacyProbe = FakeLegacyProbe.methodNotFound,
    this.silentInitialize = false,
    this.declareTaskCalls = false,
    this.probeErrorCode,
    this.pingBeforeInitializeResult = false,
    this.serverName = 'fake-mcp-server',
  }) : _tools = [...tools],
       _responses = {...responses};

  final FakeMcpEra era;
  final int pageSize;
  final bool endlessPages;
  final bool emptyStringFirstCursor;
  final bool listChanged;
  final bool advertiseTools;
  final bool acknowledgeToolsListChanged;
  final FakeListen listen;

  /// Подтверждение подписки приходит дважды подряд.
  final bool duplicateAck;

  /// Во время первого `tools/list` приходит `list_changed`, а набор
  /// становится этим.
  final List<FakeMcpTool>? notifyDuringFirstList;
  final List<String> supportedVersions;
  final bool refuseWithUnsupportedVersion;
  final String legacyVersion;
  final FakeLegacyProbe legacyProbe;
  final bool silentInitialize;
  final bool declareTaskCalls;

  /// Если задан, проба `server/discover` получает ошибку с этим кодом без
  /// `data.supported` (например, `-32020`/`-32021`).
  final int? probeErrorCode;

  /// Legacy: перед ответом на `initialize` сервер шлёт клиенту `ping` с
  /// id `handshake-ping` (окно рукопожатия, `basic/utilities/ping.md`).
  final bool pingBeforeInitializeResult;
  final String serverName;

  final List<FakeMcpTool> _tools;
  final Map<String, FakeToolResponse> _responses;

  /// Все сообщения клиента (запросы и уведомления) в порядке прихода.
  final requests = <Map<String, Object?>>[];

  /// Ответы клиента на запросы сервера (`ping` и т. п.).
  final responsesFromClient = <Map<String, Object?>>[];

  /// Параметры принятых `tools/call`: `{name, arguments}`.
  final calls = <Map<String, Object?>>[];

  /// `requestId` из `notifications/cancelled`.
  final cancelledRequestIds = <Object>[];

  /// Запросы, чей поток ответа закрыл клиент (`abandon`, отмена HTTP).
  final abandoned = <Object>[];

  /// Нарушения порядка рукопожатия клиентом; в корректном тесте пусто.
  final violations = <String>[];

  /// Сколько следующих `tools/list` оборвать без ответа (поток ответа
  /// закрыт, транспорт жив): проверка единственного повтора (D8, D10).
  var abortListResponses = 0;

  /// Сколько следующих `tools/list` оставить без ответа (молчание сервера):
  /// проверка таймаута и сигнала отмены (`cancellation.md`, Timeouts).
  var silentLists = 0;

  /// Сколько следующих `tools/list` ответить ошибкой `-32603`.
  var failListErrors = 0;
  var _firstListSeen = false;
  Object? _listenId;

  /// Сколько раз открыт `subscriptions/listen`.
  var subscriptions = 0;
  var closedTransports = 0;

  /// Заголовки каждого `send` в порядке прихода (HTTP, group 9).
  final sentHeaders = <Map<String, String>>[];

  _FakeTransport? _transport;
  Object? _subscriptionId;
  Object? _silentProbeId;
  var _initialized = false;
  var _pageCounter = 0;
  final _heldCalls = <Object, _FakeGated>{};

  /// Имена методов клиента в порядке прихода.
  List<String> get methods => [
    for (final r in requests)
      if (r['method'] is String) r['method']! as String,
  ];

  /// Клиентская половина новой пары транспортов. [kind] — `stdio` или
  /// `http`: от него зависит сигнал отмены клиента (D8).
  McpTransport connect({String kind = 'stdio'}) {
    final transport = _FakeTransport(this, kind);
    _transport = transport;
    return transport;
  }

  /// Заменяет набор инструментов, если [newTools] задан, и шлёт
  /// `notifications/tools/list_changed`: modern — с `subscriptionId`
  /// ([subscriptionId] подменяет его для проверки чужой подписки), legacy —
  /// без.
  void notifyToolsListChanged({
    List<FakeMcpTool>? newTools,
    Object? subscriptionId,
  }) {
    if (newTools != null) {
      _tools
        ..clear()
        ..addAll(newTools);
    }
    final modern = _isModernConnection;
    _push(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'notifications/tools/list_changed',
        if (modern)
          'params': {
            '_meta': {
              'io.modelcontextprotocol/subscriptionId':
                  subscriptionId ?? _subscriptionId,
            },
          },
      }),
    );
  }

  /// Запрос сервера клиенту (`ping`, `sampling/createMessage`).
  void sendRequest(String method, {required Object id}) =>
      _push(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method}));

  /// Сервер падает: транспорт закрывается с [reason].
  void crash({String reason = 'process exited with code 1'}) =>
      _transport?._closeFromServer(reason);

  /// Поток ответа запроса [id] оборвался, транспорт жив (HTTP).
  void abortResponse(Object id) => _transport?._aborted.add(id);

  /// Поздний ответ на молчаливую пробу `server/discover`.
  void answerSilentProbe() {
    final id = _silentProbeId;
    if (id != null) {
      _push(_discoverResult(id));
    }
  }

  /// Тест вызывает ответ ещё не отвеченного [FakeToolResponse.gated].
  void setResponse(String tool, FakeToolResponse response) =>
      _responses[tool] = response;

  bool get _isModernConnection =>
      era == FakeMcpEra.modern ||
      (era == FakeMcpEra.dualEra && _subscriptionId != null) ||
      (era == FakeMcpEra.dualEra && !_initialized);

  void _push(String text) => _transport?._deliver(text);

  void _handleRaw(String text, Map<String, String> headers) {
    sentHeaders.add(headers);
    final message = jsonDecode(text) as Map<String, Object?>;
    final method = message['method'];
    if (method is! String) {
      responsesFromClient.add(message);
      return;
    }
    requests.add(message);
    final id = message['id'];
    final params = (message['params'] as Map?)?.cast<String, Object?>() ?? {};
    if (id == null) {
      _handleNotification(method, params);
      return;
    }
    _handleRequest(id, method, params);
  }

  void _handleNotification(String method, Map<String, Object?> params) {
    if (method == 'notifications/initialized') {
      _initialized = true;
    } else if (method == 'notifications/cancelled') {
      final requestId = params['requestId'];
      if (requestId != null) {
        cancelledRequestIds.add(requestId);
        _heldCalls.remove(requestId);
      }
    }
  }

  void _handleRequest(Object id, String method, Map<String, Object?> params) {
    final meta = (params['_meta'] as Map?)?.cast<String, Object?>();
    final hasMeta = meta != null && meta.containsKey(_versionKey);
    switch (method) {
      case 'server/discover':
        return _discover(id, meta);
      case 'initialize':
        if (era == FakeMcpEra.modern) {
          return _error(id, -32601, 'Method not found: initialize');
        }
        return _initialize(id);
      case 'subscriptions/listen' when _modernRequest(id, hasMeta, meta):
        return _listen(id);
      case 'tools/list' when _modernOrLegacy(id, hasMeta, meta):
        return _list(id, params);
      case 'tools/call' when _modernOrLegacy(id, hasMeta, meta):
        return _call(id, params);
      default:
        if (_modernOrLegacy(id, hasMeta, meta)) {
          _error(id, -32601, 'Method not found: $method');
        }
    }
  }

  static const _versionKey = 'io.modelcontextprotocol/protocolVersion';

  bool get _modernServing =>
      era == FakeMcpEra.modern || era == FakeMcpEra.dualEra;

  bool _modernRequest(Object id, bool hasMeta, Map<String, Object?>? meta) =>
      _modernOrLegacy(id, hasMeta, meta);

  /// Проверяет `_meta` modern-запроса (D15) или порядок legacy-рукопожатия.
  /// `false` — ответ-ошибка уже отправлен.
  bool _modernOrLegacy(Object id, bool hasMeta, Map<String, Object?>? meta) {
    final modernRequest = hasMeta && _modernServing;
    if (era == FakeMcpEra.modern || modernRequest) {
      if (!hasMeta) {
        _error(id, -32602, 'Missing required _meta fields');
        return false;
      }
      final version = meta![_versionKey];
      if (version != modernProtocolVersion) {
        _error(
          id,
          mcpUnsupportedProtocolVersion,
          'Unsupported protocol version',
          data: {'supported': supportedVersions, 'requested': version},
        );
        return false;
      }
      return true;
    }
    if (!_initialized) {
      violations.add('request before notifications/initialized');
    }
    return true;
  }

  void _discover(Object id, Map<String, Object?>? meta) {
    if (era == FakeMcpEra.legacy) {
      switch (legacyProbe) {
        case FakeLegacyProbe.silent:
          _silentProbeId = id;
        case FakeLegacyProbe.methodNotFound:
          _error(id, -32601, 'Method not found: server/discover');
        case FakeLegacyProbe.invalidParams:
          _error(id, -32602, 'Invalid params');
      }
      return;
    }
    if (probeErrorCode case final code?) {
      _error(id, code, 'Probe rejected');
      return;
    }
    if (refuseWithUnsupportedVersion) {
      _error(
        id,
        mcpUnsupportedProtocolVersion,
        'Unsupported protocol version',
        data: {'supported': supportedVersions, 'requested': meta?[_versionKey]},
      );
      return;
    }
    _push(_discoverResult(id));
  }

  String _discoverResult(Object id) => jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'result': {
      'resultType': 'complete',
      'supportedVersions': supportedVersions,
      'capabilities': {
        if (advertiseTools) 'tools': {if (listChanged) 'listChanged': true},
      },
      '_meta': {
        'io.modelcontextprotocol/serverInfo': {
          'name': serverName,
          'version': '1.0.0',
        },
      },
    },
  });

  void _initialize(Object id) {
    if (silentInitialize) {
      return;
    }
    if (pingBeforeInitializeResult) {
      sendRequest('ping', id: 'handshake-ping');
    }
    _result(id, {
      'protocolVersion': legacyVersion,
      'capabilities': {
        if (advertiseTools) 'tools': {if (listChanged) 'listChanged': true},
        if (declareTaskCalls)
          'tasks': {
            'requests': {
              'tools': {'call': <String, Object?>{}},
            },
          },
      },
      'serverInfo': {'name': serverName, 'version': '1.0.0'},
    }, modern: false);
  }

  void _listen(Object id) {
    subscriptions++;
    _subscriptionId = id;
    _listenId = id;
    switch (listen) {
      case FakeListen.acknowledge:
        sendAck();
        if (duplicateAck) {
          sendAck();
        }
      case FakeListen.withhold:
        break;
      case FakeListen.error:
        _error(id, -32603, 'Internal error');
      case FakeListen.close:
        closeSubscription();
      case FakeListen.abort:
        abortResponse(id);
    }
  }

  /// Подтверждение подписки (`notifications/subscriptions/acknowledged`);
  /// можно послать позже, чтобы проверить ack после таймаута.
  void sendAck() => _push(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'notifications/subscriptions/acknowledged',
      'params': {
        '_meta': {'io.modelcontextprotocol/subscriptionId': _listenId},
        'notifications': {
          if (acknowledgeToolsListChanged) 'toolsListChanged': true,
        },
      },
    }),
  );

  /// Сервер корректно закрывает подписку (`subscriptions.md`,
  /// «Graceful Closure»).
  void closeSubscription() => _push(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': _listenId,
      'result': {
        'resultType': 'complete',
        '_meta': {'io.modelcontextprotocol/subscriptionId': _listenId},
      },
    }),
  );

  /// Сервер снимает подписку уведомлением `notifications/cancelled` с id
  /// `subscriptions/listen` (`cancellation.md`: сервер MUST слать его при
  /// разрыве потока подписки).
  void cancelSubscription() => _push(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'notifications/cancelled',
      'params': {'requestId': _listenId},
    }),
  );

  /// Произвольный текст клиенту (пакеты, мусор).
  void pushRaw(String text) => _push(text);

  /// Ошибка чтения потока транспорта.
  void breakStream() => _transport?._incoming.addError(StateError('broken'));

  bool _isModernParams(Map<String, Object?> params) =>
      (params['_meta'] as Map?)?.containsKey(_versionKey) ?? false;

  void _list(Object id, Map<String, Object?> params) {
    if (abortListResponses > 0) {
      abortListResponses--;
      abortResponse(id);
      return;
    }
    if (silentLists > 0) {
      silentLists--;
      return;
    }
    if (failListErrors > 0) {
      failListErrors--;
      _error(id, -32603, 'Internal error');
      return;
    }
    final modern = _isModernParams(params);
    final cursor = params['cursor'];
    String? next;
    List<FakeMcpTool> page;
    if (endlessPages) {
      page = [..._tools];
      next = 'page-${++_pageCounter}';
    } else if (emptyStringFirstCursor) {
      // Курсор непрозрачен: пустая строка — допустимый курсор (D5).
      if (cursor == null) {
        page = _tools.take(1).toList();
        next = '';
      } else {
        page = _tools.skip(1).toList();
      }
    } else if (pageSize > 0) {
      final start = cursor is String && cursor.startsWith('o')
          ? int.parse(cursor.substring(1))
          : 0;
      final end = (start + pageSize).clamp(0, _tools.length);
      page = _tools.sublist(start, end);
      if (end < _tools.length) {
        next = 'o$end';
      }
    } else {
      page = [..._tools];
    }
    final body = {
      'tools': [for (final t in page) t.toJson()],
      'nextCursor': ?next,
    };
    if (notifyDuringFirstList case final fresh? when !_firstListSeen) {
      _firstListSeen = true;
      notifyToolsListChanged(newTools: fresh);
    }
    _result(id, body, modern: modern);
  }

  void _call(Object id, Map<String, Object?> params) {
    final modern = _isModernParams(params);
    final name = params['name'] as String? ?? '';
    calls.add({
      'name': name,
      'arguments': (params['arguments'] as Map?)?.cast<String, Object?>() ?? {},
    });
    final response = _responses[name];
    switch (response) {
      case null:
        _result(id, {
          'content': [
            {'type': 'text', 'text': 'ok'},
          ],
        }, modern: modern);
      case _FakeResult(:final result):
        _result(id, result, modern: modern);
      case _FakeError(:final code, :final message):
        _error(id, code, message);
      case _FakeRaw(:final result):
        _push(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
      case final _FakeGated gated:
        _heldCalls[id] = gated;
        gated.gate.future.then((result) {
          // Отменённый запрос сервер не отвечает (`cancellation.md`, п. 3);
          // но тест может проверить и поздний ответ — для этого он сам
          // вызывает [answerLate].
          if (_heldCalls.remove(id) != null) {
            _result(id, result, modern: modern);
          }
        });
      case _FakeCrash():
        crash();
    }
  }

  /// Поздний ответ на вызов, уже отменённый клиентом: нарушение
  /// `cancellation.md`, п. 3 допустимо («servers MAY …»), клиент обязан его
  /// игнорировать (п. 5).
  void answerLate(Object id, Map<String, Object?> result) =>
      _result(id, result, modern: _isModernConnection);

  void _result(
    Object id,
    Map<String, Object?> result, {
    required bool modern,
  }) => _push(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'result': {if (modern) 'resultType': 'complete', ...result},
    }),
  );

  void _error(Object id, int code, String message, {Object? data}) => _push(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message, 'data': ?data},
    }),
  );
}

final class _FakeTransport implements McpTransport {
  _FakeTransport(this._server, this.kind);

  final FakeMcpServer _server;
  final _incoming = StreamController<String>();
  final _aborted = StreamController<Object>.broadcast();
  final _done = Completer<McpTransportClosed>();
  var _closed = false;

  @override
  final String kind;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Stream<Object> get abortedRequests => _aborted.stream;

  @override
  Future<McpTransportClosed> get done => _done.future;

  @override
  Future<void> send(
    String message, {
    Map<String, String> headers = const {},
  }) async {
    if (_closed) {
      throw const McpTransportException('transport is closed');
    }
    _server._handleRaw(message, headers);
  }

  @override
  Future<void> abandon(Object requestId) async {
    _server.abandoned.add(requestId);
  }

  void _deliver(String text) {
    if (!_closed) {
      _incoming.add(text);
    }
  }

  void _closeFromServer(String reason) => _finish(McpTransportClosed(reason));

  void _finish(McpTransportClosed closed) {
    if (_closed) {
      return;
    }
    _closed = true;
    _server.closedTransports++;
    _done.complete(closed);
    _incoming.close();
    _aborted.close();
  }

  @override
  Future<void> close() async => _finish(const McpTransportClosed('closed'));
}

/// Фабрика транспортов в памяти: сервер выбирается по `name` из описания
/// (`command` и `url` игнорируются, D15).
///
/// Как использовать: передать в `McpTransports` вместо настоящих фабрик;
/// [failures] имитирует ошибку запуска (`spawn failed: …`) для сервера по
/// имени.
final class FakeMcpTransportFactory implements McpTransportFactory {
  FakeMcpTransportFactory(
    Map<String, FakeMcpServer> servers, {
    Set<String> transports = const {'stdio', 'http'},
    Map<String, String> failures = const {},
  }) : _servers = servers,
       _failures = failures,
       transports = Set.unmodifiable(transports);

  final Map<String, FakeMcpServer> _servers;
  final Map<String, String> _failures;

  @override
  final Set<String> transports;

  /// Имена серверов в порядке открытия транспортов.
  final opened = <String>[];

  @override
  Future<McpTransport> open(
    McpServerConfig server, {
    required String cwd,
    required CancelToken cancel,
  }) async {
    opened.add(server.name);
    if (_failures[server.name] case final message?) {
      throw McpTransportException(message);
    }
    final fake = _servers[server.name];
    if (fake == null) {
      throw McpTransportException('no fake server named ${server.name}');
    }
    return fake.connect(kind: server.transport);
  }
}
