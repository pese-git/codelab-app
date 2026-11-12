## MODIFIED Requirements

### Requirement: initialize
Ответ на `initialize` SHALL содержать ровно поля и значения §13.2 документа ядра: `protocolVersion: 1`; `agentCapabilities` с `loadSession` (`true` при capability `sessionPersistence`, иначе `false`), `promptCapabilities` (`image: true`, `audio: false`, `embeddedContext: true`), `mcpCapabilities` (`http: true`, если в плане ядра capability `mcp` включена с транспортом `http`, иначе `false`; `sse: false` всегда), `sessionCapabilities.list: {}` при `sessionPersistence`; `agentInfo`; `authMethods: []`. Флага stdio в `mcpCapabilities` нет: stdio обязателен для каждого агента (`03-Session Setup.md`, «MCP Servers»); профиль без stdio (`mobile`) и WS-профиль бинаря, где capability `mcp` выключена (design.md change `add-agent-mcp-client`, D3), — отклонения §13.15 документа ядра.

Единственное исключение из «ровно этих полей» — блок объявлений расширений CodeLab `agentCapabilities._meta.codelab` (design.md change `add-subagents-and-tasks`, D9). Правила блока:
- он SHALL отправляться, только если клиент прислал объект `clientCapabilities._meta.codelab` (в том числе пустой);
- значение каждого ключа — объект с целым `version`: при `subagents.enabled` — `subagents: {"version": 1, "maxDepth": <subagents.max_depth>}` и `subagentToolCalls: {"version": 1}`; всегда — `tasks: {"version": 1}`;
- неизвестные ключи и значения в `clientCapabilities._meta.codelab` SHALL игнорироваться без ошибки;
- стандартные поля и их значения блок не меняет.

`clientCapabilities` SHALL сохраняться на соединение и определять env сессий этого соединения; отсутствие поля SHALL логироваться `acp.client_capabilities.absent`. Повторный `initialize` SHALL давать `-32600` «already initialized», любой метод `session/*` до `initialize` — `-32600` «initialize required». Метод `authenticate` SHALL давать `-32601` (§13.3).

#### Scenario: Ответ codelab-app
- **WHEN** клиент присылает `initialize` с `protocolVersion: 1` и `fs`/`terminal` capabilities без `_meta`
- **THEN** ответ совпадает с фикстурой `acp/initialize-capabilities`, где `mcpCapabilities` — `{"http": true, "sse": false}`, а `_meta` у `agentCapabilities` нет

#### Scenario: Клиент CodeLab объявил расширения
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}, "future": true}`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions`: `agentCapabilities._meta.codelab` — `{"subagents": {"version": 1, "maxDepth": 3}, "subagentToolCalls": {"version": 1}, "tasks": {"version": 1}}`, остальные поля — как в `acp/initialize-capabilities`

