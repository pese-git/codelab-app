## MODIFIED Requirements

### Requirement: initialize
Ответ на `initialize` SHALL содержать ровно поля и значения §13.2 документа ядра: `protocolVersion: 1`; `agentCapabilities` с `loadSession` (`true` при capability `sessionPersistence`, иначе `false`), `promptCapabilities` (`image: true`, `audio: false`, `embeddedContext: true`), `mcpCapabilities` (`http: true`, если в плане ядра capability `mcp` включена с транспортом `http`, иначе `false`; `sse: false` всегда), `sessionCapabilities.list: {}` при `sessionPersistence`; `agentInfo`; `authMethods: []`. Флага stdio в `mcpCapabilities` нет: stdio обязателен для каждого агента (`03-Session Setup.md`, «MCP Servers»); профиль без stdio (`mobile`) и WS-профиль бинаря, где capability `mcp` выключена (design.md change `add-agent-mcp-client`, D3), — отклонения §13.15 документа ядра.

Единственное исключение из «ровно этих полей» — блок объявлений расширений CodeLab `agentCapabilities._meta.codelab` (design.md change `add-subagents-and-tasks`, D9). Правила блока:
- он SHALL отправляться, только если клиент прислал объект `clientCapabilities._meta.codelab` (в том числе пустой);
- значение каждого ключа — объект с целым `version`: всегда — `tasks: {"version": 1}`; `subagents: {"version": 1, "maxDepth": <subagents.max_depth>}` — только если у ядра включены субагенты (инструмент `agent` при `subagents.enabled`, с итерации 2 change `add-subagents-and-tasks`); `enabled` и эффективная глубина SHALL браться из применённого конфига в момент `initialize` (геттер `AgentRuntime.subagents`; design.md, D37): `maxDepth` — это `subagents.max_depth`, ограниченная глубиной, которую реализует агент (до итерации 4 change — 1); порог окна контекста D40 объявления не меняет, поэтому перезагрузка конфига меняет блок для следующих `initialize` без перезапуска; `subagentToolCalls: {"version": 1}` — при том же условии и только когда адаптер умеет проецировать вызовы потомков (требование «Шаги потомков деревом», с итерации 5 change `add-subagents-and-tasks`, задача 5.2). Агент НЕ SHALL объявлять расширение, которого у него нет. Состав блока не зависит от того, какие ключи и версии объявил клиент;
- `usage: {"version": 1}` — всегда, когда блок отправляется (design.md change `add-usage-extension`, D3; с итерации 1 этого change): usage ядро считает всегда, а неизвестную цену выражают поля `cost` и `partial` уведомления. Как и остальной состав блока, ключ не зависит от того, какие ключи и версии объявил клиент;
- `usageLedger: {"version": 1}` — всегда, когда блок отправляется (design.md change `add-usage-ledger`, D7; с итерации 2 того change): агент принимает запрос `_codelab/session/usage/ledger` (требование «Запрос `_codelab/session/usage/ledger`»). Клиент этот ключ не объявляет; ключ `usageLedger` в `clientCapabilities._meta.codelab` SHALL игнорироваться, как любой неизвестный ключ;
- неизвестные ключи и значения в `clientCapabilities._meta.codelab` SHALL игнорироваться без ошибки;
- стандартные поля и их значения блок не меняет.

`clientCapabilities` SHALL сохраняться на соединение и определять env сессий этого соединения; отсутствие поля SHALL логироваться `acp.client_capabilities.absent`. Повторный `initialize` SHALL давать `-32600` «already initialized», любой метод `session/*` до `initialize` — `-32600` «initialize required». Метод `authenticate` SHALL давать `-32601` (§13.3).

Объявление клиентом `clientCapabilities._meta.codelab.usage` SHALL сохраняться на соединение и определять, получает ли оно `_codelab/session/usage` (требование «Уведомление `_codelab/session/usage`»; design.md change `add-usage-extension`, D3). Объявление считается сделанным, только если значение ключа `usage` — объект, где `version` — целое JSON-число `1` (не `1.0`, не строка `"1"`, не другое число), — по тому же правилу, по которому клиент CodeLab согласует расширения из ответа агента (design.md change `add-subagents-and-tasks`, D9). Иное значение SHALL давать «не объявлено» без ошибки `initialize`.

