# agent-runtime Specification

## Purpose
Сборка и среда выполнения Dart-агента: `AgentRuntime` и `AgentSession` в памяти, профили хостов и их сужение по capability, минимальная сборка `buildAgentCore`, сквозной сценарий хода и требование детерминизма повторных прогонов. Через эту границу хосты получают готового агента, не собирая цикл, инструменты и политику вручную (`agent-core-architecture` §10).
## Requirements
### Requirement: Профили хостов и сужение
`HostProfile.of(name)` SHALL знать профили `agent-serve`, `embedded-app-desktop` и `embedded-cli` с явным состоянием каждой capability ядра по таблице §10.4 документа ядра (HOST-1):
- `shellExec`, `fileListing`, `interactiveApproval` — как в этапе 2; в `embedded-app-desktop` — те же состояния, что в `embedded-cli`: `shellExec` и `fileListing` — transport `local`, `interactiveApproval` — transport `acp` (design.md change `add-embedded-agent-mode`, D4);
- `sessionPersistence` — transport `jsonl-file` во всех трёх профилях;
- `compaction` — `on` во всех трёх профилях;
- `mcp` — transport `{stdio, http}` во всех трёх профилях (design.md change `add-agent-mcp-client`, D3).

Для неизвестного имени `of` бросает `ArgumentError`. Состояния `off` и `transport` SHALL нести непустую причину.

Режим новой сессии по умолчанию во всех трёх профилях — `standard` (§10.5).

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

#### Scenario: Профиль встроенного агента приложения
- **WHEN** вызывается `HostProfile.of('embedded-app-desktop')`
- **THEN** состояния всех capability и режим по умолчанию совпадают с `embedded-cli`, а golden-матрица `test/host/profiles/embedded-app-desktop.golden.json` (схемы инструментов, секции промпта, slash-команды) совпадает с матрицей `embedded-cli`

#### Scenario: Паритет профилей
- **WHEN** один сценарий модели («прочитай файл, измени, покажи план») проходит через ядро в профилях `agent-serve`, `embedded-app-desktop` и `embedded-cli` с одинаковыми ответами на запросы разрешений
- **THEN** последовательности `AgentEvent` трёх прогонов совпадают; различаются только env и gate хоста (§10.12)

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
3. **Подключение.** Ядро SHALL передавать `services.mcp.connect` серверы конфига с шаблонами `${secret:<name>}` в значениях `env`/`headers` и функцию раскрытия `McpConnectRequest.expandSecrets` (`McpSecretExpander`) над `AgentCoreServices.secrets` (capability `agent-secrets`, «Секреты MCP-серверов конфигурации»; design.md change `add-agent-secret-store`, D4; design.md change `add-config-writer-and-reload`, D11). Коннектор SHALL вызывать её перед каждой попыткой подключения сервера с шаблонами, в том числе первой, и использовать раскрытую копию только в этой попытке. Секрет не найден, хранилище недоступно или у ядра нет резолвера → функция SHALL бросать `McpSecretsException(reason)`, транспорт сервера НЕ SHALL открываться, сервер SHALL оставаться в списке сессии в состоянии `failed` с `lastError` — `reason` и повторяться по расписанию задержек (capability `agent-mcp-client`, «Переподключение и состояние серверов сессии»); на первом сбое — `mcp.server.failed {server, transport, reason}`. Причина называет имя секрета и бэкенд (`secret <name> is not set`, `secret <name> cannot be read: <backend> is unavailable`, `no secret store`) и НЕ SHALL содержать значение секрета. Остальные серверы подключаются, сессия создаётся. `AgentRuntime.dispose()` или `AgentSession.close()` во время раскрытия SHALL отбрасывать попытку: транспорт не открывается, `mcp.server.failed` не пишется, сервер — `failed` с `lastError` `connection cancelled` без таймера повтора. Заголовки после раскрытия SHALL идти в порядке файла конфига. Серверы клиента не раскрываются: `${secret:…}` в них — литерал. `services.mcp.connect` подключает серверы параллельно, каждый в своём `connectTimeout`. Сбой сервера SHALL давать `mcp.server.failed` и сессию без его инструментов. Исключение `connect` целиком SHALL давать `mcp.server.failed` с причиной `MCP connector failed: <runtimeType>` и сессию без MCP-инструментов, а не ошибку `createSession` / `loadSession`.
4. **Регистрация.** После всех подключений, в порядке списка, внутри сервера — в порядке `tools/list`, в реестр сессии поверх копии базового реестра.
5. **Коллизия имени** MCP-инструмента со встроенным или с уже зарегистрированным SHALL отключать весь более поздний сервер (транспорт закрыт, инструменты не зарегистрированы, состояние `disabled` с `lastError` `tool name collision: <имя инструмента>`) с `mcp.server.failed`, причина которого называет оба источника. Сессия SHALL создаваться (HOST-5). Независимо от проверки коннектора ядро SHALL отклонять с `mcp.tool.invalid` инструмент коннектора без префикса `mcp__` или с именем встроенного инструмента (защита в глубину).
6. **Изоляция.** Инструменты одной сессии НЕ SHALL быть видны другим сессиям.
7. **Закрытие.** `AgentSession.close()` и `AgentRuntime.dispose()` SHALL закрывать транспорты серверов сессии после остановки хода. Если `createSession` / `loadSession` падает после подключения серверов, подключения SHALL закрываться до проброса ошибки: сессия, не возвращённая вызывающему, не оставляет живых процессов.
8. **Обновление набора.** Ожидающее обновление `McpSessionTools.takeUpdate()` ядро SHALL применять на границе шага через `prepareNextStep` полями `StepUpdate.tools` и `StepUpdate.systemPrompt` (транскрипт цикла не меняется), а между ходами — перед началом хода.
9. **Журнал.** Описания серверов НЕ SHALL записываться в журнал.

`AgentSession.setMcpServers(servers)` SHALL заменять серверы с `origin: session`:
- список проходит те же слияние и фильтр, что при `createSession`; в `McpSessionTools.replaceServers` уходит полный желаемый список (серверы конфига с шаблонами, затем клиента); сервер конфига с ненайденным секретом входит в него и становится `failed` по шагу 3;
- серверы конфига не трогаются; совпавшие по `name`, параметрам (`sameConnection`) и `enabled` остаются; исчезнувшие закрываются, новые подключаются и занимают имена инструментов последними (коллизия отключает новый сервер); отключённый коллизией или не подключившийся (`failed`) сервер пробуется заново, а выключенный `setEnabled(name, false)` остаётся выключенным;
- без хода — набор меняется до завершения возвращённого `Future`; во время хода вызов возвращается сразу, набор применяется после `TurnEnded`, последний вызов за ход побеждает, следующий `prompt` дожидается применения;
- на закрытой сессии — `StateError`;
- сбой коннектора НЕ SHALL пробрасываться: прежний набор остаётся, лог `mcp.server.failed`;
- «последний вызов побеждает» SHALL обеспечиваться счётчиком поколений: результат устаревшей замены, завершившейся позже, НЕ SHALL перекрывать новую;
- `AgentSession.close()` SHALL отменять идущую замену токеном отмены уровня сессии, в том числе ожидание секретов: транспорт не открывается, `mcp.server.failed` не пишется.

