## MODIFIED Requirements

### Requirement: Формат журнала JSONL
Журнал сессии SHALL быть UTF-8 файлом: одна JSON-запись на строку, разделитель `\n` (§8.2 документа ядра). Пустые строки при чтении пропускаются; логическая структура задаётся `parentId`, а не позицией строки.

Первая строка SHALL быть заголовком `{"type":"session","version":1,...}` с полями `id`, `cwd`, `created`, `agent` и необязательными `metadata` (§8.2.1) и `parent` у журнала субагента: `sessionId` прямого родителя, `rootSessionId`, `toolCallId`, `subagentId`, `agent`, `depth` (§17.3.6). Заголовок не входит в дерево.

Записи:
- `message` с сообщением в канонической JSON-форме §2.2 и полями записи `outcome`, `diff`, `toolMeta`, `origin`;
- `model_change`, `mode_change`, `config_change`, `compaction`, `label`, `leaf`, `session_info`, `custom` (§8.2.4);
- `task` — операция над списком задач: `op`, `actor`, `items` (полные снимки изменённых пунктов), `deleted` (§17.16.6);
- `subagent` — связь с журналом ребёнка: `subagentId`, `toolCallId`, `agent`, `description`, `childSessionId`, `journal`, `status`, `failure`, `report`, `usage` (§17.3.6);
- `plan` — запись старого формата: новые журналы её не пишут, читатель SHALL её понимать всегда.

Поля записи (`outcome`, `diff`, `toolMeta`, `origin` и сопутствующие) SHALL лежать на верхнем уровне объекта рядом с общими полями и НЕ SHALL попадать в сообщение, которое видит модель. Записи `task`, `subagent`, `plan` в контекст модели не входят.

Читатель SHALL:
- игнорировать неизвестные поля заголовка известной версии;
- сохранять неизвестные поля известной записи в `extra` и записывать их обратно при копировании;
- читать запись неизвестного `type` как `CustomRecord("unknown:<type>")` с исходным объектом (design.md change `add-agent-core-sessions-and-compaction`, D2).

Решения «разрешить всегда», частичные снимки ответа, дельты, `ToolCallProgress`, `SubagentProgress` и `SubagentActivity` НЕ SHALL попадать в журнал.

#### Scenario: Golden-разбор
- **WHEN** `parseSessionLines` разбирает фикстуру `test/fixtures/sessions/all_records.jsonl`, где есть каждая запись, включая `task`, `subagent`, `plan` и заголовок с `parent`
- **THEN** каждая запись разобрана в свой тип, `toJson` каждой записи побайтово равен исходной строке

#### Scenario: Неизвестный тип записи
- **WHEN** в журнале встречается строка с `"type":"branch"`
- **THEN** она читается как `CustomRecord("unknown:branch")`, не участвует в проекциях и пишется обратно без изменений

### Requirement: Запись журнала из событий
`SessionWriter` SHALL быть первым подписчиком `Agent` сессии и писать журнал по таблице §8.3 (design.md change `add-agent-core-sessions-and-compaction`, D2, D4; change `add-subagents-and-tasks`, D7, D12):

| Событие | Запись | `durable` |
|---|---|---|
| `MessageEnded` (user, assistant) | `message`; у служебных сообщений — `origin` из `MessageStarted.origin` | нет |
| `MessageEnded` (toolResult) | `message` с `outcome`, `diff`, `toolMeta` вызова | да |
| `ModeChanged` | `mode_change` | нет |
| `TaskListChanged` | `task` из `change` (только в журнале корневой сессии) | нет |
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

#### Scenario: Ошибка записи завершает ход
- **WHEN** хранилище возвращает ошибку на записи результата инструмента
- **THEN** эмитится `AgentError(cls: storage)`, ход завершается `TurnEnded(failed)`, следующий запрос к модели не делается

## ADDED Requirements

### Requirement: Список задач из журнала
Проекция `buildTaskList(snapshot)` SHALL быть чистой функцией ядра над активной веткой (§17.16.6) и сворачивать записи по порядку:
- `task` — вставляет или заменяет `items` и убирает `deleted`;
- `plan` старого формата — заменяет весь список пунктами `"1"…"n"` в порядке entries: `subject` = `content`, приоритет и статус как есть, `owner: main`, без зависимостей.

Следующий id SHALL быть максимумом выданных id плюс 1 (TSK-3). При `open` корневой сессии `TaskList` SHALL восстанавливаться из проекции без публикации и без записи в журнал (TSK-6).

`SessionStore` SHALL уметь создать журнал потомка в каталоге `subagents/` корневой сессии. Дочерние журналы НЕ SHALL попадать в `list` и `index.json` (SUB-9).

#### Scenario: Список после загрузки
- **WHEN** сессия с операциями `task` (создание трёх пунктов, удаление второго) закрывается и открывается в новом `AgentRuntime`
- **THEN** `TaskList.items` — пункты `#1` и `#3`, следующий созданный пункт получает id `4` (`task_list_journal_test.dart`)

#### Scenario: Старая сессия с update_plan
- **WHEN** журнал содержит только записи `plan` старого формата, последняя — три пункта
- **THEN** после `open` список — `#1`, `#2`, `#3` с `owner: main`, журнал побайтово не изменён; `task_update` `#2` в `completed` пишет одну запись `task` (`core/task-list-legacy-session-continues`)

#### Scenario: Дочерние журналы не в списке сессий
- **WHEN** в проекте есть сессия с двумя детьми
- **THEN** `listSessions` возвращает одну сессию, `index.json` не содержит дочерних журналов
