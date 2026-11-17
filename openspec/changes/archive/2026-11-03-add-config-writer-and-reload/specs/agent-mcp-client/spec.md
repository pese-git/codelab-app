## ADDED Requirements

### Requirement: Переподключение и состояние серверов сессии
Сессия `McpClientConnector` SHALL вести каждый свой сервер — из конфига (`origin: config`) и из `session/new` (`origin: session`) — по автомату `connecting`, `connected`, `failed`, `disabled` (`agent-core-architecture` §17.5.7; design.md, D11).

**Переходы:**
- `connected` → `failed`: процесс вышел, транспорт закрыт, HTTP 404 сессии;
- `connecting` → `failed`: ошибка или таймаут `initialize`/`tools/list`;
- `failed` → `connecting`: после задержки `min(30 с, 2^attempt с × (1 + 0.2·r))`, где `attempt` — число предыдущих сбоев подряд, а `r ∈ [0, 1)` — из `Random`, переданного хостом;
- `connecting` → `failed` без таймера: отмена токена запроса (`McpConnectRequest.cancel` — закрытие сессии или `dispose()` во время попытки, в том числе во время раскрытия секретов) с `lastError` `connection cancelled`, без `mcp.server.failed`;
- `disabled` — коллизия имён, `enabled: false` или `setEnabled(name, false)`.

Счётчик `attempt` SHALL сбрасываться только после соединения, прожившего не меньше 10 с. Таймеры SHALL создаваться через `Clock.timer`, а `r` — браться из `Random`; оба `McpClientConnector` SHALL получать от хоста (PKG-6), коннектор НЕ SHALL создавать `Timer` и читать системные часы. Сервер, не подключившийся при создании сессии, SHALL тоже переходить в `failed` и пробоваться в фоне; ответ `session/new` ждёт только первую попытку.

**Вызовы инструментов:**
- вызов в полёте при падении сервера SHALL завершаться результатом `isError` с текстом `MCP server <name> disconnected during the call: <reason>` и НЕ SHALL повторяться;
- вызов, пока сервер после успешного подключения не в `connected` (простой до повтора или идущая попытка), SHALL давать `isError` с текстом `MCP server <name> is not connected (retry in <n>s). Continue without it or try later.`, без обращения к транспорту; `n` — секунды до назначенной попытки, округлённые до целого и не меньше 1 (попытка не назначена — 1);
- инструменты SHALL переживать переподключение: после него вызов того же инструмента SHALL идти на новое соединение без пересоздания инструмента в реестре.

Инструменты упавшего сервера SHALL оставаться в реестре. Новый набор после таймерного переподключения SHALL применяться только через `takeUpdate()` на границе шага; неизменённый набор обновления НЕ SHALL давать. Явные действия, во время которых ход модели не идёт, — начальное подключение, `reconnect`, `setEnabled(name, true)`, `replaceServers`, — SHALL регистрировать инструменты в наборе сессии коннектора (`tools`, с проверкой коллизий) сразу по итогу своей попытки, а не по таймерной отметке «набор изменился»; реестр сессии ядра получает набор ближайшим `takeUpdate()` (до следующего шага или хода).

`close()` сессии и `AgentRuntime.dispose()` SHALL отменять таймеры и идущие подключения; сервер в `connecting` SHALL переходить в `failed` с `lastError` `connection cancelled` без `mcp.server.failed` и без таймера. Подключение, завершившееся после `close()`, SHALL закрываться сразу и не регистрироваться. Процессов stdio после `close()` НЕ SHALL оставаться.

**Порт `McpSessionTools`:**
- `servers` SHALL возвращать сводку каждого сервера сессии в порядке списка, в любом состоянии, включая `failed` и `disabled`: `McpServerSummary {name, toolCount, origin, transport, state, lastError, retryIn}`, где `retryIn` — только у `failed` с назначенным повтором, а `toolCount` у `disabled` — 0. Новые поля SHALL иметь умолчания конструктора (`origin: session`, `transport: stdio`, `state: connected`, без `lastError` и `retryIn`);
- `lastError` SHALL быть текстом кода CodeLab (правила «Наблюдаемость MCP без секретов») не длиннее 200 символов, без значений `env`, `headers` и секретов;
- `reconnect(name)` SHALL разрывать соединение и подключать сервер сразу; неизвестное имя или сервер в `disabled` — ничего. Сервер, удалённый идущей `replaceServers`, НЕ SHALL подключаться вызовами `setEnabled(name, true)` или `reconnect(name)`, пришедшими во время замены;
- `setEnabled(name, enabled)` SHALL менять состояние только в этой сессии и в памяти. `setEnabled(name, false)` SHALL закрывать транспорт, снимать таймер и давать `disabled` с `lastError` `disabled by /mcp disable`. `setEnabled(name, true)` SHALL подключать и сервер, выключенный конфигом (`enabled: false`), — с параметрами, которые коннектор получил последними, то есть применённого снимка (R6-1); сервер, выключенный коллизией имён, SHALL подключаться заново, а повторная коллизия — снова давать `disabled` с `lastError` `tool name collision: <имя инструмента>`.

