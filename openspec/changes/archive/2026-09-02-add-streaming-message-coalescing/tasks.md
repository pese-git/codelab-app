## 1. Функция коалесации transcript-записей

- [x] 1.1 Переписать `_agentTranscriptEntries` (`shell_cubit.dart:1305-1347`): схлопывать подряд идущие `AgentMessageChunk`/`AgentThoughtChunk` по соседству в `turn.updates` (алгоритм — см. design.md, раздел Decisions) вместо одной записи на каждый чанк
- [x] 1.2 Сохранить существующее fallback-поведение — синтетическая запись "Completed with stopReason ..." для завершённого turn без единого текстового чанка

## 2. Единый вывод transcriptEntries через _handleSessionChange

- [x] 2.1 Вызывать `_transcriptEntriesForSession(session)` внутри `_handleSessionChange` (`shell_cubit.dart:1039-1062`) и устанавливать `transcriptEntries` в `state.copyWith(...)` наравне с `inspectorEntries`/`pendingApproval`/`configOptions`
- [x] 2.2 Убрать ручной append `agentEntries` в успешной ветке `submitPrompt` (`shell_cubit.dart:817-829`) — оставить только diagnostic-лог, сброс `isPromptSubmitting`/`canCancel`
- [x] 2.3 Убрать ручной append diagnostic-записи об ошибке отправки в failure-ветке `submitPrompt` (`shell_cubit.dart:793-816`) — по той же причине (см. design.md, Decisions)
- [x] 2.4 Проверить, что optimistic "You"-запись по-прежнему появляется сразу при отправке промпта — через `_storeSession(runningSession)`, вызываемый в `AcpClientApplication.sendPrompt` (`acp_client_application.dart:199-205`) до сетевого запроса, а не только после ответа агента. Подтверждено: этот emit в `submitPrompt` не тронут этим change'ем — остаётся как есть.

## 3. Проверка эквивалентности сообщения об ошибке (Open Question из design.md)

- [x] 3.1 Сравнить текст `turn.failureMessage` (`error.toString()` в catch-блоке `AcpClientApplication.sendPrompt`) с текстом `_failureMessage(failure)` (`shell_cubit.dart:1296-1303`) для тех же типов ошибок отправки. Расхождение подтверждено: `AcpClientApplicationException`/`AcpTransportException`/`StateTransitionException` переопределяют `toString()` с префиксом имени класса (`"ClassName: message"` / `"ClassName(code): message"`), тогда как `_failureMessage` берёт чистое поле `message`.
- [x] 3.2 Тексты расходятся заметно (протекает имя типа исключения в пользовательский текст) — решено не трогать domain-слой (вне заявленного scope этого change'а, proposal.md §Impact), вместо этого добавлена `_cleanDomainFailureMessage` в `shell_cubit.dart`, снимающая префикс `"ClassName[(...)]: "` на уровне производной transcript-функции

## 4. Тесты

- [x] 4.1 Unit-тест: несколько подряд идущих `AgentMessageChunk` схлопываются в одну запись с конкатенированным текстом — `test/widget_test.dart`, "submitPrompt coalesces consecutive agent_message_chunk updates into a single, growing transcript entry"
- [x] 4.2 Unit-тест: обновление другого рода (например, обновление вызова инструмента) между двумя `AgentMessageChunk` создаёт две отдельные записи, а не одну — "a tool call update between two agent_message_chunk runs starts a new transcript entry instead of merging their text"
- [x] 4.3 Unit-тест: смена рода потокового обновления (message → thought или обратно) создаёт новую запись, даже без стороннего обновления между ними — "switching from agent_message_chunk to agent_thought_chunk starts a new transcript entry instead of merging their text"
- [x] 4.4 Cubit-тест: emit `sessionChanges` с ещё не терминальным активным turn обновляет `transcriptEntries` до завершения turn (проверка эффекта "живого" дописывания) — покрыто тем же тестом, что и 4.1 (`isPromptSubmitting: isTrue` в момент проверки первого частично полученного чанка)
- [x] 4.5 Тест: `id` уже сформированных ранее записей transcript остаются стабильными при пересчёте по мере роста текста последней записи — покрыто тем же тестом, что и 4.1 (`growingEntryId` сравнивается на трёх этапах)
- [x] 4.6 Обновить существующие тесты `_agentTranscriptEntries`/`_transcriptEntriesForSession`, ожидавшие одну запись на каждый чанк — проверено: в существующих тестах не было сценариев с несколькими `agent_message_chunk` за один turn (единственный существующий тест с чанком использует один чанк), обновлений не потребовалось; полный прогон `test/widget_test.dart` зелёный (51/51)

## 5. Проверка

- [x] 5.1 `fvm dart run melos run format` — 1 файл переформатирован (`test/widget_test.dart`)
- [x] 5.2 `fvm dart run melos run analyze` — без замечаний
- [x] 5.3 `fvm dart run melos run test` — все пакеты зелёные (`acp_ui` 66/66, `codelab_app` 51/51)
