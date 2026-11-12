## MODIFIED Requirements

### Requirement: initialize
Ответ на `initialize` SHALL содержать ровно поля и значения §13.2 документа ядра: `protocolVersion: 1`; `agentCapabilities` с `loadSession` (`true` при capability `sessionPersistence`, иначе `false`), `promptCapabilities` (`image: true`, `audio: false`, `embeddedContext: true`), `mcpCapabilities` (`http: true`, если в плане ядра capability `mcp` включена с транспортом `http`, иначе `false`; `sse: false` всегда), `sessionCapabilities.list: {}` при `sessionPersistence`; `agentInfo`; `authMethods: []`. Флага stdio в `mcpCapabilities` нет: stdio обязателен для каждого агента (`03-Session Setup.md`, «MCP Servers»); профиль без stdio (`mobile`) и WS-профиль бинаря, где capability `mcp` выключена (design.md change `add-agent-mcp-client`, D3), — отклонения §13.15 документа ядра.

Единственное исключение из «ровно этих полей» — блок объявлений расширений CodeLab `agentCapabilities._meta.codelab` (design.md change `add-subagents-and-tasks`, D9; change `add-usage-extension`, D3). Правила блока:
- он SHALL отправляться, только если клиент прислал объект `clientCapabilities._meta.codelab` (в том числе пустой);
- значение каждого ключа — объект с целым `version`: при `subagents.enabled` — `subagents: {"version": 1, "maxDepth": <subagents.max_depth>}` и `subagentToolCalls: {"version": 1}`; всегда — `tasks: {"version": 1}` и `usage: {"version": 1}`;
- неизвестные ключи и значения в `clientCapabilities._meta.codelab` SHALL игнорироваться без ошибки;
- стандартные поля и их значения блок не меняет.

`clientCapabilities` SHALL сохраняться на соединение и определять env сессий этого соединения; отсутствие поля SHALL логироваться `acp.client_capabilities.absent`. Объявление клиентом `clientCapabilities._meta.codelab.usage` с целым `version` ≥ 1 SHALL сохраняться на соединение и определять, получает ли оно `_codelab/session/usage` (требование «Уведомление `_codelab/session/usage`»). Повторный `initialize` SHALL давать `-32600` «already initialized», любой метод `session/*` до `initialize` — `-32600` «initialize required». Метод `authenticate` SHALL давать `-32601` (§13.3).

#### Scenario: Ответ codelab-app
- **WHEN** клиент присылает `initialize` с `protocolVersion: 1` и `fs`/`terminal` capabilities без `_meta`
- **THEN** ответ совпадает с фикстурой `acp/initialize-capabilities`, где `mcpCapabilities` — `{"http": true, "sse": false}`, а `_meta` у `agentCapabilities` нет

#### Scenario: Клиент CodeLab объявил расширения
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}, "usage": {"version": 1}, "future": true}`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions`: `agentCapabilities._meta.codelab` — `{"subagents": {"version": 1, "maxDepth": 3}, "subagentToolCalls": {"version": 1}, "tasks": {"version": 1}, "usage": {"version": 1}}`, остальные поля — как в `acp/initialize-capabilities`

