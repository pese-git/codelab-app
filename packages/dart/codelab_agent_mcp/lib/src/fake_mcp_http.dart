part of 'fake_mcp_server.dart';

/// Как HTTP-обработчик [FakeMcpServer] отвечает на запрос, ответ на который
/// готов сразу (design.md change `add-agent-mcp-client`, D10, D15).
///
/// Запрос, на который ответ придёт позже (задержанный `tools/call`,
/// `subscriptions/listen`), всегда получает поток `text/event-stream`.
enum FakeHttpStyle {
  /// Один объект `application/json`.
  json,

  /// Поток SSE: keep-alive-комментарий, уведомление `notifications/progress`
  /// и затем ответ (`streamable-http.md`, «Receiving Messages»).
  sse,
}

/// Готовый HTTP-ответ сервера на пробу `server/discover` (D2).
///
/// Как использовать: `FakeMcpServer(probeReply: FakeHttpReply(404, ''))` —
/// legacy-сервер без modern-конечной точки; `FakeHttpReply.error(400,
/// -32022, supported: [...])` — modern-ошибка в теле.
final class FakeHttpReply {
  const FakeHttpReply(this.status, this.body, {this.headers = const {}});

  /// Тело — ошибка JSON-RPC с `id: null`: клиент сопоставляет её с запросом
  /// сам (`streamable-http.md`: тело может быть ошибкой без `id`).
  factory FakeHttpReply.error(
    int status,
    int code, {
    List<String>? supported,
  }) => FakeHttpReply(
    status,
    jsonEncode({
      'jsonrpc': '2.0',
      'id': null,
      'error': {
        'code': code,
        'message': 'Error $code',
        if (supported != null) 'data': {'supported': supported},
      },
    }),
    headers: const {'content-type': 'application/json'},
  );

  final int status;
  final String body;
  final Map<String, String> headers;
}

/// HTTP-запрос клиента, записанный сервером: имена заголовков в нижнем
/// регистре, тело — текст.
final class FakeHttpRequest {
  FakeHttpRequest(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;

  /// Тело `POST` как JSON-RPC-сообщение; `null` у `GET` и `DELETE`.
  late final Map<String, Object?>? json = body.isEmpty
      ? null
      : (jsonDecode(body) as Map).cast<String, Object?>();
}

/// HTTP-сторона [FakeMcpServer]: разводит ответы ядра fake-сервера по
/// потокам ответов запросов, потоку `subscriptions/listen` (modern) и потоку
/// `GET` (legacy), считает статусы и проверяет зеркальные заголовки
/// (`streamable-http.md`, «Server Validation»; D10).
final class _FakeHttp {
  _FakeHttp(this.server);

  final FakeMcpServer server;
  var expired = false;
  var crashed = false;
  final _exchanges = <Object, _Exchange>{};
  _Exchange? _listen;
  _Exchange? _current;
  StreamController<List<int>>? _get;
  final _polls = <String, _Exchange>{};
  var _eventSeq = 0;

  Future<http.StreamedResponse> handle(
    http.BaseRequest request,
    Stream<List<int>> body,
  ) async {
    if (crashed) {
      throw http.ClientException('connection refused', request.url);
    }
    final bytes = <int>[];
    await for (final chunk in body) {
      bytes.addAll(chunk);
    }
    final text = utf8.decode(bytes);
    final headers = {
      for (final e in request.headers.entries) e.key.toLowerCase(): e.value,
    };
    server.httpLog.add(
      FakeHttpRequest(request.method, request.url, headers, text),
    );
    if (expired && headers.containsKey('mcp-session-id')) {
      return _plain(request, 404);
    }
    return switch (request.method) {
      'POST' => _post(request, headers, text),
      'GET' => _getRequest(request, headers),
      'DELETE' => _plain(request, server.allowDelete ? 200 : 405),
      _ => _plain(request, 405),
    };
  }

  http.StreamedResponse _plain(
    http.BaseRequest request,
    int status, {
    String body = '',
    Map<String, String> headers = const {},
  }) => http.StreamedResponse(
    body.isEmpty ? const Stream.empty() : Stream.value(utf8.encode(body)),
    status,
    headers: headers,
    request: request,
  );

