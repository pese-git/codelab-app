# 17.16. Список задач сессии (менеджер задач)

> Часть [архитектуры ядра агента CodeLab](../agent-core-architecture.md). Status: Proposed (OpenSpec change `add-subagents-and-tasks`; решения пользователя 2026-11-10 внесены). Общие соглашения, термины и порядок чтения — в оглавлении.

← [17.15. A2A](17-15-a2a.md) · [Оглавление ядра](../agent-core-architecture.md)

Цели: C-20 (основная), C-05 (меняется: проекция в ACP `plan`), C-06 (владельцы задач —
субагенты). Решение пользователя 2026-11-09: список задач в стиле Claude Code заменяет
`update_plan`. Затрагивает §5.3 (`TaskListChanged` вместо `PlanUpdated`), §6.4 (инструменты),
§7.5 (шаблон `*`), §8.2.4 (запись `task`), §8.3, §8.7, §11.2 (`tools/tasks.md`), §13.5, §13.7,
§13.12, §17.3.

## 17.16.1. Назначение

`update_plan` (§6.4) заставляет модель каждый раз присылать весь план: она переписывает пункты,
которых не меняла, теряет их порядок и не может сказать «этот пункт делает субагент» или «этот
пункт ждёт тех двух». Список задач даёт модели адресуемые пункты с id и операции над одним
пунктом, а клиенту — тот же стандартный ACP `plan`, что и раньше.

| Что делает раздел | Чего раздел не делает |
|---|---|
| вводит один список задач на дерево корневой сессии (§17.3.1): пункты с id, заголовком, описанием, статусом, приоритетом, владельцем и зависимостями; инструменты `task_create`, `task_update`, `task_list`, `task_get`; проекцию в ACP `plan` с `_meta.codelab.task`; запись в журнал и чтение старых сессий с записями `plan` | не вводит общий список между сессиями (позже, §17.16.9); не показывает доску задач (U-21, D-25, этап 5 §17.3.1); не исполняет пункты сам: список — заметки модели, а не планировщик |

**Имена (решение пользователя 2026-11-10, design.md change `add-subagents-and-tasks`, D20).**
Как в Claude Code: «задача» (task) — только пункт этого списка, а субагент — инструмент `agent`
(§17.3) с семейством `agent_*` (`agent_status`, `agent_cancel`, `agent_send`, `agent_resume`,
`agent_observe`). Инструменты списка — `task_create`, `task_update`, `task_list`, `task_get`;
запись журнала — `task`; событие — `TaskListChanged`; поле назначения пункта у инструмента `agent` —
`task`. Имена инструментов, событий и записей нигде не означают субагента словом task.
Исключение принято сознательно (решение пользователя 2026-11-10): slash-команда фоновой работы
для человека остаётся `/tasks`, как в Claude Code — привычность важнее строгости имени, а список
задач пользователь видит чек-листом плана, отдельной команды у него нет.

## 17.16.2. Контракт