#### Scenario: Закрытие во время замены
- **WHEN** `setMcpServers` подключает новый сервер, а сессия закрывается до конца подключения
- **THEN** подключение отменено, транспорт нового сервера закрыт, набор сессии не изменился после `close()`

#### Scenario: Секрет сервера конфига не найден
- **WHEN** `CoreConfig.mcpServers` содержит http-сервер `gh` с `headers.Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"` и stdio-сервер `docs` без ссылок, секрета нет ни в хранилище, ни в `CODELAB_SECRET_CODELAB_MCP_GH_AUTHORIZATION`
- **THEN** `createSession` возвращает сессию, `docs` подключён, транспорт для `gh` не открывался, `servers` содержит `gh` в состоянии `failed` с `lastError` `secret codelab/mcp/gh/authorization is not set` и `retryIn`, лог `mcp.server.failed {server: gh, transport: http, reason: "secret codelab/mcp/gh/authorization is not set"}`; лог и журнал не содержат значений секретов

#### Scenario: Хранилище недоступно при загрузке сессии
- **WHEN** `loadSession` восстанавливает сессию, а хранилище бросает `SecretStoreUnavailableException(backend: "file", …)` для секрета сервера `gh`
- **THEN** сессия загружена без инструментов `gh`, `gh` в состоянии `failed`, лог `mcp.server.failed` с причиной `secret codelab/mcp/gh/authorization cannot be read: file is unavailable`

#### Scenario: Секрет задан после создания сессии
- **WHEN** сессия создана, когда секрета `codelab/mcp/gh/authorization` сервера `gh` не было, а затем секрет записан в хранилище
- **THEN** очередная попытка по расписанию раскрывает его заново, `gh` подключается без перезагрузки конфига и перезапуска; значение секрета в коннекторе между попытками не хранится

#### Scenario: Закрытие во время раскрытия секретов
- **WHEN** `read` хранилища для сервера конфига не завершается, а рантайм получает `dispose()` (или сессия — `close()` во время `setMcpServers`)
- **THEN** транспорт этого сервера не открывался, записи `mcp.server.failed` для него нет, таймера повтора нет, процессов серверов не осталось

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

### Requirement: Файлы проекта сессии
`createSession` и `loadSession` SHALL до возврата сессии вызывать `AgentCoreServices.projectFiles.load` (если порт задан) с каноническим `cwd` сессии, признаком `projectTrusted` и `tools.project_context.max_bytes` снимка конфигурации сессии (design.md change `add-agent-project-files`, D1, D4). `projectTrusted` SHALL быть истинным, только если канонический `cwd` равен одному из `CoreConfig.trustedProjects`; канонизация — тем же `PathResolver.realpath`, что выбирает снимок (D9 change `add-agent-configuration`). Если `cwd` не раскрылся (у базового env нет `PathResolver` или `realpath` вернул ошибку), `projectTrusted` SHALL быть ложным (fail-closed, D4): нераскрытый путь не сравнивается с доверенными корнями.

Результат SHALL проверяться ядром:
- `assembleProjectContext` → `PromptInputs.projectContext`;
- `parseCommandTemplates` → `AgentSession.commands`;
- `parseAgentDefinitions` с каталогом моделей сборки → `AgentSession.agents`.

Каждая диагностика SHALL писаться логгером сессии событием `project_files.diagnostic` (`session_id`, `path`, `line`, `column`, `code`, `message`; `warning` для уровней `error` и `warning`, `debug` для `info`), без содержимого файлов. Итоги — `project_context.loaded`, `commands.loaded`, `agents.loaded`.

Загрузка SHALL идти под токеном, дочерним от токена рантайма, и под таймаутом фазы (agent-project-context «Порт файлов проекта», D6): после `dispose()` рантайма результат выбрасывается и сессия не создаётся, по таймауту сессия создаётся без файлов проекта.

`AgentSession` SHALL получить члены `commands`, `agents`, `agent`, `setAgent(String)` (agent-slash-commands, agent-definitions).

#### Scenario: Доверие по cwd сессии
- **WHEN** глобальный конфиг доверяет `/work/b`, хост запущен в `/work/a`, а сессия создаётся с `cwd: /work/b`, где есть `.codelab/prompts/review.md`
- **THEN** фейковый порт получает `projectTrusted: true`, у сессии есть команда `review`

#### Scenario: Symlink на доверенный корень
- **WHEN** `/work/link` — symlink на доверенный `/work/b`, а сессия создаётся с `cwd: /work/link`
- **THEN** порт получает канонический `cwd: /work/b` и `projectTrusted: true`

#### Scenario: cwd не раскрылся
- **WHEN** глобальный конфиг доверяет `/work/b`, а `realpath` базового env для `cwd: /work/b` возвращает ошибку
- **THEN** фейковый порт получает `projectTrusted: false`

#### Scenario: Диагностика без содержимого
- **WHEN** порт возвращает определение агента с ошибкой frontmatter, а тело файла содержит строку `sk-test-secret`
- **THEN** лог содержит `project_files.diagnostic` с путём и кодом и не содержит `sk-test-secret`

### Requirement: Очередь смен конфигурации сессии
`AgentSession.setMode`, `setModel`, `setEffort` и `setAgent` SHALL исполняться строго по одной в порядке вызова (очередь сессии; design.md change `add-agent-project-files`, D11). Новое значение (база агента, пол режима, итоговые режим и модель) SHALL вычисляться под очередью — от состояния после предыдущей смены, а не в момент вызова. Записи журнала и события `ModeChanged` SHALL идти в порядке очереди; итоговое состояние сессии SHALL быть результатом последнего вызова. Ошибка одного вызова (`ArgumentError`) НЕ SHALL останавливать очередь. Правило применения смены к идущему ходу у каждого метода прежнее: `setMode` — со следующего вызова инструмента, `setModel`, `setEffort` и `setAgent` (включая режим агента) — со следующего шага.

#### Scenario: Параллельные setAgent и setMode
- **WHEN** режим конфигурации `standard`, определение `reviewer` задаёт `mode: plan`, а хост без ожидания вызывает `setAgent('reviewer')` и сразу `setMode(bypass)`
- **THEN** события `ModeChanged` идут в порядке `plan`, `bypass`; журнал содержит `config_change {optionId: "agent", value: "reviewer"}` и `mode_change plan` раньше `mode_change bypass`; итог — `agent == "reviewer"`, режим `bypass`

