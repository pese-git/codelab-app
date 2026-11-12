## ADDED Requirements

### Requirement: Метаданные пунктов плана
`PlanEntryView` SHALL получать из `_meta.codelab.task` entry `plan` необязательные поля `taskId` (строка), `owner` (строка) и `blockedBy` (список строк) (design.md change `add-subagents-and-tasks`, D15). Отсутствие `_meta`, неверный тип поля или неизвестные ключи SHALL давать `null` (или пустой список) для этого поля без отказа обработки обновления. Каждое обновление `plan` по-прежнему SHALL заменять план целиком (требование «Публикация представлений сессии»).

`SessionView` SHALL давать представлению для каждого пункта:
- список незавершённых блокеров — id из `blockedBy`, чьи пункты в текущем плане не `completed`;
- метку владельца-субагента — `type` из известного kit сведения о субагенте с этим id (`SubagentRequester`), иначе сам id; для `owner: main` и без `owner` метки нет.

#### Scenario: План с метаданными
- **WHEN** агент присылает `plan`, где у второй entry `_meta.codelab.task: {"id": "2", "owner": "sub_a1", "blockedBy": ["1"]}`, а первая entry `pending`
- **THEN** `PlanEntryView` второго пункта имеет `taskId: "2"`, `owner: "sub_a1"`, незавершённый блокер `1`

#### Scenario: План стороннего агента
- **WHEN** агент присылает `plan` без `_meta` (фикстура `acp/prompt-update-plan`, роль `client`)
- **THEN** `SessionView.plan` содержит пункты с `taskId == null`, показ прежний

#### Scenario: Неверная форма метаданных
- **WHEN** у entry `_meta.codelab.task` — `{"id": 5, "blockedBy": "1"}`
- **THEN** обновление применяется, `taskId` и `blockedBy` пустые, ошибки нет

### Requirement: Запрос одобрения от субагента
`PendingApprovalView` и `ToolCallView` вызова, объявленного только запросом `session/request_permission`, SHALL получать поле `subagent` (`SubagentRequester`: `id`, `type`, `description`, `depth`, `parentToolCallId`) из `toolCall._meta.codelab.subagent` запроса (design.md, D15). Поле нужно, чтобы показать, кто спрашивает. Нет или неверная форма → `null`, запрос показывается как обычный. `toolCallId` с `/` SHALL оставаться непрозрачной строкой: kit его не разбирает.

`SubagentRequester` SHALL давать `pathTypes` — типы цепочки от ребёнка корня до спрашивающего (D27): первый — `type` из `rawInput` вызова `agent` с id `parentToolCallId`, последний — `type` спрашивающего, промежуточные — `type` вызовов `agent`, найденных подъёмом по `parentToolCallId` в дереве вызовов (этап 2); звено, которое kit не знает (нет дерева), — `…`. Длина пути равна `depth`. Kit SHALL давать строку пути `review › explore` для представлений.

Ответ на такой запрос SHALL идти тем же `SessionHandle.respond` и только в этот запрос (PERM-4). Сведения о субагенте SHALL оставаться у строки вызова после решения.

Строка вызова `agent` (`kind: think`) SHALL показывать в `ToolRowView`:
- заголовок агента как деталь;
- последнюю строку прогресса из `content`, пока вызов идёт;
- текст отчёта как текстовый вывод после завершения.

#### Scenario: Запрос ребёнка
- **WHEN** агент присылает `session/request_permission` с `toolCall.toolCallId: "call_3/call_1"` и `_meta.codelab.subagent: {"id": "sub_a1", "type": "review", "description": "Check the diff", "depth": 1, "path": [], "parentToolCallId": "call_3"}`
- **THEN** `PendingApprovalView.subagent` — `review`, `Check the diff`, глубина 1, `parentToolCallId: "call_3"`, путь `review`; ответ уходит с id этого запроса

#### Scenario: Путь внука без дерева
- **WHEN** клиент без `subagentToolCalls` получает запрос внука `explore` (`depth: 2`, `parentToolCallId` — вызов `agent` корня с `rawInput.type: "review"`)
- **THEN** путь — `review › explore`; при `depth: 3` без дерева — `review › … › explore`