Блоки `agentCapabilities._meta.codelab` в сценариях change `add-subagents-and-tasks` ниже (с пометками итераций, «Субагенты выключены перезагрузкой конфига», «Неизвестные ключи и версии клиента», «Субагенты выключены») описывают ответ до итерации 1 change `add-usage-extension`; после неё каждый такой блок дополнительно содержит `"usage": {"version": 1}`, остальное в них не меняется. Сценарии change `add-usage-extension` помечены «(usage)». После итерации 2 change `add-usage-ledger` каждый блок `agentCapabilities._meta.codelab` в сценариях ниже, включая сценарии «(usage)», дополнительно содержит `"usageLedger": {"version": 1}`, остальное в них не меняется; сценарии этого change помечены «(usageLedger)».

#### Scenario: Ответ codelab-app
- **WHEN** клиент присылает `initialize` с `protocolVersion: 1` и `fs`/`terminal` capabilities без `_meta` (так ведёт себя сторонний клиент; в любой итерации change)
- **THEN** ответ совпадает с фикстурой `acp/initialize-capabilities`, где `mcpCapabilities` — `{"http": true, "sse": false}`, а `_meta` у `agentCapabilities` нет

#### Scenario: Клиент CodeLab объявил расширения, субагентов ещё нет (итерация 1)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}}`, а ядро собрано без инструмента `agent`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции итерации 1: `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}}`, остальные поля — как в `acp/initialize-capabilities`

#### Scenario: Клиент CodeLab объявил расширения, субагенты включены (итерации 2–3)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}}`, ядро собрано с `subagents.enabled: true` и `max_depth: 3`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции итерации 2: `agentCapabilities._meta.codelab` — `{"subagents": {"version": 1, "maxDepth": 1}, "tasks": {"version": 1}}`: вложенности до итерации 4 нет, поэтому объявляется эффективная глубина 1, а не `max_depth: 3`; ключа `subagentToolCalls` нет: вызовы потомков адаптер ещё не проецирует

#### Scenario: Клиент CodeLab объявил расширения, вложенность (итерация 4)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}}`, ядро собрано с `subagents.enabled: true` и `max_depth: 3`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции итерации 4: `agentCapabilities._meta.codelab` — `{"subagents": {"version": 1, "maxDepth": 3}, "tasks": {"version": 1}}`: потомки запускают своих детей до `max_depth`, поэтому объявляется `max_depth`; ключа `subagentToolCalls` нет (design.md, D45 Т9)

#### Scenario: Клиент CodeLab объявил расширения, дерево вызовов (итерация 5)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}}`, ядро собрано с `subagents.enabled: true` и `max_depth: 3`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции итерации 5: `agentCapabilities._meta.codelab` — `{"subagents": {"version": 1, "maxDepth": 3}, "subagentToolCalls": {"version": 1}, "tasks": {"version": 1}}`

#### Scenario: Субагенты выключены перезагрузкой конфига
- **WHEN** агент запущен с `subagents.enabled: true`, затем перезагрузка конфига ставит `subagents.enabled: false`, и новое соединение присылает `initialize` с `clientCapabilities._meta.codelab: {}`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}}`; ответ `initialize`, полученный соединением до перезагрузки, не меняется (`initialize_test.dart`; D37)

#### Scenario: Неизвестные ключи и версии клиента
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 2, "x": 1}, "future": true, "board": "yes"}`
- **THEN** ошибки нет, блок ответа — тот же, что при известном объявлении (в итерации 1 — `{"tasks": {"version": 1}}`); проверяет unit-тест `initialize_test.dart` агента, а не фикстура

#### Scenario: Клиентский _meta без codelab
- **WHEN** клиент присылает `clientCapabilities._meta: {"traceparent": "…"}` без ключа `codelab`
- **THEN** у `agentCapabilities` нет `_meta` (`initialize_test.dart`)

#### Scenario: Субагенты выключены
- **WHEN** `subagents.enabled: false`, клиент объявил `clientCapabilities._meta.codelab: {}`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}}`

#### Scenario: Сессия до initialize
- **WHEN** первым кадром соединения приходит `session/new`
- **THEN** ответ — `-32600` «initialize required», соединение живо

#### Scenario: Ядро без MCP
- **WHEN** хост собрал ядро без `AgentCoreServices.mcp`
- **THEN** `mcpCapabilities` в ответе — `{"http": false, "sse": false}`

#### Scenario: Клиент CodeLab объявил расширения (usage)
- **WHEN** после итерации 1 change `add-usage-extension` клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}, "usage": {"version": 1}, "future": true}`, ядро собрано с `subagents.enabled: true` и `max_depth: 3`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в текущей редакции: блок редакции change `add-subagents-and-tasks` с добавленным `"usage": {"version": 1}` — в итерации 2 того change `{"subagents": {"version": 1, "maxDepth": 1}, "tasks": {"version": 1}, "usage": {"version": 1}}`, после его итерации 5 — `{"subagents": {"version": 1, "maxDepth": 3}, "subagentToolCalls": {"version": 1}, "tasks": {"version": 1}, "usage": {"version": 1}}`; остальные поля — как в `acp/initialize-capabilities`

