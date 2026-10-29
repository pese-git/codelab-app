/// Тестовая поддержка MCP-клиента: `FakeMcpServer` (design.md change
/// `add-agent-mcp-client`, D15). Только для тестов и тестовых хостов,
/// основной барель его не экспортирует. Web-безопасен так же, как пакет.
library;

export 'src/fake_mcp_server.dart';
