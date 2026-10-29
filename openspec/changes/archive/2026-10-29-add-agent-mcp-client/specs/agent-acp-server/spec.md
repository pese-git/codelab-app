## MODIFIED Requirements

### Requirement: initialize
Ответ на `initialize` SHALL содержать ровно поля и значения §13.2 документа ядра: `protocolVersion: 1`; `agentCapabilities` с `loadSession` (`true` при capability `sessionPersistence`, иначе `false`), `promptCapabilities` (`image: true`, `audio: false`, `embeddedContext: true`), `mcpCapabilities` (`http: true`, если в плане ядра capability `mcp` включена с транспортом `http`, иначе `false`; `sse: false` всегда), `sessionCapabilities.list: {}` при `sessionPersistence`; `agentInfo`; `authMethods: []`. Флага stdio в `mcpCapabilities` нет: stdio обязателен для каждого агента (`03-Session Setup.md`, «MCP Servers»); профиль без stdio (`mobile`) и WS-профиль бинаря, где capability `mcp` выключена (design.md change `add-agent-mcp-client`, D3), — отклонения §13.15 документа ядра.

`clientCapabilities` SHALL сохраняться на соединение и определять env сессий этого соединения; отсутствие поля SHALL логироваться `acp.client_capabilities.absent`. Повторный `initialize` SHALL давать `-32600` «already initialized», любой метод `session/*` до `initialize` — `-32600` «initialize required». Метод `authenticate` SHALL давать `-32601` (§13.3).

#### Scenario: Ответ codelab-app
- **WHEN** клиент присылает `initialize` с `protocolVersion: 1` и `fs`/`terminal` capabilities
- **THEN** ответ совпадает с фикстурой `acp/initialize-capabilities`, где `mcpCapabilities` — `{"http": true, "sse": false}`

#### Scenario: Сессия до initialize
- **WHEN** первым кадром соединения приходит `session/new`
- **THEN** ответ — `-32600` «initialize required», соединение живо

#### Scenario: Ядро без MCP
- **WHEN** хост собрал ядро без `AgentCoreServices.mcp`
- **THEN** `mcpCapabilities` в ответе — `{"http": false, "sse": false}`

### Requirement: session/new
`session/new` SHALL выполнять алгоритм §13.4:
1. `cwd` не абсолютный → `-32602`; при локальном листинге несуществующий каталог → `-32602` (design.md change `add-dart-agent-acp-server`, D5).
2. `mcpServers` декодируются и отображаются в `McpServerConfig` с `origin: session` (design.md change `add-agent-mcp-client`, D11):
   - сервер `sse` пропускается с логом `mcp.server.skipped` и причиной `transport sse is not supported`;
   - сервер `http`, чей `url` не разбирается (`Uri.tryParse` → `null`), пропускается с логом `mcp.server.skipped` и причиной `invalid url`;
   - сервер неизвестного `type` (вариант `McpServer.unknown`) пропускается с логом `mcp.server.skipped` и причиной `unknown transport`;
   - `mcp.server.skipped` адаптера SHALL нести `session_id`, а строки клиента `type` и `name` в нём SHALL обрезаться до 64 символов по рунам;
   - остальные правила (capability, транспорт профиля, дубликаты, коллизии имён) применяет ядро;
   - сбой или пропуск сервера НЕ SHALL быть ошибкой запроса.
3. Сессия создаётся через `AgentRuntime.createSession` с env и `AcpPermissionGate` соединения, хуком `markInProgress` и серверами шага 2. Создание ждёт подключения серверов (параллельно, каждый — не дольше своего `connectTimeout`).
4. Ответ `NewSessionResponse(sessionId, modes, configOptions)`.
5. После ответа — `available_commands_update` с `availableCommands: []`.

До ответа на `session/new` уведомления этой сессии НЕ SHALL отправляться (ACP-8). Инструменты подключённых серверов SHALL быть доступны модели с первого хода этой сессии (R-24). Это заменяет поведение этапа 4, в котором каждый сервер пропускался (R-02).

#### Scenario: Режимы и опции новой сессии
- **WHEN** клиент создаёт сессию с абсолютным `cwd`
- **THEN** ответ содержит `modes` с пятью режимами и `configOptions` `mode` и `model`, а следующий кадр — `available_commands_update` с пустым списком

#### Scenario: Относительный cwd
- **WHEN** `session/new` приходит с `cwd: "work/demo"`
- **THEN** ответ — `-32602`, сессия не создана

#### Scenario: Инструмент сервера доступен модели
- **WHEN** `session/new` содержит stdio-сервер `fake` эпохи modern и stdio-сервер `old` эпохи legacy, оба с инструментом `echo`, затем клиент присылает `session/prompt`
- **THEN** первый запрос к модели содержит схемы `mcp__fake__echo` и `mcp__old__echo` (фикстура `acp/session-new-with-mcp`, R-24)

#### Scenario: Сервер без общей версии протокола
- **WHEN** `session/new` содержит сервер, который на `server/discover` отвечает `-32022` без `2026-07-28` в `data.supported`
- **THEN** ответ `session/new` успешен, сервер пропущен с `mcp.server.failed` и списком его версий, остальные серверы подключены

#### Scenario: Сервер неподдерживаемого типа
- **WHEN** `session/new` содержит HTTP-сервер `web` и сервер `legacy` типа `sse`
- **THEN** ответ содержит `sessionId`, `legacy` пропущен с `mcp.server.skipped`, инструменты `web` доступны модели (фикстура `acp/mcp-http-tool-call`, E-03)

