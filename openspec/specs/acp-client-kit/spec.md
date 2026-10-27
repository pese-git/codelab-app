# acp-client-kit Specification

## Purpose

Общий клиентский слой ACP без UI — пакет `codelab_client_core` на чистом web-безопасном Dart и его `dart:io`-адаптеры `codelab_client_io`: рабочее пространство и явный автомат соединения, профили и резолверы транспорта без секретов в профилях, сессии с инкрементальной проекцией транскрипта, очередь промптов, одобрения, опции и команды агента, инспектор и диагностика без секретов. Владелец клиентского состояния для `codelab_desktop` и `codelab_cli`; хосты только отображают `WorkspaceState` и `SessionView`.
## Requirements
### Requirement: Общий клиентский слой без UI
Логика клиента ACP — подключение, сессии, очередь промптов, проекция транскрипта, одобрения, опции конфигурации, команды, инспектор и диагностика — SHALL жить в пакете `packages/dart/codelab_client_core` на чистом Dart, а не в Flutter-приложении. Публичный API SHALL экспортироваться через `lib/codelab_client_core.dart`: `ClientWorkspace`, `SessionHandle`, `WorkspaceState`, `SessionView`, `ConnectionView`, `TranscriptItem`, `PromptQueue`, `ConnectionProfile`, `TransportResolver`, `SecretSource`, `AgentCommandView`, `ConfigOptionView`, `InspectorProjection`, `WorkspaceDiagnostic`, `describeFailure`. Источник данных kit SHALL быть портом `AgentBackend`; реализация `AcpClientBackend` SHALL работать поверх `AcpClientApplication` из `codelab_client_acp`. В коде kit НЕ SHALL быть членов, помеченных в плане как «после MVP», и заглушек для них.

#### Scenario: Kit используется без Flutter
- **WHEN** Dart-программа без Flutter создаёт `ClientWorkspace` с `AcpClientBackend` и тестовым резолвером на `FakeAcpTransport`
- **THEN** она подключается, создаёт сессию, отправляет промпт и получает `SessionView` с ответом агента в транскрипте

#### Scenario: Приложение работает через kit
- **WHEN** `CodeLabShellCubit` разрешается из графа cherrypick app
- **THEN** он получает `ClientWorkspace`, а не use case-ы `codelab_client_acp`, и его публичная поверхность остаётся прежней

### Requirement: Явный автомат соединения
Состояние соединения в kit SHALL быть закрытой иерархией `ConnectionView` — `Disconnected`, `Connecting`, `Connected`, `Reconnecting`, `ConnectionLost` и `ConnectionFailed` с причиной и сообщением — а не набором булевых флагов. `ConnectionLost` SHALL означать, что установленное соединение оборвалось без вызова `connect()` или `reconnect()`; `ConnectionFailed` SHALL означать, что не удалась попытка `connect()` или `reconnect()`. `reconnect()` SHALL быть доступен из обоих состояний. Переподключение SHALL быть одной попыткой с транспортом текущего профиля, без повторов; после успешного переподключения kit SHALL загружать открытые сессии заново (требование «Сессии после переподключения»). Поздние события соединения старого поколения (`AcpClientApplication.generation`) НЕ SHALL менять `WorkspaceState`.

#### Scenario: Сбой транспорта
- **WHEN** транспорт подключённого соединения закрывается неожиданно
- **THEN** `WorkspaceState.connection` становится `ConnectionLost`, сообщение диагностики не содержит секретов

#### Scenario: Неудачное подключение не считается потерей
- **WHEN** `connect()` не может открыть транспорт
- **THEN** `WorkspaceState.connection` становится `ConnectionFailed`, а не `ConnectionLost`

#### Scenario: Переподключение после потери
- **WHEN** `WorkspaceState.connection` — `ConnectionLost`, и вызывается `reconnect()`, который успешно открывает транспорт
- **THEN** соединение проходит `Reconnecting` с `attempt: 1` и становится `Connected`

#### Scenario: Позднее событие старого соединения
- **WHEN** после `reconnect()` приходит `session/update` от транспорта прежнего поколения
- **THEN** ни `WorkspaceState`, ни `SessionView` не меняются

#### Scenario: Неудачное переподключение не повторяется
- **WHEN** `reconnect()` не может открыть транспорт
- **THEN** `WorkspaceState.connection` становится `ConnectionFailed` после одной попытки, а `Reconnecting` за время вызова имел `attempt: 1`

