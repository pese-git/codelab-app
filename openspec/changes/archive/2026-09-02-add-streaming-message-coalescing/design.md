## Context

Сегодня `transcriptEntries` заполняется двумя независимыми путями, и ни один из них не реагирует на `sessionChanges` во время выполнения turn:

- `CodeLabShellCubit.submitPrompt` (`shell_cubit.dart:785-836`) добавляет "You"-запись сразу, затем **ждёт** весь `_sendPromptUseCase(...).run()` целиком и только после его резолва вызывает `_agentTranscriptEntries(turn, baseIndex:...)`, добавляя результат одним emit'ом.
- `_transcriptEntriesForSession(AcpSession session)` (`shell_cubit.dart:1354-...`) пересобирает весь transcript "с нуля" из `session.turns`, но используется только при переключении на сессию, не отслеживаемую инкрементально (`selectSession`).

`_agentTranscriptEntries` (`shell_cubit.dart:1305-1347`) создаёт **один `AcpTranscriptEntry` на каждый** `AgentMessageChunk`/`AgentThoughtChunk` — оба маппятся в одинаковый `kind: agent, title: 'Agent'`, без коалесации подряд идущих чанков.

При этом `AcpClientApplication.sessionChanges` (`acp_client_application.dart:100`) уже эмитит `AcpSession` на **каждое** входящее `session/update`-уведомление, включая каждый чанк стрима (`_handleSessionUpdate`, `acp_client_application.dart:687-710`, вызывает `SessionStateMachine.applyUpdate` и сразу `_storeSession`). `CodeLabShellCubit._handleSessionChange` (`shell_cubit.dart:1039-1062`) уже подписан на этот stream и **уже** пересчитывает `pendingApproval`, `configOptions`, `agentCommands` и — что важно как прецедент — `inspectorEntries: _inspectorEntriesForSession(session)` заново на каждое событие. Именно так уже устроено всё остальное состояние сессии; `transcriptEntries` — единственное исключение, которое не следует этому паттерну.

## Goals / Non-Goals

**Goals:**
- `transcriptEntries` выводится из `session.turns` внутри `_handleSessionChange` на каждое событие `sessionChanges`, тем же способом, что и `inspectorEntries`/`pendingApproval`/`configOptions` — единственный источник истины, без ручных append'ов в `submitPrompt`.
- Подряд идущие `AgentMessageChunk` схлопываются в одну запись; отдельно — подряд идущие `AgentThoughtChunk` схлопываются в одну запись. Соседство определяется по позиции в исходном `turn.updates` (см. Decisions), а не только по фактически добавленному тексту.
- Пузырь агента растёт "живьём" по мере поступления чанков, пока turn выполняется — без mutable-аккумулятора, чистым пересчётом на снапшоте `session` при каждом событии.
- Существующие инварианты изоляции по сессии/поколению (generation) не ослабляются — используются как есть.

**Non-Goals:**
- Визуальное различение `AgentMessageChunk` и `AgentThoughtChunk` (разные стили/иконки) — не в этом change; сегодня оба рендерятся идентично ("Agent"), и это не меняется.
- Рендеринг tool call'ов как записей `transcriptEntries` — как и сегодня, они не отображаются в transcript (видны в инспекторе/approval-панели).
- Изменение публичного API `AcpTranscriptPanel`/`AcpTranscriptEntry` в `acp_ui` — панель продолжает рендерить один пузырь на одну запись списка без изменений.
- Устранение отдельной, не связанной с этим change'ем дубликации: `submitPrompt`'s успешная ветка также вручную выставляет `inspectorEntries: _inspectorEntriesForTurn(turn)` поверх уже актуального значения из `_handleSessionChange` — предсуществующая мелкая избыточность, не в scope здесь.

## Decisions

