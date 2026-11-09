## ADDED Requirements

### Requirement: Инструмент agent и типы субагентов
Ядро SHALL регистрировать инструмент `agent` на сессию при `subagents.enabled` (по умолчанию `true`; `false` — ни схемы, ни секции промпта). `agent` — tier `read`, kind `think`, `outputTrust` `untrusted`, `permissionPattern` — имя типа (agent-core-architecture §17.3.2).

Схема базового этапа:
- `description` — обязательное, 3–60 символов после обрезки пробелов;
- `prompt` — обязательное, 1–32768 символов;
- `type` — `enum` из имён типов субагентов, по умолчанию `general`;
- `task` — необязательное, id пункта списка задач; поле есть только в схеме корневой сессии.

Полей `output_schema` и `run_in_background` в базе нет.

Типы SHALL браться из встроенных определений `general`, `explore`, `review`, `plan` (`source: builtin:<name>`) и из определений агентов со `scope` `subagent` или `both`. Пользовательское определение с тем же именем заменяет встроенное с логом `subagent.type_overridden`. Определение со `scope: session` в `enum` не входит. Снимок типов и `enum` SHALL фиксироваться при создании сессии.

Ошибки проверки SHALL давать результат-ошибку без создания ребёнка. Тексты:
- `Invalid agent call: description must be 3-60 characters.`;
- `Invalid agent call: prompt must be 1-32768 characters.`;
- `Unknown agent type "<x>". Available: <имена через ", ">.`;
- `Unknown task #<id>. …` (§17.16.3).

#### Scenario: Enum типов
- **WHEN** у доверенного проекта есть определения `reviewer` (`scope: both`) и `notes` (`scope: session`)
- **THEN** `enum` поля `type` — `explore`, `general`, `plan`, `review`, `reviewer` по алфавиту, без `notes` (`agent_tool_schema_test.dart`)

#### Scenario: Неверный заголовок
- **WHEN** модель вызывает `agent` с `description` из двух символов
- **THEN** результат — ошибка `Invalid agent call: description must be 3-60 characters.`, ни дочерней сессии, ни журнала не создано

### Requirement: Сборка ребёнка
`SubagentManager.spawn` SHALL строить ребёнка из текущего состояния родителя по §17.3.3:
- **Инструменты.** `base` — схемы текущего шага родителя. Набор ребёнка = `type.tools == null ? base : base ∩ type.tools`. `agent` SHALL входить в набор, только если `depth < max_depth`. Инструменты списка задач SHALL входить только детским вариантом (agent-tools «Инструменты списка задач»). Инструмент типа, которого нет у родителя, не добавляется (SUB-1).
- **Режим.** Эффективный режим SHALL вычисляться при каждом решении как `narrow(parentMode(), type.mode)` по всей цепочке предков (SUB-2).
- **Модель.** `type.model`, иначе текущая модель родителя.
- **Промпт.** `composeSystemPrompt` для набора и режима ребёнка, затем `subagent/system`, затем профиль типа, затем строка назначенного пункта, если он есть.
- **Задача.** Ребёнок получает одно user-сообщение с текстом `prompt`; истории родителя он не видит.

#### Scenario: Пересечение инструментов
- **WHEN** родитель без `exec` вызывает `agent` с типом `review`
- **THEN** набор ребёнка — `read`, `ls`, `search` и детский вариант задач, без `exec` (`subagent_tools_intersection_test.dart`)

#### Scenario: Смена режима родителя посреди работы ребёнка
- **WHEN** ребёнок `general` работает, а пользователь переключает корневую сессию в `plan`
- **THEN** следующий вызов `write` ребёнка отклонён причиной режима `plan` без вопроса (`subagent_mode_narrow_test.dart`)

### Requirement: Вложенность и слоты дерева
Глубина ребёнка SHALL быть глубиной родителя плюс 1 (корневая сессия — 0) и не больше `subagents.max_depth` (1–3, по умолчанию 3). У потомка глубины `max_depth` инструмента `agent` SHALL не быть (SUB-24).

