## MODIFIED Requirements

### Requirement: Хуки и сборка payload
`AgentLoopConfig` SHALL принимать хуки:
- `transformContext` — перед каждым запросом, меняет только payload;
- цепочку `beforeToolCall` — после валидации аргументов, до исполнения; первый `Block(reason)` останавливает цепочку;
- цепочку `afterToolCall` — после исполнения, переопределение по полям;
- `prepareNextStep` — после `StepEnded`, может заменить контекст или модель, а также набор инструментов (`StepUpdate.tools`) и системный промпт (`StepUpdate.systemPrompt`) со следующего запроса. `tools` и `systemPrompt` применяются поверх `context` и транскрипт цикла не меняют (design.md change `add-agent-mcp-client`, D6: обновление MCP-инструментов по `tools/list_changed`);
- `beforeFinalResponse` — финальный гейт ответа; без хука поведение совпадает с `Accept` (LOOP-13). Вердикты цикл обрабатывает по требованию «Вердикты финального гейта в цикле». Корневой сессии рантайм ставит составной хук встроенных проверок (`agent-runtime` «Проверки финального ответа сессии»; design.md change `add-final-response-guardrails`, D1). Хост МОЖЕТ передать свой хук напрямую в `AgentLoopConfig`, тогда лимит задаёт только `maxResponseRevisions` цикла;
- `estimateTokens(LlmContext)` — оценка размера payload (§9.3);
- `emergencyCompact(EmergencyCause, CancelToken)` — аварийное сжатие с причиной `preflight` или `overflow`; возвращает новый `LoopContext` или `null`, если сжать нечего или сжатие не удалось; `contextWindowCap` ограничивает окно проверки перед запросом (CMP-6).

Без `estimateTokens` и `emergencyCompact` поведение SHALL совпадать с этапом 2: размер не проверяется, `overflow` — обычная ошибка шага.

Первым звеном `beforeToolCall` SHALL стоять проверка разрешений (PERM-1); это обеспечивает сборка ядра.

Payload каждого запроса SHALL собираться по §5.2:
1. `transformContext` или копия транскрипта.
2. Удаление пустых ответов.
3. Ремонт парности с событием `ToolPairingRepaired` при непустом отчёте.
4. Оценка `estimateTokens`; если она больше окна модели и `emergencyCompact` в этом ходе ещё не вызывался — один вызов и пересборка с шага 1; если сжатие не помогло или его нет — синтетический ответ `stopReason: error`, `errorClass: overflow`, `errorMessage: 'context window exhausted'` без обращения к провайдеру.

Заметка `Revise` отдельно к payload НЕ SHALL добавляться: она уже есть в транскрипте как сообщение цикла (design.md change `add-final-response-guardrails`, D10). Транскрипт `Agent` после запроса SHALL быть равен транскрипту до запроса плюс новые сообщения (LOOP-7); после аварийного сжатия — сообщениям возвращённого контекста плюс новые сообщения.

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

## ADDED Requirements

### Requirement: Вердикты финального гейта в цикле
Цикл SHALL вызывать `beforeFinalResponse` только для непустого ответа без вызовов, когда нет ожидающего ввода (LOOP-13), и передавать `TurnInfo` с полем `toolOutcomes` — отображением `toolCallId → ToolOutcome` всех вызовов хода, исполненных или закрытых к моменту вызова (design.md change `add-final-response-guardrails`, D2). Поле аддитивно: хук, который его не читает, работает как прежде.

Вердикты:
- `Accept` — ход завершается, если нет нового ввода;
- `Revise(note)` при `revisions < maxResponseRevisions` — цикл SHALL добавить в транскрипт `UserMessage` с текстом `note` и `origin: LoopNudgeOrigin(finalCheck, n)`, где `n` — номер ревизии с 1, и сделать ещё один шаг. В журнале заметка SHALL быть записью `message` с `origin: "loop_nudge"`, `nudge: "final_check"`, `attempt: n`. Заметка добавляется до опроса steering, steering той же границы идёт в тот же шаг. `Revise` сверх лимита равен `Accept`;
- `Hold(reason)` — `held` хода SHALL стать `reason`.

`held` SHALL относиться к последнему кандидату хода: цикл SHALL сбрасывать `held` в начале каждого нового шага, в том числе открытого steering или follow-up после `Hold` (D11). `TurnEnded.held` и `TurnEnded.budgetExceeded` НЕ SHALL быть заданы одновременно. Счётчик ревизий на новый шаг не сбрасывается.

#### Scenario: Заметка ревизии в транскрипте
- **WHEN** хук возвращает `Revise('check again')` на первый ответ и `Accept` на второй
- **THEN** транскрипт после хода — промпт, кандидат, `UserMessage('check again')` с `LoopNudgeOrigin(finalCheck, 1)`, второй ответ; ни в одном запросе к модели нет двух `assistant` подряд; журнал содержит запись `message` с `origin: "loop_nudge"`, `nudge: "final_check"`, `attempt: 1`

#### Scenario: Следующий ход после ревизии
- **WHEN** после хода с ревизией пользователь отправляет новый промпт, а сессия перед этим загружена через `session/load`
- **THEN** payload первого запроса нового хода содержит кандидата, заметку и второй ответ в том же порядке, что живой ход, и не содержит двух `assistant` подряд

#### Scenario: Steering после Hold
- **WHEN** хук возвращает `Hold('r')`, на той же границе в очереди steering есть сообщение, а на ответ после него хук возвращает `Accept`
- **THEN** ход делает ещё один шаг и завершается `TurnEnded(completed)` с `held == null`

#### Scenario: Бюджет после Hold и steering
- **WHEN** `maxSteps: 1`, хук возвращает `Hold('r')`, а на той же границе пришёл steering
- **THEN** ход завершается `TurnEnded(completed, budgetExceeded: steps)` с `held == null`

#### Scenario: Исходы вызовов в TurnInfo
- **WHEN** в ходе вызов `exec` отклонён разрешением, а вызов `read` исполнен, затем модель отвечает текстом
- **THEN** `TurnInfo.toolOutcomes` содержит `rejected` для `exec` и `completed` для `read`

#### Scenario: Хук хоста без составного гейта
- **WHEN** хост передаёт в `AgentLoopConfig` хук `beforeFinalResponse`, который всегда возвращает `Revise('again')`, а `maxResponseRevisions` равен `2`
- **THEN** выполняются ровно два дополнительных шага с двумя заметками в транскрипте, третий вердикт `Revise` равен `Accept`, `TurnEnded.held` равен `null`
