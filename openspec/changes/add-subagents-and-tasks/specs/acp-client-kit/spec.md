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

Ответ на такой запрос SHALL идти тем же `SessionHandle.respond` и только в этот запрос (PERM-4). Сведения о субагенте SHALL оставаться у строки вызова после решения.

Строка вызова `agent` (`kind: think`) SHALL показывать в `ToolRowView`:
- заголовок агента как деталь;
- последнюю строку прогресса из `content`, пока вызов идёт;
- текст отчёта как текстовый вывод после завершения.

#### Scenario: Запрос ребёнка
- **WHEN** агент присылает `session/request_permission` с `toolCall.toolCallId: "call_3/call_1"` и `_meta.codelab.subagent: {"id": "sub_a1", "agent": "review", "description": "Check the diff", "depth": 1, "path": [], "parentToolCallId": "call_3"}`
- **THEN** `PendingApprovalView.subagent` — `review`, `Check the diff`, глубина 1, `parentToolCallId: "call_3"`; ответ уходит с id этого запроса

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
`ToolCallView` вызова `agent` SHALL получать `subagentSummary` (`toolCalls`, `inputTokens`, `outputTokens`, `duration`) из `_meta.codelab.subagent.summary` финального обновления (design.md change `add-subagents-and-tasks`, D24). Отсутствие, неверная форма или неизвестные ключи SHALL давать `null` или игнорироваться без отказа обработки. Kit SHALL давать готовую строку итога `N tool calls · N.Nk tokens · <время>` (токены — `input + output`, `k` с одним знаком; время — `48s`, `2m 05s`, `1h 02m`).

Для работающего вызова `agent` с потомками в дереве (acp-client-kit «Дерево вызовов потомков») `SessionView` SHALL давать «хвост» (D25): три последних по времени вызова его поддерева в порядке прихода и `moreCount` — число остальных вызовов поддерева. Без вызовов потомков хвост пуст, и представление показывает строку прогресса.

#### Scenario: Итог в представлении
- **WHEN** финальный `tool_call_update` вызова `agent` несёт `summary` `{"toolCalls": 4, "tokens": {"input": 15200, "output": 3000}, "durationMs": 48000, "future": 1}`
- **THEN** строка итога — `4 tool calls · 18.2k tokens · 48s`, неизвестный ключ проигнорирован

#### Scenario: Сторонний агент без итога
- **WHEN** вызов `agent` завершается без `_meta.codelab.subagent.summary`
- **THEN** `subagentSummary == null`, строки итога нет

#### Scenario: Хвост из пяти вызовов
- **WHEN** у работающего вызова `agent` пять вызовов потомков
- **THEN** хвост — три последних, `moreCount` — 2
