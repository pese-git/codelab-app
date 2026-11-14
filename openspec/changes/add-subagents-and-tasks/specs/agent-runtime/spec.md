## MODIFIED Requirements

### Requirement: Минимальная сборка buildAgentCore
Хост SHALL собирать ядро только через `buildAgentCore(profile, services, config, streamFunction)` (HOST-6). Функция выполняет шаги §10.7 документа ядра в объёме этапов 2–4 и 8 (design.md change `add-agent-core-loop-and-tools`, D12; design.md change `add-agent-core-sessions-and-compaction`, D12; design.md change `add-dart-agent-acp-server`, D3; design.md change `add-agent-mcp-client`, D3, D6; design.md change `add-subagents-and-tasks`, D13, D17):

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
   - `read`, `write`, `edit`, `task_create`, `task_update`, `task_list`, `task_get` — всегда;
   - `exec` — при `shellExec`;
   - `ls`, `search` — при `fileListing`;
   - `agent` — на сессию при `subagents.enabled` конфига этой сессии на момент её создания и эффективном окне контекста модели сессии не меньше порога субагентов 32 768 токенов (design.md change `add-subagents-and-tasks`, D40; иначе `agent` не регистрируется, лог `subagent.unavailable`, ошибки нет) (живая перезагрузка действует на новые сессии, design.md change `add-subagents-and-tasks`, D37); `enum` типов — из встроенных типов и определений агентов сессии (agent-subagents «Инструмент task и типы субагентов»);
   - дубликат имени встроенного инструмента → `HostWiringException` (HOST-5).

   Это базовый реестр. Каждая сессия получает свою копию с MCP-инструментами своих серверов («MCP-серверы сессии») и с `agent`.
5. **Политика разрешений** — первым звеном `beforeToolCall`, хуки хоста `extraBeforeToolCall` — последними; `extraAfterToolCall` — первыми в `afterToolCall`.
6. **Промпт** из секций включённых capability.
7. **`AgentRuntime`** с хранилищем `services.sessions`, настройками `CoreConfig.compaction` и `CoreConfig.subagents`, каталогом `services.models` (без каталога — каталог из одной `CoreConfig.defaultModel`) и усилием рассуждения по умолчанию `CoreConfig.effort` (`medium`).
8. **`CorePlan`** со списком инструментов базового реестра, секций промпта и причин выключения, лог `host.plan`.

Выключенная capability НЕ SHALL оставлять на поверхности модели ни схемы, ни секции промпта (HOST-4).

#### Scenario: Каталог по умолчанию
- **WHEN** ядро собирается без `services.models`
- **THEN** `AgentRuntime.models.models` содержит одну модель — `CoreConfig.defaultModel`

#### Scenario: Матрица профиля
- **WHEN** ядро собирается для `agent-serve` на `MemoryExecutionEnv` и `MemorySessionStore` с `shellExec` и `sessionPersistence`, выключенными через `narrowed`, и `subagents.enabled: false`
- **THEN** схемы запроса — `read`, `write`, `edit`, `task_create`, `task_update`, `task_list`, `task_get`, `ls`, `search` в этом порядке, в промпте нет `tools/exec`, а `CorePlan.offReasons` содержит причины для `shellExec`, `sessionPersistence` и `mcp`

#### Scenario: Субагенты включены
- **WHEN** та же сборка с `subagents.enabled: true`
- **THEN** схемы запроса сессии дополнительно содержат `agent` последним встроенным инструментом, а в промпте есть описание `agent` со списком типов

#### Scenario: Субагенты выключены перезагрузкой
- **WHEN** ядро собрано с `subagents.enabled: true`, открыта сессия A, затем перезагрузка конфига ставит `subagents.enabled: false` и открывается сессия B
- **THEN** схемы сессии A по-прежнему содержат `agent`, у сессии B `agent` нет, а `AgentRuntime.subagents` возвращает `null` (D37)

#### Scenario: Малое окно — нет agent
- **WHEN** ядро собрано с `subagents.enabled: true`, а сессия создаётся с моделью, у которой `effectiveContextWindow` — 8 192 (или окно ограничено `compaction.context_window_cap: 8192`)
- **THEN** схемы сессии не содержат `agent`, сессия создаётся без ошибки, в логе — `subagent.unavailable` с `session_id`, `reason: context_window`, `window: 8192`, `min_window: 32768`; с моделью окна 32 768 `agent` в схемах есть (D40)

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
