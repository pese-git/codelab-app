## ADDED Requirements

### Requirement: Метаданные пунктов плана
`PlanEntryView` SHALL получать из `_meta.codelab.task` entry `plan` необязательные поля `taskId` (строка), `owner` (строка) и `blockedBy` (список строк) (design.md change `add-subagents-and-tasks`, D15). Отсутствие `_meta`, неверный тип поля или неизвестные ключи SHALL давать `null` (или пустой список) для этого поля без отказа обработки обновления. Каждое обновление `plan` по-прежнему SHALL заменять план целиком (требование «Публикация представлений сессии»).

`SessionView` SHALL давать представлению для каждого пункта:
- список незавершённых блокеров — id из `blockedBy`, чьи пункты в текущем плане не `completed`;
- метку владельца-субагента — `agent` из известного kit сведения о субагенте с этим id (`SubagentRequester`), иначе сам id; для `owner: main` и без `owner` метки нет.

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
`PendingApprovalView` и `ToolCallView` вызова, объявленного только запросом `session/request_permission`, SHALL получать поле `subagent` (`SubagentRequester`: `id`, `agent`, `description`, `depth`, `parentToolCallId`) из `toolCall._meta.codelab.subagent` запроса (design.md, D15). Поле нужно, чтобы показать, кто спрашивает. Нет или неверная форма → `null`, запрос показывается как обычный. `toolCallId` с `/` SHALL оставаться непрозрачной строкой: kit его не разбирает.

`SubagentRequester` SHALL давать `pathTypes` — типы цепочки от ребёнка корня до спрашивающего (D27): первый — `type` из `rawInput` вызова `agent` с id `parentToolCallId`, последний — `agent` спрашивающего, промежуточные — `type` вызовов `agent`, найденных подъёмом по `parentToolCallId` в дереве вызовов (этап 2); звено, которое kit не знает (нет дерева), — `…`. Длина пути равна `depth`. Kit SHALL давать строку пути `review › explore` для представлений.

Ответ на такой запрос SHALL идти тем же `SessionHandle.respond` и только в этот запрос (PERM-4). Сведения о субагенте SHALL оставаться у строки вызова после решения.

Строка вызова `agent` (`kind: think`) SHALL показывать в `ToolRowView`:
- заголовок агента как деталь;
- последнюю строку прогресса из `content`, пока вызов идёт;
- текст отчёта как текстовый вывод после завершения.

#### Scenario: Запрос ребёнка
- **WHEN** агент присылает `session/request_permission` с `toolCall.toolCallId: "call_3/call_1"` и `_meta.codelab.subagent: {"id": "sub_a1", "agent": "review", "description": "Check the diff", "depth": 1, "path": [], "parentToolCallId": "call_3"}`
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

Для работающего вызова `agent` с потомками в дереве (acp-client-kit «Дерево вызовов потомков») `SessionView` SHALL давать «хвост» (D25): три последних по времени вызова его поддерева в порядке прихода и `moreCount` — число остальных вызовов поддерева. Без вызовов потомков хвост пуст, и представление показывает строку прогресса.

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
- **THEN** хвост — три последних, `moreCount` — 2

### Requirement: Операции со списком задач в ленте
Kit SHALL распознавать вызов операции со списком задач по уже имеющимся данным, без разбора текста и заголовка (D27): вызов `kind: think`, завершившийся `completed`, без `_meta.codelab.subagent` (ни в первом кадре, ни в финальном) и без вызовов-потомков, во время которого (между его `tool_call` и финальным обновлением) пришёл `plan` с `_meta.codelab.task`. Такой вызов SHALL становиться в транскрипте элементом `TaskOpsItem` с изменением списка — разницей планов до и после: добавленные id, id, ставшие `completed`, удалённые id и прочие изменённые id. Подряд идущие `TaskOpsItem` без других элементов транскрипта между ними SHALL сливаться в один (разницы объединяются).

Kit SHALL давать текст элемента: «Task #3 added to the plan» / «Tasks #1–#4 added to the plan» (подряд идущие id — диапазоном, иначе списком `#1, #3`), «Task #2 done», «Task #2 removed», «Task #2 updated»; части объединяются через `; `.

Вызов `failed` или без пришедшего `plan` (чтение `task_list`, `task_get`; план стороннего агента без `_meta`) SHALL оставаться обычным `ToolCallView`.

#### Scenario: Слияние созданий
- **WHEN** четыре вызова `think` подряд, во время каждого приходит `plan` с новым пунктом (`#1`…`#4`), все `completed`
- **THEN** транскрипт содержит один `TaskOpsItem` с текстом «Tasks #1–#4 added to the plan»

#### Scenario: Отклонённая операция
- **WHEN** вызов `think` завершился `failed`, `plan` во время него не приходил
- **THEN** вызов — обычный `ToolCallView` со статусом `failed`

#### Scenario: Сторонний агент
- **WHEN** агент без `_meta.codelab.task` присылает вызов `think` и `plan` во время него
- **THEN** вызов — обычный `ToolCallView`, план показывается как прежде