#### Scenario: Субагенты выключены (usage)
- **WHEN** после итерации 1 change `add-usage-extension` ядро собрано с `subagents.enabled: false`, а клиент объявил `clientCapabilities._meta.codelab: {}`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}, "usage": {"version": 1}}`

#### Scenario: Объявление usage не той версии (usage)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"usage": {"version": 2}}` (или `{"version": 1.0}`, `{"version": "1"}`, `usage: true`)
- **THEN** `initialize` успешен, блок ответа содержит `"usage": {"version": 1}`, но соединение не считается объявившим `usage` и кадров `_codelab/session/usage` не получает (`initialize_test.dart`)

#### Scenario: Клиент CodeLab объявил расширения (usageLedger)
- **WHEN** после итерации 2 change `add-usage-ledger` клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "usage": {"version": 1}}`, ядро собрано с `subagents.enabled: false`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}, "usage": {"version": 1}, "usageLedger": {"version": 1}}`; ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции этого change

#### Scenario: Клиент объявил usageLedger (usageLedger)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"usageLedger": {"version": 1}}`
- **THEN** `initialize` успешен, блок ответа тот же, что при `clientCapabilities._meta.codelab: {}`; ключ клиента ни на что не влияет (`initialize_test.dart`)

### Requirement: Расширения протокола этапа 4
Сервер SHALL отправлять только расширения, введённые утверждёнными changes (ACP-2):
- change `add-dart-agent-acp-server`: `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded`, `data.codelab` (`errorClass`, `message`, `retryable`, `reason`), `_meta.codelab.turnEnded`, `_meta.codelab.critical`;
- change `add-subagents-and-tasks`: блок `agentCapabilities._meta.codelab` (`subagents`, `subagentToolCalls`, `tasks`), `_meta.codelab.task` у entries `plan`, `_meta.codelab.subagent` у `toolCall` в `session/request_permission`, у первого `tool_call` вызова `agent` (`id`, `type`) и у его финального `tool_call_update` (`summary`, при `failed` — `failure`), `_meta.codelab.parentToolCallId` у `tool_call`/`tool_call_update` вызовов потомков (только клиенту с `subagentToolCalls`).
- change `add-usage-extension`: ключ `usage` блока `agentCapabilities._meta.codelab` и уведомление агент → клиент `_codelab/session/usage` (только соединению, объявившему `clientCapabilities._meta.codelab.usage`).
- change `add-usage-ledger`: ключ `usageLedger` блока `agentCapabilities._meta.codelab`, запрос клиент → агент `_codelab/session/usage/ledger` и значение `trigger: "load"` уведомления `_codelab/session/usage`.

Каждое расширение SHALL быть перечислено в §13.12 документа ядра со ссылкой на свой change. Новых методов и корневых полей ACP сервер НЕ SHALL вводить (`15-Extensibility.md`).

Уточнение change `add-usage-extension` (D17): запрет новых методов относится к методам вне пространства `_codelab/*`. Уведомление `_codelab/session/usage` введено по разделам «Extension Methods» и «Custom Notifications» `15-Extensibility.md` (имя с `_`, без `id`), перечислено выше и не вводит ни корневых полей, ни значений `sessionUpdate`. Запрос `_codelab/session/usage/ledger` (change `add-usage-ledger`, D6) введён по разделу «Custom Requests» того же документа: имя с `_`, ответ с тем же `id`, поддержка объявляется ключом `usageLedger`; агент без этого ключа отвечает на метод `-32601`.

#### Scenario: Бюджет хода
- **WHEN** ход исчерпал лимит шагов
- **THEN** ответ на `session/prompt` — `stopReason: max_turn_requests` с `_meta.codelab.budgetExceeded: "steps"`

#### Scenario: Запрос журнала у агента без ключа
- **WHEN** клиент шлёт `_codelab/session/usage/ledger` агенту, в ответе `initialize` которого нет ключа `usageLedger` (сторонний агент или CodeLab до change `add-usage-ledger`)
- **THEN** ответ — `-32601` «Method not found» по `15-Extensibility.md`; соединение живо