#### Scenario: Субагенты выключены
- **WHEN** `subagents.enabled: false`, клиент объявил `clientCapabilities._meta.codelab: {}`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}}`

#### Scenario: Сессия до initialize
- **WHEN** первым кадром соединения приходит `session/new`
- **THEN** ответ — `-32600` «initialize required», соединение живо

#### Scenario: Ядро без MCP
- **WHEN** хост собрал ядро без `AgentCoreServices.mcp`
- **THEN** `mcpCapabilities` в ответе — `{"http": false, "sse": false}`

### Requirement: session/load и реплей
`session/load` SHALL выполнять алгоритм §13.5 в объёме MVP: неизвестный `sessionId` → `-32002`; `cwd` запроса выигрывает у `cwd` заголовка с записью `custom` `codelab.cwd_changed`; сессия открывается `AgentRuntime.loadSession` с env, gate и хуками соединения и с `mcpServers` запроса, отображёнными так же, как в `session/new`. Id журнала субагента в базовом этапе SHALL давать `-32002`: хранилище дочерние журналы по id не ищет (design.md change `add-subagents-and-tasks`, D7). Если сессия уже открыта в этом процессе, `mcpServers` запроса SHALL заменять серверы сессии с `origin: session` через `AgentSession.setMcpServers` (design.md change `add-agent-mcp-client`, D11):
- совпавшие по `name` и параметрам остаются подключёнными;
- исчезнувшие закрываются, новые подключаются;
- серверы конфигурации не трогаются;
- без хода изменения применяются до ответа `session/load`, во время хода — после его окончания;
- проверка «сессия занята» и `reattach` SHALL быть атомарны относительно `setMcpServers`: ожидание замены не разделяет их;
- исключение `setMcpServers` НЕ SHALL ронять `session/load`: лог `mcp.servers.replace_failed` (warning, `session_id`, `error` — тип исключения), ответ отправляется как обычно.

Файлы проекта (agent-project-context) при повторном `session/load` уже открытой в процессе сессии НЕ SHALL перечитываться: адаптер переподключает открытую сессию (`reattach`) без вызова `AgentRuntime.loadSession`, поэтому `ProjectFilesSource.load` не вызывается, а команды и определения агентов сессии остаются прежними до её закрытия (design.md change `add-agent-project-files`, D6; §17.2.1 документа ядра: изменения файлов — со следующей сессии).

Описания серверов НЕ SHALL читаться из журнала. Реплей SHALL идти по активной ветке:
- слова пользователя → `user_message_chunk` на каждый блок; у записи с полем `command` первым блоком идёт исходный текст `/<name>[ <args>]` вместо развёрнутого (agent-slash-commands «Исходный текст команды в журнале»); прочие user-записи пропускаются;
- ответ модели → `agent_thought_chunk` и `agent_message_chunk` по блокам; вызов → один `tool_call` с итоговым статусом, `title`, `kind`, `locations`, `rawInput`, `content` результата, `diff` и `_meta.codelab.outcome` для `cancelled`/`rejected`/`interrupted`; вызов `agent` — так же, с телом отчёта в `content`;
- `compaction`, `task`, `subagent` и `plan` в ленту не отправляются; журналы детей не проигрываются.

После истории — `plan` из списка задач активной ветки (`buildTaskList`, agent-sessions «Список задач из журнала»; entries с `_meta.codelab.task`), если в ветке была хоть одна запись `task` или `plan`; затем `current_mode_update`, `config_option_update` (с опцией `agent` и восстановленным значением, если она есть), `available_commands_update` с `AgentSession.commands`, `session_info_update`; затем ответ `LoadSessionResponse(modes, configOptions)`.

#### Scenario: Реплей двух ходов
- **WHEN** сессия с двумя ходами, вызовом `read` и заголовком загружается в новом соединении
- **THEN** кадры совпадают с фикстурой `acp/session-load-replay`, а ответ `session/load` — последний

#### Scenario: Прерванный ход
- **WHEN** журнал кончается вызовом без результата
- **THEN** реплей содержит `tool_call` со `status: failed` и `_meta.codelab.outcome: "interrupted"`, повторного вызова инструмента нет

#### Scenario: План старой сессии
- **WHEN** журнал содержит запись `plan` старого формата с тремя пунктами и ни одной записи `task`
- **THEN** после истории уходит `plan` с тремя entries в порядке записи и `_meta.codelab.task.id` `"1"`, `"2"`, `"3"` (фикстура `acp/session-load-legacy-plan`)

#### Scenario: Серверы загруженной сессии
- **WHEN** сохранённая сессия загружается с `mcpServers`, содержащим stdio-сервер `fake`
- **THEN** первый запрос к модели после загрузки содержит схему `mcp__fake__echo`

#### Scenario: Повторная загрузка открытой сессии с другим набором
- **WHEN** открытая сессия без хода с сервером `a` загружается заново с `mcpServers: [b]`
- **THEN** до ответа `session/load` транспорт `a` закрыт, `b` подключён, а следующий запрос к модели содержит инструменты `b` и не содержит инструментов `a`

#### Scenario: Повторная загрузка открытой сессии не читает файлы проекта
- **WHEN** открытая в процессе сессия загружается заново через `session/load`, а `AGENTS.md` в её `cwd` между загрузками изменён
- **THEN** фейковый `ProjectFilesSource` вызван ровно один раз — при первом открытии, системный промпт следующего хода содержит прежний текст файла

#### Scenario: Реплей команды шаблона
- **WHEN** сессия, в которой пользователь отправил `/review lib/parser "error handling"`, загружается в новом соединении
- **THEN** реплей содержит `user_message_chunk` с этим текстом, `available_commands_update` содержит `review` (фикстура `acp/prompt-template-command`)

### Requirement: Расширения протокола этапа 4
Сервер SHALL отправлять только расширения, введённые утверждёнными changes (ACP-2):
- change `add-dart-agent-acp-server`: `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded`, `data.codelab` (`errorClass`, `message`, `retryable`, `reason`), `_meta.codelab.turnEnded`, `_meta.codelab.critical`;
- change `add-subagents-and-tasks`: блок `agentCapabilities._meta.codelab` (`subagents`, `subagentToolCalls`, `tasks`), `_meta.codelab.task` у entries `plan`, `_meta.codelab.subagent` у `toolCall` в `session/request_permission`, у первого `tool_call` вызова `agent` (`id`, `type`) и у его финального `tool_call_update` (`summary`, при `failed` — `failure`), `_meta.codelab.parentToolCallId` у `tool_call`/`tool_call_update` вызовов потомков (только клиенту с `subagentToolCalls`).

Каждое расширение SHALL быть перечислено в §13.12 документа ядра со ссылкой на свой change. Новых методов и корневых полей ACP сервер НЕ SHALL вводить (`15-Extensibility.md`).

#### Scenario: Бюджет хода
- **WHEN** ход исчерпал лимит шагов
- **THEN** ответ на `session/prompt` — `stopReason: max_turn_requests` с `_meta.codelab.budgetExceeded: "steps"`

## ADDED Requirements

### Requirement: Проекция субагентов и списка задач
События субагентов и списка задач SHALL проецироваться по таблицам §13.7 и §17.3.7 исчерпывающим `switch` (ACP-6):

| Событие ядра | Кадр |
|---|---|
| `TaskListChanged` | `session/update` `plan` со всем списком в порядке создания; у entry `content` = `subject`, `priority`, `status` и `_meta: {"codelab": {"task": {"id", "owner", "blockedBy"}}}`; пустой список — `entries: []` (TSK-5); так же — при `change.op == restore` (список новой ветки, D29) |
| `ToolCallStarted(agent)` | `tool_call` с `kind: think`, `title` `Subagent <agent>: <description>` и `_meta.codelab.subagent: {"id", "type"}` (D28); то же — у `tool_call` вызова `agent` при реплее |
| `ToolCallProgress(agent)` | `tool_call_update` с одним текстовым блоком строки прогресса, заменяющим предыдущий |
| `ToolCallFinished(agent)` | `tool_call_update` со `status` и телом отчёта без обёртки `<subagent-report>` и без ограды; всегда — `_meta.codelab.subagent: {"id", "summary": {"toolCalls", "tokens": {"input", "output"}, "durationMs"}}` из `SubagentReport` (с потомками, D24); при `failed` — ещё `failure` |
| `SubagentStarted`, `SubagentProgress`, `SubagentFinished` | не отправляются; логи `subagent.start`, `subagent.end` |
| `SubagentActivity` | клиенту без `subagentToolCalls` — не отправляется (SUB-12); клиенту с ним — требование «Шаги потомков деревом» |

`AcpPermissionGate` для запроса потомка SHALL отправлять `session/request_permission` с `sessionId` корневой сессии, `toolCall.toolCallId` — цепочкой, `title` с префиксом и `toolCall._meta.codelab.subagent` с полями `id`, `type`, `description`, `depth`, `path`, `parentToolCallId`. Пометка `critical` сохраняется в том же `_meta.codelab`.

Данные `_meta.codelab.task` и `_meta.codelab.subagent` SHALL отправляться независимо от объявления клиента в `initialize`.

#### Scenario: Список задач в ходе
- **WHEN** модель вызывает `task_create` три раза, затем `task_update` первого пункта в `completed`, затем `task_list`
- **THEN** клиент получает четыре `plan`, каждый со всем списком на момент операции и `_meta.codelab.task.id` у каждой entry; после `task_list` нового `plan` нет (фикстура `acp/prompt-task-plan`)

#### Scenario: Список новой ветки
- **WHEN** ядро публикует `TaskListChanged` с `op: restore` и пустым списком, затем — с `op: restore` и пунктами `#1`, `#4`
- **THEN** клиент получает `plan` с `entries: []`, затем `plan` с двумя entries и `_meta.codelab.task.id` `"1"`, `"4"` (`acp_projection_exhaustive_test.dart`)

