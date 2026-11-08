/// Сценарий модели и фейковый MCP-хост для тестов встроенного агента (design.md
/// changes `add-embedded-agent-mode`, D8, и `add-provider-setup-ui`, Q28).
///
/// Почему отдельная точка входа: основной барель и `io.dart` не принимают
/// функцию модели и сценарий, а импорт `testing.dart` разрешён сторожем только
/// тестам и драйверу фикстур `codelab test-scenario` (D3). Так сценарий не
/// попадает в релизную сборку структурно, без dart-define.
library;

export 'src/testing/scripted_opener.dart' show scriptedEmbeddedAgentOpener;
export 'src/testing/fake_mcp_http_host.dart' show FakeMcpHttpHost;
export 'package:codelab_agent_mcp/testing.dart' show FakeMcpServer, FakeMcpTool;
