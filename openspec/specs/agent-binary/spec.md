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
Логи SHALL идти в stderr и в файл JSON Lines по §12.3.1 документа ядра, если файл задан (флаг сильнее переменной, переменная сильнее конфига): `--log-file`, `CODELAB_LOG_FILE` или явно заданный ключ `logging.file` конфига. Файл: каталоги `0700`, файл `0600`, дописывание. Путь в stdout (`-`, `/dev/stdout`, `/dev/fd/1`, `/proc/self/fd/1`) и неоткрываемый путь — ошибка использования, код `64`. Файл лога по умолчанию (`$CODELAB_HOME/logs/agent.log`) без явного ключа НЕ SHALL создаваться (design.md change `add-agent-configuration`, OQ5 (а), решение пользователя 2026-10-29). Уровень — `--log-level`, `CODELAB_LOG_LEVEL`, затем `logging.level`; по умолчанию `info`.

#### Scenario: Лог в файл
- **WHEN** бинарь запущен с `--log-file <tmp>/agent.log` и проводит ход
- **THEN** файл содержит записи JSON Lines с ключами `ts`, `level`, `event` первыми, права файла — `0600`

#### Scenario: Лог в stdout запрещён
- **WHEN** бинарь запущен с `--log-file /dev/stdout`
- **THEN** процесс завершается с кодом `64` и текстом `--log-file cannot point to stdout: stdout carries the ACP protocol`

#### Scenario: Файл лога из конфига
- **WHEN** `config.yaml` задаёт `logging.file: <tmp>/a.log` и `logging.level: debug`, а флагов логов нет
- **THEN** записи уровня `debug` пишутся в `<tmp>/a.log` с правами `0600`; с флагом `--log-file <tmp>/b.log` пишется только `b.log`

### Requirement: Жизненный цикл процесса
Процесс SHALL завершаться безопасно через `AcpAgentServer.shutdown`: EOF stdin в режиме `--stdio` — код `0`; `SIGINT` — `130`; `SIGTERM` — `143` (где ОС его поддерживает); повторный сигнал во время завершения — немедленный выход с тем же кодом. Ошибка запуска вне ошибок использования (например, занятый порт) SHALL давать код `1` и текст в stderr.

#### Scenario: EOF во время хода
- **WHEN** stdin процесса закрывается, пока идёт ход
- **THEN** ход отменяется, журнал дописывается, процесс завершается с кодом `0`

#### Scenario: SIGTERM
- **WHEN** процессу `serve --ws` приходит `SIGTERM`
- **THEN** активные ходы отменяются, сокеты закрываются, код выхода — `143`

### Requirement: MCP-серверы в бинаре
`codelab-agent serve` SHALL собирать ядро с `AgentCoreServices.mcp`: `McpClientConnector` с stdio-транспортом `codelab_agent_io` и streamable HTTP на HTTP-клиенте хоста (design.md change `add-agent-mcp-client`, D3). HTTP-клиент один на процесс — тот же, что у LLM-провайдеров, — и закрывается при завершении хоста. Профиль `agent-serve` даёт capability `mcp` с транспортами `stdio` и `http`, поэтому `initialize` по `--stdio` объявляет `mcpCapabilities.http: true`.

Серверы SHALL приходить из двух источников: из `session/new.mcpServers` и из `mcp.servers` конфигурации (`CoreConfig.mcpServers`, `origin: config`) с таймаутом вызова `call_timeout` каждого сервера.

В `codelab-agent serve --ws` capability `mcp` SHALL быть выключена с причиной профиля: серверы клиента и серверы конфига пропускаются `mcp.server.skipped`, `initialize` объявляет `mcpCapabilities.http: false` — сознательное отступление от `03-Session Setup.md` (stdio MUST) ради безопасности: держатель токена WebSocket не должен запускать команды на машине агента (design.md change `add-agent-mcp-client`, D3). Завершение процесса агента (EOF stdin для `--stdio`, сигнал) SHALL закрывать сессии и тем самым завершать процессы stdio-серверов не позже 10 с.

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
- **WHEN** `codelab-agent serve --ws` с stdio-сервером в `mcp.servers` конфига получает `session/new` со stdio-сервером в `mcpServers`
- **THEN** ответ успешен, ни один процесс сервера не запущен, лог `mcp.server.skipped` с причиной профиля для обоих, `initialize` этого соединения объявляет `mcpCapabilities.http: false`

#### Scenario: Возможности MCP в initialize
- **WHEN** бинарь `serve --stdio` отвечает на `initialize`
- **THEN** `agentCapabilities.mcpCapabilities` — `{"http": true, "sse": false}`

