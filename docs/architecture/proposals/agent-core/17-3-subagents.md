# 17.3. Субагенты: инструмент `agent`

> Часть [архитектуры ядра агента CodeLab](../agent-core-architecture.md). Status: Accepted. Общие соглашения, термины и порядок чтения — в оглавлении.

← [17.2. Skills и шаблоны промптов](17-2-skills-and-templates.md) · [Оглавление ядра](../agent-core-architecture.md) · [17.4. Вынос огромного результата инструмента в файл (T-28)](17-4-output-spill.md) →

Цели: C-06 (основная), C-17, H-05, U-21, L-10, R-15, S-09, S-13; удалённые A2A-агенты как типы
`agent` (E-22) — §17.15.3.

> Изменения 2026-11-09 и 2026-11-10 (вложенность до 3 вместо глубины 1, лимиты дерева,
> `SubagentActivity`, таблица этапов, схема объявления `_meta.codelab`, шаги потомков деревом,
> переименование инструмента `task` → `agent` и семейства `task_*` → `agent_*`; команда фоновой работы
> осталась `/tasks`) — по решениям пользователя, в статусе Proposed до одобрения OpenSpec change
> `add-subagents-and-tasks` (design.md, D20, D21). Слово task в CodeLab означает только пункт
> списка задач (§17.16).

## 17.3.1. Назначение

Инструмент `agent` запускает **дочернего агента** (субагента) с отдельным контекстом: свой
системный промпт, своя история, свой набор инструментов и свой бюджет. Родитель передаёт ему
задачу текстом и получает обратно **только итоговый отчёт** — промежуточные шаги ребёнка в
контекст родителя не попадают. Так родитель может поручить исследование большого кода,
ревью изменений или черновик плана, не расходуя на это собственное окно контекста, и запустить
несколько таких задач параллельно.

| Что делает раздел | Чего раздел не делает |
|---|---|
| описывает инструмент `agent`, типы субагентов, вложенность до `max_depth` (не больше 3), параллельный запуск с лимитами на всё дерево, итоговый отчёт (в том числе по JSON-схеме), журнал ребёнка, разрешения, отмену, проекцию в ACP, ожидание в headless | фоновый режим (`run_in_background`, §17.3.8) вводит без хода, начатого агентом: отчёт доставляется через steering или с ближайшим `session/prompt`; глубже 3 уровней субагентов не бывает (§17.3.3, шаг 2); не вводит обмен сообщениями между родителем и работающим ребёнком (сообщение ребёнку, сдавшему отчёт, и повторный запуск упавшего — §17.3.8.1); удалённых агентов не исполняет сам — их типы `a2a:<имя>` и прогон поверх A2A описаны в §17.15.3; список задач сессии, которым пользуются родитель и дети, — §17.16 |

Субагент — это обычная `AgentSession` ядра (§5.6) с особой сборкой: ни цикл (§5), ни единая
точка исполнения (§6.3.1), ни политика разрешений (§7) не получают специальных веток для детей.
Всё особенное сосредоточено в четырёх местах: `SubagentTool`, `SubagentManager` (по одному на
сессию-родителя любого уровня), `SubagentTree` (один на корневую сессию: общие лимиты, очередь
слотов и очередь вопросов всего дерева) и обёртка `PermissionGate` родителя.

**Термины.** *Корневая сессия* — сессия пользователя, глубина 0. *Ребёнок* — субагент, глубина
1–3; у ребёнка глубины 1 родитель — корневая сессия, у ребёнка глубины 2 — ребёнок глубины 1 и
так далее. *Дерево* — корневая сессия и все её потомки.

**Этапы внедрения (решение пользователя 2026-11-09).** Раздел описывает конечное устройство.
Реализация поэтапная; каждый этап встаёт в точки расширения базового этапа без смены
используемых сигнатур (дорожная карта §9, пункт «в»):

| Этап | Объём | Где описано | OpenSpec |
|---|---|---|---|
| 1 — база | `agent` с типами `general`, `explore`, `review`, `plan`; вложенность до `max_depth`; лимиты дерева; состояния хэндла сразу полные (`queued`…`cancelled`); дочерние `CancelToken`; журнал ребёнка и запись `subagent`; события ребёнка внутри ядра с `parentToolCallId` и id субагента (`SubagentActivity`); запрос разрешения ребёнка через gate родителя; список задач §17.16 вместо `update_plan` | §17.3.2–§17.3.7 без доски, §17.3.10–§17.3.14, §17.16 | `add-subagents-and-tasks` |
| 2 — шаги ребёнка деревом | `tool_call` потомков на проводе с `_meta.codelab.parentToolCallId` для клиентов с `subagentToolCalls`; меняет SUB-12 | §17.3.7, «Шаги потомков деревом» | `add-subagents-and-tasks`, итерация 5 |
| 3 — фон и пробуждение | `run_in_background`, `agent_status`, `agent_cancel`, `wake` | §17.3.8, §17.3.9 | отдельный change, 1.x (первый) |
| 4 — продолжение ребёнка (C-17) | `agent_send`, `agent_resume`, `agent_observe`; `output_schema` и ремонт отчёта | §17.3.8.1, §17.3.5 | отдельный change, 1.x (третий) |
| 5a — панель Agents v1 (клиент) | список субагентов сессии в доке app из данных этапов 1 и 2 (`_meta.codelab.subagent`, итог, дерево `parentToolCallId`, запросы потомков); ядро и протокол не меняются | dart-agent-and-clients §12.3, A15 | `add-subagents-and-tasks`, итерация 5b |
| 5 — доска (U-21, D-25) и `/tasks` | `_codelab/subagents/*` в той же панели Agents, вид CLI `tasks` | §17.3.7, §17.3.8 | `add-subagent-board`, 1.x (второй) |
| 6 — фоновые команды (T-10) | `_codelab/jobs/*` на той же доске | §17.9 | `add-background-jobs`, 1.x (четвёртый) |
| позже | общий список задач между сессиями; изоляция ребёнка в git worktree | — | — |

Решение пользователя 2026-11-10: 1.0 = этапы 1 и 2 (change `add-subagents-and-tasks`); этапы 3 → 5 →
4 → 6 — начало пула 1.x в этом порядке (дорожная карта §6.2, §6.4). Решение 2026-11-12 (Q13,
design.md change, D33): клиентская панель Agents v1 (строка «5a») входит в 1.0; ядру и адаптеру она
ничего не добавляет, доска этапа 5 встаёт в ту же панель.

## 17.3.2. Контракт

**Типы субагентов — это определения агентов.** Отдельного класса «тип субагента» нет: тип — тот
же `AgentDefinition` из §15.8, расширенный двумя полями.

```dart
enum AgentScope { session, subagent, both }

final class AgentDefinition {                // §15.8, где поля scope и role уже внесены
  final String name, description, prompt;
  final ModelRef? model;
  final ModeId? mode;
  final List<String>? tools;                 // null — все инструменты профиля; для субагента — все инструменты родителя
  final String source;                       // путь файла или 'builtin:<name>'
  final AgentScope scope;                    // новое: где определение доступно; по умолчанию both
  final ModelRole? role;                     // новое: роль модели (L-10), если model не задана
}
```

Во frontmatter Markdown-определения добавляется необязательное поле `scope`
(`session` | `subagent` | `both`, по умолчанию `both`). Поле `role` во frontmatter не
допускается: оно есть только у встроенных типов. `session` — определение видно только в опции
`agent` сессии (§15.8); `subagent` — только как тип в `agent`; `both` — в обоих местах.

Встроенные типы (`source: 'builtin:<name>'`, тело — файл `prompts/subagent/types/<name>.md`, §11.2):

| `name` | `description` (видит модель) | `tools` | `mode` | `role` |
|---|---|---|---|---|
| `general` | `General-purpose agent for multi-step tasks that may read, edit files and run commands.` | `null` | `null` (режим родителя) | `subagent` |
| `explore` | `Read-only search of the codebase. Returns findings with file paths and line numbers.` | `read`, `ls`, `search` | `plan` | `smol` |
| `review` | `Reviews changes for defects. Reads files and may run read-only commands such as git diff.` | `read`, `ls`, `search`, `exec` | `standard` | `slow` |
| `plan` | `Investigates the code and returns an implementation plan without changing files.` | `read`, `ls`, `search` | `plan` | `plan` |

Пользовательское определение с тем же `name` и `scope` `subagent` или `both` заменяет встроенный
тип (лог `subagent.type_overridden` с путём файла). Определения из недоверенного проекта не
загружаются (CFG-6), поэтому подменить `explore` из чужого репозитория нельзя.

Встроенные профили сессии `architect`, `review` (§17.12.2) — отдельный список со `scope: session`;
тип субагента `review` они не заменяют.

**Удалённые типы (после MVP, §17.15.3).** Каждый `a2a.agents.<имя>` конфига даёт определение с
`name: "a2a:<имя>"`, `scope: subagent`, описанием из конфига и полем `remote` (`RemoteAgentInfo`).
Такой тип входит в `enum` наравне с локальными, но исполняется не дочерней `AgentSession`, а
прогоном A2A через порт `RemoteAgentConnector`: `tierOf` у `agent` — `network`, ключ разрешения —
`("agent", "a2a:<имя>")`, отчёт — `untrusted` с `source="a2a:<имя>"`.

**Инструмент.**

```dart
final class SubagentTool extends AgentTool {
  SubagentTool(this.manager, this.types);         // types — снимок на момент создания сессии
  final SubagentManager manager;
  final List<AgentDefinition> types;          // scope subagent | both, отсортированы по name
  @override String get name => 'agent';
  @override ToolTier get tier => ToolTier.read;         // сам запуск ничего не меняет (§17.3.3, шаг 1)
  @override ToolKind get kind => ToolKind.think;
  @override ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.untrusted;
  @override String permissionPattern(Map<String, Object?> args) => args['type'] as String;
  @override ToolPresentation present(Map<String, Object?> args);   // title: 'Subagent <agent>: <description>'
  @override Future<ToolExecutionResult> execute(Map<String, Object?> args, ToolContext ctx);
}
```

Схема параметров (поле `enum` строится из `types` при создании сессии и дальше не меняется —
схемы стабильны для prompt cache):

```json
{"type":"object","required":["description","prompt"],"properties":{
  "description":{"type":"string","description":"Short title of the work, 3-60 characters. Shown to the user."},
  "prompt":{"type":"string","description":"Complete instructions for the subagent: the goal, relevant paths, constraints and the expected shape of the report. The subagent does not see this conversation."},
  "type":{"type":"string","enum":["explore","general","plan","review"],"default":"general","description":"Subagent type. See the tool description for the list."},
  "output_schema":{"type":["object","null"],"description":"Optional JSON Schema for the final report. When set, the report is a JSON value that matches it."}}}
```

Проверки сверх подмножества §6.3.2 делает `execute` (результат-ошибка, outcome `failed`, ребёнок
не создаётся): `description` — 3–60 символов после обрезки пробелов; `prompt` — 1–32768
символов; `output_schema` — объект, у которого есть `type` (иначе
`output_schema must be a JSON Schema object with a "type" key.`). Тексты ошибок:
`Invalid agent call: description must be 3-60 characters.` и `Invalid agent call: prompt must be 1-32768 characters.`

Описание инструмента (`prompts/tool_descriptions/agent.md`, переменные `maxConcurrent`,
`nesting`, `background`, `agentList`):

```text
Launch a subagent: a separate agent with its own context that does one self-contained assignment and returns a single final report.
Use it to explore a large codebase, review changes or draft a plan without filling your own context.
The subagent does not see this conversation: put everything it needs into `prompt`.
Several agent calls in one response run in parallel, at most {{maxConcurrent}} at a time.
You receive only the final report, not the subagent's intermediate steps.{{background}}
Subagents cannot ask the user questions. {{nesting}}

Agent types:
{{agentList}}
```

`agentList` — строки `- <name>: <description>` в порядке `name`. `nesting` зависит от глубины
вызывающего: `depth + 1 < max_depth` → `A subagent may start its own subagents, up to <max_depth - depth - 1> more level(s) below it.`;
иначе → `Subagents you start cannot start other subagents.` `background` — пустая строка в
базовом этапе; с этапом 3 (§17.3.8) — `\nSet run_in_background to keep working while the subagent runs: its report arrives later as a notice.`
Текст описания для одной глубины детерминирован, поэтому схема и описание стабильны для prompt
cache (§11). Схема `agent` базового этапа — без `output_schema` и `run_in_background`; оба поля
добавляются своими этапами (таблица этапов выше) без смены остальных полей. Поле `task`
(необязательное, id пункта списка задач §17.16) есть только в схеме корневой сессии: ребёнок,
получивший слот, становится владельцем этого пункта (§17.16.4).

**Менеджер и хэндл.**

```dart
typedef SubagentId = String;                  // 'sub_' + 8 символов [0-9a-z] от IdGenerator

/// waiting — ребёнок ждёт решения пользователя или своих детей (поле waitingFor снимка).
enum SubagentState { queued, running, waiting, completed, failed, cancelled }
enum SubagentWait { approval, subagents }
enum SubagentFailure { error, budgetExceeded, invalidOutput, interrupted, refused }

final class SubagentSpec {
  final SessionId parentSessionId; final String parentToolCallId;
  final int depth;                             // 1..max_depth; глубина ребёнка, а не родителя
  final List<SubagentId> path;                 // id предков-субагентов от глубины 1, без самого ребёнка
  final AgentDefinition type; final String description, prompt;
  final String? taskId;                        // пункт списка задач §17.16, только от корневой сессии
  final Map<String, Object?>? outputSchema;    // этап 4; в базе всегда null
}

final class SubagentReport {
  final SubagentId id; final String agent;
  final SubagentState status;                 // completed | failed | cancelled
  final SubagentFailure? failure;             // только при failed
  final BudgetLimit? budgetExceeded;          // при failure == budgetExceeded
  final String text;                          // финальный текст ребёнка (после усечения)
  final Object? json;                         // разобранный отчёт, если задана output_schema и он валиден
  final bool truncated;
  final int steps, toolCalls; final Usage usage; final Duration duration;   // toolCalls и usage — вместе со всеми потомками (транзитивно, §17.3.4, шаг 7)
}

abstract interface class SubagentHandle {
  SubagentId get id;
  SessionId? get childSessionId;              // null, пока в очереди
  SubagentSpec get spec;
  SubagentState get state;
  Stream<SubagentState> get states;           // широковещательный, без повторов значения
  SubagentSnapshot get snapshot;              // для прогресса и доски
  Future<SubagentReport> get report;          // завершается ровно один раз, никогда ошибкой
}

final class SubagentSnapshot {
  final SubagentId id; final String parentToolCallId, agent, description;
  final int depth;
  final SubagentState state; final SubagentWait? waitingFor;   // только при state == waiting
  final int steps, toolCalls; final Usage usage;               // usage — вместе с потомками
  final int activeChildren;                   // потомки ребёнка в queued | running | waiting
  final DateTime startedAt; final DateTime? endedAt;
  final String? lastActivity;                 // title последнего ToolCallStarted ребёнка или его потомка
}

/// Общее состояние дерева: один экземпляр на корневую сессию (§17.3.4).
abstract interface class SubagentTree {
  int get maxDepth;                            // subagents.max_depth
  Future<SlotLease> acquire(SubagentId id, {required bool resume});   // resume — родитель, дождавшийся детей
  int get spawnedThisTurn;                     // счётчик max_per_turn за ход корневой сессии
  PermissionGate wrapGate(PermissionGate rootGate);   // общая FIFO вопросов дерева (SUB-3)
}

abstract interface class SubagentManager {     // один на AgentSession, у которой есть agent (любой глубины)
  /// Ставит задачу в очередь и сразу возвращает хэндл (state = queued).
  /// SubagentLimitException, если исчерпан max_per_turn.
  SubagentHandle spawn(SubagentSpec spec, CancelToken cancel);
  Future<SubagentReport> join(SubagentId id);            // то же, что handle.report
  Future<void> cancel(SubagentId id, [Object? reason]);  // идемпотентно; для доски (§17.3.7)
  List<SubagentSnapshot> list();                         // все дети сессии, в порядке spawn
  Future<void> closeAll(Object reason);                  // при закрытии родительской сессии
}
```

