## ADDED Requirements

### Requirement: Пакет codelab_agent_mcp и решение о библиотеке
MCP-клиент Dart-агента SHALL жить в пакете `packages/dart/codelab_agent_mcp` (agent-core-architecture §1.2):
- зависимости — только `codelab_agent_core`, `http`, `meta`, `async`;
- без `dart:io`, Flutter, ACP и клиентских пакетов (PKG-3).

Клиент SHALL быть собственным минимальным кодом (design.md, D1): ни один пакет pub.dev не прошёл чек-лист этапа 8. Сторонний код НЕ SHALL копироваться. Кодек JSON-RPC 2.0 SHALL быть собственным кодом пакета, не кодеком `codelab_acp_protocol` и не `json_rpc_2` (D4).

#### Scenario: Пакет web-безопасен
- **WHEN** запускается `fvm dart run melos run guard`
- **THEN** ни один файл `packages/dart/codelab_agent_mcp/lib/`, включая `lib/testing.dart`, не импортирует `dart:io`, `package:flutter/`, `package:codelab_acp_` и `package:codelab_client_`

#### Scenario: Решение записано
- **WHEN** ревьюер открывает design.md change `add-agent-mcp-client`
- **THEN** D1 содержит кандидатов, отметку по каждому пункту чек-листа и решение «свой клиент»

### Requirement: Эпоха сервера и версия протокола
`McpClient` SHALL быть клиентом dual-era по `docs/protocols/mcp/specification/basic/versioning.md` (design.md, D2, D5) и выполнять подключение одного сервера в пределах `connectTimeout` сервера (по умолчанию 10 с).

- **Эпоха.** Первая посылка — `server/discover` с modern `_meta`.
  - `DiscoverResult` с `2026-07-28` в `supportedVersions` → modern.
  - Распознанная modern-ошибка (`-32020`, `-32021`, `-32022`) или `DiscoverResult` без `2026-07-28` → нет общей версии. Соединение закрывается с `mcp.server.failed` и причиной `no common protocol version: server supports [...]`, отката на `initialize` НЕТ.
  - stdio: любая другая ошибка или отсутствие ответа за `min(5 с, connectTimeout / 2)` → legacy.
  - HTTP: `400` без распознанной modern-ошибки в теле, другой `4xx` → legacy.
  - Эпоха SHALL кэшироваться на время жизни процесса (stdio) или на `origin` URL (HTTP) в памяти и определяться заново один раз, если кэш не подтвердился.
- **Modern.** Каждый запрос SHALL нести `_meta` с `io.modelcontextprotocol/protocolVersion: "2026-07-28"`, `io.modelcontextprotocol/clientCapabilities: {}` и `io.modelcontextprotocol/clientInfo`. Клиент SHALL трактовать отсутствующий `resultType` как `complete`, а неизвестный — как ответ не по схеме. При `capabilities.tools.listChanged` клиент SHALL открывать `subscriptions/listen` с `toolsListChanged: true`.
- **Legacy.** Клиент SHALL выполнить `initialize` с `protocolVersion: "2025-11-25"` и пустыми `capabilities`, принять в ответе `2025-11-25`, `2025-06-18` или `2025-03-26` (иначе `mcp.server.failed` с `unsupported protocol version <v>`) и отправить `notifications/initialized`. `initialize` НЕ SHALL отменяться уведомлением. Клиент SHALL отвечать на `ping` пустым результатом и принимать входящие пакеты JSON-RPC (массив).
- **Обе эпохи.** `tools/list` SHALL читаться по всем страницам `nextCursor`, не больше 100 страниц. Запросы сервера, кроме legacy-`ping`, SHALL получать `-32601`. Исходящие id SHALL быть целыми числами без повторов в пределах соединения.

Определённая эпоха SHALL логироваться `mcp.server.era`. Deprecated HTTP+SSE и `2024-11-05` НЕ SHALL поддерживаться.