### Requirement: Уведомление `_codelab/session/usage`
Сервер SHALL отправлять уведомление JSON-RPC `_codelab/session/usage` (без `id`) каждому соединению сессии, объявившему `clientCapabilities._meta.codelab.usage` (значение — объект с `version`, равным целому JSON-числу `1`; требование «initialize»), и НЕ SHALL отправлять его остальным соединениям (design.md change `add-usage-extension`, D1, D3). Расширение SHALL соблюдать `15-Extensibility.md` (D17): метод начинается с `_`, это уведомление без `id` (ответа и `-32601` нет), поддержка объявляется только в `_meta` capability-объектов, а стандартные типы ACP (`InitializeResponse`, `AgentCapabilities`, `PromptResponse`, `SessionNotification`) НЕ SHALL получать новых корневых полей и новых значений `sessionUpdate`. Поводы (`trigger`):
- `step` — после каждого `StepEnded` хода;
- `turn` — по `TurnEnded` хода, в котором был хотя бы один `StepEnded`, после последнего `session/update` хода и до ответа на `session/prompt`, при любой причине завершения, включая `cancelled` и сбой `-32603` (ACP-3, ACP-5, ACP-7); `session_info_update` с названием сессии, которое агент даёт после хода, идёт после снимка `turn` (design.md, D19 п. 5);
- `compaction` — после `ContextCompacted`;
- `load` — после ответа на `session/load` этому соединению, если в сумме сессии есть хотя бы один шаг (change `add-usage-ledger`, D8): снимок несёт `session` и, если мосту известно заполнение контекста, `context`; полей `turnId`, `step` и `turn` у него нет. То же — после повторного `session/load` уже открытой сессии (`reattach`).

Ход без шагов модели (встроенная команда, отмена до первого запроса) НЕ SHALL давать уведомлений.

Параметры SHALL иметь форму D2: `sessionId`; `seq` — целое, начиная с 1 и строго растущее на каждый снимок в пределах сессии сервера, общее для всех её соединений; `trigger`; `turnId` при `step` и `turn`; `step` (`index`, `model` в виде `<provider>/<id>`, `tokens`, `cost`, `partial`) только при `step`; агрегат `turn` при `step` и `turn`; агрегат `session` всегда; `currency: "USD"`, если в параметрах есть хоть одно `cost`; `context` с целыми `used` и `size` и целым `compactAt` (порог автосжатия; поле отсутствует, если автосжатие выключено), если ядро сообщило заполнение контекста. Агрегат SHALL содержать `tokens` (`input`, `output`, `cacheRead`, `cacheWrite`; `reasoning` — только если сообщён), `steps` (у сессии ещё `turns` — число ходов сессии в сервере, в которых был хотя бы один `StepEnded`, включая текущий), `cost` и `partial` по правилам ниже. `context` снимка `turn` SHALL совпадать с `context` последнего `StepEnded` хода (design.md, D19 п. 3–4).

