# agent-runtime Specification

## Purpose
Сборка и среда выполнения Dart-агента: `AgentRuntime` и `AgentSession` в памяти, профили хостов и их сужение по capability, минимальная сборка `buildAgentCore`, сквозной сценарий хода и требование детерминизма повторных прогонов. Через эту границу хосты получают готового агента, не собирая цикл, инструменты и политику вручную (`agent-core-architecture` §10).
## Requirements
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
Публичный API ядра SHALL предоставлять `AgentRuntime` и `AgentSession` (§5.6 документа ядра; состав этапа 2 — design.md change `add-agent-core-loop-and-tools`, D4; добавления этапа 3 — design.md change `add-agent-core-sessions-and-compaction`, D4, D5; добавления этапа 4 — design.md change `add-dart-agent-acp-server`, D3, D4).

`AgentRuntime`:
- `createSession(SessionSpec)` — сессия с `cwd`, режимом `ModeId`, моделью `ModelRef`, портами `SessionHostPorts` и хуками хоста; журнал создаётся в `SessionStore` и начинается записью `model_change`;
- `loadSession(id, ports, {model, cwd})` — открытие журнала, запись синтетических результатов прерванных вызовов, транскрипт из `buildLlmContext`, режим из последней `mode_change`, план из последней `plan`, усилие рассуждения из последней `config_change` с `optionId: "effort"`; модель — из аргумента, иначе последняя `model_change` ветки, найденная в каталоге, иначе `CoreConfig.defaultModel` с логом `session.model.not_restored`; хуки хоста — `ports.extraBeforeToolCall` и `ports.extraAfterToolCall` по тому же правилу сборки, что у `createSession`; `cwd`, отличный от заголовка, — рабочая папка сессии и запись `custom` `codelab.cwd_changed` (§13.5, шаг 2);
- `models` — каталог моделей сборки (`ModelCatalog`);
- `listSessions({cwd, cursor, pageSize})` — страница `SessionPage` из `SessionStore.list`; неверный курсор → `InvalidCursor`;
- `dispose()` — отменяет идущие ходы, дожидается очередей записи и закрывает потоки событий.

`AgentSession`:
- `id`;
- `events` — широковещательный поток; поздний подписчик получает события текущего хода с начала;
- `prompt(content, {cancel})` — возвращает `TurnResult` с полями `TurnEnded`; ждёт завершения фонового сжатия предыдущего хода;
- `cancel()`;
- `setMode(ModeId)` — эмитит `ModeChanged`; новый режим действует со следующего вызова инструмента;
- `model` и `effort` — текущая модель и усилие рассуждения;
- `setModel(ModelId)` — модель из каталога, запись `model_change`, действует со следующего шага; модели нет в каталоге → `ArgumentError`;
- `setEffort(ReasoningEffort)` — запись `config_change {optionId: "effort"}`, действует со следующего шага; модель без `supportsReasoning` хранит значение, но параметр рассуждения в запрос не уходит (§2.12.3);
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

#### Scenario: Модель журнала восстанавливается из каталога
- **WHEN** журнал заканчивается `model_change` модели `a/x`, модель `a/x` есть в каталоге, а `loadSession` вызывается без `model`
- **THEN** сессия работает на `a/x`, и новой записи `model_change` нет

#### Scenario: Модели журнала нет в каталоге
- **WHEN** журнал заканчивается `model_change` модели `a/x`, её нет в каталоге, а `loadSession` вызывается без `model` при `defaultModel` `b/y`
- **THEN** сессия работает на `b/y`, пишет лог `session.model.not_restored` и запись `model_change` модели `b/y`

#### Scenario: Смена модели и усилия
- **WHEN** сессия вызывает `setModel` с моделью каталога и `setEffort(high)`, затем `prompt`
- **THEN** журнал содержит `model_change` и `config_change {optionId: "effort", value: "high"}`, а запрос хода идёт новой моделью с усилием `high`, если она поддерживает рассуждение

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
- список проходит те же слияние и фильтр, что при `createSession`; в `McpSessionTools.replaceServers` уходит полный желаемый список (серверы конфига, затем клиента);
- серверы конфига не трогаются; совпавшие по `name` и параметрам (`sameConnection`) остаются; исчезнувшие закрываются, новые подключаются и занимают имена инструментов последними (коллизия отключает новый сервер); отключённый или не подключившийся сервер пробуется заново;
- без хода — набор меняется до завершения возвращённого `Future`; во время хода вызов возвращается сразу, набор применяется после `TurnEnded`, последний вызов за ход побеждает, следующий `prompt` дожидается применения;
- на закрытой сессии — `StateError`;
- сбой коннектора НЕ SHALL пробрасываться: прежний набор остаётся, лог `mcp.server.failed`;
- «последний вызов побеждает» SHALL обеспечиваться счётчиком поколений: результат устаревшей замены, завершившейся позже, НЕ SHALL перекрывать новую;
- `AgentSession.close()` SHALL отменять идущую замену токеном отмены уровня сессии.

