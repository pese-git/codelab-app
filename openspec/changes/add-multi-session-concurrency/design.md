## Context

`CodeLabShellCubit.isPromptSubmitting`/`canCancel` сегодня — обычные `bool`-поля state, вручную выставляемые внутри `_dispatchPrompt`/`cancelTurn`/`respondToApproval` (`state.copyWith(isPromptSubmitting: true/false, ...)`), одни на весь cubit, без привязки к конкретной сессии. `_isSessionBusy(sessionId)` сначала проверяет именно этот общий флаг и только потом — approval конкретной сессии (`shell_cubit.dart`, комментарий: «isPromptSubmitting itself stays a single cubit-wide flag, not per-session — only one session/prompt round trip is ever in flight through this cubit at a time regardless of sessionId»).

При этом сам домен уже отслеживает занятость **на уровне каждой сессии независимо**: `AcpSession.status` — `SessionLifecycleStatus { idle, active, runningTurn, awaitingApproval, failed }` (`domain_models.dart`). `SessionStateMachine._startTurn` проверяет статус именно ТОЙ сессии, для которой стартует turn, не какой-то общий флаг; `_requestApproval`/`_selectApproval`/`_cancelApproval` корректно держат `awaitingApproval`, пока остаётся хоть один нерешённый approval (`_resolveApproval`: `hasPending = approvals.values.any((a) => !a.isResolved)`), и снимают его только когда все approval'ы разрешены — то есть уже сейчас поддерживают несколько параллельных approval на один turn (см. существующий тест «two parallel pending approvals are both embedded independently»). `_sendRequest` отслеживает запросы по id в `_pendingRequests`, без единой блокировки. Каждое изменение сессии (включая самое первое — `_storeSession(runningSession)` в момент старта turn, синхронно, до `await`) публикуется в `sessionChanges`, на который cubit уже подписан.

Дальше — вторая находка, важная для UI: `AcpSessionListItem` (используется сайдбаром сессий) уже содержит `status: AcpSessionStatus` (idle/running/awaitingApproval/completed/failed/cancelled), и `acp_session_sidebar.dart` уже рендерит бейдж/иконку по этому полю для **каждого** элемента списка, не только активного. То есть визуальный индикатор «работает в фоне» технически уже существует — просто не обновляется для неактивных сессий, потому что `_handleSessionChange` сегодня начинается с:

```dart
if (state.activeSessionId != null && state.activeSessionId != session.id.value) {
  return;
}
```

— событие `sessionChanges` для любой неактивной сессии полностью игнорируется, включая обновление её собственной строчки в `state.sessions`.

Третья находка: `_transcriptEntriesForSession(session)` уже реконструирует и реплику пользователя (`_textFrom(turn.prompt)`), и запись о провале (`turn.status == failed && turn.failureMessage`) **из состояния домена**, независимо от чего-либо, что вручную кладёт в `transcriptEntries` `_dispatchPrompt`. Ручная вставка `userEntry` в `_dispatchPrompt` сегодня попросту дублирует то, что и так появится через `_handleSessionChange` на первом же `sessionChanges` событии этого turn'а.

## Goals / Non-Goals

