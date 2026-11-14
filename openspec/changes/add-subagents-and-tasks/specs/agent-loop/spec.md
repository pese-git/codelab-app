## MODIFIED Requirements

### Requirement: События AgentEvent
Цикл, `Agent` и `AgentSession` SHALL сообщать о ходе закрытой иерархией `AgentEvent`:
- `TurnStarted`, `StepStarted`, `ModelRequested` (с `estimatedTokens` — оценкой payload, 0 без оценщика);
- `MessageStarted` (с `origin` служебного сообщения), `MessageDelta`, `ThoughtDelta`, `MessageEnded`;
- `ToolCallStarted` (с необязательным `subagent` — `SubagentCallRef(id, type)` у вызова `agent`, из `ToolPresentation.subagent`; change `add-subagents-and-tasks`, D28), `ToolCallProgress`, `ToolCallFinished` (с `outcome`, `diffs` и признаком `interrupted` у синтетического результата реплея), `ToolPairingRepaired`;
- `StepEnded`, `ModeChanged`, `AgentError`, `TurnEnded`;
- `ContextCompacted(tokensBefore, tokensAfter)` — сжатие уже записано в журнал (§9.8);
- `SessionTitleChanged(title, updatedAt)` — событие уровня `AgentSession`, заголовок записан в журнал (§8.3);
- `TaskListChanged(items, change)` — список задач дерева изменился (§17.16.2); заменяет `PlanUpdated`, которого в иерархии больше нет (change `add-subagents-and-tasks`, D13);
- `SubagentStarted`, `SubagentProgress`, `SubagentFinished` — события уровня `AgentSession` родителя о его ребёнке (§17.3.2);
- `SubagentActivity(subagentId, parentToolCallId, path, depth, event)` — событие потомка, переизлучённое в поток родителя; `event` никогда не `SubagentActivity` (§17.3.2, SUB-24).

Поля событий и моменты эмиссии SHALL соответствовать таблице §5.3 документа ядра, таблице §8.3 для событий сессии и §17.3.2, §17.16.2 для событий субагентов и списка задач. События остальных этапов добавляются ветками иерархии без изменения перечисленных.

Цикл SHALL ждать завершения каждого `emit`: следующее событие не эмитится, пока подписчики не обработали предыдущее (LOOP-2). Это относится и к переизлучению `SubagentActivity`. В параллельном пакете `ToolCallFinished` приходят в порядке завершения, а сообщения-результаты в транскрипте идут в порядке вызовов в ответе модели (LOOP-3).

#### Scenario: Медленный подписчик
- **WHEN** подписчик обрабатывает каждое событие через `await Future.delayed`
- **THEN** события приходят строго по одному, в порядке эмиссии

#### Scenario: Порядок параллельного пакета
- **WHEN** в одном шаге два параллельных вызова и второй завершается раньше первого
- **THEN** события идут как `ToolCallStarted(c1), ToolCallStarted(c2), ToolCallFinished(c2), ToolCallFinished(c1)`, а результаты в транскрипте — как `c1, c2`

#### Scenario: Оценка в ModelRequested
- **WHEN** у цикла есть `estimateTokens`
- **THEN** `ModelRequested.estimatedTokens` равен её результату для payload этого запроса

#### Scenario: Список задач до результата вызова
- **WHEN** модель вызывает `task_create`
- **THEN** `TaskListChanged` приходит между `ToolCallStarted` и `ToolCallFinished` этого вызова

### Requirement: Пакет инструментов
Пакет вызовов одного ответа SHALL исполняться по §5.5 (решение пользователя 2026-11-14; design.md change `add-subagents-and-tasks`, D39):
- **Группы.** Пакет SHALL делиться по порядку ответа модели на группы: подряд идущие вызовы, у которых `executionModeOf(args) == parallel`, — одна параллельная группа; каждый вызов с `executionModeOf(args) == sequential` — барьер, группа из одного вызова (LOOP-4). Группы SHALL исполняться строго по порядку: барьер начинается после завершения всех вызовов перед ним, следующая группа — после завершения барьера. Один `sequential`-вызов НЕ SHALL делать последовательным весь пакет.
- **Параллельная группа.** `ToolCallStarted` вызовов группы эмитятся по порядку ответа в начале группы, затем вызовы группы исполняются одновременно; `ToolCallFinished` — в порядке завершения (LOOP-3).
- **Барьер.** `ToolCallStarted` → исполнение → `ToolCallFinished`.
- **Отмена.** Перед каждой группой SHALL проверяться отмена. Вызовы не начатых групп не исполняются и получают `ToolCallStarted` и `ToolCallFinished(cancelled)` с текстом `Tool call was cancelled before it started`; идущие вызовы группы отменяются токеном хода.
- **Результаты.** Сообщения-результаты SHALL добавляться после всего пакета в порядке вызовов ответа, независимо от групп (LOOP-3); у каждого вызова ответа есть результат (TOOL-6).
- **Предохранитель.** В начале хода создаётся один `MisuseBreaker`, общий для всех вызовов хода (LOOP-16).

#### Scenario: Барьер делит пакет на группы
- **WHEN** ответ содержит `[read, task_update, agent, agent]`, где `task_update` — `sequential`, остальные — `parallel`
- **THEN** события идут как `ToolCallStarted(read)`, `ToolCallFinished(read)`, `ToolCallStarted(task_update)`, `ToolCallFinished(task_update)`, `ToolCallStarted(agent1)`, `ToolCallStarted(agent2)`, затем два `ToolCallFinished(agent)` в порядке завершения; оба `agent` исполняются одновременно, `task_update` начинается после завершения `read`; результаты в транскрипте — `read`, `task_update`, `agent1`, `agent2` (`sequential_mode_test.dart`)

#### Scenario: Два барьера подряд
- **WHEN** ответ содержит `[task_create, task_create, read, ls]`
- **THEN** `task_create` исполняются по одному в порядке ответа и получают id по порядку, затем `read` и `ls` — одновременно

#### Scenario: Отмена посреди группы
- **WHEN** ход отменяется, пока исполняется группа `{agent, agent}` пакета `[agent, agent, task_update, read]`
- **THEN** оба `agent` завершаются по отмене через токен хода, `task_update` и `read` не исполняются и получают `ToolCallFinished(cancelled)` с текстом `Tool call was cancelled before it started`, у каждого вызова ответа есть результат

#### Scenario: Режим по аргументам
- **WHEN** в пакете два вызова, и `executionModeOf` одного из них возвращает `sequential` только при заданном аргументе
- **THEN** с этим аргументом он — барьер между группами, без него оба вызова исполняются одной параллельной группой

#### Scenario: Пакет без барьеров
- **WHEN** все вызовы ответа — `parallel`
- **THEN** все `ToolCallStarted` эмитятся по порядку ответа, затем вызовы исполняются одновременно — как одна группа