`SubagentTree` (один на корневую сессию) SHALL держать `max_concurrent` слотов на всё дерево:
- слот держит потомок в `running` или в `waiting` с `waitingFor: approval`;
- потомок, ждущий своих детей блокирующим `agent`, SHALL переходить в `waiting` с `waitingFor: subagents` и возвращать слот;
- когда дети его пакета терминальны, потомок SHALL получать слот снова раньше новых детей очереди, до следующего запроса к модели (SUB-23);
- новые дети SHALL получать слоты в порядке `spawn`;
- число `spawn` во всём дереве за ход корневой сессии SHALL быть не больше `max_per_turn`. Сверх лимита — ошибка `Subagent limit reached: at most <N> subagents per turn. …` (SUB-5);
- ребёнок, отменённый в очереди, SHALL не делать запросов к модели и не создавать журнал.

Значения `max_depth`, `max_concurrent`, `max_per_turn` и бюджетов SHALL браться из ключей `subagents.*` текущего `CoreConfig` при каждом `spawn` (agent-configuration «Ключи subagents в схеме и реестре настроек»); `max_depth` и `enabled` меняют схему `agent` только в новых сессиях.

#### Scenario: Нет взаимоблокировки при одном слоте
- **WHEN** `max_concurrent: 1`, `max_depth: 3`, ребёнок запускает внука, внук — правнука
- **THEN** все трое завершаются, ход корня завершается `end_turn` (`core/subagent-nested-no-deadlock`)

#### Scenario: Возвращающийся родитель раньше нового ребёнка
- **WHEN** при `max_concurrent: 1` внук завершился, а в очереди уже стоит новый ребёнок корня, поставленный позже
- **THEN** слот получает ребёнок-родитель внука, новый ребёнок — после него (`subagent_nested_slots_test.dart`)

#### Scenario: Предел слотов дерева
- **WHEN** корень вызывает в одном ответе три `agent`, каждый ребёнок — по два `agent`, при `max_concurrent: 2`
- **THEN** в любой момент слот держат не больше двух потомков

#### Scenario: Лимит запусков считает внуков
- **WHEN** `max_per_turn: 3`, корень запускает двух детей, первый из них — двух внуков
- **THEN** второй внук получает ошибку лимита, остальные работают

### Requirement: Бюджет и usage дерева
Usage потомка SHALL входить в usage прямого родителя (`subagentUsage`) и транзитивно в usage хода корневой сессии.

У потомка SHALL быть свой `TurnBudget` из `subagents.max_steps`, `max_tokens`, `max_cost`, `max_duration`. На каждой границе шага потомок SHALL проверять также остаток `maxTokens`/`maxCost` всех предков до бюджета хода корня. Исчерпан бюджет любого из них → потомок останавливается с `failed` и `failure: budget_exceeded:<limit>` (SUB-11).

#### Scenario: Бюджет корня останавливает внука
- **WHEN** `maxTokens` хода корня исчерпан usage внука, пока корень и ребёнок ждут
- **THEN** внук останавливается на своей границе шага с `budget_exceeded:tokens`, его usage входит в `TurnEnded.usage` корня (`subagent_tree_budget_test.dart`)

### Requirement: Жизненный цикл и отмена
Хэндл SHALL проходить состояния `queued`, `running`, `waiting`, `completed`, `failed`, `cancelled`. Терминальное состояние SHALL наступать ровно один раз; `report` SHALL завершаться ровно один раз и никогда ошибкой. При гонке отмены и завершения выигрывает первое записанное терминальное состояние.

Токен ребёнка SHALL быть потомком токена хода его родителя: отмена хода корня отменяет всё дерево, отмена ребёнка — его и его потомков, но не родителя и не соседей (SUB-6). `SubagentTool` SHALL ждать остановки детей не дольше `cancel_grace` от момента отмены, затем возвращать `cancelled`. `TurnEnded(cancelled)` родителя SHALL приходить после `ToolCallFinished` всех его `agent` (CAN-5).

События ребёнка после терминального состояния хэндла SHALL не переизлучаться, а его вопрос из очереди SHALL сниматься с исходом `cancelled`.

#### Scenario: Отмена хода корня
- **WHEN** во время работы ребёнка и внука клиент шлёт `session/cancel`
- **THEN** оба получают `cancelled`, `TurnEnded(cancelled)` корня приходит после `ToolCallFinished(agent)` с `cancelled` (`subagent_cancel_test.dart`)

#### Scenario: Отмена в момент завершения
- **WHEN** отмена хода приходит, когда ребёнок уже эмитит `TurnEnded(completed)`
- **THEN** у хэндла ровно одно терминальное состояние, вызов `agent` получает ровно один результат, лишних событий ребёнка после него в потоке родителя нет

