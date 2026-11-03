## MODIFIED Requirements

### Requirement: Секреты MCP-серверов конфигурации
Значения `env.*` и `headers.*` MCP-сервера конфигурации с `${secret:<name>}` SHALL храниться в `CoreConfig` шаблоном из литералов и ссылок, а не строкой (design.md change `add-agent-secret-store`, D4). Раскрывать их SHALL коннектор перед каждой попыткой подключения сервера — первой и повторной — функцией раскрытия `McpConnectRequest.expandSecrets` (`McpSecretExpander`), которую рантайм строит над `AgentCoreServices.secrets` при создании и загрузке сессии, в `AgentSession.setMcpServers` и при перезагрузке конфигурации (design.md change `add-config-writer-and-reload`, D11). Раскрытая копия SHALL жить только в одной попытке; значение секрета НЕ SHALL храниться в коннекторе между попытками, поэтому после `SecretResolver.invalidate()` следующая попытка берёт новое значение.

Сервер с ненайденным секретом НЕ SHALL подключаться: функция раскрытия бросает `McpSecretsException(reason)`, транспорт сервера не открывается, сервер SHALL оставаться в списке сессии в состоянии `failed` с `lastError` — `reason` — и повторяться по расписанию задержек (capability `agent-mcp-client`, «Переподключение и состояние серверов сессии»). На первом сбое SHALL писаться `mcp.server.failed {server, transport, reason}` с причиной `secret <name> is not set` или `secret <name> cannot be read: <backend> is unavailable` (имя секрета и бэкенд, никогда значение). Сессия создаётся без инструментов этого сервера (agent-runtime «MCP-серверы сессии», шаг 3).

`AgentSession.close()` или `AgentRuntime.dispose()` во время раскрытия SHALL отбрасывать попытку: транспорт не открывается, `mcp.server.failed` не пишется, таймера повтора нет, процессов серверов не остаётся. `createSession` / `loadSession`, прерванные `dispose()`, SHALL завершаться `CancelledException`.

Заголовки HTTP-сервера после раскрытия SHALL идти в порядке файла конфига. `${secret:…}` в серверах `session/new.mcpServers` SHALL оставаться литералом: функция раскрытия для них не вызывается. Литерал `$${secret:x}` SHALL давать строку `${secret:x}` без обращения к резолверу. Без `AgentCoreServices.secrets` ссылка SHALL давать сбой попытки с причиной `no secret store`.

#### Scenario: Заголовок из хранилища
- **WHEN** конфиг объявляет http-сервер `gh` с `headers.Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`, а хранилище содержит `tok-test-secret`
- **THEN** транспорт попытки получает заголовок `Bearer tok-test-secret`, а лог, журнал и `McpServerSummary` не содержат `tok-test-secret`

#### Scenario: Порядок заголовков сохраняется
- **WHEN** сервер `gh` задаёт заголовки `X-A: a`, `Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`, `X-B: b` в этом порядке, секрет найден
- **THEN** транспорт получает заголовки в порядке `X-A`, `Authorization`, `X-B`

#### Scenario: Закрытие во время раскрытия
- **WHEN** `read` хранилища для сервера `gh` не завершается, а рантайм получает `dispose()` во время `createSession` (или сессия — `close()` во время `setMcpServers`)
- **THEN** транспорт `gh` не открывался, записи `mcp.server.failed` для `gh` нет, таймера повтора нет, процессов серверов не осталось; `createSession` завершается `CancelledException`

#### Scenario: Ненайденный секрет MCP
- **WHEN** у сервера `gh` секрет не задан, а у сервера `docs` ссылок нет
- **THEN** сессия создаётся, `docs` подключён, `gh` в списке сессии в состоянии `failed` с `lastError` `secret codelab/mcp/gh/authorization is not set` без инструментов, лог `mcp.server.failed` с той же причиной

#### Scenario: Секрет появился после сбоя
- **WHEN** у сервера `gh` секрет не задан при создании сессии, а затем записан в хранилище
- **THEN** очередная попытка по расписанию раскрывает его заново и подключает `gh` без перезагрузки и перезапуска

