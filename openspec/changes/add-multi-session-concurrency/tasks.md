## 1. Derived busy-state вместо ручного флага

- [ ] 1.1 Добавить `_isSessionBusyStatus(sessionId)` / переиспользовать существующий доступ к `_application.sessionById(sessionId)?.status`, возвращающий `runningTurn`/`awaitingApproval` → занята, `idle`/`active`/`failed` → свободна
- [ ] 1.2 Упростить `_isSessionBusy(sessionId)` до чистой проверки статуса домена (см. design.md, Decisions) — убрать ветку с `state.isPromptSubmitting` и ручной перебор `_earliestPendingApprovalId`
- [ ] 1.3 Убедиться, что `CodeLabShellState.isPromptSubmitting`/`canCancel` пересчитываются в `_handleSessionChange` для активной сессии из её текущего `AcpSession.status`, а не выставляются вручную внутри `_dispatchPrompt`/`cancelTurn`/`respondToApproval`

## 2. `_handleSessionChange` — разделение эффектов

- [ ] 2.1 Убрать ранний `return`, полностью игнорирующий события для неактивных сессий — обновление элемента `state.sessions` (включая `AcpSessionStatus`) должно происходить для любой сессии, изменившейся в `sessionChanges`
- [ ] 2.2 Пересчёт `transcriptEntries`/`inspectorEntries`/`agentCommands`/`configOptions`/`currentPlan`/`isPromptSubmitting`/`canCancel` оставить условным — только когда изменившаяся сессия совпадает с `activeSessionId`
- [ ] 2.3 Проверить существующий тест «switching sessions reloads transcript, inspector and pending approval for the newly selected session...» и аналогичные — не должны сломаться после разделения эффектов

## 3. Убрать дублирующую ручную запись в transcript

- [ ] 3.1 Убрать вставку `userEntry` в `_dispatchPrompt` — `_transcriptEntriesForSession` уже реконструирует реплику пользователя из `turn.prompt` через `_handleSessionChange`
- [ ] 3.2 Убедиться, что запись о провале ("Failed to send prompt: ...") по-прежнему появляется в transcript — она тоже уже реконструируется из `turn.failureMessage`, ручная вставка в `result.match`'s failure-ветке `_dispatchPrompt` не нужна для transcript (диагностика/`_recordDiagnostic` остаётся)

## 4. Параллельные turns

- [ ] 4.1 Проверить (и при необходимости поправить) `submitPrompt`/`sendQueuedPromptNow`/`_drainQueueIfFree` — каждый вызывает `_isSessionBusy` с правильным `sessionId`, не полагаясь более на общий флаг
- [ ] 4.2 Убедиться, что `_dispatchPrompt`, вызванный для сессии, которая перестала быть активной пока запрос был в полёте, не портит presentation state активной (в данный момент другой) сессии — эффект должен идти только через `_handleSessionChange`
- [ ] 4.3 Widget-тест: turn в сессии A продолжает идти, пока пользователь создаёт и работает в сессии B — сообщение в B отправляется немедленно, не в очередь
- [ ] 4.4 Widget-тест: завершение turn'а в фоновой сессии A (пока активна B) не меняет `transcriptEntries`/`isPromptSubmitting`/`canCancel`, которые видит B
- [ ] 4.5 Widget-тест: очередь фоновой сессии A дренируется автоматически по завершении её собственного turn'а, пока активна другая сессия (без возврата к A)

## 5. Сайдбар сессий — живой статус фоновых сессий

- [ ] 5.1 Widget-тест: статус неактивной сессии в `state.sessions` (`AcpSessionListItem.status`) обновляется на `running`/`awaitingApproval`/`idle` по мере хода её turn'а — без переключения на неё
- [ ] 5.2 Убедиться, что `acp_session_sidebar.dart` уже корректно рендерит этот статус для любого элемента списка (новых виджетов не требуется, см. design.md) — зафиксировать существующим/новым widget-тестом в `acp_organisms_test.dart`

## 6. Тестовый агент становится session-aware

- [ ] 6.1 В `codelab_compatible_stdio_agent.dart` заменить константный `_sessionId` на генерацию уникального id на каждый `session/new`
- [ ] 6.2 Заменить одиночный `_pendingPromptId` на `Map<String, Object?>`, keyed by session id, чтобы независимо отслеживать отложенный `session/prompt` для каждой сессии
- [ ] 6.3 Добавить новый режим (например `withConcurrentSessions`), в котором первая сессия зависает на permission request, а вторая, созданная поверх того же процесса, отвечает сразу — без взаимного блокирования
- [ ] 6.4 Убедиться, что существующие e2e-тесты (single-session режимы) не сломались от смены `_sessionId`/`_pendingPromptId` на per-session хранение

## 7. E2e на реальную параллельность

- [ ] 7.1 Новый e2e-тест: сессия A отправляет запрос и зависает на approval; пользователь создаёт сессию B и отправляет в неё запрос — оно уходит немедленно, реальный второй `session/prompt` round trip завершается независимо от A
- [ ] 7.2 В том же тесте: approval A разрешается уже после ответа B — транскрипт A корректно обновляется, пока активна B, и корректно отображается при возврате к A
- [ ] 7.3 Добавить скрипт `test:e2e:app:multi-session` в `melos.yaml`

## 8. Проверка

- [ ] 8.1 `fvm dart run melos run format`
- [ ] 8.2 `fvm dart run melos run analyze`
- [ ] 8.3 `fvm dart run melos run test`
- [ ] 8.4 Прогнать новый e2e-тест (`melos run test:e2e:app:multi-session`)