**События.** `SubagentManager` эмитит три события уровня `AgentSession` — так же, как
`ConfigOptionChanged` и `SessionTitleChanged` (§8.3): их эмитит не цикл, а сессия родителя, и
`sessionId` у них — родительский. Они дополняют иерархию §5.3:

```dart
final class SubagentStarted extends AgentEvent {
  final SubagentId subagentId; final String parentToolCallId, agent, description;
  final SessionId childSessionId; final String journalPath; }        // путь относительно sessions/
final class SubagentProgress extends AgentEvent { final SubagentSnapshot snapshot; }
final class SubagentFinished extends AgentEvent {
  final SubagentId subagentId; final String parentToolCallId;
  final SubagentState status; final SubagentFailure? failure;
  final Usage usage; final Duration duration; final String reportPreview; }   // первые 200 символов
```

| Событие | Когда | Кто пишет в журнал родителя |
|---|---|---|
| `SubagentStarted` | ребёнок получил слот, его журнал создан, до первого запроса к модели | `SessionWriter`: запись `subagent` со `status: "running"` (`durable`) |
| `SubagentProgress` | смена состояния, `StepEnded` ребёнка, `ToolCallStarted` ребёнка — не чаще раза в `progress_interval`; смена состояния — всегда | ничего |
| `SubagentFinished` | отчёт готов (после проверки схемы), до возврата из `SubagentTool.execute` | запись `subagent` с итоговым `status` и `report` (`durable`) |

Порядок в потоке родителя для одного вызова:
`ToolCallStarted(agent)` → `SubagentStarted` → `SubagentProgress`×N (вперемешку с
`ToolCallProgress(agent)`) → `SubagentFinished` → `ToolCallFinished(agent)`. Ребёнок, отменённый в
очереди, не даёт `SubagentStarted`: только `SubagentFinished(cancelled)`.

**События ребёнка в потоке родителя.** Каждое событие дочерней сессии (`MessageDelta`,
`ToolCallStarted`, `TurnEnded` и остальные §5.3) сессия родителя переизлучает обёрнутым:

```dart
final class SubagentActivity extends AgentEvent {   // sessionId — родительский
  final SubagentId subagentId;                // ребёнок, чьё событие внутри
  final String parentToolCallId;              // вызов agent В СЕССИИ РОДИТЕЛЯ, запустивший ребёнка
  final List<SubagentId> path;                // предки ребёнка от глубины 1, без него самого
  final int depth;                            // глубина ребёнка
  final AgentEvent event;                     // исходное событие ребёнка, никогда не SubagentActivity
}
```

Обёртка плоская: событие внука, пришедшее родителю от ребёнка уже обёрнутым, переизлучается с тем
же `event`, а `path` и `depth` берутся из исходной обёртки — вложенных `SubagentActivity` не
бывает. Так поток корневой сессии содержит все события дерева с адресом каждого, и дерево шагов
(этап 2) — чистая проекция этого потока без нового API. `SessionWriter` родителя
`SubagentActivity` не пишет (у ребёнка свой журнал); ACP-проекция базового этапа их не отправляет
(SUB-12); переизлучение ждёт подписчиков родителя так же, как любое событие (LOOP-2), поэтому
медленный подписчик тормозит ребёнка, а не теряет его события.

## 17.3.3. Алгоритм: запуск дочернего агента

```mermaid
flowchart TD
    A["вызов agent после разрешений"] --> B{"лимит на ход исчерпан?"}
    B -->|да| E1["ошибка: subagent limit reached"]
    B -->|нет| C{"тип найден и разрешён?"}
    C -->|нет| E2["ошибка: unknown agent type"]
    C -->|да| D["инструменты: родитель ∩ тип; agent только выше max_depth; задачи — детский набор"]
    D --> F["режим: min родителя и типа, запреты объединяются"]
    F --> G["модель: определение, роль, модель родителя"]
    G --> H["бюджет ребёнка и токен-потомок токена хода"]
    H --> Q["очередь семафора"]
    Q --> R["дочерняя AgentSession, журнал в каталоге родителя"]
```

```text
SubagentTool.execute(args, ctx):
 1  вызов agent уже прошёл единую точку исполнения: валидацию, разрешения (tier read, шаблон
    allow_always — имя типа: «разрешить всегда» на explore не разрешает general), хуки
 2  проверки §17.3.2 → при ошибке результат-ошибка
 3  type := types.byName(args.type); нет → `Unknown agent type "<x>". Available: <имена через ", ">.`
 4  handle := manager.spawn(SubagentSpec(...), ctx.cancel)
      SubagentLimitException → `Subagent limit reached: at most <N> subagents per turn. Combine the
      remaining work into fewer tasks or do it yourself.` (outcome failed)
 5  подписка на handle.snapshot → ctx.onUpdate(progressLine(snapshot)) (§17.3.4)
 6  report := await handle.report
 7  вернуть wrapReport(report) (§17.3.5); status cancelled → бросить CancelledException
    (единая точка даёт outcome cancelled, CAN-5); failed → isError: true
```

`SubagentManager.spawn` строит ребёнка из **текущего** состояния родителя:

1. **Счётчик.** `SubagentTree.spawnedThisTurn` — число `spawn` во всём дереве за текущий ход
   **корневой** сессии (сбрасывается в её `AgentSession.prompt()`); запуски внуков считаются
   наравне с запусками детей. `spawnedThisTurn >= max_per_turn` → `SubagentLimitException`.
2. **Глубина.** `depth` ребёнка = глубина родителя + 1 (корневая сессия — 0). Инструмент `agent`
   входит в набор ребёнка, только если `depth < max_depth` (шаг 3), поэтому запуск глубже
   `max_depth` невозможен по построению, а не проверкой во время исполнения. `max_depth` — 1…3,
   по умолчанию 3 (§17.3.10); `max_depth: 1` даёт прежнее поведение «у ребёнка нет `agent`».
3. **Инструменты.** `base` := инструменты схем текущего шага родителя (уже суженные профилем хоста
   и выбранным определением агента родителя, §15.8 шаг 5; `base` уже без выключенных
   инструментов, §6.3.8). `tools` := `type.tools == null ? base :
   base ∩ type.tools` (шаблоны `*` — по префиксу, как в §15.8); затем `agent` убирается, если
   `depth == max_depth`; инструменты списка задач (§17.16) заменяются детским вариантом: ребёнок
   читает весь список, но меняет только статус пунктов, владелец которых — он сам, и пунктов не
   создаёт (§17.16.4). Список один на дерево и принадлежит корневой сессии и её UI; ребёнок, ведущий
   свой отдельный план, сбил бы клиента. Инструмент типа, которого нет у родителя, молча не добавляется (CFG-7 сохраняется:
   список только сужает). MCP-инструменты ребёнок использует через **те же** подключения
   родителя; блокировки путей (§6.3.4) — общие для процесса, поэтому параллельные дети, пишущие
   один файл, сериализуются. После MVP `memory`, `ask`, `checkpoint`, `discover_tools` в набор
   ребёнка не входят (XT-12); видимые схемы родителя в режиме `essential` — текущий
   `ToolLoadPlan` (§17.11.9).
4. **Режим разрешений.** Эффективный режим ребёнка вычисляется **при каждом решении**, а не один
   раз при запуске (`PermissionPolicy.modeOf`, §7.2): `effective = narrow(parentMode(), type.mode)`, где `narrow` берёт
   `PermissionMode` с меньшим номером в порядке §7.3.1 `alwaysAsk(0) < write(1) < acceptEdits(2) <
   yolo(3) < autopilot(4)` и объединяет запреты уровней (`plan` запрещает tier `write` и `exec`,
   §13.6). Примеры: родитель `standard` + тип `plan` → `write` с запретом `write`/`exec`; родитель
   `ask` + тип `plan` → `alwaysAsk` с тем же запретом; родитель `plan` + тип `general` → запрет
   `write`/`exec`; родитель `bypass` + тип `review` (`standard`) → `write`; родитель
   `accept-edits` + тип `standard` → `write`. Если родитель сменил
   режим посреди хода, следующий вызов ребёнка проверяется уже по новому режиму. Для внука
   `parentMode()` — эффективный режим его родителя-ребёнка, поэтому сужение идёт по всей цепочке:
   потомок любой глубины не мягче ни одного предка (SUB-2).
5. **Правила.** `PolicyRules` (deny из конфига, per-tool policy) — те же, что у родителя.
   Множества `allowAlways`/`rejectAlways` (`PermissionDecisionStore`, §7.2) ребёнок **не копирует, а разделяет** с родительской
   сессией: решение «разрешить всегда», принятое в запросе ребёнка, сохраняется в сессии
   родителя (пользователь видел запрос в сессии родителя) и действует для родителя и всех его
   детей до закрытия сессии. С вложенностью хранилище решений одно на дерево — хранилище
   корневой сессии: решение, принятое в запросе внука, действует для всего дерева. Grants на ход (`grantForTurn`) ребёнок читает из текущего хода
   корневой сессии, но не может их менять.
6. **Gate.** `gate := SubagentPermissionGate(rootGate, handle)` (ниже): запрос потомка любой
   глубины идёт в gate **корневой** сессии — только её знает клиент ACP. Если у корневой сессии
   gate нет, у потомков его тоже нет (PERM-5).
7. **Модель.** Первое доступное: `type.model`; модель роли `type.role` (L-10); модель роли
   `subagent`; текущая модель родителя. Недоступная модель определения — ошибка определения ещё
   при загрузке (§15.8), до `agent` она не доходит. Цепочка роли — по §17.10.5. Пока ролей моделей
   нет (L-10 не реализована), базовый этап берёт `type.model`, иначе текущую модель родителя;
   поле `role` у встроенных типов появляется вместе с L-10 без смены остальных шагов.
8. **Промпт.** `composeSystemPrompt` (§11.5) для набора инструментов ребёнка с режимом `effective`,
   затем секции `prompts/subagent/system.md` (ниже), `## Agent profile: <name>` с телом
   определения (как в §15.8, шаг 2) и, если задана `output_schema`, секция
   `prompts/subagent/output_schema.md` с канонической JSON-записью схемы. Контекст проекта
   (`AGENTS.md`) входит как у родителя.
9. **Бюджет.** `TurnBudget(maxSteps: subagents.max_steps, maxTokens: subagents.max_tokens,
   maxCost: subagents.max_cost, maxDuration: subagents.max_duration)`. Время ожидания одобрения
   не входит в `maxDuration` (как §5.2). После MVP ребёнок получает `SessionDeadline` родителя
   (только чтение, §17.12.5); проверки финального ответа (§17.12.4) не наследуются.
   **Бюджет предков.** Свой `TurnBudget` ребёнка — верхняя граница, но не единственная: на каждой
   границе шага ребёнок проверяет и остаток бюджетов всех предков вплоть до бюджета хода корневой
   сессии (`maxTokens`, `maxCost`; usage потомков уже учтён в них, §17.3.4, шаг 7). Исчерпан
   бюджет любого предка → ребёнок останавливается так же, как по своему (`failed`,
   `budget_exceeded:<limit>`). Так дерево целиком не тратит больше бюджета хода корневой сессии.
10. **Отмена.** `childSource := CancelTokenSource(parent: cancel)`, где `cancel` — токен хода
   родителя из `ToolContext` (CAN-3: отмена хода отменяет всех детей; отмена ребёнка через
   `manager.cancel` не трогает родителя). Токен внука — потомок токена хода ребёнка, поэтому
   `session/cancel` корневой сессии каскадом отменяет всё дерево синхронно. Steering родителя детям не доставляется.
11. **Очередь.** Хэндл в состоянии `queued` встаёт в очередь слотов дерева (§17.3.4).

При получении слота: создать дочернюю сессию через `AgentRuntime.createChildSession` (§5.6,
`ChildSessionSpec`; журнал по §17.3.6), эмитить `SubagentStarted`, вызвать `child.prompt([TextContent(prompt)], cancel:
childSource.token)`. По `TurnEnded` ребёнка — построить отчёт (§17.3.5), эмитить
`SubagentFinished`, освободить слот, `childSource.dispose()`, закрыть дочернюю сессию (при
`subagents.follow_ups` — по истечении `idle_keep`, если за это время не начат новый прогон, §17.3.8.1).

`prompts/subagent/system.md` (`id: subagent.system`, без переменных):

```text
You are a subagent. Another agent started you to complete one assignment and will read only your final message.
- Work autonomously. You cannot ask the user or the other agent questions. If something is ambiguous, choose the most reasonable interpretation and state it in your report.
- Stay within the assignment. Do not start unrelated work.
- Your final message is the report. Make it self-contained: findings, file paths with line numbers, what you changed (if anything) and what remains uncertain. Do not narrate your intermediate steps.
```

`prompts/subagent/output_schema.md` (`id: subagent.output_schema`, переменная `schema`):

```text
Your final message must be only a JSON value that matches this JSON Schema. Do not wrap it in code fences and do not add any other text:
{{schema}}
```

