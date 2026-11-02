## ADDED Requirements

### Requirement: Переподключение и состояние серверов сессии
Сессия `McpClientConnector` SHALL вести каждый свой сервер — из конфига (`origin: config`) и из `session/new` (`origin: session`) — по автомату `connecting`, `connected`, `failed`, `disabled` (`agent-core-architecture` §17.5.7; design.md, D11).

**Переходы:**
- `connected` → `failed`: процесс вышел, транспорт закрыт, HTTP 404 сессии;
- `connecting` → `failed`: ошибка или таймаут `initialize`/`tools/list`;
- `failed` → `connecting`: после задержки `min(30 с, 2^attempt с × (1 + 0.2·r))`, где `r ∈ [0, 1)` — из `Random`, переданного хостом;
- `disabled` — коллизия имён, `enabled: false` или `setEnabled(name, false)`.

Счётчик `attempt` SHALL сбрасываться только после соединения, прожившего не меньше 10 с. Таймеры SHALL создаваться через `Clock.timer` хоста (PKG-6). Сервер, не подключившийся при создании сессии, SHALL тоже переходить в `failed` и пробоваться в фоне; ответ `session/new` ждёт только первую попытку.

**Вызовы инструментов:**
- вызов в полёте при падении сервера SHALL завершаться результатом `isError` с текстом `MCP server <name> disconnected during the call: <reason>` и НЕ SHALL повторяться;
- вызов, пока сервер в `failed` после успешного подключения, SHALL давать `isError` с текстом `MCP server <name> is not connected (retry in <n>s). Continue without it or try later.`, без обращения к транспорту.

Инструменты упавшего сервера SHALL оставаться в реестре. Новый набор после переподключения SHALL применяться через `takeUpdate()` на границе шага.

`close()` сессии и `AgentRuntime.dispose()` SHALL отменять таймеры и идущие подключения. Подключение, завершившееся после `close()`, SHALL закрываться сразу и не регистрироваться. Процессов stdio после `close()` НЕ SHALL оставаться.

**Порт `McpSessionTools`:**
- `servers` SHALL возвращать сводку каждого сервера сессии в порядке списка: `McpServerSummary {name, toolCount, origin, transport, state, lastError, retryIn}`, где `retryIn` — только у `failed`;
- `lastError` SHALL быть текстом кода CodeLab (правила «Наблюдаемость MCP без секретов») не длиннее 200 символов;
- `reconnect(name)` SHALL разрывать соединение и подключать сервер сразу;
- `setEnabled(name, enabled)` SHALL менять состояние только в этой сессии и в памяти. `setEnabled(name, true)` SHALL подключать и сервер, выключенный конфигом (`enabled: false`); сервер, выключенный коллизией имён, SHALL подключаться заново, а повторная коллизия — снова давать `disabled` с `lastError` `tool name collision: <name>`.

Сервер конфига с `enabled: false` SHALL приходить коннектору с признаком `McpServerConfig.enabled == false` и находиться в состоянии `disabled` без подключения.

Шаблоны `${secret:…}` сервера конфига SHALL раскрываться заново перед каждой попыткой подключения функцией раскрытия, которую передаёт ядро. Значение секрета НЕ SHALL храниться в коннекторе между попытками. Неудачное раскрытие SHALL быть сбоем попытки: состояние `failed`, `lastError` `secret <name> is not set` или `secret <name> cannot be read: <backend> is unavailable` без значения, затем обычная задержка повтора.

**Логи:**
- `mcp.server.failed` (warning) — на первом и каждом десятом подряд сбое;
- `mcp.server.retry {server, attempt, delay_ms}` (info) — на остальных;
- `mcp.server.state {server, from, to}` (debug);
- `mcp.server.connect` — на каждом успехе.

Все записи — с `session_id`, без значений `env`, `headers` и текстов сервера.

#### Scenario: Задержки повторов
- **WHEN** fake-транспорт закрывается сразу после каждого подключения, используются `FakeClock` и `Random(0)`
- **THEN** попытки идут через ≈1, 2, 4, 8, 16, 30, 30 с, каждая задержка не меньше базовой и не больше базовой плюс 20 %, и не больше 30 с (`core/mcp-reconnect-after-crash`, E-04)

#### Scenario: Сброс после стабильного соединения
- **WHEN** сервер после трёх неудач подключился, проработал 10 с и упал
- **THEN** следующая задержка ≈1 с

#### Scenario: Вызов в полёте и вызов во время простоя
- **WHEN** сервер падает во время вызова `mcp__docs__search`, а модель вызывает его снова до переподключения
- **THEN** первый вызов — `isError` с `disconnected during the call`, второй — `isError` с `is not connected (retry in <n>s)`; повторной отправки первого вызова серверу нет

#### Scenario: Новый набор после переподключения
- **WHEN** сервер переподключается во время пакета вызовов и отдаёт в `tools/list` новый инструмент
- **THEN** пакет исполняется по прежнему набору, а следующий запрос к модели содержит новую схему

#### Scenario: Закрытие сессии во время ожидания повтора
- **WHEN** сервер в `failed` ждёт повтора, и сессия закрывается
- **THEN** таймер отменён, новых процессов не запускается, лог `mcp.server.retry` больше не появляется

#### Scenario: Подключение завершилось после закрытия
- **WHEN** подключение stdio-сервера завершается после `close()` сессии
- **THEN** транспорт закрыт сразу, инструменты не зарегистрированы, процесс сервера завершён

#### Scenario: Секрет не задан при повторе
- **WHEN** сервер конфига с заголовком `${secret:codelab/mcp/gh/authorization}` упал, а секрет к следующей попытке удалён
- **THEN** состояние `failed`, `lastError` — `secret codelab/mcp/gh/authorization is not set`, следующая попытка — по расписанию задержек

#### Scenario: Выключенный конфигом сервер
- **WHEN** конфиг задаёт сервер `docs` с `enabled: false`, затем `setEnabled("docs", true)`
- **THEN** до вызова `servers` содержит `docs` в состоянии `disabled` и процесс не запущен; после вызова сервер подключается в этой сессии, конфиг не изменён

#### Scenario: Состояние серверов
- **WHEN** у сессии серверы `github` (config, http, подключён, 12 инструментов) и `docs` (session, stdio, `failed` после выхода процесса с кодом 1)
- **THEN** `servers` возвращает обе сводки в порядке списка, у `docs` — `lastError` `process exited with code 1` и `retryIn`
