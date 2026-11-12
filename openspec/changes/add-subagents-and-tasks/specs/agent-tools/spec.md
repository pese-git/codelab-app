## MODIFIED Requirements

### Requirement: Встроенные инструменты MVP
Ядро SHALL предоставлять инструменты `read`, `write`, `edit`, `ls`, `search`, `exec` и инструменты списка задач `task_create`, `task_update`, `task_list`, `task_get` (требование «Инструменты списка задач»). Схемы, алгоритмы, тексты вывода и ошибок первых шести SHALL совпадать с §6.4 документа ядра, инструментов списка задач — с §17.16.3:

- **`read`** — tier `read`, kind `read`. Строки `<номер>| <текст>`, `offset < 1` приводится к 1 с заметкой, `limit < 1` — ошибка. Файл с `U+0000` в первых 8 КиБ → `<path> appears to be a binary file.`, пустой файл → `(empty file)`.
- **`write`** — tier `write`, kind `edit`. Вывод `Created <path> (<N> bytes).` или `Overwrote <path> (<N> bytes).`, `FileDiff` с `oldText: null` для нового файла.
- **`edit`** — tier `write`, kind `edit`. Точное совпадение без пересечений. Ноль или несколько совпадений → ошибка, файл не меняется (TOOL-8). Сохраняются CRLF и BOM. Вывод `Edited <path>: replaced lines <a>-<b>.` и фрагмент unified diff не длиннее 40 строк.
- **`ls`** — tier `read`, kind `search`, требует `DirectoryListing`. Один уровень, сортировка без учёта регистра, суффиксы `/` и `@`, лимит 500.
- **`search`** — tier `read`, kind `search`, требует `DirectoryListing`. `RegExp` Dart или литерал, обход в ширину, пропуск служебных и скрытых каталогов, файлов больше 1 МиБ и бинарных, glob, лимит 100 совпадений и 10 000 файлов.
- **`exec`** — tier `exec`, kind `execute`. `timeout` 1..3600 с, по умолчанию 120. Хвост вывода, `(no output)`, `[Command exited with code <N>]`, `[Command timed out after <t> s and was terminated]`, `[Command was cancelled after <t> s]`; `shellUnavailable` → `Shell commands are not available in this environment.`

Инструмента `update_plan` в ядре НЕ SHALL быть (change `add-subagents-and-tasks`, D13): план ведут инструменты списка задач, а ACP `plan` строится из списка.

Ошибки env SHALL отображаться в тексты §6.4. Суффикс ` Use ls to list it.` дописывается, только если `ls` есть в схемах шага. Пути в выводе SHALL быть относительными `cwd`.

#### Scenario: Golden-вывод инструментов
- **WHEN** каждый встроенный инструмент исполняется на `MemoryExecutionEnv` с фиксированным деревом файлов
- **THEN** вывод совпадает с golden-файлом `builtin_tools_golden_test.dart`, включая `search` с glob `**/*.dart`, `exec` с текстом `Shell commands are not available in this environment.` и вывод `task_create`, `task_update`, `task_list`, `task_get`; golden `update_plan.txt` удалён

#### Scenario: edit без единственного совпадения
- **WHEN** `oldText` встречается 0 раз, 2 раза и `aa` ищется в `aaa`
- **THEN** первые два вызова дают ошибки §6.4 без изменения файла, третий находит одно вхождение и заменяет его

#### Scenario: edit сохраняет CRLF и BOM
- **WHEN** `edit` правит файл с BOM и переводами строк CRLF
- **THEN** файл после правки начинается с BOM и содержит только CRLF

#### Scenario: Код возврата exec
- **WHEN** команда завершается с кодом 2
- **THEN** результат — ошибка `isError: true` с выводом и строкой `[Command exited with code 2]`

## ADDED Requirements

### Requirement: Инструменты списка задач
Ядро SHALL вести один список задач (`TaskList`) на дерево корневой сессии и предоставлять инструменты по §17.16:
- `task_create(subject, description?, priority?, blocked_by?, owner?)`;
- `task_update(id, subject?, description?, status?, priority?, owner?, blocked_by?)`, где `status` — `pending`, `in_progress`, `completed` или `deleted`, а `blocked_by` заменяет список целиком;
- `task_list()`;
- `task_get(id)`.

У каждого инструмента: tier `read`, kind `think`, `outputTrust` `trusted`, `permissionPattern` `*`.