```dart
typedef TaskId = String;                       // "1", "2", … — десятичное, растёт, не переиспользуется

enum TaskStatus { pending, inProgress, completed }   // как ACP PlanEntryStatus
enum TaskPriority { high, medium, low }              // как ACP PlanEntryPriority

/// Владелец пункта: корневая сессия или субагент дерева.
extension type const TaskOwner(String value) {
  static const main = TaskOwner('main');      // иначе — SubagentId 'sub_…'
}

final class TaskItem {
  final TaskId id;
  final String subject;                        // 1–200 символов; ACP PlanEntry.content
  final String? description;                   // до 4000 символов; в ACP не уходит
  final TaskStatus status;
  final TaskPriority priority;                 // по умолчанию medium
  final TaskOwner owner;                       // по умолчанию main
  final List<TaskId> blockedBy;                // по возрастанию id; без удалённых
}

/// Кто выполняет операцию: корневая сессия или субагент (детский вариант, §17.16.4).
sealed class TaskActor { const TaskActor(); }
final class MainActor extends TaskActor { const MainActor(); }
final class SubagentActor extends TaskActor { final SubagentId id; const SubagentActor(this.id); }

sealed class TaskOp { const TaskOp(); }
final class CreateTask extends TaskOp { /* subject, description?, priority?, owner?, blockedBy? */ }
final class UpdateTask extends TaskOp { /* id, subject?, description?, status?, priority?, owner?, blockedBy? */ }
final class DeleteTask extends TaskOp { final TaskId id; }

final class TaskChange {                       // что записать в журнал и показать клиенту
  final String op;                             // create | update | delete | assign
  final TaskActor actor;
  final List<TaskItem> changed;                // полные снимки изменённых пунктов
  final List<TaskId> deleted;
}

/// Список задач дерева. Один на корневую сессию; потомки получают тот же экземпляр.
abstract interface class TaskList {
  List<TaskItem> get items;                    // порядок создания, без удалённых
  List<TaskId> blocksOf(TaskId id);            // обратные рёбра blockedBy, вычисляются
  /// Проверяет и применяет операцию атомарно; публикует TaskListChanged до возврата.
  /// Ошибка проверки — TaskRejected с текстом для модели, список не меняется.
  Future<TaskResult> apply(TaskOp op, TaskActor actor);
  /// Состояние из журнала при open (§17.16.6) — без публикации.
  void restore(List<TaskItem> items, {required int nextId});
}

final class TaskListChanged extends AgentEvent {   // заменяет PlanUpdated (§5.3)
  final List<TaskItem> items;                  // весь список после операции
  final TaskChange change;
}
```

`TaskList` заменяет `PlanService` в `ToolServices` (`ToolServices.tasks`). Операции одного
списка сериализуются внутренним замком: параллельные вызовы пакета и вызовы потомков
применяются по одному в порядке прихода, и каждая проверка видит состояние после предыдущей.

## 17.16.3. Инструменты

Все четыре: tier `read`, kind `think`, `outputTrust` `trusted`, `permissionPattern` `*` (§7.5) —
список не касается файлов, команд и сети, и «разрешить всегда» действует на любой вызов.
Тексты пунктов пишет только модель корневой сессии (детский вариант текстов не меняет,
§17.16.4), поэтому вывод доверенный.

| Инструмент | Параметры | Результат (видит модель) |
|---|---|---|
| `task_create` | `subject` (обязательный), `description`, `priority` (`high` / `medium` / `low`, по умолчанию `medium`), `blocked_by` (массив id), `owner` (`main` или id субагента) | `Created task #<id>: <subject>.` + строка сводки |
| `task_update` | `id` (обязательный); `subject`, `description`, `status` (`pending` / `in_progress` / `completed` / `deleted`), `priority`, `owner`, `blocked_by` (заменяет список целиком) | `Updated task #<id>: <поля через ", ">.` или `Deleted task #<id>.` + `Unblocked: #<id> <subject>` для пунктов, которые эта операция разблокировала + строка сводки |
| `task_list` | — | строка на пункт `#<id> [<status>] <subject>[ (owner: <owner>)][ (blocked by #<id>, …)]` в порядке создания; пусто — `The task list is empty.` |
| `task_get` | `id` (обязательный) | все поля пункта, `blocks` и `blocked by` с заголовками |

Строка сводки: `Task list: <n> items (<c> completed, <i> in progress, <p> pending).` Заметки:
`[Note: task #<id> is in_progress, but #<a>, #<b> are not completed yet.]` — статус
`in_progress` при незавершённых блокерах допускается, но модель об этом узнаёт;
`[Note: more than one task is in_progress.]` — как у `update_plan`.

Ошибки (результат-ошибка, outcome `failed`, список не меняется, `TaskListChanged` нет):