### Requirement: Конфиг бинаря из файлов, окружения и флагов
`codelab-agent serve` SHALL собирать ядро из результата `ConfigLoader` (capability `agent-configuration`). Слои конфигурации:
- проектные слои — для корня запуска, канонического текущего каталога процесса;
- флаги и переменные этапа 4 — слои окружения и флагов:
  - `--provider openai-compatible|anthropic` и `--base-url <url>` задают провайдера с id `cli`. `api_key_env: CODELAB_API_KEY` SHALL ставиться, только если `CODELAB_API_KEY` задана и непуста: без неё запросы идут без ключа, как на этапе 4 (Ollama, LM Studio), и предупреждения `config.provider.key_missing` нет (решение пользователя 2026-10-30);
  - слой флагов SHALL заменять `providers.cli` целиком, а не сливаться с ним по полям: `headers`, `api_key_env`, `api_key_secret` и модели провайдера `cli` из файлов НЕ SHALL уходить на адрес `--base-url` (решение пользователя 2026-10-30);
  - повторяемый `--model <id>` (или `CODELAB_MODEL`) с `--provider` задаёт модели `cli/<id>`, первая — модель по умолчанию;
  - `--model <provider>/<model>` без `--provider` SHALL выбирать модель по умолчанию из конфига (`agent.default_model`); повтор `--model` без `--provider` — ошибка использования;
  - `--model <id>` без косой черты и без `--provider` — ошибка использования `--model needs <provider>/<model> without --provider`;
  - `--permission-mode` / `CODELAB_PERMISSION_MODE` — `permissions.mode`, `autopilot` — только флагом;
  - `--max-steps <n>` / `CODELAB_MAX_STEPS` — `budget.max_steps`; не целое `n ≥ 1` — ошибка использования (флаг) или проблема конфига (переменная);
  - `--config <path>` / `CODELAB_CONFIG` — дополнительный файл с приоритетом выше `config.local.yaml`, флаг сильнее переменной. `--config` МОЖЕТ быть относительным и разрешается от текущего каталога процесса. `CODELAB_CONFIG` SHALL быть абсолютным путём: относительный — ошибка использования, текст называет переменную `CODELAB_CONFIG` (решение пользователя 2026-10-30; относительный путь считался бы от корня проекта, а слой `--config` не подчиняется доверию CFG-3, и склонированный репозиторий обошёл бы его). Явно названный, но отсутствующий файл — проблема конфига `cannot read the file` с источником `--config` или `CODELAB_CONFIG` и код `64`.

Каталог моделей SHALL содержать модели всех провайдеров конфигурации, а запросы SHALL маршрутизироваться по провайдеру модели. Сессии SHALL храниться в `JsonlSessionStore` под `sessions.dir` (по умолчанию `$CODELAB_HOME/sessions`) с политикой `sessions.fsync`. Исключение — сценарий `--llm-script`: журнал SHALL вестись только по `--sessions-dir` (без него — в памяти), а явно заданные `sessions.dir` и `sessions.fsync` из `--config` НЕ SHALL применяться и SHALL давать по предупреждению `config.key.not_applied {key, source}` (решение пользователя 2026-10-30): сценарий не трогает `$CODELAB_HOME` и пользовательские журналы. Сужение `profile.agent-serve.*` SHALL применяться к профилю; расширение профиля SHALL быть ошибкой конфига.

Невалидный конфиг SHALL завершать процесс кодом `64` до старта транспорта. В stderr и в лог `serve.config.invalid` SHALL выводиться каждая проблема с файлом, строкой, столбцом и путём ключа. Отсутствие модели по умолчанию (ни `agent.default_model`, ни `--provider` с `--model`, ни `--llm-script`) SHALL быть проблемой `agent.default_model: required`. Неизвестная переменная `CODELAB_*` SHALL давать предупреждение в лог. Значения `CODELAB_API_KEY`, ключей из `api_key_env` и подстановок `${ENV}` НЕ SHALL попадать в лог, текст ошибок и строковое представление опций.

С `--llm-script` бинарь НЕ SHALL читать `$CODELAB_HOME/config.yaml`, проектные слои и не искать `codelab.toml`; `--config` SHALL читаться.

Ошибки использования SHALL завершать процесс кодом `64` с текстом в stderr: неизвестный флаг, неизвестный режим, `--provider` вместе с `--llm-script`, `--sessions-dir` без `--llm-script`, `--config` с расширением `.toml`, относительный `CODELAB_CONFIG`, `--model` без косой черты без `--provider`, повтор `--model` без `--provider`.

