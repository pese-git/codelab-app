## 1. Domain/application (acp_client_core)

- [x] 1.1 Добавить private helper, маппящий `AcpTransportErrorCode` → `ConnectionFailureReason` (exhaustive switch, без `default`)
- [x] 1.2 В `AcpClientApplication._handleTransportEvent`, кейс `AcpTransportFailure`, добавить вызов `_transitionConnection(ConnectionStateEvent.fail(...))` с guard `if (_connectionState is! ClientConnectionDisconnected)`, сохранив существующий вызов `_recordDiagnostic(...)`
- [x] 1.3 Тест: `AcpTransportFailure` на `ready`-соединении переводит `connectionStateChanges` в `ClientConnectionFailed` с корректно смэппленной причиной
- [x] 1.4 Тест: `AcpTransportFailure`, пришедший когда соединение уже `disconnected`, не бросает исключение и не меняет состояние
- [x] 1.5 Тест: `AcpTransportFailure` от старого транспорта, отвязанного в рамках `reconnect()`/`_replaceTransport`, не влияет на состояние нового соединения (race из `concurrency.md` §68)

## 2. Приложение (codelab_app)

- [x] 2.1 Подписать `CodeLabShellCubit` на `_application.connectionStateChanges` в конструкторе, рядом с уже существующими подписками на `sessionChanges`/`diagnosticChanges`
- [x] 2.2 Реализовать обработчик: реагировать на `ClientConnectionFailed` только если `state.connectionStatus == AcpConnectionStatus.connected`; иначе игнорировать (explicit connect/reconnect сами управляют своим результатом)
- [x] 2.3 При срабатывании — emit: `connectionStatus: failed`, `pendingApproval: null`, `isPromptSubmitting: false`, `canCancel: false`, `isRespondingToApproval: false`, `isRespondingToConfigOption: false`; записать diagnostic severity error с причиной
- [x] 2.4 Не трогать `transcriptEntries`/`agentCommands`/`configOptions`/список сессий в этом обработчике

## 3. Тесты — codelab_app

- [x] 3.1 Тест: connect → создание сессии → submitPrompt (turn running) → эмулированный `AcpTransportFailure` от `FakeAcpTransport` → `connectionStatus == failed`, `canCancel == false`, `isPromptSubmitting == false`, `pendingApproval == null`
- [x] 3.2 Тест: `transcriptEntries`, накопленные до потери соединения, остаются в state после срабатывания обработчика (объединено с 3.1 в один тест)
- [x] 3.3 Регрессионный тест: explicit `connect()` с ошибкой (например, пустая stdio-команда) не создаёт вторую diagnostic-запись от обработчика потери соединения — ровно одна запись, как и до этого change
- [x] 3.4 Регрессионный тест: явный `reconnect()`, завершившийся неудачей, не получает конфликтующую реакцию от нового обработчика (та же гарантия, что и 3.3, для reconnect-флоу)

## 4. Проверка

- [x] 4.1 `fvm dart run melos run format`
- [x] 4.2 `fvm dart run melos run analyze`
- [x] 4.3 `fvm dart run melos run test`