**Разрешения ребёнка через gate родителя.** `SubagentPermissionGate` оборачивает
`PermissionRequest` ребёнка и передаёт его в gate **родителя**:

| Поле запроса | Значение |
|---|---|
| `toolCallId` | цепочка вызовов от корневой сессии через `/`: `<agent корня>/<вызов ребёнка>` для глубины 1 (`call_3/call_1`), `<agent корня>/<agent ребёнка>/<вызов внука>` для глубины 2 (`call_3/call_2/call_1`) и так далее. Уникален в корневой сессии (PERM-4) и начинается с id вызова `agent`, который клиент видел. Клиент НЕ ДОЛЖЕН разбирать id: связь даёт `_meta.codelab.subagent` (§17.3.7) |
| `title` | `[<agent>: <description>] <title потомка>` — тип и заголовок **того** ребёнка, чей вызов, например `[review: Check the diff] Run git diff --stat` |
| `rawInput`, `locations`, `diffs`, `reason`, `allowAlwaysOffered`, `kind`, `tier` | как у ребёнка, без изменений (PERM-6) |
| `sessionId` (на проводе) | корневой сессии: `AcpPermissionGate` знает только её |

Запросы всех потомков одной корневой сессии **сериализуются**: у дерева одна FIFO
(`SubagentTree`), в каждый момент к пользователю уходит не больше одного запроса от потомков;
запрос самой корневой сессии очередь не ждёт (во время `agent` она новых вызовов не делает, кроме
параллельных в том же пакете). Пока запрос ребёнка ждёт ответа или своей очереди, хэндл в
состоянии `waiting` с `waitingFor: approval`; слот при этом **не** освобождается (§17.3.4).
Отмена токена ребёнка снимает его запрос из очереди и даёт `cancelled` (PERM-7).

## 17.3.4. Алгоритм: параллелизм и ожидание

1. **Параллельность задаёт пакет.** `agent` не объявляет `executionMode`, поэтому несколько вызовов
   `agent` в одном ответе модели исполняются параллельно (§5.5). Если в пакете есть
   `sequential`-инструмент, весь пакет, включая `agent`, идёт последовательно (LOOP-4).
2. **Слоты дерева.** У `SubagentTree` `max_concurrent` слотов (по умолчанию 3) на всё дерево
   корневой сессии; корневая сессия слота не занимает. Слот держит ребёнок, который **сам
   работает**: ждёт модель, исполняет инструмент или ждёт решения пользователя. `spawn` сверх
   лимита ставит хэндл в очередь в порядке вызовов `spawn` — для параллельного пакета это порядок
   `ToolCallStarted`, то есть порядок вызовов в ответе.
   **Ожидание детей освобождает слот.** Ребёнок, вызвавший блокирующий `agent`, на время ожидания
   своих детей переходит в `waiting` (`waitingFor: subagents`) и **возвращает слот** дереву. Когда
   все дети его пакета терминальны, он снова берёт слот — `acquire(resume: true)` — и только потом
   делает следующий запрос к модели. Очередь слотов двухуровневая: сначала возвращающиеся
   родители (FIFO между собой), затем новые дети (FIFO).
   **Почему нет взаимоблокировки.** Держатель слота никогда не ждёт другого слота: он ждёт только
   модель, инструмент или пользователя, и каждое из ожиданий кончается без участия очереди слотов.
   Значит, держатели всегда освобождают слоты, а очередь движется. Приоритет возвращающихся
   родителей не даёт новым детям бесконечно занимать освободившиеся слоты, пока родитель с
   готовыми результатами стоит в очереди (SUB-23). При `max_depth: 1` правило не срабатывает:
   ребёнок без `agent` детей не ждёт.
3. **Отмена в очереди.** Хэндл, отменённый в состоянии `queued`, удаляется из очереди, слот не
   занимает, журнал не создаётся, `report` завершается `cancelled` без единого запроса к модели.
   Отменённый родитель, стоящий в очереди за слотом после ожидания детей, тоже удаляется из
   очереди: доделывать ход ему не нужно, его отчёт — `cancelled`.
4. **Прогресс.** Пока ребёнок работает, вызов `agent` родителя остаётся в `in_progress` (хук
   `markInProgress`, §13.7). `SubagentTool` вызывает `ctx.onUpdate` с одной строкой прогресса при
   каждом `SubagentProgress` и, если событий не было, раз в `heartbeat_interval` (по умолчанию
   15 с) — чтобы клиент видел, что вызов жив. Строка (для человека, формат фиксирован ради golden):
   `<agent> · <state> · <steps> steps · <toolCalls> tool calls · <tokens> tokens[ · <n> subagents][ · <lastActivity>]`,
   где `tokens` — `input + output` ребёнка вместе с потомками с суффиксом `k` от 1000 с одним
   знаком (`12.3k`), `<n> subagents` — число активных потомков (`activeChildren`, если больше 0), а
   `lastActivity` — title последнего вызова ребёнка или его потомка, обрезанный до 60 символов.
5. **Ожидание.** Родительский шаг ждёт все вызовы пакета (`Future.wait`, §5.5): ход родителя не
   продолжается, пока не завершены все дети этого пакета. Ни один блокирующий ребёнок не
   переживает вызов `agent`, который его запустил, а значит, и ход родителя (SUB-4); фоновые дети
   (§17.3.8) в пакет не входят: их вызов `agent` завершается сразу.
6. **Порядок результатов.** `ToolCallFinished(agent)` приходят в порядке завершения детей,
   сообщения-результаты в транскрипте родителя — в порядке вызовов (LOOP-3). Порядок записей
   `subagent` в журнале родителя — порядок событий.
7. **Учёт usage.** `Usage` ребёнка добавляется к usage хода родителя отдельной строкой
   `subagentUsage` в `TurnUsage` (§12.6) и учитывается в `maxTokens`/`maxCost` бюджета хода
   родителя на ближайшей границе шага родителя (LOOP-12). Так родитель не может обойти бюджет,
   раздав работу детям. Usage внука входит в usage ребёнка, а через него — в usage корневой
   сессии: учёт транзитивный. Пока родитель ждёт детей, его бюджет проверяют сами дети на своих
   границах шага (§17.3.3, шаг 9, «Бюджет предков»), поэтому дерево не уходит за бюджет корня,
   даже если корень долго не доходит до своей границы шага.
8. **Отмена хода родителя.** Токен хода отменён → токены всех детей отменены (CAN-3), каскадом до
   самой глубокой глубины. `SubagentTool`
   ждёт `TurnEnded` каждого ребёнка не дольше `cancel_grace` (по умолчанию 10 с), затем
   возвращает `cancelled`. По истечении `cancel_grace` хэндл помечается `cancelled`, лог
   `subagent.cancel_grace_exceeded`; дочерняя сессия закрывается в фоне. `TurnEnded(cancelled)`
   родителя приходит после `ToolCallFinished` всех `agent` (CAN-5). Все токены дерева отменяются в
   один момент, поэтому `cancel_grace` на каждом уровне отсчитывается от одного и того же момента
   и вложенность не умножает ожидание.

## 17.3.5. Алгоритм: итоговый отчёт

```text
buildReport(child, turnEnded, spec):
1  last := последнее assistant-сообщение ребёнка; text := склейка его text-блоков через "\n\n"
   (thinking и toolCall не входят)
2  turnEnded.reason:
     cancelled → status cancelled
     failed    → status failed, failure error (text из AgentError, если text пуст)
     refused   → status failed, failure refused
     completed с budgetExceeded → status failed, failure budgetExceeded; text — последний ответ
       (может быть пустым: тогда text := "")
     completed или maxTokens → шаг 3
3  spec.outputSchema == null → status completed
   иначе json := extractJson(text); errors := validate(json, schema) (подмножество §6.3.2)
     ok → status completed, json
     ошибка и ремонта ещё не было → child.prompt([TextContent(schemaFix(errors))]) в той же
       дочерней сессии с остатком бюджета, затем повторить с шага 1 (ровно один раз)
     ошибка после ремонта → status failed, failure invalidOutput, text как есть
4  усечение: text длиннее report_max_bytes (UTF-8) → оставить начало по границе строки,
   дописать "\n[report truncated: <N> of <M> bytes shown; the full report is in the subagent journal]",
   truncated := true
```

`extractJson(text)`: (а) `text.trim()` целиком разбирается как JSON → он; (б) иначе последний
fenced-блок с языком `json` или без языка; (в) иначе подстрока от первого `{` или `[` до
последней парной `}` или `]`; (г) иначе — ошибка `no JSON value found`.

Текст ремонта (`prompts/subagent/schema_fix.md`, переменная `errors`):

```text
Your final message does not match the required JSON Schema:
{{errors}}
Reply with only a JSON value that matches the schema. Do not add any other text.
```

`errors` — перечень нарушений в формате ошибок валидации §6.3.2, по строке на нарушение.

**Что видит модель родителя.** `wrapReport` строит один `TextContent`; атрибуты в фиксированном
порядке, значения экранируются как атрибуты XML (`&`, `<`, `"`):

```text
<subagent-report id="sub_k3f9a1c2" agent="explore" status="completed" steps="6" tool_calls="9">
<текст отчёта; при output_schema — JSON в канонической записи (ключи по алфавиту, без пробелов)>
</subagent-report>
```

| Исход | Атрибуты сверх базовых | Тело | `isError` |
|---|---|---|---|
| `completed` | `truncated="true"`, если усечено | отчёт | `false` |
| `failed`, `budgetExceeded` | `reason="budget_exceeded:<steps|tokens|cost|duration>"` | последний текст или `Subagent stopped: its budget was exhausted before it finished.` | `true` |
| `failed`, `invalidOutput` | `reason="invalid_output"` | `Subagent report does not match output_schema: <errors>` + `\n\nRaw report:\n` + текст | `true` |
| `failed`, `error` / `refused` | `reason="error"` / `reason="refused"` | `Subagent failed: <сообщение>` | `true` |
| `cancelled` | — | `Tool call was cancelled` (стандартный текст §6.3.1) | `true` |

Вхождения `</subagent-report` в тексте отчёта экранируются заменой `<` на `&lt;` (как §6.3.6,
шаг 1). Затем результат проходит обычное усечение (§6.3.5) и ограду: `agent` всегда `untrusted`
(`source="agent"`). Отчёт — пересказ того, что ребёнок прочёл в файлах, выводе команд и
MCP-ответах, то есть транзитивно содержит недоверенные данные; инструкции внутри отчёта родитель
исполнять не должен (TOOL-10 по смыслу).

`agent` не `spillable`: отчёт уже ограничен `report_max_bytes`. Выносы ребёнка (§17.4) лежат в
его собственном каталоге выноса (§17.3.6); пути к ним в тексте отчёта родителю бесполезны —
`BoundedEnv` родителя этот каталог не содержит, и `read` по такому пути даёт `outsideWorkspace`.

## 17.3.6. Журнал субагента

**Раскладка.** Журнал ребёнка — полноценный JSONL-файл формата §8.2 в подкаталоге журнала
родителя:

```text
$CODELAB_HOME/sessions/<cwd-slug>/
  2026-10-21T08-00-00-000Z_01JB8Q2W6R9T3M5K7N1P4X8Z0C.jsonl           родитель
  2026-10-21T08-00-00-000Z_01JB8Q2W6R9T3M5K7N1P4X8Z0C/
    subagents/
      2026-10-21T08-00-05-120Z_01JB8Q3A1D2E3F4G5H6J7K8M9N.jsonl     ребёнок sub_k3f9a1c2
      2026-10-21T08-00-05-120Z_01JB8Q3A1D2E3F4G5H6J7K8M9N/spills/   выносы ребёнка (§17.4)
    spills/                                                         выносы родителя (§17.4)
```

У ребёнка свой `SpillService` и свой каталог выноса `<журнал ребёнка без .jsonl>/spills/` в
`readOnlyRoots` его `BoundedEnv`; каталог выноса родителя ребёнку недоступен, и наоборот
(SPL-5).

**Вложенность — плоско.** Журналы потомков любой глубины лежат в одном каталоге `subagents/`
**корневой** сессии, а не в каталогах своих родителей: вложенные каталоги на глубине 3 дали бы
путь длиннее 260 символов Windows уже при обычном `CODELAB_HOME`. Дерево восстанавливается по
заголовкам (`parent.sessionId` — прямой родитель, `parent.depth`) и записям `subagent` в журнале
прямого родителя: запись о внуке лежит в журнале ребёнка. Каталог выноса у каждого потомка свой,
рядом с его журналом.

Имя каталога — имя файла корневой сессии без `.jsonl`; имя файла ребёнка — по правилу §8.9. `list`
(§8.10, шаг 1) перебирает только `sessions/*/*.jsonl`, поэтому дочерние журналы в `session/list`
**не попадают** и сводку родителя не меняют: ребёнок — деталь вызова инструмента, а не сессия
пользователя. `index.json` дочерние журналы не содержит.

**Заголовок ребёнка** — обычный заголовок §8.2.1 с новым необязательным полем `parent`:

```json
{"type":"session","version":1,"id":"01JB8Q3A1D2E3F4G5H6J7K8M9N","cwd":"/work/demo","created":"2026-10-21T08:00:05.120Z","agent":{"name":"codelab-agent","version":"0.1.0"},"parent":{"sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","rootSessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","toolCallId":"call_3","subagentId":"sub_k3f9a1c2","agent":"explore","depth":1}}
```

`parent.sessionId` — прямой родитель (у внука — ребёнок), `parent.rootSessionId` — корневая
сессия дерева, `parent.toolCallId` — вызов `agent` в журнале прямого родителя.

Первая запись дерева ребёнка — `model_change` с моделью ребёнка, затем `mode_change` с
эффективным режимом на момент запуска, затем `message` с промптом задачи. Остальные записи — как
у любой сессии (`SessionWriter` ребёнка подписан на его `Agent`).

**Запись связи в журнале родителя** — новая служебная запись `subagent` (в контекст модели не
входит; последняя запись с данным `subagentId` выигрывает):