#### Scenario: Modern-сервер
- **WHEN** fake-сервер эпохи modern отвечает на `server/discover` `supportedVersions: ["2026-07-28"]` и `capabilities.tools.listChanged: true`, а `tools/list` отдаёт два инструмента на двух страницах
- **THEN** `initialize` не отправлен, каждый запрос несёт `_meta.io.modelcontextprotocol/protocolVersion: "2026-07-28"`, открыт `subscriptions/listen`, получены оба инструмента, логи `mcp.server.era` с `era: modern` и `mcp.server.connect` с `tools: 2`

#### Scenario: Legacy-сервер на stdio с откатом по ошибке
- **WHEN** stdio-сервер эпохи legacy отвечает на `server/discover` ошибкой `-32601`
- **THEN** клиент отправляет `initialize` с `protocolVersion: "2025-11-25"`, затем `notifications/initialized`, получает инструменты; `mcp.server.era` — `era: legacy`, `probe: fallback_error`

#### Scenario: Legacy-сервер молчит на пробу
- **WHEN** stdio-сервер не отвечает на `server/discover`
- **THEN** через время пробы клиент откатывается на `initialize`; поздний ответ на пробу, если придёт, игнорируется с `mcp.message.ignored`

#### Scenario: Legacy-сервер по HTTP
- **WHEN** HTTP-сервер отвечает на `server/discover` `400` с пустым телом
- **THEN** клиент выполняет `initialize`, запоминает `Mcp-Session-Id` и продолжает в legacy

#### Scenario: Несовместимая версия
- **WHEN** modern-сервер отвечает на `server/discover` ошибкой `-32022` с `data.supported: ["2027-01-01"]`
- **THEN** `initialize` не отправлен, соединение закрыто, `mcp.server.failed` называет `2027-01-01`, сессия создана без инструментов сервера

#### Scenario: Legacy-версия вне набора
- **WHEN** legacy-сервер отвечает на `initialize` `protocolVersion: "2024-11-05"`
- **THEN** соединение закрыто, `mcp.server.failed` называет версию

#### Scenario: Таймаут подключения
- **WHEN** legacy-сервер не отвечает на `initialize` до конца `connectTimeout`
- **THEN** транспорт закрыт, `notifications/cancelled` для `initialize` не отправлен, лог `mcp.server.failed`

#### Scenario: Бесконечная пагинация
- **WHEN** сервер на каждую страницу `tools/list` возвращает новый `nextCursor`
- **THEN** после 100 страниц соединение закрыто с причиной `tools/list pagination did not end`

#### Scenario: Кэш эпохи HTTP
- **WHEN** две сессии подключают HTTP-серверы с одним `origin`, первая определила `legacy`
- **THEN** вторая пропускает пробу, `mcp.server.era` — `probe: cached`

### Requirement: Вызов инструмента, отмена и таймаут
`McpClient.callTool` SHALL отправлять `tools/call {name, arguments}` с исходным именем инструмента сервера (в modern — с `_meta` протокола).

- **Отмена.** При отмене токена вызова клиент SHALL сразу завершить вызов `CancelledException` и один раз подать сигнал отмены по `basic/patterns/cancellation.md`:
  - stdio (обе эпохи) — `notifications/cancelled {requestId, reason}`;
  - Streamable HTTP modern — только закрытие потока ответа запроса, без `notifications/cancelled`;
  - Streamable HTTP legacy — `notifications/cancelled` и закрытие потока ответа.

  Ответ, пришедший после отмены или таймаута, SHALL игнорироваться с `mcp.message.ignored` и не менять состояние.
- **Таймаут** вызова по умолчанию — 10 минут. По истечении — тот же сигнал отмены и результат-ошибка `MCP server <id> did not answer tools/call within <n> s.`
- **Обрыв.** Закрытие транспорта или потока ответа во время вызова SHALL давать результат-ошибку `MCP server <id> disconnected during the call: <reason>` без автоматического повтора `tools/call`. Вызов сервера, упавшего раньше, — `MCP server <id> is not connected. Continue without it.`
- **Ошибки ответа:**
  - ошибка JSON-RPC — `MCP server <id> returned an error: <message> (code <code>)`;
  - ответ не по схеме или неизвестный `resultType` — `MCP server <id> returned an invalid tools/call result.`;
  - `resultType: input_required` — `MCP server <id> asked for client input, which is not supported.`

