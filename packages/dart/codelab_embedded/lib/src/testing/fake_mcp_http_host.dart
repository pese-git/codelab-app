import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:http/http.dart' as http;

/// Фейковый MCP-сервер на loopback HTTP (change `add-provider-setup-ui`,
/// задача 5.8a, решение Q28; design.md D20, D22; §12.4.13, шаги 1–4).
///
/// Почему: интеграционному тесту app (5.11) нужен настоящий URL в
/// `mcp.servers` временного `CODELAB_HOME`, чтобы встроенный агент прошёл
/// путь клиента MCP целиком (`initialize`, `tools/list`) без сети наружу.
/// Протокол уже умеет [FakeMcpServer] (`codelab_agent_mcp`), поэтому хост —
/// тонкий мост: сокет принимает запрос и передаёт его в `handleHttp`.
///
/// Для чего: слушает только `127.0.0.1` на свободном порту; заголовок
/// `Authorization` запросов доступен тесту в [authorizations], но НИКОГДА не
/// попадает в журнал хоста (PERM/CFG-2: в записи — только метод и путь).
/// [close] освобождает порт.
///
/// Как использовать: `host = await FakeMcpHttpHost.start();` — `host.url`
/// подставляется в конфиг; в `tearDown` — `await host.close()`. Без [tools]
/// сервер отдаёт один инструмент `echo`. Экспорт только из `testing.dart`
/// (сторож, web-compile).
final class FakeMcpHttpHost {
  FakeMcpHttpHost._(this._http, this.server, this._logger) {
    _subscription = _http.listen(_handle);
  }

  /// Поднимает хост на loopback. [tools] — инструменты сервера (по
  /// умолчанию один), [logger] — журнал запросов без значений заголовков.
  static Future<FakeMcpHttpHost> start({
    Logger? logger,
    List<FakeMcpTool>? tools,
  }) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FakeMcpHttpHost._(
      http,
      // Эпоха legacy: клиент делает `initialize` + `tools/list`, как в шагах
      // 1–4 §12.4.13 и в тесте 5.3a (modern начинает с `server/discover`).
      FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: tools ?? const [FakeMcpTool('echo')],
      ),
      logger,
    );
  }

  final HttpServer _http;
  final Logger? _logger;
  late final StreamSubscription<HttpRequest> _subscription;

  /// Сервер за хостом: журнал `methods`, `calls`, `httpLog` для проверок.
  final FakeMcpServer server;

  /// Значения `Authorization` запросов в порядке прихода.
  final authorizations = <String>[];

  /// Адрес привязки (всегда loopback): тест 5.3a проверяет, что хост не
  /// слушает внешние интерфейсы.
  InternetAddress get address => _http.address;

  /// Базовый URL для `mcp.servers[].url` (реальный порт).
  Uri get url => Uri(scheme: 'http', host: '127.0.0.1', port: _http.port);

  Future<void> _handle(HttpRequest request) async {
    try {
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
      }
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (auth != null) {
        authorizations.add(auth);
      }
      // Значения заголовков в журнал не пишутся: только метод и путь.
      _logger?.log(
        LogLevel.debug,
        'fake_mcp_host.request',
        fields: {'method': request.method, 'path': request.uri.path},
      );
      final outgoing = http.StreamedRequest(
        request.method,
        url.replace(path: request.uri.path, query: request.uri.query),
      );
      request.headers.forEach((name, values) {
        outgoing.headers[name] = values.join(',');
      });
      outgoing.sink
        ..add(bytes)
        ..close();
      final reply = await server.handleHttp(outgoing, outgoing.finalize());
      request.response.statusCode = reply.statusCode;
      reply.headers.forEach((name, value) {
        if (name.toLowerCase() != 'content-length' &&
            name.toLowerCase() != 'transfer-encoding') {
          request.response.headers.set(name, value);
        }
      });
      await request.response.addStream(reply.stream);
    } on Object catch (error) {
      _logger?.log(
        LogLevel.warning,
        'fake_mcp_host.error',
        fields: {'type': error.runtimeType.toString()},
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
      } on Object {
        // Ответ уже начат: закрываем как есть.
      }
    } finally {
      try {
        await request.response.close();
      } on Object {
        // Клиент ушёл: закрывать нечего.
      }
    }
  }

  /// Останавливает приём и освобождает порт.
  Future<void> close() async {
    await _subscription.cancel();
    await _http.close(force: true);
  }
}