**Goals:**
- Turn в сессии A продолжает выполняться (реальный round trip), пока пользователь работает в сессии B — ни то, ни другое не блокирует и не ставит в очередь друг друга.
- Композер, Send/Cancel и очередь (`add-prompt-queue`) реагируют только на состояние **активной** сессии — так же, как до этого change, просто корректно per-session.
- Сайдбар сессий показывает актуальный статус (idle/running/awaitingApproval/failed) для каждой сессии в реальном времени, включая неактивные — не только текущую.
- Очередь сообщений каждой сессии авто-дренируется, когда освобождается именно её собственный turn — независимо от того, какая сессия сейчас активна (это уже почти работает после `add-prompt-queue`'s per-session фикса; здесь закрывается последний пробел — сам сигнал «свободна» станет per-session).

**Non-Goals:**
- Split-view / одновременный показ нескольких сессий на экране — по-прежнему одна активная сессия видна за раз, только её занятость влияет на композер.
- Ограничение количества одновременно работающих сессий — не вводится (как и сегодня, лимитов на число turn'ов нет за пределами того, что каждая сессия может иметь только один активный turn — это уже гарантирует `SessionStateMachine`).
- Изменения в ACP wire-протоколе или `acp_client_core`/`acp_protocol` — не требуются, домен уже поддерживает параллельные turns per-session.

## Decisions

- **Источник истины занятости — `AcpSession.status`, не отдельный флаг в cubit.** `CodeLabShellState.isPromptSubmitting`/`canCancel` перестают быть вручную выставляемыми полями и становятся производными от `SessionLifecycleStatus` активной сессии (`runningTurn`/`awaitingApproval` → занята; `idle`/`active` → свободна), пересчитываемыми в `_handleSessionChange` при каждом `sessionChanges`-событии для активной сессии. Альтернатива — завести `Set<String> _submittingSessionIds` в cubit (по аналогии с `_queuedPromptsBySession` из `add-prompt-queue`) — отклонена: это дублировало бы состояние, которое домен и так корректно ведёт per-session, с риском рассинхронизации (собственно то, из-за чего сегодняшний общий флаг уже описан как потенциально «stale» в комментарии к `_isSessionBusy`).
- **`_handleSessionChange` разделяет два эффекта.** Обновление элемента `state.sessions` для изменившейся сессии (включая её `AcpSessionStatus`) происходит **всегда**, независимо от того, активна ли эта сессия — сайдбар уже умеет рендерить статус любого элемента, новых полей/виджетов не требуется. Пересчёт `transcriptEntries`/`inspectorEntries`/`agentCommands`/`configOptions`/`currentPlan`/`isPromptSubmitting`/`canCancel` остаётся условным — только если изменившаяся сессия совпадает с `activeSessionId` — чтобы фоновая сессия не подменяла то, что сейчас видит пользователь.
- **`_isSessionBusy(sessionId)` — чистая проверка домена.** Убирается ветка с `state.isPromptSubmitting` и ручной перебор `_earliestPendingApprovalId`; остаётся один запрос `_application.sessionById(sessionId)?.status` и проверка на `runningTurn`/`awaitingApproval`. Эквивалентность существующему поведению для одной сессии подтверждена через `_resolveApproval` — `awaitingApproval` уже корректно держится, пока остаётся хоть один нерешённый approval, ровно как сегодняшний ручной scan.
- **`_dispatchPrompt` перестаёт вручную класть `userEntry` в `transcriptEntries`.** Приход пользовательского сообщения в транскрипт уже гарантирован `_handleSessionChange`, реагирующим на `_storeSession(runningSession)` внутри `AcpClientApplication.sendPrompt` (синхронно, до первого `await`) — к моменту, когда `_dispatchPrompt` получил бы контроль обратно, `sessionChanges` для этого turn'а уже отработал. Диагностика (`_recordDiagnostic('Prompt completed with stopReason...')` и т. п.) остаётся как есть — это не presentation state, а сайд-эффект логирования, change его не трогает.
- **Авто-drain остаётся привязан к `sessionId`, которому принадлежит завершившийся turn** (уже так после `add-prompt-queue`) — но теперь `_isSessionBusy(sessionId)` внутри него корректно проверяет именно эту сессию, а не активную, так что очередь фоновой сессии, к которой никто не возвращался, всё равно дренируется в момент, когда её собственный turn реально завершается — без необходимости в отдельном «drain при возврате к сессии» механизме (изначально предполагавшемся в proposal, но оказавшемся излишним при этом дизайне).
- **Тестовый агент (`codelab_compatible_stdio_agent.dart`) должен стать session-aware для e2e-покрытия.** Сегодня он хранит один константный `_sessionId` и один `_pendingPromptId`, что физически не позволяет смоделировать две сессии с параллельными turn'ами через один процесс. Для e2e на реальную параллельность нужен новый режим, генерирующий уникальный `sessionId` на каждый `session/new` и хранящий `_pendingPromptId` в `Map<String, Object?>`, keyed by session id — минимальное расширение существующего файла, не новый протокол.

## Risks / Trade-offs

- [Удаление ручных `emit(isPromptSubmitting/canCancel/transcriptEntries)` — широкий рефакторинг трёх методов, риск регресса в объёмном existing widget_test.dart] → внедрять поэтапно: сначала завести derived-путь и покрыть его тестами параллельно с существующим ручным путём, затем убирать ручные emit по одному, каждый раз прогоняя полный `melos test`, а не одним большим патчем.
- [`_handleSessionChange`'а теперь чаще будит cubit — событие для КАЖДОЙ фоновой сессии тоже вызывает `emit` (для обновления `state.sessions`)] → это уже наблюдаемое, штатное поведение Bloc (rebuild только там, где подписаны на изменившуюся часть state); сайдбар сессий и так перерисовывается на каждое изменение списка сессий, доп. нагрузки не создаёт.
- [Два параллельных turn'а в реальном e2e-тесте требуют session-aware тестового агента, которого сегодня нет] → отдельная, явно выделенная задача в tasks.md перед самим e2e-тестом; agent должен остаться пригодным для scenario prompт'ов существующих e2e-тестов (не менять поведение для одной сессии).
- [Пользователь может не заметить, что сессия A всё ещё работает в фоне, если не смотрит на сайдбар] → тот же существующий статус-бейдж (`Running`/`Approval`), просто теперь живой для фоновых сессий — никакой новой, более навязчивой нотификации (toast/badge-count) этот change не вводит; если понадобится — отдельный change.
