import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Подставной [McpConnector] для тестов ядра: ядро не знает протокола MCP
/// (design.md change `add-agent-mcp-client`, D3), поэтому о подключении
/// серверов договаривается только через порт.
///
/// Как использовать: [transports] задаёт то, что умеет «коннектор»;
/// [connect] запоминает запросы в [requests], а возвращённый набор
/// инструментов берётся из [toolsOf] (по умолчанию пустой).
final class FakeMcpConnector implements McpConnector {
  FakeMcpConnector({
    Set<String> transports = const {'stdio', 'http'},
    this.toolsOf,
    this.onClose,
    this.failWith,
  }) : transports = Set.unmodifiable(transports);

  @override
  final Set<String> transports;

  /// Инструменты по запросу; `null` — серверов нет.
  final List<AgentTool> Function(McpConnectRequest request)? toolsOf;

  /// Зовётся при `McpSessionTools.close()` — порядок закрытия в тестах.
  final void Function()? onClose;

  /// Если задан, [connect] бросает его: сбой коннектора целиком.
  final Object? failWith;

  final requests = <McpConnectRequest>[];
  final sessions = <FakeMcpSessionTools>[];

  @override
  Future<McpSessionTools> connect(McpConnectRequest request) async {
    requests.add(request);
    if (failWith case final error?) {
      throw error;
    }
    final tools = toolsOf?.call(request) ?? const <AgentTool>[];
    final session = FakeMcpSessionTools(
      tools: tools,
      onClose: onClose,
      servers: [
        for (final s in request.servers)
          McpServerSummary(
            name: s.name,
            toolCount: tools
                .where((t) => t.name.startsWith(mcpServerPrefix(s.name)))
                .length,
          ),
      ],
    );
    sessions.add(session);
    return session;
  }
}

final class FakeMcpSessionTools implements McpSessionTools {
  FakeMcpSessionTools({
    required this.tools,
    required this.servers,
    this.onClose,
  });

  final void Function()? onClose;

  @override
  final List<AgentTool> tools;

  @override
  final List<McpServerSummary> servers;

  var closed = 0;
  McpToolsUpdate? pending;

  @override
  McpToolsUpdate? takeUpdate() {
    final update = pending;
    pending = null;
    return update;
  }

  @override
  Future<void> replaceServers(List<McpServerConfig> servers) async {}

  @override
  Future<void> close() async {
    closed++;
    onClose?.call();
  }
}