#### Scenario: Неразбираемый url HTTP-сервера
- **WHEN** `session/new` содержит сервер `type: "http"` с `url`, который `Uri.tryParse` не разбирает, и stdio-сервер `fake`
- **THEN** ответ успешен, первый сервер пропущен с `mcp.server.skipped` и причиной `invalid url`, `fake` подключён

#### Scenario: Сервер не подключился
- **WHEN** процесс stdio-сервера из `mcpServers` не запускается
- **THEN** ответ `session/new` успешен, лог `mcp.server.failed`, инструментов сервера в сессии нет

### Requirement: session/load и реплей
`session/load` SHALL выполнять алгоритм §13.5 в объёме MVP: неизвестный `sessionId` → `-32002`; `cwd` запроса выигрывает у `cwd` заголовка с записью `custom` `codelab.cwd_changed`; сессия открывается `AgentRuntime.loadSession` с env, gate и хуками соединения и с `mcpServers` запроса, отображёнными так же, как в `session/new`. Если сессия уже открыта в этом процессе, `mcpServers` запроса SHALL заменять серверы сессии с `origin: session` через `AgentSession.setMcpServers` (design.md change `add-agent-mcp-client`, D11):
- совпавшие по `name` и параметрам остаются подключёнными;
- исчезнувшие закрываются, новые подключаются;
- серверы конфигурации не трогаются;
- без хода изменения применяются до ответа `session/load`, во время хода — после его окончания;
- проверка «сессия занята» и `reattach` SHALL быть атомарны относительно `setMcpServers`: ожидание замены не разделяет их;
- исключение `setMcpServers` НЕ SHALL ронять `session/load`: лог `mcp.servers.replace_failed` (warning, `session_id`, `error` — тип исключения), ответ отправляется как обычно.

Описания серверов НЕ SHALL читаться из журнала. Реплей SHALL идти по активной ветке:
- слова пользователя → `user_message_chunk` на каждый блок; прочие user-записи пропускаются;
- ответ модели → `agent_thought_chunk` и `agent_message_chunk` по блокам; вызов → один `tool_call` с итоговым статусом, `title`, `kind`, `locations`, `rawInput`, `content` результата, `diff` и `_meta.codelab.outcome` для `cancelled`/`rejected`/`interrupted`;
- `compaction` не отправляется.

После истории — последний `plan`, `current_mode_update`, `config_option_update`, `available_commands_update`, `session_info_update`; затем ответ `LoadSessionResponse(modes, configOptions)`.

#### Scenario: Реплей двух ходов
- **WHEN** сессия с двумя ходами, вызовом `read` и заголовком загружается в новом соединении
- **THEN** кадры совпадают с фикстурой `acp/session-load-replay`, а ответ `session/load` — последний

#### Scenario: Прерванный ход
- **WHEN** журнал кончается вызовом без результата
- **THEN** реплей содержит `tool_call` со `status: failed` и `_meta.codelab.outcome: "interrupted"`, повторного вызова инструмента нет

#### Scenario: Серверы загруженной сессии
- **WHEN** сохранённая сессия загружается с `mcpServers`, содержащим stdio-сервер `fake`
- **THEN** первый запрос к модели после загрузки содержит схему `mcp__fake__echo`

#### Scenario: Повторная загрузка открытой сессии с другим набором
- **WHEN** открытая сессия без хода с сервером `a` загружается заново с `mcpServers: [b]`
- **THEN** до ответа `session/load` транспорт `a` закрыт, `b` подключён, а следующий запрос к модели содержит инструменты `b` и не содержит инструментов `a`

## ADDED Requirements

### Requirement: Неизвестный транспорт MCP-сервера
Модель `McpServer` пакета `codelab_acp_protocol` SHALL разбирать элемент `mcpServers` с неизвестным строковым `type` в вариант `McpServer.unknown({type, name?, raw})` (design.md change `add-agent-mcp-client`, D11; `AGENTS.md` §7, совместимость вперёд):
- проверка допустимых ключей к такому элементу не применяется;
- `raw` хранит объект целиком, `toJson()` возвращает его без изменений;
- известные типы (`stdio` без `type` или с `"stdio"`, `http`, `sse`) SHALL проверяться строго, как раньше: неизвестный ключ, отсутствующее обязательное поле и нестроковый `type` дают `-32602`.

ACP-сервер агента SHALL пропускать такой сервер с `mcp.server.skipped {server, transport: <type>, reason: "unknown transport"}`. `session/new` и `session/load` SHALL при этом создавать сессию с остальными серверами.

#### Scenario: Сервер будущего транспорта
- **WHEN** `session/new` содержит `{"type": "websocket", "name": "future", "url": "wss://x"}` и stdio-сервер `fake`
- **THEN** ответ успешен, `future` пропущен с `mcp.server.skipped` и `reason: unknown transport`, инструменты `fake` доступны модели

#### Scenario: Известный тип по-прежнему строг
- **WHEN** элемент `mcpServers` имеет `type: "http"` без `url`
- **THEN** `session/new` получает `-32602`, сессия не создана

#### Scenario: Модель сохраняет неизвестный сервер
- **WHEN** `McpServer.fromJson` получает `{"type": "websocket", "name": "future", "extra": 1}`
- **THEN** результат — `McpServerUnknown` с `type: "websocket"`, `name: "future"`, а `toJson()` равен исходному объекту
