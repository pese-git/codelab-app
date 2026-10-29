import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:http/http.dart' as http;

import 'protocol.dart' show legacyAcceptedVersions;

/// Предел тела ответа: больше — ошибка (design.md change
/// `add-agent-mcp-client`, D10).
const defaultMaxResponseBytes = 16 * 1024 * 1024;

/// Сколько раз клиент возобновляет поток ответа одного запроса
/// (`2025-11-25/basic/transports.md`, «Resumability and Redelivery»; D10).
const maxStreamResumes = 5;

/// Пауза до возобновления, если сервер не прислал `retry` (D10).
const defaultResumePause = Duration(seconds: 1);

final _sessionPattern = RegExp(r'^[\x21-\x7E]+$');

/// Транспорт MCP «streamable HTTP» на `package:http` (design.md change
/// `add-agent-mcp-client`, D10; `basic/transports/streamable-http.md`,
/// обе эпохи).
///
/// Почему отдельный класс на `http.Client`, а не SDK: HTTP-клиент приходит от
/// хоста (PKG-6), в тестах это `MockClient`, а пакет остаётся web-безопасным
/// (нет `dart:io`) — транспорт доступен профилям `mobile` и `web`.
///
/// Для чего: превращает «строки туда и обратно» порта [McpTransport] в HTTP.
/// Каждое сообщение клиента — отдельный `POST`; ответ запроса приходит как
/// `application/json` или поток SSE и попадает в [incoming]; поток, закрытый
/// без ответа, — в [abortedRequests] (D8); [abandon] закрывает поток ответа —
/// в modern это и есть отмена (`streamable-http.md`, «Cancellation»).
///
/// Как использовать: хост создаёт транспорт фабрикой
/// [StreamableHttpTransportFactory]; `McpClient` сам передаёт зеркальные
/// заголовки modern-запросов (`send(..., headers:)`). Транспорт сам ведёт
/// только legacy-часть: `Mcp-Session-Id` и `MCP-Protocol-Version` из ответа на
/// `initialize`, поток `GET` при `tools.listChanged`, `DELETE` при закрытии и
/// возобновление потока `GET` с `Last-Event-ID`.
///
/// Безопасность: редиректы выключены (`3xx` — ошибка), значения заголовков
/// сервера, `Mcp-Session-Id` и `Mcp-Param-*` не попадают ни в логи, ни в
/// причины ошибок (D13): причины — только тексты этого кода.
final class StreamableHttpTransport implements McpTransport {
  StreamableHttpTransport({
    required this.url,
    this.headers = const [],
    required http.Client client,
    required Clock clock,
    required Logger logger,
    this.serverName = '',
    this.maxResponseBytes = defaultMaxResponseBytes,
    this.resumePauseLimit = defaultMcpConnectTimeout,
  }) : _client = client,
       _clock = clock,
       _logger = logger;

  /// Конечная точка MCP.
  final Uri url;

  /// Заголовки сервера из описания; служебные заголовки их перекрывают.
  final List<(String, String)> headers;
  final String serverName;

  /// Предел одного события SSE (`data` + служебные поля) и тела JSON-ответа.
  /// Поток SSE в целом не ограничен: listen живёт часами.
  final int maxResponseBytes;

  /// Потолок паузы перед возобновлением: `retry` приходит от недоверенного
  /// сервера, и пауза в сутки подвесила бы вызов (D10). Фабрика ставит
  /// `connectTimeout` сервера.
  final Duration resumePauseLimit;

  final http.Client _client;
  final Clock _clock;
  final Logger _logger;

  final _incoming = StreamController<String>();
  final _aborted = StreamController<McpRequestAbort>.broadcast();
  final _done = Completer<McpTransportClosed>();
  final _exchanges = <Object, _Exchange>{};
  _SseReader? _getReader;

  /// Завершается при закрытии: обрывает все запросы, не только запросы с
  /// обменом (`GET`, `DELETE`).
  final _closeAbort = Completer<void>();
  var _closing = false;
  var _closed = false;

  /// Legacy-эпоха началась с отправки `initialize`.
  var _legacy = false;
  String? _sessionId;
  String? _legacyVersion;
  var _listChanged = false;

  @override
  String get kind => 'http';

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Stream<McpRequestAbort> get abortedRequests => _aborted.stream;

  @override
  Future<McpTransportClosed> get done => _done.future;