Значения SHALL считаться так (D4, D6, D9):
- шаг — usage и модель `StepEnded`; ход во время хода — сумма его шагов; ход в конце — `TurnEnded.usage`; сессия — засев из свёртки журнала при загрузке (требование «Полная сумма сессии после session/load»), плюс итоги завершённых ходов этой сессии в сервере, плюс текущий ход, плюс usage суммаризатора из `ContextCompacted.usage` (в агрегат хода он не входит; change `add-usage-ledger`, D4);
- стоимость — в целых микродолларах (`round(cost.total × 10⁶)` шага и итога хода, сумма ходов для сессии), на проводе — десятичная строка без хвостовых нулей с не более чем 6 знаками после точки (`"0"` для нуля); `cost` шага SHALL присутствовать всегда, когда у модели шага есть цены (`ModelRef.cost != null`), в том числе при нулевых токенах — тогда `"0"` (причина `noUsage` при этом остаётся); `cost` хода и сессии SHALL присутствовать, если цены есть хотя бы у одной модели их шагов, и отсутствовать, только если цен нет ни у одной (design.md, D6, D20);
- стоимость шага или итога хода, которая не является конечным неотрицательным числом или в микроединицах превышает `2^53 − 1`, SHALL считаться неизвестной ценой: она даёт 0 микроединиц и причину `noPrice` (у шага `cost` нет; у хода с таким итогом `TurnEnded.usage` `cost` нет: итог берётся из ядра и включает детей, поэтому невалидному итогу нельзя доверять ни целиком, ни частично), а ход SHALL продолжаться без ошибки и без исключения в проекции (защита адаптера; цены конфигурации проверяет `agent-configuration` «Цены моделей конфигурации», D20);
- `partial`: `noUsage` — у ответа модели со `stopReason`, отличным от `error`, у которого все счётчики `input`, `output`, `cacheRead` и `cacheWrite` равны нулю; шаг только с кэш-токенами — сообщённый расход, `noUsage` у него нет. В том числе у шага, прерванного отменой (`aborted`), по которому провайдер не сообщил usage. У шага с ошибкой (`error`, в том числе `overflow` проверки перед запросом) `noUsage` не ставится (design.md, D26); `noPrice` — у модели шага нет цен при ненулевых токенах, а у итога хода ещё и когда `TurnEnded.subagentUsage` имеет ненулевые токены при нулевой стоимости (эвристика: цены моделей детей адаптеру не видны); `beforeLoad` агент CodeLab НЕ SHALL ставить: после change `add-usage-ledger` сумма сессии после загрузки полная (D8); значение остаётся в протоколе v1 для других агентов, и клиент его по-прежнему понимает; у суммаризатора `noPrice` — модель ответа без цен в каталоге при ненулевых токенах; у хода и сессии — объединение причин их шагов; у шага `noUsage` и `noPrice` вместе не бывают (`noPrice` требует ненулевых токенов); причины в массиве SHALL идти в порядке `noUsage`, `noPrice`, `beforeLoad`; пустой массив не отправляется (design.md, D19 п. 2).

Уведомление НЕ SHALL нести секретов, текстов сообщений и аргументов инструментов. Каждая отправка SHALL давать debug-запись `acp.usage.sent {session_id, seq, trigger, turn_id?}` без токенов и денег; `turn_id` — при `trigger` `step` и `turn`, у `compaction` и `load` его нет (design.md, D14, D20).

#### Scenario: Два шага с ценами
- **WHEN** клиент объявил `usage`, а ход делает два запроса к модели с ценами и заканчивается `end_turn`
- **THEN** кадры совпадают с фикстурой `acp/prompt-usage-steps`: после первого и второго шага — `_codelab/session/usage` с `trigger: "step"` и `seq` 1 и 2 (уже в первом `session.turns` — 1), затем `trigger: "turn"` с `seq` 3, суммой двух шагов в `turn` и `session` и `context` второго шага, затем ответ `stopReason: end_turn`

#### Scenario: Модель без цен и шаг без usage
- **WHEN** у модели сессии нет цен, а scripted-модель отвечает без usage
- **THEN** в снимках нет `cost` и `currency`; `partial` шага с токенами — `["noPrice"]`, шага без usage — `["noUsage"]`, а хода и сессии после обоих шагов — `["noUsage", "noPrice"]` (фикстура `acp/prompt-usage-unpriced`)

#### Scenario: Шаг без usage на модели с ценами
- **WHEN** у модели сессии есть цены, а scripted-модель отвечает успешно без usage
- **THEN** у снимка `step` `cost` — `"0"`, `partial` — `["noUsage"]`, `currency` — `"USD"`; у `turn` и `session` — `cost` `"0"` с `noUsage` (`usage_bridge_test.dart`; design.md, D20 п. 1, п. 9)

#### Scenario: Не конечная стоимость
- **WHEN** usage шага на модели с ценами несёт стоимость `Infinity` (или отрицательную)
- **THEN** снимок `step` уходит без `cost` с `partial: ["noPrice"]`; если невалиден итог `TurnEnded.usage`, у агрегата `turn` снимка `trigger: "turn"` нет `cost`, а `partial` содержит `noPrice`; ход завершается тем же `stopReason`, что без этой стоимости, ошибки `-32603` нет; то же при стоимости `NaN` и при стоимости больше `2^53 − 1` микроединиц (переполнение) (`usage_bridge_test.dart` — `Infinity`, `NaN`, переполнение; `usage_projection_test.dart` — отрицательная цена через ядро; design.md, D20 п. 3, п. 9)

#### Scenario: Отмена посреди инструмента
- **WHEN** клиент отменяет ход, пока `exec` ждёт `terminal/wait_for_exit`
- **THEN** снимок `trigger: "turn"` идёт после `tool_call_update` `failed` с `outcome: "cancelled"` и до ответа `stopReason: cancelled`. Снимок `step` шага, ответ модели которого получен целиком (`stopReason: toolUse` с usage), несёт этот usage без причины `noUsage` (фикстура `acp/prompt-usage-cancelled`; design.md, D19 п. 9, D26)