### Requirement: Инкрементальная проекция транскрипта
`TranscriptProjector` SHALL строить `TranscriptItem` сессии инкрементально по новым `session/update`: дельты `agent_message_chunk` и `agent_thought_chunk` подряд дописываются в один элемент того же вида, любое другое обновление закрывает отрезок; `tool_call` с известным `toolCallId` обновляет существующий элемент, а не добавляет второй; статус и одобрение вызова берутся из read-модели хода ядра клиента; запрос разрешения привязывается к `ToolCallItem` по `toolCallId`, а для вызова без `tool_call` — к элементу вызова в конце хода; сорвавшийся ход добавляет `NoticeItem` вида `error` с типизированным сбоем хода (`PromptFailure`), завершённый ход без вывода агента — `NoticeItem` вида `emptyTurn`. Повторно обработанный снимок сессии SHALL быть no-op. Для любой последовательности обновлений результат инкрементальной проекции SHALL совпадать с проекцией с нуля по всем ходам сессии.

#### Scenario: Свойство на корпусе фикстур
- **WHEN** выполняется `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture`
- **THEN** для каждой фикстуры корпуса с ролью `client` на каждом шаге инкрементальная проекция равна проекции с нуля

#### Scenario: Повторная доставка tool_call
- **WHEN** агент дважды присылает `tool_call` с одним `toolCallId`
- **THEN** транскрипт содержит один `ToolCallItem` на прежней позиции с полями второго кадра

#### Scenario: Заметка о сбое несёт причину агента
- **WHEN** ход срывается ответом агента, как в фикстуре `acp/prompt-failed-provider-auth`
- **THEN** `NoticeItem` вида `error` этого хода несёт `PromptFailure.agent` с `errorClass: "auth"`, сообщением агента и `retryable: false`

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
`ConnectionProfile` SHALL быть закрытой иерархией `StdioProfile` и `WebSocketProfile`; токен WebSocket в профиле SHALL храниться ссылкой, а не значением; значение SHALL давать порт `SecretSource`. Превращение профиля в `AcpTransport` SHALL выполнять `TransportResolver`, который регистрирует composition root; kit НЕ SHALL открывать процессы и сокеты сам. `ConfigTransportResolver` kit SHALL переводить профиль в конфигурацию транспорта `codelab_acp_transports` и вызывать фабрику, которую передал хост.

#### Scenario: Профиль без резолвера
- **WHEN** `connect` вызывается с профилем, для которого не зарегистрирован резолвер
- **THEN** `WorkspaceState.connection` становится `ConnectionFailed` с сообщением о неподдерживаемом профиле, транспорт не открывается

### Requirement: IO-адаптеры клиента
`dart:io`-реализации портов клиента SHALL жить в `packages/dart/codelab_client_io`: `IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider`, `ioTransportResolver` — `ConfigTransportResolver` kit с настоящими транспортами stdio и WebSocket, `JsonFileProfileStore` (`~/.codelab/profiles.json`) и `JsonFileRecentProjectsStore`. Реализации на Flutter-плагинах (`SharedPreferencesRecentProjectsStore`, `FileSelectorProjectFolderPicker`) SHALL оставаться в app.

#### Scenario: Профили сохраняются в JSON
- **WHEN** `JsonFileProfileStore` сохраняет профиль `WebSocketProfile` и читает его заново
- **THEN** профиль восстановлен полностью, а файл не содержит значения токена

### Requirement: Список и загрузка сессий проекта
`WorkspaceState.sessions` SHALL быть списком сессий проекта: сначала сессии, открытые в этом запуске, затем ещё не открытые сессии агента из `session/list` в порядке агента; сессия SHALL входить в список один раз. После каждого успешного `connect` и `reconnect` kit SHALL запрашивать первую страницу `session/list` с `cwd` проекта, если агент объявил `sessionCapabilities.list`. Неоткрытая сессия SHALL иметь статус `notLoaded`, заголовок и время изменения из ответа агента. `WorkspaceState.hasMoreSessions` SHALL показывать наличие следующей страницы; `ClientWorkspace.loadMoreSessions()` SHALL запрашивать её, а курсор kit НЕ SHALL отдавать хостам. `ClientWorkspace.loadSession(id, cwd)` SHALL открывать сессию через `session/load` и строить её транскрипт из реплея с нуля; повторный вызов для той же сессии во время загрузки SHALL не отправлять второй `session/load`. Без `loadSession` у агента `loadSession` SHALL завершаться ошибкой рабочего пространства без запроса к агенту.

