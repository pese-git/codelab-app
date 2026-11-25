## ADDED Requirements

### Requirement: Локальное исполнение в serve
`codelab-agent serve` SHALL принимать флаг `--local-exec` с любым транспортом (`--stdio` или `--ws`) и повторяемый флаг `--workspace-root <dir>` (design.md change `add-agent-remote-exec`, D1, D2). С `--local-exec` хост SHALL передавать серверу `AcpServerConfig.localEnv` — фабрику `LocalExecutionEnv` по `cwd` сессии — и `AcpServerConfig.workspaceRoots`, а `localListing` НЕ SHALL передаваться. Тогда файлы, команды, листинг и поиск исполняет процесс агента, и запросы `fs/*` и `terminal/*` клиенту НЕ SHALL отправляться, даже если клиент их объявил (agent-acp-server «Локальное окружение сессии от хоста»). Gate сессии SHALL оставаться `AcpPermissionGate`: вопрос о разрешении уходит клиенту `session/request_permission`. Без `--local-exec` поведение прежнее.

Ошибки использования (код `64`, текст в stderr, до загрузки ядра и до старта транспорта):
- `--local-exec` без `--workspace-root`: `--local-exec needs at least one --workspace-root`;
- `--workspace-root` без `--local-exec`: `--workspace-root requires --local-exec`;
- корень, которого нет или который не каталог: `--workspace-root <путь>: not a directory`.

Относительный корень SHALL разрешаться от текущего каталога процесса. Каждый корень SHALL раскрываться (символические ссылки) и приводиться к виду путей ядра до передачи серверу.

`--local-exec --ws` SHALL слушать только loopback-адрес (design.md, D3):
- разбор флагов SHALL принимать `--host` только как `localhost` или литерал IP, у которого `InternetAddress.isLoopback` истинно (`127.0.0.0/8`, `::1`); иначе код `64` с текстом `--local-exec over --ws listens only on a loopback address; reach it through an SSH tunnel or a TLS reverse proxy` до загрузки ядра и привязки сокета. IPv4-адрес в IPv6-записи (`::ffff:127.0.0.1`) НЕ SHALL считаться loopback (fail closed);
- после привязки адрес сокета (`HttpServer.address`) SHALL проверяться ещё раз: если он не loopback (например, `localhost` разрешился иначе через `hosts`), сокет закрывается, процесс завершается с кодом `64` и тем же текстом, ни одно подключение не принимается.

С `--local-exec --ws` токен из `--token-env` SHALL быть не короче 32 байт в UTF-8; более короткий — код `64` с текстом `--local-exec over --ws needs a token of at least 32 bytes in <VAR>` (имя переменной, не значение) до привязки сокета. Токен — единственный барьер для локальных пользователей машины и для порта SSH-туннеля (design.md, D3).

С `--local-exec` по WebSocket сужения по транспорту НЕ SHALL применяться: capability `fileListing` и `mcp` остаются включёнными, ядро получает `ProjectFilesLoader` (`projectFiles`, `skillFiles`), `hostFiles` и, без `--llm-script`, порт `projectConfig`; событие `project_files.skipped` не пишется. Встроенная команда `/config` по WebSocket SHALL оставаться выключенной (`configCommand: false`), в том числе с `--local-exec` (design.md, D5).

При старте с `--local-exec` хост SHALL писать одно событие `serve.local_exec` уровня warning с полями `transport` и `workspace_roots` (раскрытые корни) (design.md, D10).

#### Scenario: Файлы и команды на машине агента по WebSocket
- **WHEN** `codelab-agent serve --ws --port 0 --local-exec --workspace-root <tmp> --llm-script <сценарий>` принимает клиента, который объявил `fs.readTextFile`, `fs.writeTextFile` и `terminal`, клиент создаёт сессию с `cwd: <tmp>`, а сценарий в режиме `bypass` зовёт `write` файла `a.txt`, `read` этого файла и `exec` `cat a.txt`
- **THEN** клиент не получает ни одного запроса `fs/*` и `terminal/*`, файл `<tmp>/a.txt` создан процессом агента, а вывод команды приходит текстом в `tool_call_update` вызова `exec`