Ни одна из этих ошибок НЕ SHALL прерывать ход (TOOL-3).

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

### Requirement: Обновление списка инструментов
По `notifications/tools/list_changed` клиент SHALL перечитать `tools/list`; в modern уведомление принимается только с `io.modelcontextprotocol/subscriptionId` своей подписки `subscriptions/listen`, в legacy — с общего канала stdio или GET-потока HTTP. Уведомление во время перечитывания SHALL ставить один повтор, а не параллельное перечитывание. Новый набор SHALL проходить те же правила имён и коллизий, что при подключении. Ядро SHALL применять его только на границе шага, до сборки запроса к модели, и никогда внутри пакета вызовов. Применение SHALL сопровождаться логом `mcp.tools.changed` с добавленными и удалёнными именами.

#### Scenario: Новый инструмент между шагами
- **WHEN** сервер присылает `list_changed` с новым инструментом `lookup` во время исполнения пакета вызовов
- **THEN** вызовы пакета исполняются по прежнему набору, а следующий запрос к модели содержит схему `mcp__fake__lookup`

#### Scenario: Два уведомления подряд
- **WHEN** сервер присылает два `list_changed` подряд
- **THEN** клиент делает не больше двух `tools/list`, и итоговый набор соответствует последнему ответу

### Requirement: stdio-транспорт MCP
`StdioProcessTransport` пакета `codelab_agent_io` (`lib/src/mcp/stdio_process_transport.dart`) SHALL реализовывать порт ядра `McpTransport`:
- **Запуск.** Процесс `command` с `args` в рабочей папке сессии; родительское окружение не наследуется.
- **Окружение.** Только переменные базового набора §4.5 (`PATH`, `HOME`, `USER`, `LANG`, `LC_ALL`, `TMPDIR`, `SHELL`) со значениями хоста и `env` сервера поверх них (ENV-6).
- **Кадры.** Одна строка UTF-8 на сообщение. Входящая строка длиннее 16 МиБ SHALL закрывать транспорт. stderr SHALL читаться всегда и попадать в лог только уровнем debug.
- **Закрытие.** Закрыть stdin, ждать выхода 2 с, отправить `SIGTERM` дереву процессов, через 5 с — `SIGKILL` оставшимся. Лог `mcp.server.closed`.

#### Scenario: Окружение по allowlist
- **WHEN** тестовый процесс хоста имеет `SECRET_X=1`, а сервер запускается с `env: [{"name":"API_KEY","value":"k"}]`
- **THEN** процесс сервера видит `API_KEY=k` и `PATH` хоста и не видит `SECRET_X`

#### Scenario: Сервер не выходит по EOF
- **WHEN** процесс сервера игнорирует закрытие stdin и `SIGTERM`
- **THEN** `close()` завершает его `SIGKILL` вместе с потомками не позже 10 с

#### Scenario: Ошибка запуска
- **WHEN** `command` указывает на несуществующий файл
- **THEN** подключение заканчивается `mcp.server.failed` с причиной `spawn failed: …`, сессия создаётся без инструментов сервера

### Requirement: Транспорт streamable HTTP
`StreamableHttpTransport` пакета `codelab_agent_mcp` SHALL работать на `http.Client`, переданном хостом, по `basic/transports/streamable-http.md`.

- **Обе эпохи.**
  - Каждое сообщение — `POST` с `Content-Type: application/json` и `Accept: application/json, text/event-stream`; заголовки сервера идут вместе со служебными, служебные их перекрывают.
  - Ответ запроса принимается как `application/json` или как поток `text/event-stream` (`SseDecoder` ядра, комментарии keep-alive пропускаются); для уведомлений — `202 Accepted`.
  - Редиректы не выполняются. Принимаются только схемы `http` и `https`. Тело ответа больше 16 МиБ отклоняется.