  @override
  Future<void> send(
    String message, {
    Map<String, String> headers = const {},
  }) async {
    if (_closing || _closed) {
      throw const McpTransportException('transport is closed');
    }
    final parsed = jsonDecode(message) as Map<String, Object?>;
    final method = parsed['method'];
    final id = parsed['id'];
    if (method == 'initialize') {
      _legacy = true;
    }
    final exchange = method is String && id != null
        ? _Exchange(id, method)
        : null;
    final request = _newRequest(
      'POST',
      mirrored: headers,
      abort: exchange?.abort,
    )..bodyBytes = utf8.encode(message);
    if (exchange == null) {
      // Уведомление или ответ клиента (legacy `ping`): ждём `202`.
      final response = await _dispatch(request);
      await _checkStatus(response, expectBody: false);
      await _discard(response);
      if (method == 'notifications/initialized' && _listChanged) {
        unawaited(_openGetStream());
      }
      return;
    }
    _exchanges[exchange.id] = exchange;
    final http.StreamedResponse response;
    try {
      response = await _dispatch(request);
      if (!exchange.abandoned && !_closed) {
        await _checkStatus(response, expectBody: true);
      }
    } on Object {
      _exchanges.remove(exchange.id);
      if (exchange.abandoned || _closed) {
        // Отмена клиента (`abandon`) сама оборвала запрос: это не сбой.
        return;
      }
      rethrow;
    }
    if (exchange.abandoned || _closed) {
      await _discard(response);
      return;
    }
    if (method == 'initialize' && _isSuccess(response.statusCode)) {
      final session = _header(response.headers, 'mcp-session-id');
      if (session != null && _sessionPattern.hasMatch(session)) {
        _sessionId = session;
      }
    }
    _readResponse(exchange, response);
  }

  @override
  Future<void> abandon(Object requestId) async {
    final exchange = _exchanges.remove(requestId);
    if (exchange == null) {
      return;
    }
    exchange
      ..abandoned = true
      ..pause.cancel();
    // Запрос ещё ждёт заголовки ответа: без этого закрывать нечего, и
    // соединение жило бы до ответа сервера.
    exchange.cancelRequest();
    final stop = exchange.stop;
    exchange.stop = null;
    await stop?.call();
  }

