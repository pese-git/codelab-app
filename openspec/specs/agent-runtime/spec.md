# agent-runtime Specification

## Purpose
Сборка и среда выполнения Dart-агента: `AgentRuntime` и `AgentSession` в памяти, профили хостов и их сужение по capability, минимальная сборка `buildAgentCore`, сквозной сценарий хода и требование детерминизма повторных прогонов. Через эту границу хосты получают готового агента, не собирая цикл, инструменты и политику вручную (`agent-core-architecture` §10).
## Requirements
### Requirement: Профили хостов и сужение
`HostProfile.of(name)` SHALL знать профили `agent-serve` и `embedded-cli` с явным состоянием каждой capability ядра по таблице §10.4 документа ядра (HOST-1):
- `shellExec`, `fileListing`, `interactiveApproval` — как в этапе 2;
- `sessionPersistence` — transport `jsonl-file` в обоих профилях;
- `compaction` — `on` в обоих профилях.

Для неизвестного имени `of` бросает `ArgumentError`. Состояния `off` и `transport` SHALL нести непустую причину.

Режим новой сессии по умолчанию в обоих профилях — `standard` (§10.5).

`narrowed(overrides)` SHALL принимать только сужение: `on` → `transport` → `off` и `transport(A)` → `transport(B)` при `B ⊆ A`. Расширение SHALL давать `HostWiringException` с именем capability (HOST-2).

#### Scenario: Расширение запрещено
- **WHEN** у профиля с `fileListing: off` вызывается `narrowed({fileListing: CapabilityOn()})`
- **THEN** вызов бросает `HostWiringException`, называющий `fileListing`

#### Scenario: Журнал в памяти для тестов
- **WHEN** профиль `agent-serve` сужается до `sessionPersistence: off` и собирается над `MemorySessionStore`
- **THEN** сборка не бросает исключения, а `CorePlan.offReasons` содержит причину для `sessionPersistence`

### Requirement: Минимальная сборка buildAgentCore
Хост SHALL собирать ядро только через `buildAgentCore(profile, services, config, streamFunction)` (HOST-6). Функция выполняет шаги §10.7 документа ядра в объёме этапов 2 и 3 (design.md change `add-agent-core-loop-and-tools`, D12; design.md этого change, D12):

1. **Сужение по сервисам и конфигурации:**
   - нет `gate` → `interactiveApproval` выключается;
   - env без `DirectoryListing` → `fileListing` выключается;
   - `CoreConfig.compaction.enabled == false` → `compaction` выключается с причиной «выключено конфигом»;
   - включённый `shellExec` над `MemoryExecutionEnv` → `HostWiringException`.
2. **Проверка сервисов** включённых capability (HOST-3): включённая `sessionPersistence` над `MemorySessionStore` → `HostWiringException`, называющий `sessionPersistence`; журнал в памяти — только при выключенной capability (тесты, хост без постоянного носителя).
3. **Env-цепочка** `BoundedEnv(baseEnv, root: cwd)` на сессию. Все инструменты получают один экземпляр внешнего `BoundedEnv` (ENV-2).
4. **Реестр инструментов:**
   - `read`, `write`, `edit`, `update_plan` — всегда;
   - `exec` — при `shellExec`;
   - `ls`, `search` — при `fileListing`;
   - дубликат имени → `HostWiringException` (HOST-5).
5. **Политика разрешений** — первым звеном `beforeToolCall`, хуки хоста `extraBeforeToolCall` — последними; `extraAfterToolCall` — первыми в `afterToolCall`.
6. **Промпт** из секций включённых capability.
7. **`AgentRuntime`** с хранилищем `services.sessions` и настройками `CoreConfig.compaction`.
8. **`CorePlan`** со списком инструментов, секций промпта и причин выключения, лог `host.plan`.

Выключенная capability НЕ SHALL оставлять на поверхности модели ни схемы, ни секции промпта (HOST-4).

#### Scenario: Матрица профиля
- **WHEN** ядро собирается для `agent-serve` на `MemoryExecutionEnv` и `MemorySessionStore` с `shellExec` и `sessionPersistence`, выключенными через `narrowed`
- **THEN** схемы запроса — `read`, `write`, `edit`, `update_plan`, `ls`, `search` в этом порядке, в промпте нет `tools/exec`, а `CorePlan.offReasons` содержит причины для `shellExec` и `sessionPersistence`

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

### Requirement: Сквозной сценарий и детерминизм
Сценарий `test/scenarios/read_edit_exec_test.dart` SHALL проверять вместе цикл, инструменты, разрешения и сборку:
- scripted LLM читает файл, правит его и запускает команду;
- работа идёт на `MemoryExecutionEnv` с фейковым `Shell`;
- `PermissionGate` отвечает `allowOnce`.