#### Scenario: Запрос без сведений о субагенте
- **WHEN** запрос несёт `toolCallId` с `/`, но без `_meta.codelab.subagent`
- **THEN** `subagent == null`, запрос показывается и решается как обычный

### Requirement: Дерево вызовов потомков
`ToolCallView` SHALL получать необязательное `parentToolCallId` из `_meta.codelab.parentToolCallId` кадров `tool_call` и `tool_call_update` (этап 2; design.md change `add-subagents-and-tasks`, D21). `SessionView` SHALL давать представлению дерево: вызовы с `parentToolCallId` — дети вызова с этим id в том же ходе, в порядке прихода; вызов, чей родитель неизвестен, SHALL показываться на верхнем уровне, а не теряться. Неверная форма поля → `null`.

Ожидающее одобрение вызова потомка SHALL оставаться привязанным к его `toolCallId` (PERM-4); путь от корня до такого вызова SHALL быть доступен представлению, чтобы раскрыть его. Повтор кадров реплея и живого хода SHALL не дублировать детей (идемпотентность по `toolCallId`, `AGENTS.md` §9).

#### Scenario: Вложенность по parentToolCallId
- **WHEN** агент присылает `tool_call` `call_1` (`agent`), затем `call_1/call_1` и `call_1/call_2/call_1` с `parentToolCallId` `call_1` и `call_1/call_2`, причём `call_1/call_2` пришёл раньше своего ребёнка
- **THEN** дерево: `call_1` → [`call_1/call_1`, `call_1/call_2` → [`call_1/call_2/call_1`]]

#### Scenario: Неизвестный родитель
- **WHEN** приходит `tool_call` с `parentToolCallId: "call_9"`, которого в ходе нет
- **THEN** вызов показывается на верхнем уровне, ошибки нет

#### Scenario: Реплей без дублей
- **WHEN** сессия с деревом вызовов загружается дважды подряд в один `ClientWorkspace`
- **THEN** у каждого вызова `agent` ровно столько детей, сколько в журнале

### Requirement: Итог и хвост субагента
Вызов SHALL считаться вызовом `agent` с первого кадра, если его `tool_call` несёт `_meta.codelab.subagent` (`ToolCallView.subagentCall`: `id`, `type`; D28). Отсутствие поля, неверная форма или неизвестные ключи SHALL давать `null` без отказа; такой вызов (сторонний агент) — обычный вызов `think`.

`ToolCallView` вызова `agent` SHALL получать `subagentSummary` (`toolCalls`, `inputTokens`, `outputTokens`, `duration`) из `_meta.codelab.subagent.summary` финального обновления (design.md change `add-subagents-and-tasks`, D24). Отсутствие, неверная форма или неизвестные ключи SHALL давать `null` или игнорироваться без отказа обработки. Kit SHALL давать готовую строку итога `N tool calls · N.Nk tokens · <время>` и её сокращённый вид для свёрнутой строки `N tool calls · N.Nk · <время>` (D27) (токены — `input + output`, `k` с одним знаком; время — `48s`, `2m 05s`, `1h 02m`).

Для работающего вызова `agent` с потомками в дереве (acp-client-kit «Дерево вызовов потомков») `SessionView` SHALL давать «хвост» (D25): три последних по времени вызова его поддерева в порядке прихода и `moreCount` — число остальных вызовов поддерева. Токенов в хвосте нет: kit НЕ SHALL разбирать строку прогресса; токены даёт только `subagentSummary` завершённого вызова (D24, D25, Q15). Без вызовов потомков хвост пуст, и представление показывает строку прогресса.

#### Scenario: Вызов agent с первого кадра
- **WHEN** приходит `tool_call` с `kind: think` и `_meta.codelab.subagent: {"id": "sub_a1", "type": "explore", "x": 1}`, потомков и запросов ещё нет
- **THEN** `subagentCall` — `sub_a1`, `explore`; неизвестный ключ проигнорирован; тот же кадр без `_meta` даёт `subagentCall == null`