#### Scenario: Вызов agent
- **WHEN** модель вызывает `agent` с типом `explore`, ребёнок делает три вызова и сдаёт отчёт
- **THEN** клиент получает `tool_call` с `kind: think`, title `Subagent explore: …` и `_meta.codelab.subagent` с `id` вида `sub_…` и `type: "explore"`, `in_progress`, хотя бы одну строку прогресса и `completed` с телом отчёта; ни одного `tool_call` с id вызова ребёнка (фикстура `acp/prompt-subagent-tool-call`)

#### Scenario: Итог субагента
- **WHEN** ребёнок `explore` сделал 4 вызова, потратил 15 200 входных и 3 000 выходных токенов за 48 с, затем завершился; во втором варианте ход отменён во время работы ребёнка
- **THEN** финальный `tool_call_update` вызова `agent` содержит `_meta.codelab.subagent.summary` `{"toolCalls": 4, "tokens": {"input": 15200, "output": 3000}, "durationMs": 48000}`; во втором варианте — `status: failed`, `_meta.codelab.outcome: "cancelled"` и `summary` с фактическими значениями; при `session/load` реплей вызова `agent` несёт тот же `summary` из итоговой записи `subagent`

#### Scenario: Запрос разрешения ребёнка
- **WHEN** ребёнок `review` просит `exec git diff --stat`, клиент отвечает `reject_once`
- **THEN** кадр `session/request_permission` содержит `sessionId` корня, `toolCallId` `call_1/call_1`, title `[review: …] …` и `_meta.codelab.subagent` с `depth: 1` и `parentToolCallId: "call_1"`; ребёнок продолжает и сдаёт отчёт (фикстура `acp/prompt-subagent-permission`)