#### Scenario: Ссылка от клиента ACP — литерал
- **WHEN** `session/new.mcpServers` содержит http-сервер с заголовком `${secret:codelab/openai}`
- **THEN** резолвер не вызывается, транспорт получает строку `${secret:codelab/openai}`

#### Scenario: Недоверенный проект не читает секреты
- **WHEN** `<cwd>/.codelab/config.yaml` недоверенного проекта объявляет сервер с `${secret:codelab/openai}`
- **THEN** сервер отброшен правилом доверия, резолвер не вызывается

### Requirement: Резолвер секретов
Ядро SHALL получать значение секрета только через `SecretResolver` (`codelab_agent_core/lib/src/secrets/`, чистый Dart, без `dart:io`). `SecretResolver.secret(name, purpose)` SHALL возвращать `SecretFound(value, source)`, `SecretMissing(backend)` или `SecretUnavailable(backend, reason)` (design.md change `add-agent-secret-store`, D3).

Порядок:
1. Кэш процесса содержит имя → `SecretFound(source: "cache")`.
2. Переменная `SecretNames.envOverride(name)` задана и непуста → её значение, `source: "env"`.
3. `DescribedSecretStore.read(name)`:
   - найдено → `source` — id бэкенда;
   - `null` или пусто → `SecretMissing`;
   - `SecretStoreUnavailableException` → `SecretUnavailable` и предупреждение `secrets.backend.unavailable {backend, reason}`, не чаще одного раза на пару `(backend, reason)` за процесс.

Найденное значение SHALL кэшироваться до вызова `invalidate()` или до конца жизни резолвера, ненайденное НЕ SHALL кэшироваться. `invalidate()` SHALL очищать кэш найденных значений; его вызывает перезагрузка конфигурации (capability `agent-runtime`, «Живая перезагрузка конфигурации»; design.md change `add-config-writer-and-reload`, D8). Чтение хранилища, начатое до `invalidate()` и завершившееся после, SHALL отдавать значение своим вызывающим, но НЕ SHALL класть его в кэш.

Одновременные запросы одного имени SHALL приводить к одному вызову `read` в пределах одного поколения кэша. Переменная переопределения SHALL побеждать хранилище при любом бэкенде. `SecretFound.toString()` НЕ SHALL содержать значение. `SecretResolver.env(variable, purpose)` SHALL читать только окружение, переданное резолверу.

#### Scenario: Переменная побеждает хранилище
- **WHEN** `MemorySecretStore` содержит `codelab/openai = store-value`, а окружение — `CODELAB_SECRET_CODELAB_OPENAI=env-value`
- **THEN** `secret("codelab/openai")` даёт `env-value` с `source: env`, а `read` хранилища не вызывается

#### Scenario: Кэш и отсутствие
- **WHEN** секрет `codelab/a` найден в хранилище, а `codelab/b` отсутствует; оба запрашиваются дважды, а между запросами `codelab/b` записывается в хранилище
- **THEN** `read("codelab/a")` вызван один раз, второй ответ — `source: cache`; `codelab/b` сначала `SecretMissing`, затем `SecretFound`

#### Scenario: Одно обращение на имя
- **WHEN** три вызова `secret("codelab/a")` начинаются до завершения первого `read`
- **THEN** хранилище получает один `read`, все три вызова получают одно значение

#### Scenario: Хранилище недоступно
- **WHEN** `read` бросает `SecretStoreUnavailableException(backend: "file", reason: "<path> has permissions 0644; run: chmod 600 <path>")` на двух разных именах
- **THEN** оба вызова дают `SecretUnavailable`, а в логе ровно одно `secrets.backend.unavailable`

#### Scenario: Сброс кэша
- **WHEN** `codelab/a` найден и закэширован со значением `v1`, затем хранилище получает `v2`, и вызывается `invalidate()`
- **THEN** следующий `secret("codelab/a")` вызывает `read` и даёт `v2` с `source` бэкенда

#### Scenario: Чтение во время сброса
- **WHEN** `read("codelab/a")` начат, затем вызван `invalidate()`, затем `read` завершается значением `v1`, а хранилище уже содержит `v2`
- **THEN** вызывающий первого запроса получает `v1`, а следующий `secret("codelab/a")` снова вызывает `read` и получает `v2`