#### Scenario: Ошибка не ломает очередь
- **WHEN** без ожидания вызываются `setAgent('missing')` и `setMode(plan)`
- **THEN** первый завершается `ArgumentError`, второй исполняется, режим `plan`

### Requirement: Живая перезагрузка конфигурации
`AgentCoreServices` SHALL принимать необязательный порт `ConfigSource {ConfigLoadResult initial; Future<ConfigLoadResult> load({bool rebase = true}); Stream<void> changes}` (design.md, D7, D8). `initial` — результат стартовой загрузки, с которым хост собрал ядро; `load()` SHALL оценивать доверие проектам по `initial.config.trustedProjects` до перезапуска (через `CoreConfig.fromLayers(..., pinnedTrustedProjects:)`). Если порт передан, `buildAgentCore` SHALL требовать параметр `modelsFor` — функцию хоста, которая строит функцию модели и каталог по `CoreConfig`; без него — `HostWiringException`. Без порта перезагрузки нет, команда `/config` не объявляется.

`buildAgentCore` SHALL сохранять обязательный `streamFunction` — функцию модели начального снимка; начальный каталог — `AgentCoreServices.models`. `modelsFor` при сборке НЕ SHALL вызываться: его вызывает только перезагрузка на каждом применённом снимке. Без `ConfigSource` `modelsFor` не требуется.

`ConfigLoadResult` SHALL нести плоскую карту листьев итогового дерева `values` (пути как у `SettingsRegistry`; элемент `mcp.servers` — целиком под `mcp.servers[<name>]`); по ней перезагрузка строит список изменённых ключей. Рантайм SHALL хранить `values` и `HostSettings` применённого снимка.

`AgentRuntime` SHALL предоставлять:
- `reloadConfig()` → `ConfigApplyReport {outcome: applied | unchanged | failed, issues, changedKeys, restartRequiredKeys}`. `changedKeys` — применённые листья; `restartRequiredKeys` — ключи показа (лист, `mcp.servers[<name>]`, `providers.<id>`); оба SHALL быть отсортированы. `reloadConfig()` НЕ SHALL бросать при проблемах конфига и исключениях загрузки или сборки модели;
- `checkConfig()` → `ConfigLoadResult` загрузки без применения — по закреплённому доверию из `initial`; состояние рантайма НЕ SHALL меняться. Валидную загрузку `checkConfig()` SHALL прогонять тем же планом, что перезагрузка, и `CoreConfig.withDeferred(...)` с `validateSnapshot()`: ошибка повторной проверки — проблема результата, как у `reloadConfig()`. Загрузка проверки НЕ SHALL сдвигать базу сравнения наблюдателя: `ConfigSource.load(rebase: false)`, `rebase()` — только на пути перезагрузки (design.md, D7, D8). Новое значение `trusted_projects` и другие отложенные ключи SHALL приходить предупреждениями результата с `event: 'config.reload.restart_required'` и ключом показа в `key`; по ним команда `/config check` печатает строку `Restart required`. Исключение загрузки уходит вызывающему;
- `configStatus()` → `{loadedAt, sources, lastFailureAt, lastIssues, pendingRestartKeys}`; работает и без `ConfigSource`.

Без `ConfigSource` `reloadConfig()` и `checkConfig()` SHALL бросать `StateError`.

Сигнал `ConfigSource.changes` SHALL запускать `reloadConfig()`. Подписка принадлежит рантайму и SHALL отменяться в `dispose()`.

**Порядок `reloadConfig()`:**
1. **Коалесценция.** Если перезагрузка уже идёт, вызов SHALL ставить не больше одного повтора и получать его итог.
2. **Загрузка.** Вызывается `ConfigSource.load()`. После `dispose()` результат SHALL отбрасываться с итогом `unchanged`: снимок и `configStatus` не меняются, уведомлений и замен MCP нет.
3. **Невалидный конфиг.** Прежний снимок SHALL оставаться целиком (CFG-15). Клиентам НЕ SHALL уходить ни одно уведомление. `configStatus` получает `lastFailureAt` и `lastIssues`, лог — `config.reload.failed` с источниками, строками и путями ключей, без значений. Итог — `failed`. Исключение `load()` или `modelsFor` SHALL давать тот же итог `failed` (снимок прежний, `lastFailureAt` и `lastIssues` обновлены) и лог `config.reload.failed {error_class}`; текст исключения НЕ SHALL попадать ни в лог, ни в `lastIssues`.
4. **Ключи перезапуска.** Ключи diff — листья итогового дерева; список сравнивается целиком и даёт один ключ, по элементам развёрнут только `mcp.servers[<name>]`. Отложенными SHALL быть:
   - ключи с `restartRequired` в реестре настроек: `sessions.*`, `logging.*`, `profile.*`, `secrets.backend`, `config.*`;
   - ключ diff, для которого реестр настроек не нашёл дескриптора (fail closed);
   - ключи, ослабляющие права (R0-1): `permissions.*`, `trusted_projects`; элемент `mcp.servers[<name>]` с `type: stdio`, для которого в применённом снимке нет элемента `old` с `old.sameConnection(new) && (old.enabled || !new.enabled)` (новый, в том числе сразу с `enabled: false`; включённый из `enabled: false`; сменивший тип `http` → `stdio`; с другими `command`, `args` или `env`, в том числе шаблонами `${secret:…}`). Правило SHALL действовать и для выключенного сервера (R6-1): правка параметров соединения сервера с `enabled: false` откладывается так же, как у включённого. Если правка одновременно выключает сервер и меняет параметры соединения, выключение SHALL применяться сразу, а в применённом снимке SHALL оставаться прежний элемент с `enabled: false`;
   - правки, способные направить секрет на другой адрес (R0-4). «Ссылка на секрет» определяется по значению: любая подстановка `${…}` — `${secret:…}` или `${VAR}`. Отложены: элемент `mcp.servers[<name>]` с `type: http` без прежнего `old` с `old.sameConnection(new) && (old.enabled || !new.enabled)`, если в `url`, `headers` или `env` есть подстановка, **находка `findInlineSecrets`** (литерал по шаблону, ключ `inlineSecretKeys`) **или литерал в заголовке с секретным именем по `isSecretLikeName`** (как у провайдера; design.md change `add-config-literal-secrets-and-migrate`, D12), — в том числе выключенный (R6-1); провайдер `providers.<id>` с ключом (в прежнем или новом снимке есть `api_key_secret`, `api_key_env`, литеральный `api_key` или `api_key` со ссылкой `${…}` (R8-8), подстановка в `base_url`, `headers` или `auth_header`, литеральный секретный заголовок или любая находка `findInlineSecrets` в элементе провайдера; D12), если он новый или изменилось поле группы `kind`, `base_url`, `headers`, `auth_header`, `api_key_secret`, `api_key_env`, `api_key` — группа атомарна: её поля прежние, модели новые; каждая ссылка на модели нового отложенного провайдера (`agent.default_model`; с потребителем — `agent.fallback`, `agent.summary_model`, `llm.roles.*`, модели субагентов).

   План SHALL строиться по обоим снимкам — полному и `withoutProject` (сессии вне корня запуска получают второй): ключ отложен, если он отложен по сравнению любого из них. Ключ, который в полном снимке перекрыт проектным слоем, а в `withoutProject` изменился, SHALL откладываться так же. Набор отложенного SHALL передаваться в `CoreConfig.withDeferred` структурированно (признак `permissions`, имена серверов и провайдеров, ссылки на модели), а не строками ключей показа с повторным разбором: имя сервера может содержать `]`.

   Отложенные ключи SHALL браться из применённого снимка (design.md, D8, «Пересборка снимка с отложенными ключами»): доверие закрепляет ядро — `CoreConfig.fromLayers(..., pinnedTrustedProjects:)` получает список из `initial` и строит по нему и проектные слои, и `CoreConfig.trustedProjects` (с `withoutProject`), по которому новая сессия читает `prompts` и `agents`; остальное подставляет `CoreConfig.withDeferred` (`permissions`, элементы серверов, группа полей провайдера с прежними `key` и `headerTemplates`), а прежние `HostSettings` и `values` — рантайм; затем снимок проверяется семантически заново. Отложенная ссылка на модель нового провайдера НЕ SHALL давать итог `failed`. Ключи SHALL попадать в `restartRequiredKeys` и `pendingRestartKeys`; лог — `config.reload.restart_required {keys}`. `pendingRestartKeys` SHALL равняться `restartRequiredKeys` последней успешной перезагрузки: это ключи, которые в файлах ещё отличаются от применённого снимка. Ключ, отложенный раньше и не возвращённый в файле, SHALL оставаться в наборе (применённый снимок хранит его прежнее значение, поэтому он снова отличается); ключ, возвращённый в файле к применённому значению, SHALL уходить из набора. Итог `failed` набор не меняет. Удаление и выключение (`enabled: true → false`) серверов, удаление провайдеров, модели, провайдеры без ключа и HTTP-серверы без подстановок (включённые и выключенные) SHALL применяться без перезапуска.