#### Scenario: Отмена посреди потока без usage провайдера
- **WHEN** клиент объявил `usage`, у модели сессии есть цены, а клиент отменяет ход, пока модель ещё отвечает, и провайдер не прислал usage оборванного потока (шаг `stopReason: aborted`, все счётчики usage нулевые)
- **THEN** у снимка `step` этого шага `partial` — `["noUsage"]`, `cost` — `"0"`; снимок `turn` идёт до ответа `stopReason: cancelled`, и у агрегатов `turn` и `session` `partial` содержит `noUsage` (design.md, D26)

#### Scenario: Отмена посреди потока с частичным usage провайдера
- **WHEN** шаг прерван отменой (`stopReason: aborted`), но провайдер успел сообщить usage с `input > 0`
- **THEN** у снимка `step` нет причины `noUsage`, а токены и стоимость шага берутся из сообщённого usage (design.md, D26)

#### Scenario: Ошибка модели без usage
- **WHEN** запрос к модели завершился ошибкой (`stopReason: error`) с нулевым usage
- **THEN** у снимка `step` этого шага нет причины `noUsage` (design.md, D6, D26)

#### Scenario: Клиент без объявления
- **WHEN** клиент не прислал `clientCapabilities._meta.codelab.usage`
- **THEN** кадров `_codelab/session/usage` нет, остальные кадры совпадают с существующими фикстурами хода (например, `acp/prompt-text-end-turn`)

#### Scenario: Стандартные типы без новых полей
- **WHEN** клиент объявил `usage`, и проходит ход с двумя шагами
- **THEN** ответ `initialize` отличается от фикстуры `acp/initialize-capabilities` только блоком `agentCapabilities._meta.codelab`, кадры `session/update` и ответ `session/prompt` не содержат полей вне схемы `17-Schema.md`, кроме `_meta.codelab.*`, а usage приходит только в `_codelab/session/usage`

#### Scenario: Автосжатие выключено
- **WHEN** у сессии `compaction.enabled: false`, клиент объявил `usage`
- **THEN** `context` в снимках содержит `used` и `size` без `compactAt` (фикстура `acp/prompt-usage-compaction-off`)

#### Scenario: Сессия перешла к новому соединению
- **WHEN** после хода со снимками до `seq` 3 сессию без идущего хода загружает другое соединение, объявившее `usage` (`reattach`: у сессии один владелец, веер кадров на все соединения — после MVP, SESM-15), и отправляет промпт
- **THEN** после ответа на `session/load` новое соединение получает снимок `trigger: "load"` с `seq` 4 и суммой ходов до перехода (change `add-usage-ledger`, D8); снимки нового хода получает только новое соединение, `seq` продолжает счёт сессии сервера без сброса (первый снимок хода — `seq` 5), агрегат `session` включает ходы до перехода, `partial` не содержит `beforeLoad`; прежнее соединение снимков не получает

#### Scenario: Придержанный снимок и соединение без согласия
- **WHEN** соединение, объявившее `usage`, загружает сессию, снимок `_codelab/session/usage` придержан в буфере реплея, соединение рвётся до выпуска буфера, и ту же сессию загружает (`reattach`) соединение без объявления `usage`
- **THEN** новое соединение не получает придержанный кадр `_codelab/session/usage` ни при выпуске буфера, ни позже; придержанные `session/update` реплея оно получает в прежнем порядке (`usage_bridge_test.dart`; design.md, D20 п. 8)

#### Scenario: Субагент на модели без цен
- **WHEN** в ходе вызов `agent` запустил ребёнка, `TurnEnded.subagentUsage` содержит ненулевые токены, а его стоимость равна нулю
- **THEN** у агрегатов `turn` и `session` снимка `trigger: "turn"` `partial` содержит `noPrice` (стоимость детей не оценена)

#### Scenario: Встроенная команда без модели
- **WHEN** клиент, объявивший `usage`, отправляет встроенную команду `/status`
- **THEN** кадров `_codelab/session/usage` нет: модель не вызывалась (`usage_projection_test.dart`); то же для `/usage` и `/usage rebuild` (фикстура `acp/slash-usage`; change `add-usage-ledger`, D5)

