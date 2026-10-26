## ADDED Requirements

### Requirement: Общий клиентский слой без UI
Логика клиента ACP — подключение, сессии, очередь промптов, проекция транскрипта, одобрения, опции конфигурации, команды, инспектор и диагностика — SHALL жить в пакете `packages/dart/acp_client_kit` на чистом Dart, а не в Flutter-приложении. Публичный API SHALL экспортироваться через `lib/acp_client_kit.dart`: `ClientWorkspace`, `SessionHandle`, `WorkspaceState`, `SessionView`, `ConnectionView`, `TranscriptItem`, `PromptQueue`, `ConnectionProfile`, `TransportResolver`, `SecretSource`, `AgentCommandView`, `ConfigOptionView`, `InspectorProjection`, `WorkspaceDiagnostic`, `describeFailure`. Источник данных kit SHALL быть портом `AgentBackend`; реализация `AcpClientBackend` SHALL работать поверх `AcpClientApplication` из `acp_client_core`. В коде kit НЕ SHALL быть членов, помеченных в плане как «после MVP», и заглушек для них.

#### Scenario: Kit используется без Flutter
- **WHEN** Dart-программа без Flutter создаёт `ClientWorkspace` с `AcpClientBackend` и тестовым резолвером на `FakeAcpTransport`
- **THEN** она подключается, создаёт сессию, отправляет промпт и получает `SessionView` с ответом агента в транскрипте

#### Scenario: Приложение работает через kit
- **WHEN** `CodeLabShellCubit` разрешается из графа cherrypick app
- **THEN** он получает `ClientWorkspace`, а не use case-ы `acp_client_core`, и его публичная поверхность остаётся прежней

### Requirement: Явный автомат соединения
Состояние соединения в kit SHALL быть закрытой иерархией `ConnectionView` — `Disconnected`, `Connecting`, `Connected`, `Reconnecting`, `ConnectionFailed` с причиной и сообщением — а не набором булевых флагов. Переподключение SHALL повторять поведение app до переноса: одна попытка с транспортом текущего профиля без `session/load`. Поздние события соединения старого поколения (`AcpClientApplication.generation`) НЕ SHALL менять `WorkspaceState`.

#### Scenario: Сбой транспорта
- **WHEN** транспорт подключённого соединения закрывается неожиданно
- **THEN** `WorkspaceState.connection` становится `ConnectionFailed`, сообщение диагностики не содержит секретов

#### Scenario: Позднее событие старого соединения
- **WHEN** после `reconnect()` приходит `session/update` от транспорта прежнего поколения
- **THEN** ни `WorkspaceState`, ни `SessionView` не меняются

### Requirement: Инкрементальная проекция транскрипта
`TranscriptProjector` SHALL строить `TranscriptItem` сессии инкрементально по новым `session/update`: дельты `agent_message_chunk` и `agent_thought_chunk` подряд дописываются в один элемент того же вида, любое другое обновление закрывает отрезок; `tool_call` с известным `toolCallId` обновляет существующий элемент, а не добавляет второй; статус и одобрение вызова берутся из read-модели хода ядра клиента; запрос разрешения привязывается к `ToolCallItem` по `toolCallId`, а для вызова без `tool_call` — к элементу вызова в конце хода; сорвавшийся ход добавляет `NoticeItem` вида `error`, завершённый ход без вывода агента — `NoticeItem` вида `emptyTurn`. Повторно обработанный снимок сессии SHALL быть no-op. Для любой последовательности обновлений результат инкрементальной проекции SHALL совпадать с проекцией с нуля по всем ходам сессии.

#### Scenario: Свойство на корпусе фикстур
- **WHEN** выполняется `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture`
- **THEN** для каждой фикстуры корпуса с ролью `client` на каждом шаге инкрементальная проекция равна проекции с нуля

#### Scenario: Повторная доставка tool_call
- **WHEN** агент дважды присылает `tool_call` с одним `toolCallId`
- **THEN** транскрипт содержит один `ToolCallItem` на прежней позиции с полями второго кадра

### Requirement: Публикация представлений сессии
`SessionHandle.view` SHALL публиковать неизменяемый `SessionView` с растущим `revision` синхронно: одно изменение сессии в ядре клиента — одна публикация, и `SessionHandle.current` уже обновлён, когда другие подписчики `sessionChanges` получают это изменение. `SessionView.status` активной сессии `running` (в том числе с ожидающими одобрениями) или `cancelling` SHALL означать «сессия занята»; `SessionView.configOptionInFlight` SHALL быть отличным от `null` на время запроса `session/set_config_option`, и повторный `SessionHandle.setConfigOption` в это время SHALL быть no-op.

