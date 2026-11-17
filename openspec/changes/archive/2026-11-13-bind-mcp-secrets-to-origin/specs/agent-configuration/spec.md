## MODIFIED Requirements

### Requirement: MCP-серверы конфигурации
Элементы `mcp.servers` SHALL отображаться в `CoreConfig.mcpServers` с `origin: config`:
- `type: stdio` → `McpStdioServerConfig {command, args, env}`;
- `type: http` → `McpHttpServerConfig {url, headers}` с порядком заголовков файла.

Другой `type` SHALL быть проблемой `only stdio and http are supported`. `url` без схемы `http`/`https` SHALL быть проблемой. `connect_timeout` (по умолчанию `10s`) SHALL задавать `connectTimeout`. Новый ключ `call_timeout` (тип `duration`, по умолчанию `10m`, допустимо `1s..24h`) SHALL задавать `McpServerConfig.callTimeout`. Сервер с `enabled: false` SHALL попадать в `CoreConfig.mcpServers` с признаком `McpServerConfig.enabled == false` (коннектор держит его в `disabled` без подключения; capability `agent-mcp-client`, «Переподключение и состояние серверов сессии») и SHALL давать лог `mcp.server.skipped {server, reason: "disabled in config"}`; проблемы и предупреждения его сборки не пишутся, а элемент, который не из чего собрать, выпадает из списка (design.md change `bind-mcp-secrets-to-origin`, D10: прежняя фраза «НЕ SHALL попадать» устарела после change `add-config-writer-and-reload`, D10, D11).

Элементы `mcp.servers` разных слоёв SHALL сливаться по `name`: элемент верхнего слоя с тем же `name` заменяет нижний целиком, новый добавляется в конец. Это правило группы адреса и аутентификации для MCP: сервер собирается из одного слоя, и заголовки, `env` и ссылки нижнего слоя к `url` или `command` верхнего НЕ SHALL наследоваться (design.md change `bind-mcp-secrets-to-origin`, D2). Ссылки HTTP-сервера проектного слоя подчиняются требованию capability `agent-secrets` «Ссылки MCP-сервера проектного слоя привязаны к адресу»: непривязанный сервер остаётся в `CoreConfig.mcpServers` с причиной `McpServerConfig.blockedReason`, без значений непривязанных ссылок. Значения `env` и `headers` НЕ SHALL попадать в логи, журнал сессии и строковое представление.

#### Scenario: Сервер конфига в сессии
- **WHEN** глобальный `config.yaml` объявляет stdio-сервер `fake`, а клиент создаёт сессию без `mcpServers`
- **THEN** модель видит `mcp__fake__echo` с первого хода, а после закрытия сессии процесс сервера завершён

#### Scenario: Сервер клиента вытесняет сервер конфига
- **WHEN** конфиг объявляет `github` (http), а `session/new.mcpServers` — `github` (stdio)
- **THEN** подключается только сервер клиента, сервер конфига пропущен с `mcp.server.skipped` и причиной `replaced by a server of the client with the same name`

#### Scenario: Таймаут вызова из конфига
- **WHEN** сервер конфига задаёт `call_timeout: 2s`, а его инструмент не отвечает
- **THEN** через 2 с серверу уходит сигнал отмены, а результат вызова — ошибка `MCP server <id> did not answer tools/call within 2 s.`

#### Scenario: Неподдерживаемый тип в конфиге
- **WHEN** элемент `mcp.servers` задаёт `type: sse`
- **THEN** загрузка даёт проблему `mcp.servers[<name>].type: only stdio and http are supported`

#### Scenario: Сервер проектного слоя заменяет сервер пользователя целиком
- **WHEN** пользовательский слой задаёт HTTP-сервер `github` с `url: https://api.githubcopilot.com/mcp/` и заголовком `Authorization: "${secret:codelab/mcp/github/authorization}"`, а `config.local.yaml` доверенного проекта — элемент `github` с `type: http` и `url: https://mcp.internal.test/`
- **THEN** `CoreConfig.mcpServers` содержит один `github` с `url` проекта, без заголовков и без шаблонов в `secretValues`

#### Scenario: Выключенный сервер доходит до коннектора
- **WHEN** глобальный `config.yaml` объявляет stdio-сервер `docs` с `enabled: false`
- **THEN** `CoreConfig.mcpServers` содержит `docs` с `enabled == false`, лог содержит `mcp.server.skipped` с `reason: "disabled in config"`, процесс не запускался