#### Scenario: Итог в представлении
- **WHEN** финальный `tool_call_update` вызова `agent` несёт `summary` `{"toolCalls": 4, "tokens": {"input": 15200, "output": 3000}, "durationMs": 48000, "future": 1}`
- **THEN** строка итога — `4 tool calls · 18.2k tokens · 48s`, неизвестный ключ проигнорирован

#### Scenario: Сторонний агент без итога
- **WHEN** вызов `agent` завершается без `_meta.codelab.subagent.summary`
- **THEN** `subagentSummary == null`, строки итога нет

#### Scenario: Хвост из пяти вызовов
- **WHEN** у работающего вызова `agent` пять вызовов потомков
- **THEN** хвост — три последних, `moreCount` — 2, токенов у хвоста нет, даже если строка прогресса их содержит

### Requirement: Операции со списком задач в ленте
Kit SHALL распознавать вызов операции со списком задач только по ключу `plan._meta.codelab.taskChange` (design.md, D35), без разбора текста, заголовка и порядка кадров: вызов корневого уровня (без `parentToolCallId`) вида `think`, без `_meta.codelab.subagent`, завершившийся `completed`, на который ссылается `taskChange.toolCallId` хотя бы одного `plan`. Такой вызов SHALL становиться в транскрипте элементом `TaskOpsItem` с изменением из ключей: добавленные id (`op: create`), удалённые (`op: delete` и `deleted`), ставшие `completed` (`op: update`, пункт `completed` в этом `plan` и не `completed` в предыдущем плане сессии) и прочие изменённые id (`changed`). Подряд идущие `TaskOpsItem` без других элементов транскрипта между ними SHALL сливаться в один (изменения объединяются).

`plan` без `taskChange` (сторонний или старый агент, реплей) и `taskChange` без `toolCallId` (`restore`, `assign`) SHALL только обновлять план сессии; вызовы при этом остаются обычными `ToolCallView`. Запасного распознавания по сравнению планов или по статусу вызова в момент прихода `plan` НЕ SHALL быть. Неизвестные ключи и значения `taskChange` SHALL игнорироваться; ключ неверной формы — как отсутствующий.

Kit SHALL давать текст элемента: «Task #3 added to the plan» / «Tasks #1–#4 added to the plan» (подряд идущие id — диапазоном, иначе списком `#1, #3`), «Task #2 done», «Task #2 removed», «Task #2 updated»; части объединяются через `; `.

Вызов `failed` и вызов, на который не ссылается ни один `taskChange` (чтение `task_list`, `task_get`; план стороннего агента), SHALL оставаться обычным `ToolCallView`.

После `session/load` прошлые вызовы `task_*` приходят реплеем завершёнными `tool_call`, а план — одним `plan` после истории без `taskChange` (agent-acp-server «Реплей плана без taskChange»). Поэтому в реплее они SHALL показываться обычными строками вызовов, а не `TaskOpsItem`: это ожидаемо, текущий список виден по `plan` в хвосте.

#### Scenario: Слияние созданий
- **WHEN** четыре вызова `think` подряд, на каждый ссылается `plan` с `taskChange` `{op: create, toolCallId: <id вызова>, changed: [<новый id>]}` (`#1`…`#4`), все `completed`
- **THEN** транскрипт содержит один `TaskOpsItem` с текстом «Tasks #1–#4 added to the plan»

#### Scenario: Отклонённая операция
- **WHEN** вызов `think` завершился `failed`, ни один `plan` на него не ссылается
- **THEN** вызов — обычный `ToolCallView` со статусом `failed`

#### Scenario: Параллельный пакет с чтением между операциями
- **WHEN** ответ модели — пакет `[task_create, read, task_create]` с id `c1`, `r1`, `c2`; `plan` с `taskChange {op: create, toolCallId: "c2", changed: ["2"]}` приходит раньше `plan` для `c1` (`changed: ["1"]`); все три вызова `completed`
- **THEN** транскрипт — `TaskOpsItem` «Task #1 added to the plan», строка `read`, `TaskOpsItem` «Task #2 added to the plan»: каждый `plan` отнесён к своему вызову по ключу независимо от порядка кадров, `read` разделяет элементы, слияния нет