| Поле | Тип | Смысл |
|---|---|---|
| `subagentId` | string | `sub_…` |
| `toolCallId` | string | вызов `agent`, запустивший ребёнка |
| `agent`, `description` | string | тип и заголовок |
| `childSessionId` | string? | `null`, если ребёнок отменён в очереди |
| `journal` | string? | путь журнала ребёнка относительно `sessions/` |
| `status` | string | `running`, `completed`, `failed`, `cancelled` |
| `failure` | string? | `budget_exceeded:<limit>`, `invalid_output`, `error`, `refused`, `interrupted` |
| `report` | string? | у итоговой записи: тело `<subagent-report>` после усечения (без обёртки) |
| `usage` | object? | у итоговой записи: usage ребёнка вместе с потомками (формат §8.2.3) |
| `toolCalls`, `durationMs` | int? | у итоговой записи: вызовы ребёнка вместе с потомками и длительность; вместе с `usage` дают `_meta.codelab.subagent.summary` при реплее (D24 change `add-subagents-and-tasks`) |
| `background` | bool? | `true` у фонового ребёнка (§17.3.8); отсутствует — блокирующий |

```json
{"type":"subagent","id":"b7n2m4k1","parentId":"q1w2e3r4","timestamp":"2026-10-21T08:00:05.130Z","subagentId":"sub_k3f9a1c2","toolCallId":"call_3","agent":"explore","description":"Find auth code","childSessionId":"01JB8Q3A1D2E3F4G5H6J7K8M9N","journal":"work-demo-9c3e51a7/2026-10-21T08-00-00-000Z_01JB8Q2W6R9T3M5K7N1P4X8Z0C/subagents/2026-10-21T08-00-05-120Z_01JB8Q3A1D2E3F4G5H6J7K8M9N.jsonl","status":"running"}
{"type":"subagent","id":"c8x1z2v3","parentId":"b7n2m4k1","timestamp":"2026-10-21T08:00:41.900Z","subagentId":"sub_k3f9a1c2","toolCallId":"call_3","agent":"explore","description":"Find auth code","childSessionId":"01JB8Q3A1D2E3F4G5H6J7K8M9N","journal":"…","status":"completed","report":"Auth is in lib/auth/session.dart:12-80 …","usage":{"input":21400,"output":930,"cacheRead":0,"cacheWrite":0}}
```

Записи `subagent` ставятся в дерево родителя после assistant-сообщения с вызовом `agent` и до
его результата; цепочка `parentId` остаётся линейной (параллельные дети пишут по очереди через
общую очередь записи, SES-4). Итоговая запись пишется **до** `ToolCallFinished(agent)` и с
`durable` — это точка восстановления отчёта.

**Lease (S-09, §17.6.8).** Lease корневой сессии покрывает журналы всех потомков:
отдельный lease на ребёнка не берётся, писатель дочерних журналов — только процесс-владелец lease
родителя; проверка lease перед записью общая, сравнение ревизии ведётся для каждого файла
отдельно. Fork родителя копирует журналы детей на скопированном пути под новыми `SessionId`
ребёнка с `parent.sessionId` новой сессии (§17.6.7).
`session/load` с id дочерней сессии → `-32602` с `data: {"codelab": {"reason":
"subagentSession", "parentSessionId": "<id>"}}`: история ребёнка открывается только через
родителя (просмотр — расширение доски, §17.3.7). Ответ `subagentSession` требует поиска id среди
дочерних журналов и вводится вместе с доской (этап 5); в базовом этапе хранилище дочерние журналы
по id не находит, и `session/load` с id ребёнка даёт обычное «сессия не найдена» (`-32002`).

**Прерывание (S-13).** Субагент после сбоя **не перезапускается**. `healInterruptedTurn`
родителя (§8.8) получает правило для `agent`:

```text
для каждого missing-вызова с toolName == "agent":
  s := последняя запись subagent с toolCallId == вызов.id
  s.status == completed | failed (итог записан, результат — нет: сбой между записью и результатом)
      → результат из s.report и s.status с обёрткой §17.3.5; outcome записи = completed | failed
        (вызов не повторяется, отчёт не теряется)
  иначе (s нет, или status running)
      → стандартный синтетический результат interrupted (§8.8)
      → дописать subagent{status: "failed", failure: "interrupted"} для s.subagentId
      → открыть журнал ребёнка, выполнить его healInterruptedTurn и записать результат в его файл
        (то же правило рекурсивно: прерванный agent ребёнка лечит журналы внуков)
```

Так параллельный пакет из двух `agent`, где первый ребёнок успел закончить, а второй — нет,
после перезапуска даёт модели отчёт первого и `interrupted` для второго; ни один ребёнок не
запускается снова. Реплей (§13.5) показывает первый вызов `completed`, второй — `failed` с
`_meta.codelab.outcome: "interrupted"`.

## 17.3.7. Проекция в ACP

**Стандартная проекция.** Вызов `agent` — обычный вызов инструмента (§13.7):

| Что | Кадр | Поля |
|---|---|---|
| `ToolCallStarted(agent)` | `tool_call` | `kind: "think"`, `title: "Subagent explore: Find auth code"`, `status: "pending"`, `rawInput` (все аргументы, включая `prompt`), `_meta.codelab.subagent: {"id": "sub_…", "type": "explore"}` — клиент опознаёт вызов субагента с первого кадра; `id` резервируется в `present` и переносится в `ToolCallStarted.subagent`, при реплее — из записи `subagent` (решение пользователя 2026-11-10, design.md change `add-subagents-and-tasks`, D28) |
| `markInProgress` | `tool_call_update` | `status: "in_progress"` |
| `ToolCallProgress(agent)` | `tool_call_update` | `content: [{"type":"content","content":{"type":"text","text":"<строка прогресса>"}}]` — заменяет предыдущую строку (в ACP `content` обновления заменяет коллекцию) |
| `ToolCallFinished(agent)` | `tool_call_update` | `status: "completed"` или `"failed"` (отмена — `failed` с `_meta.codelab.outcome: "cancelled"`); `content` — один текстовый блок с **телом** отчёта (без обёртки `<subagent-report>` и ограды: клиент показывает человеку текст); всегда — `_meta.codelab.subagent: {"id", "summary": {"toolCalls", "tokens": {"input", "output"}, "durationMs"}}` — итог ребёнка вместе с потомками из `SubagentReport` (`toolCalls`, `usage`, `duration`; решение пользователя 2026-11-10, design.md change `add-subagents-and-tasks`, D24); для `failed` — ещё `failure` |
| `SubagentStarted`, `SubagentFinished` | — | лог `subagent.start` / `subagent.end`; доска (ниже) |
| `SubagentProgress` | — | только доска (ниже); строку прогресса уже несёт `ToolCallProgress` |
| запрос разрешения потомка | `session/request_permission` | `sessionId` корневой сессии, `toolCall.toolCallId: "call_3/call_1"` (цепочка, §17.3.3), `title` с префиксом, `toolCall._meta: {"codelab": {"subagent": {"id": "sub_…", "type": "review", "description": "Check the diff", "depth": 1, "path": [], "parentToolCallId": "call_3"}}}`; `parentToolCallId` — вызов `agent` **корневой** сессии, который клиент видел (первый сегмент цепочки), `path` — id предков-субагентов от глубины 1 |
| `SubagentActivity` | — / `tool_call`, `tool_call_update` | клиенту без `subagentToolCalls` — не отправляется (SUB-12); клиенту с ним — вызовы потомков, ниже «Шаги потомков деревом» |

**Вызовы инструментов ребёнка не проецируются** клиенту, не согласовавшему дерево, как `tool_call` верхнего уровня. Причины:
(1) в ACP нет вложенности вызовов — три параллельных ребёнка по десять вызовов превратили бы
ленту сессии в 30 перемешанных строк без связи с задачами; (2) суть субагента — родитель и
пользователь видят итог, а не шаги; (3) детали доступны отдельно — в журнале ребёнка и на
доске. Запрос разрешения — единственное, что от ребёнка уходит клиенту напрямую: без него
пользователь не может одобрить действие. Его `toolCallId` клиенту заранее не объявлен;
клиент ДОЛЖЕН показать такой запрос самостоятельно, используя `title`, `rawInput` и `content`
запроса (golden `acp/prompt-subagent-permission`). `_meta.codelab.subagent` — расширение через
OpenSpec (change `add-subagents-and-tasks`).

**Объявление в `initialize` (базовый этап).** Агент перечисляет поддержанные расширения CodeLab в
`agentCapabilities._meta.codelab` (§13.2), только если клиент объявил
`clientCapabilities._meta.codelab` (объект, возможно пустой): сторонний клиент получает ответ
`initialize` без изменений. Значение каждого ключа — объект с целым `version`; отсутствие ключа —
расширения нет; неизвестные ключи обе стороны игнорируют. Базовый этап объявляет
`subagents: {"version": 1, "maxDepth": <max_depth>}` (только при `subagents.enabled`) и
`tasks: {"version": 1}` (§17.16). Данные расширений (`_meta.codelab.subagent`,
`_meta.codelab.task`) агент отправляет независимо от объявления клиента — как `_meta.codelab.critical`:
клиент без поддержки `_meta` их игнорирует. Капабилити доски и пробуждения (`subagentBoard`,
`subagentWake`) следуют той же схеме — объект с `version` вместо `true` — и вводятся своими этапами.

**Шаги потомков деревом (этап 2; решение пользователя 2026-11-10, design.md change
`add-subagents-and-tasks`, D21).** Клиент, понимающий вложенность, объявляет
`clientCapabilities._meta.codelab.subagentToolCalls: {"version": 1}`; агент при `subagents.enabled`
объявляет тот же ключ. Только такому клиенту адаптер проецирует `SubagentActivity`:

| Событие потомка | Кадр | Поля |
|---|---|---|
| `ToolCallStarted` | `tool_call` | как у вызова корня (§13.7); `toolCallId` — цепочка от вызова `agent` корня (тот же id, что у запроса разрешения этого вызова); `_meta.codelab.parentToolCallId` — `toolCallId` на проводе вызова `agent`, запустившего потомка |
| `ToolCallProgress`, `ToolCallFinished` | `tool_call_update` | как у корня, с тем же `_meta.codelab.parentToolCallId` |
| прочие (`MessageDelta`, `ThoughtDelta`, `TurnEnded`…) | — | не отправляются: итог потомка — отчёт |

Запрос разрешения потомка у такого клиента приходит после `tool_call` своего вызова и встаёт в
его строку стандартным путём ACP. Когда вызов `agent` становится терминальным, адаптер до его
`tool_call_update` закрывает ещё открытые вызовы поддерева: `tool_call_update` `failed` с
`_meta.codelab.outcome: "cancelled"` — поздние события отписанного потомка (§17.3.4, шаг 8) не
дойдут, а строка не должна остаться «Running». `session/load` такому клиенту проигрывает вызовы
потомков из их журналов (по записям `subagent`, рекурсивно) сразу после кадра `tool_call` вызова
`agent`. Клиенты (kit, app, CLI) строят дерево по `parentToolCallId`; вызов с неизвестным
родителем показывается на верхнем уровне. Фикстуры: `acp/prompt-subagent-tool-tree`,
`acp/session-load-subagent-tool-tree`.

Пока вызов `agent` идёт, клиент с деревом может показывать в свёрнутой строке «хвост» — три
последних вызова потомков и строку `+N more tool calls` (без токенов: они только в итоге завершённого,
Q15); это проекция клиента над
вызовами с `parentToolCallId`, агент для неё ничего сверх таблицы не шлёт (design.md change
`add-subagents-and-tasks`, D25). Без дерева клиент показывает строку прогресса `ToolCallProgress`.

**Доска субагентов (U-21) — предложение, вводится через OpenSpec.** Расширение `_codelab/subagents`
включается, только если клиент объявил `clientCapabilities._meta.codelab.subagentBoard: {"version": 1}`, а
агент — `agentCapabilities._meta.codelab.subagentBoard: {"version": 1}` в `initialize`. Предлагаемая форма:

| Метод | Направление | Параметры → результат |
|---|---|---|
| `_codelab/subagents/update` (уведомление) | агент → клиент | `{sessionId, subagents: [SubagentSnapshotJson], pendingNotices}` — полный снимок детей текущего хода и активных фоновых детей (`"background": true` в снимке); `pendingNotices` — число недоставленных уведомлений (§17.3.8); на каждый `SubagentStarted`/`Progress`/`Finished` и изменение очереди уведомлений, не чаще `progress_interval`; для фоновых детей отправляется и вне хода |
| `_codelab/subagents/list` | клиент → агент | `{sessionId}` → `{subagents: [...]}`: все дети сессии, включая завершённые (по записям `subagent` журнала) |
| `_codelab/subagents/cancel` | клиент → агент | `{sessionId, subagentId}` → `{}`; `SubagentManager.cancel`; вызов `agent` получает `cancelled`, ход родителя продолжается |
| `_codelab/subagents/history` | клиент → агент | `{sessionId, subagentId}` → `{updates: [SessionUpdate]}` — реплей журнала ребёнка (§13.5) без отправки в ленту сессии |

```json
{"id":"sub_k3f9a1c2","parentToolCallId":"call_3","type":"explore","description":"Find auth code",
 "state":"running","startedAt":"2026-10-21T08:00:05.130Z","endedAt":null,
 "steps":4,"toolCalls":7,"tokens":{"input":15200,"output":610},"cost":0.041,
 "lastActivity":"Search \"login\" in lib"}
```

Без расширения клиент видит всё нужное через стандартный `tool_call`: заголовок, строку
прогресса и итоговый отчёт.

## 17.3.8. Фоновый режим

**Назначение.** Блокирующий `agent` держит ход родителя, пока ребёнок не закончит. Для долгой
независимой работы (исследовать соседний пакет, пока родитель правит текущий) модель запускает
ребёнка **в фоне**: вызов `agent` сразу возвращает идентификатор, родитель продолжает работу, а
отчёт приходит позже **уведомлением**.

**Ограничение ACP, которое определяет устройство.** Ход начинается только по `session/prompt`
от клиента; агент не открывает ход сам и не возвращает `stopReason` без запроса. Поэтому у
уведомления есть ровно два пути доставки, и оба не требуют, чтобы агент начинал ход:

| Состояние родителя в момент завершения ребёнка | Доставка | Нужно ли расширение ACP |
|---|---|---|
| ход идёт | `Agent.steer` (§5.6): уведомление входит в контекст на ближайшей границе шага (CAN-6), модель реагирует в этом же ходе | нет |
| ход не идёт | уведомление ждёт в очереди сессии и входит в контекст **перед** сообщением пользователя следующего `session/prompt` (поведение `steer` без хода, §5.6) | нет |
| ход не идёт, клиент поддерживает пробуждение | агент сообщает клиенту `_codelab/subagents/update` с `pendingNotices > 0`; клиент по своей политике отправляет `session/prompt` с `_meta.codelab.wake: true` — ход начинает **клиент** | да, через OpenSpec |

**Контракт.** Схема параметров `agent` (§17.3.2) получает поле:

