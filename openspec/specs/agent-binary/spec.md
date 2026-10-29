# agent-binary Specification

## Purpose
Бинарь `codelab-agent` (`apps/codelab_agent`): Dart-агент как отдельный процесс для внешних ACP-клиентов — Zed, Claude Code, codelab-app по stdio и удалённых клиентов по WebSocket. Команда `serve --stdio | --ws` собирает ядро в профиле `agent-serve` через `buildAgentCore` и обслуживает соединения `AcpAgentServer`; минимальный конфиг — флаги и переменные окружения (провайдер, модели, режим разрешений, логи; полный конфиг — этап 8), ключ провайдера и токен WebSocket в логи не попадают. Тестам клиентов бинарь даёт детерминированную модель `--llm-script` вместо провайдера (`agent-core-architecture` §15.6; `dart-agent-and-clients` §9.9). Известные ограничения MVP: MCP-серверы не подключаются до этапа 8, `--local-exec` — этап 8.
## Requirements
### Requirement: Команда serve
Бинарь `codelab-agent` (`apps/codelab_agent`) SHALL обслуживать ACP-клиентов командой `serve` ровно с одним транспортом: `--stdio` или `--ws`. Ядро SHALL собираться только через `buildAgentCore` в профиле `agent-serve` (HOST-6), сервер — `AcpAgentServer` пакета `codelab_agent_acp`.

- `serve --stdio`: одно соединение через `StdioServerAcpTransport` на stdin/stdout процесса; сервер получает `localListing` на `LocalExecutionEnv`, поэтому `ls` и `search` включены; `detachGrace` — ноль (отсоединение stdio — конец процесса).
- `serve --ws [--host <host>] [--port <port>] [--token-env <VAR>]`: по умолчанию `127.0.0.1:8765` и `CODELAB_AGENT_TOKEN`; каждое принятое подключение — отдельное соединение того же сервера через `WebSocketServerAcpTransport`; capability `fileListing` выключена с причиной, `localListing` не передаётся; `detachGrace` — ноль, как у stdio: закрытие WebSocket посреди хода отменяет ход (для MVP ход без клиента не может исполнять `fs/*` и `terminal/*`; возобновление хода после переподключения — после MVP).

stdout в режиме `--stdio` SHALL нести только кадры JSON-RPC: одно сообщение — одна строка UTF-8 (R-13).

#### Scenario: Ответ на initialize по stdio
- **WHEN** в stdin процесса `codelab-agent serve --stdio --llm-script test/llm_scripts/hello.json` записана строка `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}`
- **THEN** в stdout приходит одна строка с ответом `id: 1` и `protocolVersion: 1`, а в stdout нет ничего, кроме строк JSON-RPC

#### Scenario: Ход до конца по stdio
- **WHEN** клиент процесса выполняет `initialize`, `session/new` и `session/prompt` со сценарием `hello.json`
- **THEN** приходят `agent_message_chunk` с текстом `hello` и ответ `stopReason: end_turn`

#### Scenario: Два транспорта сразу
- **WHEN** бинарь запущен с `serve --stdio --ws` или с `serve` без транспорта
- **THEN** процесс завершается с кодом `64` и текстом ошибки использования в stderr, сервер не стартует

#### Scenario: Закрытие WebSocket посреди хода отменяет ход
- **WHEN** клиент `serve --ws` закрывает соединение во время `session/prompt`, а затем новое соединение загружает сессию через `session/load` и отправляет `session/prompt`
- **THEN** прежний ход отменён без ожидания переподключения, ожидающие разрешения получили `cancelled`, и новый `session/prompt` выполняется, а не отклоняется как занятой сессией

### Requirement: Аутентификация WebSocket
`serve --ws` SHALL требовать Bearer-токен при HTTP upgrade (R-12, документ ядра §13.3). Токен — значение переменной окружения из `--token-env`; пустая или отсутствующая переменная — ошибка использования, код `64`. Запрос без upgrade SHALL получать `426`; upgrade без заголовка `Authorization: Bearer <token>` или с неверным токеном — `401` с `WWW-Authenticate: Bearer` до обмена ACP. Сравнение токена SHALL идти за постоянное время, токен НЕ SHALL попадать в лог. Путь запроса НЕ SHALL проверяться: один процесс — один endpoint, маршрут клиента и сервера совпадает (DF-07). Не-loopback `--host` SHALL давать предупреждение в лог.

#### Scenario: Подключение без токена
- **WHEN** клиент открывает WebSocket без заголовка `Authorization`
- **THEN** сервер отвечает `401` до upgrade, ни одного кадра ACP не отправляется

#### Scenario: Неверный токен
- **WHEN** клиент открывает WebSocket с `Authorization: Bearer wrong`
- **THEN** сервер отвечает `401`, а запись лога `serve.ws.unauthorized` не содержит ни присланного, ни верного токена

#### Scenario: Верный токен
- **WHEN** клиент `WebSocketAcpTransport` подключается с верным токеном к пути `/acp`
- **THEN** upgrade проходит, и `initialize` получает ответ