#### Scenario: task_list в пакете не операция
- **WHEN** пакет `[task_create, task_list]`; `plan` с `taskChange.toolCallId` вызова `task_create` приходит, пока оба вызова `in_progress`
- **THEN** `task_create` — `TaskOpsItem` «Task #1 added to the plan», `task_list` — обычный `ToolCallView`

#### Scenario: plan без taskChange
- **WHEN** агент CodeLab старой версии присылает вызов `think` и во время него `plan` с `_meta.codelab.task`, но без `taskChange`
- **THEN** план сессии обновлён, вызов — обычный `ToolCallView`, `TaskOpsItem` нет

#### Scenario: restore без toolCallId
- **WHEN** во время хода приходит `plan` с `taskChange {op: restore, actor: main}` без `toolCallId`, пока вызов `think` в `in_progress`
- **THEN** план сессии заменён, вызов после `completed` — обычный `ToolCallView`

#### Scenario: Реплей прошлых операций
- **WHEN** `session/load` проигрывает три завершённых вызова `task_create`, затем один `plan` со списком `#1`–`#3` без `taskChange`
- **THEN** три вызова — обычные строки `ToolCallView`, `TaskOpsItem` нет; план сессии — `#1`–`#3`

#### Scenario: Сторонний агент
- **WHEN** агент без `_meta.codelab.task` присылает вызов `think` и `plan` во время него
- **THEN** вызов — обычный `ToolCallView`, план показывается как прежде


### Requirement: Список субагентов сессии
`SessionView.subagents` SHALL давать список субагентов сессии для панели Agents v1 (решение пользователя 2026-11-12, Q13; design.md change `add-subagents-and-tasks`, D33): по одной строке `SubagentRowView` на каждый вызов сессии с `ToolCallView.subagentCall` (требование «Итог и хвост субагента»), за все ходы, включая вызовы потомков из дерева (требование «Дерево вызовов потомков») и вызовы, проигранные `session/load`. Порядок — обход в глубину в порядке прихода: строки потомков стоят под строкой своего родительского вызова `agent`. Вызов без `subagentCall` (сторонний агент) строки НЕ SHALL давать.

Строка SHALL содержать:
- `toolCallId` вызова на проводе (ключ строки), id и `type` субагента, заголовок — `rawInput.description`, а без него — `title` вызова как есть;
- состояние `running`, `awaitingApproval`, `completed`, `failed` или `cancelled`: терминальные — по статусу вызова `agent`, как у его строки в ленте; `awaitingApproval` — если есть ожидающее одобрение этой строки (ниже); иначе `running`;
- время: у терминальной строки — `duration` из `subagentSummary`; у работающей — `startedAt`, момент, когда kit впервые увидел `tool_call` вызова, по часам, внедрённым в `ClientWorkspace` (повтор кадра его не сдвигает); у терминальной строки без `subagentSummary` времени нет. Kit SHALL давать формат длительности тот же, что у строки итога (`48s`, `2m 05s`, `1h 02m`);
- число вызовов инструментов: у терминальной строки — `subagentSummary.toolCalls`, у работающей — число вызовов её поддерева в дереве; токены `input + output` — только из `subagentSummary`;
- последнее действие: у работающей строки — `title` последнего пришедшего вызова её поддерева, у `failed` — `_meta.codelab.subagent.failure`; иначе нет;
- глубину: 1 для вызова без `parentToolCallId` или с неизвестным родителем, иначе глубина строки-родителя плюс 1;
- id пунктов плана, у которых `PlanEntryView.owner` — id этого субагента, и id из `rawInput.task`;
- `approvalId` ожидающего одобрения, у которого `PendingApprovalView.subagent.id` — id этого субагента; если строки с таким id нет, одобрение SHALL относиться к строке корневого уровня с `toolCallId`, равным `subagent.parentToolCallId`.

`SessionView` SHALL давать счётчики строк по состояниям.

Kit НЕ SHALL разбирать `title`, строку прогресса и текст отчёта: состояния `queued` и `waiting`, шаги и токены работающего субагента в строке НЕ SHALL появляться (D33). Отсутствие или неверная форма любого источника SHALL давать пустое поле, а не отказ обработки обновления.

