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

  /// Запросы, оставшиеся без ответа при живом транспорте (HTTP): оборвался
  /// поток ответа или произошёл локальный сбой (`HTTP 500` без тела ошибки
  /// JSON-RPC, слишком большое тело). Клиент завершает такой запрос
  /// «disconnected during the call» / «transport error» (`tools/call`) или
  /// повторяет один раз, если [McpRequestAbort.retryable] (`tools/list`,
  /// `server/discover`, `subscriptions/listen`; D8, D10). Для stdio — пустой
  /// поток.
  Stream<McpRequestAbort> get abortedRequests;

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

/// Запрос остался без ответа при живом транспорте.
///
/// Почему отдельный тип, а не ошибка JSON-RPC: локальный сбой транспорта не
/// должен выглядеть как ответ сервера и не может занимать коды JSON-RPC
/// (`basic/index.md`, «Error Codes»: диапазон -32000…-32019 — legacy, а
/// локальные ошибки нельзя спутать с ошибками собеседника).
///
/// Как использовать: транспорт эмитит значение в `abortedRequests`.
/// [retryable] — обрыв потока ответа, запрос без побочных эффектов можно
/// повторить один раз; `false` — локальная ошибка, повтор бесполезен.
/// [reason] — текст этого кода без секретов (`HTTP 500`), только для
/// неповторяемых сбоев.
final class McpRequestAbort {
  const McpRequestAbort(this.id, {this.reason, this.retryable = true});

  /// Идентификатор запроса, оставшегося без ответа.
  final Object id;

  /// Причина локального сбоя (`HTTP 500`); `null` у обрыва потока.
  final String? reason;

  /// `true` — обрыв потока, запрос без побочных эффектов можно повторить;
  /// `false` — локальный сбой, повтор бесполезен.
  final bool retryable;
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