```json
"run_in_background":{"type":"boolean","default":false,"description":"Run the subagent in the background. The call returns at once with the subagent id; the report arrives later as a separate notice. Use it for long independent work while you continue. Background subagents cannot ask the user for approval while you are idle."}
```

```dart
final class SubagentSpec {                    // §17.3.2, дополнение
  // ...
  final bool background;                      // run_in_background
}

abstract interface class SubagentManager {     // §17.3.2, дополнение
  // ...
  List<SubagentNotice> takePendingNotices();   // забрать недоставленные уведомления (FIFO)
  int get pendingNoticeCount;
  Stream<void> get noticesChanged;             // для доски и пробуждения
}

final class SubagentNotice {
  final SubagentId id; final String agent, description, parentToolCallId;
  final SubagentReport report;
}
```

Два новых инструмента регистрируются вместе с `agent` (§10.7), только если
`subagents.background = true` (по умолчанию `true`):

| Инструмент | Параметры | tier / kind | Результат (видит модель) |
|---|---|---|---|
| `agent_status` | `id` (необязательный); `wait_seconds` (0–120, по умолчанию 0) | `read` / `think` | без `id` — строки `<id> <agent> <state> <steps> steps "<description>"` по всем фоновым детям сессии; с `id` — то же для одного; при `wait_seconds > 0` ждёт, пока ребёнок (или любой, если `id` нет) не станет терминальным, но не дольше `wait_seconds`; завершённый за время ожидания ребёнок сразу получает уведомление в этом же результате |
| `agent_cancel` | `id` (обязательный) | `read` / `think` | `Cancelled subagent <id>.` или `Subagent <id> is not running (state: <state>).`; отмена только уменьшает работу, поэтому разрешение не спрашивается в `standard` |

Описания инструментов — `prompts/tool_descriptions/agent_status.md` и `agent_cancel.md` (§11.2).

**Алгоритм: запуск в фоне.** `SubagentTool.execute` (§17.3.3) при `run_in_background: true`:

```text
1-3  как в §17.3.3 (проверки, тип)
4    лимит: фоновых детей сессии в состоянии queued | running | waiting < max_background
     (по умолчанию 4), иначе `Background subagent limit reached: at most <N> run at once.
     Wait for a notice or cancel one with agent_cancel.` (outcome failed); max_per_turn — общий
5    handle := manager.spawn(spec{background: true}, sessionToken)
       токен — потомок токена СЕССИИ, а не хода: session/cancel хода фоновых детей не трогает;
       closeAll (закрытие сессии, выход процесса) — отменяет
6    вернуть сразу (без ожидания) TextContent:
       `Started background subagent <id> (<agent>): "<description>". You will receive its report
        as a notice when it finishes. Use agent_status to check progress and agent_cancel to stop it.`
     outcome completed; ToolCallFinished(agent) — сразу
```

Ребёнок занимает тот же семафор `max_concurrent`, что и блокирующие (§17.3.4); очередь общая,
FIFO. Бюджет ребёнка — свой `TurnBudget` (§17.3.3, шаг 9). Usage фонового ребёнка входит в usage
сессии и в `TurnUsage.subagentUsage` того хода родителя, в котором **доставлено** уведомление;
в бюджет хода родителя, давно завершившегося, он не входит (SUB-11 уточняется: для фонового
ребёнка — ход доставки).

**Алгоритм: разрешения фонового ребёнка.** Запрос ребёнка идёт через `SubagentPermissionGate`
(§17.3.3) только если у родителя **идёт ход**: клиент ACP ждёт `session/request_permission`
лишь внутри хода. Если хода нет:

```text
1  решение без вопроса по политике (режим, allowAlways/rejectAlways, PolicyRules) → применить
2  вопрос нужен → не спрашивать; отказ с результатом-ошибкой ребёнку:
     `Approval is not available: the session is idle. Do only actions that need no approval, or
      report what needs approval.`
   лог subagent.approval_unavailable; ребёнок продолжает и может включить это в отчёт
3  начался ход родителя → новые запросы ребёнка снова идут через gate (очередь SUB-3)
```

Поэтому фоновый режим естественно подходит типам `explore` и `plan`, у которых нет `write` и
`exec`; `general` в фоне работает в пределах уже выданных «разрешить всегда».

**Алгоритм: доставка уведомления.** По `SubagentFinished` фонового ребёнка:

```text
1  итоговая запись subagent{status, report, usage, background: true} — durable (как SUB-10)
2  notice := SubagentNotice(report); добавить в FIFO pending сессии; noticesChanged
3  текст уведомления (user-сообщение, origin "subagent_notice"):
     <subagent-notice id="<id>" agent="<agent>" status="<status>" description="<description>">
     The background subagent finished. Its report follows. Continue your work with it.
     </subagent-notice>
     + wrapReport(report) (§17.3.5) внутри ограды untrusted-content source="agent"
4  ход идёт → agent.steer(message, origin: SubagentNoticeOrigin(id)) (§5.6); иначе — ждать следующего prompt()
5  доставка = запись в журнал message{role: user, origin: "subagent_notice", subagentId} и
   MessageStarted; из pending уведомление удаляется только после этой записи
6  AgentSession.prompt(content) при непустом pending (уведомления субагентов и фоновых команд
   §17.9.6, в порядке завершения): сначала все уведомления (по одному user-сообщению), затем
   content пользователя; всё — в одном ходе
```

Уведомление — не слова пользователя: в ленту ACP как `user_message_chunk` оно не отправляется ни
вживую, ни при реплее (`session/load` пропускает сообщения с `origin: "subagent_notice"`, кроме
строки в доске). Клиент без расширения узнаёт о завершении из ответа модели и из команды
`/tasks`.

**Общая очередь со steering (§17.7.3.2).** Уведомления лежат в той же FIFO-очереди `steering`,
что и пользовательские steering-сообщения, в порядке поступления: один опрос забирает все
элементы и добавляет один шаг (STEER-6). В `TurnEnded.returnedSteers` уведомления не попадают
никогда: недоставленное уведомление остаётся в pending до следующего хода. Уведомления фоновых
команд (§17.9.6) лежат в той же очереди; `pendingNotices` — сумма недоставленных уведомлений
субагентов и задач; пробуждение доставляет все.

**Команда агента `/tasks`** (стандартный `available_commands_update`, R-07; место в списке — перед `help`, §13.4): `/tasks` — список
фоновой работы сессии: фоновых детей и фоновых команд (§17.9.11) со статусом; `/tasks cancel <id>` —
отмена ребёнка (`sub_…`) или остановка задачи (`job_…`); `/tasks output <id>` — последние 40 строк
вывода задачи. Обрабатывается агентом без модели, как `/status` (§13.6), и даёт человеку
управление без расширения протокола.

**Пробуждение (через OpenSpec).** Агент, поддерживающий пробуждение, объявляет
`agentCapabilities._meta.codelab.subagentWake: {"version": 1}` в ответе `initialize`. Если и клиент объявил
`clientCapabilities._meta.codelab.subagentWake: {"version": 1}`, агент при `pendingNoticeCount > 0` и
отсутствии хода шлёт `_codelab/subagents/update` с полем `pendingNotices`. Клиент МОЖЕТ ответить
`session/prompt` с `prompt: []` (пустой список блоков) и `_meta: {"codelab": {"wake": true}}`; агент
выполняет ход только из уведомлений. Без согласованной capability агент такой `session/prompt` с
пустым `prompt` отклоняет `-32602`. Политика клиента: CLI REPL и app будят автоматически, если
пользователь не печатает (`subagents.auto_wake = true`); `codelab -p` — по §17.3.9.

**Журнал и сбой.** Запись `subagent` получает поле `background: true`. После перезапуска
(`open`, §8.6):

```text
1  для каждой фоновой записи subagent без итогового status → дописать
   subagent{status: failed, failure: interrupted}; журнал ребёнка лечится как в §17.3.6
   (ребёнок не перезапускается)
2  pending := итоговые фоновые записи, для которых нет message с origin "subagent_notice" и тем же
   subagentId (порядок — порядок итоговых записей)
3  pending доставляется по шагу 6 доставки при следующем prompt()
```

Так уведомление доставляется **ровно один раз**: не теряется при сбое между завершением ребёнка
и доставкой и не дублируется после доставки.

```mermaid
sequenceDiagram
    participant CL as "ACP-клиент"
    participant PA as "Сессия родителя"
    participant SM as "SubagentManager"
    participant CH as "Фоновый ребёнок"
    CL->>PA: session/prompt
    PA->>SM: agent run_in_background true
    SM-->>PA: Started background subagent sub_1
    PA-->>CL: ответ end_turn
    SM->>CH: prompt, токен сессии
    CH-->>SM: TurnEnded, отчёт
    SM->>SM: запись subagent completed, pending
    SM-->>CL: _codelab/subagents/update pendingNotices 1 (если согласовано)
    CL->>PA: session/prompt (пользователь или wake)
    PA->>PA: уведомление в контекст перед промптом, запись origin subagent_notice
    PA-->>CL: ответ модели с учётом отчёта
```

### 17.3.8.1. Продолжение работы с субагентом (C-17)

**Назначение.** Отчёт ребёнка часто требует уточнения («а где вызывается `verifyToken`?»), а
ребёнок, упавший на сбое провайдера или прерванный, уже проделал половину работы. Новый `agent`
начал бы с нуля и потратил бы окно ребёнка на повторное чтение тех же файлов. Три инструмента
продолжают работу с **уже запущенным** ребёнком по его `SubagentId`: `agent_send` — новое сообщение
ребёнку, сдавшему отчёт; `agent_resume` — повторный запуск ребёнка, не закончившего работу;
`agent_observe` — последние сообщения ребёнка без загрузки его контекста в контекст родителя.
Обмена сообщениями с **работающим** ребёнком раздел не вводит: steering родителя детям по-прежнему
не доставляется (§17.3.3, шаг 10).

**Прогон.** Каждый запуск ребёнка — **прогон** с номером `run` (первый — `agent`, `run = 1`; каждый
`agent_send` и `agent_resume` — следующий номер). Прогон — один ход дочерней `AgentSession` в **том же**
журнале ребёнка (§17.3.6): история прежних прогонов сохраняется, ребёнок видит её как обычную
историю своей сессии (и сжимает её по §9, как любая сессия). Состояния хэндла (§17.3.11) относятся
к прогону: `completed`, `failed`, `cancelled` терминальны для прогона, продолжение — новый прогон с
новым `report`, а не переход назад.

**Кого можно продолжить.** Ребёнок **известен** сессии, если на активной ветке родителя есть запись
`subagent` с его `subagentId` (после перемотки до вызова `agent` ребёнок неизвестен). Его состояние —
итоговая запись последнего прогона:

| Состояние последнего прогона | `agent_send` | `agent_resume` |
|---|---|---|
| `queued`, `running`, `waiting` | ошибка «still running» | ошибка «still running» |
| `completed`; `failed` с `budgetExceeded`, `invalidOutput`, `refused` (ход ребёнка закончился штатно — **ожидает**) | новый прогон с сообщением родителя | ошибка «use agent_send» |
| `failed` с `error`, `interrupted`; `cancelled` (ход не закончен) | ошибка «use agent_resume» | новый прогон с текстом продолжения |

**Контракт.**

```dart
abstract interface class SubagentManager {     // §17.3.2, §17.3.8, дополнение
  // ...
  /// Новый прогон известного ребёнка. SubagentFollowUpException — правила таблицы выше и лимиты.
  SubagentHandle followUp(SubagentId id, SubagentFollowUp request, CancelToken cancel);
  /// Последние сообщения активной ветки журнала ребёнка; работает в любом состоянии.
  Future<SubagentObservation> observe(SubagentId id, {int last = 10, bool tools = false});
}

sealed class SubagentFollowUp { const SubagentFollowUp(); }
final class SendFollowUp extends SubagentFollowUp { final String message; final String toolCallId; final bool background; }
final class ResumeFollowUp extends SubagentFollowUp { final String? note; final String toolCallId; final bool background; }

final class SubagentObservation {
  final SubagentId id; final String agent; final SubagentState state; final int run;
  final List<String> lines; final int omitted; }   // omitted — сообщений до окна

// Дополнение §17.7.2.1: поля записи origin в журнале РЕБЁНКА (§8.2.3, §8.2.5).
final class ParentMessageOrigin extends MessageOrigin { final int run; final String toolCallId; }   // "parent_message"
final class SubagentResumeOrigin extends MessageOrigin { final int run; final String failure; }   // "subagent_resume"
```

| Инструмент | Параметры | tier / kind | `outputTrust` | `permissionPattern` |
|---|---|---|---|---|
| `agent_send` | `id` (обязательный), `message` (1–32768 символов), `run_in_background` (по умолчанию `false`) | `read` / `think` | `untrusted` | тип ребёнка (`agent`), ключ решения — `PermissionKey("agent", <agent>)` |
| `agent_resume` | `id` (обязательный), `note` (необязательный, до 4000 символов), `run_in_background` (по умолчанию `false`) | `read` / `think` | `untrusted` | то же |
| `agent_observe` | `id` (обязательный), `last` (1–`observe_max`, по умолчанию `observe_default`), `include_tools` (по умолчанию `false`) | `read` / `think` | `untrusted` (`source="agent"`) | `id` |

`agent_send` и `agent_resume` проходят ту же политику, что `agent`: решение «разрешить всегда» и
правила `PolicyRules`, заданные для `agent` с типом `<agent>`, действуют и на них (новый геттер
`AgentTool.permissionKeyName => 'agent'`, §7.3). Инструменты регистрируются вместе с `agent` (§10.7),
если `subagents.follow_ups = true`; `run_in_background` в их схеме есть, только если
`subagents.background = true`. Описания — `prompts/tool_descriptions/agent_send.md`,
`agent_resume.md`, `agent_observe.md` (§11.2), по строке:

```text
agent_send: Send a new instruction to a subagent that already returned its report. It continues in its own context and returns a new report.
agent_resume: Restart a subagent whose last run failed or was cancelled. It continues from its own history; finished tool calls are not repeated.
agent_observe: Show the last messages of a subagent (running or finished) without its full history. Use it to check progress or to quote its work.
```

**Алгоритм: `agent_send` и `agent_resume`.**

