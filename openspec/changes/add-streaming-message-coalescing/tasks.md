## 1. Функция коалесации transcript-записей

- [ ] 1.1 Переписать `_agentTranscriptEntries` (`shell_cubit.dart:1305-1347`): схлопывать подряд идущие `AgentMessageChunk`/`AgentThoughtChunk` по соседству в `turn.updates` (алгоритм — см. design.md, раздел Decisions) вместо одной записи на каждый чанк
- [ ] 1.2 Сохранить существующее fallback-поведение — синтетическая запись "Completed with stopReason ..." для завершённого turn без единого текстового чанка

## 2. Единый вывод transcriptEntries через _handleSessionChange

- [ ] 2.1 Вызывать `_transcriptEntriesForSession(session)` внутри `_handleSessionChange` (`shell_cubit.dart:1039-1062`) и устанавливать `transcriptEntries` в `state.copyWith(...)` наравне с `inspectorEntries`/`pendingApproval`/`configOptions`
- [ ] 2.2 Убрать ручной append `agentEntries` в успешной ветке `submitPrompt` (`shell_cubit.dart:817-829`) — оставить только diagnostic-лог, сброс `isPromptSubmitting`/`canCancel`
- [ ] 2.3 Убрать ручной append diagnostic-записи об ошибке отправки в failure-ветке `submitPrompt` (`shell_cubit.dart:793-816`) — по той же причине (см. design.md, Decisions)
- [ ] 2.4 Проверить, что optimistic "You"-запись по-прежнему появляется сразу при отправке промпта — через `_storeSession(runningSession)`, вызываемый в `AcpClientApplication.sendPrompt` (`acp_client_application.dart:199-205`) до сетевого запроса, а не только после ответа агента

## 3. Проверка эквивалентности сообщения об ошибке (Open Question из design.md)

- [ ] 3.1 Сравнить текст `turn.failureMessage` (`error.toString()` в catch-блоке `AcpClientApplication.sendPrompt`) с текстом `_failureMessage(failure)` (`shell_cubit.dart:1296-1303`) для тех же типов ошибок отправки
- [ ] 3.2 Если тексты расходятся так, что пользователю станет менее понятно — доработать сообщение на domain-уровне (`SessionStateMachine.failTurn`) либо задокументировать расхождение как принятое отличие

## 4. Тесты

- [ ] 4.1 Unit-тест: несколько подряд идущих `AgentMessageChunk` схлопываются в одну запись с конкатенированным текстом
- [ ] 4.2 Unit-тест: обновление другого рода (например, обновление вызова инструмента) между двумя `AgentMessageChunk` создаёт две отдельные записи, а не одну
- [ ] 4.3 Unit-тест: смена рода потокового обновления (message → thought или обратно) создаёт новую запись, даже без стороннего обновления между ними
- [ ] 4.4 Cubit-тест: emit `sessionChanges` с ещё не терминальным активным turn обновляет `transcriptEntries` до завершения turn (проверка эффекта "живого" дописывания)
- [ ] 4.5 Тест: `id` уже сформированных ранее записей transcript остаются стабильными при пересчёте по мере роста текста последней записи
- [ ] 4.6 Обновить существующие тесты `_agentTranscriptEntries`/`_transcriptEntriesForSession`, ожидавшие одну запись на каждый чанк

## 5. Проверка

- [ ] 5.1 `fvm dart run melos run format`
- [ ] 5.2 `fvm dart run melos run analyze`
- [ ] 5.3 `fvm dart run melos run test`
