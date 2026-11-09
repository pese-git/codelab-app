## ADDED Requirements

### Requirement: Поток состояний серверов сессии
`McpSessionTools` SHALL предоставлять `Stream<List<McpServerSummary>> get changes` — полный список сводок серверов сессии в порядке `servers` после каждой смены состояния (`connecting`, `connected`, `failed`, `disabled`), числа инструментов, `lastError` или состава серверов (`replaceServers`, `setEnabled`, `reconnect`) (`17-5-agent-setup.md`, OQ4; design.md change `add-provider-setup-ui`, D12). Поток SHALL быть широковещательным, НЕ SHALL повторять последнее значение новому подписчику (снимок — `servers`) и SHALL закрываться в `close()`. Сводки SHALL подчиняться тем же правилам, что `servers`: `lastError` — текст кода CodeLab без текстов сервера и секретов.

`AgentRuntime` SHALL давать хосту порт состояния MCP сессии (`mcpStatus(SessionId)`: снимок `servers`, `changes`, `reconnect(name)`), для любой открытой сессии: у сессии без MCP-серверов `servers` пуст, а `changes` SHALL присылать список, когда серверы появятся после перезагрузки конфига (решение Q18 design.md). Для неизвестной или закрытой сессии — `null`. Новых методов и полей ACP порт НЕ SHALL вводить.

#### Scenario: Сбой и восстановление сервера
- **WHEN** у сессии сервер `docs` в `connected`, его процесс завершается, затем по `reconnect('docs')` подключается снова
- **THEN** подписчик `changes` получает списки с `docs` в `failed` (с `retryIn`), `connecting` и `connected` в этом порядке; `servers` после этого показывает `connected`

#### Scenario: Первый сервер после перезагрузки конфига
- **WHEN** сессия открыта без MCP-серверов, хост получил `mcpStatus` и подписан на `changes`, затем в конфиг добавлен сервер `docs`, и агент перечитал конфиг
- **THEN** порт был не `null` с пустым `servers`, подписчик получает список с `docs` (`connecting`, затем `connected`) без повторного вызова `mcpStatus`

#### Scenario: Поток закрывается с сессией
- **WHEN** сессия закрывается
- **THEN** поток `changes` завершается, таймеры повторов отменены
