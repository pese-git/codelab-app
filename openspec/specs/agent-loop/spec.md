# agent-loop Specification

## Purpose
Цикл хода Dart-агента: функция `runAgentLoop` без собственного состояния и `Agent` поверх неё, закрытая иерархия событий `AgentEvent`, хуки и сборка payload для модели, бюджет хода, пакетное исполнение инструментов, обработка пустого ответа модели, очереди steering и follow-up. Цикл только эмитит события, сохраняет их хост (`agent-core-architecture` §5).
## Requirements
### Requirement: Функция хода runAgentLoop
Ход SHALL исполняться чистой функцией `runAgentLoop(prompts, context, config, emit, cancel)` над внедрёнными `StreamFunction` и `ToolExecutor` по алгоритму §5.4 документа ядра. Функция возвращает сообщения, добавленные ходом.

Цикл НЕ SHALL обращаться к хранилищу и НЕ SHALL знать о протоколе (LOOP-6). «Ход» соответствует ACP prompt turn, «шаг» — одному вызову модели.

Правила хода:
- `TurnEnded` SHALL быть последним событием хода и эмитироваться ровно один раз, в том числе при исключении в хуке: исключение превращается в `AgentError(cls: hook)` и `TurnEnded(failed)` (LOOP-1);
- `TurnEnded.reason` SHALL выводиться из ответа: `stop`/`toolUse` без вызовов → `completed`, `length` без вызовов → `maxTokens`, `terminalFinish` → `refused`, отмена → `cancelled`, отмена причиной `StorageFailure` → `failed`, прочие ошибки → `failed`;
- ответ с `stopReason: error` SHALL давать `AgentError(cls: provider, errorClass)` перед `StepEnded`;
- ответ с `errorClass: overflow` при заданном `emergencyCompact`, ещё не вызванном в этом ходе, SHALL давать один вызов `emergencyCompact` и повтор шага с возвращённым контекстом; ответ с ошибкой, после которого был повтор, в транскрипт не входит; второй `overflow` или `null` от `emergencyCompact` — обычная ошибка шага (§5.4, шаг 14a; CMP-8);
- при `stopReason: length` ни один вызов из ответа НЕ SHALL исполняться; каждый получает результат-ошибку `Tool call arguments were truncated because the response hit the output token limit. Retry with smaller arguments.` (LOOP-5);
- id вызовов SHALL быть уникальны во всём транскрипте: дубликат от провайдера получает суффикс `_2`, `_3`… уже в первом снимке, до первого события наружу (LOOP-11);
- ответ `badRequest` с ошибкой парности SHALL повторяться один раз с пересобранным payload (design.md change `add-agent-core-loop-and-tools`, D8).

#### Scenario: Эталонные последовательности
- **WHEN** scripted модель отвечает текстом; одним вызовом; двумя параллельными вызовами; ответом `length` с вызовом; ошибкой провайдера; ход отменяется во время стрима
- **THEN** каждая последовательность `AgentEvent` совпадает с эталоном `loop_sequences_test.dart`, `TurnEnded` в каждой ровно один и последний, у каждого `ToolCallStarted` ровно один `ToolCallFinished` (LOOP-9)

#### Scenario: Исключение в хуке
- **WHEN** `transformContext` или `prepareNextStep` бросает исключение
- **THEN** эмитятся `AgentError(cls: hook)` и `TurnEnded(failed)` ровно один раз

#### Scenario: Дубликат id вызова
- **WHEN** провайдер присылает `call_1` в двух разных шагах
- **THEN** второй вызов получает id `call_1_2` уже в первом `MessageStarted`, и его результат несёт тот же id

#### Scenario: Переполнение без сжатия
- **WHEN** `emergencyCompact` равен `null`, а модель отвечает ошибкой `overflow`
- **THEN** ход завершается `TurnEnded(failed)` как в этапе 2, повтора нет