  @override
  Future<void> close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    if (_sessionId != null && !_closed) {
      await _deleteSession();
    }
    await _finish(const McpTransportClosed('closed'));
  }

  // --- запросы -----------------------------------------------------------

  /// Запрос с заголовками сервера, затем служебными: поздние перекрывают
  /// ранние без учёта регистра (`http.BaseRequest.headers`).
  http.Request _newRequest(
    String method, {
    Map<String, String> mirrored = const {},
    Map<String, String> extra = const {},
    Completer<void>? abort,
  }) {
    // `abortTrigger`: отмена (`abandon`) или закрытие обрывает запрос,
    // который ещё не получил заголовки ответа.
    final request = http.AbortableRequest(
      method,
      url,
      abortTrigger: Future.any([
        _closeAbort.future,
        if (abort != null) abort.future,
      ]),
    )..followRedirects = false;
    for (final (name, value) in headers) {
      request.headers[name] = value;
    }
    if (method == 'POST') {
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'application/json, text/event-stream';
    }
    if (_legacy) {
      if (_sessionId case final session?) {
        request.headers['Mcp-Session-Id'] = session;
      }
      // Для `2025-03-26` заголовка нет (`2025-11-25/basic/transports.md`,
      // «Protocol Version Header»).
      if (_legacyVersion case final version?
          when version.compareTo('2025-06-18') >= 0) {
        request.headers['MCP-Protocol-Version'] = version;
      }
    }
    request.headers
      ..addAll(mirrored)
      ..addAll(extra);
    return request;
  }

  /// Отправка без чтения тела. Сбой соединения — [McpTransportException] с
  /// текстом этого кода: текст исключения `http` содержит URL, а в нём бывают
  /// секреты (D13).
  Future<http.StreamedResponse> _dispatch(http.Request request) async {
    try {
      return await _client.send(request);
    } on Object catch (error) {
      throw McpTransportException('connection failed: ${error.runtimeType}');
    }
  }

  /// Статусы, при которых запрос не продолжается: редирект и истёкшая
  /// legacy-сессия (D10).
  ///
  /// Перед исключением тело ответа отбрасывается: соединение не должно
  /// висеть из-за непрочитанного потока.
  Future<void> _checkStatus(
    http.StreamedResponse response, {
    required bool expectBody,
  }) async {
    final status = response.statusCode;
    final McpTransportException? failure;
    if (status == 404 && _sessionId != null) {
      unawaited(_expire());
      failure = const McpTransportException('HTTP session expired');
    } else if (status >= 300 && status < 400) {
      failure = McpTransportException(
        'HTTP redirect ($status) is not followed',
      );
    } else if (!expectBody && !_isSuccess(status)) {
      failure = McpTransportException('HTTP $status');
    } else {
      failure = null;
    }
    if (failure != null) {
      await _discard(response);
      throw failure;
    }
  }

  static bool _isSuccess(int status) => status >= 200 && status < 300;

  Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.listen((_) {}).cancel();
    } on Object {
      // Тело уже не нужно.
    }
  }

  Future<void> _expire() async {
    _logger.log(
      LogLevel.info,
      'mcp.server.closed',
      fields: {
        'server': serverName,
        'transport': 'http',
        'reason': 'HTTP session expired',
      },
    );
    await _finish(const McpTransportClosed('HTTP session expired'));
  }

  // --- ответы ------------------------------------------------------------

  void _readResponse(_Exchange exchange, http.StreamedResponse response) {
    final type = _header(response.headers, 'content-type') ?? '';
    final status = response.statusCode;
    if (!_isSuccess(status)) {
      // Тело ошибки: JSON-RPC-ошибка нужна пробе эпохи (D2).
      _readBody(exchange, response.stream, limit: 64 * 1024, (bytes) {
        _failExchange(exchange, bytes, status);
      });
    } else if (status == 200 && type.contains('text/event-stream')) {
      _readSse(exchange, response.stream);
    } else if (status == 200 && type.contains('application/json')) {
      _readBody(exchange, response.stream, limit: maxResponseBytes, (bytes) {
        final text = utf8.decode(bytes, allowMalformed: true);
        try {
          jsonDecode(text);
        } on FormatException {
          _localFailure(exchange, 'invalid JSON in the response');
          return;
        }
        _deliver(exchange, text);
        if (!exchange.responded) {
          // Тело не содержит ответа на свой запрос: без этого запрос ждал бы
          // таймаута. Ошибка без `id` привязывается к запросу (как при не-2xx).
          final error = _errorWithoutId(text);
          if (error != null) {
            exchange.responded = true;
            _push(
              jsonEncode({'jsonrpc': '2.0', 'id': exchange.id, 'error': error}),
            );
          } else {
            _localFailure(exchange, 'unexpected response (HTTP 200)');
          }
        }
        _finishExchange(exchange);
      });
    } else {
      unawaited(_discard(response));
      _localFailure(exchange, 'unexpected response (HTTP $status)');
    }
  }

  /// Читает тело целиком, не превышая [limit], и отдаёт его [onBody].
  void _readBody(
    _Exchange exchange,
    Stream<List<int>> stream,
    void Function(Uint8List bytes) onBody, {
    required int limit,
  }) {
    final builder = BytesBuilder(copy: false);
    final subscription = stream.listen(
      (chunk) {
        builder.add(chunk);
        if (builder.length > limit) {
          unawaited(exchange.stop?.call());
          exchange.stop = null;
          _localFailure(exchange, 'response body too large');
        }
      },
      onError: (Object _) => _streamEnded(exchange),
      onDone: () {
        exchange.stop = null;
        onBody(builder.takeBytes());
      },
      cancelOnError: true,
    );
    exchange.stop = subscription.cancel;
  }

  /// `error` ответа без `id` (`id: null`), если он есть и корректен.
  static Map<Object?, Object?>? _errorWithoutId(String text) {
    final body = jsonDecode(text);
    if (body is Map && body['id'] == null && body['error'] is Map) {
      final error = body['error']! as Map;
      if (error['code'] is int && error['message'] is String) {
        return error;
      }
    }
    return null;
  }

  void _failExchange(_Exchange exchange, Uint8List bytes, int status) {
    try {
      final body = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (body is Map && body['error'] is Map) {
        final error = body['error']! as Map;
        if (error['code'] is int && error['message'] is String) {
          // Тело ошибки может быть без `id` или с чужим: ответ привязывается
          // к запросу, на который пришёл статус.
          exchange.responded = true;
          _push(
            jsonEncode({'jsonrpc': '2.0', 'id': exchange.id, 'error': error}),
          );
          _finishExchange(exchange);
          return;
        }
      }
    } on FormatException {
      // Не JSON: ошибка с кодом статуса ниже.
    }
    _localFailure(exchange, 'HTTP $status');
  }

  void _readSse(_Exchange exchange, Stream<List<int>> stream) {
    final reader = _SseReader(
      stream,
      limit: maxResponseBytes,
      onEvent: (event) => _onEvent(exchange, event),
      onError: (Object error) {
        exchange.stop = null;
        if (error is _TooLarge) {
          _localFailure(exchange, 'response body too large');
        } else {
          _streamEnded(exchange);
        }
      },
      onDone: () => _streamEnded(exchange),
    );
    exchange.stop = reader.cancel;
  }

  void _onEvent(_Exchange? exchange, ServerSentEvent event) {
    if (exchange != null) {
      if (event.id != null) {
        exchange.lastEventId = event.id;
      }
      if (event.retry != null) {
        exchange.retry = event.retry;
      }
    }
    // Событие `id` без данных — «заправка» опроса, не сообщение
    // (`2025-11-25/basic/transports.md`, «Sending Messages», п. 6).
    if (event.data.isEmpty ||
        (event.event != null && event.event != 'message')) {
      return;
    }
    _deliver(exchange, event.data);
  }

  /// Сообщение сервера — в [incoming]; ответ на запрос [exchange] помечает
  /// запрос отвеченным, ответ на `initialize` запоминает версию и
  /// `tools.listChanged` для legacy (D10).
  void _deliver(_Exchange? exchange, String text) {
    if (exchange != null) {
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      for (final item in decoded is List ? decoded : [decoded]) {
        if (item is! Map || item['id'] != exchange.id) {
          continue;
        }
        if (item.containsKey('result') || item.containsKey('error')) {
          exchange.responded = true;
          if (exchange.method == 'initialize' && item['result'] is Map) {
            _rememberInitialize(item['result']! as Map);
          }
        }
      }
    }
    _push(text);
  }

  void _rememberInitialize(Map<Object?, Object?> result) {
    final version = result['protocolVersion'];
    // Только известная версия: строка сервера попадёт в заголовок запросов.
    if (version is String && legacyAcceptedVersions.contains(version)) {
      _legacyVersion = version;
    }
    final tools = (result['capabilities'] as Map?)?['tools'];
    _listChanged = tools is Map && tools['listChanged'] == true;
  }

  void _push(String text) {
    if (!_incoming.isClosed) {
      _incoming.add(text);
    }
  }

  /// Локальный сбой ответа (`HTTP 500` без тела ошибки, слишком большое
  /// тело): неповторяемый [McpRequestAbort] с текстом этого кода. Это не
  /// ошибка JSON-RPC: у неё нет кода, и её нельзя спутать с ответом сервера
  /// (`basic/index.md`, «Error Codes»).
  void _localFailure(_Exchange exchange, String reason) {
    if (exchange.abandoned || _closed) {
      return;
    }
    exchange.responded = true;
    _finishExchange(exchange);
    if (!_aborted.isClosed) {
      _aborted.add(
        McpRequestAbort(exchange.id, reason: reason, retryable: false),
      );
    }
  }

  void _finishExchange(_Exchange exchange) {
    exchange.stop = null;
    _exchanges.remove(exchange.id);
  }

  /// Поток ответа закрылся. Без ответа: legacy-поток с событием `id`
  /// возобновляется `GET` (D10), остальное — обрыв (D8).
  void _streamEnded(_Exchange exchange) {
    exchange.stop = null;
    if (_closed || exchange.abandoned || exchange.responded) {
      _exchanges.remove(exchange.id);
      return;
    }
    if (_legacy &&
        exchange.lastEventId != null &&
        exchange.resumes < maxStreamResumes) {
      exchange.resumes++;
      unawaited(_resume(exchange));
      return;
    }
    _abort(exchange);
  }

  void _abort(_Exchange exchange) {
    _exchanges.remove(exchange.id);
    if (!_aborted.isClosed) {
      _aborted.add(McpRequestAbort(exchange.id));
    }
  }

  /// Дочитывает тот же ответ: `GET` с `Last-Event-ID` после паузы `retry`
  /// (без него — 1 с). Это не повтор `tools/call`: новый запрос не уходит.
  Future<void> _resume(_Exchange exchange) async {
    try {
      final wanted = exchange.retry ?? defaultResumePause;
      await _clock.delay(
        wanted < resumePauseLimit ? wanted : resumePauseLimit,
        cancel: exchange.pause.token,
      );
    } on CancelledException {
      return;
    }
    if (_closed || exchange.abandoned) {
      return;
    }
    final request = _newRequest(
      'GET',
      extra: {
        'Accept': 'text/event-stream',
        'Last-Event-ID': exchange.lastEventId!,
      },
    );
    final http.StreamedResponse response;
    try {
      response = await _dispatch(request);
    } on McpTransportException catch (error) {
      _debug('stream_resume_failed', error.message);
      _abort(exchange);
      return;
    }
    if (_closed || exchange.abandoned) {
      await _discard(response);
      return;
    }
    if (response.statusCode == 404 && _sessionId != null) {
      await _discard(response);
      await _expire();
      return;
    }
    final type = _header(response.headers, 'content-type') ?? '';
    if (response.statusCode != 200 || !type.contains('text/event-stream')) {
      await _discard(response);
      _debug('stream_resume_failed', 'HTTP ${response.statusCode}');
      _abort(exchange);
      return;
    }
    _readSse(exchange, response.stream);
  }

  // --- legacy: поток GET и DELETE ---------------------------------------

  /// Поток уведомлений сервера (`2025-11-25/basic/transports.md`,
  /// «Listening for Messages from the Server»). `405` — потока нет; оборвавшийся
  /// поток в MVP не открывается заново (D10).
  Future<void> _openGetStream() async {
    final request = _newRequest('GET', extra: {'Accept': 'text/event-stream'});
    final http.StreamedResponse response;
    try {
      response = await _dispatch(request);
    } on McpTransportException catch (error) {
      _debug('notification_stream_closed', error.message);
      return;
    }
    if (_closing || _closed) {
      await _discard(response);
      return;
    }
    if (response.statusCode == 404 && _sessionId != null) {
      await _discard(response);
      await _expire();
      return;
    }
    final type = _header(response.headers, 'content-type') ?? '';
    if (response.statusCode != 200 || !type.contains('text/event-stream')) {
      await _discard(response);
      // `405` — сервер не предлагает поток; уведомления не придут.
      _debug('notification_stream_closed', 'HTTP ${response.statusCode}');
      return;
    }
    _getReader = _SseReader(
      response.stream,
      limit: maxResponseBytes,
      onEvent: (event) => _onEvent(null, event),
      onError: (Object error) => _debug(
        'notification_stream_closed',
        error is _TooLarge ? 'event too large' : 'stream error',
      ),
      onDone: () => _debug('notification_stream_closed', 'stream closed'),
    );
  }

  /// `DELETE` с `Mcp-Session-Id`, best effort до 2 с; `405` нормален
  /// (`2025-11-25/basic/transports.md`, «Session Management», п. 5).
  Future<void> _deleteSession() async {
    final finished = Completer<void>();
    final timer = _clock.timer(const Duration(seconds: 2), () {
      if (!finished.isCompleted) {
        finished.complete();
      }
    });
    unawaited(() async {
      try {
        final response = await _dispatch(_newRequest('DELETE'));
        await _discard(response);
      } on Object {
        // Сервер недоступен: сессия истечёт сама.
      } finally {
        if (!finished.isCompleted) {
          finished.complete();
        }
      }
    }());
    await finished.future;
    timer.cancel();
  }

  Future<void> _finish(McpTransportClosed closed) async {
    if (_closed) {
      return;
    }
    _closed = true;
    // `done` раньше остального: клиент должен увидеть закрытие до того, как
    // следующий вызов успеет прийти в уже закрытый транспорт.
    _done.complete(closed);
    if (!_closeAbort.isCompleted) {
      _closeAbort.complete();
    }
    for (final exchange in [..._exchanges.values]) {
      exchange
        ..abandoned = true
        ..pause.cancel();
      await exchange.stop?.call();
    }
    _exchanges.clear();
    await _getReader?.cancel();
    await _incoming.close();
    await _aborted.close();
  }

  /// Диагностика потоков без ответа на запрос: debug, без значений
  /// заголовков (D13); [reason] — текст этого кода.
  void _debug(String kind, String reason) {
    if (_closing || _closed) {
      return;
    }
    _logger.log(
      LogLevel.debug,
      'mcp.message.ignored',
      fields: {'kind': kind, 'server': serverName, 'reason': reason},
    );
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) {
        return entry.value;
      }
    }
    return null;
  }
}

