## MODIFIED Requirements

### Requirement: Профили хостов и сужение
`HostProfile.of(name)` SHALL знать профили `agent-serve` и `embedded-cli` с явным состоянием каждой capability ядра по таблице §10.4 документа ядра (HOST-1):
- `shellExec`, `fileListing`, `interactiveApproval` — как в этапе 2;
- `sessionPersistence` — transport `jsonl-file` в обоих профилях;
- `compaction` — `on` в обоих профилях;
- `mcp` — transport `{stdio, http}` в обоих профилях (design.md change `add-agent-mcp-client`, D3).

Для неизвестного имени `of` бросает `ArgumentError`. Состояния `off` и `transport` SHALL нести непустую причину.

Режим новой сессии по умолчанию в обоих профилях — `standard` (§10.5).

`narrowed(overrides)` SHALL принимать только сужение: `on` → `transport` → `off` и `transport(A)` → `transport(B)` при `B ⊆ A`. Расширение SHALL давать `HostWiringException` с именем capability (HOST-2).

#### Scenario: Расширение запрещено
- **WHEN** у профиля с `fileListing: off` вызывается `narrowed({fileListing: CapabilityOn()})`
- **THEN** вызов бросает `HostWiringException`, называющий `fileListing`

#### Scenario: Журнал в памяти для тестов
- **WHEN** профиль `agent-serve` сужается до `sessionPersistence: off` и собирается над `MemorySessionStore`
- **THEN** сборка не бросает исключения, а `CorePlan.offReasons` содержит причину для `sessionPersistence`

#### Scenario: Сужение транспортов MCP
- **WHEN** у `agent-serve` вызывается `narrowed({mcp: CapabilityTransport({'http'}, …)})`, а затем `narrowed({mcp: CapabilityTransport({'http', 'stdio'}, …)})`
- **THEN** первое сужение принято, второе бросает `HostWiringException`, называющий `mcp`

### Requirement: Минимальная сборка buildAgentCore
Хост SHALL собирать ядро только через `buildAgentCore(profile, services, config, streamFunction)` (HOST-6). Функция выполняет шаги §10.7 документа ядра в объёме этапов 2–4 и 8 (design.md change `add-agent-core-loop-and-tools`, D12; design.md change `add-agent-core-sessions-and-compaction`, D12; design.md change `add-dart-agent-acp-server`, D3; design.md change `add-agent-mcp-client`, D3, D6):

1. **Сужение по сервисам и конфигурации:**
   - нет `gate` → `interactiveApproval` выключается;
   - env без `DirectoryListing` → `fileListing` выключается;
   - `CoreConfig.compaction.enabled == false` → `compaction` выключается с причиной «выключено конфигом»;
   - нет `services.mcp` (`McpConnector`) → `mcp` выключается с причиной «сервис MCP не передан»;
   - включённый `shellExec` над `MemoryExecutionEnv` → `HostWiringException`.
2. **Проверка сервисов** включённых capability (HOST-3):
   - включённая `sessionPersistence` над `MemorySessionStore` → `HostWiringException`, называющий `sessionPersistence`; журнал в памяти — только при выключенной capability (тесты, хост без постоянного носителя);
   - транспорт capability `mcp`, которого нет в `services.mcp.transports`, → `HostWiringException`, называющий `mcp` и транспорт.
3. **Env-цепочка** `BoundedEnv(baseEnv, root: cwd)` на сессию. Все инструменты получают один экземпляр внешнего `BoundedEnv` (ENV-2).
4. **Реестр инструментов:**
   - `read`, `write`, `edit`, `update_plan` — всегда;
   - `exec` — при `shellExec`;
   - `ls`, `search` — при `fileListing`;
   - дубликат имени встроенного инструмента → `HostWiringException` (HOST-5).

   Это базовый реестр. Каждая сессия получает свою копию с MCP-инструментами своих серверов («MCP-серверы сессии»).
