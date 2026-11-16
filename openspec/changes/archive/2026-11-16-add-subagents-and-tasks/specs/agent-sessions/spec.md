## MODIFIED Requirements

### Requirement: Формат журнала JSONL
Журнал сессии SHALL быть UTF-8 файлом: одна JSON-запись на строку, разделитель `\n` (§8.2 документа ядра). Пустые строки при чтении пропускаются; логическая структура задаётся `parentId`, а не позицией строки.

Первая строка SHALL быть заголовком `{"type":"session","version":1,...}` с полями `id`, `cwd`, `created`, `agent` и необязательными `metadata` (§8.2.1) и `parent` у журнала субагента: `sessionId` прямого родителя, `rootSessionId`, `toolCallId`, `subagentId`, `agent`, `depth` (§17.3.6). Заголовок не входит в дерево.

Записи:
- `message` с сообщением в канонической JSON-форме §2.2 и полями записи `outcome`, `diff`, `toolMeta`, `origin`;
- `model_change`, `mode_change`, `config_change`, `compaction`, `label`, `leaf`, `session_info`, `custom` (§8.2.4);
- `task` — операция над списком задач: `op`, `actor`, `items` (полные снимки изменённых пунктов), `deleted` (§17.16.6);
- `subagent` — связь с журналом ребёнка: `subagentId`, `toolCallId`, `agent`, `description`, `childSessionId`, `journal`, `status`, `failure`, `report`, `usage`, `toolCalls`, `durationMs` (§17.3.6);
- `plan` — запись старого формата: новые журналы её не пишут, читатель SHALL её понимать всегда.

Поля записи (`outcome`, `diff`, `toolMeta`, `origin` и сопутствующие) SHALL лежать на верхнем уровне объекта рядом с общими полями и НЕ SHALL попадать в сообщение, которое видит модель. Записи `task`, `subagent`, `plan` в контекст модели не входят.

Читатель SHALL:
- игнорировать неизвестные поля заголовка известной версии;
- сохранять неизвестные поля известной записи в `extra` и записывать их обратно при копировании;
- читать запись неизвестного `type` как `CustomRecord("unknown:<type>")` с исходным объектом (design.md change `add-agent-core-sessions-and-compaction`, D2).

Решения «разрешить всегда», частичные снимки ответа, дельты, `ToolCallProgress`, `SubagentProgress` и `SubagentActivity` НЕ SHALL попадать в журнал.

#### Scenario: Golden-разбор
- **WHEN** `parseSessionLines` разбирает фикстуры `test/fixtures/sessions/all_records.jsonl` (журнал корневой сессии: каждая запись, включая `task`, `subagent` и `plan`) и `test/fixtures/sessions/child_journal_header.jsonl` (журнал ребёнка: заголовок с `parent`)
- **THEN** заголовок и каждая запись обеих фикстур разобраны в свой тип, `toJson` каждой побайтово равен исходной строке

#### Scenario: Неизвестный тип записи
- **WHEN** в журнале встречается строка с `"type":"branch"`
- **THEN** она читается как `CustomRecord("unknown:branch")`, не участвует в проекциях и пишется обратно без изменений

### Requirement: Запись журнала из событий
`SessionWriter` SHALL быть первым подписчиком `Agent` сессии и писать журнал по таблице §8.3 (design.md change `add-agent-core-sessions-and-compaction`, D2, D4; change `add-subagents-and-tasks`, D7, D12, D29):

| Событие | Запись | `durable` |
|---|---|---|
| `MessageEnded` (user, assistant) | `message`; у служебных сообщений — `origin` из `MessageStarted.origin` | нет |
| `MessageEnded` (toolResult) | `message` с `outcome`, `diff`, `toolMeta` вызова | да |
| `ModeChanged` | `mode_change` | нет |
| `TaskListChanged` | `task` из `change` (только в журнале корневой сессии); при `change.op == restore` — ничего: состояние выводится из ветки (TSK-1) | нет |
| `SubagentStarted` | `subagent` со `status: running` | да |
| `SubagentFinished` | итоговая `subagent` со `status`, `failure`, `report`, `usage` | да |
| `SubagentProgress`, `SubagentActivity` | ничего | — |
| `ContextCompacted` | `compaction` пишется компактором до события | да |
| `SessionTitleChanged` | `session_info` | нет |
| `TurnEnded` | ничего; сброс последней записи хода | да |

Каждое сообщение транскрипта SHALL быть записано до перехода цикла к следующему действию (SES-8). Результат каждого инструмента SHALL быть записан с `durable` до следующего запроса к модели (SES-9). Итоговая запись `subagent` SHALL быть записана до `ToolCallFinished(agent)` (SUB-10). Индекс снимка в памяти обновляется только после успешной записи.

Ошибка записи SHALL давать лог `session.append.failed`, `AgentError(cls: storage, retrying: false)` и `TurnEnded(failed)`: ход, который нельзя сохранить, не продолжается (design.md change `add-agent-core-sessions-and-compaction`, D4).

#### Scenario: Побайтово одинаковый журнал
- **WHEN** один сценарий с вызовами `read`, `edit`, `task_create` и `agent` дважды выполняется на `FakeClock` и `SequentialIdGenerator`
- **THEN** оба журнала корня и оба журнала ребёнка побайтово равны (`deterministic_journal_test.dart`, PKG-6)

