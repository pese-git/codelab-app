## ADDED Requirements

### Requirement: MCP-серверы в бинаре
`codelab-agent serve` SHALL собирать ядро с `AgentCoreServices.mcp`: `McpClientConnector` с stdio-транспортом `codelab_agent_io` и streamable HTTP на HTTP-клиенте хоста (design.md change `add-agent-mcp-client`, D3). Профиль `agent-serve` даёт capability `mcp` с транспортами `stdio` и `http`, поэтому `initialize` объявляет `mcpCapabilities.http: true`. До задачи 9.6 (итерация 3) хост подключает только `StdioMcpTransportFactory`, профиль сужает capability `mcp` до `{stdio}`, и `initialize` бинаря объявляет `mcpCapabilities.http: false`; сценарий «Возможности MCP в initialize» выполняется с задачи 9.6. В `codelab-agent serve --ws` capability `mcp` SHALL быть выключена с причиной профиля: серверы клиента пропускаются `mcp.server.skipped`, `initialize` объявляет `mcpCapabilities.http: false` — сознательное отступление от `03-Session Setup.md` (stdio MUST) ради безопасности: держатель токена WebSocket не должен запускать команды на машине агента (design.md, D3). Завершение процесса агента (EOF stdin для `--stdio`, сигнал) SHALL закрывать сессии и тем самым завершать процессы stdio-серверов не позже 10 с.

#### Scenario: Реальный stdio-сервер
- **WHEN** `codelab-agent serve --stdio --llm-script <сценарий>` получает `session/new` с fake stdio-сервером (`fake_mcp_stdio_server.dart`), модель вызывает `mcp__fake__echo {"text":"hi"}`, клиент одобряет вызов
- **THEN** `tool_call_update` — `completed` с `hi`, а после закрытия stdin агента процесс сервера с записанным pid не жив не позже 10 с (E-02, R-24; `apps/codelab_agent/test/mcp_stdio_process_test.dart`)

#### Scenario: WS-профиль не запускает MCP-серверы
- **WHEN** `codelab-agent serve --ws` получает `session/new` со stdio-сервером в `mcpServers`
- **THEN** ответ успешен, процесс сервера не запущен, лог `mcp.server.skipped` с причиной профиля, `initialize` этого соединения объявляет `mcpCapabilities.http: false`

#### Scenario: Возможности MCP в initialize
- **WHEN** бинарь `serve --stdio` отвечает на `initialize` (с задачи 9.6)
- **THEN** `agentCapabilities.mcpCapabilities` — `{"http": true, "sse": false}`