#### Scenario: Битый конфиг не доходит до первого хода
- **WHEN** `<cwd>/.codelab/config.yaml` содержит в строке 3 неизвестный ключ, а бинарь запускается `serve --stdio`
- **THEN** процесс завершается с кодом `64` до чтения stdin, stderr содержит `config.yaml:3:` и путь ключа (`codelab_agent_io/test/config/config_loader_test.dart: invalid config reports key path and line`; процессный тест бинаря)

#### Scenario: Флаги этапа 4 без файлов
- **WHEN** бинарь запущен с `--provider openai-compatible --base-url http://localhost:4000 --model gpt-5 --model gpt-4` в каталоге без файлов конфига
- **THEN** опция `model` новой сессии содержит `cli/gpt-5` и `cli/gpt-4`, текущее значение — `cli/gpt-5`

#### Scenario: Модель из конфига
- **WHEN** `config.yaml` объявляет провайдеров `openai` и `anthropic`, а бинарь запущен с `--model anthropic/claude-sonnet-4` без `--provider`
- **THEN** модель новой сессии — `anthropic/claude-sonnet-4`, опция `model` содержит модели обоих провайдеров, запрос уходит на `base_url` провайдера `anthropic`

#### Scenario: Провайдер флагов без ключа
- **WHEN** бинарь запущен с `--provider openai-compatible --base-url http://localhost:11434/v1 --model llama3` без `CODELAB_API_KEY` (во втором варианте — `CODELAB_API_KEY=""`)
- **THEN** загрузка успешна без предупреждения `config.provider.key_missing`, ход уходит на `base_url` без заголовка авторизации

#### Scenario: Флаги заменяют providers.cli целиком
- **WHEN** `$CODELAB_HOME/config.yaml` объявляет `providers.cli` с `base_url: https://a.example`, `headers.X-Token: "${T}"` и моделью `m1`, а бинарь запущен с `--provider openai-compatible --base-url http://localhost:4000 --model gpt-5`
- **THEN** запрос уходит на `http://localhost:4000` без заголовка `X-Token`, опция `model` содержит `cli/gpt-5` и не содержит `cli/m1`

#### Scenario: Ошибки --model без --provider
- **WHEN** бинарь запущен с `--model gpt` без `--provider`; во втором варианте — с `--model a/x --model b/y` без `--provider`
- **THEN** в обоих вариантах код `64` и текст ошибки использования в stderr до загрузки конфига

#### Scenario: Нет модели по умолчанию
- **WHEN** бинарь запущен `serve --stdio` без `--provider`, без `--llm-script`, а ни один слой не задаёт `agent.default_model`
- **THEN** код `64`, stderr содержит `agent.default_model: required`

#### Scenario: Относительный CODELAB_CONFIG
- **WHEN** бинарь запущен с `CODELAB_CONFIG=.codelab/extra.yaml`
- **THEN** код `64`, stderr называет `CODELAB_CONFIG` и требование абсолютного пути, файл не читается; тот же путь через `--config .codelab/extra.yaml` читается от текущего каталога процесса

#### Scenario: Явно названный файл отсутствует
- **WHEN** бинарь запущен с `--config <tmp>/missing.yaml`
- **THEN** код `64` до старта транспорта, stderr содержит `--config` и `cannot read the file`

#### Scenario: Журналы сценария не берутся из конфига
- **WHEN** бинарь запущен с `--llm-script hello.json --config <tmp>/c.yaml`, где `c.yaml` задаёт `sessions.dir: <tmp>/s` и `sessions.fsync: always`
- **THEN** каталог `<tmp>/s` не создаётся, журнал ведётся в памяти, лог содержит два `config.key.not_applied` с ключами `sessions.dir` и `sessions.fsync`; с `--sessions-dir <tmp>/d` журнал пишется в `<tmp>/d`

#### Scenario: Ключ не попадает в лог
- **WHEN** бинарь запущен с `CODELAB_API_KEY=sk-test-secret`, `--log-level debug` и `--log-file <tmp>`
- **THEN** ни stderr, ни файл лога не содержат строки `sk-test-secret`

#### Scenario: Провайдер вместе со сценарием
- **WHEN** бинарь запущен с `--provider anthropic --llm-script hello.json`
- **THEN** процесс завершается с кодом `64` и сообщением о взаимоисключающих флагах

#### Scenario: Каталог журналов без сценария
- **WHEN** бинарь запущен с `--provider anthropic --model claude --sessions-dir /tmp/sessions`
- **THEN** процесс завершается с кодом `64` и сообщением, что `--sessions-dir` требует `--llm-script`

