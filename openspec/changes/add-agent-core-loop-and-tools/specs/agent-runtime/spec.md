## ADDED Requirements

### Requirement: AgentRuntime и AgentSession в памяти
Публичный API ядра SHALL предоставлять `AgentRuntime` и `AgentSession` (§5.6 документа ядра, состав этапа 2 — design.md, D4).

`AgentRuntime` этапа 2:
- `createSession(SessionSpec)` — сессия с `cwd`, режимом `ModeId`, моделью `ModelRef`, портами `SessionHostPorts` и хуками хоста;
- `listSessions()` — сессии этого процесса в порядке создания;
- `dispose()` — отменяет идущие ходы и закрывает потоки событий.

`AgentSession` этапа 2:
- `id`;
- `events` — широковещательный поток; поздний подписчик получает события текущего хода с начала;
- `prompt(content, {cancel})` — возвращает `TurnResult` с полями `TurnEnded`;
- `cancel()`;
- `setMode(ModeId)` — эмитит `ModeChanged`; новый режим действует со следующего вызова инструмента.

`prompt()` SHALL очищать grants разрешений на ход до начала хода (PERM-8). Повторный `prompt()` во время хода SHALL завершаться `StateError` (LOOP-10).

Сессия SHALL ставить `LlmContext.cacheKey` равным своему id (§2.12.1). Системный промпт SHALL собираться при создании сессии и при смене режима (§11.5).

#### Scenario: Ход через прямой API
- **WHEN** хост создаёт сессию на `MemoryExecutionEnv` и `ScriptedStreamFunction` и вызывает `prompt([TextContent('hi')])`
- **THEN** `events` отдаёт `TurnStarted … TurnEnded(completed)`, а `prompt` возвращает `TurnResult(reason: completed)`

#### Scenario: Поздний подписчик
- **WHEN** подписчик подключается к `events` после `StepStarted` идущего хода
- **THEN** он получает события этого хода с `TurnStarted`

#### Scenario: Смена режима посреди хода
- **WHEN** `setMode` вызывается во время исполнения первого из двух последовательных вызовов
- **THEN** эмитится `ModeChanged`, первый вызов не прерывается, а решение для второго принимается по новому режиму

### Requirement: Профили хостов и сужение
`HostProfile.of(name)` SHALL знать профили `agent-serve` и `embedded-cli` с явным состоянием каждой capability этапа 2 (`shellExec`, `fileListing`, `interactiveApproval`) по таблице §10.4 документа ядра (HOST-1). Для неизвестного имени `of` бросает `ArgumentError`. Состояния `off` и `transport` SHALL нести непустую причину.

Режим новой сессии по умолчанию в обоих профилях — `standard` (§10.5).

`narrowed(overrides)` SHALL принимать только сужение: `on` → `transport` → `off` и `transport(A)` → `transport(B)` при `B ⊆ A`. Расширение SHALL давать `HostWiringException` с именем capability (HOST-2).

#### Scenario: Расширение запрещено
- **WHEN** у профиля с `fileListing: off` вызывается `narrowed({fileListing: CapabilityOn()})`
- **THEN** вызов бросает `HostWiringException`, называющий `fileListing`

### Requirement: Минимальная сборка buildAgentCore
Хост SHALL собирать ядро только через `buildAgentCore(profile, services, config, streamFunction)` (HOST-6). Функция выполняет шаги §10.7 документа ядра в объёме этапа 2 (design.md, D12):

1. **Сужение по сервисам:**
   - нет `gate` → `interactiveApproval` выключается;
   - env без `DirectoryListing` → `fileListing` выключается;
   - включённый `shellExec` над `MemoryExecutionEnv` → `HostWiringException`.
2. **Проверка сервисов** включённых capability (HOST-3).
3. **Env-цепочка** `BoundedEnv(baseEnv, root: cwd)` на сессию. Все инструменты получают один экземпляр внешнего `BoundedEnv` (ENV-2).
4. **Реестр инструментов:**
   - `read`, `write`, `edit`, `update_plan` — всегда;
   - `exec` — при `shellExec`;
   - `ls`, `search` — при `fileListing`;
   - дубликат имени → `HostWiringException` (HOST-5).
5. **Политика разрешений** — первым звеном `beforeToolCall`, хуки хоста `extraBeforeToolCall` — последними; `extraAfterToolCall` — первыми в `afterToolCall`.
6. **Промпт** из секций включённых capability.
7. **`AgentRuntime`.**
8. **`CorePlan`** со списком инструментов, секций промпта и причин выключения, лог `host.plan`.

Выключенная capability НЕ SHALL оставлять на поверхности модели ни схемы, ни секции промпта (HOST-4).

#### Scenario: Матрица профиля
- **WHEN** ядро собирается для `agent-serve` на `MemoryExecutionEnv` с `shellExec` выключенным через `narrowed`
- **THEN** схемы запроса — `read`, `write`, `edit`, `update_plan`, `ls`, `search` в этом порядке, в промпте нет `tools/exec`, а `CorePlan.offReasons` содержит причину для `shellExec`

#### Scenario: Включено без сервиса
- **WHEN** профиль с включённым `shellExec` собирается над `MemoryExecutionEnv`
- **THEN** `buildAgentCore` бросает `HostWiringException`, называющий `shellExec`

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
