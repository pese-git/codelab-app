## MODIFIED Requirements

### Requirement: Вызов инструмента, отмена и таймаут
`McpClient.callTool` SHALL отправлять `tools/call {name, arguments}` с исходным именем инструмента сервера (в modern — с `_meta` протокола).

- **Отмена.** При отмене токена вызова клиент SHALL сразу завершить вызов `CancelledException` и один раз подать сигнал отмены по `basic/patterns/cancellation.md`:
  - stdio (обе эпохи) — `notifications/cancelled {requestId, reason}`;
  - Streamable HTTP modern — только закрытие потока ответа запроса, без `notifications/cancelled`;
  - Streamable HTTP legacy — `notifications/cancelled` и закрытие потока ответа.

  Ответ, пришедший после отмены или таймаута, SHALL игнорироваться с `mcp.message.ignored` и не менять состояние.
- **Таймаут** вызова — `McpServerConfig.callTimeout` сервера (ключ конфигурации `mcp.servers[*].call_timeout`, design.md change `add-agent-configuration`, D10). Если он `null` (серверы `session/new` и серверы конфига без ключа) — `McpClientOptions.callTimeout` коннектора, по умолчанию 10 минут. По истечении — тот же сигнал отмены и результат-ошибка `MCP server <id> did not answer tools/call within <n> s.`, где `<n>` — таймаут этого сервера в секундах.
- **Обрыв.** Закрытие транспорта (`done`) или обрыв потока ответа запроса при живом транспорте (`abortedRequests` порта `McpTransport`) во время вызова SHALL давать результат-ошибку `MCP server <id> disconnected during the call: <reason>` без автоматического повтора `tools/call`. Вызов сервера, упавшего раньше, — `MCP server <id> is not connected. Continue without it.`
- **Ошибки ответа:**
  - ошибка JSON-RPC — `MCP server <id> returned an error: <message> (code <code>)`;
  - локальный сбой HTTP-транспорта без JSON-RPC-тела — `MCP server <id> transport error: <reason>`, без кода;
  - ответ не по схеме или неизвестный `resultType` — `MCP server <id> returned an invalid tools/call result.`;
  - `resultType: input_required` — `MCP server <id> asked for client input, which is not supported.`

Ни одна из этих ошибок НЕ SHALL прерывать ход (TOOL-3). Ошибка в потоке `incoming` или `abortedRequests` транспорта SHALL переводить клиент сервера в «не подключён» с `mcp.server.failed` и причиной `disconnected: transport error`.

#### Scenario: Отмена хода доходит до stdio-сервера
- **WHEN** fake stdio-сервер держит `tools/call`, а клиент ACP присылает `session/cancel`
- **THEN** сервер получает ровно одно `notifications/cancelled` с `requestId` вызова, `tool_call_update` — `cancelled`, ход завершается `stopReason: cancelled`

#### Scenario: Отмена на modern HTTP
- **WHEN** вызов modern HTTP-сервера отменён, пока поток ответа открыт
- **THEN** поток ответа закрыт клиентом, POST с `notifications/cancelled` не отправлен, итог `cancelled`

#### Scenario: Ответ сразу после отмены
- **WHEN** ответ сервера на вызов приходит после сигнала отмены
- **THEN** итог вызова остаётся `cancelled`, ответ записан в лог `mcp.message.ignored` с `kind: late_response`

#### Scenario: Процесс сервера упал во время вызова
- **WHEN** процесс stdio-сервера выходит, пока вызов ждёт ответа
- **THEN** результат вызова — ошибка `MCP server fake disconnected during the call: …`, ход продолжается следующим шагом модели

#### Scenario: Ошибка сервера
- **WHEN** сервер отвечает на `tools/call` ошибкой `-32602` «Unknown tool»
- **THEN** результат — ошибка с этим сообщением и кодом, outcome `failed`, ход продолжается

#### Scenario: Сервер просит ввод
- **WHEN** modern-сервер отвечает на `tools/call` `resultType: "input_required"`
- **THEN** результат — ошибка `… asked for client input, which is not supported.`, повторного `tools/call` нет

#### Scenario: Таймаут сервера сильнее общего
- **WHEN** `McpClientConnector` создан с `McpClientOptions(callTimeout: 10 min)`, сервер `a` имеет `callTimeout: 2 s`, сервер `b` — `null`, и оба не отвечают на `tools/call` на `FakeClock`
- **THEN** через 2 с вызов `a` завершается ошибкой `… within 2 s.` и сигналом отмены, а вызов `b` ещё ждёт до 600 с