#### Scenario: Запрос разрешения внука
- **WHEN** внук глубины 2 просит `exec`
- **THEN** `toolCallId` состоит из трёх сегментов, `_meta.codelab.subagent.depth` — 2, `path` — id ребёнка, `parentToolCallId` — вызов `agent` корня (фикстура `acp/prompt-subagent-nested-permission`)

### Requirement: Шаги потомков деревом
Клиенту, объявившему `clientCapabilities._meta.codelab.subagentToolCalls`, адаптер SHALL отправлять вызовы потомков любой глубины (этап 2, решение пользователя 2026-11-10; design.md change `add-subagents-and-tasks`, D21; §17.3.7):
- `SubagentActivity` с `ToolCallStarted` → `tool_call`; с `ToolCallProgress` → `tool_call_update` с `content`; с `ToolCallFinished` → `tool_call_update` с итоговым `status`, `content`, `diff` и `_meta.codelab.outcome` — по тем же правилам, что у вызовов корня;
- `toolCallId` — цепочка через `/` от вызова `agent` корня (тот же id, что у запроса разрешения этого вызова, SUB-3);
- каждый такой кадр SHALL нести `_meta.codelab.parentToolCallId` — `toolCallId` на проводе вызова `agent`, запустившего потомка;
- текст, мысли и прочие события потомков НЕ SHALL отправляться.

Когда вызов `agent` становится терминальным, адаптер SHALL отправить `tool_call_update` со `status: failed` и `_meta.codelab.outcome: "cancelled"` для каждого ещё не завершённого вызова его поддерева, до `tool_call_update` самого вызова `agent`.

При `session/load` такому клиенту реплей SHALL сразу после кадра `tool_call` вызова `agent` проигрывать вызовы потомков из их журналов (по записям `subagent`, рекурсивно) с итоговыми статусами и теми же `toolCallId` и `_meta.codelab.parentToolCallId`. Клиенту без `subagentToolCalls` ни вживую, ни при реплее вызовы потомков НЕ SHALL отправляться (SUB-12).

#### Scenario: Вызовы ребёнка и внука
- **WHEN** клиент объявил `subagentToolCalls`, ребёнок `general` вызывает `read`, затем запускает внука, внук вызывает `ls`
- **THEN** клиент получает `tool_call` `call_1/call_1` (`read`) с `parentToolCallId: "call_1"`, `tool_call` `call_1/call_2` (`agent`) с `parentToolCallId: "call_1"` и `_meta.codelab.subagent` `{id, type}` внука (как у вызова `agent` корня, D28; Q16) и `tool_call` `call_1/call_2/call_1` (`ls`) с `parentToolCallId: "call_1/call_2"`; текстов потомков нет (фикстура `acp/prompt-subagent-tool-tree`)

#### Scenario: Запрос разрешения в строке своего вызова
- **WHEN** клиент объявил `subagentToolCalls`, ребёнок вызывает `exec`, требующий вопроса
- **THEN** `tool_call` с id `call_1/call_1` приходит раньше `session/request_permission` с тем же `toolCall.toolCallId`

#### Scenario: Клиент без согласия
- **WHEN** тот же сценарий проигрывается клиенту без `clientCapabilities._meta.codelab.subagentToolCalls`
- **THEN** кадров `tool_call` с id потомков нет, кадры совпадают с `acp/prompt-subagent-tool-call`

#### Scenario: Висящие вызовы при отмене
- **WHEN** ход отменён, а ребёнок не завершил `exec` в пределах `cancel_grace`
- **THEN** до `tool_call_update` вызова `agent` клиент получает `tool_call_update` вызова `exec` ребёнка со `status: failed` и `_meta.codelab.outcome: "cancelled"`; поздних кадров этого вызова после него нет

#### Scenario: Реплей дерева
- **WHEN** сессия с вызовом `agent`, у ребёнка которого два вызова, загружается клиентом с `subagentToolCalls`
- **THEN** после `tool_call` вызова `agent` идут два `tool_call` ребёнка с итоговыми статусами и `parentToolCallId` (фикстура `acp/session-load-subagent-tool-tree`); клиент без согласия их не получает

