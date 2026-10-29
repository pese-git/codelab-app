## ADDED Requirements

### Requirement: Конфиг бинаря из файлов, окружения и флагов
`codelab-agent serve` SHALL собирать ядро из результата `ConfigLoader` (capability `agent-configuration`). Слои конфигурации:
- проектные слои — для корня запуска, канонического текущего каталога процесса;
- флаги и переменные этапа 4 — слои окружения и флагов:
  - `--provider openai-compatible|anthropic` и `--base-url <url>` задают провайдера с id `cli`, а `CODELAB_API_KEY` — его `api_key_env`;
  - повторяемый `--model <id>` (или `CODELAB_MODEL`) с `--provider` задаёт модели `cli/<id>`, первая — модель по умолчанию;
  - `--model <provider>/<model>` без `--provider` SHALL выбирать модель по умолчанию из конфига;
  - `--model <id>` без косой черты и без `--provider` — ошибка использования;
  - `--permission-mode` / `CODELAB_PERMISSION_MODE` — `permissions.mode`, `autopilot` — только флагом;
  - `--max-steps <n>` / `CODELAB_MAX_STEPS` — `budget.max_steps`;
  - `--config <path>` / `CODELAB_CONFIG` — дополнительный файл с приоритетом выше `config.local.yaml`.

Каталог моделей SHALL содержать модели всех провайдеров конфигурации, а запросы SHALL маршрутизироваться по провайдеру модели. Сессии SHALL храниться в `JsonlSessionStore` под `sessions.dir` (по умолчанию `$CODELAB_HOME/sessions`) с политикой `sessions.fsync`. Сужение `profile.agent-serve.*` SHALL применяться к профилю; расширение профиля SHALL быть ошибкой конфига.

Невалидный конфиг SHALL завершать процесс кодом `64` до старта транспорта. В stderr и в лог `serve.config.invalid` SHALL выводиться каждая проблема с файлом, строкой, столбцом и путём ключа. Отсутствие модели по умолчанию (ни `agent.default_model`, ни `--provider` с `--model`, ни `--llm-script`) SHALL быть проблемой `agent.default_model: required`. Неизвестная переменная `CODELAB_*` SHALL давать предупреждение в лог. Значения `CODELAB_API_KEY`, ключей из `api_key_env` и подстановок `${ENV}` НЕ SHALL попадать в лог, текст ошибок и строковое представление опций.

С `--llm-script` бинарь НЕ SHALL читать `$CODELAB_HOME/config.yaml`, проектные слои и не искать `codelab.toml`; `--config` SHALL читаться.

Ошибки использования SHALL завершать процесс кодом `64` с текстом в stderr: неизвестный флаг, неизвестный режим, `--provider` вместе с `--llm-script`, `--sessions-dir` без `--llm-script`, `--config` с расширением `.toml`.

#### Scenario: Битый конфиг не доходит до первого хода
- **WHEN** `<cwd>/.codelab/config.yaml` содержит в строке 3 неизвестный ключ, а бинарь запускается `serve --stdio`
- **THEN** процесс завершается с кодом `64` до чтения stdin, stderr содержит `config.yaml:3:` и путь ключа (`codelab_agent_io/test/config/config_loader_test.dart: invalid config reports key path and line`; процессный тест бинаря)

#### Scenario: Флаги этапа 4 без файлов
- **WHEN** бинарь запущен с `--provider openai-compatible --base-url http://localhost:4000 --model gpt-5 --model gpt-4` в каталоге без файлов конфига
- **THEN** опция `model` новой сессии содержит `cli/gpt-5` и `cli/gpt-4`, текущее значение — `cli/gpt-5`

#### Scenario: Модель из конфига
- **WHEN** `config.yaml` объявляет провайдеров `openai` и `anthropic`, а бинарь запущен с `--model anthropic/claude-sonnet-4` без `--provider`
- **THEN** модель новой сессии — `anthropic/claude-sonnet-4`, опция `model` содержит модели обоих провайдеров, запрос уходит на `base_url` провайдера `anthropic`

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
`codelab-agent config check [--cwd <dir>]` SHALL работать без запуска сервера и без чтения stdin. Тексты, правила и коды выхода — общая реализация `ConfigCommands` (capability `agent-configuration`, требование «Подкоманда config check»). `codelab-agent config` без подкоманды или с неизвестной подкомандой — код `64` и справка в stderr.

#### Scenario: Проверка без сервера
- **WHEN** запускается `codelab-agent config check` в каталоге с валидным `config.yaml`
- **THEN** stdout заканчивается `Config: valid`, код `0`, процесс не открывает транспорт ACP

#### Scenario: Неизвестная подкоманда
- **WHEN** запускается `codelab-agent config set budget.max_steps 10` или `codelab-agent config migrate`
- **THEN** код `64`, в stderr — справка подкоманды `config`; файл конфига не изменён

## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Минимальный конфиг из флагов
**Reason**: этап 8 (задача 8.5) вводит файлы конфигурации: флаги и переменные этапа 4 становятся слоями окружения и флагов поверх YAML-слоёв (`agent-core-architecture` §15.6, «До этапа 8»).
**Migration**: требование «Конфиг бинаря из файлов, окружения и флагов» сохраняет все флаги этапа 4 с прежним смыслом. Меняются две ошибки: `--model <provider>/<model>` без `--provider` теперь выбирает модель конфига, а запуск без модели даёт проблему `agent.default_model: required` с кодом `64`.