| Случай | Текст |
|---|---|
| нет пункта | `Unknown task #<id>. Known: #<id>, ….` (пусто — `The task list is empty.`) |
| заголовок | `Invalid task: subject must be 1-200 characters.` |
| описание | `Invalid task: description must be at most 4000 characters.` |
| пунктов больше 100 | `Task limit reached: at most 100 items. Delete completed items first.` |
| зависимость на себя или на неизвестный id | `Invalid task: blocked_by must list other existing tasks.` |
| цикл | `Invalid task: blocked_by would create a cycle: #<a> → #<b> → #<a>.` |
| владелец не из дерева | `Invalid task: owner must be "main" or the id of a subagent of this session.` |
| ребёнок меняет чужой пункт или не статус | `Subagents may change only the status of their own tasks.` |

Удаление пункта убирает его id из `blocked_by` остальных; изменённые так пункты входят в
`TaskChange.changed`. Удалённый id больше не выдаётся: следующий id — максимум из всех выданных
плюс 1.

Описания инструментов — `prompts/tool_descriptions/task_*.md`, правило ведения списка —
секция `prompts/tools/tasks.md` (`tools: [task_create]`) вместо `tools/plan.md` (§11.2). Тексты
пишутся заново, без заимствований (§17.16.8).

## 17.16.4. Субагенты и владельцы

Список один на дерево (§17.3.1): корневая сессия и все потомки видят один и тот же `TaskList`.

* **Корневая сессия** (`MainActor`) — все четыре инструмента, любые поля любого пункта.
* **Потомок** (`SubagentActor`) — детский вариант набора (SUB-1): `task_list`, `task_get` и
  `task_update`, где допустим только `status` и только у пунктов с `owner` = id этого потомка;
  `task_create` в набор потомка не входит. Тексты пунктов остаются словами модели корневой
  сессии, а потомок не может переписать чужую работу.
* **Назначение.** Вызов `agent` корневой сессии с полем `task: "<id>"` (§17.3.2) проверяет пункт
  до запуска (нет пункта → `Unknown task #<id>…`, ребёнок не создаётся). Когда ребёнок получает
  слот, ядро от имени корневой сессии ставит пункту `owner` = id ребёнка и, если пункт был
  `pending`, `status: in_progress` — операция `assign`, отдельный `TaskListChanged`. В системный
  промпт ребёнка добавляется строка `Your task: #<id> <subject>.` Пункт, удалённый, пока ребёнок
  стоял в очереди, не назначается (лог `task.assign.skipped`). По завершении ребёнка ядро статус
  не меняет: закрыть пункт решает тот, кто прочитал отчёт.
* Владелец `owner` — только `main` или id субагента, когда-либо запущенного в дереве; id
  завершившегося ребёнка допустим (пункт остаётся за ним в истории).

## 17.16.5. Проекция в ACP

После каждой операции, изменившей список, корневая сессия эмитит `TaskListChanged`, а адаптер
отправляет `session/update` `plan` со **всем** списком (`11-Agent Plan.md`: агент MUST
присылать полный список, клиент MUST заменять):

```json
{"sessionUpdate":"plan","entries":[
 {"content":"Read the failing test","priority":"high","status":"completed",
  "_meta":{"codelab":{"agent":{"id":"1","owner":"main","blockedBy":[]}}}},
 {"content":"Fix the parser","priority":"medium","status":"in_progress",
  "_meta":{"codelab":{"agent":{"id":"2","owner":"sub_k3f9a1c2","blockedBy":["1"]}}}}]}
```

* `content` — `subject`; `description` в ACP не уходит (клиенту он не нужен для чек-листа, а
  `rawInput` вызова его уже показывает).
* `_meta.codelab.task` — `{id, owner, blockedBy}`; `blocks` клиент при желании вычисляет сам:
  одно направление рёбер не может разойтись с другим. `_meta` у plan entry разрешён
  `15-Extensibility.md` («plan entries»); клиент без поддержки его игнорирует и показывает обычный
  план.
* Порядок entries — порядок создания пунктов. Список, опустевший после удаления, — `plan` с
  `entries: []`.