#### Scenario: Сценарий не читает конфиг пользователя
- **WHEN** бинарь запущен с `--llm-script hello.json` и `CODELAB_HOME=<tmp>`, где `config.yaml` невалиден
- **THEN** ход проходит, каталог `<tmp>` не изменён

### Requirement: Подкоманда config бинаря
`codelab-agent config check [--cwd <dir>]` SHALL работать без запуска сервера, без открытия транспорта и без чтения stdin. Тексты, правила и коды выхода — общая реализация `ConfigCommands` (capability `agent-configuration`, требование «Подкоманда config check»); флагов `serve` у команды нет, окружение (включая `CODELAB_CONFIG`) учитывается. `codelab-agent config` без подкоманды, с неизвестной подкомандой, с лишними аргументами или с ошибкой разбора аргументов (неизвестный флаг, `--cwd` без значения) SHALL завершаться кодом `64` со справкой команды `config` в stderr. Общая справка бинаря (`serveUsage`, печатается при ошибке использования `serve`) SHALL упоминать `config check`.

#### Scenario: Проверка без сервера
- **WHEN** запускается `codelab-agent config check` в каталоге с валидным `config.yaml`
- **THEN** stdout заканчивается `Config: valid`, код `0`, процесс не открывает транспорт ACP

#### Scenario: Неизвестная подкоманда
- **WHEN** запускается `codelab-agent config set budget.max_steps 10` или `codelab-agent config migrate`
- **THEN** код `64`, в stderr — справка подкоманды `config`; файл конфига не изменён

#### Scenario: Ошибка разбора аргументов config
- **WHEN** запускается `codelab-agent config check --bogus` или `codelab-agent config check --cwd` без значения
- **THEN** код `64`, stderr содержит причину и справку команды `config` (`Usage: codelab-agent config check [--cwd <dir>]`), stdout пуст

#### Scenario: Общая справка называет config check
- **WHEN** бинарь запущен с неизвестным флагом `serve`, например `codelab-agent serve --stdio --bogus`
- **THEN** код `64`, справка в stderr содержит `config check`

### Requirement: Файлы проекта в бинаре
`codelab-agent serve --stdio` SHALL передавать ядру `ProjectFilesLoader` из `codelab_agent_io` в `AgentCoreServices.projectFiles` (design.md change `add-agent-project-files`, D16). Пользовательская область — `$CODELAB_HOME` процесса. С `--llm-script` пользовательская область НЕ SHALL читаться, а проект SHALL считаться недоверенным (глобальный слой не читается); контекст проекта (`AGENTS.md` дерева `cwd`) SHALL читаться.

`codelab-agent serve --ws` НЕ SHALL передавать загрузчик (решение пользователя 2026-10-30; D2, D16): клиент WebSocket выбирает `cwd` и может быть на другой машине, а чтение шло бы с файловой системы машины агента и отдавало бы удалённому клиенту инструкции любого каталога этой машины. Поэтому по WebSocket не читаются ни файлы проекта (`AGENTS.md`/`CLAUDE.md`, `.codelab/prompts`, `.codelab/agents`), ни файлы `$CODELAB_HOME` (`AGENTS.md`, `prompts/`, `agents/`). Это сужение по транспорту, как у MCP (`mcp.server.skipped`, design.md change `add-agent-mcp-client`, D3): хост SHALL один раз при запуске писать событие `project_files.skipped` (info) с полями `transport: ws` и `reason: "project files are not read over WebSocket"`.

#### Scenario: Шаблон пользователя
- **WHEN** `AgentHost.build` для `--stdio` получает временный `CODELAB_HOME` с `prompts/review.md` и создаёт сессию
- **THEN** `session.commands` содержит `review`

#### Scenario: Сценарий не читает CODELAB_HOME
- **WHEN** `serve --stdio --llm-script` запускается во временном `cwd` с `AGENTS.md`, а `CODELAB_HOME` содержит `prompts/review.md` и `AGENTS.md`
- **THEN** лог `project_context.loaded` называет только `AGENTS.md` из `cwd`, а `available_commands_update` после `session/new` пуст

#### Scenario: WebSocket не читает файлы проекта
- **WHEN** `AgentHost.build` для `--ws` получает временный `CODELAB_HOME` с `AGENTS.md`, а сессия создаётся в `cwd` с `AGENTS.md`
- **THEN** `AgentCoreServices.projectFiles` равен `null`, системный промпт не содержит секции `project_context`, лог содержит одно событие `project_files.skipped` с `transport: ws` и не содержит `project_context.loaded`

