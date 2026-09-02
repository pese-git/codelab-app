## Why

Когда ACP-агент стримит ответ, каждое обновление `agent_message_chunk`/`agent_thought_chunk` сейчас превращается в отдельный `AcpTranscriptEntry` (`CodeLabShellCubit._agentTranscriptEntries`), и весь этот набор добавляется в `transcriptEntries` одним куском только после завершения всего prompt turn (`CodeLabShellCubit.submitPrompt`). Пользователь видит несколько разрозненных пузырей агента, появляющихся разом, и не получает никакой живой обратной связи "агент печатает" во время выполнения turn — хотя `AcpClientApplication.sessionChanges` уже эмитит событие на каждый входящий чанк в реальном времени.

## What Changes

- `transcriptEntries` активного turn теперь выводится из `AcpSession.activeTurn` внутри `CodeLabShellCubit._handleSessionChange`, на каждое событие `sessionChanges` — по тому же паттерну "пересчёт из состояния сессии", который уже используется для `pendingApproval`, `configOptions` и `agentCommands` — вместо однократного append'а из уже завершённого `PromptTurn` в конце `submitPrompt`.
- Подряд идущие обновления `AgentMessageChunk` (и отдельно — подряд идущие `AgentThoughtChunk`) в рамках одного turn схлопываются в один растущий `AcpTranscriptEntry` путём конкатенации текста, так что transcript показывает один пузырь на непрерывный отрезок текста агента, а не один пузырь на чанк.
- В результате пузырь агента растёт живьём, чанк за чанком, пока turn выполняется (ощущение "печати") — это достигается чистым пересчётом состояния на каждое событие стрима, без mutable-аккумулятора текста, без таймеров/анимаций.
- Убирается ставший избыточным ручной append в `transcriptEntries` как в успешной, так и в failure-ветке `submitPrompt` (последняя дублировала бы diagnostic-запись, которую `_transcriptEntriesForSession` уже формирует для провалившегося turn через `session.turns`); обе ветки продолжают трогать только `isPromptSubmitting`/`canCancel`/диагностику, так как сам transcript уже поддерживается актуальным в `_handleSessionChange`.
- Сохраняются существующие инварианты: устаревшие/поздние обновления сессии из предыдущего generation не должны портить transcript текущей активной сессии (существующие проверки generation/session-id в `_handleSessionChange` и `AcpClientApplication` не ослабляются); `transcriptEntries` завершённой сессии остаются видимыми/стабильными после окончания turn (согласно `agent-workbench-ui` spec — transcript сессии остаётся видимым после завершения).

## Capabilities

### New Capabilities
(нет)

### Modified Capabilities
- `agent-workbench-ui`: добавляется требование о том, что transcript схлопывает подряд идущие однотипные streaming-обновления агента (message chunks, thought chunks) в рамках одного turn в единую живо обновляющуюся запись, вместо одной записи на каждый чанк, и что эта запись обновляется по мере поступления новых чанков, пока turn выполняется.

## Impact

- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart`: `_handleSessionChange`, `_agentTranscriptEntries` (или её замена), `submitPrompt`.
- Без изменений в `packages/dart/acp_protocol` и `packages/dart/acp_client_core` — `SessionUpdate`/`AcpClientApplication.sessionChanges` уже предоставляют всё необходимое; это чисто изменение вывода на уровне application layer.
- Без изменений в `AcpTranscriptPanel`/`AcpTranscriptEntry` пакета `packages/flutter/acp_ui` — панель продолжает рендерить один пузырь на одну запись списка; записи просто производятся уже схлопнутыми.
- Существующие тесты вокруг `_agentTranscriptEntries`/построения transcript в тестах `shell_cubit` потребуют обновления с учётом схлопнутого вывода и новой точки пересчёта.