#### Scenario: Вопрос о разрешении остаётся у клиента
- **WHEN** тот же сервер в режиме `standard` получает от сценария вызов `exec`
- **THEN** клиент получает `session/request_permission` с `toolCallId` вызова, процесс команды запускается только после `allow_once`, а после `reject_once` не запускается

#### Scenario: Листинг и поиск по WebSocket
- **WHEN** сервер `--ws --local-exec` отвечает на `initialize` и собирает сессию в корне
- **THEN** запись `host.plan` не содержит `fileListing` и `mcp` среди выключенных, инструменты сессии содержат `ls` и `search`, `initialize` объявляет `mcpCapabilities.http: true`, а события `project_files.skipped` нет

#### Scenario: Без корня
- **WHEN** бинарь запущен с `serve --ws --local-exec` без `--workspace-root`
- **THEN** процесс завершается с кодом `64` и текстом `--local-exec needs at least one --workspace-root`, сокет не открыт

#### Scenario: Корень без флага режима
- **WHEN** бинарь запущен с `serve --stdio --workspace-root <tmp>`
- **THEN** процесс завершается с кодом `64` и текстом `--workspace-root requires --local-exec`

#### Scenario: Не-loopback адрес
- **WHEN** бинарь запущен с `serve --ws --host 0.0.0.0 --local-exec --workspace-root <tmp>`
- **THEN** процесс завершается с кодом `64` и текстом `--local-exec over --ws listens only on a loopback address; reach it through an SSH tunnel or a TLS reverse proxy`, сокет не открыт

#### Scenario: IPv4 в IPv6-записи
- **WHEN** бинарь запущен с `serve --ws --host ::ffff:127.0.0.1 --local-exec --workspace-root <tmp>`
- **THEN** процесс завершается с кодом `64`, сокет не открыт

#### Scenario: Короткий токен
- **WHEN** бинарь запущен с `serve --ws --local-exec --workspace-root <tmp>`, а `CODELAB_AGENT_TOKEN` длиной 16 байт
- **THEN** процесс завершается с кодом `64` и текстом `--local-exec over --ws needs a token of at least 32 bytes in CODELAB_AGENT_TOKEN`, значение токена не попадает ни в stderr, ни в лог

#### Scenario: Режим по stdio
- **WHEN** `codelab-agent serve --stdio --local-exec --workspace-root <tmp> --llm-script <сценарий>` получает сессию с `cwd: <tmp>` от клиента без `fs` и `terminal`, а сценарий в режиме `bypass` зовёт `read` и `exec`
- **THEN** оба вызова завершаются успешно, в stdout нет запросов `fs/*` и `terminal/*`

#### Scenario: Предупреждение при старте
- **WHEN** бинарь стартует с `serve --ws --local-exec --workspace-root <tmp>`
- **THEN** лог содержит одно событие `serve.local_exec` уровня warning с `transport: ws` и `workspace_roots`, где есть раскрытый `<tmp>`, и не содержит значения токена

#### Scenario: Разрыв во время команды
- **WHEN** клиент `--ws --local-exec` закрывает соединение, пока идёт `exec` команды `sleep 60`
- **THEN** ход отменяется без ожидания переподключения, процесс команды и его потомки завершены не позже 5 с после разрыва

## MODIFIED Requirements

### Requirement: Команда serve
Бинарь `codelab-agent` (`apps/codelab_agent`) SHALL обслуживать ACP-клиентов командой `serve` ровно с одним транспортом: `--stdio` или `--ws`. Ядро SHALL собираться только через `buildAgentCore` в профиле `agent-serve` (HOST-6), сервер — `AcpAgentServer` пакета `codelab_agent_acp`.