#### Scenario: Сайдбар после подключения
- **WHEN** агент объявил `sessionCapabilities.list` и в его журнале две сессии проекта
- **THEN** после `connect()` `WorkspaceState.sessions` содержит обе со статусом `notLoaded` и их заголовками

#### Scenario: Открытая сессия не дублируется
- **WHEN** сессия, созданная в этом запуске, есть и в ответе `session/list`
- **THEN** в `WorkspaceState.sessions` она одна, со статусом открытой сессии

#### Scenario: Подгрузка следующей страницы
- **WHEN** ответ `session/list` содержит `nextCursor`, и хост вызывает `loadMoreSessions()`
- **THEN** kit отправляет `session/list` с этим курсором и добавляет новые сессии в конец списка; после страницы без `nextCursor` `hasMoreSessions` — `false`

#### Scenario: Загрузка сессии из списка
- **WHEN** хост вызывает `loadSession` для сессии `notLoaded`, и агент повторяет историю до ответа на `session/load`
- **THEN** у сессии появляется `SessionHandle`, её `SessionView.transcript` содержит повторённые реплики пользователя и ответы агента, а статус в `WorkspaceState.sessions` — `idle`

#### Scenario: Ошибка загрузки
- **WHEN** агент отвечает на `session/load` ошибкой
- **THEN** сессия остаётся `notLoaded`, `SessionHandle` не создаётся, а диагностика содержит причину без секретов

### Requirement: Сессии после переподключения
После успешного `reconnect()` kit SHALL загружать каждую открытую сессию через `session/load`, начиная с активной, если агент объявил `loadSession`; транскрипт загруженной сессии SHALL строиться из реплея заново, а не дополняться. Если агент не объявил `loadSession` или `session/load` открытой сессии завершился ошибкой, сессия SHALL получать статус `detached`, а в её транскрипт SHALL добавляться уведомление о потере связи. `detached` сессия НЕ SHALL отправлять промпты агенту — `send()` SHALL завершаться исходом `PromptFailed` — и НЕ SHALL сливать свою очередь.

#### Scenario: Переподключение к агенту с loadSession
- **WHEN** открыты две сессии, и `reconnect()` подключается к агенту с `loadSession`
- **THEN** kit отправляет `session/load` сначала для активной сессии, затем для второй, и транскрипт каждой совпадает с реплеем агента

#### Scenario: Агент без loadSession
- **WHEN** `reconnect()` подключается к агенту без `loadSession`
- **THEN** каждая открытая сессия получает статус `detached` и уведомление `The agent cannot restore sessions after reconnecting.`, а промпт в неё завершается `PromptFailed` без запроса к агенту

### Requirement: Восстановление после перезапуска
Kit SHALL сохранять снимок рабочего пространства через порт `WorkspaceSnapshotStore`: версия формата, проект, активная сессия и открытые сессии (`id`, `cwd`). Снимок НЕ SHALL содержать курсоры `session/list`, транскрипты, очереди промптов, профили и секреты. Запись SHALL выполняться после успешных создания, загрузки и активации сессии и смены проекта; записи НЕ SHALL накладываться — изменения во время записи SHALL склеиваться в одну следующую запись с последним снимком, а закрытие рабочего пространства SHALL дожидаться последней записи; ошибка записи SHALL быть диагностикой, а не отказом операции. До чтения снимка при старте хоста kit НЕ SHALL писать снимок. При старте хоста kit SHALL читать снимок и отдавать проект хосту; битый снимок или неизвестная версия SHALL удаляться с диагностикой. При первом успешном подключении в запуске kit SHALL восстанавливать сессии: сессии снимка SHALL появляться в списке, активная сессия SHALL загружаться через `session/load`, если агент объявил `loadSession`. Агент без `loadSession` или ошибка загрузки активной сессии SHALL приводить к `session/new` в проекте снимка с уведомлением в транскрипте новой сессии; при ошибке загрузки id SHALL удаляться из снимка. Восстановление НЕ SHALL отправлять промпты и ответы на одобрения.

#### Scenario: Перезапуск с агентом, умеющим загружать сессии
- **WHEN** снимок содержит активную сессию `sess_42`, и первое подключение после старта идёт к агенту с `loadSession`
- **THEN** kit загружает `sess_42` через `session/load`, делает её активной, а остальные сессии снимка показывает со статусом `notLoaded`