- **Modern.**
  - Каждый POST несёт `MCP-Protocol-Version: 2026-07-28` и `Mcp-Method`, `tools/call` — ещё `Mcp-Name` и `Mcp-Param-<имя>` для свойств `inputSchema` с `x-mcp-header`. Значения вне безопасного ASCII кодируются `=?base64?…?=`.
  - Ответ `-32020` на `tools/call` SHALL давать один `tools/list` и один повтор вызова с новым id.
  - `Mcp-Session-Id`, GET и `DELETE` НЕ SHALL использоваться.
- **Legacy.**
  - `Mcp-Session-Id` из ответа на `initialize` шлётся в следующих запросах; `MCP-Protocol-Version` — для `2025-06-18` и `2025-11-25`.
  - GET-поток уведомлений открывается при `tools.listChanged` (`405` — потока нет).
  - `404` при выданном `Mcp-Session-Id` — конец соединения.
  - При закрытии — `DELETE` (best effort, 2 с).
  - Поток ответа, закрытый сервером до ответа после события с `id`, SHALL возобновляться `GET` с `Last-Event-ID` после паузы `retry` (без `retry` — 1 с), не больше 5 раз на запрос (`docs/protocols/mcp/specification/2025-11-25/basic/transports.md`). Это дочитывание того же ответа, а не новый `tools/call`.
- **Повтор после обрыва.** Без возобновления оборванный запрос `tools/list` и `server/discover` SHALL повторяться один раз с новым id. `tools/call` НЕ SHALL повторяться автоматически, результат — «disconnected during the call».

#### Scenario: Ответ потоком SSE
- **WHEN** `MockClient` отвечает на `tools/call` потоком `text/event-stream` с уведомлением `notifications/progress` и затем ответом
- **THEN** вызов получает результат из ответа, уведомление записано `mcp.message.ignored`, транспорт жив

#### Scenario: Заголовки modern-вызова
- **WHEN** modern-клиент вызывает инструмент `get_weather`, у которого свойство `region` помечено `x-mcp-header: Region`, с аргументами `{"region": "Москва"}`
- **THEN** POST несёт `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method: tools/call`, `Mcp-Name: get_weather` и `Mcp-Param-Region: =?base64?…?=` с UTF-8 значения, и не несёт `Mcp-Session-Id`

#### Scenario: Сессия legacy-сервера
- **WHEN** legacy-сервер отвечает на `initialize` с заголовком `Mcp-Session-Id: s-1` и версией `2025-06-18`
- **THEN** каждый следующий `POST` и `DELETE` при закрытии несут `Mcp-Session-Id: s-1` и `MCP-Protocol-Version: 2025-06-18`

#### Scenario: Редирект не выполняется
- **WHEN** сервер отвечает `307` с `Location` на другой хост
- **THEN** запрос на другой хост не отправлен, подключение заканчивается `mcp.server.failed`

#### Scenario: Опрос legacy-потока
- **WHEN** legacy-сервер `2025-11-25` отправляет событие `id: e1` с `retry: 100` и закрывает соединение потока ответа на `tools/call` до ответа
- **THEN** через 100 мс клиент отправляет `GET` с `Last-Event-ID: e1`, получает ответ вызова из возобновлённого потока, второго `tools/call` нет

#### Scenario: Обрыв modern-потока на вызове
- **WHEN** поток ответа modern-сервера на `tools/call` обрывается без ответа
- **THEN** результат — «disconnected during the call», повторного `tools/call` нет; оборванный `tools/list` повторён один раз с новым id

#### Scenario: Истёкшая legacy-сессия
- **WHEN** после legacy-подключения `POST` получает `404`
- **THEN** транспорт закрыт с причиной `HTTP session expired`, следующий вызов инструментов сервера — ошибка «is not connected»