#### Scenario: Аварийное сжатие один раз за ход
- **WHEN** модель дважды подряд отвечает `overflow`, а `emergencyCompact` возвращает новый контекст
- **THEN** `emergencyCompact` вызван ровно один раз, шаг повторён один раз, ход завершается `TurnEnded(failed)`

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

### Requirement: Хуки и сборка payload
`AgentLoopConfig` SHALL принимать хуки:
- `transformContext` — перед каждым запросом, меняет только payload;
- цепочку `beforeToolCall` — после валидации аргументов, до исполнения; первый `Block(reason)` останавливает цепочку;
- цепочку `afterToolCall` — после исполнения, переопределение по полям;
- `prepareNextStep` — после `StepEnded`, может заменить контекст или модель, а также набор инструментов (`StepUpdate.tools`) и системный промпт (`StepUpdate.systemPrompt`) со следующего запроса. `tools` и `systemPrompt` применяются поверх `context` и транскрипт цикла не меняют (design.md change `add-agent-mcp-client`, D6: обновление MCP-инструментов по `tools/list_changed`);
- `beforeFinalResponse` — в MVP только интерфейс; без хука поведение совпадает с `Accept` (LOOP-13);
- `estimateTokens(LlmContext)` — оценка размера payload (§9.3);
- `emergencyCompact(EmergencyCause, CancelToken)` — аварийное сжатие с причиной `preflight` или `overflow`; возвращает новый `LoopContext` или `null`, если сжать нечего или сжатие не удалось; `contextWindowCap` ограничивает окно проверки перед запросом (CMP-6).

Без `estimateTokens` и `emergencyCompact` поведение SHALL совпадать с этапом 2: размер не проверяется, `overflow` — обычная ошибка шага.

Первым звеном `beforeToolCall` SHALL стоять проверка разрешений (PERM-1); это обеспечивает сборка ядра.

Payload каждого запроса SHALL собираться по §5.2:
1. `transformContext` или копия транскрипта.
2. Удаление пустых ответов.
3. Ремонт парности с событием `ToolPairingRepaired` при непустом отчёте.
4. Заметка `Revise` в конце.
5. Оценка `estimateTokens`; если она больше окна модели и `emergencyCompact` в этом ходе ещё не вызывался — один вызов и пересборка с шага 1; если сжатие не помогло или его нет — синтетический ответ `stopReason: error`, `errorClass: overflow`, `errorMessage: 'context window exhausted'` без обращения к провайдеру.

Транскрипт `Agent` после запроса SHALL быть равен транскрипту до запроса плюс новые сообщения (LOOP-7); после аварийного сжатия — сообщениям возвращённого контекста плюс новые сообщения.

#### Scenario: Payload не меняет транскрипт
- **WHEN** `transformContext` удаляет сообщение, а ремонт парности синтезирует результат
- **THEN** запрос к модели содержит изменения, а транскрипт после шага отличается от транскрипта до шага только новыми сообщениями

#### Scenario: Порядок хуков
- **WHEN** в цепочке `beforeToolCall` два хука, и первый возвращает `Block('no')`
- **THEN** второй хук не вызывается, инструмент не исполняется, результат-ошибка содержит `no`, outcome `rejected`

#### Scenario: Payload больше окна
- **WHEN** `estimateTokens` возвращает значение больше окна модели, а `emergencyCompact` возвращает `null`
- **THEN** провайдер не вызывается, шаг завершается ошибкой `overflow`, ход — `TurnEnded(failed)`

#### Scenario: Новые инструменты без замены транскрипта
- **WHEN** `prepareNextStep` возвращает `StepUpdate(tools: [read, mcp__fake__lookup], systemPrompt: 'P2')` без `context`
- **THEN** следующий запрос к модели содержит схемы `read` и `mcp__fake__lookup` и системный промпт `P2`, а транскрипт `Agent` не изменился

