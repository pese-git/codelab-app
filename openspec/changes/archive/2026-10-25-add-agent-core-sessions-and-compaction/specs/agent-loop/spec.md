## MODIFIED Requirements

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
- `ToolCallStarted`, `ToolCallProgress`, `ToolCallFinished` (с `outcome`, `diffs` и признаком `interrupted` у синтетического результата реплея), `ToolPairingRepaired`;
- `StepEnded`, `PlanUpdated`, `ModeChanged`, `AgentError`, `TurnEnded`;
- `ContextCompacted(tokensBefore, tokensAfter)` — сжатие уже записано в журнал (§9.8);
- `SessionTitleChanged(title, updatedAt)` — событие уровня `AgentSession`, заголовок записан в журнал (§8.3).

Поля событий и моменты эмиссии SHALL соответствовать таблице §5.3 документа ядра и таблице §8.3 для событий сессии. События остальных этапов добавляются ветками иерархии без изменения перечисленных.

Цикл SHALL ждать завершения каждого `emit`: следующее событие не эмитится, пока подписчики не обработали предыдущее (LOOP-2). В параллельном пакете `ToolCallFinished` приходят в порядке завершения, а сообщения-результаты в транскрипте идут в порядке вызовов в ответе модели (LOOP-3).

#### Scenario: Медленный подписчик
- **WHEN** подписчик обрабатывает каждое событие через `await Future.delayed`
- **THEN** события приходят строго по одному, в порядке эмиссии

#### Scenario: Порядок параллельного пакета
- **WHEN** в одном шаге два параллельных вызова и второй завершается раньше первого
- **THEN** события идут как `ToolCallStarted(c1), ToolCallStarted(c2), ToolCallFinished(c2), ToolCallFinished(c1)`, а результаты в транскрипте — как `c1, c2`

#### Scenario: Оценка в ModelRequested
- **WHEN** у цикла есть `estimateTokens`
- **THEN** `ModelRequested.estimatedTokens` равен её результату для payload этого запроса

### Requirement: Хуки и сборка payload
`AgentLoopConfig` SHALL принимать хуки:
- `transformContext` — перед каждым запросом, меняет только payload;
- цепочку `beforeToolCall` — после валидации аргументов, до исполнения; первый `Block(reason)` останавливает цепочку;
- цепочку `afterToolCall` — после исполнения, переопределение по полям;
- `prepareNextStep` — после `StepEnded`, может заменить контекст или модель;
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