5. **Политика разрешений** — первым звеном `beforeToolCall`, хуки хоста `extraBeforeToolCall` — последними; `extraAfterToolCall` — первыми в `afterToolCall`.
6. **Промпт** из секций включённых capability.
7. **`AgentRuntime`** с хранилищем `services.sessions`, настройками `CoreConfig.compaction`, каталогом `services.models` (без каталога — каталог из одной `CoreConfig.defaultModel`) и усилием рассуждения по умолчанию `CoreConfig.effort` (`medium`).
8. **`CorePlan`** со списком инструментов базового реестра, секций промпта и причин выключения, лог `host.plan`.

Выключенная capability НЕ SHALL оставлять на поверхности модели ни схемы, ни секции промпта (HOST-4).

#### Scenario: Каталог по умолчанию
- **WHEN** ядро собирается без `services.models`
- **THEN** `AgentRuntime.models.models` содержит одну модель — `CoreConfig.defaultModel`

#### Scenario: Матрица профиля
- **WHEN** ядро собирается для `agent-serve` на `MemoryExecutionEnv` и `MemorySessionStore` с `shellExec` и `sessionPersistence`, выключенными через `narrowed`
- **THEN** схемы запроса — `read`, `write`, `edit`, `update_plan`, `ls`, `search` в этом порядке, в промпте нет `tools/exec`, а `CorePlan.offReasons` содержит причины для `shellExec`, `sessionPersistence` и `mcp`

#### Scenario: Включено без сервиса
- **WHEN** профиль с включённым `shellExec` собирается над `MemoryExecutionEnv`
- **THEN** `buildAgentCore` бросает `HostWiringException`, называющий `shellExec`

#### Scenario: Файловый журнал над памятью
- **WHEN** профиль `embedded-cli` без сужения собирается с `MemorySessionStore`
- **THEN** `buildAgentCore` бросает `HostWiringException`, называющий `sessionPersistence`

#### Scenario: Сжатие выключено конфигом
- **WHEN** `CoreConfig.compaction` имеет `enabled: false`
- **THEN** `CorePlan.offReasons` содержит причину для `compaction`, а ответ `overflow` не вызывает сжатия

#### Scenario: Без gate вопрос становится отказом
- **WHEN** ядро собрано без `PermissionGate`, а модель в режиме `standard` зовёт `write`
- **THEN** `CorePlan.offReasons` содержит `interactiveApproval`, вызов отклонён с причиной `no approval interface is available`, ход продолжается

#### Scenario: Коннектор без нужного транспорта
- **WHEN** `agent-serve` с `mcp: {stdio, http}` собирается с `McpConnector`, у которого `transports` — `{stdio}`
- **THEN** `buildAgentCore` бросает `HostWiringException`, называющий `mcp` и `http`

## ADDED Requirements

### Requirement: MCP-серверы сессии
`createSession(SessionSpec)` и `loadSession(id, ports, mcpServers: …)` SHALL подключать MCP-серверы сессии до возврата сессии (design.md change `add-agent-mcp-client`, D6).

1. **Список.** Серверы `CoreConfig.mcpServers`, затем `SessionSpec.mcpServers`. Сервер клиента с тем же `name` заменяет сервер конфига (§13.4, шаг 2); сервер конфига пропускается с `mcp.server.skipped` и причиной `replaced by a server of the client with the same name`. Второй сервер с тем же `name` внутри одного источника (`duplicate server name in the same source`) и сервер с пустым `name` (`empty server name`) пропускаются с `mcp.server.skipped`.
2. **Фильтр.** При выключенной capability `mcp` каждый сервер пропускается с `mcp.server.skipped` и причиной выключения. Сервер с транспортом вне набора capability пропускается с причиной, называющей транспорт и профиль.
3. **Подключение.** `services.mcp.connect` подключает серверы параллельно, каждый в своём `connectTimeout`. Сбой сервера SHALL давать `mcp.server.failed` и сессию без его инструментов. Исключение `connect` целиком SHALL давать `mcp.server.failed` с причиной `MCP connector failed: <runtimeType>` и сессию без MCP-инструментов, а не ошибку `createSession` / `loadSession`.
4. **Регистрация.** После всех подключений, в порядке списка, внутри сервера — в порядке `tools/list`, в реестр сессии поверх копии базового реестра.
5. **Коллизия имени** MCP-инструмента со встроенным или с уже зарегистрированным SHALL отключать весь более поздний сервер (транспорт закрыт, инструменты не зарегистрированы) с `mcp.server.failed`, причина которого называет оба источника. Сессия SHALL создаваться (HOST-5). Независимо от проверки коннектора ядро SHALL отклонять с `mcp.tool.invalid` инструмент коннектора без префикса `mcp__` или с именем встроенного инструмента (защита в глубину).
6. **Изоляция.** Инструменты одной сессии НЕ SHALL быть видны другим сессиям.
7. **Закрытие.** `AgentSession.close()` и `AgentRuntime.dispose()` SHALL закрывать транспорты серверов сессии после остановки хода. Если `createSession` / `loadSession` падает после подключения серверов, подключения SHALL закрываться до проброса ошибки: сессия, не возвращённая вызывающему, не оставляет живых процессов.
8. **Обновление набора.** Ожидающее обновление `McpSessionTools.takeUpdate()` ядро SHALL применять на границе шага через `prepareNextStep` полями `StepUpdate.tools` и `StepUpdate.systemPrompt` (транскрипт цикла не меняется), а между ходами — перед началом хода.
9. **Журнал.** Описания серверов НЕ SHALL записываться в журнал.