### Requirement: Бюджет хода
`TurnBudget` (`maxSteps` по умолчанию 50, необязательные `maxTokens`, `maxCost`, `maxDuration`) SHALL проверяться только на границе шага: после `StepEnded` и до следующего запроса к модели. Исполняемый инструмент не прерывается.

При исчерпании любого лимита ход SHALL завершаться `TurnEnded(reason: completed, budgetExceeded: <limit>)` без нового шага (LOOP-12). Время ожидания `PermissionGate` НЕ SHALL входить в `maxDuration` (design.md, D6). `maxCost` проверяется только при известных ценах модели.

#### Scenario: Лимит шагов
- **WHEN** `maxSteps: 2`, а модель на каждом шаге зовёт инструмент
- **THEN** выполняются ровно два шага, и `TurnEnded.budgetExceeded` равен `steps`

#### Scenario: Ожидание одобрения не тратит время хода
- **WHEN** `maxDuration: 10 s`, gate отвечает через 60 с по `FakeClock`, а сам шаг занимает 1 с
- **THEN** ход не останавливается по `duration`

### Requirement: Пакет инструментов
Пакет вызовов одного ответа SHALL исполняться по §5.5 (решение пользователя 2026-11-14; design.md change `add-subagents-and-tasks`, D39):
- **Группы.** Пакет SHALL делиться по порядку ответа модели на группы: подряд идущие вызовы, у которых `executionModeOf(args) == parallel`, — одна параллельная группа; каждый вызов с `executionModeOf(args) == sequential` — барьер, группа из одного вызова (LOOP-4). Группы SHALL исполняться строго по порядку: барьер начинается после завершения всех вызовов перед ним, следующая группа — после завершения барьера. Один `sequential`-вызов НЕ SHALL делать последовательным весь пакет.
- **Параллельная группа.** `ToolCallStarted` вызовов группы эмитятся по порядку ответа в начале группы, затем вызовы группы исполняются одновременно; `ToolCallFinished` — в порядке завершения (LOOP-3).
- **Барьер.** `ToolCallStarted` → исполнение → `ToolCallFinished`.
- **Отмена.** Перед каждой группой SHALL проверяться отмена. Вызовы не начатых групп не исполняются и получают `ToolCallStarted` и `ToolCallFinished(cancelled)` с текстом `Tool call was cancelled before it started`; идущие вызовы группы отменяются токеном хода.
- **Результаты.** Сообщения-результаты SHALL добавляться после всего пакета в порядке вызовов ответа, независимо от групп (LOOP-3); у каждого вызова ответа есть результат (TOOL-6).
- **Сбой объявления.** Если объявление вызова группы завершилось исключением, место этого вызова в очереди пути SHALL быть освобождено, а уже объявленные вызовы группы SHALL закрываться откатом группы. Ход SHALL завершаться исходной ошибкой объявления (LOOP-1); вызовы после упавшего не объявляются.
- **Откат группы.** При отмене группы и после сбоя объявления объявленные вызовы группы SHALL закрываться `ToolCallFinished(cancelled)` без исполнения. Места всех этих вызовов в очереди пути SHALL освобождаться до ожидания любого `ToolCallFinished`: сбой или зависание эмита одного вызова НЕ SHALL держать места остальных. Сбой закрытия каждого вызова SHALL логироваться `tool.abandon.error` с полем `error_class` (`runtimeType` исключения; само исключение — в `error` и `stack` записи; design.md, D41, п. 5) и НЕ SHALL прерывать закрытие остальных; сбой самого логгера НЕ SHALL менять исход хода. При отмене первая ошибка закрытия SHALL завершать ход `failed` (LOOP-1).
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