5. **Сброс.** `AgentCoreServices.secrets?.invalidate()` и `modelsFor(next)` SHALL выполняться при каждой успешной загрузке, даже без изменённых ключей.
6. **Замена.** Полный снимок, снимок без проекта, функция модели и каталог SHALL заменяться одной атомарной операцией. Шаг, ход или проверка разрешения читают их один раз и НЕ SHALL видеть смесь двух снимков.
7. **Итог.** `unchanged` и `config.reload.noop` — только если ни один ключ не изменился (пустой diff); иначе — `applied` и `config.reload.applied {keys, restart_required}`, в том числе когда все изменённые ключи отложены.

**Когда действует новое значение** (CFG-16):
- `providers.*` и модели — со следующего шага любой сессии. Сессия, чья текущая модель исчезла из каталога, SHALL продолжать работать на функции модели прежнего снимка до смены модели; рантайм пишет `config.reload.model_orphaned {session_id, model}` один раз на сессию и модель;
- `budget.*`, `compaction.*` — со следующего хода: сессия берёт их из применённого снимка на границе хода, идущий ход доигрывает с прежними;
- `agent.default_model`, `agent.effort`, `tools.project_context.*` и файлы проекта — для новых сессий;
- ключи без потребителя (`tools.disabled`, `exec.*`, `redact.*` и другие узлы `applied: false`) перезагрузкой не применяются (`config.key.not_applied`);
- `mcp.servers` — требование «Серверы конфигурации при перезагрузке»;
- `permissions.*`, `trusted_projects`, новые или изменённые stdio-серверы (в том числе выключенные, R6-1) и правки R0-4 — только после перезапуска (шаг 4).

Идущий вызов инструмента и идущий запрос разрешения SHALL доигрывать со старыми значениями.

Если каталог моделей изменил список моделей, каждая живая сессия SHALL получить событие `ModelOptionsChanged`. Живая сессия — возвращённая вызывающему до замены и не закрытая. Событие SHALL публиковаться в момент замены, вне очереди агента (в том числе во время хода), НЕ SHALL записываться в журнал сессии и НЕ SHALL буферизоваться в истории хода: подписчик, подключившийся к ходу позже, его не получает (design.md, D8, шаг 7b). Сессия, создание или загрузка которой началось до замены, SHALL получить снимок начала целиком.

Ошибка перезагрузки, запущенной сигналом или вызовом, НЕ SHALL теряться и НЕ SHALL уходить в зону хоста: она пишется `config.reload.failed` с `error_class`.

#### Scenario: Права не меняются на лету
- **WHEN** сессия идёт в режиме `standard`, и перезагрузка меняет `permissions.tools.exec` на `allow`, `permissions.mode` на `bypass` и добавляет проект в `trusted_projects`
- **THEN** следующий `exec` спрашивается как прежде; `restartRequiredKeys` и `pendingRestartKeys` содержат `permissions.tools.exec`, `permissions.mode` и `trusted_projects`; лог `config.reload.restart_required` (`config_reload_test.dart`)

#### Scenario: Проект добавлен в trusted_projects
- **WHEN** проект `/w/p` не доверен при старте, его `.codelab/config.yaml` задаёт провайдера `pp` и HTTP-сервер `ph`, и перезагрузка добавляет `/w/p` в `trusted_projects`
- **THEN** в снимке нет ни `pp`, ни `ph`, `CoreConfig.trustedProjects` прежний, новая сессия в `/w/p` не читает `.codelab/prompts` и `.codelab/agents` проекта; `pendingRestartKeys` содержит `trusted_projects`, ответ `/config reload` — со строкой `Restart required: trusted_projects`

#### Scenario: Доверие снято
- **WHEN** проект `/w/p` доверен при старте, его конфиг задаёт `permissions.tools.exec: allow` и HTTP-сервер `ph`, и перезагрузка удаляет `/w/p` из `trusted_projects`
- **THEN** проектные слои по-прежнему оцениваются как доверенные до перезапуска, `pendingRestartKeys` содержит `trusted_projects`

