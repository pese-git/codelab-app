## 1. State и постановка в очередь

- [ ] 1.1 Добавить `CodeLabQueuedPrompt {id, text}` и `queuedPrompts: List<CodeLabQueuedPrompt>` в `CodeLabShellState`
- [ ] 1.2 В `submitPrompt()` — проверка `isPromptSubmitting || pendingApproval != null` до попытки отправки; при true — добавить в `queuedPrompts`, не вызывать `_sendPromptUseCase`, не трогать `transcriptEntries`
- [ ] 1.3 Убедиться, что при false (сессия свободна) поведение не меняется — прямая отправка как сегодня

## 2. Управление очередью

- [ ] 2.1 Реализовать `editQueuedPrompt(id)` — удаляет из очереди, возвращает текст в композер через `initialPrompt`
- [ ] 2.2 Реализовать `deleteQueuedPrompt(id)`
- [ ] 2.3 Реализовать `sendQueuedPromptNow(id)` — немедленная попытка через `_sendPromptUseCase`; при отказе (гонка) — возврат на прежнее место в очереди, без diagnostic-ошибки
- [ ] 2.4 Реализовать `clearQueuedPrompts()`
- [ ] 2.5 Реализовать авто-drain: при переходе `isPromptSubmitting: false` и `pendingApproval: null` одновременно и непустой очереди — отправить самый старый элемент

## 3. AcpPromptQueuePanel (acp_ui)

- [ ] 3.1 Реализовать organism: список элементов, Edit/Delete/Send Now на элемент, Clear All для всей панели
- [ ] 3.2 Панель не рендерится (или родитель её не монтирует), когда очередь пуста

## 4. Композер

- [ ] 4.1 Проверить/скорректировать `AcpPromptComposer._submit()` — очистка поля остаётся синхронной, т.к. текст в обоих исходах (очередь/отправка) сохраняется вне композера; убедиться, что `initialPrompt` корректно принимает текст обратно при Edit без потери курсора/фокуса

## 5. Интеграция в main pane

- [ ] 5.1 Добавить `AcpPromptQueuePanel` между транскриптом и композером в `WorkbenchMainPane`

## 6. Тесты

- [ ] 6.1 Widget-тест: submit во время `pendingApproval` кладёт сообщение в очередь, не показывает "Prompt failed"
- [ ] 6.2 Widget-тест: submit во время `isPromptSubmitting` кладёт в очередь
- [ ] 6.3 Widget-тест: submit при свободной сессии отправляется немедленно, поведение не изменилось
- [ ] 6.4 Widget-тест: Edit возвращает текст в композер и убирает из очереди
- [ ] 6.5 Widget-тест: Delete убирает элемент без отправки
- [ ] 6.6 Widget-тест: Send Now при свободной сессии отправляет немедленно
- [ ] 6.7 Widget-тест: Send Now в момент гонки (сессия ещё занята) возвращает элемент в очередь без ошибки
- [ ] 6.8 Widget-тест: Clear All очищает всю очередь
- [ ] 6.9 Widget-тест: снятие блокировки автоматически отправляет самый старый элемент очереди

## 7. Проверка

- [ ] 7.1 `fvm dart run melos run format`
- [ ] 7.2 `fvm dart run melos run analyze`
- [ ] 7.3 `fvm dart run melos run test`