#### Scenario: Сбой объявления в параллельной группе
- **WHEN** в параллельной группе `[c1, c2]` оба вызова правят один путь, и `emit ToolCallStarted(c2)` бросает исключение
- **THEN** `c1` получает ровно один `ToolCallFinished(cancelled)` и не исполняется, у `c2` нет ни `ToolCallStarted`, ни `ToolCallFinished`, ход завершается `TurnEnded(failed)`, а следующий ход той же сессии правит этот путь без ожидания (`parallel_edit_test.dart`)

#### Scenario: Сбой закрытия при откате
- **WHEN** в параллельной группе `[c1, c2]` одного пути после `ToolCallStarted(c1)` приёмник событий бросает на любом событии
- **THEN** закрытие `c1` даёт ровно одну запись лога `tool.abandon.error` с `tool_call_id` `c1` и `error_class` — именем типа брошенного исключения, исключение выходит из хода, а путь `c1` свободен для следующего вызова той же сессии (`parallel_edit_test.dart`)

#### Scenario: Сбой закрытия одного вызова при откате после сбоя объявления
- **WHEN** в параллельной группе `[c1, c2, c3]` одного пути объявление `c3` бросает, а эмит `ToolCallFinished(c1)` при откате тоже бросает
- **THEN** лог содержит одну запись `tool.abandon.error` для `c1`, `c2` получает `ToolCallFinished(cancelled)`, ход завершается `AgentError` с исходной ошибкой объявления и `TurnEnded(failed)`, а путь свободен для следующего вызова той же сессии (`batch_cancel_abandon_failure_test.dart`)

#### Scenario: Сбой закрытия при отмене группы
- **WHEN** ход отменяется после объявления группы `[c1, c2]` одного пути, а эмит каждого `ToolCallFinished` бросает
- **THEN** лог содержит записи `tool.abandon.error` для `c1` и `c2` по порядку, ход завершается `AgentError` с первой ошибкой закрытия и `TurnEnded(failed)`, а путь свободен для следующего вызова той же сессии (`batch_cancel_abandon_failure_test.dart`)

#### Scenario: Зависший эмит при откате
- **WHEN** ход отменяется после объявления группы `[c1, c2]` одного пути, а эмит `ToolCallFinished(c1)` зависает
- **THEN** следующий вызов того же пути в сессии исполняется ещё до того, как эмит отпущен; после его отпускания `c1` и `c2` получают `ToolCallFinished(cancelled)`, а ход завершается `TurnEnded(cancelled)` (`batch_cancel_abandon_failure_test.dart`)

#### Scenario: Режим по аргументам
- **WHEN** в пакете два вызова, и `executionModeOf` одного из них возвращает `sequential` только при заданном аргументе
- **THEN** с этим аргументом он — барьер между группами, без него оба вызова исполняются одной параллельной группой

#### Scenario: Пакет без барьеров
- **WHEN** все вызовы ответа — `parallel`
- **THEN** все `ToolCallStarted` эмитятся по порядку ответа, затем вызовы исполняются одновременно — как одна группа

### Requirement: Пустой ответ модели
Ответ SHALL считаться пустым (`isEmptyCompletion`), если одновременно:
- `stopReason` — `stop` или `toolUse`;
- вызовов нет;
- у каждого `TextContent` пустой `trim()`.

Блоки рассуждения при этом не учитываются.

Пока счётчик пустых ответов подряд меньше `emptyResponseRetries` (по умолчанию 2), цикл SHALL добавлять подсказку и делать ещё один шаг. Подсказка — `UserMessage` с текстом `Your previous response was empty. Continue the task: call a tool or answer the user with text.` и `origin: LoopNudgeOrigin(emptyResponse, n)`.

После исчерпания повторов цикл SHALL добавлять синтетическую заметку:
- текст `[Stopped: the model returned an empty response (attempts: <N>). Send a message to continue.]`;
- `origin: LoopNoteOrigin(emptyResponse)`;
- события `MessageStarted`, `MessageDelta`, `MessageEnded`, без `StepStarted`;
- затем ход останавливается как обычно (LOOP-14).

