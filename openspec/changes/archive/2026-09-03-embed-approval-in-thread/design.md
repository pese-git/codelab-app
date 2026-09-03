## Context

`agent-workbench-ui` уже требует "approval появляется inline в transcript" (см. proposal.md, Why). Сегодняшняя реализация не строит tool-call записи transcript вовсе: `CodeLabShellCubit._agentTranscriptEntries` обрабатывает только `AgentMessageChunk`/`AgentThoughtChunk` из `turn.updates` ([shell_cubit.dart:1362-1385](../../../apps/codelab_app/lib/features/workbench/application/shell_cubit.dart#L1362)), полностью пропуская `SessionUpdate.toolCall`/`toolCallUpdate`. Approval виден только через отдельный `state.pendingApproval` (единственный слот, `_pendingApprovalFor` берёт **первый по времени** pending approval активного turn, `shell_cubit.dart:1179-1211`).

`turn.updates` — сырой хронологический поток ACP session updates для активного/последнего turn; `turn.toolCalls`/`turn.approvals` — живые read-model карты, обновляемые по `toolCallId`/`approvalId` при каждом апдейте (не сырой поток, а текущее агрегированное состояние). `_transcriptEntriesForSession` уже документированно пересобирается **с нуля** при каждом `sessionChanges` event ([shell_cubit.dart:1403-1409](../../../apps/codelab_app/lib/features/workbench/application/shell_cubit.dart#L1403)) — это существующий idempotency-механизм (см. `add-streaming-message-coalescing/design.md`), которым это решение пользуется, не изобретая новый.

`docs/architecture/streaming.md:650,656` явно допускают параллельные tool calls и то, что approval одного из них не обязан быть terminal pause всего потока — единственный `pendingApproval`-слот структурно не может отразить это; embedding решает это естественно, так как каждый approval живёт при своей записи.

## Goals / Non-Goals

**Goals:**
- Tool call появляется в transcript в правильной хронологической позиции потока, с текущим статусом из `turn.toolCalls`.
- `pending` approval рендерится интерактивно внутри записи своего tool call; несколько параллельных pending approval видимы одновременно, каждый на своём месте.
- Resolved approval схлопывается в маркер на месте записи, не исчезает из истории.
- Лента автоскроллится к новому approval, если пользователь не читает историю выше.
- Существующие клавиатурные шорткаты approve/reject продолжают работать без регрессии для однозначного (единственного/первого) pending approval.

**Non-Goals:**
- Не меняется ACP wire protocol и `acp_protocol`/`acp_client_core` domain-модели (`ApprovalRequest`, `ToolCallRecord`, `PromptTurn` остаются как есть — уже достаточно данных).
- Не проектируется полноценный UX для одновременного approve/reject нескольких approval с клавиатуры (fine-grained focus management между несколькими карточками) — см. Open Questions.
- Не меняется `AcpApprovalPanel`/`AcpApprovalOptionGroup` API сверх минимально необходимого для inline-контекста (без внешней рамки, если родительская запись её уже даёт).
- Не трогает `add-approval-option-kinds` (kind-based шорткаты) — независимый change, эта работа с ним не конфликтует и не требует его как предпосылку.

## Decisions

### 1. Порядок transcript строится из `turn.updates`, содержимое — из `turn.toolCalls`/`turn.approvals`
`_agentTranscriptEntries` проходит `turn.updates` по порядку; на `SessionUpdate.toolCall(toolCall)` — вставляет новую tool-call запись в текущую позицию потока (после `flush()` любого накопленного текстового run) с `toolCallId` для последующего связывания; на `SessionUpdate.toolCallUpdate` — не создаёт новую запись (позиция уже зафиксирована первым `toolCall`-событием), только сигнализирует "есть свежие данные" для уже вставленной записи. Отображаемые статус/title/content/approval для этой записи читаются из `turn.toolCalls[id]`/`turn.approvals` в момент рендера — не из самого update-события, аналогично тому, как уже сегодня `_pendingApprovalFor` читает `turn.approvals`, а не поток.
- Альтернатива (отклонена): итерировать `turn.toolCalls.values` в порядке карты вместо `turn.updates`. Отклонена — `Map` не гарантирует сохранение порядка вставки для читаемости кода как контракта (Dart's `Map`/`LinkedHashMap` на практике сохраняет insertion order, но это не то же самое, что позиция относительно текстовых чанков agent'а — tool call между двумя текстовыми ответами должен визуально стоять между ними, что даёт только `turn.updates`).

### 2. Approval-данные — вложенный value object в `AcpTranscriptEntry`, не новые top-level поля россыпью
`AcpTranscriptEntry` получает одно новое опциональное поле `approval: AcpTranscriptApproval?` (новый небольшой класс: risk, reason, details, `List<AcpApprovalOption>`, `onOptionSelected`, либо `resolvedLabel` для уже решённого случая — например через sealed-вариант `pending`/`resolved`). Строка транскрипта рендерит `AcpApprovalPanel`-подобный контент только когда это поле не `null`.
- Альтернатива (отклонена): десяток отдельных nullable-полей (`approvalRisk`, `approvalOptions`, `approvalReason`, ...) прямо на `AcpTranscriptEntry`. Отклонена — размывает модель записи транскрипта посторонней ответственностью вместо одного явного namespace (`AGENTS.md §13`: не создавать лишние независимые поля там, где оправдан один составной объект).

### 3. Resolved-маркер вычисляется из существующих `ApprovalStatus`/`selectedOptionId`, без новых полей в domain
`ApprovalRequest` уже хранит `status` и `selectedOptionId` ([domain_models.dart:109-123](../../../packages/dart/acp_client_core/lib/src/domain/domain_models.dart#L109)). Presentation-слой при построении записи транскрипта, если `status != pending`, строит `AcpTranscriptApproval.resolved(label: ...)` из имени выбранной `PermissionOption` (или "Cancelled" для `cancelled`) — никакого нового domain-состояния не требуется.

### 4. `state.pendingApproval`/`CodeLabPendingApproval` удаляются из `CodeLabShellState`
Approval больше не отдельный кусок состояния shell — он полностью выражается через записи `state.transcriptEntries` (каждая несёт своё `approval`). `main_pane.dart` теряет блок `if (state.pendingApproval case ...)`. `respondToApproval(optionId)` в `CodeLabShellCubit` остаётся публичным методом (уже принимает `optionId`, не зависит от глобального слота), но теперь вызывается из callback конкретной записи, а не из единственной внешней панели.
- Альтернатива (отклонена): оставить `state.pendingApproval` как "какой approval сейчас в фокусе клавиатуры" отдельно от embedded-рендеринга остальных. Рассмотрена всерьёз — см. Decision 6 (шорткаты), но реализована не как отдельный видимый UI-слот, а как чистый non-visual "какой approvalId сейчас получает клавиатурный фокус" — это не тот же `pendingApproval`, что рисовал панель, поэтому переименовывается (`focusedApprovalId` или аналог), не путается с прежним полем.

### 5. Автоскролл к новому approval — только если пользователь не читает историю
`AcpTranscriptPanel` (или его host) отслеживает, находится ли scroll offset у пользователя "около низа" ленты (threshold, не точный 0) непосредственно перед приходом нового pending approval; если да — скроллит к новой записи; если пользователь проскроллил вверх (читает историю) — не трогает scroll position, но может показать unobtrusive "new approval" indicator (сама механика индикатора — на усмотрение реализации, не специфицируется этим change детально).
- Альтернатива (отклонена): всегда принудительно скроллить к новому approval. Отклонена — выдёргивает пользователя из чтения истории, хуже UX, чем текущее поведение (текущая фиксированная панель гарантированно видна, но именно потому, что она вне ленты — компромисс, который embedding сознательно меняет, и это надо явно компенсировать, а не игнорировать).

### 6. Клавиатурные шорткаты approve/reject привязаны к одному "focused" approval за раз (FIFO), не ко всем сразу
Когда pending approval несколько одновременно, глобальные `Ctrl/Cmd+Enter`/`Escape` применяются к самому раннему по `requestedAt` (тот же порядок, который уже вычисляет сегодняшний `_pendingApprovalFor`) — не к тому, что ближе к текущей scroll-позиции. Остальные pending approval кликабельны мышью, но не имеют глобального шortcut, пока не станут "самыми ранними" (после resolve предыдущего).
- Альтернатива (отложена, не решена в этом change): шорткат применяется к approval, ближайшему к центру viewport. Отклонена для MVP как усложнение без чёткого UX-прецедента у референсов; зафиксирована как Open Question.

## Risks / Trade-offs

- [Неправильная интерпретация `turn.updates` может визуально сместить tool call относительно текста, если агент присылает апдейты в нетипичном порядке] → тесты на несколько вариантов чередования (tool call до/после текста, несколько tool calls подряд, tool call между двумя текстовыми run) в `_agentTranscriptEntries`.
- [Пользователь, привыкший к фиксированному месту approval снизу, может не сразу найти карточку в ленте] → компенсируется автоскроллом (Decision 5); индикатор "есть новый approval выше/ниже" — недостающая часть UX, вне строгого scope, но стоит предусмотреть как минимум событие в состоянии, на которое presentation сможет опереться.
- [`AcpTranscriptEntry` разрастается новой ответственностью] → смягчается Decision 2 (один вложенный объект, а не россыпь полей).
- [Убирая `state.pendingApproval`, ломается что-то, что снаружи (тесты, другие виджеты) полагалось на это поле напрямую] → grep-аудит всех использований `state.pendingApproval`/`CodeLabPendingApproval` перед удалением, часть tasks.md.
- [Множественные одновременные pending approval — редкий, слабо протестированный на практике сценарий для существующих агентов] → покрыть explicit unit/widget тестом с двумя параллельными `ApprovalRequest` в одном `turn.approvals`, даже если в проде это будет редкость — иначе Decision 6 останется непроверенным кодом.

## Migration Plan

Персистентных данных/схем это не касается — `transcriptEntries` полностью пересобирается из `session.turns` при каждом событии (`shell_cubit.dart:1403-1409`), никакого stored UI state не мигрирует. Изменение разворачивается одним PR: protocol/domain слои не трогаются, откат — обычный revert коммита без последствий для сохранённых сессий или ACP-совместимости.

## Open Questions

- Нужен ли явный "new approval" индикатор/toast, когда автоскролл не сработал (пользователь читает историю), или достаточно того, что approval просто виден при следующем скролле вниз? Не решено, не блокирует MVP.
- Как в будущем распределять клавиатурный фокус между несколькими одновременными pending approval за пределами FIFO (Decision 6) — по scroll position, по explicit Tab-навигации между карточками? Оставлено как direction для отдельного последующего change, если параллельные tool calls на практике станут частым кейсом.