### Requirement: Хранилище секретов в бинаре
`AgentHost.build` SHALL создавать одно хранилище по `secrets.backend` загруженного конфига и окружению процесса, а над ним — один `SecretResolver` на процесс. Резолвер SHALL передаваться в функцию модели (`createRoutedStreamFunction`) и в `AgentCoreServices.secrets` (design.md, D11).
- **`--debug-secrets`** — флаг `serve` без значения; он и `CODELAB_DEBUG_SECRETS=1` включают режим отладки резолвера (capability `agent-secrets`, «Диагностика обращений к секретам»). Режим НЕ SHALL менять уровень лога.
- **`secrets.backend: keychain`** — проблема конфигурации «not supported yet» (capability `agent-secrets`): `serve` завершается кодом `64` до старта транспорта.
- **`--llm-script`** SHALL использовать бэкенд `env` независимо от `secrets.backend`: `secrets.yaml` не читается, событие выбора — `secrets.backend.selected {backend: env, reason: forced by --llm-script}`.
- **`secrets.backend: file`** SHALL давать при каждом старте предупреждение `secrets.backend.plaintext {path}` в лог и stderr.
- **`serve --ws`** SHALL разрешать ключи провайдеров так же, как `--stdio`.

Значения секретов НЕ SHALL попадать в stdout, stderr, лог, журнал сессии и кадры ACP.

#### Scenario: Ключ провайдера из переменной переопределения
- **WHEN** `codelab-agent serve --stdio` запускается с конфигом `providers.p.api_key_secret: codelab/p`, `CODELAB_SECRET_CODELAB_P=sk-test-0123456789abcdef` и локальным HTTP-сервером провайдера в тесте
- **THEN** запрос к серверу несёт ключ, а stdout, stderr и файл лога не содержат `sk-test-0123456789abcdef`

#### Scenario: Секрет не задан — ошибка хода
- **WHEN** тот же конфиг без переменной, `secrets.backend: env`, клиент выполняет `session/prompt` с моделью `p/<model>`
- **THEN** ответ `session/prompt` — JSON-RPC ошибка, текст которой содержит `API key secret codelab/p is not set. Run: codelab secret set codelab/p`; процесс продолжает работать

#### Scenario: Режим отладки секретов
- **WHEN** тот же запуск с `--debug-secrets` и переменной `CODELAB_SECRET_CODELAB_P`
- **THEN** лог содержит `secrets.lookup` с `name: codelab/p`, `source: env`, `found: true` и не содержит значения

#### Scenario: Бэкенд file при старте
- **WHEN** `serve --stdio` запускается с глобальным `secrets.backend: file` во временном `CODELAB_HOME`
- **THEN** лог содержит `secrets.backend.plaintext` с путём `<CODELAB_HOME>/secrets.yaml`, файл не создан, процесс работает

#### Scenario: Сценарий не читает secrets.yaml
- **WHEN** `serve --stdio --llm-script <file>` запускается с `--config`, где `secrets.backend: file`, а в `CODELAB_HOME` лежит `secrets.yaml`
- **THEN** процесс стартует, ход сценария выполняется, файл не открывается, лог содержит `secrets.backend.selected` с `backend: env` и `reason: forced by --llm-script`

### Requirement: Подкоманда secret бинаря
`codelab-agent secret set|delete|list` SHALL работать без запуска сервера и без открытия транспорта. Тексты, правила и коды выхода даёт общая реализация `SecretCommands` (capability `agent-secrets`, «Подкоманды secret»). Разбор аргументов — `apps/codelab_agent/lib/src/cli/secret_cli.dart`. `codelab-agent secret` без подкоманды или с неизвестной подкомандой SHALL завершаться кодом `64`, сообщением `codelab-agent: secret needs a subcommand: set, delete or list` и справкой `secret` в stderr; ошибка разбора argv — кодом `64`, сообщением `codelab-agent: invalid arguments for secret` без присланных слов и справкой `secret`. Ошибки использования из `SecretCommands` (неверное имя, значение аргументом) бинарь SHALL дополнять справкой `secret`, ошибки значения — нет. Справка `secret` называет `codelab-agent`. Общая справка бинаря SHALL упоминать `secret set|delete|list`. stdin SHALL читаться только подкомандой `set`.

#### Scenario: Неизвестная подкоманда
- **WHEN** запускается `codelab-agent secret show codelab/openai`
- **THEN** код `64`, stderr содержит `secret needs a subcommand` и справку `secret`, не содержит `codelab/openai`, stdout пуст, хранилище не вызывалось

#### Scenario: list с бэкендом env
- **WHEN** запускается `codelab-agent secret list` с `secrets.backend: env` во временном `CODELAB_HOME`
- **THEN** первая строка stdout — `Backend: env`, код `0`