/// Ответ на один запрос клиента.
final class _Exchange {
  _Exchange(this.id, this.method);

  final Object id;
  final String method;

  /// Останавливает чтение тела (закрывает поток ответа).
  Future<void> Function()? stop;
  var abandoned = false;
  var responded = false;
  var resumes = 0;
  String? lastEventId;
  Duration? retry;

  /// Отмена паузы перед возобновлением (`abandon`, закрытие).
  final pause = CancelTokenSource();

  /// Обрывает запрос, пока нет заголовков ответа (`abortTrigger`).
  final abort = Completer<void>();

  void cancelRequest() {
    if (!abort.isCompleted) {
      abort.complete();
    }
  }
}

/// Читает поток SSE и отдаёт события [onEvent].
///
/// Почему не `bytes.transform(Utf8Decoder).transform(SseDecoder).listen`:
/// `SseDecoder` — генератор `async*`, а отмена подписки на него не доходит до
/// источника, пока генератор ждёт новые данные, то есть закрытие потока
/// ответа (отмена в modern, D8) зависло бы на молчащем сервере. Здесь отменяется
/// подписка на сами байты, а декодер получает конец потока.
final class _SseReader {
  _SseReader(
    Stream<List<int>> bytes, {
    required int limit,
    required void Function(ServerSentEvent event) onEvent,
    required void Function(Object error) onError,
    required void Function() onDone,
  }) {
    final text = StreamController<String>();
    final decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(text.sink);
    // Лимит на одно событие: счётчик сбрасывается, когда событие собрано.
    var total = 0;
    _text = text;
    _events = text.stream
        .transform(const SseDecoder())
        .listen(
          (event) {
            total = 0;
            if (!_cancelled) {
              onEvent(event);
            }
          },
          onError: (Object error) {
            // Ошибка декодера не должна становиться необработанной в зоне.
            if (!_cancelled) {
              unawaited(cancel());
              onError(error);
            }
          },
          onDone: () {
            if (!_cancelled) {
              onDone();
            }
          },
        );
    _raw = bytes.listen(
      (chunk) {
        total += chunk.length;
        if (total > limit) {
          unawaited(cancel());
          onError(const _TooLarge());
          return;
        }
        decoder.add(chunk);
      },
      onError: (Object error) {
        if (!_cancelled) {
          unawaited(cancel());
          onError(error);
        }
      },
      onDone: decoder.close,
      cancelOnError: true,
    );
  }