#### Scenario: Секрет на новый адрес
- **WHEN** у провайдера `p` есть `api_key_secret`, и перезагрузка меняет его `base_url` и добавляет модель `p/m2`; одновременно добавляется HTTP-сервер `h` с заголовком `Authorization: "Bearer ${secret:codelab/mcp/h/authorization}"` и HTTP-сервер `h2` без ссылок
- **THEN** модель `p/m2` в каталоге, запросы идут на прежний `base_url`, `h` не подключается, `h2` подключается; `pendingRestartKeys` содержит `providers.p` и `mcp.servers[h]`

#### Scenario: Подстановка по значению
- **WHEN** перезагрузка добавляет HTTP-сервер `a` с заголовком `X-Gw: ${secret:gw}`, HTTP-сервер `b` с `Authorization: Bearer ${GITHUB_TOKEN}` и меняет `base_url` провайдера `q`, у которого `auth_header: "Bearer ${Q_KEY}"`
- **THEN** `a`, `b` и адрес `q` отложены, `pendingRestartKeys` содержит `mcp.servers[a]`, `mcp.servers[b]`, `providers.q`

#### Scenario: Подстановка в base_url
- **WHEN** у провайдера `g` нет `api_key_*` и секретных заголовков, но `base_url: "https://${GW_HOST}/v1"`, и перезагрузка меняет его `headers`
- **THEN** правка отложена, `pendingRestartKeys` содержит `providers.g`

#### Scenario: Новый провайдер с ключом и ссылки на его модели
- **WHEN** перезагрузка добавляет провайдера `n` с `api_key_secret` и модель `n/m`, меняет `agent.default_model` на `n/m` и `budget.max_steps`
- **THEN** итог `applied`, не `failed`; `budget.max_steps` применён; `n` и `agent.default_model` прежние, `pendingRestartKeys` содержит `providers.n` и `agent.default_model`

#### Scenario: Атомарность группы полей провайдера
- **WHEN** у провайдера `p` с ключом одна перезагрузка меняет `base_url` и добавляет модель, а следующая меняет только `headers`
- **THEN** после первой модели новые, а адрес, заголовки и ключ прежние; после второй провайдер целиком прежний; оба раза `pendingRestartKeys` содержит `providers.p`

#### Scenario: Включение stdio-сервера из enabled: false
- **WHEN** stdio-сервер `d` был `enabled: false`, и перезагрузка ставит `enabled: true` без других изменений
- **THEN** `d` не запускается, `pendingRestartKeys` содержит `mcp.servers[d]`

#### Scenario: Правка выключенного stdio-сервера
- **WHEN** stdio-сервер `d` с `enabled: false` есть в применённом снимке, перезагрузка меняет у него `command` (сервер остаётся выключенным), затем человек вызывает `/mcp enable d`
- **THEN** `pendingRestartKeys` содержит `mcp.servers[d]`; `setEnabled("d", true)` запускает процесс с прежней `command` применённого снимка, новая `command` не запускается до перезапуска (R6-1)

#### Scenario: Новый выключенный stdio-сервер
- **WHEN** перезагрузка добавляет stdio-сервер `n` с `enabled: false`
- **THEN** `n` не попадает в применённый снимок, `/mcp list` его не показывает, `/mcp enable n` отвечает `Unknown MCP server: n. Run /mcp list.`, `pendingRestartKeys` содержит `mcp.servers[n]`

#### Scenario: Выключение применяется сразу
- **WHEN** включённый stdio-сервер `s` и HTTP-сервер `h` с заголовком `X-Gw: ${secret:gw}` подключены, и перезагрузка ставит обоим `enabled: false`, а у `s` вдобавок меняет `args`
- **THEN** без хода оба закрыты до итога `reloadConfig` и находятся в `disabled`; `mcp.servers[s]` в `pendingRestartKeys`, а в применённом снимке `s` — с прежними `args` и `enabled: false`; `mcp.servers[h]` в `pendingRestartKeys` нет

#### Scenario: Смена типа на stdio
- **WHEN** HTTP-сервер `s` конфига меняется на `type: stdio`, а у stdio-сервера `t` в `env` меняется ссылка `${secret:a}` на `${secret:b}`
- **THEN** оба остаются в прежнем виде, `pendingRestartKeys` содержит `mcp.servers[s]` и `mcp.servers[t]`

#### Scenario: Новый stdio-сервер ждёт перезапуска
- **WHEN** перезагрузка добавляет stdio-сервер `x` и HTTP-сервер `h` и удаляет сервер `old`
- **THEN** `h` подключается, `old` закрывается, `x` не запускается, а `pendingRestartKeys` содержит `mcp.servers[x]`

#### Scenario: modelsFor не вызывается при сборке
- **WHEN** ядро собрано с `ConfigSource`, `streamFunction` и `modelsFor`, затем идёт ход, затем перезагрузка с итогом `unchanged`, затем ещё ход
- **THEN** `modelsFor` вызван ровно один раз — перезагрузкой; первый ход шёл на `streamFunction`, второй — на функции из `modelsFor`

#### Scenario: Модель по умолчанию — только новым сессиям
- **WHEN** перезагрузка меняет `agent.default_model` с `a/m1` на `a/m2`
- **THEN** модель идущей сессии остаётся `a/m1`, новая сессия получает `a/m2`

#### Scenario: Невалидная правка
- **WHEN** после ручной правки файл содержит `budget.max_steps: 0`, и срабатывает `changes`
- **THEN** итог `failed`, снимок прежний, ни одно событие сессий не опубликовано, `configStatus().lastIssues` содержит `budget.max_steps`, лог `config.reload.failed` не содержит значений

#### Scenario: Ключ вне реестра ждёт перезапуска
- **WHEN** фейковый `ConfigSource` отдаёт `values` с ключом, для которого `SettingsRegistry.lookup` не находит дескриптора, и перезагрузка меняет его значение
- **THEN** ключ попадает в `restartRequiredKeys` и `pendingRestartKeys`, а в `values` применённого снимка остаётся его прежнее значение

#### Scenario: Ключ перезапуска
- **WHEN** перезагрузка меняет `logging.file` и `budget.max_steps`
- **THEN** `budget.max_steps` применён, `logging.file` — прежний, `restartRequiredKeys` и `pendingRestartKeys` содержат `logging.file`

#### Scenario: Смена списка моделей
- **WHEN** перезагрузка добавляет модель `a/m3` в каталог
- **THEN** каждая живая сессия получает одно `ModelOptionsChanged`, следующий шаг использует новую функцию модели

#### Scenario: Отложенные ключи накапливаются по построению
- **WHEN** одна перезагрузка меняет `sessions.fsync`, следующая — `logging.file`, а третья возвращает `logging.file` к значению при старте
- **THEN** после второй `pendingRestartKeys` — `logging.file`, `sessions.fsync`; после третьей — только `sessions.fsync`