Пункт SHALL иметь id (десятичная строка, растёт, не переиспользуется), `subject` (1–200 символов), `description` (до 4000), `status`, `priority` (по умолчанию `medium`), `owner` (`main` или id субагента дерева), `blockedBy`. Живых пунктов SHALL быть не больше 100.

Операция SHALL отклоняться результатом-ошибкой с текстом §17.16.3 без изменения списка в случаях:
- неизвестный id;
- неверная длина;
- превышен лимит пунктов;
- зависимость на себя или на несуществующий пункт;
- цикл в `blocked_by` — текст с цепочкой id (TSK-2);
- владелец не из дерева.

Удаление SHALL убирать id из `blocked_by` остальных пунктов. Статус `in_progress` при незавершённых блокерах SHALL допускаться с заметкой.

Каждая операция, изменившая список, SHALL эмитить ровно один `TaskListChanged` со всем списком до `ToolCallFinished` своего вызова (TSK-1). Операции одного списка SHALL применяться по одной в порядке прихода. Восстановление списка не операцией модели (`TaskList.restore`, `op: restore`) — требование agent-sessions «Список задач следует ветке журнала». Id пункта, выданный на любой ветке журнала, НЕ SHALL выдаваться снова (TSK-3).

Вывод `task_get` SHALL состоять из строк `Task #<id>: <subject>`, `Status: …`, `Priority: …`, `Owner: …`, `Description: …`, `Blocks: #<id> <subject>, …`, `Blocked by: #<id> <subject>, …` в этом порядке; пустое значение — `none`. Ребро зависимости показывается в `Blocks`, `Blocked by` и в суффиксе `(blocked by …)` строки `task_list`, пока блокер не `completed`; суффикс `(owner: …)` в `task_list` — только у владельца не `main` (§17.16.3). Неизвестный id при непустом списке — `Unknown task #<id>. Known: #<id>, ….`, при пустом — `Unknown task #<id>. The task list is empty.`

Детский вариант (потомки, SUB-1, TSK-4): только `task_list`, `task_get` и `task_update`, где допустим лишь `status` и лишь у пунктов с `owner` = id этого потомка. Иначе — ошибка `Subagents may change only the status of their own tasks.`

#### Scenario: Создание, разблокировка и удаление
- **WHEN** модель создаёт `#1`, `#2` с `blocked_by: ["1"]` и `#3`, отмечает `#1` `completed`, затем удаляет `#3` и создаёт ещё один пункт
- **THEN** вывод `task_update` содержит `Unblocked: #2 …`; после удаления `task_list` содержит `#1`, `#2` и новый пункт `#4`; эмитировано шесть `TaskListChanged` — по одному на операцию (`core/task-list-create-update`)

#### Scenario: Вывод task_get
- **WHEN** `#1` `completed`, `#2` (`priority: high`, описание `Rename greet to hello in lib/`) блокирован `#1`, `#3` блокирован `#2`; модель вызывает `task_get` для `#2`, затем для `#9`
- **THEN** первый вывод — `Task #2: rename greet`, `Status: in_progress`, `Priority: high`, `Owner: main`, `Description: Rename greet to hello in lib/`, `Blocks: #3 run tests`, `Blocked by: none`; второй — ошибка `Unknown task #9. Known: #1, #2, #3.` (golden `tasks.txt`)

#### Scenario: Неизвестный id в пустом списке
- **WHEN** список пуст, модель вызывает `task_get` с `id: "1"`
- **THEN** результат — ошибка `Unknown task #1. The task list is empty.`

#### Scenario: Цикл зависимостей
- **WHEN** `#2` блокирован `#1`, а модель задаёт `#1` `blocked_by: ["2"]`
- **THEN** результат — ошибка `Invalid task: blocked_by would create a cycle: #1 → #2 → #1.`, список и журнал не изменились, `TaskListChanged` нет (`core/task-list-cycle-rejected`)

#### Scenario: Потомок меняет чужой пункт
- **WHEN** ребёнок вызывает `task_update` со `status: completed` у пункта с `owner: main`, а затем с `subject` у своего пункта
- **THEN** оба вызова — ошибка `Subagents may change only the status of their own tasks.`; `task_update` своего пункта со `status: completed` проходит (`task_list_owner_test.dart`)

#### Scenario: Назначение пункта ребёнку
- **WHEN** корень вызывает `agent` с `task: "2"`, и ребёнок получает слот
- **THEN** до первого запроса ребёнка к модели эмитируется `TaskListChanged` с `#2` `owner: sub_…` и `status: in_progress`; системный промпт ребёнка содержит строку `Your task: #2 …`