* `task_list` и `task_get` список не меняют и `plan` не дают.
* Поддержку агент объявляет `agentCapabilities._meta.codelab.tasks: {"version": 1}` по схеме
  объявления §17.3.7 (только клиенту, объявившему `clientCapabilities._meta.codelab`); данные
  `_meta.codelab.task` уходят всегда.
* `TaskListChanged` эмитится до `ToolCallFinished` вызова, который его вызвал (как `PlanUpdated`).
  Изменения от потомков и назначение `assign` приходят в поток корневой сессии, пока её вызов
  `agent` открыт, и уходят клиенту как обычный `plan` этого хода.

## 17.16.6. Журнал и старые сессии

Новая запись `task` (§8.2.4) в журнале **корневой** сессии — по одной на `TaskListChanged`
(`durable` не нужен: результат вызова, который её вызвал, пишется `durable` позже, SES-9):

```json
{"type":"task","id":"k2j3h4g5","parentId":"q1w2e3r4","timestamp":"2026-11-09T10:00:01.000Z","op":"update","actor":"main","items":[{"id":"2","subject":"Fix the parser","status":"in_progress","priority":"medium","owner":"main","blockedBy":["1"]}],"deleted":[]}
```

`items` — полные снимки изменённых пунктов, `deleted` — удалённые id. Проекция журнала
`buildTaskList` — свёртка записей активной ветки по порядку: `task` — вставить или заменить
`items`, убрать `deleted`; `nextId` — максимум выданных id плюс 1. Описание пункта лежит в записи,
поэтому список полностью восстанавливается из журнала.

**Старые сессии.** Запись `plan` (§8.2.4) больше не пишется, но читается всегда. В свёртке
`plan` заменяет весь список пунктами `"1"…"n"` в порядке entries: `subject` — `content`,
приоритет и статус — как есть, `owner: main`, без зависимостей. Следующая операция `task_*`
продолжает с этого состояния; переписывать старый журнал не нужно. Вызовы `update_plan` в
истории остаются как есть: инструмента в схемах нет, и модель видит их так же, как вызовы
отключённого MCP-сервера (§6.3.8). Решение пользователя 2026-11-10 (design.md change
`add-subagents-and-tasks`, D20).

**Реплей (§13.5).** После истории уходит `plan` из `buildTaskList` активной ветки, если список
непуст или в ветке была хоть одна запись `task`/`plan`.

**Сжатие (§9).** Записи `task` и `plan` — служебные: в контекст модели не входят и при срезе
остаются с хвостом, как `plan` сейчас. После сжатия модель узнаёт состояние списка вызовом
`task_list`; правило об этом — в секции `tools/tasks.md`.

## 17.16.7. Инварианты

1. **TSK-1.** Каждая операция, изменившая список, даёт ровно один `TaskListChanged` со всем
   списком и ровно одну запись `task`; отклонённая операция не даёт ни того, ни другого.
2. **TSK-2.** Граф `blockedBy` всегда ацикличен; ссылок на удалённые и несуществующие пункты нет.
3. **TSK-3.** Id пункта не переиспользуется в пределах дерева, в том числе после удаления и после
   загрузки сессии.
4. **TSK-4.** Потомок меняет только `status` пунктов, владелец которых — он сам; тексты, владельцев
   и зависимости меняет только корневая сессия.
5. **TSK-5.** Каждый `plan` агента содержит весь список в порядке создания; у каждой entry есть
   `_meta.codelab.task.id`.
6. **TSK-6.** Список после `session/load` равен списку до закрытия: `buildTaskList` активной ветки
   детерминирован; сессия только с записями `plan` открывается со списком из последнего плана.

## 17.16.8. Обоснование решения

* **Операции над пунктом вместо плана целиком.** Модель меняет то, что знает: один статус, одну
  зависимость; переписывание всего плана теряет пункты и стоит токенов на каждом шаге.