Список SHALL быть функцией транскрипта, ожидающих одобрений и плана сессии: повтор кадров, реплей и повторная загрузка сессии SHALL давать тот же список без дублей (идемпотентность по `toolCallId`, `AGENTS.md` §9). Кадр вызова `agent`, пришедший после его терминального статуса, НЕ SHALL возвращать строку в `running` (поздние события).

#### Scenario: Строки ребёнка и внука
- **WHEN** клиент с `subagentToolCalls` получает `tool_call` `call_1` (`agent`, `_meta.codelab.subagent: {"id": "sub_a1", "type": "review"}`, `rawInput.description: "Check the diff"`), затем `call_1/call_1` (`read`) и `call_1/call_2` (`agent`, `sub_b2`, `explore`) с `parentToolCallId: "call_1"`, затем `call_1/call_2/call_1` (`ls`) с `parentToolCallId: "call_1/call_2"`
- **THEN** `SessionView.subagents` — две строки: `sub_a1` `review` «Check the diff» глубины 1, `running`, 3 вызова поддерева, последнее действие — `title` вызова `ls`; под ней `sub_b2` `explore` глубины 2, `running`, 1 вызов

#### Scenario: Итог завершённого субагента
- **WHEN** вызов `agent` `sub_a1` завершается `completed` с `summary` `{"toolCalls": 4, "tokens": {"input": 15200, "output": 3000}, "durationMs": 48000}`
- **THEN** строка — `completed`, 4 вызова, 18.2k токенов, 48s, последнего действия нет; счётчик `completed` равен 1

#### Scenario: Отмена и отказ
- **WHEN** один вызов `agent` завершается `failed` с `_meta.codelab.subagent.failure: "budget_exceeded:max_steps"`, другой — `failed` с `_meta.codelab.outcome: "cancelled"`
- **THEN** первая строка — `failed` с последним действием `budget_exceeded:max_steps`, вторая — `cancelled`

#### Scenario: Ожидание одобрения потомка
- **WHEN** у работающего `sub_b2` (внук) ожидает ответа `session/request_permission` с `_meta.codelab.subagent.id: "sub_b2"`
- **THEN** строка `sub_b2` — `awaitingApproval` с `approvalId` этого запроса, строка `sub_a1` остаётся `running`; после ответа пользователя строка `sub_b2` снова `running`

#### Scenario: Одобрение без дерева
- **WHEN** клиент без вызовов потомков получает запрос внука `sub_b2` с `parentToolCallId: "call_1"`, а строки `sub_b2` нет
- **THEN** `awaitingApproval` с `approvalId` этого запроса получает строка `call_1`

#### Scenario: Пункты списка у субагента
- **WHEN** план содержит `#2` с `_meta.codelab.task.owner: "sub_a1"`, а `rawInput.task` вызова `sub_a1` — `"2"`
- **THEN** строка `sub_a1` несёт один пункт `2`

#### Scenario: Реплей без дублей в списке
- **WHEN** сессия с двумя вызовами `agent`, у одного из которых вызов `agent` потомка, загружается дважды подряд в один `ClientWorkspace`
- **THEN** `SessionView.subagents` — ровно три строки, все терминальные, со временем и вызовами из `summary`

#### Scenario: Поздний кадр после завершения
- **WHEN** после `tool_call_update` `completed` вызова `agent` приходит ещё один `tool_call_update` того же `toolCallId` со `status: in_progress`
- **THEN** строка остаётся `completed`

#### Scenario: Время работающего субагента
- **WHEN** часы `ClientWorkspace` показывают `10:00:00`, когда приходит `tool_call` вызова `agent`, и `10:00:30`, когда тот же `tool_call` приходит повторно
- **THEN** `startedAt` строки — `10:00:00`, формат длительности для 41 с — `41s`; после завершения с `summary.durationMs: 48000` время строки — 48s из `summary`

#### Scenario: Сторонний агент без признака
- **WHEN** агент присылает вызов `think` с заголовком «Subagent explore: …» без `_meta.codelab.subagent`
- **THEN** `SessionView.subagents` пуст
