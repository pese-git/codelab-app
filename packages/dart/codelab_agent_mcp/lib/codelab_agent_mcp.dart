/// MCP-клиент Dart-агента CodeLab (`agent-core-architecture` §1.2, §6.4;
/// design.md change `add-agent-mcp-client`).
///
/// Web-безопасен: ни `dart:io`, ни Flutter, ни ACP (PKG-3, проверяет
/// `melos run guard`). Хост собирает `McpClientConnector` и передаёт его в
/// `AgentCoreServices.mcp`.
library;

// Барель — API хоста: внутренности (клиент, кодек, модели, McpTool) наружу не
// выходят, тесты пакета импортируют `src/`.
export 'src/connector.dart' show McpClientConnector, McpTransports;
export 'src/mcp_client.dart' show McpClientOptions, McpEraCache;
export 'src/streamable_http.dart' show StreamableHttpTransportFactory;

const codelabAgentMcpPackageName = 'codelab_agent_mcp';
