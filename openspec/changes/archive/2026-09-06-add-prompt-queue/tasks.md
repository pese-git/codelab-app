## 1. State и постановка в очередь

- [x] 1.1 Добавить `AcpQueuedPrompt {id, content}` в `packages/flutter/acp_ui` (presentation-тип, без промежуточного app-level DTO — см. `design.md`) и `queuedPrompts: List<AcpQueuedPrompt>` в `CodeLabShellState`
- [x] 1.2 В `submitPrompt()` — проверка `isPromptSubmitting || pendingApproval != null` (`_isSessionBusy()`) до попытки отправки; при true — добавить в `queuedPrompts`, не вызывать `_sendPromptUseCase`, не трогать `transcriptEntries`
- [x] 1.3 Убедиться, что при false (сессия свободна) поведение не меняется — прямая отправка как сегодня (вынесена в общий `_dispatchPrompt`, используется и прямой отправкой, и Send Now, и авто-drain)

## 2. Управление очередью

- [x] 2.1 Реализовать `editQueuedPrompt(id)` — удаляет из очереди, возвращает текст в композер через `composerDraft`/`initialPrompt`
- [x] 2.2 Реализовать `deleteQueuedPrompt(id)`
- [x] 2.3 Реализовать `sendQueuedPromptNow(id)` — немедленная попытка через общий `_dispatchPrompt`; при отказе (гонка, `_isSessionBusy()` всё ещё true) — элемент остаётся на прежнем месте в очереди (не удаляется вовсе), без diagnostic-ошибки
- [x] 2.4 Реализовать `clearQueuedPrompts()`
- [x] 2.5 Реализовать авто-drain (`_drainQueueIfFree()`): вызывается после `_dispatchPrompt`, `cancelTurn()` и `respondToApproval()` — каждый раз заново проверяет полное условие (`isPromptSubmitting` + pending approval активной сессии), не полагается на то, какой сигнал только что изменился; рекурсивно дренирует всю очередь, а не только первый элемент

## 3. AcpPromptQueuePanel — секция AcpActivityBar (acp_ui)

- [x] 3.1 Реализовать `AcpPromptQueuePanel.section(...)` — статическая фабрика `AcpActivityBarSection` (тот же паттерн, что `AcpProgressChecklist.section(...)`): заголовок "Queue" + счётчик, кнопка Clear All в заголовке (аналогично "✕ Clear" у Plan); тело — список элементов с Edit/Delete/Send Now на каждый
- [x] 3.2 Секция не включается в список `sections`, передаваемый в `AcpActivityBar`, когда очередь пуста (тот же принцип, что и для Plan — не рендерится вообще, не пустой заглушкой)

## 4. Композер

- [x] 4.1 Проверено: `AcpPromptComposer._submit()` уже вызывает `_controller.clear()` синхронно сразу после `onSubmit`, без изменений — текст в обоих исходах (очередь/отправка) сохраняется вне композера, так что это уже безопасно; `didUpdateWidget` уже синхронизирует `_controller.text` при изменении `initialPrompt`, обратной подстановки текста при Edit тоже не требует правок

## 5. Интеграция в main pane

- [x] 5.1 В `WorkbenchMainPane` добавить секцию Queue в тот же список `sections`, что уже строится для `AcpActivityBar` (Plan) — не новый слот layout, не второй контейнер

## 6. Тесты

- [x] 6.1 Widget-тест: submit во время `pendingApproval` кладёт сообщение в очередь, не показывает "Prompt failed"
- [x] 6.2 Widget-тест: submit во время `isPromptSubmitting` кладёт в очередь
- [x] 6.3 Widget-тест: submit при свободной сессии отправляется немедленно, поведение не изменилось
- [x] 6.4 Widget-тест: Edit возвращает текст в композер и убирает из очереди
- [x] 6.5 Widget-тест: Delete убирает элемент без отправки
- [x] 6.6 Widget-тест: Send Now при свободной сессии отправляет немедленно — на практике недостижимо как отдельное внешне наблюдаемое состояние (каждый путь освобождения сессии — завершение `_dispatchPrompt`, `cancelTurn`, `respondToApproval` — синхронно продолжается в тот же `_drainQueueIfFree()` до возврата управления, см. design.md, Decisions), поэтому реальный «свободная сессия → отправка» код-путь `sendQueuedPromptNow` покрыт тестом 6.9 (тот же `_dispatchPrompt`); тест 6.6 вместо этого проверяет defensive-guard на несуществующем id
- [x] 6.7 Widget-тест: Send Now в момент гонки (сессия ещё занята) возвращает элемент в очередь без ошибки — расширен до проверки, что элемент затем всё равно доставляется через авто-drain, когда сессия освобождается
- [x] 6.8 Widget-тест: Clear All очищает всю очередь
- [x] 6.9 Widget-тест: снятие блокировки автоматически отправляет самый старый элемент очереди
- [x] 6.10 Widget-тест: когда есть и активный план, и непустая очередь — `AcpActivityBar` показывает обе секции одновременно (не только одну из них)

## 7. Проверка

- [x] 7.1 `fvm dart run melos run format`
- [x] 7.2 `fvm dart run melos run analyze`
- [x] 7.3 `fvm dart run melos run test`