```text
1  единая точка исполнения (§6.3.1): валидация, разрешения по ключу ("agent", agent ребёнка), хуки
2  s := последняя запись subagent с id на активной ветке родителя; нет → `Unknown subagent <id>.
   Known: <id через ", ">.` (список пуст → `No subagents in this session.`)
3  проверка таблицы «Кого можно продолжить»; ребёнок уже в прогоне, запущенном этим же пакетом
   (два agent_send одному id в одном ответе) → второй получает «still running»
4  лимиты: прогонов ребёнка сверх первого ≥ max_follow_ups, или agent_resume при числе
   продолжений через resume ≥ max_resumes → ошибка лимита; turnCount ≥ max_per_turn (общий с agent,
   §17.3.3, шаг 1); фоновый прогон — и max_background (§17.3.8)
5  handle := manager.followUp(id, request, cancel); run := s.run + 1
     токен — потомок токена хода (блокирующий) или сессии (фоновый), как §17.3.3 шаг 10 и §17.3.8 шаг 5
     инструменты := tools_прогона_1 ∩ базовый набор текущего шага родителя (SUB-1; разрешения
       ребёнка не расширяются, даже если родитель получил новые инструменты)
     режим, правила, gate, модель, бюджет (свежий TurnBudget на прогон) — заново по §17.3.3, шаги 4–9
     слот семафора max_concurrent — как у agent (§17.3.4)
6  при получении слота: дочерняя сессия открыта (держится idle_keep после отчёта) или
   открывается заново из журнала ребёнка (AgentRuntime.openChildSession, §5.6; heal §8.8 уже
   выполнен при open родителя); запись subagent{status: running, run, followUp: send | resume,
   toolCallId} в журнал родителя (durable); SubagentStarted с run
7  сообщение прогона (user-сообщение ребёнка, durable):
     send   → message с origin "parent_message" и текстом args.message
     resume → message с origin "subagent_resume"; текст prompts/subagent/resume.md:
       Your previous run stopped before it finished ({{reason}}). Continue the same assignment from
       where you stopped. Tool calls that already have results are done: do not repeat them
       unless their result shows they must be repeated.{{note}}
       reason := "error: <сообщение AgentError, до 200 символов>" | "the process stopped" | "it was cancelled"
       note := "\n\nNote from the agent that started you:\n" + args.note, если задан
     resume прогона, чьё сообщение parent_message в журнал ребёнка не попало (сбой между шагами
       6 и 7) → вместо текста продолжения повторяется message из аргументов исходного agent_send
8  child.prompt([сообщение]); отчёт — buildReport (§17.3.5) по последнему ответу этого прогона,
   ремонт по output_schema исходного agent — ровно один раз на прогон
9  блокирующий: прогресс и ожидание как §17.3.3, шаги 5–7; результат — wrapReport с атрибутом
   run="<run>"; фоновый: сразу `Started run <run> of background subagent <id> (<agent>).`,
   отчёт — уведомлением §17.3.8 с атрибутом run="<run>"
```

**Алгоритм: `agent_observe`.** Снимок активной ветки журнала ребёнка: для работающего — из памяти
его `AgentSession`, иначе `openReadOnly` (§8.3) без lease ребёнка (его покрывает lease родителя) и
без записи. Берутся последние `last` записей `message` (без `toolResult`, если не `include_tools`);
строка — `[<run>] <role|origin> <HH:mm>: <текст>`, где роль — `parent` для слов принципала (первое
сообщение и `parent_message`, §8.2.5), `notice` для прочих user-записей, `assistant`, `tool <name>`;
у ответа — только text-блоки, вызовы — `call <name> <canonicalJson(args), до 200 символов>`; текст
сообщения обрезается до `observe_message_max_chars` с пометкой `…`. Первая строка —
`Subagent <id> (<agent>), state <state>, run <run>; showing <n> of <total> messages.`; итог
ограничен `observe_max_bytes` (старые строки отбрасываются первыми). Ребёнок, отменённый в
очереди (журнала нет) → `Subagent <id> has no history: it was cancelled before it started.`

**Журнал и сбой.** Запись `subagent` (§17.3.6) получает поля `run` (int, отсутствует — `1`) и
`followUp` (`"send"` | `"resume"`); `toolCallId` — вызов, запустивший **этот** прогон. Правило
лечения `agent` (§17.3.6, «Прерывание») применяется и к `agent_send`/`agent_resume`: поиск по
`toolCallId`; итог записан → результат из записи, иначе `interrupted` для прогона, ребёнок сам не
перезапускается — его можно продолжить `agent_resume`. Отмена хода родителя отменяет блокирующий
прогон (`cancelled`, SUB-6); `agent_cancel` и `/tasks cancel` отменяют текущий прогон ребёнка.
Fork родителя (§17.6.7) копирует журналы детей: в новой сессии те же `subagentId` продолжаются в
копиях. Сессия только для чтения (SESM-12) ходов не выполняет, поэтому инструменты в ней не
вызываются.

**Конфигурация** (`subagents`, §17.3.10): `follow_ups` (`true`), `max_follow_ups` (`5`),
`max_resumes` (`2`), `idle_keep` (`"2m"`), `observe_default` (`10`), `observe_max` (`50`),
`observe_message_max_chars` (`2000`), `observe_max_bytes` (`16384`).

**ACP и клиент.** Стандартная проекция §13.7: `tool_call` с `kind: "think"`; title —
`Subagent <agent>: <description> (follow-up <run>)`, `… (resume <run>)`, `Observe subagent <id>`;
у `agent_send`/`agent_resume` строки прогресса и итог — как у `agent` (§17.3.7). Снимок доски
(`_codelab/subagents/update`, `/list`) получает поля `run` и `followUps` — расширение через
OpenSpec вместе с доской; `_codelab/subagents/history` отдаёт `parent_message` как
`user_message_chunk` с `_meta.codelab.subagentRun: <run>`, `subagent_resume` пропускает.
Клиентская доска показывает номер прогона «run 2» при `run ≥ 2`, а в истории ребёнка сообщения
`parent_message` — как реплики «parent»; новых действий пользователя доска не получает:
продолжение — инструмент модели.

**Ошибки** (результат-ошибка, outcome `failed`, прогон не создаётся):

| Случай | Текст |
|---|---|
| ребёнок работает | `Subagent <id> is still running (state: <state>). Wait for its report with agent_status or cancel it with agent_cancel.` |
| `agent_send` к незаконченному | `Subagent <id> did not finish its last run (<failure>). Use agent_resume to continue it.` |
| `agent_resume` к ожидающему | `Subagent <id> finished its last run (<status>). Use agent_send to give it a new instruction.` |
| лимит продолжений | `Follow-up limit reached for subagent <id>: at most <N> follow-ups. Start a new subagent instead.` |
| лимит resume | `Resume limit reached for subagent <id>: at most <N> resumes.` |
| журнал ребёнка не открывается | `Subagent <id> cannot be continued: its journal is unavailable (<reason>).` |
| пустое `message` | `Invalid agent_send: message must be 1-32768 characters.` |

**Инварианты** (дополняют §17.3.12):

* **SUB-17.** Продолжение не создаёт нового ребёнка: прогон `run ≥ 2` идёт в той же дочерней сессии и
  том же журнале; история прежних прогонов в журнале не меняется (SES-1).
* **SUB-18.** Набор инструментов прогона — подмножество набора первого прогона и текущего набора
  родителя; режим и правила вычисляются как при `agent` (SUB-1, SUB-2); `agent_send`/`agent_resume`
  решаются по ключу разрешения `agent` того же типа.
* **SUB-19.** У ребёнка не больше одного активного прогона; `agent_send` принимается только ожидающим
  ребёнком, `agent_resume` — только незаконченным.
* **SUB-20.** `agent_resume` не повторяет вызовы, у которых в журнале ребёнка есть результат
  (SES-9, SES-10); сообщение прогона, не попавшее в журнал ребёнка, при resume доставляется один раз.
* **SUB-21.** Прогонов сверх первого у ребёнка не больше `max_follow_ups`, из них resume — не больше
  `max_resumes`; каждый прогон учитывается в `max_per_turn`, `max_concurrent`, бюджете хода
  родителя (SUB-11) и, если фоновый, в `max_background`.
* **SUB-22.** `agent_observe` ничего не пишет ни в журнал ребёнка, ни в журнал родителя и не меняет
  состояние ребёнка; его результат всегда `untrusted`.

**Как проверить.**

* `core/agent-send-to-idle-child` (`subagent_follow_up_test.dart`, scripted LLM): `agent` → отчёт;
  `agent_send` тому же id → ребёнок получает второе user-сообщение с `origin: "parent_message"` в
  том же файле, запрос к модели ребёнка содержит историю прогона 1; результат `<subagent-report …
  run="2">`; `agent_send` работающему ребёнку и ребёнку с `failed(error)` — тексты таблицы ошибок;
  шестой `agent_send` при `max_follow_ups = 5` — ошибка лимита (SUB-17, SUB-19, SUB-21).
* `core/agent-resume-failed-child` (`subagent_resume_follow_up_test.dart`): ребёнок падает на
  `ErrorEvent` после двух выполненных `exec` → `agent_resume` → fake-инструмент вызван ровно два
  раза, сообщение `subagent_resume` с текстом шаблона; процесс убит во время прогона 2 → после
  `open` прогон `interrupted`, повторный `agent_resume` работает (SUB-20).
* `subagent_follow_up_tools_test.dart`: родитель потерял `exec` после прогона 1 → прогон 2 без
  `exec`; «разрешить всегда» на `agent` `general` действует на `agent_send` к `general`;
  `rejectAlways` — тоже (SUB-18).
* `subagent_observe_test.dart`: `last: 3` у работающего ребёнка — три последние строки, журналы
  побайтово не изменены; `include_tools`; обрезка `observe_max_bytes`; отменённый в очереди —
  текст «no history» (SUB-22).
* `acp/prompt-subagent-follow-up`: `tool_call` `agent_send` с `kind: "think"` и title
  `… (follow-up 2)`, строки прогресса, `completed` с телом отчёта.

## 17.3.9. Headless: ожидание перед выходом (H-05)

Блокирующие дети (SUB-4) к ответу на `session/prompt` уже завершены, а при отмене (`SIGINT`,
`--timeout`) остановлены в пределах `cancel_grace`. Ход переживают **фоновые** дети (§17.3.8) и
фоновые команды (§17.9): без ожидания `codelab -p` вышел бы раньше, чем
их результат попадёт в ответ. Цель H-05 — только клиентская: CLI работает с агентом через ACP и
узнаёт о фоновой работе только через расширения (`_codelab/subagents` и аналогичные).

```text
codelab -p, после ответа на session/prompt (любого stopReason, кроме cancelled):
1  если агент не объявил ни одного расширения списков фоновой работы → выход сразу,
   лог debug cli.drain.unsupported
2  wakes := 0
3  pending := объединение list-ответов всех объявленных расширений (_codelab/subagents/list,
   _codelab/jobs/list, §17.9.11) по sessionId, элементы в состоянии queued | running | waiting
4  pending пуст и pendingNotices == 0 → выход
5  stderr (один раз): "codelab: waiting for <N> background item(s) (up to <T>s)…"
6  ждать, пока pending не опустеет или не появится pendingNotices > 0: по уведомлениям */update,
   без них — опрос list раз в 500 мс; общий предел на все шаги — --drain-timeout
   (по умолчанию subagents.drain_timeout = 60s; 0 — не ждать)
7  pendingNotices > 0, агент объявил agentCapabilities._meta.codelab.subagentWake и wakes < --max-wakes (по умолчанию 3):
     session/prompt с prompt [] и _meta.codelab.wake: true; ответ модели печатается в stdout
     после пустой строки (в stream-json — ход с `turn_start{trigger: "wake"}`, без пустой строки;
     dart-agent-and-clients §12.5.4); wakes += 1; перейти к шагу 3
   pendingNotices > 0 без agentCapabilities._meta.codelab.subagentWake → stderr "codelab: <N> background report(s) were not
     delivered: the agent does not support wake-up"; выход
8  предел истёк → _codelab/subagents/cancel для детей и _codelab/jobs/kill с reason: "drain"
   для задач, затем ещё до 5 с ожидания;
   stderr: "codelab: background work did not finish within <T>s; cancelled <N> item(s)"
9  код выхода — по stopReason последнего хода (H-02); если сработал шаг 8 и код был 0 → 1
10 повторный SIGINT во время ожидания → шаг 8 без ожидания, код 130
```

После ответа `cancelled` ожидание не выполняется: отмена хода фоновых детей не останавливает
(§17.3.8, шаг 5; SUB-4), поэтому CLI сразу отменяет их через `*/cancel` и выходит с кодом 130. Время ожидания не
входит в `--timeout` хода; ход пробуждения ограничен тем же `--timeout`.

После drain и итоговой строки CLI закрывает соединение; сессия, открытая с
`_meta.codelab.sealOnClose`, запечатывается (§8.5.1, S-15).

## 17.3.10. Конфигурация

**`subagents`**

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `enabled` | bool | `true` | `false` — инструмент `agent` не регистрируется (правило «выключено — невидимо», §10.9) |
| `max_depth` | int | `3` | наибольшая глубина потомка; 1–3, иначе `ConfigException`; `1` — у детей нет `agent` |
| `max_concurrent` | int | `3` | слотов на всё дерево корневой сессии (§17.3.4); 1–8, иначе `ConfigException` |
| `max_per_turn` | int | `10` | запусков `agent` во всём дереве за ход корневой сессии; 1–50 |
| `max_steps` | int | `30` | `TurnBudget.maxSteps` ребёнка |
| `max_tokens` | int | нет | `TurnBudget.maxTokens` ребёнка |
| `max_cost` | float | нет | `TurnBudget.maxCost` ребёнка, USD |
| `max_duration` | duration | `"10m"` | `TurnBudget.maxDuration` ребёнка, без ожидания одобрения |
| `report_max_bytes` | int | `16384` | предел отчёта до усечения (§17.3.5) |
| `progress_interval` | duration | `"2s"` | минимальный интервал `SubagentProgress` и строк прогресса |
| `heartbeat_interval` | duration | `"15s"` | строка прогресса при отсутствии событий |
| `cancel_grace` | duration | `"10s"` | ожидание остановки детей после отмены хода |
| `drain_timeout` | duration | `"60s"` | значение `--drain-timeout` по умолчанию для `codelab -p` (§17.3.9) |
| `background` | bool | `true` | фоновый режим (§17.3.8): параметр `run_in_background` и инструменты `agent_status`, `agent_cancel`; `false` — параметра и инструментов нет в схемах |
| `max_background` | int | `4` | одновременно активных фоновых детей сессии; 0–8 |
| `auto_wake` | bool | `true` | клиентская политика REPL и app: будить агента (`_meta.codelab.wake`), когда есть недоставленные уведомления и пользователь не печатает; без согласованного `subagentWake` не действует |
| `max_wakes` | int | `3` | значение `--max-wakes` по умолчанию для `codelab -p` (§17.3.9) |
| `follow_ups` | bool | `true` | инструменты `agent_send`, `agent_resume`, `agent_observe` (§17.3.8.1); `false` — их нет в схемах |
| `max_follow_ups` | int | `5` | прогонов ребёнка сверх первого; 0–20 |
| `max_resumes` | int | `2` | из них через `agent_resume`; 0–`max_follow_ups` |
| `idle_keep` | duration | `"2m"` | сколько дочерняя сессия остаётся открытой после отчёта; потом закрывается и для продолжения открывается из журнала |
| `observe_default` | int | `10` | `last` у `agent_observe` по умолчанию |
| `observe_max` | int | `50` | максимум `last`; 1–200 |
| `observe_message_max_chars` | int | `2000` | обрезка одного сообщения в `agent_observe` |
| `observe_max_bytes` | int | `16384` | предел результата `agent_observe` |