#### Scenario: Восстановление списка не пишется
- **WHEN** `TaskList.restore(announce: true)` публикует `TaskListChanged` с `op: restore`
- **THEN** журнал побайтово не изменился, записи `task` нет (`task_list_restore_test.dart`)

#### Scenario: Ошибка записи завершает ход
- **WHEN** хранилище возвращает ошибку на записи результата инструмента
- **THEN** эмитится `AgentError(cls: storage)`, ход завершается `TurnEnded(failed)`, следующий запрос к модели не делается

## ADDED Requirements

### Requirement: Список задач из журнала
Проекция `buildTaskList(snapshot)` SHALL быть чистой функцией ядра над активной веткой (§17.16.6) и сворачивать записи по порядку:
- `task` — вставляет или заменяет `items` и убирает `deleted`;
- `plan` старого формата — заменяет весь список пунктами `"1"…"n"` в порядке entries: `subject` = `content`, приоритет и статус как есть, `owner: main`, без зависимостей.

Следующий id SHALL быть максимумом id, выданных во всём журнале (все ветки: `items` и `deleted` каждой записи `task`, у записи `plan` — число её entries), плюс 1: id пункта покинутой ветки НЕ SHALL выдаваться снова (TSK-3; design.md change `add-subagents-and-tasks`, D29). При `open` корневой сессии `TaskList` SHALL восстанавливаться из проекции без публикации и без записи в журнал (TSK-6).

`SessionStore` SHALL уметь создать журнал потомка в каталоге `subagents/` корневой сессии. Дочерние журналы НЕ SHALL попадать в `list` и `index.json` (SUB-9).

#### Scenario: Список после загрузки
- **WHEN** сессия с операциями `task` (создание трёх пунктов, удаление второго) закрывается и открывается в новом `AgentRuntime`
- **THEN** `TaskList.items` — пункты `#1` и `#3`, следующий созданный пункт получает id `4` (`task_list_journal_test.dart`)

#### Scenario: Счётчик id по всем веткам
- **WHEN** журнал содержит две ветки (запись `leaf`): на покинутой созданы `#1`…`#5`, на активной — `#1`…`#3`, и сессия открывается
- **THEN** `TaskList.items` — `#1`…`#3` активной ветки, следующий `task_create` получает id `6` (`task_list_journal_test.dart`)

#### Scenario: Старая сессия с update_plan
- **WHEN** журнал содержит только записи `plan` старого формата, последняя — три пункта
- **THEN** после `open` список — `#1`, `#2`, `#3` с `owner: main`, журнал побайтово не изменён; `task_update` `#2` в `completed` пишет одну запись `task` (`core/task-list-legacy-session-continues`)

#### Scenario: Дочерние журналы не в списке сессий
- **WHEN** в проекте есть сессия с двумя детьми
- **THEN** `listSessions` возвращает одну сессию, `index.json` не содержит дочерних журналов

### Requirement: Список задач следует ветке журнала
Список задач дерева SHALL быть свойством активной ветки журнала корневой сессии, а не сессии: настройки сессии при смене ветки переносятся (SESM-3), список — нет (§17.16.6; design.md change `add-subagents-and-tasks`, D29).

`TaskList.restore(items, nextId:, announce:)` SHALL:
- брать тот же замок, что `apply`;
- заменять список на `items` и ставить счётчик в максимум текущего и переданного `nextId` — счётчик не убывает (TSK-3);
- при `announce: false` (открытие сессии) ничего не публиковать;
- при `announce: true` публиковать ровно один `TaskListChanged` со всем новым списком и `TaskChange(op: restore, actor: main, changed: весь новый список, deleted: id пунктов, которых в новом списке нет)` (TSK-1).

Операции, меняющие активную ветку корневой сессии (переключение ветки и перемотка §17.6.5, откат к метке §17.11.6 — вводятся отдельными change), SHALL после записи `branch` и `BranchChanged` выполнять `restore` со списком и счётчиком `buildTaskList` нового снимка; `announce` SHALL быть истинным, если список до смены или после неё непуст либо в новой ветке есть запись `task` или `plan` (TSK-7). Читатель в режиме только чтения (`JournalTail`, §17.6.8) SHALL делать то же после перечитывания снимка и после каждой новой записи `task` владельца, не записывая ничего. Смена ветки журнала потомка список дерева НЕ SHALL менять.

Список задач в этом требовании — журнальная реализация порта `TaskList`; будущая общая доска команды (§17.16.9) — другая реализация, ветке не следует, и этим требованием не описывается.

#### Scenario: Восстановление с публикацией
- **WHEN** список содержит `#1` и `#2`, счётчик равен 6, и вызывается `restore([#1'], nextId: 4, announce: true)`
- **THEN** публикуется один `TaskListChanged` с `items: [#1']`, `change.op == restore`, `change.deleted == ["2"]`; следующий `task_create` получает id `6` (`task_list_restore_test.dart`)

#### Scenario: Восстановление при открытии
- **WHEN** открывается сессия с записями `task` в активной ветке
- **THEN** `TaskList.items` равен `buildTaskList` ветки, а в потоке событий сессии нет ни одного `TaskListChanged` (`task_list_journal_test.dart`)
