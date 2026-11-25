## MODIFIED Requirements

### Requirement: Наблюдаемость MCP без секретов
Клиент, транспорты и ядро SHALL писать события `mcp.server.skipped`, `mcp.server.era`, `mcp.server.connect`, `mcp.server.failed`, `mcp.server.closed`, `mcp.server.stderr` (debug), `mcp.tools.changed`, `mcp.tools.refresh_failed`, `mcp.tool.invalid`, `mcp.tool.description_truncated`, `mcp.call.cancelled`, `mcp.call.timeout`, `mcp.message.ignored` (debug) с полями design.md, D13, `session_id` и `server`. События `mcp.server.connect` и `mcp.server.failed` SHALL нести и поле `origin` (`session` — сервер из `mcpServers` клиента, `config` — сервер конфигурации): по WebSocket с `--local-exec` процессы серверов клиента запускаются на машине агента, и источник запуска должен быть виден в логе (design.md change `add-agent-remote-exec`, D10, Q3). Значения `env`, `headers`, `args`, `Mcp-Session-Id`, `Mcp-Param-*` и тела сообщений НЕ SHALL попадать ни в одно поле лога. Поле `reason` SHALL содержать только текст кода CodeLab: `message` и `data` ошибки сервера, неизвестный `resultType` и `serverInfo` в него НЕ SHALL входить. Версии протокола от сервера (`protocolVersion`, `supportedVersions`) SHALL входить только после проверки формата `YYYY-MM-DD`; не прошедшие проверку SHALL отбрасываться. Имя метода запроса сервера SHALL попадать только в `mcp.message.ignored` с `kind: server_request` (debug), не длиннее 64 символов по рунам; ошибка JSON-RPC описывается как `'<method> failed (code N)'`, непредвиденное исключение — `unexpected error: <runtimeType>`; длина — не больше 200 символов с обрезкой по рунам. Описания серверов НЕ SHALL записываться в журнал сессии.

#### Scenario: Секреты не в логе
- **WHEN** сессия подключает stdio-сервер с `env` `API_KEY=sk-123` и HTTP-сервер с заголовком `Authorization: Bearer t-456`, оба сервера падают
- **THEN** ни одна запись `RecordingLogger` и ни одна строка журнала сессии не содержит `sk-123` и `t-456`

#### Scenario: Текст ошибки сервера не в логе
- **WHEN** сервер отвечает на `tools/list` при подключении ошибкой `-32603` с `message` `token sk-789 expired`
- **THEN** `mcp.server.failed` имеет причину `tools/list failed (code -32603)`, и ни одна запись лога не содержит `sk-789`

#### Scenario: Источник сервера в логе
- **WHEN** сессия подключает stdio-сервер `a` из `mcpServers` клиента и stdio-сервер `b` из конфигурации
- **THEN** `mcp.server.connect` сервера `a` несёт `origin: "session"`, сервера `b` — `origin: "config"`