#### Scenario: Изменены только отложенные ключи
- **WHEN** перезагрузка меняет только `logging.file`
- **THEN** итог `applied`, `changedKeys` пуст, `restartRequiredKeys` — `logging.file`, лог `config.reload.applied`, а не `config.reload.noop`

#### Scenario: Исключение загрузки
- **WHEN** `ConfigSource.load()` бросает исключение, в тексте которого есть значение
- **THEN** `reloadConfig()` возвращает `failed`, снимок прежний, лог `config.reload.failed` с `error_class` не содержит текста исключения, ошибок в зоне хоста нет

#### Scenario: Проверка без применения
- **WHEN** в файле добавлен проект в `trusted_projects` и изменён `budget.max_steps`, и вызывается `checkConfig()`
- **THEN** результат без `issues`, его предупреждения содержат `config.reload.restart_required` с ключом `trusted_projects`; бюджет и `pendingRestartKeys` рантайма не изменились

#### Scenario: Проверка ловит ошибку повторной проверки снимка
- **WHEN** фейковый `ConfigSource` отдаёт валидную загрузку, на которой `validateSnapshot()` после `withDeferred` находит проблему, и вызывается `checkConfig()`
- **THEN** результат содержит эту проблему, как `reloadConfig()` на той же загрузке дал бы `failed`; состояние рантайма не изменилось; `load` вызван с `rebase: false`

#### Scenario: Проектный слой перекрывает ключ
- **WHEN** доверенный проект корня запуска задаёт `permissions.tools.exec: ask`, а перезагрузка меняет в глобальном конфиге `permissions.tools.exec` на `allow` и добавляет глобальный stdio-сервер `x`, который проект перекрывает своим `x`
- **THEN** полный снимок не изменился, но `withoutProject` изменился: `permissions.tools.exec` и `mcp.servers[x]` отложены, в `pendingRestartKeys`; сессия вне корня запуска по-прежнему спрашивает `exec`, глобальный `x` для неё не запускается (`config_reload_test.dart`)

#### Scenario: Имя сервера с ]
- **WHEN** в конфиге вручную задан stdio-сервер с именем `a]b`, и перезагрузка меняет его `command`
- **THEN** сервер `a]b` остаётся прежним в обоих снимках, `pendingRestartKeys` содержит `mcp.servers[a]b]`; набор отложенного дошёл до `withDeferred` по имени, без разбора строки ключа

#### Scenario: ModelOptionsChanged не проигрывается новому подписчику
- **WHEN** во время хода перезагрузка меняет список моделей, а затем к истории того же хода подключается новый подписчик
- **THEN** первый подписчик получил одно `ModelOptionsChanged`, новый — ни одного

#### Scenario: Коалесценция
- **WHEN** во время идущей перезагрузки приходят три сигнала `changes`
- **THEN** `load()` вызывается ещё ровно один раз, и все вызовы получают итог этой загрузки

#### Scenario: dispose во время загрузки
- **WHEN** `load()` ещё не завершился, а рантайм получает `dispose()`
- **THEN** снимок не заменён, событий сессиям и замен MCP нет, исключений в зоне хоста нет

#### Scenario: Замена ключа в хранилище секретов
- **WHEN** ключ провайдера прочитан и закэширован, затем в `secrets.yaml` записано новое значение, и перезагрузка завершается итогом `unchanged`
- **THEN** следующий запрос к провайдеру несёт новое значение ключа

#### Scenario: Хост без источника
- **WHEN** ядро собрано без `ConfigSource` (сценарий `--llm-script`)
- **THEN** подписки нет, `/config` не объявлена, поведение прежнее; `reloadConfig()` и `checkConfig()` бросают `StateError`, `configStatus()` отвечает

#### Scenario: Литеральный заголовок и новый адрес
- **WHEN** HTTP-сервер `gh` с литеральным `Authorization: "Bearer ghp_<36 символов>"` в пользовательском слое меняет `url`
- **THEN** `restartRequiredKeys` содержит `mcp.servers[gh]`, сервер работает с прежним адресом, токен на новый адрес не уходит

#### Scenario: Литеральный ключ провайдера и новый base_url
- **WHEN** провайдер `lm` с литеральным `api_key` меняет `base_url` и `api_key`
- **THEN** группа провайдера отложена целиком: `restartRequiredKeys` содержит `providers.lm`, запросы идут на прежний адрес с прежним ключом

#### Scenario: Новый сервер с литералом
- **WHEN** перезагрузка добавляет HTTP-сервер с литеральным `X-Api-Key` по шаблону
- **THEN** сервер ждёт перезапуска (`restartRequiredKeys` содержит `mcp.servers[<name>]`)

#### Scenario: Литерал в секретно названном заголовке сервера
- **WHEN** HTTP-сервер `docs` с литеральным заголовком `X-Api-Key: k-1` (не совпадает с шаблоном, имя секретное) меняет `url`
- **THEN** `restartRequiredKeys` содержит `mcp.servers[docs]`, сервер работает с прежним адресом

### Requirement: Серверы конфигурации при перезагрузке
Применённый снимок с изменённым `mcp.servers` SHALL передаваться каждой живой сессии существующей заменой `McpSessionTools.replaceServers` с полным желаемым списком: серверы нового конфига, затем текущие серверы `session/new` (design.md, D10).
- Сервер клиента с тем же `name` SHALL затенять сервер конфига, как при создании.
- Серверы `session/new` НЕ SHALL переподключаться и закрываться перезагрузкой (CFG-17).
- Неизменённые серверы (`sameConnection`) НЕ SHALL переподключаться. Неизменённый сервер в состоянии `failed` SHALL пробоваться сразу.
- Без хода замена SHALL завершаться до итога `reloadConfig`. Во время хода модели замена SHALL применяться после `TurnEnded`.
- Замены от перезагрузки и от `setMcpServers` SHALL идти через одну очередь сессии со счётчиком поколений: последний желаемый набор побеждает, а результат устаревшей замены НЕ SHALL перекрывать новую.
- Шаблоны `${secret:…}` серверов конфига SHALL раскрываться заново, по правилам требования «MCP-серверы сессии».
- Новые и изменённые stdio-серверы и HTTP-серверы со ссылками на секреты (R0-1, R0-4), в том числе выключенные (R6-1), в желаемый список НЕ SHALL попадать до перезапуска (требование «Живая перезагрузка конфигурации», шаг 4): вместо них идёт элемент применённого снимка, если он был.
- Серверы с `enabled: false` SHALL передаваться коннектору с признаком `enabled: false` (`McpServerConfig.enabled`): коннектор держит их в состоянии `disabled` без подключения; лог загрузки `mcp.server.skipped {server, reason: disabled in config}` сохраняется. Проблемы построения выключенного сервера НЕ SHALL делать конфиг невалидным; элемент без `type` либо без `command`/`url` SHALL выпадать из списка с тем же `mcp.server.skipped`. `ConfigLoadResult.values` SHALL содержать лист `mcp.servers[<name>]` и выключенных серверов списка. `McpServerConfig.sameConnection` НЕ SHALL учитывать `enabled`: сервер остаётся прежним, только если совпали и параметры соединения, и `enabled`.
- `setEnabled(name, true)` (`/mcp enable`) SHALL подключать сервер с параметрами применённого снимка (R6-1).
- **Ручной выбор** `setEnabled` (`/mcp enable|disable`) SHALL сохраняться при перезагрузке, пока элемент этого сервера в применённом снимке не изменился — параметры соединения (`sameConnection`), `enabled` и сроки `connect_timeout`/`call_timeout` прежние (R6-2). Правка сроков у сервера с ручным выбором SHALL сбрасывать выбор и пересоздавать соединение (у stdio — перезапуск процесса); у сервера без ручного выбора правка одних сроков НЕ SHALL переподключать его. Правки других ключей и серверов выбор НЕ SHALL сбрасывать; сервер, выключенный `/mcp disable`, при этом НЕ SHALL будиться вместе с `failed`. Применённая правка самого сервера, в том числе `enabled`, SHALL давать новое состояние из конфига. Отложенная правка (R0-1, R0-4, R6-1) применённый элемент не меняет и выбор НЕ SHALL сбрасывать.

