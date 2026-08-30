## Why

Сегодня на практике (см. `openspec/changes/add-session-config-options-selector` и её живую отладку) подтверждён баг: если stdio-процесс агента умирает неожиданно (например, убит `kill -9`, или сам агент упал), `CodeLabShellCubit` никак этого не замечает — UI навсегда остаётся в состоянии `Connected`, активный prompt turn навсегда показывается как `running`, а единственный способ восстановиться — полностью перезапустить всё приложение (`Reconnect`/`Connect` не помогают, потому что кубит считает себя уже подключённым и не предпринимает никаких действий).

Корень проблемы — на два слоя глубже, чем можно было предположить: `CodeLabShellCubit` действительно нигде не подписан на `AcpClientApplication.connectionStateChanges`, но даже если бы был подписан — это не помогло бы. `AcpClientApplication._handleTransportEvent` (`acp_client_application.dart:712-735`) при получении `AcpTransportFailure` от транспорта сегодня **только пишет диагностику** — никогда не вызывает `_transitionConnection(ConnectionStateEvent.fail(...))`. Спонтанная смерть транспорта вообще не долетает до `connectionStateChanges`; `_connectionState` навсегда зависает в `ClientConnectionReady`.

При этом `StdioAcpTransport._handleProcessExit` (`stdio_acp_transport.dart:223-234`) уже корректно отличает намеренное закрытие (`_isClosed` guard) от неожиданного и эмитит `AcpTransportEvent.failure(AcpTransportException(code: AcpTransportErrorCode.disconnected, ...))` — то есть сигнал уже есть, просто он никуда не транслируется дальше `application.protocol` диагностики. `ConnectionFailureReason` (домен) уже содержит неиспользуемые причины `disconnected`/`closed`/`unknown`, как будто заведённые именно под этот случай.

## What Changes

- `AcpClientApplication._handleTransportEvent` при `AcpTransportFailure` дополнительно вызывает `_transitionConnection(ConnectionStateEvent.fail(...))` с причиной, смэппленной из `AcpTransportErrorCode` — но только если соединение ещё не `disconnected` (тот же guard, что уже используется в `_establishConnection` перед намеренным disconnect), чтобы не пытаться выполнить недопустимый по reducer'у переход `disconnected → failed`. Existing generation-based фильтрация в `_bindTransport` (`boundGeneration != _generation`) уже гарантирует, что событие от старого, заменённого during reconnect транспорта никогда сюда не долетит — новый код ничего не меняет в этом механизме, только использует его.
- `CodeLabShellCubit` подписывается на `_application.connectionStateChanges` (наравне с уже существующими `sessionChanges`/`diagnosticChanges`). При получении `ClientConnectionFailed` реагирует **только если** `state.connectionStatus == AcpConnectionStatus.connected` — то есть только на подлинно спонтанную потерю, а не на неудачу explicit `connect()`/`reconnect()`, которые уже полностью сами управляют `connectionStatus` в своих catch-блоках и не должны получать дублирующую/конфликтующую реакцию от этого нового подписчика.
- При подтверждённой спонтанной потере: `connectionStatus` → `failed`; очищаются все поля, которые описывают состояние *активного, теперь недостоверного* запроса — `pendingApproval`, `isPromptSubmitting`, `canCancel`, `isRespondingToApproval`, `isRespondingToConfigOption` — по прямому требованию `docs/architecture/session-lifecycle.md` §51: нельзя показывать turn как всё ещё running без подтверждения, если resume не гарантирован. Пишется diagnostic-запись с понятной причиной.
- `transcriptEntries`/`agentCommands`/`configOptions`/список сессий **не очищаются** — это исторический, локально сохранённый контент (per session-lifecycle.md различие "local history" vs "live session trust"), пользователь может его увидеть и решить, что делать дальше (обычно — `Reconnect` и создать новую сессию, что уже естественным образом сбрасывает agentCommands/configOptions по уже существующей логике `_handleSessionChange`/`createSession`).
- Никакой auto-reconnect/retry-политики не вводится — она явно не утверждена нигде в проекте, и `docs/architecture/session-lifecycle.md` §35-37 прямо запрещает придумывать retry-policy ad hoc в feature-коде. Пользователь видит честное `Failed` и нажимает уже существующую кнопку `Reconnect` сам.

## Capabilities

### New Capabilities

_(нет)_

### Modified Capabilities

- `acp-protocol-client`: добавляется требование о трансляции неожиданного отказа транспорта в `ClientConnectionState.failed` — ранее спека вообще не описывала это поведение (сам факт наличия `ConnectionFailureReason.disconnected/closed/unknown` без единого места использования — прямое свидетельство пробела).
- `agent-workbench-ui`: добавляется требование о том, что workbench обязан честно отражать спонтанную потерю соединения (не показывать `Connected`/`running` бесконечно) и очищать состояние активного запроса, которое больше не может считаться достоверным.

## Impact

- `packages/dart/acp_client_core/lib/src/application/acp_client_application.dart` — `_handleTransportEvent`, новый private helper для маппинга `AcpTransportErrorCode` → `ConnectionFailureReason`.
- `packages/dart/acp_client_core/test/` — тест: `AcpTransportFailure` на `ready`-соединении транслируется в `ClientConnectionFailed`; тест, что уже-`disconnected` соединение не пытается выполнить недопустимый переход; тест на generation-фильтрацию (событие от заменённого транспорта не должно влиять на текущее соединение — race, явно требуемый `concurrency.md` §68).
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — подписка на `connectionStateChanges`, новый обработчик, очистка перечисленных полей state.
- `apps/codelab_app/test/widget_test.dart` — тест, повторяющий сегодняшний ручной сценарий: connect → session → prompt running → транспорт падает → `connectionStatus == failed`, `canCancel == false`, `isPromptSubmitting == false`, `pendingApproval == null`, `transcriptEntries` не пусты (сохранены); тест-регрессия, что explicit `connect()`-failure (например, пустая команда) не получает вторую, дублирующую diagnostic-запись от нового обработчика.