- **Единая функция вывода: `_transcriptEntriesForSession(AcpSession session)` становится единственным источником `transcriptEntries`**, вызываемым из `_handleSessionChange` на каждое событие (как уже происходит для `_inspectorEntriesForSession`), а не только при переключении сессии. `submitPrompt` перестаёт вручную собирать/добавлять agent-записи — он лишь ждёт результат `_sendPromptUseCase` ради diagnostic-лога и обработки ошибки отправки; сам transcript уже будет актуален к моменту резолва future, так как `_handleSessionChange` успевает отреагировать на каждое промежуточное `sessionChanges`-событие раньше.
- **Коалесация — по соседству в `turn.updates`, а не по типу "последнего добавленного текста".** Проход по `turn.updates` в порядке поступления; продолжающийся "прогон" (run) определяется тем, что **непосредственно предыдущий элемент списка** имеет тот же runtime-тип (`AgentMessageChunk` или `AgentThoughtChunk`), что и текущий — независимо от того, дал ли предыдущий элемент непустой текст. Если между двумя `AgentMessageChunk` оказался, например, `ToolCallUpdate`, run прерывается и создаётся новая запись — это соответствует интуитивному UX (действие агента между двумя мыслями не должно склеивать их текст в одну фразу без разрыва).
  - Альтернатива (отклонена): коалесировать только по типу последнего добавленного *непустого* текста, игнорируя промежуточные не-текстовые/пустые чанки того же или другого типа. Отклонено — это могло бы незаметно склеить текст через границу tool call'а, если оба текстовых чанка технически одного типа, но разделены tool-call-апдейтом, что ломает читаемость сообщения.
- **`AgentMessageChunk` и `AgentThoughtChunk` продолжают не разделяться визуально** (оба — один и тот же `kind`/`title`), поэтому соседний прогон message→thought→message даст 3 отдельные записи (все "Agent"), а не 1 — это лучше сегодняшнего (N чанков → N записей на каждый чанк), но не идеальный случай для этого конкретного паттерна чередования. Отдельная визуальная дифференциация thought/message — естественный кандидат на будущий change, не блокирует этот.
- **`submitPrompt`'s ручной append диагностической записи об ошибке отправки (failure-ветка) также удаляется**, а не только успешная ветка (шире, чем изначально сформулировано в proposal.md — proposal обновлён соответствующе). Причина: `AcpClientApplication.sendPrompt`'s catch-блок уже вызывает `SessionStateMachine.failTurn(message: error.toString())` и `_storeSession(failedSession)` **до** rethrow (`acp_client_application.dart:225-236`), то есть `_handleSessionChange` уже получает провалившийся turn через `sessionChanges` и (через `_transcriptEntriesForSession`'s существующую ветку `turn.status == PromptTurnStatus.failed`, `shell_cubit.dart:1371-1379`) уже породит diagnostic-запись "Failed to send prompt: ...". Оставление обоих путей дало бы дублирующееся сообщение об одной и той же ошибке.
- **Стабильность `id` записей.** Так как `transcriptEntries` теперь всегда пересчитывается целиком из `session.turns`, `id` каждой записи (`prompt-N`/`agent-N`) детерминирован её позицией в списке. Пока текущий "растущий" прогон продолжается (новые чанки лишь дописывают текст в последнюю запись), позиция и, соответственно, `id` всех более ранних записей не меняются — стабильно для `ListView`/анимаций прокрутки; меняется только `body` последней записи.

## Risks / Trade-offs

- [Полный пересчёт `transcriptEntries` из всех `session.turns` на каждое `sessionChanges`-событие — потенциально O(число turn × число updates) работы на каждый входящий чанк в очень длинной сессии] → Ожидаемый объём (реалистичное число turn'ов и чанков в desktop-сессии, текстовые Text-виджеты без тяжёлого рендеринга) делает это не проблемой на практике; если профилирование покажет иначе — можно кэшировать записи уже завершённых turn'ов и пересчитывать только "хвост" активного turn'а, не меняя внешний контракт этой функции.
- [Message↔thought чередование внутри одного turn всё ещё даёт несколько визуально неотличимых "Agent"-пузырей подряд] → Осознанно принято как Non-Goal (см. выше); не регресс относительно сегодняшнего поведения, просто не полное решение для этого частного паттерна.
- [Убирая ручной append в failure-ветке `submitPrompt`, полагаемся на то, что `turn.failureMessage` (из `error.toString()` в `acp_client_application.dart`) даёт пользователю не менее полезный текст, чем сегодняшний `_failureMessage(failure)` (маппинг типизированных `AcpClientApplicationFailure` в shell_cubit.dart:1296-1303)] → см. Open Questions ниже; требует проверки/теста на этапе задач перед удалением текущей ветки.

## Open Questions

- Совпадает ли по содержанию `turn.failureMessage` (formed as `error.toString()` при поднятии в `AcpClientApplication.sendPrompt`) с тем, что сегодня показывает `_failureMessage(failure)` в shell_cubit (маппинг по типу `AcpClientTransportFailure`/`AcpClientProtocolFailure`/и т. д.)? Если разойдётся заметно (менее информативно для пользователя) — на этапе задач либо обогатить `failTurn`'s message в domain-слое, либо оставить точечный fallback-текст в производной функции transcript для diagnostic-записи именно failure-turn'ов.
