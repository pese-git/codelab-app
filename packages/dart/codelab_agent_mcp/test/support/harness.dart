// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_mcp/src/mcp_client.dart';
import 'package:codelab_agent_mcp/src/protocol.dart';
import 'package:codelab_agent_mcp/testing.dart';

/// Общая обвязка тестов клиента: детерминированные часы и логгер (PKG-6),
/// подключение к `FakeMcpServer` по порту ядра.
///
/// Как использовать: `h.connect(server)` открывает транспорт нужного вида
/// (`stdio` или `http`) и подключает клиента; время двигается только через
/// `h.clock.elapse`.
final class McpHarness {
  final clock = FakeClock();
  final logger = RecordingLogger();

  Future<McpClient> connect(
    FakeMcpServer server, {
    String kind = 'stdio',
    String name = 'fake',
    Duration connectTimeout = const Duration(seconds: 10),
    McpEraCache? cache,
    McpClientOptions options = const McpClientOptions(),
    void Function(List<McpToolDefinition> tools)? onToolsChanged,
  }) => McpClient.connect(
    server: kind == 'http'
        ? McpHttpServerConfig(
            name: name,
            url: Uri.parse('https://mcp.example.com/mcp'),
            connectTimeout: connectTimeout,
          )
        : McpStdioServerConfig(
            name: name,
            command: 'fake-mcp',
            connectTimeout: connectTimeout,
          ),
    transport: server.connect(kind: kind),
    clock: clock,
    logger: logger,
    sessionId: const SessionId('s1'),
    options: options,
    eraCache: cache,
    onToolsChanged: onToolsChanged,
  );

  /// Поля единственной записи лога `event`.
  Map<String, Object?> logged(String event) =>
      logger.eventsOf(event).single.fields;
}
