## MODIFIED Requirements

### Requirement: События AgentEvent
Цикл, `Agent` и `AgentSession` SHALL сообщать о ходе закрытой иерархией `AgentEvent`:
- `TurnStarted`, `StepStarted`, `ModelRequested` (с `estimatedTokens` — оценкой payload, 0 без оценщика);
- `MessageStarted` (с `origin` служебного сообщения), `MessageDelta`, `ThoughtDelta`, `MessageEnded`;
- `ToolCallStarted` (с необязательным `subagent` — `SubagentCallRef(id, type)` у вызова `agent`, из `ToolPresentation.subagent`; change `add-subagents-and-tasks`, D28), `ToolCallProgress`, `ToolCallFinished` (с `outcome`, `diffs` и признаком `interrupted` у синтетического результата реплея), `ToolPairingRepaired`;
- `StepEnded`, `ModeChanged`, `AgentError`, `TurnEnded`;
- `ContextCompacted(tokensBefore, tokensAfter, usage?, model?)` — сжатие уже записано в журнал (§9.8); `usage` и `model` (`<provider>/<id>`) — usage и модель вызова суммаризатора, `null` у реплея старой записи без `details.usage`; в `TurnEnded.usage` не входят (design.md change `add-usage-ledger`, D4);
- `CompactionDiscarded(tokensBefore, tokensAfter, usage, model)` — оплаченный вызов суммаризатора, после которого сжатие не записано (`no reduction`, `stale`): учёт записан в журнал, проекция и транскрипт не меняются; реплей события не даёт (CMP-13; design.md change `fix-discarded-compaction-usage`, D2);
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