  http.StreamedResponse _post(
    http.BaseRequest request,
    Map<String, String> headers,
    String text,
  ) {
    final message = (jsonDecode(text) as Map).cast<String, Object?>();
    final method = message['method'];
    final id = message['id'];
    if (method is! String || id == null) {
      // Уведомление или ответ клиента: `202 Accepted` без тела.
      server._handleRaw(text, headers);
      return _plain(request, 202);
    }
    final params = (message['params'] as Map?)?.cast<String, Object?>() ?? {};
    final meta = (params['_meta'] as Map?)?.cast<String, Object?>();
    final modern =
        server._modernServing &&
        meta != null &&
        meta.containsKey(FakeMcpServer._versionKey);
    if (modern) {
      final mismatch = _validateHeaders(headers, method, params, meta);
      if (mismatch != null) {
        server.violations.add('header mismatch: $mismatch');
        return _plain(
          request,
          400,
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'error': {
              'code': mcpHeaderMismatch,
              'message': 'Header mismatch: $mismatch',
            },
          }),
          headers: const {'content-type': 'application/json'},
        );
      }
    }
    if (method == 'server/discover' && server.probeReply != null) {
      server.requests.add(message);
      server.sentHeaders.add(headers);
      final reply = server.probeReply!;
      return _plain(
        request,
        reply.status,
        body: reply.body,
        headers: reply.headers,
      );
    }
    final exchange = _Exchange(
      this,
      id,
      method,
      polling: server.pollCloses > 0 && method == 'tools/call' && !modern,
    );
    _exchanges[id] = exchange;
    if (method == 'subscriptions/listen') {
      _listen = exchange;
    }
    _current = exchange;
    server._handleRaw(text, headers);
    _current = null;
    return _reply(request, exchange);
  }

  http.StreamedResponse _reply(http.BaseRequest request, _Exchange exchange) {
    final headers = {
      if (exchange.method == 'initialize' && server.httpSessionId != null)
        'mcp-session-id': server.httpSessionId!,
    };
    final listen = exchange.method == 'subscriptions/listen';
    final response = exchange.response;
    if (response != null &&
        !listen &&
        !exchange.hasExtras &&
        (server.httpStyle == FakeHttpStyle.json || exchange.isError)) {
      exchange.silence();
      return _plain(
        request,
        exchange.isError ? _statusFor(exchange.errorCode) : 200,
        body: response,
        headers: {...headers, 'content-type': 'application/json'},
      );
    }
    if (exchange.polling) {
      _prime(exchange);
    }
    return _stream(request, exchange, headers);
  }

  http.StreamedResponse _stream(
    http.BaseRequest request,
    _Exchange exchange,
    Map<String, String> headers,
  ) => http.StreamedResponse(
    exchange.body.stream,
    200,
    headers: {
      ...headers,
      'content-type': 'text/event-stream',
      'x-accel-buffering': 'no',
    },
    request: request,
  );

  /// Событие опроса (`transports.md` 2025-11-25, п. 6): `id`, `retry` и
  /// пустой `data`; затем сервер закрывает соединение до ответа.
  void _prime(_Exchange exchange) {
    final id = 'e${++_eventSeq}';
    final retry = server.pollRetry;
    exchange
      ..emit(
        'id: $id\n${retry == null ? '' : 'retry: ${retry.inMilliseconds}\n'}data:\n\n',
      )
      ..closes += 1
      ..connectionOpen = false
      ..closeBody();
    _polls[id] = exchange;
  }

  http.StreamedResponse _getRequest(
    http.BaseRequest request,
    Map<String, String> headers,
  ) {
    final last = headers['last-event-id'];
    if (last != null) {
      final exchange = _polls.remove(last);
      if (exchange == null) {
        return _plain(request, 400);
      }
      server.resumes++;
      exchange.reopen();
      if (exchange.closes < server.pollCloses) {
        _prime(exchange);
      } else {
        exchange.connectionOpen = true;
        if (exchange.stashed case final stashed?) {
          exchange.stashed = null;
          exchange.deliverResponse(stashed);
        }
      }
      return _stream(request, exchange, const {});
    }
    if (!server.allowGetStream || server.era == FakeMcpEra.modern) {
      return _plain(request, 405);
    }
    final controller = StreamController<List<int>>();
    _get = controller;
    return http.StreamedResponse(
      controller.stream,
      200,
      headers: const {'content-type': 'text/event-stream'},
      request: request,
    );
  }

  /// Направляет сообщение ядра fake-сервера в нужный поток.
  void route(String text) {
    final message = (jsonDecode(text) as Map).cast<String, Object?>();
    final id = message['id'];
    if (id != null && !message.containsKey('method')) {
      _exchanges[id]?.deliverResponse(text);
      return;
    }
    // Уведомления и запросы сервера: modern — поток подписки, legacy — поток
    // `GET`, а до его открытия — поток ответа текущего запроса.
    if (server._isModernConnection && _listen != null) {
      _listen!.emit('data: $text\n\n');
    } else if (_get != null) {
      _get!.add(utf8.encode('data: $text\n\n'));
    } else if (_current != null) {
      _current!
        ..hasExtras = true
        ..emit('data: $text\n\n');
    }
  }

  /// Поток ответа запроса [id] оборвался без ответа.
  void abort(Object id) => _exchanges[id]?.abort();

  void closeGet() {
    _get?.close();
    _get = null;
  }

  void crash() {
    crashed = true;
    for (final exchange in _exchanges.values) {
      exchange.abort();
    }
    _get?.close();
  }

  static int _statusFor(int code) => switch (code) {
    mcpHeaderMismatch ||
    mcpMissingClientCapability ||
    mcpUnsupportedProtocolVersion => 400,
    jsonRpcMethodNotFound => 404,
    _ => 200,
  };

  /// Зеркальные заголовки modern-запроса против тела; `null` — совпали.
  String? _validateHeaders(
    Map<String, String> headers,
    String method,
    Map<String, Object?> params,
    Map<String, Object?> meta,
  ) {
    if (headers['mcp-protocol-version'] != meta[FakeMcpServer._versionKey]) {
      return 'MCP-Protocol-Version';
    }
    if (headers['mcp-method'] != method) {
      return 'Mcp-Method';
    }
    if (method != 'tools/call') {
      return null;
    }
    final name = params['name'];
    if (_decode(headers['mcp-name']) != name) {
      return 'Mcp-Name';
    }
    final tool = server._tools.where((t) => t.name == name).firstOrNull;
    final mirrored = <String, List<String>>{};
    _collect(tool?.inputSchema, const [], mirrored);
    for (final MapEntry(key: header, value: path) in mirrored.entries) {
      Object? value = params['arguments'];
      for (final step in path) {
        value = value is Map ? value[step] : null;
      }
      final expected = switch (value) {
        final String s => s,
        final int i => '$i',
        final bool b => '$b',
        _ => null,
      };
      final actual = headers['mcp-param-${header.toLowerCase()}'];
      if (expected == null ? actual != null : _decode(actual) != expected) {
        return 'Mcp-Param-$header';
      }
    }
    return null;
  }

  void _collect(
    Object? node,
    List<String> path,
    Map<String, List<String>> out,
  ) {
    if (node is! Map) {
      return;
    }
    final header = node['x-mcp-header'];
    if (header is String && path.isNotEmpty) {
      out[header] = path;
    }
    final properties = node['properties'];
    if (properties is Map) {
      properties.forEach(
        (key, value) => _collect(value, [...path, key as String], out),
      );
    }
  }

  static String? _decode(String? value) {
    if (value == null ||
        !value.startsWith('=?base64?') ||
        !value.endsWith('?=')) {
      return value;
    }
    final inner = value.substring('=?base64?'.length, value.length - 2);
    return utf8.decode(base64.decode(inner));
  }
}