- `serve --stdio`: одно соединение через `StdioServerAcpTransport` на stdin/stdout процесса; сервер получает `localListing` на `LocalExecutionEnv`, поэтому `ls` и `search` включены; `detachGrace` — ноль (отсоединение stdio — конец процесса).
- `serve --ws [--host <host>] [--port <port>] [--token-env <VAR>]`: по умолчанию `127.0.0.1:8765` и `CODELAB_AGENT_TOKEN`; каждое принятое подключение — отдельное соединение того же сервера через `WebSocketServerAcpTransport`; без `--local-exec` capability `fileListing` выключена с причиной, `localListing` не передаётся; `detachGrace` — ноль, как у stdio: закрытие WebSocket посреди хода отменяет ход (для MVP ход без клиента не может исполнять `fs/*` и `terminal/*`; возобновление хода после переподключения — после MVP).
- `--local-exec --workspace-root <dir>…` с любым из транспортов: сервер получает `localEnv` и `workspaceRoots` вместо `localListing`, файлы и команды исполняет процесс агента (requirement «Локальное исполнение в serve»); `detachGrace` остаётся нулём.

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
`serve --ws` SHALL требовать Bearer-токен при HTTP upgrade (R-12, документ ядра §13.3). Токен — значение переменной окружения из `--token-env`; пустая или отсутствующая переменная — ошибка использования, код `64`. Запрос без upgrade SHALL получать `426`; upgrade без заголовка `Authorization: Bearer <token>` или с неверным токеном — `401` с `WWW-Authenticate: Bearer` до обмена ACP. Сравнение токена SHALL идти за постоянное время, токен НЕ SHALL попадать в лог. Путь запроса НЕ SHALL проверяться: один процесс — один endpoint, маршрут клиента и сервера совпадает (DF-07). Не-loopback `--host` SHALL давать предупреждение в лог; с `--local-exec` не-loopback `--host` SHALL быть ошибкой использования (requirement «Локальное исполнение в serve»; design.md change `add-agent-remote-exec`, D3).

#### Scenario: Подключение без токена
- **WHEN** клиент открывает WebSocket без заголовка `Authorization`
- **THEN** сервер отвечает `401` до upgrade, ни одного кадра ACP не отправляется

#### Scenario: Неверный токен
- **WHEN** клиент открывает WebSocket с `Authorization: Bearer wrong`
- **THEN** сервер отвечает `401`, а запись лога `serve.ws.unauthorized` не содержит ни присланного, ни верного токена

#### Scenario: Верный токен
- **WHEN** клиент `WebSocketAcpTransport` подключается с верным токеном к пути `/acp`
- **THEN** upgrade проходит, и `initialize` получает ответ

### Requirement: MCP-серверы в бинаре
`codelab-agent serve` SHALL собирать ядро с `AgentCoreServices.mcp`: `McpClientConnector` с stdio-транспортом `codelab_agent_io` и streamable HTTP на HTTP-клиенте хоста (design.md change `add-agent-mcp-client`, D3). HTTP-клиент один на процесс — тот же, что у LLM-провайдеров, — и закрывается при завершении хоста. Профиль `agent-serve` даёт capability `mcp` с транспортами `stdio` и `http`, поэтому `initialize` по `--stdio` объявляет `mcpCapabilities.http: true`.

Серверы SHALL приходить из двух источников: из `session/new.mcpServers` и из `mcp.servers` конфигурации (`CoreConfig.mcpServers`, `origin: config`) с таймаутом вызова `call_timeout` каждого сервера.

В `codelab-agent serve --ws` без `--local-exec` capability `mcp` SHALL быть выключена с причиной профиля: серверы клиента и серверы конфига пропускаются `mcp.server.skipped`, `initialize` объявляет `mcpCapabilities.http: false` — сознательное отступление от `03-Session Setup.md` (stdio MUST) ради безопасности: держатель токена WebSocket не должен запускать команды на машине агента (design.md change `add-agent-mcp-client`, D3). С `--local-exec` держатель токена уже исполняет команды на машине агента, поэтому capability `mcp` по WebSocket НЕ SHALL выключаться: серверы клиента и конфигурации подключаются так же, как по `--stdio`, а `initialize` объявляет `mcpCapabilities.http: true` (design.md change `add-agent-remote-exec`, D5, Q3). Завершение процесса агента (EOF stdin для `--stdio`, сигнал) SHALL закрывать сессии и тем самым завершать процессы stdio-серверов не позже 10 с.