### Requirement: Минимальный конфиг из флагов
До этапа 8 бинарь НЕ SHALL читать файлы конфига (документ ядра §15.6). Конфиг SHALL собираться из флагов и переменных окружения, флаг сильнее переменной:
- `--provider openai-compatible|anthropic`, `--base-url <url>` — провайдер с id `cli`; `--model <id>` повторяемый: первое значение — модель по умолчанию, все — модели каталога `cli/<id>`; `CODELAB_MODEL` — значение `--model`, если флага нет; форма `provider/model` допустима только с провайдером этого запуска (`cli/<id>` или `scripted/<id>`): других провайдеров до конфига этапа 8 нет, поэтому `--model openai/gpt-5` без `--provider` — ошибка использования;
- ключ провайдера — только переменная `CODELAB_API_KEY`;
- `--permission-mode` / `CODELAB_PERMISSION_MODE` — `plan`, `ask`, `standard`, `accept-edits`, `bypass`, `autopilot`;
- `--log-level` / `CODELAB_LOG_LEVEL`, `--log-file` / `CODELAB_LOG_FILE`;
- остальные ключи — значения по умолчанию §15.4.

Ошибки использования — неизвестный флаг, неизвестный режим, `--provider` вместе с `--llm-script`, ни модели, ни сценария, `--sessions-dir` без `--llm-script` — SHALL завершать процесс кодом `64` с текстом в stderr. Неизвестная переменная `CODELAB_*` SHALL давать предупреждение в лог. Значение `CODELAB_API_KEY` НЕ SHALL попадать в лог, текст ошибок и строковое представление опций.

С провайдером из флагов сессии SHALL храниться в `JsonlSessionStore` под `$CODELAB_HOME/sessions` (`CODELAB_HOME` по умолчанию `~/.codelab`), и `initialize` объявляет `loadSession: true`.

#### Scenario: Ключ не попадает в лог
- **WHEN** бинарь запущен с `CODELAB_API_KEY=sk-test-secret`, `--log-level debug` и `--log-file <tmp>`
- **THEN** ни stderr, ни файл лога не содержат строки `sk-test-secret`

#### Scenario: Провайдер вместе со сценарием
- **WHEN** бинарь запущен с `--provider anthropic --llm-script hello.json`
- **THEN** процесс завершается с кодом `64` и сообщением о взаимоисключающих флагах

#### Scenario: Каталог журналов без сценария
- **WHEN** бинарь запущен с `--provider anthropic --model claude --sessions-dir /tmp/sessions`
- **THEN** процесс завершается с кодом `64` и сообщением, что `--sessions-dir` требует `--llm-script`

#### Scenario: Повторяемый --model
- **WHEN** бинарь запущен с `--provider openai-compatible --base-url http://localhost:4000 --model gpt-5 --model gpt-4`
- **THEN** опция `model` новой сессии содержит `cli/gpt-5` и `cli/gpt-4`, а текущее значение — `cli/gpt-5`

### Requirement: Сценарий --llm-script
Флаг `--llm-script <file.json>` SHALL заменять провайдера `ScriptedStreamFunction` из файла `{"llm": {"model": {...}, "steps": [...]}}` — формата блока `llm` фикстуры (документ ядра §14.7). Флаг SHALL быть скрыт в справке. Провайдер — `scripted`; модели каталога — `scripted/<id>` для каждого `--model`, без `--model` — модель из `llm.model`. Шаги SHALL быть общими для всех сессий процесса и расходоваться по порядку запросов, а новый процесс SHALL начинать их с первого шага; `${cwd}` SHALL подставляться рабочей папкой сессии запроса — в том числе сессии, загруженной `session/load`, — `${sessionId}` — её id. Невалидный файл — ошибка использования, код `64`, с путём поля.

Без флага `--sessions-dir` сессии SHALL храниться в памяти: capability `sessionPersistence` сужена, `initialize` объявляет `loadSession: false` без `sessionCapabilities.list`.

Скрытый в справке флаг `--sessions-dir <path>` SHALL включать журнал сессий на диске: `JsonlSessionStore` с корнем `<path>`, capability `sessionPersistence` включена, `initialize` объявляет `loadSession: true` и `sessionCapabilities.list`, а сессии, созданные одним процессом, SHALL отдаваться `session/list` и загружаться `session/load` следующим процессом с тем же `<path>`.

С `--llm-script` бинарь НЕ SHALL создавать и читать `$CODELAB_HOME` ни с `--sessions-dir`, ни без него.

#### Scenario: Рабочая папка сессии в ответе
- **WHEN** сценарий отвечает `cwd was: ${cwd}`, а клиент создаёт сессию с `cwd: "/work/demo"`
- **THEN** `agent_message_chunk` несёт `cwd was: /work/demo`

#### Scenario: Ничего не пишется в CODELAB_HOME
- **WHEN** бинарь с `--llm-script` и `CODELAB_HOME=<tmp>` проводит ход
- **THEN** каталог `<tmp>` не создан, а `initialize` объявляет `loadSession: false`