Модель субагента по умолчанию — роль `subagent` (`llm.roles.subagent.models = [...]`, L-10);
`explore`, `review`, `plan` сначала пробуют роли `smol`, `slow`, `plan`. Проектный конфиг может
только ужесточать `subagents` (меньшие лимиты, в том числе `max_depth`, `enabled = false`), как `permissions` (§15.3).

Базовый этап вводит ключи `enabled`, `max_depth`, `max_concurrent`, `max_per_turn`, `max_steps`,
`max_tokens`, `max_cost`, `max_duration`, `report_max_bytes`, `progress_interval`,
`heartbeat_interval`, `cancel_grace`. Остальные ключи таблицы появляются со своими этапами: ключ
схемы без потребителя давал бы `config.key.not_applied` (CFG-5).

Флаги `codelab -p --drain-timeout <длительность>` и `--max-wakes <n>` переопределяют `drain_timeout` и `max_wakes`. Проектный конфиг может выключить `background` и уменьшить `max_background`, но не включить их.

## 17.3.11. Примеры

Пользователь: «Найди, где проверяется токен, и посмотри, покрыто ли это тестами». Режим
`standard`, ACP-сессия `01JB8Q2W6R9T3M5K7N1P4X8Z0C`. Модель родителя отвечает двумя вызовами:

```json
[{"type":"toolCall","id":"call_3","name":"agent","arguments":{"description":"Find token validation","type":"explore","prompt":"Find where access tokens are validated in this repository. Report file paths with line ranges and a one-line summary of each check."}},
 {"type":"toolCall","id":"call_4","name":"agent","arguments":{"description":"Check token tests","type":"review","prompt":"List tests under test/ that cover access token validation. Run `git diff --stat` to see if validation code changed. Report covered and uncovered cases.","output_schema":{"type":"object","required":["covered","uncovered"],"properties":{"covered":{"type":"array","items":{"type":"string"}},"uncovered":{"type":"array","items":{"type":"string"}}}}}}]
```

Оба вызова — tier `read` в режиме `standard` → разрешены без вопроса. Ребёнок `explore` получает
режим `write` с запретом `write`/`exec` и инструменты `read`, `ls`, `search`; ребёнок `review` —
режим `write` и инструменты `read`, `ls`, `search`, `exec`. Его `exec git diff --stat` требует
вопроса. Кадры на проводе (уведомления сокращены до `update`):

```json
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","update":{"sessionUpdate":"tool_call","toolCallId":"call_3","title":"Subagent explore: Find token validation","kind":"think","status":"pending","rawInput":{"description":"Find token validation","type":"explore","prompt":"Find where access tokens are validated …"}}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","update":{"sessionUpdate":"tool_call","toolCallId":"call_4","title":"Subagent review: Check token tests","kind":"think","status":"pending","rawInput":{"…":"…"}}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","update":{"sessionUpdate":"tool_call_update","toolCallId":"call_3","status":"in_progress"}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","update":{"sessionUpdate":"tool_call_update","toolCallId":"call_4","status":"in_progress"}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","update":{"sessionUpdate":"tool_call_update","toolCallId":"call_3","content":[{"type":"content","content":{"type":"text","text":"explore · running · 2 steps · 3 tool calls · 8.4k tokens · Search \"verifyToken\" in lib"}}]}}}
{"jsonrpc":"2.0","id":31,"method":"session/request_permission","params":{"sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","toolCall":{"toolCallId":"call_4/call_2","title":"[review: Check token tests] Run git diff --stat","kind":"execute","status":"pending","rawInput":{"command":"git diff --stat"},"_meta":{"codelab":{"subagent":{"id":"sub_p2r7t9w1","type":"review","description":"Check token tests","depth":1,"path":[],"parentToolCallId":"call_4"}}}},"options":[{"optionId":"allow_once","name":"Allow once","kind":"allow_once"},{"optionId":"allow_always","name":"Always allow this command","kind":"allow_always"},{"optionId":"reject_once","name":"Reject","kind":"reject_once"},{"optionId":"reject_always","name":"Always reject","kind":"reject_always"}]}}
{"jsonrpc":"2.0","id":31,"result":{"outcome":{"outcome":"selected","optionId":"allow_once"}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","update":{"sessionUpdate":"tool_call_update","toolCallId":"call_3","status":"completed","content":[{"type":"content","content":{"type":"text","text":"Token validation:\n- lib/auth/token.dart:14-52 verifyToken: signature and expiry\n- lib/http/middleware.dart:30-41 rejects missing Authorization header"}}]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","update":{"sessionUpdate":"tool_call_update","toolCallId":"call_4","status":"completed","content":[{"type":"content","content":{"type":"text","text":"{\"covered\":[\"bad signature\",\"expired token\"],\"uncovered\":[\"missing header\"]}"}}]}}}
```

Что видит модель родителя в результатах (после ограды §6.3.6):

```text
<untrusted-content source="agent">
<subagent-report id="sub_k3f9a1c2" agent="explore" status="completed" steps="4" tool_calls="7">
Token validation:
- lib/auth/token.dart:14-52 verifyToken: signature and expiry
- lib/http/middleware.dart:30-41 rejects missing Authorization header
</subagent-report>
</untrusted-content>
```

```text
<untrusted-content source="agent">
<subagent-report id="sub_p2r7t9w1" agent="review" status="completed" steps="3" tool_calls="4">
{"covered":["bad signature","expired token"],"uncovered":["missing header"]}
</subagent-report>
</untrusted-content>
```

Ребёнок `explore` видит системный промпт (база, ограда, `modes/plan`, правила своих инструментов,
`subagent.system`, `## Agent profile: explore`) и одно user-сообщение с текстом `prompt`. Истории
родителя он не видит. Ребёнок `review` дополнительно видит секцию `subagent.output_schema`.

```mermaid
sequenceDiagram
    participant PL as "Цикл родителя"
    participant TT as "SubagentTool"
    participant SM as "SubagentManager"
    participant CH as "Дочерний AgentSession"
    participant PG as "PermissionGate родителя"
    participant CL as "ACP-клиент"
    PL->>TT: execute agent, type review
    TT->>SM: spawn(spec, cancel хода)
    SM->>SM: слот семафора, журнал ребёнка, запись subagent running
    SM-->>PL: SubagentStarted
    SM->>CH: prompt(текст задачи)
    CH->>CH: шаг модели, вызов exec git diff
    CH->>PG: request, toolCallId call_4/call_2, title с префиксом [review: Check token tests]
    PG->>CL: session/request_permission, sessionId родителя
    CL-->>PG: allow_once
    PG-->>CH: allowOnce
    CH->>CH: exec, следующий шаг, финальный ответ
    TT-->>PL: onUpdate, строка прогресса
    PL-->>CL: tool_call_update со строкой прогресса
    CH-->>SM: TurnEnded completed
    SM->>SM: отчёт, проверка схемы, запись subagent completed
    SM-->>TT: SubagentReport
    TT-->>PL: ToolExecutionResult с subagent-report
    PL-->>CL: tool_call_update completed, content отчёт
```

Состояния хэндла:

```mermaid
stateDiagram-v2
    [*] --> queued: spawn
    queued --> running: слот получен, журнал создан
    queued --> cancelled: отмена в очереди
    running --> waiting: запрос разрешения или ожидание своих детей
    waiting --> running: решение пользователя или слот после детей
    running --> completed: отчёт принят
    running --> failed: ошибка, бюджет или невалидный отчёт
    running --> cancelled: отмена токена
    waiting --> cancelled: отмена токена
    completed --> [*]
    failed --> [*]
    cancelled --> [*]
```

Состояния `completed`, `failed`, `cancelled` — терминальные для прогона; обратного перехода нет: продолжение (`agent_send`, `agent_resume`) — новый прогон с новым `report` (§17.3.8.1). Ремонт
отчёта по схеме (§17.3.5, шаг 3) идёт в состоянии `running`.

## 17.3.12. Инварианты

1. **SUB-1.** Набор инструментов ребёнка — подмножество набора схем текущего шага родителя; `agent` в нём есть только при `depth < max_depth`; инструменты списка задач — только детский вариант (чтение и статус своих пунктов, §17.16.4); `update_plan` в ядре больше нет.
2. **SUB-2.** Эффективный режим ребёнка не мягче режима родителя ни в один момент: он вычисляется при каждом решении как `narrow(parentMode(), type.mode)`; запреты уровней объединяются; для потомка любой глубины сужение идёт по всей цепочке предков. `PolicyRules` и хранилище решений «всегда» — общие для дерева, хранилище — корневой сессии.
3. **SUB-3.** Каждый запрос разрешения потомка любой глубины проходит через gate корневой сессии с её `sessionId`, `toolCallId`-цепочкой от вызова `agent` корня и title с префиксом `[<agent>: <description>] `; запросы потомков одного дерева уходят пользователю по одному.
4. **SUB-4.** Блокирующий ребёнок не переживает вызов `agent`, который его запустил: `ToolCallFinished(agent)` эмитится только после терминального состояния хэндла (или истечения `cancel_grace`). Фоновый ребёнок (§17.3.8) не переживает родительскую сессию: его токен — потомок токена сессии, `closeAll` его отменяет, а `session/cancel` хода — нет.
5. **SUB-5.** Одновременно слот держат не больше `max_concurrent` потомков одного дерева (в `running` или `waiting` с `waitingFor: approval`; ребёнок, ждущий своих детей, слота не держит); запусков во всём дереве за ход корневой сессии — не больше `max_per_turn`; ребёнок, отменённый в очереди, не делает ни одного запроса к модели и не создаёт журнал.
6. **SUB-6.** Отмена токена хода родителя отменяет всех его блокирующих детей и, каскадом, их потомков (фоновых — нет: их токен — потомок токена сессии, §17.3.8); отмена ребёнка не отменяет родителя, других детей и их потомков.
7. **SUB-7.** В контекст модели родителя от ребёнка попадает только результат `agent`: обёртка `<subagent-report>` внутри ограды `untrusted-content`; сообщения ребёнка в транскрипт и журнал родителя не попадают.
8. **SUB-8.** При заданной `output_schema` отчёт `completed` всегда валиден по схеме; ремонт выполняется не более одного раза; иначе — `failed` с `invalid_output`.
9. **SUB-9.** История потомка любой глубины — в отдельном журнале в каталоге `<файл корневой сессии без .jsonl>/subagents/`; заголовок содержит `parent.sessionId` (прямой родитель), `parent.rootSessionId`, `parent.toolCallId` и `parent.depth`; журнал прямого родителя содержит записи `subagent` со ссылкой на журнал; дочерние журналы не входят в `session/list`.
10. **SUB-10.** Итоговая запись `subagent` с отчётом пишется (`durable`) до `ToolCallFinished(agent)`. После сбоя ребёнок не перезапускается: вызов `agent` получает результат из итоговой записи, если она есть, иначе — `interrupted`.
11. **SUB-11.** Usage блокирующих детей входит в usage хода родителя и в проверку его `maxTokens`/`maxCost`, транзитивно до корневой сессии; потомок останавливается, когда исчерпан бюджет его или любого предка; usage фонового ребёнка — в usage сессии и хода, в котором доставлено его уведомление.
12. **SUB-12.** Клиенту без `clientCapabilities._meta.codelab.subagentToolCalls` вызовы инструментов потомков не отправляются как `tool_call`; от потомков к нему уходят только запросы разрешения (и, при согласованном расширении, снимки доски). Клиенту с `subagentToolCalls` вызовы потомков уходят `tool_call`/`tool_call_update` с цепочкой `toolCallId` и `_meta.codelab.parentToolCallId`, а при завершении вызова `agent` открытых вызовов его поддерева не остаётся (этап 2); тексты и мысли потомков не отправляются никому.
13. **SUB-13.** Агент никогда не начинает ход сам: уведомление фонового ребёнка входит в контекст только внутри хода — через `steer` идущего хода или в начале хода, открытого `session/prompt` клиента (в том числе пробуждением `_meta.codelab.wake`).
14. **SUB-14.** Каждое уведомление фонового ребёнка доставляется в контекст родителя ровно один раз: недоставленные восстанавливаются после сбоя по итоговым записям `subagent` без `message` с `origin: "subagent_notice"`; доставленные не повторяются.
15. **SUB-15.** Фоновый ребёнок не отправляет `session/request_permission`, пока у родителя нет хода: вызов, требующий вопроса, получает отказ `Approval is not available: the session is idle…`; решения без вопроса применяются как обычно.
16. **SUB-16.** Одновременно активных фоновых детей сессии не больше `max_background`; фоновые и блокирующие дети делят один семафор `max_concurrent` и общий счётчик `max_per_turn`.
17. **SUB-17 – SUB-22.** Продолжение работы с ребёнком (`agent_send`, `agent_resume`, `agent_observe`) — §17.3.8.1, «Инварианты».
18. **SUB-23.** Держатель слота дерева никогда не ждёт другого слота: ребёнок, ждущий своих детей, слот возвращает и получает его снова раньше новых детей очереди. Поэтому при любом `max_depth` и `max_concurrent ≥ 1` дерево не попадает во взаимоблокировку на слотах.
19. **SUB-24.** Глубина потомка не больше `max_depth` (≤ 3): у потомка глубины `max_depth` инструмента `agent` нет. Каждое событие потомка доходит до потока корневой сессии ровно одной обёрткой `SubagentActivity` с его `subagentId`, `path` и `parentToolCallId`.

## 17.3.13. Обоснование решения

* **Тип субагента = `AgentDefinition`.** Один формат (§15.8) для «агента сессии» и «типа задачи»:
  пользователь пишет `reviewer.md` один раз и получает и опцию `agent`, и тип `agent`. Поле
  `scope` нужно, чтобы определение-задача (например, генератор JSON-отчёта) не засоряло список
  агентов сессии.