#### Scenario: Сжатие контекста
- **WHEN** после хода клиент отправляет `/compact`, и сжатие записано
- **THEN** приходит `_codelab/session/usage` с `trigger: "compaction"`, без `turnId`, `step` и `turn`, с `context.used`, меньшим, чем в последнем снимке хода (`usage_projection_test.dart`), и `size`, `compactAt` последнего `StepEnded`; относительно чанка отчёта «Compacted…» порядок не фиксирован (фикстура `acp/compact-usage-context`)

#### Scenario: Сессия после загрузки
- **WHEN** сессию с двумя ходами с ответами модели в журнале загружают через `session/load` в новом сервере, клиент объявил `usage`, затем отправляет промпт
- **THEN** после реплея и ответа на `session/load` приходит снимок `trigger: "load"` с `session.turns: 2`, суммой токенов и стоимости двух ходов журнала и без `beforeLoad`; снимки нового хода продолжают эту сумму (`session.turns: 3`) (фикстура `acp/session-load-usage-full`; change `add-usage-ledger`, D8)

#### Scenario: Загрузка сессии без шагов
- **WHEN** загружают сессию, в журнале которой нет ни одного ответа модели
- **THEN** снимка `trigger: "load"` нет (`usage_projection_test.dart`)

#### Scenario: Загрузка соединением без объявления
- **WHEN** сессию с ответами модели загружает соединение без `clientCapabilities._meta.codelab.usage`
- **THEN** кадров `_codelab/session/usage` нет, ответ `session/load` и реплей не меняются

#### Scenario: Суммаризатор в сумме сессии
- **WHEN** клиент объявил `usage`, после хода приходит `/compact`, и суммаризатор ответил с usage на модели с ценами
- **THEN** снимок `trigger: "compaction"` несёт `session` с токенами и стоимостью суммаризатора сверх итогов ходов, `session.steps` и `session.turns` не меняются (фикстура `acp/compact-usage-summary`; change `add-usage-ledger`, D4)

## ADDED Requirements

### Requirement: Запрос `_codelab/session/usage/ledger`
Сервер SHALL принимать запрос JSON-RPC `_codelab/session/usage/ledger` (клиент → агент, с `id`) с параметрами `sessionId` (строка) и необязательным `rebuild` (логическое, по умолчанию `false`); неизвестные поля параметров SHALL игнорироваться (design.md change `add-usage-ledger`, D6). Расширение SHALL соблюдать раздел «Custom Requests» `15-Extensibility.md`: имя с `_`, ответ с тем же `id`, поддержка объявлена ключом `usageLedger` блока `initialize`.

Сессия ищется среди открытых в сервере тем же способом, что у `session/prompt`; незнакомый `sessionId` SHALL давать `-32002` «Session not found»; неверные типы параметров — `-32602`. Путь к файлам журнала из параметров НЕ SHALL строиться.

Ответ SHALL строиться из отчёта журнала usage ядра (capability `agent-sessions`, «Журнал usage сессии»): без `rebuild` — свежий `usage.json` или пересчёт, если файла нет, он битый или устарел; с `rebuild` — пересчёт всегда. Результат SHALL иметь поля:
- `sessionId`; `seq` — последний `seq`, потраченный на снимки `_codelab/session/usage` этой сессии сервера к моменту построения, `0` — снимков не было;
- `ledger` — `status` (`upToDate`, `rebuilt`, `inMemory`, `notSaved`), `reason` при `rebuilt` (`missing`, `invalid`, `stale`, `explicit`), `records`;
- `total` — агрегат формы D2 change `add-usage-extension` (`turns`, `steps`, `tokens`, `cost`, `partial`) по всем записям журнала: шаги, субагенты и суммаризатор;
- `turns` — ходы с шагами по пути до активного листа: `index` (с 1), `title` (если есть), `total` (агрегат хода с шагами и субагентами хода), `steps` (каждый — `index` с 0 в ходе, `model` в виде `<provider>/<id>`, `tokens`, `cost`, `partial`, `toolCallIds`), `subagents` (`runs` и агрегат без `steps`; только при ненулевом `runs`), `running: true` у последнего хода, если ход сессии идёт;
- `models` — `model`, `steps` и агрегат шагов этой модели, в лексикографическом порядке `model`;
- `subagents` и `summaries` — `runs` или `count` с агрегатом, только при ненулевом счётчике;
- `currency: "USD"`, если в результате есть хоть одно `cost`.