Пустой ответ НЕ SHALL попадать в payload, а подсказки и заметка — попадают (LOOP-15). Повторы — обычные шаги и входят в `TurnBudget`. `beforeFinalResponse` для пустого ответа и после заметки не вызывается.

#### Scenario: Повтор с подсказками
- **WHEN** модель отвечает «пусто», «только thinking», затем `Done.`
- **THEN** выполняются три шага с подсказками `attempt` 1 и 2; payload третьего шага не содержит пустых `assistant` и содержит обе подсказки; ход завершается `TurnEnded(completed)` (`empty_completion_test.dart`)

#### Scenario: Заметка после трёх пустых ответов
- **WHEN** модель трижды подряд отвечает пусто
- **THEN** в транскрипт добавляется заметка с `attempts: 3` без `StepStarted`, ход завершается `TurnEnded(completed)`

#### Scenario: Бюджет сильнее повтора
- **WHEN** `maxSteps: 2`, и модель дважды отвечает пусто
- **THEN** ход завершается `budgetExceeded: steps` без заметки

### Requirement: Agent, steering и follow-up
`Agent` SHALL держать транскрипт, очереди и подписчиков поверх `runAgentLoop`:
- `prompt(messages)` — запуск хода; повторный `prompt()` во время хода → `StateError` (LOOP-10);
- `steer(m)` — доставка на ближайшей границе шага после всего пакета инструментов (CAN-6);
- `followUp(m)` — доставка после естественной остановки в том же ходе;
- `abort([reason])` — отмена токена хода;
- `waitForIdle()` — завершение после `TurnEnded` и всех подписчиков;
- `subscribe(listener)` — слушатели ждутся по порядку подписки;
- `messages` — неизменяемая копия транскрипта;
- `replaceTranscript` — только вне хода.

Опрос steering SHALL забирать все элементы очереди в порядке FIFO за один опрос и добавлять не больше одного шага. Шагов, добавленных steering-ом, за ход НЕ SHALL быть больше `maxSteeringSteps` (по умолчанию 20; LOOP-8).

#### Scenario: Второй prompt во время хода
- **WHEN** `prompt()` вызывается, пока предыдущий ход не закончился
- **THEN** вызов завершается `StateError`, а идущий ход не меняется

#### Scenario: Steering во время инструмента
- **WHEN** во время исполнения пакета приходят три сообщения `steer`
- **THEN** все три попадают в транскрипт одним опросом после всего пакета в порядке поступления, и между вызовом и его результатом сообщений нет

#### Scenario: Лимит шагов steering
- **WHEN** `maxSteeringSteps: 20`, а steering приходит на каждом шаге 25 раз
- **THEN** steering добавляет не больше 20 шагов за ход

### Requirement: Заполнение контекста после шага
`StepEnded` SHALL нести заполнение контекста после шага (design.md change `add-usage-extension`, D5): `used` — оценка `estimateContextTokens` контекста цикла после добавления результатов инструментов этого шага с якорем на usage только что полученного ответа; `window` — `effectiveContextWindow` текущей модели цикла на момент `StepEnded` с `AgentLoopConfig.contextWindowCap` (смена модели посреди хода применяется после `StepEnded`, в `prepareNextStep`, и видна со следующего шага); `compactAt` — порог автосжатия `afterTurn` в токенах по тому же правилу, что проверка `shouldCompact` рантайма, переданный циклу рантаймом, или `null` при выключенном автосжатии. Оценщик заполнения — отдельное поле `AgentLoopConfig.contextEstimator`; рантайм SHALL передавать его всегда, в том числе при выключенной capability `compaction`. Оценщик `estimateTokens` и проверка перед запросом от него не зависят: без `estimateTokens` и `emergencyCompact` поведение по-прежнему совпадает с этапом 2. Без `contextEstimator` поле SHALL быть `null`. Вычисление НЕ SHALL обращаться к провайдеру и НЕ SHALL менять транскрипт, журнал и бюджет хода.