#### Scenario: Закрытие во время замены
- **WHEN** `setMcpServers` подключает новый сервер, а сессия закрывается до конца подключения
- **THEN** подключение отменено, транспорт нового сервера закрыт, набор сессии не изменился после `close()`

#### Scenario: Замена во время хода
- **WHEN** во время хода `setMcpServers` вызывается дважды с разными наборами
- **THEN** оба вызова возвращаются сразу, инструменты хода не меняются, после `TurnEnded` применён набор второго вызова, следующий `prompt` видит его

#### Scenario: Сервер конфига не тронут
- **WHEN** у сессии сервер конфига `cfg` и сервер клиента `a`, и `setMcpServers` получает `[b]`
- **THEN** `cfg` не переподключался, `a` закрыт, `b` подключён

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

### Requirement: Конфигурация сессии вне корня запуска
Если `CoreConfig.projectRoot` задан и канонический `cwd` новой или загружаемой сессии ему не равен, `AgentRuntime` SHALL брать ключи сессии из `CoreConfig.withoutProject` — снимка без проектных слоёв 3–4 (design.md change `add-agent-configuration`, D9). Ключи сессии: модель по умолчанию, `effort`, режим и правила разрешений, бюджет хода, пороги сжатия, MCP-серверы конфигурации и `redact`. Перед сравнением (`CoreConfig.forSessionCwd`) `cwd` сессии SHALL канонизироваться — symlink раскрыт портом `PathResolver.realpath` базового окружения (`AgentCoreServices.baseEnv`); ядро само путь не раскрывает. `projectRoot` уже канонический: его канонизирует загрузчик. Иначе сессия с `cwd` через symlink на корень запуска получила бы снимок без проекта и потеряла бы запреты проекта (`permissions.deny`, ужесточённый режим). Если путь не раскрылся (нет каталога, окружение без `PathResolver`), сравнивается нормализованная запись пути. Сравнивается равенство канонических путей по компонентам, а не вложенность. Ключи сборки — каталог провайдеров, capability, сужение профиля — общие для процесса. На каждый такой `cwd` SHALL писаться один лог `config.session.outside_root {session_id, cwd, config_root}`. Без `projectRoot` или без `withoutProject` поведение прежнее: все сессии получают `CoreConfig`.

#### Scenario: Проектные серверы не попадают в чужой проект
- **WHEN** ядро собрано с `projectRoot: /A`, `CoreConfig.mcpServers` содержит сервер проекта `/A`, а `withoutProject.mcpServers` пуст, и клиент создаёт сессию с `cwd: /B`
- **THEN** сессия `/B` не подключает сервер проекта `/A`, лог `config.session.outside_root` с `cwd: /B`

#### Scenario: Подкаталог — другой корень
- **WHEN** доверенный проект `/A` задаёт `permissions.tools.exec: allow` в `config.local.yaml`, а сессия создана с `cwd: /A/sub`
- **THEN** правило `allow` к сессии не применяется, режим и правила — из снимка без проекта

#### Scenario: Сессия в корне запуска
- **WHEN** сессия создана с `cwd`, равным `projectRoot`
- **THEN** она получает модель, режим, правила и серверы полного снимка, лога `config.session.outside_root` нет

#### Scenario: cwd через symlink на корень запуска
- **WHEN** ядро собрано с `projectRoot: /A` (канонический путь), проект `/A` добавляет `permissions.deny: ["write:.env"]`, а клиент создаёт сессию с `cwd: /L`, где `/L` — symlink на `/A`
- **THEN** сессия получает полный снимок: запрет `write:.env` действует, лога `config.session.outside_root` нет