Проверяются последовательность `AgentEvent`, запросы к `PermissionGate` с приведёнными аргументами (`rawInput`, `locations`, diff правки) и итоговые файлы. На `FakeClock`, `SequentialIdGenerator` и `Random(42)` сценарий SHALL давать одну и ту же последовательность событий в каждом прогоне (PKG-6).

#### Scenario: Сто прогонов
- **WHEN** сценарий выполняется 100 раз подряд
- **THEN** все 100 последовательностей событий побайтово равны (`read_edit_exec_test.dart: same script yields identical event sequence on 100 runs`)

#### Scenario: Запросы одобрения
- **WHEN** сценарий выполняется в режиме `standard`
- **THEN** `read` исполняется без вопроса, а `edit` и `exec` проходят по одному запросу к `PermissionGate` с `rawInput` их вызовов; запрос `edit` содержит `locations` и diff

### Requirement: AgentRuntime и AgentSession
Публичный API ядра SHALL предоставлять `AgentRuntime` и `AgentSession` (§5.6 документа ядра; состав этапа 2 — design.md change `add-agent-core-loop-and-tools`, D4; добавления этапа 3 — design.md этого change, D4, D5).

`AgentRuntime`:
- `createSession(SessionSpec)` — сессия с `cwd`, режимом `ModeId`, моделью `ModelRef`, портами `SessionHostPorts` и хуками хоста; журнал создаётся в `SessionStore` и начинается записью `model_change`;
- `loadSession(id, ports, {model})` — открытие журнала, запись синтетических результатов прерванных вызовов, транскрипт из `buildLlmContext`, режим из последней `mode_change`, план из последней `plan`; модель — из аргумента или `CoreConfig.defaultModel`, другая модель журнала даёт лог `session.model.not_restored`;
- `listSessions({cwd, cursor, pageSize})` — страница `SessionPage` из `SessionStore.list`; неверный курсор → `InvalidCursor`;
- `dispose()` — отменяет идущие ходы, дожидается очередей записи и закрывает потоки событий.

`AgentSession`:
- `id`;
- `events` — широковещательный поток; поздний подписчик получает события текущего хода с начала;
- `prompt(content, {cancel})` — возвращает `TurnResult` с полями `TurnEnded`; ждёт завершения фонового сжатия предыдущего хода;
- `cancel()`;
- `setMode(ModeId)` — эмитит `ModeChanged`; новый режим действует со следующего вызова инструмента;
- `replay()` — события журнала активной ветки для `session/load`.

`prompt()` SHALL очищать grants разрешений на ход до начала хода (PERM-8). Повторный `prompt()` во время хода SHALL завершаться `StateError` (LOOP-10).

Сессия SHALL ставить `LlmContext.cacheKey` равным своему id (§2.12.1). Системный промпт SHALL собираться при создании и загрузке сессии и при смене режима (§11.5).

Сессия SHALL писать журнал через `SessionWriter`, первого подписчика `Agent` (agent-sessions «Запись журнала из событий»). После первого завершённого хода со словами пользователя она пишет автоматический заголовок. После `TurnEnded(completed | maxTokens)` она проверяет порог сжатия (agent-compaction «Точки срабатывания сжатия»).

#### Scenario: Ход через прямой API
- **WHEN** хост создаёт сессию на `MemoryExecutionEnv`, `MemorySessionStore` и `ScriptedStreamFunction` и вызывает `prompt([TextContent('hi')])`
- **THEN** `events` отдаёт `TurnStarted … TurnEnded(completed)`, `prompt` возвращает `TurnResult(reason: completed)`, а журнал содержит `model_change`, сообщение пользователя и ответ

#### Scenario: Поздний подписчик
- **WHEN** подписчик подключается к `events` после `StepStarted` идущего хода
- **THEN** он получает события этого хода с `TurnStarted`

#### Scenario: Смена режима посреди хода
- **WHEN** `setMode` вызывается во время исполнения первого из двух последовательных вызовов
- **THEN** эмитится `ModeChanged`, первый вызов не прерывается, а решение для второго принимается по новому режиму

#### Scenario: Загрузка продолжает сессию
- **WHEN** сессия с двумя ходами и режимом `plan` закрывается и открывается `loadSession` в новом `AgentRuntime` над тем же хранилищем
- **THEN** режим сессии `plan`, `replay()` отдаёт сообщения обоих ходов, а следующий `prompt` отправляет модели всю историю

#### Scenario: Модель журнала не восстанавливается
- **WHEN** журнал заканчивается `model_change` модели `a/x`, а `loadSession` вызывается без `model` при `defaultModel` `b/y`
- **THEN** сессия работает на `b/y`, пишет лог `session.model.not_restored` и запись `model_change` модели `b/y`

