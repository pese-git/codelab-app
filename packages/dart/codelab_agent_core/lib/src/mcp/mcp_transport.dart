import '../cancel/cancel_token.dart';
import '../util/logger.dart';
import 'mcp_server_config.dart';

/// Транспорт MCP уровня сообщений (design.md change `add-agent-mcp-client`,
/// D3).
///
/// Почему порт в ядре, а не в пакете MCP: реализацию stdio пишет
/// `codelab_agent_io`, который зависит от ядра, но не от `codelab_agent_mcp`
/// (граф пакетов §1.2); ядро при этом не знает JSON-RPC и протокола MCP —
/// только «строки туда и обратно».
///
/// Как использовать: фабрика открывает транспорт на одно соединение;
/// `McpClient` шлёт тексты сообщений через [send], читает [incoming],
/// следит за [done] и в конце зовёт [close].
abstract interface class McpTransport {
  /// `stdio` или `http`: от него зависит сигнал отмены вызова (D8).
  String get kind;

  /// По одному JSON-тексту сообщения (или пакета JSON-RPC legacy
  /// `2025-03-26`).
  Stream<String> get incoming;

  /// Отправляет один JSON-текст. [headers] — зеркальные заголовки запроса
  /// (`MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`, `Mcp-Param-*`),
  /// которые считает клиент по эпохе (D10); stdio их игнорирует.
  Future<void> send(String message, {Map<String, String> headers = const {}});

  /// Идентификаторы запросов, чей поток ответа оборвался без ответа, пока сам
  /// транспорт жив (HTTP: обрыв SSE-потока). Клиент завершает такой запрос
  /// «disconnected during the call» (`tools/call`) или повторяет один раз
  /// (`tools/list`, `server/discover`; D8, D10). Для stdio — пустой поток.
  Stream<Object> get abortedRequests;

  /// Перестать ждать ответ на запрос [requestId]: HTTP закрывает поток
  /// ответа этого запроса (в modern это и есть отмена), stdio ничего не
  /// делает — отмена там уведомление клиента (D8).
  Future<void> abandon(Object requestId);

  /// Завершается, когда транспорт закрыт; всегда нормально, причина — в
  /// значении [McpTransportClosed].
  Future<McpTransportClosed> get done;

  /// Идемпотентно; останавливает процесс или HTTP-сессию.
  Future<void> close();
}

/// Почему транспорт закрыт: текст попадает в `mcp.server.failed` и в
/// результат-ошибку «disconnected during the call». Формируется кодом
/// транспорта и не содержит ни заголовков, ни значений `env` (D13).
final class McpTransportClosed {
  const McpTransportClosed(this.reason, {this.exitCode});

  final String reason;

  /// Код выхода процесса stdio; у HTTP `null`.
  final int? exitCode;

  @override
  String toString() => 'McpTransportClosed($reason)';
}

/// Открывает транспорт для сервера из описания.
///
/// Как использовать: хост регистрирует по фабрике на каждый ключ
/// [transports] (`stdio`, `http`) в `McpClientConnector`. Ошибка запуска —
/// исключение [McpTransportException] с текстом для `mcp.server.failed`.
///
/// `logger` — логгер сессии, уже несущий `session_id` (`BoundLogger`): через
/// него транспорт пишет свои события (`mcp.server.stderr`,
/// `mcp.server.closed`), добавляя только `server` (D13). Транспорт держит его
/// на всё время жизни соединения.
abstract interface class McpTransportFactory {
  Set<String> get transports;

  Future<McpTransport> open(
    McpServerConfig server, {
    required String cwd,
    required CancelToken cancel,
    required Logger logger,
  });
}

/// Транспорт не открылся (`spawn failed: …`, `invalid url`).
final class McpTransportException implements Exception {
  const McpTransportException(this.message);

  final String message;

  @override
  String toString() => 'McpTransportException: $message';
}
