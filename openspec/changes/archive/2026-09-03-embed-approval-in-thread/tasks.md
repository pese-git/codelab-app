## 1. acp_ui — модель записи транскрипта

- [x] 1.1 Добавить `AcpTranscriptApproval` (или аналогичное имя) — небольшой value-класс/sealed-тип: `pending` вариант (risk, reason, details, `List<AcpApprovalOption>`, `onOptionSelected`, `enabled`) и `resolved` вариант (`label`) в `packages/flutter/acp_ui/lib/src/organisms/`
- [x] 1.2 Добавить поле `approval: AcpTranscriptApproval?` в `AcpTranscriptEntry` (`acp_transcript_panel.dart`)
- [x] 1.3 Обновить `_AcpTranscriptEntryRow`: когда `entry.approval` — `pending`, рендерить интерактивный approval-контент inline (риск/причина/детали/опции с шорткатами) без внешней рамки/фона поверх уже имеющейся рамки записи; когда `resolved` — рендерить компактный маркер (иконка + label)
- [x] 1.4 Обновить `acp_organism_previews.dart`/widget preview для нового поля, чтобы preview-каталог не сломался

## 2. acp_ui — автоскролл

- [x] 2.1 Добавить `ScrollController` в `AcpTranscriptPanel` (или принять его как параметр, если host должен управлять scroll snapshot'ами)
- [x] 2.2 Реализовать эвристику "пользователь у низа ленты" (threshold от maxScrollExtent) и автоскролл к новой pending-approval записи только когда эвристика верна
- [x] 2.3 Тест: новая approval-запись при пользователе внизу ленты → скролл срабатывает; при пользователе, проскроллившем вверх → скролл не срабатывает

## 3. application — построение transcript из turn.updates

- [x] 3.1 В `CodeLabShellCubit._agentTranscriptEntries` учитывать `SessionUpdate.toolCall`: на каждое такое событие вставлять tool-call запись в текущую позицию потока (после `flush()` накопленного текстового run), связанную с `toolCallId`
- [x] 3.2 `SessionUpdate.toolCallUpdate` не создаёт новую запись — только помечает, что уже вставленная запись данного `toolCallId` должна перечитать актуальное состояние из `turn.toolCalls[id]` при рендере
- [x] 3.3 Содержимое/статус/риск каждой tool-call записи вычисляется из `turn.toolCalls[id]` в момент построения списка (не из сырого update), аналогично уже существующему `_pendingApprovalFor`
- [x] 3.4 Для tool-call записи, у которой есть `ApprovalRequest` в `turn.approvals` со статусом `pending`, строить `AcpTranscriptApproval.pending(...)` с callback, вызывающим существующий `cubit.respondToApproval(approvalId, optionId)`
- [x] 3.5 Для tool-call записи с approval в статусе `selected`/`cancelled` строить `AcpTranscriptApproval.resolved(label: ...)` из имени выбранной `PermissionOption` (или "Cancelled")
- [x] 3.6 Тесты на порядок: tool call между двумя текстовыми run; несколько tool calls подряд; tool call без последующего текста в незавершённом turn

## 4. application — убрать глобальный pendingApproval slot

- [x] 4.1 Grep-аудит всех использований `state.pendingApproval`/`CodeLabPendingApproval`/`_pendingApprovalFor` в `apps/codelab_app` (включая тесты) перед удалением
- [x] 4.2 Удалить `CodeLabPendingApproval`, поле `pendingApproval` из `CodeLabShellState`, метод `_pendingApprovalFor`
- [x] 4.3 Добавить `focusedApprovalId`-подобное non-visual состояние (самый ранний по `requestedAt` pending approval активного turn) — используется только для клавиатурных шорткатов, не для отдельного видимого UI (реализовано как `_earliestPendingApprovalId(turn)`, вычисляется при построении transcript, не хранится отдельным полем состояния)
- [x] 4.4 `respondToApproval` продолжает принимать `optionId` (и, если ещё не принимал явно, `approvalId`) — привязывается к конкретной записи, а не к единственному глобальному состоянию (сигнатура теперь `respondToApproval({required approvalId, required sessionId, required optionId})`)

## 5. presentation — main_pane.dart

- [x] 5.1 Удалить блок `if (state.pendingApproval case final approval?) ... AcpApprovalPanel(...)` из `main_pane.dart`
- [x] 5.2 Убедиться, что `AcpPromptComposer`/остальной layout не зависят от вертикального пространства, которое раньше занимала эта панель (нет визуального "провала")
- [x] 5.3 Подключить клавиатурные шорткаты approve/reject к `focusedApprovalId` (задача 4.3) на уровне, где раньше был `CallbackShortcuts` внутри снятой панели (уже реализовано через `shortcutsEnabled` на каждой встроенной `AcpApprovalPanel` в `_transcriptApproval` — main_pane не оборачивал шорткаты отдельно, менять там нечего)

## 6. Тесты

- [x] 6.1 Widget-тест: pending approval рендерится внутри записи transcript, а не отдельным виджетом снаружи ленты (подтверждено удалением отдельной панели из `main_pane.dart` + тестами ниже, проверяющими `entry.approval`)
- [x] 6.2 Widget-тест: два параллельных pending approval видны одновременно, независимо друг от друга
- [x] 6.3 Widget-тест: после выбора опции запись схлопывается в resolved-маркер и остаётся в списке (не исчезает)
- [x] 6.4 Widget-тест: `Ctrl/Cmd+Enter`/`Escape` применяются к approval с наименьшим `requestedAt` среди нескольких pending (через `shortcutsEnabled` — FIFO)
- [x] 6.5 Regression-тест: переключение сессий показывает transcript/approval только новой активной сессии (существующий сценарий "Переключение сессий показывает только состояние этой сессии" не должен сломаться)

## 7. Документация

- [x] 7.1 Свериться, что `docs/architecture/session-lifecycle.md`/`streaming.md` не содержат утверждений, противоречащих новому способу построения transcript (например, любых упоминаний, что approval — обязательно "отдельная панель") — поправить при необходимости (проверено grep'ом — ни один документ не утверждает, что approval обязан быть отдельной панелью; правок не потребовалось)

## 8. Проверка

- [x] 8.1 `fvm dart run melos run format`
- [x] 8.2 `fvm dart run melos run analyze`
- [x] 8.3 `fvm dart run melos run test`