Сервер конфига с `enabled: false` SHALL приходить коннектору с признаком `McpServerConfig.enabled == false` и находиться в состоянии `disabled` без подключения. `McpServerConfig.sameConnection` НЕ SHALL учитывать `enabled`; `replaceServers` SHALL считать сервер прежним, только если совпали параметры соединения и `enabled`, а у сервера с ручным выбором `setEnabled` — ещё и `connectTimeout`/`callTimeout` (R6-2): `true → false` закрывает сервер, `false → true` подключает новый. Сервер, выключенный `setEnabled(name, false)`, `replaceServers` с прежним описанием НЕ SHALL будить (R6-2).

Шаблоны `${secret:…}` сервера конфига SHALL раскрываться заново перед каждой попыткой подключения функцией раскрытия `McpConnectRequest.expandSecrets` (`McpSecretExpander`), которую передаёт ядро; коннектор зовёт её только для сервера с непустыми `secretValues`. Значение секрета НЕ SHALL храниться в коннекторе между попытками. Неудачное раскрытие — `McpSecretsException(reason)` — SHALL быть сбоем попытки: транспорт не открывается, состояние `failed`, `lastError` — `reason` (`secret <name> is not set`, `secret <name> cannot be read: <backend> is unavailable` или `no secret store`) без значения, затем обычная задержка повтора. Сервер при этом SHALL оставаться в `servers`.

**Логи:**
- `mcp.server.failed {server, transport, reason}` (warning) — на первом и каждом десятом подряд сбое; пишет только супервизор сессии коннектора: `McpClient` под ним свои записи сбоев НЕ SHALL писать (`logFailures: false`);
- `mcp.server.retry {server, attempt, delay_ms}` (info) — на остальных; `attempt` — номер сбоя подряд, считая с 1;
- `mcp.server.state {server, from, to}` (debug);
- `mcp.server.connect` — на каждом успехе.

Все записи — с `session_id`, без значений `env`, `headers` и текстов сервера.

#### Scenario: Задержки повторов
- **WHEN** fake-транспорт закрывается сразу после каждого подключения, используются `FakeClock` и `Random(0)`
- **THEN** попытки идут через ≈1, 2, 4, 8, 16, 30, 30 с, каждая задержка не меньше базовой и не больше базовой плюс 20 %, и не больше 30 с (`core/mcp-reconnect-after-crash`, E-04)

#### Scenario: Логи серии сбоев
- **WHEN** сервер падает сразу после каждого подключения одиннадцать раз подряд
- **THEN** `mcp.server.failed` записан на 1-м и 10-м сбое, остальные девять — `mcp.server.retry` с `attempt` 2…9 и 11; `McpClient` записей `mcp.server.failed` не добавил

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

#### Scenario: Инструмент после переподключения
- **WHEN** сервер `docs` упал и переподключился по таймеру с тем же набором инструментов, а модель вызывает `mcp__docs__search`
- **THEN** вызов идёт на новое соединение и завершается `completed`; `takeUpdate()` обновления не даёт, реестр сессии не менялся

#### Scenario: Явное переподключение регистрирует сразу
- **WHEN** сервер `docs` в `failed` с `retryIn` 20 с, и вызывается `reconnect("docs")`, а сервер отдаёт новый инструмент
- **THEN** попытка идёт сразу, не дожидаясь таймера; после возврата `reconnect` сервер `connected`, `tools` коннектора уже содержит новый инструмент, а ближайший `takeUpdate()` отдаёт обновление

#### Scenario: Отмена во время подключения
- **WHEN** первая попытка подключения сервера `slow` ещё идёт, и токен запроса отменяется
- **THEN** транспорт `slow` закрыт, состояние `failed` с `lastError` `connection cancelled`, `retryIn` нет, таймера повтора и записи `mcp.server.failed` нет

#### Scenario: Включение выключенного сервера с параметрами применённого снимка
- **WHEN** коннектор получил stdio-сервер `d` с `enabled: false` и `command: a`, затем `setEnabled("d", true)`
- **THEN** запущен процесс `a` — команда из описания, переданного коннектору; другой команды коннектор не знает (R6-1)

#### Scenario: Ручное действие во время замены
- **WHEN** `replaceServers` удаляет сервер `old`, и до её завершения вызываются `setEnabled("old", true)` и `reconnect("old")`
- **THEN** транспорт `old` не открывается, после замены `old` нет в `servers`