#### Scenario: Шаг с инструментом
- **WHEN** ответ шага имеет usage `input 41000, cacheRead 9000, output 600`, а результат `read` — 12 000 символов
- **THEN** `StepEnded` несёт `used = 50600 + оценка результата` (по правилу `agent-compaction` «Оценка токенов с якорем на usage») и `window`, равное окну модели с учётом `contextWindowCap`

#### Scenario: Цикл без оценщика
- **WHEN** `AgentLoopConfig.contextEstimator` не задан
- **THEN** заполнение контекста в `StepEnded` — `null`, остальные поля события прежние

#### Scenario: Автосжатие выключено
- **WHEN** сессия собрана без сжатия контекста (capability `compaction` выключена, `estimateTokens` и `emergencyCompact` не заданы)
- **THEN** `StepEnded` несёт `used` и `window`, а `compactAt` — `null`; проверки размера перед запросом нет, как на этапе 2

#### Scenario: Смена модели посреди хода
- **WHEN** после первого шага `prepareNextStep` меняет модель на модель с другим окном
- **THEN** `StepEnded` первого шага несёт `window` прежней модели, `StepEnded` второго шага — новой

### Requirement: Прогресс бюджета хода в событиях шага и хода
`StepEnded` и `TurnEnded` SHALL нести прогресс бюджета хода (design.md change `add-desktop-usage-pane`, D8): лимиты `TurnBudget` хода и израсходованное к моменту события — число завершённых шагов корня, токены `input + output` своих шагов и usage потомков (без `cacheRead` и `cacheWrite`), стоимость той же суммы или `null`, если у текущей модели цикла нет цен, и время хода по часам хоста без ожидания `PermissionGate`. Прогресс и проверка исчерпания (требование «Бюджет хода», LOOP-12) SHALL считаться одной функцией, поэтому значение в `StepEnded` совпадает с тем, по которому принимается решение остановить ход на этой границе шага. Вычисление НЕ SHALL обращаться к провайдеру и НЕ SHALL менять транскрипт, журнал и сам бюджет. Поле заполняется при любых лимитах; решать, передавать ли его клиенту, — не дело ядра. Шаг, отправленный в `StepEnded`, SHALL считаться завершённым и тогда, когда ответ модели — ошибка и ход на нём заканчивается: `steps` в прогрессе `TurnEnded` SHALL равняться числу `StepEnded` хода.

#### Scenario: Прогресс после шага
- **WHEN** `TurnBudget(maxSteps: 50, maxTokens: 200000)`, первый шаг потратил `input 1000, output 200, cacheRead 9000`, а потомок хода — `input 300, output 100`
- **THEN** `StepEnded` первого шага несёт `steps 1`, `tokens 1600` и лимиты `50` и `200000`

#### Scenario: Ожидание одобрения не входит во время
- **WHEN** `maxDuration: 10 min`, шаг длился 2 с по `FakeClock`, из них 60 с — ожидание gate
- **THEN** время в прогрессе `StepEnded` не включает 60 с ожидания

#### Scenario: Модель без цен
- **WHEN** у текущей модели цикла нет цен (`ModelRef.cost == null`), а `maxCost` задан
- **THEN** стоимость в прогрессе — `null`, лимит `maxCost` в прогрессе есть, и ход по `cost` не останавливается

#### Scenario: Итог хода
- **WHEN** ход остановлен по `tokens`
- **THEN** `TurnEnded` несёт `budgetExceeded: tokens` и прогресс, в котором израсходованные токены не меньше лимита

#### Scenario: Сбой модели на шаге
- **WHEN** первый шаг хода завершился успешно, а ответ модели на втором шаге — ошибка, и ход на нём заканчивается
- **THEN** отправлены два `StepEnded`, и прогресс `TurnEnded` несёт `steps 2`