#### Scenario: Сессии сценария переживают перезапуск процесса
- **WHEN** процесс с `--llm-script` и `--sessions-dir <dir>` создаёт сессию в `<cwd>` и проводит ход, затем завершается, и новый процесс с теми же флагами получает `session/list` с `cwd: <cwd>`
- **THEN** `initialize` нового процесса объявляет `loadSession: true` и `sessionCapabilities.list`, список содержит id прежней сессии, `session/load` повторяет её историю, `$CODELAB_HOME` не создан

#### Scenario: Рабочая папка загруженной сессии
- **WHEN** новый процесс с `--sessions-dir <dir>` загружает `session/load` сессию прошлого процесса из `<cwd>`, а сценарий отвечает `cwd was: ${cwd}`
- **THEN** `agent_message_chunk` хода в этой сессии несёт `cwd was: <cwd>`

### Requirement: Логи бинаря
Логи SHALL идти в stderr и, если задан `--log-file` или `CODELAB_LOG_FILE`, в файл JSON Lines по §12.3.1 документа ядра: каталоги `0700`, файл `0600`, дописывание; путь в stdout (`-`, `/dev/stdout`, `/dev/fd/1`, `/proc/self/fd/1`) и неоткрываемый путь — ошибка использования, код `64`. Файл лога по умолчанию из конфига (`logging.file`) на этом этапе НЕ SHALL создаваться (design.md, D5). Уровень по умолчанию — `info`.

#### Scenario: Лог в файл
- **WHEN** бинарь запущен с `--log-file <tmp>/agent.log` и проводит ход
- **THEN** файл содержит записи JSON Lines с ключами `ts`, `level`, `event` первыми, права файла — `0600`

#### Scenario: Лог в stdout запрещён
- **WHEN** бинарь запущен с `--log-file /dev/stdout`
- **THEN** процесс завершается с кодом `64` и текстом `--log-file cannot point to stdout: stdout carries the ACP protocol`

### Requirement: Жизненный цикл процесса
Процесс SHALL завершаться безопасно через `AcpAgentServer.shutdown`: EOF stdin в режиме `--stdio` — код `0`; `SIGINT` — `130`; `SIGTERM` — `143` (где ОС его поддерживает); повторный сигнал во время завершения — немедленный выход с тем же кодом. Ошибка запуска вне ошибок использования (например, занятый порт) SHALL давать код `1` и текст в stderr.

#### Scenario: EOF во время хода
- **WHEN** stdin процесса закрывается, пока идёт ход
- **THEN** ход отменяется, журнал дописывается, процесс завершается с кодом `0`

#### Scenario: SIGTERM
- **WHEN** процессу `serve --ws` приходит `SIGTERM`
- **THEN** активные ходы отменяются, сокеты закрываются, код выхода — `143`

### Requirement: MCP-серверы в бинаре
`codelab-agent serve` SHALL собирать ядро с `AgentCoreServices.mcp`: `McpClientConnector` с stdio-транспортом `codelab_agent_io` и streamable HTTP на HTTP-клиенте хоста (design.md change `add-agent-mcp-client`, D3). HTTP-клиент один на процесс — тот же, что у LLM-провайдера, — и закрывается при завершении хоста. Профиль `agent-serve` даёт capability `mcp` с транспортами `stdio` и `http`, поэтому `initialize` по `--stdio` объявляет `mcpCapabilities.http: true`. В `codelab-agent serve --ws` capability `mcp` SHALL быть выключена с причиной профиля: серверы клиента пропускаются `mcp.server.skipped`, `initialize` объявляет `mcpCapabilities.http: false` — сознательное отступление от `03-Session Setup.md` (stdio MUST) ради безопасности: держатель токена WebSocket не должен запускать команды на машине агента (design.md, D3). Завершение процесса агента (EOF stdin для `--stdio`, сигнал) SHALL закрывать сессии и тем самым завершать процессы stdio-серверов не позже 10 с.

#### Scenario: Реальный stdio-сервер
- **WHEN** `codelab-agent serve --stdio --llm-script <сценарий>` получает `session/new` с fake stdio-сервером (`fake_mcp_stdio_server.dart`), модель вызывает `mcp__fake__echo {"text":"hi"}`, клиент одобряет вызов
- **THEN** `tool_call_update` — `completed` с `hi`, а после закрытия stdin агента процесс сервера с записанным pid не жив не позже 10 с (E-02, R-24; `apps/codelab_agent/test/mcp_stdio_process_test.dart`)

#### Scenario: WS-профиль не запускает MCP-серверы
- **WHEN** `codelab-agent serve --ws` получает `session/new` со stdio-сервером в `mcpServers`
- **THEN** ответ успешен, процесс сервера не запущен, лог `mcp.server.skipped` с причиной профиля, `initialize` этого соединения объявляет `mcpCapabilities.http: false`

#### Scenario: Возможности MCP в initialize
- **WHEN** бинарь `serve --stdio` отвечает на `initialize`
- **THEN** `agentCapabilities.mcpCapabilities` — `{"http": true, "sse": false}`