  late final StreamController<String> _text;
  late final StreamSubscription<ServerSentEvent> _events;
  late final StreamSubscription<List<int>> _raw;
  var _cancelled = false;

  Future<void> cancel() async {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    await _raw.cancel();
    unawaited(_events.cancel());
    unawaited(_text.close());
  }
}

final class _TooLarge implements Exception {
  const _TooLarge();
}

/// Открывает [StreamableHttpTransport] для серверов `type: http` (design.md
/// change `add-agent-mcp-client`, D3, D10).
///
/// Как использовать: хост создаёт фабрику один раз на своём `http.Client` и
/// кладёт её в `McpTransports(http: ...)`. Схема URL — только `http` и
/// `https`, иначе [McpTransportException] `invalid url` (сервер не
/// подключается, сессия создаётся). `http.Client` остаётся у хоста: ни
/// транспорт, ни фабрика его не закрывают.
final class StreamableHttpTransportFactory implements McpTransportFactory {
  StreamableHttpTransportFactory({
    required http.Client client,
    required Clock clock,
  }) : _client = client,
       _clock = clock;

  final http.Client _client;
  final Clock _clock;

  @override
  Set<String> get transports => const {'http'};

  @override
  Future<McpTransport> open(
    McpServerConfig server, {
    required String cwd,
    required CancelToken cancel,
    required Logger logger,
  }) async {
    if (server is! McpHttpServerConfig) {
      throw const McpTransportException('not an http server');
    }
    final url = server.url;
    if ((url.scheme != 'http' && url.scheme != 'https') || url.host.isEmpty) {
      throw const McpTransportException('invalid url');
    }
    return StreamableHttpTransport(
      url: url,
      headers: server.headers,
      client: _client,
      clock: _clock,
      logger: logger,
      serverName: server.name,
      resumePauseLimit: server.connectTimeout,
    );
  }
}