* **Проекция в стандартный `plan`.** Клиенты (codelab-app, CLI, Zed) уже показывают ACP-план;
  новый метод расширения потребовал бы поддержки во всех клиентах, а `_meta` у plan entry
  деградирует до обычного плана.
* **Запись по операции, а не снимок.** Снимок всего списка на каждую операцию раздувает журнал
  на длинных сессиях; дельта с полными снимками изменённых пунктов остаётся самодостаточной и
  сворачивается без истории версий.
* **Приоритет — поле с `medium` по умолчанию.** ACP требует `priority` у каждой entry; поле
  позволяет модели выделить важное, а умолчание не заставляет его задавать (решение пользователя 2026-11-10).
* **Потомки только меняют статус своих пунктов (решение пользователя 2026-11-10).** Так список
  не превращается в свалку пунктов от десятка детей, тексты остаются доверенными, а владелец
  действительно отвечает за пункт. Право потомков создавать свои пункты («команды агентов»
  Claude Code) — позже: запись `task` уже несёт `actor`, поэтому формат журнала и
  `_meta.codelab.task` при этом не меняются (§17.16.9).
* **Источник поведения.** Наблюдаемое поведение Claude Code (Anthropic): список задач с
  владельцами и зависимостями. Тексты, описания инструментов и промпты Claude Code не
  воспроизводятся ([§7а](../dart-agent-and-clients/07-decision-sources.md#7а-политика-стороннего-кода));
  запись в `THIRD_PARTY_NOTICES.md` не нужна.
* **Отклонено:** (а) оставить `update_plan` рядом с `task_*` — два способа вести план сбивают
  модель и дают два источника истины; (б) свой метод `_codelab/tasks/*` вместо `plan` — стандартный
  план уже решает показ; (в) список на каждую сессию дерева отдельно — клиент знает только
  корневую сессию, и план ребёнка некуда показать.

## 17.16.9. Дальше

* общий список задач между сессиями одного проекта (несколько сессий или процессов работают по
  одному списку) — требует хранения вне журнала сессии и lease;
* доска задач и `/tasks` (этап 5 §17.3.1) — тот же `TaskList` в снимке доски;
* напоминание модели о незакрытых пунктах после сжатия;
* потомки создают свои пункты (`task_create` в детском наборе, владелец — сам потомок, тексты —
  `untrusted`): формат записи `task` с `actor` это уже допускает.

## 17.16.10. Как проверить

* `task_list_tools_test.dart` (`core/task-list-create-update`): создание трёх пунктов, `in_progress`,
  `completed` с разблокировкой, удаление с очисткой `blocked_by`, тексты вывода и ошибок таблиц
  §17.16.3; id после удаления не повторяется (TSK-1, TSK-3).
* `task_list_cycle_test.dart` (`core/task-list-cycle-rejected`): `#2 blocked_by #1`, затем
  `#1 blocked_by #2` → ошибка с цепочкой, список и журнал не изменились (TSK-2).
* `task_list_owner_test.dart`: `agent` с `task: "2"` → `assign` при получении слота; ребёнок
  закрывает свой пункт; попытка ребёнка изменить `subject` или чужой пункт — ошибка (TSK-4).
* `task_list_journal_test.dart`: свёртка записей `task` даёт тот же список после `open`; журнал только с
  записью `plan` открывается со списком `"1"…"n"`, первая операция `task_update` продолжает его
  (TSK-6).
* `acp/prompt-task-plan` (C-20, C-05): три `task_create`, `task_update` → четыре `plan` со всем
  списком и `_meta.codelab.task`; `task_list` не даёт `plan`.
* `acp/session-load-legacy-plan` (C-05): журнал с записью `plan` → реплей отправляет `plan` с
  entries старого плана и `_meta.codelab.task.id` `"1"…"n"`.
* `acp/prompt-update-plan` остаётся фикстурой с ролью `client`: клиент по-прежнему показывает план
  агента без `_meta`.

---

← [17.15. A2A](17-15-a2a.md) · [Оглавление ядра](../agent-core-architecture.md)
