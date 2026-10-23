## ADDED Requirements

### Requirement: Функция хода runAgentLoop
Ход SHALL исполняться чистой функцией `runAgentLoop(prompts, context, config, emit, cancel)` над внедрёнными `StreamFunction` и `ToolExecutor` по алгоритму §5.4 документа ядра. Функция возвращает сообщения, добавленные ходом.

Цикл НЕ SHALL обращаться к хранилищу и НЕ SHALL знать о протоколе (LOOP-6). «Ход» соответствует ACP prompt turn, «шаг» — одному вызову модели.

Правила хода:
- `TurnEnded` SHALL быть последним событием хода и эмитироваться ровно один раз, в том числе при исключении в хуке: исключение превращается в `AgentError(cls: hook)` и `TurnEnded(failed)` (LOOP-1);
- `TurnEnded.reason` SHALL выводиться из ответа: `stop`/`toolUse` без вызовов → `completed`, `length` без вызовов → `maxTokens`, `terminalFinish` → `refused`, отмена → `cancelled`, прочие ошибки → `failed`;
- ответ с `stopReason: error` SHALL давать `AgentError(cls: provider, errorClass)` перед `StepEnded`;
- при `stopReason: length` ни один вызов из ответа НЕ SHALL исполняться; каждый получает результат-ошибку `Tool call arguments were truncated because the response hit the output token limit. Retry with smaller arguments.` (LOOP-5);
- id вызовов SHALL быть уникальны во всём транскрипте: дубликат от провайдера получает суффикс `_2`, `_3`… уже в первом снимке, до первого события наружу (LOOP-11);
- ответ `badRequest` с ошибкой парности SHALL повторяться один раз с пересобранным payload (design.md, D8).

#### Scenario: Эталонные последовательности
- **WHEN** scripted модель отвечает текстом; одним вызовом; двумя параллельными вызовами; ответом `length` с вызовом; ошибкой провайдера; ход отменяется во время стрима
- **THEN** каждая последовательность `AgentEvent` совпадает с эталоном `loop_sequences_test.dart`, `TurnEnded` в каждой ровно один и последний, у каждого `ToolCallStarted` ровно один `ToolCallFinished` (LOOP-9)

#### Scenario: Исключение в хуке
- **WHEN** `transformContext` или `prepareNextStep` бросает исключение
- **THEN** эмитятся `AgentError(cls: hook)` и `TurnEnded(failed)` ровно один раз

#### Scenario: Дубликат id вызова
- **WHEN** провайдер присылает `call_1` в двух разных шагах
- **THEN** второй вызов получает id `call_1_2` уже в первом `MessageStarted`, и его результат несёт тот же id

### Requirement: События AgentEvent
Цикл и `Agent` SHALL сообщать о ходе закрытой иерархией `AgentEvent`:
- `TurnStarted`, `StepStarted`, `ModelRequested`;
- `MessageStarted` (с `origin` служебного сообщения), `MessageDelta`, `ThoughtDelta`, `MessageEnded`;
- `ToolCallStarted`, `ToolCallProgress`, `ToolCallFinished` (с `outcome` и `diffs`), `ToolPairingRepaired`;
- `StepEnded`, `PlanUpdated`, `ModeChanged`, `AgentError`, `TurnEnded`.

Поля событий и моменты эмиссии SHALL соответствовать таблице §5.3 документа ядра. События остальных этапов добавляются ветками иерархии без изменения перечисленных.

Цикл SHALL ждать завершения каждого `emit`: следующее событие не эмитится, пока подписчики не обработали предыдущее (LOOP-2). В параллельном пакете `ToolCallFinished` приходят в порядке завершения, а сообщения-результаты в транскрипте идут в порядке вызовов в ответе модели (LOOP-3).

#### Scenario: Медленный подписчик
- **WHEN** подписчик обрабатывает каждое событие через `await Future.delayed`
- **THEN** события приходят строго по одному, в порядке эмиссии

#### Scenario: Порядок параллельного пакета
- **WHEN** в одном шаге два параллельных вызова и второй завершается раньше первого
- **THEN** события идут как `ToolCallStarted(c1), ToolCallStarted(c2), ToolCallFinished(c2), ToolCallFinished(c1)`, а результаты в транскрипте — как `c1, c2`

### Requirement: Хуки и сборка payload
`AgentLoopConfig` SHALL принимать хуки:
- `transformContext` — перед каждым запросом, меняет только payload;
- цепочку `beforeToolCall` — после валидации аргументов, до исполнения; первый `Block(reason)` останавливает цепочку;
- цепочку `afterToolCall` — после исполнения, переопределение по полям;
- `prepareNextStep` — после `StepEnded`, может заменить контекст или модель;
- `beforeFinalResponse` — в MVP только интерфейс; без хука поведение совпадает с `Accept` (LOOP-13).

Первым звеном `beforeToolCall` SHALL стоять проверка разрешений (PERM-1); это обеспечивает сборка ядра.

Payload каждого запроса SHALL собираться по §5.2:
1. `transformContext` или копия транскрипта.
2. Удаление пустых ответов.
3. Ремонт парности с событием `ToolPairingRepaired` при непустом отчёте.
4. Заметка `Revise` в конце.

Транскрипт `Agent` после запроса SHALL быть равен транскрипту до запроса плюс новые сообщения (LOOP-7).

#### Scenario: Payload не меняет транскрипт
- **WHEN** `transformContext` удаляет сообщение, а ремонт парности синтезирует результат
- **THEN** запрос к модели содержит изменения, а транскрипт после шага отличается от транскрипта до шага только новыми сообщениями

#### Scenario: Порядок хуков
- **WHEN** в цепочке `beforeToolCall` два хука, и первый возвращает `Block('no')`
- **THEN** второй хук не вызывается, инструмент не исполняется, результат-ошибка содержит `no`, outcome `rejected`

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
Пакет вызовов одного ответа SHALL исполняться по §5.5:
- **Режим.** Пакет последовательный, если хотя бы для одного вызова `executionModeOf(args) == sequential` (LOOP-4); иначе параллельный.
- **Параллельный пакет.** Все `ToolCallStarted` эмитятся по порядку ответа, затем вызовы исполняются одновременно.
- **Последовательный пакет.** Перед каждым вызовом проверяется отмена. Неисполненные вызовы получают `ToolCallStarted` и `ToolCallFinished(cancelled)` с текстом `Tool call was cancelled before it started`.
- **Предохранитель.** В начале хода создаётся один `MisuseBreaker`, общий для всех вызовов хода (LOOP-16).

#### Scenario: Последовательный режим по аргументам
- **WHEN** в пакете два вызова, и `executionModeOf` одного из них возвращает `sequential` только при заданном аргументе
- **THEN** с этим аргументом пакет исполняется по порядку, без него — параллельно

#### Scenario: Отмена посреди последовательного пакета
- **WHEN** ход отменяется во время первого из трёх последовательных вызовов
- **THEN** второй и третий получают `ToolCallFinished(cancelled)` с текстом `Tool call was cancelled before it started`, и у каждого вызова ответа есть результат

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