#### Scenario: Субагенты выключены
- **WHEN** `subagents.enabled: false`, клиент объявил `clientCapabilities._meta.codelab: {}`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}, "usage": {"version": 1}}`

#### Scenario: Сессия до initialize
- **WHEN** первым кадром соединения приходит `session/new`
- **THEN** ответ — `-32600` «initialize required», соединение живо

#### Scenario: Ядро без MCP
- **WHEN** хост собрал ядро без `AgentCoreServices.mcp`
- **THEN** `mcpCapabilities` в ответе — `{"http": false, "sse": false}`

### Requirement: Расширения протокола этапа 4
Сервер SHALL отправлять только расширения, введённые утверждёнными changes (ACP-2):
- change `add-dart-agent-acp-server`: `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded`, `data.codelab` (`errorClass`, `message`, `retryable`, `reason`), `_meta.codelab.turnEnded`, `_meta.codelab.critical`;
- change `add-subagents-and-tasks`: блок `agentCapabilities._meta.codelab` (`subagents`, `subagentToolCalls`, `tasks`), `_meta.codelab.task` у entries `plan`, `_meta.codelab.subagent` у `toolCall` в `session/request_permission`, у первого `tool_call` вызова `agent` (`id`, `type`) и у его финального `tool_call_update` (`summary`, при `failed` — `failure`), `_meta.codelab.parentToolCallId` у `tool_call`/`tool_call_update` вызовов потомков (только клиенту с `subagentToolCalls`);
- change `add-usage-extension`: ключ `usage` блока `agentCapabilities._meta.codelab` и уведомление агент → клиент `_codelab/session/usage` (только соединению, объявившему `usage`).

Каждое расширение SHALL быть перечислено в §13.12 документа ядра со ссылкой на свой change. Методы и уведомления вне пространства `_codelab/*` и корневые поля ACP сервер НЕ SHALL вводить (`15-Extensibility.md`).

#### Scenario: Бюджет хода
- **WHEN** ход исчерпал лимит шагов
- **THEN** ответ на `session/prompt` — `stopReason: max_turn_requests` с `_meta.codelab.budgetExceeded: "steps"`

## ADDED Requirements

### Requirement: Уведомление `_codelab/session/usage`
Сервер SHALL отправлять уведомление JSON-RPC `_codelab/session/usage` (без `id`) каждому соединению сессии, объявившему `clientCapabilities._meta.codelab.usage` с целым `version` ≥ 1, и НЕ SHALL отправлять его остальным соединениям (design.md change `add-usage-extension`, D1, D3). Расширение SHALL соблюдать `15-Extensibility.md` (D17): метод начинается с `_`, это уведомление без `id` (ответа и `-32601` нет), поддержка объявляется только в `_meta` capability-объектов, а стандартные типы ACP (`InitializeResponse`, `AgentCapabilities`, `PromptResponse`, `SessionNotification`) НЕ SHALL получать новых корневых полей и новых значений `sessionUpdate`. Поводы (`trigger`):
- `step` — после каждого `StepEnded` хода;
- `turn` — по `TurnEnded` хода, в котором был хотя бы один `StepEnded`, после последнего `session/update` хода и до ответа на `session/prompt`, при любой причине завершения, включая `cancelled` и сбой `-32603` (ACP-3, ACP-5, ACP-7);
- `compaction` — после `ContextCompacted`.

Ход без шагов модели (встроенная команда, отмена до первого запроса) НЕ SHALL давать уведомлений.

Параметры SHALL иметь форму D2: `sessionId`; `seq` — целое, начиная с 1 и строго растущее на каждый снимок в пределах сессии сервера, общее для всех её соединений; `trigger`; `turnId` при `step` и `turn`; `step` (`index`, `model` в виде `<provider>/<id>`, `tokens`, `cost`, `partial`) только при `step`; агрегат `turn` при `step` и `turn`; агрегат `session` всегда; `currency: "USD"`, если в параметрах есть хоть одно `cost`; `context` с целыми `used` и `size` и целым `compactAt` (порог автосжатия; поле отсутствует, если автосжатие выключено), если ядро сообщило заполнение контекста. Агрегат SHALL содержать `tokens` (`input`, `output`, `cacheRead`, `cacheWrite`; `reasoning` — только если сообщён), `steps` (у сессии ещё `turns`), `cost` и `partial` по правилам ниже.

Значения SHALL считаться так (D4, D6, D9):
- шаг — usage и модель `StepEnded`; ход во время хода — сумма его шагов; ход в конце — `TurnEnded.usage`; сессия — сумма итогов завершённых ходов этой сессии в сервере плюс текущий ход;
- стоимость — в целых микродолларах (`round(cost.total × 10⁶)` шага и итога хода, сумма ходов для сессии), на проводе — десятичная строка без хвостовых нулей с не более чем 6 знаками после точки (`"0"` для нуля); `cost` отсутствует, если ни у одной модели шагов агрегата нет цен;
- `partial`: `noUsage` — у успешного ответа модели `input + output == 0`; `noPrice` — у модели шага нет цен при ненулевых токенах; `beforeLoad` — только у сессии, открытой в сервере через `session/load`, в журнале которой были ответы модели; у хода и сессии — объединение причин их шагов; пустой массив не отправляется.

Уведомление НЕ SHALL нести секретов, текстов сообщений и аргументов инструментов.

#### Scenario: Два шага с ценами
- **WHEN** клиент объявил `usage`, а ход делает два запроса к модели с ценами и заканчивается `end_turn`
- **THEN** кадры совпадают с фикстурой `acp/prompt-usage-steps`: после первого и второго шага — `_codelab/session/usage` с `trigger: "step"` и `seq` 1 и 2, затем `trigger: "turn"` с `seq` 3, суммой двух шагов в `turn` и `session`, затем ответ `stopReason: end_turn`

#### Scenario: Модель без цен и шаг без usage
- **WHEN** у модели сессии нет цен, а scripted-модель отвечает без usage
- **THEN** в снимках нет `cost` и `currency`, а `partial` шага, хода и сессии — `["noUsage"]`; при ненулевых токенах без цен — `["noPrice"]` (фикстура `acp/prompt-usage-unpriced`)

#### Scenario: Отмена посреди инструмента
- **WHEN** клиент отменяет ход, пока `exec` ждёт `terminal/wait_for_exit`
- **THEN** снимок `trigger: "turn"` идёт после `tool_call_update` `failed` с `outcome: "cancelled"` и до ответа `stopReason: cancelled` (фикстура `acp/prompt-usage-cancelled`)

#### Scenario: Клиент без объявления
- **WHEN** клиент не прислал `clientCapabilities._meta.codelab.usage`
- **THEN** кадров `_codelab/session/usage` нет, остальные кадры совпадают с существующими фикстурами хода (например, `acp/prompt-text-end-turn`)

#### Scenario: Стандартные типы без новых полей
- **WHEN** клиент объявил `usage`, и проходит ход с двумя шагами
- **THEN** ответ `initialize` отличается от фикстуры `acp/initialize-capabilities` только блоком `agentCapabilities._meta.codelab`, кадры `session/update` и ответ `session/prompt` не содержат полей вне схемы `17-Schema.md`, кроме `_meta.codelab.*`, а usage приходит только в `_codelab/session/usage`

#### Scenario: Автосжатие выключено
- **WHEN** у сессии `compaction.enabled: false`, клиент объявил `usage`
- **THEN** `context` в снимках содержит `used` и `size` без `compactAt` (фикстура `acp/prompt-usage-compaction-off`)

#### Scenario: Два соединения одной сессии
- **WHEN** сессию загрузили два соединения, объявившие `usage`, и одно из них отправило промпт
- **THEN** оба получают одинаковые снимки с одинаковыми `seq`, а ответ на `session/prompt` — только отправитель

#### Scenario: Встроенная команда без модели
- **WHEN** клиент, объявивший `usage`, отправляет `/usage`
- **THEN** кадров `_codelab/session/usage` нет (фикстура `acp/usage-and-redact-commands` не меняется)

#### Scenario: Сжатие контекста
- **WHEN** после хода клиент отправляет `/compact`, и сжатие записано
- **THEN** приходит `_codelab/session/usage` с `trigger: "compaction"`, без `turnId` и `step`, с `context.used`, меньшим, чем в последнем снимке хода (фикстура `acp/compact-usage-context`)

#### Scenario: Сессия после загрузки
- **WHEN** сессию с ответами модели в журнале загружают через `session/load` в новом сервере и отправляют промпт
- **THEN** `session.partial` в снимках содержит `beforeLoad`, а `session.turns` считает только ходы после загрузки (фикстура `acp/session-load-usage-partial`)