### Requirement: Отчёт ребёнка
Отчёт SHALL строиться по §17.3.5 без ремонта по схеме: текст последнего ответа ребёнка; статус по `TurnEnded.reason`; усечение до `report_max_bytes` с пометкой.

Модель родителя SHALL получать один блок `<subagent-report id agent status steps tool_calls …>` внутри ограды `untrusted-content source="agent"`. Вхождения `</subagent-report` в тексте отчёта экранируются (SUB-7). Атрибуты и тела исходов — по таблице §17.3.5.

#### Scenario: Обёртка отчёта
- **WHEN** ребёнок `explore` завершается текстом с подстрокой `</subagent-report>`
- **THEN** результат `agent` — одна обёртка с `status="completed"` внутри ограды, подстрока экранирована (`subagent_report_wrapper_test.dart`)

#### Scenario: Бюджет ребёнка
- **WHEN** `max_steps: 2`, а ребёнку нужно три шага
- **THEN** результат — `isError: true`, атрибут `reason="budget_exceeded:steps"`

### Requirement: Журнал субагента и прерывание
Журнал потомка любой глубины SHALL лежать в `<журнал корневой сессии без .jsonl>/subagents/`. Его заголовок SHALL содержать `parent` с полями `sessionId` (прямой родитель), `rootSessionId`, `toolCallId`, `subagentId`, `agent`, `depth`.

В журнал прямого родителя SHALL писаться запись `subagent`:
- `status: running` — при получении слота;
- итоговая запись с `status`, `failure`, `report`, `usage` — `durable`, до `ToolCallFinished(agent)` (SUB-9, SUB-10).

Дочерние журналы НЕ SHALL попадать в `session/list` и `index.json`. Lease корневой сессии SHALL покрывать журналы всего дерева.

После сбоя `healInterruptedTurn` SHALL для каждого вызова `agent` без результата:
- взять результат из итоговой записи `subagent`, если она есть;
- иначе записать `interrupted`, дописать `subagent{status: failed, failure: interrupted}` и рекурсивно вылечить журнал ребёнка.

Ни один потомок НЕ SHALL перезапускаться.

#### Scenario: Раскладка внука
- **WHEN** ребёнок запускает внука
- **THEN** журнал внука лежит в `subagents/` корневой сессии, его заголовок — `parent.sessionId` ребёнка и `depth: 2`, запись `subagent` внука — в журнале ребёнка (`subagent_journal_test.dart`)

#### Scenario: Сбой с двумя детьми
- **WHEN** процесс убит, когда ребёнок A завершён (итоговая запись есть), а B работает
- **THEN** после `open` вызов A получает отчёт из записи, B — `interrupted`, ни один ребёнок не запущен снова (`core/subagent-interrupted-not-restarted`)

### Requirement: События потомков в потоке родителя
`SubagentManager` SHALL эмитить в поток родителя `SubagentStarted`, `SubagentProgress` и `SubagentFinished`:
- порядок: `ToolCallStarted(agent)` → `SubagentStarted` → `SubagentProgress`… → `SubagentFinished` → `ToolCallFinished(agent)`;
- ребёнок, отменённый в очереди, даёт только `SubagentFinished(cancelled)`.

Каждое событие дочерней сессии родитель SHALL переизлучать как `SubagentActivity(subagentId, parentToolCallId, path, depth, event)`:
- обёртка плоская: событие внука переизлучается с исходным `event` и адресом внука;
- вложенных `SubagentActivity` нет (SUB-24).

`SubagentTool` SHALL вызывать `onUpdate` строкой прогресса `<agent> · <state> · <steps> steps · <toolCalls> tool calls · <tokens> tokens[ · <n> subagents][ · <lastActivity>]` (§17.3.4):
- при каждом `SubagentProgress`, но не чаще `progress_interval`;
- без событий — раз в `heartbeat_interval`.

#### Scenario: Адрес события внука
- **WHEN** внук вызывает `read`
- **THEN** поток корневой сессии содержит `SubagentActivity` с `depth: 2`, `path: [id ребёнка]`, `parentToolCallId` вызова `agent` ребёнка и `event` типа `ToolCallStarted`; журнал корня этого события не содержит (`subagent_activity_test.dart`)