Деньги, причины и их порядок SHALL следовать правилам уведомления `_codelab/session/usage` (D2, D6, D9 change `add-usage-extension`): микродоллары десятичной строкой; `cost` шага — при цене модели шага в каталоге сессии, стоимость хода — округлённая сумма usage его шагов и детей, сессии — сумма ходов и суммаризатора; `noUsage` — по записи журнала; `noPrice` — по каталогу моделей сессии в момент ответа; у суммаризатора — по `details.summaryModel`, у субагентов — эвристика «ненулевые токены при нулевой стоимости» (design.md change `add-usage-ledger`, D2, Q4). Ответ НЕ SHALL нести текстов сообщений, аргументов инструментов и секретов, кроме подписи хода `title` (не более 64 рун слов пользователя).

Запрос SHALL обслуживаться и во время хода; `session/cancel` его не отменяет. Сбой записи `usage.json` ошибкой запроса НЕ SHALL быть (статус `notSaved`); исключение свёртки SHALL давать `-32603` с `data.codelab.reason: "usageLedgerFailed"` и warning в лог. Каждый ответ SHALL давать debug-запись `acp.usage.ledger {session_id, rebuild, status, turns, steps, duration_ms}` без токенов, денег и подписей.

#### Scenario: Журнал после хода
- **WHEN** клиент объявил `usage`, ход сделал два шага с ценами, первый — с вызовом `read` (`toolCallId` `call_1`), и после ответа клиент шлёт `_codelab/session/usage/ledger`
- **THEN** результат совпадает с фикстурой `acp/usage-ledger-request`: `seq` равен `seq` снимка `turn`, `total.turns: 1`, `total.steps: 2`, `total` равен `session` последнего снимка по токенам и стоимости, у хода `title` — начало промпта, у первого шага `toolCallIds: ["call_1"]`, одна строка `models`

#### Scenario: Пересчёт по требованию
- **WHEN** клиент шлёт запрос с `rebuild: true`
- **THEN** `ledger.status` — `rebuilt`, `ledger.reason` — `explicit`, итоги те же, что без `rebuild` (фикстура `acp/usage-ledger-rebuild`)

#### Scenario: Незнакомая сессия
- **WHEN** `sessionId` не открыт в сервере
- **THEN** ответ — `-32002`, файлы не читаются и не пишутся

#### Scenario: Запрос во время хода
- **WHEN** запрос приходит, пока ход сессии идёт, и в журнале уже есть первый шаг хода
- **THEN** ответ приходит без ожидания конца хода, у последнего хода `running: true`, ход продолжается без изменений

#### Scenario: Модель без цен в истории
- **WHEN** в журнале есть шаги модели, которой в каталоге сессии нет цен
- **THEN** у этих шагов нет `cost`, `partial` — `["noPrice"]`; у хода, модели и `total` — `noPrice`; ноль за цену не выдаётся

#### Scenario: Сбой записи файла
- **WHEN** хранилище не может записать `usage.json`
- **THEN** ответ успешный, `ledger.status: "notSaved"`, в логе warning `usage.ledger.write_failed`

#### Scenario: Стандартные типы без новых полей (usageLedger)
- **WHEN** клиент запрашивает журнал
- **THEN** ни один стандартный тип ACP не получает новых полей; журнал приходит только в результате `_codelab/session/usage/ledger`

### Requirement: Полная сумма сессии после session/load
Когда `session/load` открывает сессию в сервере (моста сессии ещё нет), адаптер SHALL засевать агрегаты usage сессии сервера отчётом журнала usage, построенным в памяти без чтения и записи `usage.json` (design.md change `add-usage-ledger`, D8): итоги ходов, число ходов и шагов, причины `noUsage` и `noPrice`, usage субагентов и суммаризатора. Сразу после засева агрегат `session` снимка SHALL совпадать с `total` ответа `_codelab/session/usage/ledger` по `tokens`, `cost`, `turns`, `steps` и `partial`. Засев SHALL давать debug-запись `acp.usage.seeded {session_id, turns, steps, duration_ms}`. Повторный `session/load` открытой сессии (`reattach`) агрегаты НЕ SHALL пересевать.

#### Scenario: Засев равен журналу
- **WHEN** сессию с тремя ходами, субагентом и сжатием с usage суммаризатора загружают в новом сервере, а клиент сразу запрашивает журнал
- **THEN** `session` снимка `trigger: "load"` и `total` ответа журнала равны по токенам, стоимости, `turns`, `steps` и `partial` (`usage_ledger_seed_test.dart`)

#### Scenario: Reattach без пересева
- **WHEN** открытую сессию загружает другое соединение
- **THEN** сумма и `seq` продолжаются, ходы не удваиваются