/// Один запрос клиента и поток его ответа.
final class _Exchange {
  _Exchange(this.http, this.id, this.method, {required this.polling})
    : connectionOpen = !polling {
    body = _newBody();
  }

  final _FakeHttp http;
  final Object id;
  final String method;

  /// Опрос SSE: соединение закрывается до ответа (D10).
  final bool polling;

  late StreamController<List<int>> body;

  /// Ответ (JSON-текст) уже получен.
  String? response;

  /// Ответ пришёл, пока соединение было закрыто: уйдёт по `GET`.
  String? stashed;
  var connectionOpen = true;
  var hasExtras = false;
  var closes = 0;
  var _closedByServer = false;

  StreamController<List<int>> _newBody() => StreamController<List<int>>(
    onCancel: () {
      // Клиент закрыл поток ответа: в modern это и есть отмена.
      if (!_closedByServer) {
        http.server.abandoned.add(id);
      }
    },
  );

  Map<String, Object?>? get _parsed =>
      response == null ? null : (jsonDecode(response!) as Map).cast();

  bool get isError => _parsed?.containsKey('error') ?? false;

  int get errorCode => ((_parsed!['error'] as Map)['code'] as int?) ?? 0;

  void emit(String text) {
    if (!_closedByServer) {
      body.add(utf8.encode(text));
    }
  }

  void closeBody() {
    if (!_closedByServer) {
      _closedByServer = true;
      body.close();
    }
  }

  /// Закрывает поток, который никто не будет читать.
  void silence() => closeBody();

  void reopen() {
    body = _newBody();
    _closedByServer = false;
  }

  void deliverResponse(String text) {
    if (!connectionOpen) {
      stashed = text;
      return;
    }
    response = text;
    final listen = method == 'subscriptions/listen';
    if (http.server.httpStyle == FakeHttpStyle.sse && !listen && !polling) {
      emit(': keep-alive\n\n');
      emit(
        'data: ${jsonEncode({
          'jsonrpc': '2.0',
          'method': 'notifications/progress',
          'params': {'progressToken': 'p', 'progress': 1},
        })}\n\n',
      );
    }
    final eventId = polling ? 'id: e${++http._eventSeq}\n' : '';
    emit('${eventId}data: $text\n\n');
    closeBody();
  }

  void abort() {
    if (response == null) {
      closeBody();
    }
  }
}