### Requirement: Проекция результата MCP-инструмента
`McpTool` SHALL сводить `CallToolResult.content` в один `TextContent` в порядке блоков (части соединяются `\n`):
- `text` — как есть;
- `resource` с `text` — `<resource uri="<uri>">\n<text>\n</resource>`;
- `resource` с `blob` — `[binary resource <uri>, <n> bytes, not shown]`;
- `resource_link` — `[resource link: <uri> (<name>)]`;
- `audio` — `[audio omitted: <mimeType>, <n> bytes]`;
- `image` — отдельный `ImageContent`, если модель шага принимает картинки, иначе `[image omitted: the model does not accept images (<mimeType>)]`;
- неизвестный тип — `[unsupported content: <type>]`;
- пустой `content` — канонический JSON `structuredContent`, если он есть, иначе `[MCP tool returned no content]`.

`isError: true` SHALL давать outcome `failed`.

#### Scenario: Смешанное содержимое
- **WHEN** сервер возвращает блоки `text` «a», `resource_link` `file:///x` с именем `x` и `resource` с текстом «b»
- **THEN** результат — один огороженный `TextContent`: `a\n[resource link: file:///x (x)]\n<resource uri="…">\nb\n</resource>`

#### Scenario: Картинка для модели без картинок
- **WHEN** модель шага не принимает картинки, а сервер возвращает `image` `image/png`
- **THEN** в результате текст `[image omitted: the model does not accept images (image/png)]` и нет `ImageContent`

#### Scenario: Ошибка инструмента
- **WHEN** сервер возвращает `{"content":[{"type":"text","text":"not found"}],"isError":true}`
- **THEN** `tool_call_update` — `failed`, модель получает огороженный текст `not found`

### Requirement: Наблюдаемость MCP без секретов
Клиент, транспорты и ядро SHALL писать события `mcp.server.skipped`, `mcp.server.era`, `mcp.server.connect`, `mcp.server.failed`, `mcp.server.closed`, `mcp.server.stderr` (debug), `mcp.tools.changed`, `mcp.tool.invalid`, `mcp.tool.description_truncated`, `mcp.call.cancelled`, `mcp.call.timeout`, `mcp.message.ignored` (debug) с полями design.md, D13, `session_id` и `server`. Значения `env`, `headers`, `args`, `Mcp-Session-Id`, `Mcp-Param-*` и тела сообщений НЕ SHALL попадать ни в одно поле лога. Описания серверов НЕ SHALL записываться в журнал сессии.

#### Scenario: Секреты не в логе
- **WHEN** сессия подключает stdio-сервер с `env` `API_KEY=sk-123` и HTTP-сервер с заголовком `Authorization: Bearer t-456`, оба сервера падают
- **THEN** ни одна запись `RecordingLogger` и ни одна строка журнала сессии не содержит `sk-123` и `t-456`

### Requirement: Fake MCP-сервер для тестов
`codelab_agent_mcp` SHALL предоставлять в `lib/testing.dart` собственный `FakeMcpServer` с эпохой `modern`, `legacy` или `dualEra` (design.md, D15):
- **Modern:** `server/discover`, проверка `_meta` (`-32602`, `-32022`), `subscriptions/listen`, `resultType`, проверка HTTP-заголовков (`-32020`).
- **Legacy:** `initialize` с настраиваемой версией ответа, `ping`, ошибка или молчание на `server/discover`, `Mcp-Session-Id`, GET-поток, `DELETE`.
- **Общий сценарий:** инструменты, результаты по имени, задержка, ожидание отмены, падение, `list_changed`, `input_required`.
- **Запись:** полученные `tools/call`, `notifications/cancelled` и закрытые потоки ответов.
- **Входы:** пара транспортов в памяти и HTTP-обработчик для `MockClient`.

Реальный процесс fake-сервера для e2e SHALL запускаться точкой входа `apps/codelab_agent/test/support/fake_mcp_stdio_server.dart` поверх того же `FakeMcpServer`.

#### Scenario: Сервер записывает вызовы
- **WHEN** тест вызывает `mcp__fake__echo {"text":"hi"}` через fake-сервер в памяти
- **THEN** `FakeMcpServer.calls` содержит ровно `{"name":"echo","arguments":{"text":"hi"}}`