* **Глубина до 3, настройкой (решение пользователя 2026-11-09; было — «глубина 1 без
  настройки»).** Цель — поведение уровня Claude Code, где субагент может поручить часть работы
  своему субагенту. Прежние возражения сняты устройством, а не запретом:
  * *взаимоблокировка слотов* (все слоты у детей, которые ждут слотов для внуков) невозможна:
    ждущий детей родитель слот возвращает, держатели слотов чужих слотов не ждут (SUB-23);
  * *геометрический рост стоимости* ограничен лимитами дерева, а не уровня: один `max_concurrent`,
    один `max_per_turn` и бюджет хода корневой сессии, который проверяют все потомки (SUB-11);
  * *потеря контроля пользователя*: все вопросы потомков идут через gate корня с адресом
    `_meta.codelab.subagent`, режим сужается по всей цепочке (SUB-2, SUB-3).
  Потолок 3 — граница здравого смысла и длины цепочки `toolCallId`; `max_depth: 1` возвращает
  прежнее поведение. Альтернативы: (а) отдельный семафор на каждый уровень — без
  взаимоблокировки, но параллельность растёт с глубиной и не ограничена одним числом; (б)
  резервирование слотов под внуков при запуске ребёнка — простаивающие слоты и сложный учёт;
  (в) оставить глубину 1 — противоречит решению пользователя.
* **Режим вычисляется при каждом решении.** Снимок режима на старте позволил бы ребёнку
  продолжать править файлы после того, как пользователь переключил родителя в `plan`.
* **Разрешения через gate родителя, `allowAlways` общий.** У ребёнка нет своего клиента: ACP
  знает только сессию родителя. Общие множества решений дают пользователю ожидаемое поведение:
  «всегда разрешить `dart test`» действует для всей задачи, а «всегда отклонять» нельзя обойти,
  поручив то же действие ребёнку.
* **Сериализация запросов детей.** Три одновременных диалога одобрения клиенты показывают плохо,
  а пользователь не успевает понять, кто что просит. Очередь стоит секунд, но не ошибок.
* **Вызовы детей не проецируются.** См. §17.3.7: ACP без вложенности, лента превращается в шум;
  детали — в журнале и на доске.
* **Отчёт всегда `untrusted`.** Ребёнок читает файлы, вывод команд и MCP; его текст — пересказ
  недоверенных данных. Отметить отчёт `trusted` значило бы открыть обход ограды через ребёнка.
* **Отчёт в итоговой записи `subagent`.** Результаты параллельного пакета пишутся в транскрипт
  только после всего пакета (§5.5). Без записи с отчётом сбой после окончания первого ребёнка
  терял бы его работу; с ней — S-13 выполняется и для детей.
* **Фоновый режим без хода, начатого агентом.** В ACP ход начинает только клиент, поэтому
  агент не «будит» сам себя по завершении ребёнка. Доставка разделена по состоянию родителя:
  steering идущего хода (внутреннее дело ядра, без расширений), очередь до следующего
  `session/prompt` (стандартный ACP) и необязательное пробуждение, при котором `session/prompt`
  шлёт клиент (расширение через OpenSpec). Альтернатива «держать фоновых детей только внутри
  хода» лишила бы режим смысла, а «агент шлёт обновления вне хода и сам вызывает модель» нарушила
  бы ACP: у такого хода нет запроса, на который можно ответить `stopReason`.
* **Без вопросов в простое.** `session/request_permission` вне хода клиенты не ждут и могут не
  показать; зависший запрос остановил бы ребёнка навсегда. Отказ с понятной причиной оставляет
  ребёнку возможность закончить и описать в отчёте, что нужно одобрить.
* **Отмена хода не трогает фоновых детей.** Пользователь, прервавший текущий ответ, не обязательно
  хочет потерять долгую фоновую работу; для неё есть `/tasks cancel` и `agent_cancel`.
* **Лимит 3 по умолчанию.** Больше параллельных детей упираются в rate limit провайдера и в
  очередь одобрений; 3 дают выигрыш на типичной задаче «исследовать два-три места кода».
* **Источник поведения.** Ориентир — наблюдаемое поведение Claude Code (Anthropic): субагенты с
  отдельным контекстом, вложенность и общий список задач. Код, промпты, описания инструментов и
  тексты Claude Code не воспроизводятся; все тексты раздела написаны заново (`AGENTS.md` §5,
  [§7а](../dart-agent-and-clients/07-decision-sources.md#7а-политика-стороннего-кода)). Записи в
  `THIRD_PARTY_NOTICES.md` не нужно: конкретный внешний алгоритм, список или таблица не повторяются.

## 17.3.14. Как проверить

* `agent_tool_schema_test.dart`: `enum` поля `type` — встроенные типы и определения со `scope`
  `subagent`/`both`, по алфавиту; определение со `scope: session` отсутствует; описание
  инструмента рендерится с `maxConcurrent` и `agentList`; неверные `description`/`prompt` —
  ошибки с текстами §17.3.2, ребёнок не создан.
* `subagent_tools_intersection_test.dart`: родитель с профилем без `exec` + тип `review` →
  набор `read`, `ls`, `search`; при `max_depth: 3` у ребёнка глубины 1 и 2 есть `agent`, у глубины 3
  нет; при `max_depth: 1` `agent` нет у ребёнка; инструменты списка задач у ребёнка — детский
  вариант (SUB-1, SUB-24).
* `subagent_nested_slots_test.dart` (`core/subagent-nested-no-deadlock`): `max_concurrent: 1`,
  `max_depth: 3`, ребёнок запускает внука, внук — правнука → все трое завершаются, ни один не
  ждёт слот дольше работы держателя; родитель, дождавшийся детей, получает слот раньше нового
  ребёнка, поставленного в очередь позже (SUB-23); пакет из трёх `agent` корня, каждый из которых
  запускает по два внука, при `max_concurrent: 2` — в любой момент не больше двух держателей слота
  (SUB-5).
* `subagent_tree_budget_test.dart`: бюджет хода корня `maxTokens` исчерпан usage внука, пока корень
  и ребёнок ждут → внук останавливается на своей границе шага с `budget_exceeded:tokens`, usage
  внука входит в `TurnEnded.usage` корня (SUB-11); `max_per_turn: 3` считает запуски внуков.
* `subagent_activity_test.dart`: события внука приходят в поток корня одной обёрткой
  `SubagentActivity` с `depth: 2`, `path: [id ребёнка]` и `parentToolCallId` вызова `agent` ребёнка;
  журнал корня их не содержит; журнал внука — в `subagents/` корня (SUB-9, SUB-24).
* `subagent_mode_narrow_test.dart`: таблица `parentMode × type.mode` из §17.3.3, шаг 4; родитель
  переключён в `plan` посреди работы ребёнка → следующий `write` ребёнка отклонён (SUB-2).
* `subagent_permission_prefix_test.dart`: запрос ребёнка приходит в fake gate родителя с
  `toolCallId` `call_3/call_1`, title с префиксом; два ребёнка просят одновременно → второй
  запрос уходит только после ответа на первый; `allow_always` в ребёнке действует для родителя;
  `reject_always` родителя действует для ребёнка (SUB-3).
* `core/agent-two-children-parallel` (`agent_parallel_test.dart`, scripted LLM для родителя и
  детей): два `agent` в одном ответе — оба ребёнка стартуют до завершения любого; `max_concurrent
  = 1` — второй стартует после первого; порядок результатов в транскрипте — порядок вызовов,
  `ToolCallFinished` — порядок завершения; четыре `agent` при `max_concurrent = 3` — один в
  `queued`; одиннадцатый вызов при `max_per_turn = 10` — ошибка лимита (SUB-5, LOOP-3).
* `subagent_cancel_test.dart`: отмена хода родителя → оба ребёнка `cancelled`, `TurnEnded`
  родителя после двух `ToolCallFinished(cancelled)`; ребёнок в очереди не вызывает модель и не
  создаёт файл; `manager.cancel` одного ребёнка не трогает второго и родителя (SUB-4, SUB-6).
* `subagent_report_schema_test.dart`: валидный JSON с первого раза; невалидный → ровно один
  ремонт с текстом `schema_fix`, затем `completed`; два невалидных → `failed` с `invalid_output`;
  JSON внутри fenced-блока извлекается; отчёт длиннее `report_max_bytes` усечён с пометкой
  (SUB-8).
* `subagent_report_wrapper_test.dart`: обёртка и атрибуты для каждого исхода таблицы §17.3.5;
  `</subagent-report` в тексте экранирован; результат внутри `untrusted-content source="agent"`
  (SUB-7).
* `subagent_budget_test.dart`: `max_steps = 2` у ребёнка → `failed` с
  `budget_exceeded:steps`; usage ребёнка входит в `TurnEnded.usage` родителя и останавливает
  родителя по `maxTokens` на ближайшей границе шага (SUB-11).
* `subagent_journal_test.dart`: файл ребёнка в `<родитель>/subagents/`, заголовок с `parent`;
  две записи `subagent` в журнале родителя (`running`, итог с `report`); `session/list` не
  содержит ребёнка; `session/load` id ребёнка → `-32602` с `reason: subagentSession` (SUB-9).
* `subagent_resume_test.dart` (`core/subagent-interrupted-not-restarted`): процесс убит, когда
  ребёнок A завершён (итоговая запись есть), а B работает → после `open` вызов A получает отчёт
  из записи, B — `interrupted`, в журнал B дописан синтетический результат, ни один ребёнок не
  запущен снова (SUB-10, SES-10).
* `acp/prompt-subagent-tool-call`: `tool_call` с `kind: "think"` и title `Subagent explore: …`,
  `in_progress`, хотя бы одна строка прогресса, `completed` с телом отчёта в `content`; ни одного
  `tool_call` с id вызова ребёнка (SUB-12).
* `acp/prompt-subagent-permission`: ребёнок `review` просит `exec`; кадр
  `session/request_permission` с `sessionId` родителя, `toolCallId` `call_4/call_2`, префиксом
  title и `_meta.codelab.subagent`; `reject_once` → ребёнок продолжает и сдаёт отчёт (PERM-7).
* `acp/prompt-subagent-nested-permission`: внук глубины 2 просит `exec` → `toolCallId`
  `call_1/call_1/call_1`, `_meta.codelab.subagent` с `depth: 2`, `path` из id ребёнка и
  `parentToolCallId: "call_1"` (SUB-3).
* `acp/initialize-codelab-extensions`: клиент объявил `clientCapabilities._meta.codelab: {}` →
  ответ содержит `agentCapabilities._meta.codelab.subagents` с `maxDepth` и `tasks`; клиент без
  этого объявления получает ответ `acp/initialize-capabilities` без изменений.
* `acp/session-load-subagent-interrupted`: реплей после сбоя показывает завершённый `agent` как
  `completed`, прерванный — `failed` с `_meta.codelab.outcome: "interrupted"`.
* `cli/headless-drains-background-job`: scripted-агент объявляет расширение списка фоновой
  работы и после ответа на `session/prompt` сообщает один элемент `running`, через 2 с —
  `completed` → CLI печатает строку ожидания в stderr и выходит с кодом 0 после завершения
  элемента; вариант с `--drain-timeout 1s` → `*/cancel` для элемента, строка о прерывании, код 1;
  агент без расширения → выход сразу (§17.3.9); вариант с фоновыми командами — §17.9.16.
* `cli/headless-subagent-cancel-timeout`: `codelab -p --timeout 2s`, ребёнок работает дольше →
  ответ `cancelled` приходит после остановки ребёнка, код выхода 130, журнал ребёнка
  завершён записью результата `cancelled`.
* `acp_projection_exhaustive_test.dart` (ACP-6): строки таблицы §17.3.7 есть для
  `SubagentStarted`, `SubagentProgress`, `SubagentFinished`.
* `subagent_background_test.dart` (`core/agent-background-notice-steered`): `agent` с
  `run_in_background: true` возвращается сразу с текстом `Started background subagent …`, ход
  родителя продолжается; ребёнок завершается во время хода → уведомление доставлено `steer` на
  ближайшей границе шага; ребёнок завершается после хода → уведомление входит в контекст перед
  сообщением пользователя следующего `prompt()`; `session/cancel` хода фонового ребёнка не
  отменяет, `closeAll` — отменяет (SUB-4, SUB-13).
* `subagent_background_approval_test.dart`: фоновый ребёнок просит `exec` во время хода родителя →
  запрос через gate с префиксом; после хода → отказ `Approval is not available: the session is
  idle…` без кадра `session/request_permission`; вызов из `allowAlways` исполняется без вопроса
  (SUB-15).
* `subagent_background_resume_test.dart` (`core/agent-background-notice-once`): процесс убит после
  итоговой записи фонового ребёнка, но до доставки → после `open` уведомление доставлено при
  следующем `prompt()` ровно один раз; убит до итоговой записи → `interrupted`, ребёнок не
  перезапущен; повторный `open` после доставки уведомления не повторяет (SUB-14).
* `subagent_background_limits_test.dart`: пятый фоновый при `max_background = 4` → ошибка
  лимита; фоновые и блокирующие делят `max_concurrent` (SUB-16); `agent_status` с
  `wait_seconds: 5` возвращает уведомление ребёнка, завершившегося за время ожидания; `agent_cancel`
  неизвестного id — текст `Subagent <id> is not running…`.
* `acp/prompt-subagent-background`: `tool_call` `agent` сразу `completed` с текстом запуска; ответ
  `end_turn`; следующий `session/prompt` — модель получает уведомление перед сообщением
  пользователя; при реплее (`session/load`) уведомление не отправляется как `user_message_chunk`.
* `acp/slash-tasks`: `/tasks` перечисляет фоновых детей, `/tasks cancel <id>` отменяет; модель не
  вызывается.
* `cli/headless-background-wake` (после OpenSpec `subagentWake`): `codelab -p`, модель запускает
  фонового ребёнка и отвечает; CLI ждёт, получает `pendingNotices: 1`, шлёт `session/prompt` с
  `_meta.codelab.wake`, печатает второй ответ, код 0; `--max-wakes 0` → строка о недоставленном
  отчёте в stderr; `--drain-timeout 1s` при долгом ребёнке → `*/cancel`, код 1.

---

← [17.2. Skills и шаблоны промптов](17-2-skills-and-templates.md) · [Оглавление ядра](../agent-core-architecture.md) · [17.4. Вынос огромного результата инструмента в файл (T-28)](17-4-output-spill.md) →