`AgentSession.setMcpServers(servers)` SHALL заменять серверы с `origin: session`:
- совпавшие по `name` и параметрам остаются;
- исчезнувшие закрываются, новые подключаются;
- без хода — сразу, во время хода — после `TurnEnded`.

#### Scenario: Сервер клиента побеждает сервер конфига
- **WHEN** `CoreConfig.mcpServers` содержит `github` (http), а `SessionSpec.mcpServers` — `github` (stdio)
- **THEN** подключается только stdio-сервер клиента

#### Scenario: Коллизия двух серверов
- **WHEN** `mcpServers` содержит серверы `my.srv` и затем `my_srv`, оба с инструментом `t`, а `my_srv` подключается раньше
- **THEN** оба дают имя `mcp__my_srv__t`; сервер `my_srv`, стоящий в списке позже, отключён с `mcp.server.failed`, причина называет `my_srv` и `my.srv`; сессия создана и содержит `mcp__my_srv__t` сервера `my.srv` (`core/mcp-tool-name-sanitized`, E-05)

#### Scenario: Коллизия внутри одного сервера
- **WHEN** сервер `x` отдаёт инструменты `get issue` и `get_issue`
- **THEN** сервер `x` отключён с причиной о коллизии `mcp__x__get_issue`, сессия создана

#### Scenario: Сессии не видят чужих инструментов
- **WHEN** сессия A подключает сервер `fake`, а сессия B создана без серверов
- **THEN** запрос к модели сессии B не содержит схем `mcp__`

#### Scenario: Процессы закрываются вместе с сессией
- **WHEN** сессия с stdio-сервером закрывается `AgentSession.close()`
- **THEN** `close()` транспорта вызван после окончания хода, лог `mcp.server.closed`

#### Scenario: Сбой после подключения закрывает серверы
- **WHEN** сессия подключила stdio-сервер, а запись журнала в `createSession` бросает исключение
- **THEN** `createSession` пробрасывает ошибку, а `close()` транспорта сервера вызван до этого

#### Scenario: Коннектор бросил
- **WHEN** `McpConnector.connect` бросает исключение
- **THEN** `createSession` возвращает сессию без инструментов `mcp__`, лог `mcp.server.failed` с причиной `MCP connector failed: <runtimeType>`

#### Scenario: Коннектор отдал инструмент без префикса
- **WHEN** fake `McpConnector` возвращает инструменты `read` и `mcp__x__t`
- **THEN** в реестре сессии только `mcp__x__t` от коннектора, встроенный `read` не подменён, лог `mcp.tool.invalid` для `read`

#### Scenario: Capability выключена
- **WHEN** ядро собрано без `services.mcp`, а `SessionSpec.mcpServers` содержит сервер
- **THEN** сервер пропущен с `mcp.server.skipped` и причиной «сервис MCP не передан», сессия создана
