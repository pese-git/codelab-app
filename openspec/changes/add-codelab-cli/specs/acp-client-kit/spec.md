## MODIFIED Requirements

### Requirement: Публикация представлений сессии
`SessionHandle.view` SHALL публиковать неизменяемый `SessionView` с растущим `revision` синхронно: одно изменение сессии в ядре клиента — одна публикация, и `SessionHandle.current` уже обновлён, когда другие подписчики `sessionChanges` получают это изменение. `SessionView.status` активной сессии `running` (в том числе с ожидающими одобрениями) или `cancelling` SHALL означать «сессия занята»; `SessionView.configOptionInFlight` SHALL быть отличным от `null` на время запроса `session/set_config_option`, и повторный `SessionHandle.setConfigOption` в это время SHALL быть no-op. `SessionView.plan` SHALL содержать записи последнего обновления `plan` сессии (`PlanEntryView`: содержание, статус, приоритет) в порядке агента, а до первого обновления — пустой список; каждое обновление `plan` SHALL заменять план целиком.

#### Scenario: Флаги фасада совпадают с прежними
- **WHEN** ход идёт и ждёт одобрения
- **THEN** `CodeLabShellState.isPromptSubmitting` и `canCancel` равны `true`, а после `stopReason` оба `false`, как до переноса

#### Scenario: Повторная опция в полёте
- **WHEN** `setConfigOption` вызывается второй раз до ответа на первый
- **THEN** второй запрос не отправляется

#### Scenario: План заменяется целиком
- **WHEN** агент присылает `plan` из трёх записей, затем `plan` из двух
- **THEN** `SessionView.plan` сначала содержит три записи, затем ровно две записи второго обновления

### Requirement: Одобрения привязаны к вызову
`SessionView.pendingApprovals` SHALL содержать запросы `session/request_permission` с `toolCallId`, заголовком, видом, сырыми аргументами и вариантами ответа по `kind`. `PendingApprovalView.critical` SHALL быть `true` только тогда, когда запрос несёт `_meta.codelab.critical: true`. `SessionHandle.respond` SHALL отправлять выбранный `optionId` только в запрос этой сессии; ответ в одной сессии НЕ SHALL менять одобрения другой.

#### Scenario: Ответ в фоновой сессии
- **WHEN** у сессий A и B ожидают одобрения, и пользователь отвечает в B
- **THEN** одобрение A остаётся ожидающим

#### Scenario: Критичный запрос
- **WHEN** агент присылает `session/request_permission` с `_meta: {"codelab": {"critical": true}}`
- **THEN** у соответствующего `PendingApprovalView` `critical == true`, у запроса без этого поля — `false`

### Requirement: Профили и резолверы транспорта
`ConnectionProfile` SHALL быть закрытой иерархией `StdioProfile` и `WebSocketProfile`; токен WebSocket в профиле SHALL храниться ссылкой, а не значением; значение SHALL давать порт `SecretSource`. Превращение профиля в `AcpTransport` SHALL выполнять `TransportResolver`, который регистрирует composition root; kit НЕ SHALL открывать процессы и сокеты сам. `ConfigTransportResolver` kit SHALL переводить профиль в конфигурацию транспорта `codelab_acp_transports` и вызывать фабрику, которую передал хост. `parseShellWords` SHALL делить строку команды как POSIX shell без подстановок: пробелы вне кавычек разделяют слова, одинарные кавычки сохраняют текст буквально, двойные кавычки сохраняют текст с экранированием `\"` и `\\`, обратная косая вне кавычек экранирует следующий символ; незакрытая кавычка SHALL давать `FormatException`.

#### Scenario: Профиль без резолвера
- **WHEN** `connect` вызывается с профилем, для которого не зарегистрирован резолвер
- **THEN** `WorkspaceState.connection` становится `ConnectionFailed` с сообщением о неподдерживаемом профиле, транспорт не открывается

#### Scenario: Кавычки в команде
- **WHEN** `parseShellWords('python -m "codelab agent" --name \'a b\' x\\ y')`
- **THEN** результат — `python`, `-m`, `codelab agent`, `--name`, `a b`, `x y`

#### Scenario: Незакрытая кавычка
- **WHEN** `parseShellWords('run "oops')`
- **THEN** бросается `FormatException`

### Requirement: IO-адаптеры клиента
`dart:io`-реализации портов клиента SHALL жить в `packages/dart/codelab_client_io`: `IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider`, `ioTransportResolver` — `ConfigTransportResolver` kit с настоящими транспортами stdio и WebSocket, `JsonFileProfileStore` (`~/.codelab/profiles.json`) и `JsonFileRecentProjectsStore`. Реализации на Flutter-плагинах (`SharedPreferencesRecentProjectsStore`, `FileSelectorProjectFolderPicker`) SHALL оставаться в app. `ProfileStore.remove(id)` SHALL удалять профиль с этим `id` и возвращать `true`, а без такого профиля — возвращать `false` и не менять файл.

#### Scenario: Профили сохраняются в JSON
- **WHEN** `JsonFileProfileStore` сохраняет профиль `WebSocketProfile` и читает его заново
- **THEN** профиль восстановлен полностью, а файл не содержит значения токена

#### Scenario: Удаление профиля
- **WHEN** в `JsonFileProfileStore` сохранены профили `remote` и `local`, и вызывается `remove('remote')`
- **THEN** результат — `true`, а новое хранилище на том же файле читает только `local`