#### Scenario: Изменён адрес одного сервера
- **WHEN** у сессии серверы конфига `a` и `b`, и перезагрузка меняет `url` у `b`
- **THEN** переподключён только `b`, процесс или соединение `a` не трогались (`mcp_apply_config_test.dart`)

#### Scenario: Удаление во время хода
- **WHEN** во время хода перезагрузка удаляет сервер `b`, а модель вызывает `mcp__b__t`
- **THEN** вызов завершается по прежнему набору, после `TurnEnded` сервер `b` закрыт, следующий запрос к модели не содержит `mcp__b__t`

#### Scenario: Сервер клиента не тронут
- **WHEN** у сессии сервер `session/new` `github` и сервер конфига `github`, и перезагрузка меняет конфиговый `github`
- **THEN** сервер клиента не переподключался, сервер конфига по-прежнему затенён

#### Scenario: Последний побеждает
- **WHEN** во время хода две перезагрузки подряд дают наборы HTTP-серверов `{a}` и `{a, c}`
- **THEN** после `TurnEnded` применён `{a, c}`

#### Scenario: Ручной выбор переживает правку других ключей
- **WHEN** человек выключил HTTP-сервер `a` командой `/mcp disable a` и включил выключенный конфигом сервер `b` командой `/mcp enable b`, а перезагрузка меняет `budget.max_steps` и `url` другого HTTP-сервера `c`
- **THEN** `a` остаётся `disabled` с `lastError` `disabled by /mcp disable` и не подключался, `b` остаётся `connected` без переподключения, переподключён только `c` (R6-2)

#### Scenario: Правка самого сервера сбрасывает ручной выбор
- **WHEN** HTTP-серверы `a` и `e` без подстановок выключены командами `/mcp disable a` и `/mcp disable e`; перезагрузка меняет `url` у `a` и ставит `e` `enabled: false`, а следующая перезагрузка ставит `e` `enabled: true`
- **THEN** после первой перезагрузки `a` подключён по новому `url`, `e` в `disabled` без `lastError` `disabled by /mcp disable`; после второй `e` подключён (R6-2)

#### Scenario: Правка сроков и ручной выбор
- **WHEN** HTTP-сервер `a` выключен `/mcp disable a`, HTTP-сервер `b` не трогали, и перезагрузка меняет `connect_timeout` у обоих
- **THEN** `a` пересоздан по конфигу и подключён с новым сроком (ручной выбор сброшен); соединение `b` не переподключалось (R6-2)

#### Scenario: Отложенная правка не сбрасывает ручной выбор
- **WHEN** выключенный конфигом stdio-сервер `d` включён командой `/mcp enable d`, и перезагрузка ставит ему в файле `enabled: true` и меняет `args`
- **THEN** `d` не переподключался и работает прежним процессом, `mcp.servers[d]` в `pendingRestartKeys` (R6-2, R0-1)

### Requirement: Модель новой сессии
`AgentRuntime.createSession(SessionSpec)` без `spec.model` SHALL выбирать модель так (design.md change `optional-default-model`, D5):
1. `CoreConfig.defaultModelSource == config` снимка сессии — `CoreConfig.defaultModel`, источник `config`;
2. иначе — модель из `AgentCoreServices.lastModel.read()`, если порт задан и каталог сессии (`AgentRuntime.models`) её разрешает, источник `last-used`;
3. иначе — `CoreConfig.defaultModel` (первый провайдер), источник `first-provider`.

С `spec.model` SHALL использоваться она, как раньше. Выбор SHALL писаться событием `session.model.selected {session_id, model, source}` уровня `info` (source — `config`, `last-used`, `first-provider`); значений секретов и адресов провайдеров в нём нет. Ошибка порта `read()` SHALL давать шаг 3 и событие `model.last_used.ignored {reason}`, а не ошибку `createSession`. Модель памяти, которой нет в каталоге сессии, SHALL давать шаг 3 и событие `model.last_used.ignored {session_id, reason: not in catalog}` уровня `info`. `loadSession` без модели журнала и база модели агента сессии SHALL, как раньше, брать `CoreConfig.defaultModel` без шага 2. ACP-проекция не меняется: `configOptions` опции `model` SHALL иметь `currentValue` выбранной модели, новых полей и методов ACP нет. Смена модели в сессии (`AgentSession.setModel`, `session/set_config_option` опции `model`, запись `model_change`, восстановление при `session/load`) SHALL работать как раньше.

#### Scenario: Явная модель конфига побеждает последнюю
- **WHEN** конфиг задаёт `agent.default_model: a/x`, порт последней модели возвращает `b/y` из каталога, и вызывается `createSession` без модели
- **THEN** модель сессии — `a/x`, событие `session.model.selected` с `source: config`

#### Scenario: Последняя модель побеждает первого провайдера
- **WHEN** ключа модели нет, неявная модель `a/x`, порт возвращает `b/y` из каталога
- **THEN** модель сессии — `b/y`, `source: last-used`; первая запись журнала — `model_change` `b/y`; `configOptions` опции `model` — `currentValue: b/y`

