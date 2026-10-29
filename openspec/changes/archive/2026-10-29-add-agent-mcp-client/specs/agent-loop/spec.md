## MODIFIED Requirements

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