#### Scenario: Реальный stdio-сервер
- **WHEN** `codelab-agent serve --stdio --llm-script <сценарий>` получает `session/new` с fake stdio-сервером (`fake_mcp_stdio_server.dart`), модель вызывает `mcp__fake__echo {"text":"hi"}`, клиент одобряет вызов
- **THEN** `tool_call_update` — `completed` с `hi`, а после закрытия stdin агента процесс сервера с записанным pid не жив не позже 10 с (E-02, R-24; `apps/codelab_agent/test/mcp_stdio_process_test.dart`)

#### Scenario: Сервер из конфигурации
- **WHEN** `codelab-agent serve --stdio --llm-script <сценарий> --config <tmp>/c.yaml`, где `c.yaml` объявляет fake stdio-сервер `fake`, получает `session/new` без `mcpServers`, а модель вызывает `mcp__fake__echo`
- **THEN** после одобрения `tool_call_update` — `completed` с `hi`, а после закрытия stdin процесс сервера не жив не позже 10 с (E-02, часть конфигурации; `apps/codelab_agent/test/config_mcp_servers_test.dart`)

#### Scenario: HTTP-сервер из конфигурации
- **WHEN** хост собран из конфига с сервером `type: http`, а HTTP-клиент хоста — `MockClient` над `FakeMcpServer`
- **THEN** инструмент сервера доступен модели с первого хода и вызывается (E-03, часть конфигурации; `apps/codelab_agent/test/agent_host_config_test.dart`)

#### Scenario: WS-профиль не запускает MCP-серверы
- **WHEN** `codelab-agent serve --ws` без `--local-exec` с stdio-сервером в `mcp.servers` конфига получает `session/new` со stdio-сервером в `mcpServers`
- **THEN** ответ успешен, ни один процесс сервера не запущен, лог `mcp.server.skipped` с причиной профиля для обоих, `initialize` этого соединения объявляет `mcpCapabilities.http: false`

#### Scenario: MCP по WebSocket с локальным исполнением
- **WHEN** `codelab-agent serve --ws --local-exec --workspace-root <tmp> --llm-script <сценарий> --config <tmp>/c.yaml`, где `c.yaml` объявляет fake stdio-сервер `fake`, получает `session/new` с `cwd: <tmp>` и без `mcpServers`, а модель вызывает `mcp__fake__echo`
- **THEN** `initialize` объявляет `mcpCapabilities.http: true`, после одобрения `tool_call_update` — `completed` с `hi`, а после `SIGTERM` процесс сервера не жив не позже 10 с

#### Scenario: Возможности MCP в initialize
- **WHEN** бинарь `serve --stdio` отвечает на `initialize`
- **THEN** `agentCapabilities.mcpCapabilities` — `{"http": true, "sse": false}`

### Requirement: Файлы проекта в бинаре
`codelab-agent serve --stdio` SHALL передавать ядру `ProjectFilesLoader` из `codelab_agent_io` в `AgentCoreServices.projectFiles` (design.md change `add-agent-project-files`, D16). Пользовательская область — `$CODELAB_HOME` процесса. С `--llm-script` пользовательская область НЕ SHALL читаться, а проект SHALL считаться недоверенным (глобальный слой не читается); контекст проекта (`AGENTS.md` дерева `cwd`) SHALL читаться.

`codelab-agent serve --ws` без `--local-exec` НЕ SHALL передавать загрузчик (решение пользователя 2026-10-30; D2, D16): клиент WebSocket выбирает `cwd` и может быть на другой машине, а чтение шло бы с файловой системы машины агента и отдавало бы удалённому клиенту инструкции любого каталога этой машины. Поэтому по WebSocket не читаются ни файлы проекта (`AGENTS.md`/`CLAUDE.md`, `.codelab/prompts`, `.codelab/agents`), ни файлы `$CODELAB_HOME` (`AGENTS.md`, `prompts/`, `agents/`). Это сужение по транспорту, как у MCP (`mcp.server.skipped`, design.md change `add-agent-mcp-client`, D3): хост SHALL один раз при запуске писать событие `project_files.skipped` (info) с полями `transport: ws` и `reason: "project files are not read over WebSocket"`.