#### Scenario: Последней модели нет в каталоге
- **WHEN** ключа модели нет, неявная модель `a/x`, порт возвращает `gone/z`, которой нет в каталоге
- **THEN** модель сессии — `a/x`, `source: first-provider`, событие `model.last_used.ignored` с `session_id` и `reason: not in catalog` уровня `info`; файл состояния не меняется

#### Scenario: Сбой чтения последней модели
- **WHEN** порт `read()` бросает исключение
- **THEN** `createSession` возвращает сессию с неявной моделью, событие `model.last_used.ignored` с причиной без содержимого файла

#### Scenario: Пустой CODELAB_HOME и provider add
- **WHEN** `$CODELAB_HOME` пуст, выполняется `codelab-agent provider add gw --kind openai-compatible --base-url https://x/v1 --model m --context-window 8192 --api-key-env GW_KEY` без `--default`, затем бинарь запускается `serve --stdio` и клиент вызывает `session/new`
- **THEN** `provider add` — код `0` без `warning: agent.default_model: required`; бинарь стартует, модель сессии — `gw/m`, событие `session.model.selected` с `source: first-provider`

### Requirement: Последняя выбранная модель
Ядро SHALL иметь порт `LastModelStore` с операциями `read() → Future<ModelId?>` и `write(ModelId)`, передаваемый хостом в `AgentCoreServices.lastModel` (design.md change `optional-default-model`, D6–D8). `null` — памяти нет: шаг 2 требования «Модель новой сессии» пропускается, запись не выполняется.

**Когда пишется.** Ядро SHALL вызывать `write` после успешной явной смены модели: `AgentSession.setModel` (в том числе `session/set_config_option` опции `model`) после записи `model_change` в журнал, и `createSession`/`loadSession` с явно переданной моделью. Автоматический выбор, восстановление модели из журнала, смена агента и перезагрузка конфига `write` НЕ SHALL вызывать. Сбой `write` НЕ SHALL менять результат `setModel` и создание сессии: событие `model.last_used.write_failed {reason}` уровня `warning`.

**Файл.** Реализация `codelab_agent_io` SHALL хранить одну модель на `$CODELAB_HOME` в `$CODELAB_HOME/state/last-model.json` содержимым `{"v": 1, "model": "<provider>/<model>"}`:
- запись — во временный файл с уникальным именем в том же каталоге и атомарный `rename`; каталог `state` создаётся при первой записи; отсутствующий `$CODELAB_HOME`, созданный при этом, SHALL получать права `0700` (кроме Windows), как у `ConfigWriter`; записи одного процесса идут по очереди, между процессами выигрывает последняя;
- отсутствующий файл SHALL давать `null` без события;
- перед чтением SHALL проверяться тип и размер файла: не обычный файл (каталог, FIFO, сокет, устройство) SHALL давать причину `not a file` без открытия файла; размер больше 4096 байт — причину `too large` без чтения; чтение SHALL ограничиваться 4097 байтами (лишний байт — `too large`);
- не обычный файл, файл больше 4 KiB, не JSON, неизвестная версия `v` или значение `model` не вида `<provider>/<model>` SHALL давать `null` и событие `model.last_used.ignored {path, reason}` уровня `warning`; `reason` — категория без содержимого файла; файл при чтении не переписывается и не удаляется;
- в файле, событиях и логе НЕ SHALL быть ключей, секретов, адресов и заголовков провайдеров: только идентификатор модели;
- в пути PERM-11 (`agentConfigPathsFor`) SHALL входить лексический путь `$CODELAB_HOME/state/last-model.json`, его канонический путь, если файл — символическая ссылка, и каталог `$CODELAB_HOME/state` префиксом (как `$CODELAB_HOME/agents` и `prompts`): правка их инструментами агента — критическая, как правка конфига; в `watchedConfigFiles` они НЕ SHALL входить.

Бинарь `serve` без `--llm-script` и настольный открыватель `codelab_embedded/io.dart` SHALL передавать файловую реализацию над своим `$CODELAB_HOME`; `--llm-script`, сценарный открыватель `codelab_embedded/testing.dart`, web-безопасный барель и тесты по умолчанию — `null`.

#### Scenario: Смена модели запоминается
- **WHEN** сессия на `a/x` получает `session/set_config_option` опции `model` со значением `b/y`, затем создаётся новая сессия без модели при конфиге без `agent.default_model`
- **THEN** `$CODELAB_HOME/state/last-model.json` содержит `{"v": 1, "model": "b/y"}`, модель новой сессии — `b/y`

#### Scenario: Автоматический выбор не пишет файл
- **WHEN** `createSession` без модели выбирает неявную модель `a/x`
- **THEN** файл состояния не создаётся и не меняется

#### Scenario: Повреждённый файл состояния
- **WHEN** `last-model.json` содержит `{"v": 1, "model": 42}`, во втором варианте — обрезанный JSON, в третьем — `{"v": 9, "model": "a/x"}`
- **THEN** `read()` возвращает `null`, событие `model.last_used.ignored` с путём и причиной, файл не изменён; сессия создаётся с моделью следующего шага

#### Scenario: На месте файла состояния не файл
- **WHEN** на месте `last-model.json` — каталог, во втором варианте — FIFO (POSIX)
- **THEN** `read()` возвращает `null` без зависания, событие `model.last_used.ignored` с `reason: not a file`; файл не открывается для чтения

#### Scenario: Слишком большой файл состояния
- **WHEN** `last-model.json` больше 4096 байт
- **THEN** `read()` возвращает `null`, событие `model.last_used.ignored` с `reason: too large`; содержимое не читается, файл не изменён

#### Scenario: Секретов нет в файле и логе
- **WHEN** провайдер `gw` задаёт `api_key_secret: codelab/gw` со значением `sk-test-leak-0123456789` в хранилище, сессия меняет модель на `gw/m` при `--log-level debug`
- **THEN** файл состояния содержит только `v` и `model`; ни файл, ни лог не содержат `sk-test-leak-0123456789`, `base_url` и заголовков

#### Scenario: Сбой записи не ломает смену модели
- **WHEN** `write` бросает исключение (каталог только для чтения)
- **THEN** `setModel` возвращает результат с новой моделью, журнал содержит `model_change`, событие `model.last_used.write_failed`

#### Scenario: Файл под защитой PERM-11
- **WHEN** модель вызывает инструмент записи в `$CODELAB_HOME/state/last-model.json`; во втором варианте — в другой файл каталога `$CODELAB_HOME/state/`; в третьем `last-model.json` — символическая ссылка, и инструмент пишет в её цель
- **THEN** во всех вариантах действие классифицируется как критическое по PERM-11, как запись в `$CODELAB_HOME/config.yaml`; пути не входят в `watchedConfigFiles`