#### Scenario: Флаги фасада совпадают с прежними
- **WHEN** ход идёт и ждёт одобрения
- **THEN** `CodeLabShellState.isPromptSubmitting` и `canCancel` равны `true`, а после `stopReason` оба `false`, как до переноса

#### Scenario: Повторная опция в полёте
- **WHEN** `setConfigOption` вызывается второй раз до ответа на первый
- **THEN** второй запрос не отправляется

### Requirement: Очередь промптов на сессию
Каждая сессия SHALL иметь свою `PromptQueue`. `SessionHandle.send` SHALL отправлять `session/prompt` сразу, если сессия свободна, и ставить промпт в очередь, если она занята; после конца хода первый элемент очереди SHALL уходить автоматически, пока очередь не опустеет. `remove`, `sendNow` (отправка элемента вне очереди; в занятой сессии — no-op) и `clear` SHALL работать по стабильному id элемента; id НЕ SHALL переиспользоваться в пределах `ClientWorkspace`. Исход каждого хода, в том числе промпта из очереди, SHALL публиковаться в `ClientWorkspace.promptOutcomes`. Очередь НЕ SHALL сохраняться и отправляться агенту иначе как промптом.

#### Scenario: Промпт из очереди после конца хода
- **WHEN** во время хода в очередь добавлен промпт, а затем ход завершился
- **THEN** выполняется `prompt_queue_test.dart: queued prompt is sent after the turn ends` — промпт уходит одним `session/prompt`, очередь пуста

#### Scenario: Очереди сессий независимы
- **WHEN** в очередь сессии A добавлен промпт, а активна сессия B
- **THEN** очередь B пуста, и промпт A уходит только по концу хода A

### Requirement: Одобрения привязаны к вызову
`SessionView.pendingApprovals` SHALL содержать запросы `session/request_permission` с `toolCallId`, заголовком, видом, сырыми аргументами и вариантами ответа по `kind`. `SessionHandle.respond` SHALL отправлять выбранный `optionId` только в запрос этой сессии; ответ в одной сессии НЕ SHALL менять одобрения другой.

#### Scenario: Ответ в фоновой сессии
- **WHEN** у сессий A и B ожидают одобрения, и пользователь отвечает в B
- **THEN** одобрение A остаётся ожидающим

### Requirement: Диагностика без секретов
`ClientWorkspace.diagnostics` SHALL публиковать `WorkspaceDiagnostic` о событиях kit — исходе хода, отмене, ответе на одобрение, опции конфигурации, неожиданной потере соединения — только после редакции секретов `SecretRedactor`; `describeFailure` SHALL давать текст ошибки для UI и CLI без токенов и ключей.

#### Scenario: Токен в тексте ошибки
- **WHEN** транспорт установленного соединения падает с сообщением, содержащим токен
- **THEN** опубликованная диагностика `Connection to ACP agent lost` содержит маску вместо токена

#### Scenario: Сбой явного подключения не дублируется
- **WHEN** `connect` завершается ошибкой транспорта
- **THEN** диагностика потери соединения не публикуется

### Requirement: Профили и резолверы транспорта
`ConnectionProfile` SHALL быть закрытой иерархией `StdioProfile` и `WebSocketProfile`; токен WebSocket в профиле SHALL храниться ссылкой, а не значением; значение SHALL давать порт `SecretSource`. Превращение профиля в `AcpTransport` SHALL выполнять `TransportResolver`, который регистрирует composition root; kit НЕ SHALL открывать процессы и сокеты сам. `ConfigTransportResolver` kit SHALL переводить профиль в конфигурацию транспорта `acp_transports` и вызывать фабрику, которую передал хост.

#### Scenario: Профиль без резолвера
- **WHEN** `connect` вызывается с профилем, для которого не зарегистрирован резолвер
- **THEN** `WorkspaceState.connection` становится `ConnectionFailed` с сообщением о неподдерживаемом профиле, транспорт не открывается

### Requirement: IO-адаптеры клиента
`dart:io`-реализации портов клиента SHALL жить в `packages/dart/acp_client_io`: `IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider`, `ioTransportResolver` — `ConfigTransportResolver` kit с настоящими транспортами stdio и WebSocket, `JsonFileProfileStore` (`~/.codelab/profiles.json`) и `JsonFileRecentProjectsStore`. Реализации на Flutter-плагинах (`SharedPreferencesRecentProjectsStore`, `FileSelectorProjectFolderPicker`) SHALL оставаться в app.

#### Scenario: Профили сохраняются в JSON
- **WHEN** `JsonFileProfileStore` сохраняет профиль `WebSocketProfile` и читает его заново
- **THEN** профиль восстановлен полностью, а файл не содержит значения токена