#### Scenario: Агент не знает сессию из снимка
- **WHEN** агент отвечает ошибкой на `session/load` активной сессии снимка
- **THEN** kit создаёт новую сессию в проекте снимка с уведомлением `Session <id> could not be restored; a new session was started.` и удаляет id из снимка

#### Scenario: Битый снимок
- **WHEN** снимок не разбирается или имеет неизвестную версию
- **THEN** kit записывает диагностику, удаляет снимок и стартует без восстановления

#### Scenario: Изменения во время записи склеиваются
- **WHEN** проект меняется дважды, пока предыдущая запись снимка ещё идёт
- **THEN** после неё выполняется ровно одна запись — с последним проектом

#### Scenario: Снимок без лишнего
- **WHEN** kit записывает снимок после загрузки сессии со списком, у которого есть `nextCursor`
- **THEN** в снимке нет курсора, транскрипта, очереди и секретов

### Requirement: Повтор сорвавшегося хода
`SessionHandle` SHALL предоставлять `retry()`, который отправляет `prompt` последнего хода сессии новым `session/prompt` по обычному пути отправки, не меняя и не удаляя прежние ходы. Сессия, чей последний ход сорвался, SHALL принимать новый ход. `SessionView.canRetry` SHALL быть истинным тогда и только тогда, когда выполнены все условия:

- последний ход сессии имеет статус `failed`;
- сбой не `connectionLost` и не сбой агента с `retryable: false`;
- сессия не занята и связана с агентом.

Вызов `retry()` при ложном `canRetry` SHALL отклоняться без отправки запроса.

#### Scenario: Повтор после сбоя сети
- **WHEN** последний ход сессии сорвался с `errorClass: "network"` и `retryable: true`, соединение `Connected`, и вызывается `retry()`
- **THEN** kit отправляет `session/prompt` с тем же `prompt`, сорвавшийся ход остаётся в транскрипте, а новый ход добавляется после него

#### Scenario: Повтор запрещён агентом
- **WHEN** последний ход сорвался с `retryable: false`
- **THEN** `SessionView.canRetry` ложно, и `retry()` не отправляет запрос

#### Scenario: Ход, прерванный потерей соединения, не повторяется
- **WHEN** ход сорвался из-за потери соединения
- **THEN** `SessionView.canRetry` ложно

#### Scenario: Занятая сессия не повторяет ход
- **WHEN** последний ход сорвался, а пользователь уже отправил следующий промпт, и сессия занята его ходом
- **THEN** `SessionView.canRetry` ложно

### Requirement: Каталог команд палитры
`codelab_client_core` SHALL предоставлять `CommandCatalog` — неизменяемое слияние команд хоста (`HostCommand`: id, имя, название, описание, доступность) и команд агента активной сессии (`SessionView.agentCommands`). Какие команды есть у хоста, SHALL решать хост; kit НЕ SHALL знать о командах конкретного хоста и об иконках. `CommandCatalog.commands` SHALL перечислять команды хоста в порядке хоста, затем команды агента в порядке `available_commands_update`. Недоступная команда хоста SHALL исключаться, если агент объявил команду с тем же именем (без `/`, с учётом регистра); доступная команда хоста и одноимённая команда агента SHALL оставаться обе. Повтор имени внутри списка агента SHALL давать одну команду — первую. `CommandCatalog.search(query)` SHALL снимать пробелы по краям и ведущий `/`, сравнивать без учёта регистра и для пустого запроса возвращать `commands`; иначе SHALL возвращать подходящие команды в порядке правил: префикс имени, подстрока имени, подпоследовательность имени, подстрока названия или описания; внутри правила — в порядке `commands`.

#### Scenario: Заглушка хоста уступает агенту
- **WHEN** хост передаёт недоступную `compact` и доступную `new`, а агент объявил `compact` и `new`
- **THEN** `commands` содержит `new` хоста, затем `compact` и `new` агента, без `compact` хоста

#### Scenario: Ранжирование поиска
- **WHEN** в каталоге команды агента `review` («Review the plan») и `plan`, и вызывается `search('pl')`
- **THEN** результат — `plan`, затем `review`

#### Scenario: Подпоследовательность имени
- **WHEN** в каталоге команда `compact`, и вызывается `search('/cpt')`
- **THEN** результат содержит `compact`

#### Scenario: Пустой запрос
- **WHEN** вызывается `search('/')`
- **THEN** результат совпадает с `commands`