`codelab-agent serve --ws --local-exec` SHALL передавать загрузчик по тем же правилам, что `--stdio` (в том числе правила `--llm-script`), и НЕ SHALL писать `project_files.skipped`: `cwd` сессии ограничен корнями `--workspace-root`, которые задал оператор машины агента, а файлы и команды сессии и так исполняются на этой машине (design.md change `add-agent-remote-exec`, D2, D5).

#### Scenario: Шаблон пользователя
- **WHEN** `AgentHost.build` для `--stdio` получает временный `CODELAB_HOME` с `prompts/review.md` и создаёт сессию
- **THEN** `session.commands` содержит `review`

#### Scenario: Сценарий не читает CODELAB_HOME
- **WHEN** `serve --stdio --llm-script` запускается во временном `cwd` с `AGENTS.md`, а `CODELAB_HOME` содержит `prompts/review.md` и `AGENTS.md`
- **THEN** лог `project_context.loaded` называет только `AGENTS.md` из `cwd`, а `available_commands_update` после `session/new` содержит только встроенные команды сессии, без шаблона `review`

#### Scenario: WebSocket не читает файлы проекта
- **WHEN** `AgentHost.build` для `--ws` без `--local-exec` получает временный `CODELAB_HOME` с `AGENTS.md`, а сессия создаётся в `cwd` с `AGENTS.md`
- **THEN** `AgentCoreServices.projectFiles` равен `null`, системный промпт не содержит секции `project_context`, лог содержит одно событие `project_files.skipped` с `transport: ws` и не содержит `project_context.loaded`

#### Scenario: WebSocket с локальным исполнением читает файлы проекта
- **WHEN** `AgentHost.build` для `--ws --local-exec --workspace-root <tmp>` создаёт сессию в `<tmp>` с `AGENTS.md`
- **THEN** `AgentCoreServices.projectFiles` задан, системный промпт содержит секцию `project_context` с текстом файла, события `project_files.skipped` нет

### Requirement: Проектный конфиг сессий в serve
`codelab-agent serve --stdio` (кроме прогона `--llm-script`) SHALL передавать ядру порт `ProjectConfigLoader` — источник `serveConfigSource` с теми же окружением, флагами, `--config` и закреплённым доверием. Сессия вне корня запуска тогда получает конфигурацию и функцию модели своей папки (флаги запуска входят в её слои) (spec agent-runtime «Конфигурация сессии вне корня запуска»; design.md change `require-project-folder`, D21). Корень запуска по-прежнему задаёт ключи процесса (`HostSettings`). `serve --ws` без `--local-exec` порт НЕ SHALL передавать: по WebSocket `cwd` называет клиент, а проектные файлы бинарь по WebSocket не читает (requirement «Файлы проекта в бинаре»; design.md, Q18 (a)); сессия вне корня получает `withoutProject` и лог `config.session.outside_root`, как раньше. `serve --ws --local-exec` (кроме прогона `--llm-script`) SHALL передавать порт так же, как `--stdio`: `cwd` сессии лежит внутри корней `--workspace-root` (design.md change `add-agent-remote-exec`, D5).

#### Scenario: serve обслуживает сессию другой папки
- **WHEN** `codelab-agent serve --stdio` запущен в `/A`, доверенный проект `/B` задаёт `budget.max_steps: 3`, и клиент создаёт сессию с `cwd: /B`
- **THEN** бюджет хода этой сессии — 3 шага, а флаги запуска (`--model`, `--provider`) по-прежнему действуют как слой флагов

#### Scenario: serve --ws не читает конфиг папки клиента
- **WHEN** `codelab-agent serve --ws` без `--local-exec` запущен в `/A`, доверенный проект `/B` на машине агента задаёт `budget.max_steps: 3`, и клиент создаёт сессию с `cwd: /B`
- **THEN** проектные слои `/B` не читаются: сессия получает `withoutProject`, лог `config.session.outside_root`

#### Scenario: serve --ws --local-exec читает конфиг папки сессии
- **WHEN** `codelab-agent serve --ws --local-exec --workspace-root /B` запущен в `/A`, доверенный проект `/B` задаёт `budget.max_steps: 3`, и клиент создаёт сессию с `cwd: /B`
- **THEN** бюджет хода этой сессии — 3 шага
