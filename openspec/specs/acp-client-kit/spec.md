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
Состояние соединения в kit SHALL быть закрытой иерархией `ConnectionView` — `Disconnected`, `Connecting`, `Connected`, `Reconnecting`, `ConnectionLost` и `ConnectionFailed` с причиной и сообщением — а не набором булевых флагов. `ConnectionLost` SHALL означать, что установленное соединение оборвалось без вызова `connect()` или `reconnect()`; `ConnectionFailed` SHALL означать, что не удалась попытка `connect()` или `reconnect()`. `reconnect()` SHALL быть доступен из обоих состояний. Переподключение SHALL быть одной попыткой с транспортом текущего профиля, без повторов; после успешного переподключения kit SHALL загружать открытые сессии заново (требование «Сессии после переподключения»). Поздние события соединения старого поколения (`AcpClientApplication.generation`) НЕ SHALL менять `WorkspaceState`. Повторный вызов `connect()` или `reconnect()` SHALL делать устаревшей любую ещё не завершённую попытку `connect()` или `reconnect()` того же `ClientWorkspace` (design.md change `add-embedded-agent-mode`, D6, «Устаревшая попытка в `ClientWorkspace`»). Исход устаревшей попытки — успех или ошибка — НЕ SHALL менять `WorkspaceState.connection` и возможности агента, НЕ SHALL возобновлять, перезагружать или отсоединять открытые сессии и НЕ SHALL запускать шаги после подключения (`session/list`, восстановление снимка); состоянием SHALL владеть последняя попытка. Правило SHALL действовать для профилей любого типа, публичный API `ClientWorkspace` оно не меняет.

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

#### Scenario: Повторный Connect во время подключения
- **WHEN** открыта сессия, `connect()` ждёт открытия транспорта резолвером, вызывается второй `connect()`, а затем первая попытка завершается ошибкой (например, резолвер встроенного агента отменил устаревший `open`)
- **THEN** `WorkspaceState.connection` между вызовами не становится `ConnectionFailed`: остаётся `Connecting` второй попытки до её исхода; сессия первой попыткой не возобновляется и не загружается

#### Scenario: Повторный Reconnect во время переподключения
- **WHEN** `reconnect()` ждёт открытия транспорта, вызывается второй `reconnect()`, и первая попытка завершается ошибкой
- **THEN** `WorkspaceState.connection` остаётся `Reconnecting` второй попытки до её исхода, без промежуточного `ConnectionFailed`, а сессии первой попыткой не возобновляются

#### Scenario: Поздний успех устаревшей попытки
- **WHEN** первая попытка `connect()` завершается успешно уже после старта второй попытки, которая ещё не завершилась
- **THEN** первая попытка не публикует `Connected` и возможности агента, не запрашивает `session/list` и не загружает сессии; `WorkspaceState` меняет только исход второй попытки

### Requirement: Инкрементальная проекция транскрипта
`TranscriptProjector` SHALL строить `TranscriptItem` сессии инкрементально по новым `session/update`: дельты `agent_message_chunk` и `agent_thought_chunk` подряд дописываются в один элемент того же вида, любое другое обновление закрывает отрезок; `tool_call` с известным `toolCallId` обновляет существующий элемент, а не добавляет второй; статус и одобрение вызова берутся из read-модели хода ядра клиента; запрос разрешения привязывается к `ToolCallItem` по `toolCallId`, а для вызова без `tool_call` — к элементу вызова в конце хода; сорвавшийся ход добавляет `NoticeItem` вида `error` с типизированным сбоем хода (`PromptFailure`), завершённый ход без вывода агента — `NoticeItem` вида `emptyTurn`; ход, завершённый с `stopReason` `max_tokens`, `max_turn_requests` или `refusal`, — `NoticeItem` вида `turnStopped` всегда, даже при выводе агента, и вместо `emptyTurn` у хода без вывода (решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q33, D27). Заметка `turnStopped` SHALL строиться только по `stopReason` ответа на `session/prompt`: у ходов реплея `session/load` его нет, и заметки у них нет (Q36). Тексты `turnStopped`: `max_tokens` — `The model reached its token limit, so the turn ended.`; `max_turn_requests` — `The turn reached the limit of model requests.`; `refusal` — `The agent refused to continue.`. Если итог хода `max_turn_requests` несёт причину бюджета (acp-protocol-client «Причина остановки по бюджету») со значением `steps`, `tokens`, `cost`, `duration` или `deadline`, заметка `turnStopped` SHALL называть лимит: `The turn stopped: budget exceeded: <limit>.`; без причины или с незнакомой причиной SHALL оставаться текст `The turn reached the limit of model requests.` (design.md change `add-usage-extension`, D10, D21 Т6). Повторно обработанный снимок сессии SHALL быть no-op. Для любой последовательности обновлений результат инкрементальной проекции SHALL совпадать с проекцией с нуля по всем ходам сессии.

#### Scenario: Свойство на корпусе фикстур
- **WHEN** выполняется `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture`
- **THEN** для каждой фикстуры корпуса с ролью `client` на каждом шаге инкрементальная проекция равна проекции с нуля

#### Scenario: Повторная доставка tool_call
- **WHEN** агент дважды присылает `tool_call` с одним `toolCallId`
- **THEN** транскрипт содержит один `ToolCallItem` на прежней позиции с полями второго кадра

#### Scenario: Заметка о сбое несёт причину агента
- **WHEN** ход срывается ответом агента, как в фикстуре `acp/prompt-failed-provider-auth`
- **THEN** `NoticeItem` вида `error` этого хода несёт `PromptFailure.agent` с `errorClass: "auth"`, сообщением агента и `retryable: false`

#### Scenario: Ход упёрся в лимит токенов после размышлений
- **WHEN** ход содержит только `agent_thought_chunk` и завершается ответом агента с `stopReason: max_tokens`
- **THEN** транскрипт хода содержит `ThoughtItem` и один `NoticeItem` вида `turnStopped` с текстом `The model reached its token limit, so the turn ended.`; `NoticeItem` вида `emptyTurn` нет

#### Scenario: Отказ агента после текста
- **WHEN** ход содержит `agent_message_chunk` и завершается с `stopReason: refusal`
- **THEN** после `AgentTextItem` хода есть `NoticeItem` вида `turnStopped` с текстом `The agent refused to continue.`; ход `end_turn` и `cancelled` такой заметки не получает

#### Scenario: Реплей session/load без заметки исхода
- **WHEN** сессия загружена через `session/load`, и в реплее истории есть ход, который при живом выполнении завершился с `stopReason: max_tokens` (реплей ACP не передаёт `stopReason`, `03-Session Setup.md`, «Loading a Session»), а после загрузки новый ход той же сессии завершается с `stopReason: max_tokens`
- **THEN** ход реплея не получает `NoticeItem` вида `turnStopped`, а новый ход получает; исход хода клиент не хранит и не восстанавливает (решение пользователя 2026-11-09, design.md change `add-provider-setup-ui`, Q36)

#### Scenario: Лимит стоимости
- **WHEN** ход завершён `max_turn_requests` с причиной `cost`
- **THEN** в ленте заметка `turnStopped` с текстом `The turn stopped: budget exceeded: cost.`

#### Scenario: Причина неизвестна
- **WHEN** ход завершён `max_turn_requests` без причины или с причиной `energy`
- **THEN** в ленте заметка `turnStopped` с текстом `The turn reached the limit of model requests.`

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

### Requirement: Очередь промптов на сессию
Каждая сессия SHALL иметь свою `PromptQueue`. `SessionHandle.send` SHALL отправлять `session/prompt` сразу, если сессия свободна, и ставить промпт в очередь, если она занята; после конца хода первый элемент очереди SHALL уходить автоматически, пока очередь не опустеет. `remove`, `sendNow` (отправка элемента вне очереди; в занятой сессии — no-op) и `clear` SHALL работать по стабильному id элемента; id НЕ SHALL переиспользоваться в пределах `ClientWorkspace`. Исход каждого хода, в том числе промпта из очереди, SHALL публиковаться в `ClientWorkspace.promptOutcomes`. Очередь НЕ SHALL сохраняться и отправляться агенту иначе как промптом.

#### Scenario: Промпт из очереди после конца хода
- **WHEN** во время хода в очередь добавлен промпт, а затем ход завершился
- **THEN** выполняется `prompt_queue_test.dart: queued prompt is sent after the turn ends` — промпт уходит одним `session/prompt`, очередь пуста

#### Scenario: Очереди сессий независимы
- **WHEN** в очередь сессии A добавлен промпт, а активна сессия B
- **THEN** очередь B пуста, и промпт A уходит только по концу хода A

### Requirement: Одобрения привязаны к вызову
`SessionView.pendingApprovals` SHALL содержать запросы `session/request_permission` с `toolCallId`, заголовком, видом, сырыми аргументами и вариантами ответа по `kind`. `PendingApprovalView.critical` SHALL быть `true` только тогда, когда `_meta.codelab.critical` запроса или его `toolCall` равно `true` (Dart-агент помечает так опасные команды в `toolCall`); другое значение или его отсутствие SHALL давать `false`. `SessionHandle.respond` SHALL отправлять выбранный `optionId` только в запрос этой сессии; ответ в одной сессии НЕ SHALL менять одобрения другой. Одобрение привязано и к соединению, в котором пришёл запрос: при замене транспорта (`reconnect`) и при неожиданной потере соединения kit SHALL снимать каждое ждущее одобрение каждой сессии — оно получает статус `cancelled`, уходит из `pendingApprovals` и карточки вызова, ход больше не ждёт одобрения, а в диагностику пишется предупреждение с id сессии, одобрения и вызова без сырых аргументов. Поздний `respond` по снятому одобрению SHALL завершаться ошибкой и НЕ SHALL отправлять ответ ни в одно соединение. Очередь промптов сессии при этом SHALL сохраняться. Запрос нового соединения SHALL обрабатываться как новый, даже если его JSON-RPC id совпал с id снятого (design.md change `require-project-folder`, «Затронутые пакеты», `codelab_client_acp`; D22).

#### Scenario: Ответ в фоновой сессии
- **WHEN** у сессий A и B ожидают одобрения, и пользователь отвечает в B
- **THEN** одобрение A остаётся ожидающим

#### Scenario: Критичный запрос
- **WHEN** агент присылает `session/request_permission` с `toolCall._meta: {"codelab": {"critical": true}}` или с `_meta: {"codelab": {"critical": true}}` у запроса
- **THEN** у соответствующего `PendingApprovalView` `critical == true`, у запроса без этого поля или со значением, отличным от `true`, — `false`

#### Scenario: Перезапуск снимает одобрение detached-сессии
- **WHEN** ход сессии `a1` с одним промптом в очереди ждёт одобрения, и `reconnect()` подключается к агенту без `loadSession`
- **THEN** `a1` — `detached`, её `pendingApprovals` пуст и карточки одобрения в транскрипте нет, промпт остаётся в очереди, а `respond` по прежнему id завершается ошибкой без ответа агенту

#### Scenario: Потеря соединения снимает одобрение
- **WHEN** ход ждёт одобрения, и транспорт установленного соединения неожиданно падает
- **THEN** `pendingApprovals` сессии пуст, а `respond` по прежнему id завершается ошибкой без отправки ответа

#### Scenario: Ответ во время замены транспорта
- **WHEN** ход ждёт одобрения, хост вызывает `reconnect()`, и до завершения замены транспорта пользователь отвечает на одобрение
- **THEN** одобрение снято, ответ не отправлен ни в старое, ни в новое соединение

#### Scenario: Запрос нового соединения с прежним id
- **WHEN** одобрение с JSON-RPC id `7` снято при `reconnect()`, и агент нового соединения присылает `session/request_permission` с id `7`
- **THEN** запрос виден в `pendingApprovals`, и ответ пользователя уходит в новое соединение ровно один раз

### Requirement: Диагностика без секретов
`ClientWorkspace.diagnostics` SHALL публиковать `WorkspaceDiagnostic` о событиях kit — исходе хода, отмене, ответе на одобрение, опции конфигурации, неожиданной потере соединения — только после редакции секретов `SecretRedactor`; `describeFailure` SHALL давать текст ошибки для UI и CLI без токенов и ключей.

#### Scenario: Токен в тексте ошибки
- **WHEN** транспорт установленного соединения падает с сообщением, содержащим токен
- **THEN** опубликованная диагностика `Connection to ACP agent lost` содержит маску вместо токена

#### Scenario: Сбой явного подключения не дублируется
- **WHEN** `connect` завершается ошибкой транспорта
- **THEN** диагностика потери соединения не публикуется

### Requirement: Профили и резолверы транспорта
`ConnectionProfile` SHALL быть закрытой иерархией `StdioProfile`, `WebSocketProfile` и `EmbeddedProfile`; токен WebSocket в профиле SHALL храниться ссылкой, а не значением; значение SHALL давать порт `SecretSource`. `EmbeddedProfile` SHALL нести только `id`, `label` и строку `hostProfile` (имя профиля хоста встроенного агента, например `embedded-cli`); типов ядра агента kit НЕ SHALL знать (design.md change `add-embedded-agent-mode`, D7). Превращение профиля в `AcpTransport` SHALL выполнять `TransportResolver`, который регистрирует composition root; kit НЕ SHALL открывать процессы и сокеты и НЕ SHALL собирать агента сам. `ConfigTransportResolver` kit SHALL переводить `StdioProfile` и `WebSocketProfile` в конфигурацию транспорта `codelab_acp_transports` и вызывать фабрику, которую передал хост; `EmbeddedProfile` он НЕ SHALL поддерживать. `JsonFileProfileStore` НЕ SHALL сохранять `EmbeddedProfile` (`ArgumentError`) и SHALL отвергать запись `"type": "embedded"` при чтении `FormatException`, как неизвестный тип. `parseShellWords` SHALL делить строку команды как POSIX shell без подстановок: пробелы вне кавычек разделяют слова, одинарные кавычки сохраняют текст буквально, двойные кавычки сохраняют текст с экранированием `\"` и `\\`, обратная косая вне кавычек экранирует следующий символ; незакрытая кавычка SHALL давать `FormatException`.

#### Scenario: Профиль без резолвера
- **WHEN** `connect` вызывается с профилем, для которого не зарегистрирован резолвер
- **THEN** `WorkspaceState.connection` становится `ConnectionFailed` с сообщением о неподдерживаемом профиле, транспорт не открывается

#### Scenario: Встроенный профиль без резолвера встроенного агента
- **WHEN** `ClientWorkspace` собран только с `ConfigTransportResolver`, и `connect` вызывается с `ConnectionProfile.embedded(id: 'embedded', label: 'Embedded agent', hostProfile: 'embedded-cli')`
- **THEN** `WorkspaceState.connection` становится `ConnectionFailed` с сообщением о неподдерживаемом профиле

#### Scenario: Встроенный профиль не сохраняется в profiles.json
- **WHEN** `JsonFileProfileStore.save` получает список с `EmbeddedProfile`, а затем отдельно `load` читает файл с записью `"type": "embedded"`
- **THEN** `save` бросает `ArgumentError` и файл не меняется; `load` бросает `FormatException`

#### Scenario: Кавычки в команде
- **WHEN** `parseShellWords('python -m "codelab agent" --name \'a b\' x\\ y')`
- **THEN** результат — `python`, `-m`, `codelab agent`, `--name`, `a b`, `x y`

#### Scenario: Незакрытая кавычка
- **WHEN** `parseShellWords('run "oops')`
- **THEN** бросается `FormatException`

### Requirement: IO-адаптеры клиента
`dart:io`-реализации портов клиента SHALL жить в `packages/dart/codelab_client_io`:
- `IoTextFileIo`;
- `IoTerminalProcessRunner`;
- `IoWorkingDirectoryProvider`;
- `ioTransportResolver` — `ConfigTransportResolver` kit с настоящими транспортами stdio и WebSocket;
- `JsonFileProfileStore` (`$CODELAB_HOME/profiles.json`, общий файл CLI и app);
- `JsonFileRecentProjectsStore`.

Реализации на Flutter-плагинах (`SharedPreferencesRecentProjectsStore`, `FileSelectorProjectFolderPicker`) SHALL оставаться в app. `ProfileStore.remove(id)` SHALL удалять профиль с этим `id` и возвращать `true`, а без такого профиля — возвращать `false` и не менять файл. `JsonFileProfileStore` SHALL записывать `profiles.json` через уникальный временный файл в том же каталоге, сброшенный на диск (`flush`) до атомарного переименования: прерванная запись НЕ SHALL оставлять под именем `profiles.json` пустой или неполный файл (design.md change `add-app-settings-shell`, D7). Классификатора ошибок проверки профиля (`classifyProbeFailure`) в пакете НЕ SHALL быть: проверка профиля удалена (design.md change `remove-test-connection`, D2).

#### Scenario: Профили сохраняются в JSON
- **WHEN** `JsonFileProfileStore` сохраняет профиль `WebSocketProfile` и читает его заново
- **THEN** профиль восстановлен полностью, а файл не содержит значения токена

#### Scenario: Удаление профиля
- **WHEN** в `JsonFileProfileStore` сохранены профили `remote` и `local`, и вызывается `remove('remote')`
- **THEN** результат — `true`, а новое хранилище на том же файле читает только `local`

#### Scenario: Барель без классификатора проверки
- **WHEN** код импортирует `package:codelab_client_io/codelab_client_io.dart`
- **THEN** `classifyProbeFailure` не экспортируется, а `ioTransportResolver`, `JsonFileProfileStore` и `JsonFileRecentProjectsStore` доступны

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
После успешного `reconnect()` kit SHALL загружать каждую открытую сессию через `session/load` с её собственным `cwd`, начиная с активной, если агент объявил `loadSession`. Транскрипт загруженной сессии SHALL строиться из реплея заново, а не дополняться. Если агент не объявил `loadSession` или `session/load` открытой сессии завершился ошибкой, сессия SHALL получать статус `detached`, а в её транскрипт SHALL добавляться уведомление о потере связи. `detached`-сессия НЕ SHALL отправлять промпты агенту — `send()` SHALL завершаться исходом `PromptFailed` — и НЕ SHALL сливать свою очередь. `loadSession` SHALL принимать и `detached`-сессию: после успешной загрузки она снова принимает промпты, а её очередь сливается по общим правилам (design.md change `require-project-folder`, D16).

#### Scenario: Переподключение к агенту с loadSession
- **WHEN** открыты две сессии, и `reconnect()` подключается к агенту с `loadSession`
- **THEN** kit отправляет `session/load` сначала для активной сессии, затем для второй, и транскрипт каждой совпадает с реплеем агента

#### Scenario: Агент без loadSession
- **WHEN** `reconnect()` подключается к агенту без `loadSession`
- **THEN** каждая открытая сессия получает статус `detached` и уведомление `The agent cannot restore sessions after reconnecting.`, а промпт в неё завершается `PromptFailed` без запроса к агенту

#### Scenario: Сессии разных папок
- **WHEN** открыты сессии с `cwd` `/work/a` и `/work/b`, и `reconnect()` подключается с корнем процесса `/work/a`
- **THEN** `session/load` отправлен для обеих сессий, каждой — с её `cwd`

#### Scenario: Загрузка detached-сессии
- **WHEN** сессия `a1` в состоянии `detached` с очередью из одного промпта, агент подключён и объявил `loadSession`, и хост вызывает `loadSession(a1, cwd: '/work/a')`
- **THEN** сессия загружена, её статус больше не `detached`, а промпт из очереди отправлен агенту после загрузки

### Requirement: Восстановление после перезапуска
Kit SHALL сохранять снимок рабочего пространства через порт `WorkspaceSnapshotStore`: версия формата, проект, активная сессия и открытые сессии (`id`, `cwd`). Снимок НЕ SHALL содержать курсоры `session/list`, транскрипты, очереди промптов, профили и секреты. Запись SHALL выполняться после успешных создания, загрузки и активации сессии и смены проекта; записи НЕ SHALL накладываться — изменения во время записи SHALL склеиваться в одну следующую запись с последним снимком, а закрытие рабочего пространства SHALL дожидаться последней записи; ошибка записи SHALL быть диагностикой, а не отказом операции. До чтения снимка при старте хоста kit НЕ SHALL писать снимок. При старте хоста kit SHALL читать снимок и отдавать проект хосту; битый снимок или неизвестная версия SHALL удаляться с диагностикой. При первом успешном подключении в запуске kit SHALL восстанавливать сессии, если проект с тех пор не сменён; выбор другого проекта до подключения SHALL отменять восстановление: сессии снимка SHALL появляться в списке, активная сессия SHALL загружаться через `session/load`, если агент объявил `loadSession` и её `cwd` равен проекту снимка (точное равенство записей). Активная сессия с другим `cwd` НЕ SHALL загружаться, активироваться и заменяться новой сессией: она остаётся строкой `notLoaded` и открывается только действием хоста (design.md change `require-project-folder`, D10). Агент без `loadSession` или ошибка загрузки активной сессии в папке проекта SHALL приводить к `session/new` в проекте снимка с уведомлением в транскрипте новой сессии; при ошибке загрузки id SHALL удаляться из снимка. Восстановление НЕ SHALL отправлять промпты и ответы на одобрения.

#### Scenario: Перезапуск с агентом, умеющим загружать сессии
- **WHEN** снимок содержит активную сессию `sess_42`, и первое подключение после старта идёт к агенту с `loadSession`
- **THEN** kit загружает `sess_42` через `session/load`, делает её активной, а остальные сессии снимка показывает со статусом `notLoaded`

#### Scenario: Агент не знает сессию из снимка
- **WHEN** агент отвечает ошибкой на `session/load` активной сессии снимка
- **THEN** kit создаёт новую сессию в проекте снимка с уведомлением `Session <id> could not be restored; a new session was started.` и удаляет id из снимка

#### Scenario: Проект сменён до первого подключения
- **WHEN** снимок указывает на проект `/work`, а хост до первого подключения выбрал другой проект — через `selectProject` или папкой в `connect`
- **THEN** kit не восстанавливает снимок: не добавляет его сессии в список, не шлёт `session/load` и `session/new`, а в следующую запись снимка попадает новый проект без сессий прошлого

#### Scenario: Битый снимок
- **WHEN** снимок не разбирается или имеет неизвестную версию
- **THEN** kit записывает диагностику, удаляет снимок и стартует без восстановления

#### Scenario: Изменения во время записи склеиваются
- **WHEN** проект меняется дважды, пока предыдущая запись снимка ещё идёт
- **THEN** после неё выполняется ровно одна запись — с последним проектом

#### Scenario: Снимок без лишнего
- **WHEN** kit записывает снимок после загрузки сессии со списком, у которого есть `nextCursor`
- **THEN** в снимке нет курсора, транскрипта, очереди и секретов

#### Scenario: Активная сессия снимка в другой папке
- **WHEN** снимок содержит проект `/work/app` и активную сессию `s1` с `cwd` `/`, и первое подключение в запуске идёт к агенту с `loadSession`
- **THEN** `session/load` и `session/new` для `s1` не отправлены, `s1` в списке со статусом `notLoaded`, активной сессии нет

#### Scenario: Активная сессия в другой папке у агента без loadSession
- **WHEN** снимок содержит проект `/work/app` и активную сессию `s1` с `cwd` `/`, и агент не объявил `loadSession`
- **THEN** новая сессия с уведомлением не создаётся

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

### Requirement: Строка инструмента без сырого JSON
`ToolCallView` SHALL нести `rawInput`, пути `locations` и текст текстовых элементов `content` вызова. `ToolRowFormatter.format` SHALL быть чистой функцией `ToolCallItem` и `cwd` сессии, возвращающей `ToolRowView` с меткой, деталью и необязательной второй строкой по `dart-agent-and-clients` §12.1.6, без поля времени.

Метка SHALL определяться видом вызова: `read` → `Read`, `edit` → `Edit`, `delete` → `Delete`, `move` → `Move`, `search` → `Search`, `execute` → `Run`, `fetch` → `Fetch`, `think` → `Think`, `switch_mode` → `Mode`, `other` → `title` вызова. Вызов, чей строковый `kind` клиент не знает, имеет вид `other` (требование «Неизвестный вид вызова инструмента» acp-protocol-client) и получает метку по `title`. У `switch_mode` нет своих полей `rawInput`: его деталь берётся общим правилом из `title` (design.md change `tolerate-unknown-tool-kind`, D7).

Деталь SHALL браться первым подходящим правилом §12.1.6 из скалярных полей `rawInput` или `locations` и никогда не из сериализации объекта; путь внутри `cwd` SHALL показываться относительно `cwd`; у `fetch` SHALL отбрасываться схема и query-строка; управляющие символы SHALL заменяться пробелом; значение SHALL проходить маскирование секретов и SHALL быть не длиннее 160 символов с `…`. Если деталь пуста или совпадает с меткой, а `title` отличается от метки, деталью SHALL становиться `title`.

Вторая строка SHALL быть первой непустой строкой первого текстового элемента у вызова в статусе `failed` и отсутствовать у остальных. Проекция с новыми полями SHALL сохранять равенство инкрементальной проекции и проекции с нуля (требование «Инкрементальная проекция транскрипта»).

#### Scenario: Команда из нескольких строк
- **WHEN** форматируется вызов `execute` с `rawInput.command` "npm test --\n  --watch=false"
- **THEN** `ToolRowView` — метка `Run`, деталь `npm test -- --watch=false`, второй строки нет

#### Scenario: Чтение диапазона внутри проекта
- **WHEN** форматируется вызов `read` с `rawInput` `{"path": "/work/app/lib/a.dart", "offset": 10, "limit": 20}` в сессии с `cwd` `/work/app`
- **THEN** метка `Read`, деталь `lib/a.dart:10-29`

#### Scenario: URL без query-строки
- **WHEN** форматируется вызов `fetch` с `rawInput.url` "https://example.com/docs?token=abc"
- **THEN** деталь `example.com/docs`, и строка `token=abc` не попадает в `ToolRowView`

#### Scenario: Инструмент без скалярных полей
- **WHEN** форматируется вызов `other` с `title` "mcp__db__stats" и `rawInput` `{"items": [1, 2]}`
- **THEN** метка `mcp__db__stats`, деталь пуста, JSON не показан

#### Scenario: Смена режима
- **WHEN** форматируется вызов `switch_mode` с `title` "Ready for implementation" и без `rawInput`
- **THEN** метка `Mode`, деталь `Ready for implementation`, слово `switch_mode` не показано

#### Scenario: Вызов незнакомого вида
- **WHEN** форматируется вызов, пришедший с `kind: "future_kind"` и `title` "Plan sync"
- **THEN** метка `Plan sync`, как у вида `other`, слово `future_kind` не показано

### Requirement: Черновик профиля подключения
`codelab_client_core` SHALL предоставлять `ProfileDraft` — неизменяемый черновик профиля stdio или WebSocket. Это одна логика для «Add connection profile» в app и для будущей формы CLI (`dart-agent-and-clients` §12.4.9; design.md change `add-app-settings-shell`, D11). У черновика две операции:
- `validate` возвращает типизированные проблемы по полям, а не исключения;
- `toProfile` строит `ConnectionProfile` только из черновика без проблем. Другого пути из черновика в профиль НЕ SHALL быть.

**id.**
- `suggestProfileId(label)` SHALL давать нижний регистр, в котором каждый символ вне `[a-z0-9]` заменён на `-`, повторы `-` схлопнуты, а `-` по краям удалены.
- Допустимость id SHALL проверять `isValidProfileId`: `^[a-z0-9][a-z0-9._-]{0,63}$`.
- Id из `reservedProfileIds = {embedded, default}` (`isReservedProfileId`) SHALL отклоняться как зарезервированные: оба — имена встроенного агента (design.md change `add-app-settings-shell`, D21). Этим же множеством SHALL пользоваться `codelab profiles add`.
- Id, совпадающий с существующим без учёта регистра, SHALL отклоняться как занятый.

**stdio.**
- Команда обязательна.
- Аргументы SHALL разбираться `parseShellWords`; незакрытая кавычка — проблема поля.
- Ключ `env`, который после перевода в верхний регистр равен `KEY`, `TOKEN`, `SECRET` или оканчивается на `_KEY`, `_TOKEN`, `_SECRET`, SHALL отклоняться (SETUP-19). Текст проблемы НЕ SHALL содержать значение.

**WebSocket.**
- URL SHALL иметь схему `ws` или `wss` и непустой хост.
- URL с userinfo (имя пользователя, с паролем или без) SHALL давать проблему `urlUserInfo` с текстом `Remove the user name and password from the URL; use the Token setting instead.`, и `toProfile` профиль НЕ SHALL строить: userinfo попал бы в `profiles.json` и ушёл бы на сервер заголовком Basic auth (design.md change `add-app-settings-shell`, D11). Текст проблемы НЕ SHALL содержать URL и userinfo.
- `ws://` к хосту вне `localhost`, `127.0.0.0/8` и `::1` SHALL давать предупреждение `plaintextToRemote`. Оно требует подтверждения, но не запрещает сохранение.
- Выбор токена — `NoToken`, `EnvToken(name)` с именем переменной по правилу `^[A-Za-z_][A-Za-z0-9_]*$` (профиль получает `tokenRef: env:<name>`) или `KeepTokenRef(ref)` для существующего профиля.

**Типы.** `profileKindsFor(resolvers)` SHALL возвращать только типы, которые поддерживает хотя бы один зарегистрированный `TransportResolver` (SETUP-22).

#### Scenario: id из имени
- **WHEN** `suggestProfileId('My  Dev-Box!')`
- **THEN** результат — `my-dev-box`

#### Scenario: Занятый и зарезервированный id
- **WHEN** проверяются черновики с id `embedded`, `default`, `Dev` при существующем `dev`, `a:b` и пустым id
- **THEN** проблемы — зарезервированный, зарезервированный, занятый, недопустимый и пустой id соответственно

#### Scenario: Секретоподобный ключ окружения
- **WHEN** черновик stdio содержит env `GITHUB_TOKEN=ghp_x` и `LOG_LEVEL=debug`
- **THEN** проверка возвращает одну проблему для `GITHUB_TOKEN`, её текст не содержит `ghp_x`, а `toProfile` профиль не строит

#### Scenario: ws:// к удалённому хосту
- **WHEN** проверяются URL `ws://localhost:8765`, `ws://10.0.0.5:8765` и `wss://devbox:7420`
- **THEN** предупреждение `plaintextToRemote` есть только у второго

#### Scenario: Userinfo в URL
- **WHEN** проверяются WebSocket-черновики с URL `ws://u:sk-test-leak-0123456789@10.0.0.5:8765` и `wss://u@devbox:7420`
- **THEN** у обоих есть проблема `urlUserInfo`, её текст не содержит `u:`, `u@` и `sk-test-leak-0123456789`, а `toProfile` профиль не строит

#### Scenario: Токен из переменной окружения
- **WHEN** WebSocket-черновик с `EnvToken('DEVBOX_TOKEN')` превращается в профиль, а черновик с `EnvToken('1BAD')` проверяется
- **THEN** профиль хранит `tokenRef: env:DEVBOX_TOKEN`, а второй черновик даёт проблему имени переменной

#### Scenario: Только поддержанные типы
- **WHEN** `profileKindsFor` получает только `ConfigTransportResolver(webSocket: …)` без фабрики stdio
- **THEN** результат — только WebSocket

### Requirement: Ссылка на токен профиля
`ProfileTokenRef.parse(ref)` SHALL понимать две формы `WebSocketProfile.tokenRef` (design.md change `add-app-settings-shell`, D15; design.md change `add-provider-setup-ui`, D13):
- `env:<NAME>` для любой переменной с допустимым именем — ссылка на переменную окружения процесса (`EnvTokenRef`);
- `secret:<имя>`, где имя проходит правило `SecretNames` (`^[a-z0-9][a-z0-9._/-]{0,127}$`, без `..` и пустых сегментов), — ссылка на секрет хранилища агента (`SecretTokenRef`).

Любую другую ссылку, в том числе голое имя секрета без префикса и `secret:` с недопустимым именем, он SHALL возвращать как неподдерживаемую в этой версии. `toString()` неподдерживаемой ссылки SHALL маскировать значение: туда мог попасть вписанный вручную токен.

`ProfileSecretSource(environment, {stored})` SHALL реализовывать `SecretSource` по этому правилу:
- `env:` читает переменную окружения;
- `secret:` читает `ProfileSecrets.read(имя)` порта `stored`.

Результат SHALL быть `null`, и подключение идёт без токена, если:
- переменная пуста или отсутствует;
- секрета нет;
- порт `stored` не передан;
- ссылка не поддерживается.

Источник SHALL использоваться и app, и CLI. Значение токена НЕ SHALL кэшироваться источником: каждое открытие транспорта читает его заново. Метод источника `isSecretMissing(profile)` SHALL возвращать `true`, только если WebSocket-профиль ссылается на `secret:<имя>`, а `ProfileSecrets.isSet(имя)` ложно, либо порт `stored` не передан, либо порт бросил ошибку; значение секрета он НЕ SHALL читать. Для `env:`, профиля без токена, неподдерживаемой ссылки и не-WebSocket-профиля — `false`. Источник сам НЕ SHALL писать в журнал: предупреждение о незаданном секрете (текст — `secretMissingWarning(profileId)`) выдаёт хост перед подключением (spec app-settings и codelab-cli; design.md change `add-provider-setup-ui`, D13).

#### Scenario: Формы ссылки
- **WHEN** `ProfileSecretSource` с окружением `CODELAB_AGENT_TOKEN=t1`, `DEVBOX_TOKEN=t2`, `EMPTY=` и портом `stored`, где секрет `codelab/profiles/dev/token` = `t3`, читает `env:CODELAB_AGENT_TOKEN`, `env:DEVBOX_TOKEN`, `env:EMPTY`, `env:MISSING`, `secret:codelab/profiles/dev/token`, `secret:codelab/missing` и `codelab/profiles/dev/token`
- **THEN** результаты — `t1`, `t2`, `null`, `null`, `t3`, `null` и `null`; `ProfileTokenRef.parse('codelab/profiles/dev/token')` и `ProfileTokenRef.parse('secret:Bad Name')` — неподдерживаемые ссылки

#### Scenario: Без порта хранилища
- **WHEN** `ProfileSecretSource` создан без `stored` и читает `secret:codelab/profiles/dev/token`
- **THEN** результат `null`, исключения нет

#### Scenario: Проверка наличия секрета без чтения значения
- **WHEN** `isSecretMissing` вызывается для профилей с `secret:codelab/profiles/a/token` (задан), `secret:codelab/profiles/b/token` (не задан), `env:MISSING` и без токена
- **THEN** результаты — `false`, `true`, `false`, `false`; `ProfileSecrets.read` не вызывался

#### Scenario: Замена секрета видна при следующем подключении
- **WHEN** источник прочитал `secret:codelab/ws` = `a`, после чего другой процесс заменил значение на `b`, и транспорт открывается снова
- **THEN** второе чтение возвращает `b`

### Requirement: Записи профилей с зарезервированным id
`usableStoredProfiles(profiles)` SHALL отделять от прочитанного списка запись с зарезервированным id `default` (`ignoredDefault`) и возвращать остальные профили в порядке файла. Хосты SHALL выбирать профиль только из отделённого списка и сообщать пользователю о проигнорированной записи; `ProfileStore.load` при этом SHALL возвращать файл как есть. `JsonFileProfileStore.save` SHALL отклонять профиль с id из `reservedProfileIds` `ArgumentError`, не меняя файл. `ProfileStore.remove('default')` SHALL удалять такую запись, как любую другую.

#### Scenario: Старая запись default отделяется
- **WHEN** `ProfileStore.load` возвращает профили `default` и `dev`
- **THEN** `usableStoredProfiles` возвращает только `dev` и признак проигнорированной записи `default`

#### Scenario: Запись default нельзя сохранить, но можно удалить
- **WHEN** `JsonFileProfileStore.save` получает stdio-профиль с id `default`, а затем на файле со старой записью `default` вызывается `remove('default')`
- **THEN** `save` бросает `ArgumentError` и файл не меняется; `remove` возвращает `true`, и запись удалена

### Requirement: Неизвестный уровень риска вызова
Клиентский уровень риска одобрения (`ApprovalRiskLevel` пакета `codelab_client_acp`) SHALL иметь значение `unknown` для вызова, вид которого (`ToolKind` ACP) — `other` или не передан; `read`, `search` и `think` остаются `readOnly`. `unknown` SHALL ранжироваться выше `readOnly` и ниже `localWrite`, а решение режима разрешений клиента для него SHALL требовать явного одобрения (AGENTS.md §10: неизвестная потенциально опасная capability не считается безопасной; решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q32, D27). Новых полей и значений ACP это не вводит.

#### Scenario: Вид other
- **WHEN** агент запрашивает разрешение на вызов с `kind: other` без содержимого diff и терминала
- **THEN** уровень риска одобрения — `unknown`, инспектор показывает `unknown`, CLI — `unknown risk`

#### Scenario: Вид не передан
- **WHEN** `tool_call` пришёл без `kind`
- **THEN** уровень риска — `unknown`, а не `readOnly`

### Requirement: Порт хранилища секретов профилей
Kit SHALL объявлять порт `ProfileSecrets` (`codelab_client_core/lib/src/connection/profile_secrets.dart`, чистый Dart) с описанием бэкенда (`id`, `writable`, `unavailableReason`), `names()`, `isSet(name)`, `store(name, SecretText)`, `delete(name)` и `read(name)` (design.md, D13). Результаты `store` и `delete` SHALL быть типизированными (`Stored`, `Exists`, `ReadOnly`, `Failed`; `Deleted`, `NotSet`, `ReadOnly`, `Failed`) и НЕ SHALL содержать значения. Реализацию SHALL давать composition root хоста. Kit НЕ SHALL зависеть от `codelab_setup` и пакетов агента.

`SecretText` SHALL оборачивать значение нового токена в памяти: `toString()` и JSON-представление — `***`, значение доступно только через `reveal()`.

Функция kit `selectableProfileTokenSecrets(names)` SHALL отбирать из имён хранилища только те, что начинаются с `codelab/profiles/` и дают `SecretTokenRef` при разборе `secret:<имя>`, по алфавиту и без повторов (удобно для списка выбора). Ключи провайдеров (`codelab/<id>`) и секреты MCP (`codelab/mcp/…`) она НЕ SHALL возвращать (design.md change `add-provider-setup-ui`, D14). Ссылку `secret:<имя>` на другой допустимый секрет, вписанную в `profiles.json` вручную, фильтр не затрагивает: её по-прежнему читает `ProfileSecretSource`.

#### Scenario: Фильтр имён для «Use stored secret»
- **WHEN** `selectableProfileTokenSecrets` получает `codelab/anthropic`, `codelab/mcp/github/authorization`, `codelab/profiles/devbox/token`, `codelab/profiles/Bad Name` и `codelab/profiles/ci/token`
- **THEN** результат — `codelab/profiles/ci/token` и `codelab/profiles/devbox/token` в этом порядке; повторное имя во входе даёт одну строку

#### Scenario: SecretText не печатает значение
- **WHEN** `SecretText('sk-test-leak-0123456789')` попадает в `toString()` черновика профиля, в `jsonEncode` и в текст исключения
- **THEN** ни один результат не содержит `sk-test-leak-0123456789`

### Requirement: Запись профиля с новым токеном
`ProfileCommitter` (kit) SHALL сохранять WebSocket-профиль с вариантом «Store a new token» в порядке «секрет → профиль» (SETUP-19; design.md, D13):
1. перечитать id профилей; занятый id — проблема черновика `idTaken` без записи;
2. `ProfileSecrets.store('codelab/profiles/<id>/token', value)`; `Exists` — проблема черновика `tokenSecretExists` без записи профиля и без отката. `Exists` SHALL возвращаться и тогда, когда имя появилось в хранилище между проверкой и записью (хранилище сообщило «обновлено»): такой секрет не создан этой операцией. `ReadOnly` и `Failed` — `ProfileSaveFailed` без записи профиля;
3. ещё раз перечитать id — после записи секрета; занятый id — проблема `idTaken` и удаление секрета, созданного на шаге 2;
4. `ProfileStore.save` профиля с `tokenRef: secret:codelab/profiles/<id>/token`;
5. если шаг 4 не удался, секрет, созданный на шаге 2, SHALL удаляться.

Для «Use stored secret» SHALL выполняться только шаги 1, 3 и 4 с `tokenRef: secret:<выбранное имя>`. `ProfileSaveFailed` и `RemoveFailed` SHALL нести `errorType` — имя типа исключения без его текста.

`ProfileCommitter.remove(id, {deleteOwnSecret})` SHALL сначала удалять профиль. Только после успеха и только если профиль ссылается на `secret:codelab/profiles/<id>/token`, и ни один другой профиль файла не ссылается на то же имя, он SHALL удалять этот секрет. Секрет, выбранный «Use stored secret» (не собственный), НЕ SHALL удаляться никогда. Ошибка удаления секрета НЕ SHALL восстанавливать профиль.

#### Scenario: Секрет до профиля и откат
- **WHEN** `ProfileCommitter` сохраняет профиль `devbox` с новым токеном, а `ProfileStore.save` бросает исключение
- **THEN** `ProfileSecrets.store` вызван до `save`, после ошибки вызван `delete('codelab/profiles/devbox/token')`, результат — `ProfileSaveFailed`, `profiles.json` не изменён

#### Scenario: Id занят во время записи секрета
- **WHEN** `ProfileCommitter` записал секрет `codelab/profiles/devbox/token`, а к повторной проверке id профиль `devbox` уже создан другим процессом
- **THEN** результат — проблема `idTaken`, секрет удалён, профиль другого процесса не изменён

#### Scenario: Имя секрета появилось между проверкой и записью
- **WHEN** хранилище на `store('codelab/profiles/devbox/token', …)` сообщает, что имя уже было и значение обновлено
- **THEN** результат — проблема `tokenSecretExists`, `ProfileStore.save` не вызывался, `delete` не вызывался

#### Scenario: Тип ошибки без текста
- **WHEN** `ProfileStore.save` бросает исключение, чей `toString()` содержит `sk-test-leak-0123456789`
- **THEN** `ProfileSaveFailed.errorType` — имя типа исключения, ни один результат не содержит маркера

#### Scenario: Существующий секрет не перезаписывается
- **WHEN** в хранилище уже есть `codelab/profiles/devbox/token`, и `ProfileCommitter` сохраняет профиль `devbox` с новым токеном
- **THEN** результат — проблема `tokenSecretExists`, значение секрета не изменено, `ProfileStore.save` не вызывался

#### Scenario: Удаление профиля с собственным секретом
- **WHEN** профиль `devbox` с `tokenRef: secret:codelab/profiles/devbox/token` удаляется с `deleteOwnSecret: true`, а профиль `ci` ссылается на `secret:codelab/ws-ci`
- **THEN** профиль удалён, затем удалён секрет `codelab/profiles/devbox/token`; удаление `ci` с `deleteOwnSecret: true` удаляет профиль и не трогает `codelab/ws-ci`

#### Scenario: Общий секрет не удаляется
- **WHEN** профили `a` и `b` (последний отредактирован вручную) оба ссылаются на `secret:codelab/profiles/a/token`, и `a` удаляется с `deleteOwnSecret: true`
- **THEN** профиль `a` удалён, секрет остаётся

### Requirement: Отказ рукопожатия из-за токена
Kit SHALL определять отказ WebSocket-агента из-за токена одной web-безопасной функцией (`codelab_client_core/lib/src/connection/token_rejection.dart`; design.md, D25):
- `tokenRejectionStatus(error)` SHALL возвращать 401 или 403, найденные по цепочке `cause` ошибки (`AcpClientApplicationException` → `AcpTransportException` → `AcpWebSocketHandshakeRejected`) на ограниченную глубину, и `null` для любого другого статуса и ошибки. Текст ошибок НЕ SHALL разбираться;
- `describeTokenRejection(error, {tokenSent})` SHALL возвращать `the agent rejected the token (HTTP <код>)` при `tokenSent` и `the agent requires a token (HTTP <код>)` без него, а для прочих ошибок — `null`;
- `profileTokenSent(profile, SecretSource?)` SHALL отвечать, был ли токен отправлен, не читая значения: для `ProfileSecretSource` с `secret:` — через `isSet` порта, для `env:` — по наличию непустой переменной;
- `describeConnectFailureByToken(error, profile, SecretSource?)` SHALL сначала вычислять `tokenRejectionStatus(error)` и только при 401 или 403 обращаться к `profileTokenSent`; для прочих ошибок источник секретов НЕ SHALL вызываться, а результат — `null`. Результат — строчный текст `describeTokenRejection` без точки; хосты оформляют его сами.

`tokenRejectionStatus` SHALL оставаться единственным местом, где цепочка `cause` читается ради 401/403 (design.md change `remove-test-connection`, D2).

#### Scenario: Статус по цепочке причин
- **WHEN** `tokenRejectionStatus` получает `AcpClientApplicationException`, чья причина — `AcpTransportException` с причиной `AcpWebSocketHandshakeRejected(401)`; затем такую же цепочку с `500`; затем `SocketException`
- **THEN** результаты — `401`, `null`, `null`

#### Scenario: Текст по отправленному токену
- **WHEN** `describeTokenRejection` получает отказ `403` с `tokenSent: true`, затем с `tokenSent: false`, затем ошибку без статуса
- **THEN** результаты — `the agent rejected the token (HTTP 403)`, `the agent requires a token (HTTP 403)` и `null`

#### Scenario: При прочей ошибке источник не вызывается
- **WHEN** `describeConnectFailureByToken` получает `SocketException` (или отказ `500`) для WebSocket-профиля с `secret:codelab/profiles/a/token` и источником-шпионом
- **THEN** результат `null`, ни `isSet`, ни `read` источника не вызывались; при отказе `401` вызван только `isSet`, `read` — нет

#### Scenario: Токен отправлен или нет
- **WHEN** `profileTokenSent` проверяет WebSocket-профили с `env:SET` (переменная непуста), `env:EMPTY`, `secret:<имя без значения>`, без токена и stdio-профиль
- **THEN** результаты — `true`, `false`, `false`, `false`, `false`; значение секрета не читалось

### Requirement: Агент по требованию хоста
Kit SHALL предоставлять операцию `ClientWorkspace.ensureAgent(directory, {profile})` и поле `WorkspaceState.agentDirectory` — корень процесса текущего соединения (design.md change `require-project-folder`, D11, D15, D16):

- **Профиль.** Берётся `profile`, иначе профиль текущего или последнего соединения. Без профиля — `ClientWorkspaceException`, без обращения к резолверам.
- **Работающий агент.** При `Connected` операция SHALL завершаться без запросов к агенту и резолверам, какую бы папку ни передали.
- **Single-flight.** Если идёт попытка (`Connecting`, `Reconnecting`), операция SHALL возвращать её результат и НЕ SHALL открывать второй транспорт. Явный `connect` или `reconnect` во время попытки `ensureAgent` SHALL вытеснять её по общим правилам вытеснения: `Future` `ensureAgent` завершается без ошибки, итог читается из состояния (design.md change `require-project-folder`, Q25 (a)).
- **Новая попытка.** Иначе kit SHALL открывать соединение с корнем процесса `directory` по правилам `connect` (вытеснение, `Connecting`, `ConnectionFailed`). `agentDirectory` SHALL становиться `directory`. `projectDirectory` (выбранный проект и снимок) НЕ SHALL меняться.
- **Совместимость.** `connect(profile, projectDirectory:)` SHALL по-прежнему задавать и `projectDirectory`, и `agentDirectory`. `reconnect(projectDirectory:)` SHALL задавать обе папки. `reconnect(agentDirectory:)` SHALL задавать только `agentDirectory` и НЕ SHALL менять `projectDirectory`; без обоих параметров корнем SHALL оставаться прежний `agentDirectory`, а без него — `projectDirectory`. Резолвер SHALL получать `agentDirectory` в параметре `projectDirectory` метода `TransportResolver.open`. Поведение хостов, которые вызывают только `connect` и `reconnect()` (CLI), не меняется.
- **Список при смене проекта.** `selectProject(path)` при `Connected` SHALL сбрасывать список и курсор и запрашивать первую страницу `session/list` для `path`, если агент объявил `sessionCapabilities.list`. Ответ, пришедший после следующей смены проекта или подключения, НЕ SHALL менять список и курсор. Без `projectDirectory` kit НЕ SHALL запрашивать `session/list` после подключения: запрос без `cwd` вернул бы сессии всех папок.
- **Новая сессия без активации.** `newSession(cwd:, activate: false)` SHALL создавать сессию, добавлять её в список и снимок и НЕ SHALL менять `activeSessionId`. По умолчанию `activate` истинно, как сейчас.

#### Scenario: Работающий агент не трогается
- **WHEN** агент подключён с корнем процесса `/work/a`, и вызывается `ensureAgent('/work/b')`
- **THEN** резолвер не вызывается, запросов к агенту нет, `agentDirectory` — `/work/a`

#### Scenario: Первый старт
- **WHEN** соединения нет, выбран проект `/work/app`, и вызывается `ensureAgent('/work/app')`
- **THEN** резолвер открывает транспорт с папкой `/work/app`, после подключения `agentDirectory` — `/work/app`, `projectDirectory` прежний, запрошен `session/list` для `/work/app`

#### Scenario: Повторный вызов во время попытки
- **WHEN** `ensureAgent('/work/a')` ждёт открытия транспорта, и вызывается `ensureAgent('/work/b')`
- **THEN** резолвер вызван один раз, с `/work/a`; оба вызова завершаются после одного подключения

#### Scenario: Смена проекта перезапрашивает список
- **WHEN** агент подключён, `session/list` для `/work/a` ещё не ответил, и хост вызывает `selectProject('/work/b')`
- **THEN** отправлен `session/list` с `cwd` `/work/b`; поздний ответ для `/work/a` список не меняет

#### Scenario: Перезапуск вытесняет зависший старт
- **WHEN** `ensureAgent('/work/a')` ждёт открытия транспорта, и хост вызывает `reconnect(agentDirectory: '/work/a')`
- **THEN** транспорт первой попытки закрыт, `Future` `ensureAgent` завершается без ошибки, промежуточного `ConnectionFailed` нет, а состояние соединения задаёт попытка `reconnect`

#### Scenario: Перезапуск с корнем сессии не меняет проект
- **WHEN** выбран проект `/work/a`, агент подключён, и хост вызывает `reconnect(agentDirectory: '/work/b')`
- **THEN** резолвер открывает транспорт с папкой `/work/b`, `agentDirectory` — `/work/b`, `projectDirectory` — `/work/a`, а `session/list` после подключения отправлен с `cwd` `/work/a`

#### Scenario: Старт без проекта не запрашивает список
- **WHEN** проект не выбран, открыта `detached`-сессия с `cwd` `/work/b`, и хост вызывает `ensureAgent('/work/b')`
- **THEN** после подключения `session/list` не отправлен

#### Scenario: Сессия без активации
- **WHEN** активна сессия `s1`, и хост вызывает `newSession(cwd: '/work/a', activate: false)`
- **THEN** `session/new` отправлен, новая сессия есть в `WorkspaceState.sessions`, а `activeSessionId` — `s1`

#### Scenario: CLI-путь не меняется
- **WHEN** хост вызывает `connect(profile, projectDirectory: '/work/app')` и создаёт сессии без `cwd`
- **THEN** `agentDirectory` и `projectDirectory` — `/work/app`, сессии создаются с `cwd` `/work/app`, а `reconnect()` загружает их все

### Requirement: Метаданные пунктов плана
`PlanEntryView` SHALL получать из `_meta.codelab.task` entry `plan` необязательные поля `taskId` (строка), `owner` (строка) и `blockedBy` (список строк) (design.md change `add-subagents-and-tasks`, D15). Отсутствие `_meta`, неверный тип поля или неизвестные ключи SHALL давать `null` (или пустой список) для этого поля без отказа обработки обновления. Каждое обновление `plan` по-прежнему SHALL заменять план целиком (требование «Публикация представлений сессии»).

`SessionView` SHALL давать представлению для каждого пункта:
- список незавершённых блокеров — id из `blockedBy`, чьи пункты в текущем плане не `completed`;
- метку владельца-субагента — `type` из известного kit сведения о субагенте с этим id (`ToolCallView.subagentCall` вызовов `agent` сессии; с итерации 3 — и `SubagentRequester` запросов одобрения), иначе сам id; для `owner: main` и без `owner` метки нет (design.md, D36 Т13, D42 Т9).

#### Scenario: План с метаданными
- **WHEN** агент присылает `plan`, где у второй entry `_meta.codelab.task: {"id": "2", "owner": "sub_a1", "blockedBy": ["1"]}`, а первая entry `pending`
- **THEN** `PlanEntryView` второго пункта имеет `taskId: "2"`, `owner: "sub_a1"`, незавершённый блокер `1`

#### Scenario: План стороннего агента
- **WHEN** агент присылает `plan` без `_meta` (фикстура `acp/prompt-update-plan`, роль `client`)
- **THEN** `SessionView.plan` содержит пункты с `taskId == null`, показ прежний

#### Scenario: Неверная форма метаданных
- **WHEN** у entry `_meta.codelab.task` — `{"id": 5, "blockedBy": "1"}`
- **THEN** обновление применяется, `taskId` и `blockedBy` пустые, ошибки нет

### Requirement: Запрос одобрения от субагента
`PendingApprovalView` и `ToolCallView` вызова, объявленного только запросом `session/request_permission`, SHALL получать поле `subagent` (`SubagentRequester`: `id`, `type`, `description`, `depth`, `parentToolCallId`) из `toolCall._meta.codelab.subagent` запроса (design.md, D15). Поле нужно, чтобы показать, кто спрашивает.

Смысл `_meta.codelab.subagent` SHALL определяться видом кадра (design.md, D43, п. 1): в `toolCall` запроса разрешения — спрашивающий потомок, в `tool_call` и `tool_call_update` — запущенный вызовом `agent` субагент. `SubagentRequester` SHALL браться только из запроса разрешения и храниться отдельно от данных вызова `agent`; запрос НЕ SHALL делать вызов вызовом `agent` (`ToolCallView.subagentCall`) и НЕ SHALL менять его `subagentSummary`. Нет или неверная форма → `null`, запрос показывается как обычный. `toolCallId` с `/` SHALL оставаться непрозрачной строкой: kit его не разбирает.

`SubagentRequester` SHALL давать `pathTypes` — типы цепочки от ребёнка корня до спрашивающего (D27): первый — тип вызова `agent` с id `parentToolCallId`: `subagentCall.type`, если его нет — `rawInput.type`, иначе `…` (D43, п. 4), последний — `type` спрашивающего, промежуточные — `type` вызовов `agent`, найденных подъёмом по `parentToolCallId` в дереве вызовов (этап 2); звено, которое kit не знает (нет дерева), — `…`. Длина пути равна `depth`. Kit SHALL давать строку пути `review › explore` для представлений.

Ответ на такой запрос SHALL идти тем же `SessionHandle.respond` и только в этот запрос (PERM-4). Сведения о субагенте SHALL оставаться у записи вызова после решения.

Вызов потомка, объявленный только запросом с `SubagentRequester`, НЕ SHALL давать отдельного элемента транскрипта, пока в ходе есть строка вызова `agent` с id `subagent.parentToolCallId` (D43, п. 2): ожидающее одобрение и после решения его исход SHALL быть доступны представлению у этой строки. Если такой строки в ходе нет, вызов SHALL показываться прежним элементом вызова, объявленного только запросом, в конце хода.

Строка вызова `agent` (`kind: think`) SHALL показывать в `ToolRowView`:
- заголовок агента как деталь;
- последнюю строку прогресса из `content`, пока вызов идёт;
- текст отчёта как текстовый вывод после завершения.

#### Scenario: Запрос ребёнка
- **WHEN** агент присылает `session/request_permission` с `toolCall.toolCallId: "call_3/call_1"` и `_meta.codelab.subagent: {"id": "sub_a1", "type": "review", "description": "Check the diff", "depth": 1, "path": [], "parentToolCallId": "call_3"}`
- **THEN** `PendingApprovalView.subagent` — `review`, `Check the diff`, глубина 1, `parentToolCallId: "call_3"`, путь `review`; ответ уходит с id этого запроса

#### Scenario: Путь внука без дерева
- **WHEN** клиент без `subagentToolCalls` получает запрос внука `explore` (`depth: 2`, `parentToolCallId` — вызов `agent` корня с `rawInput.type: "review"`)
- **THEN** путь — `review › explore`; при `depth: 3` без дерева — `review › … › explore`

#### Scenario: Запрос ребёнка не делает вызов вызовом agent
- **WHEN** агент присылает запрос ребёнка `review` к `call_1/call_1` с `_meta.codelab.subagent` `{id, type, description, depth: 1, path: [], parentToolCallId: "call_1"}`, строка `call_1` — вызов `agent` с `subagentCall` `sub_a1`
- **THEN** у записи `call_1/call_1` `subagentCall == null` и `subagentSummary == null`, `subagent` — `review`; отдельного элемента транскрипта для `call_1/call_1` нет, одобрение доступно у строки `call_1`; после решения — его исход там же

#### Scenario: Запрос ребёнка без строки корня
- **WHEN** приходит запрос ребёнка с `parentToolCallId: "call_9"`, а строки `call_9` в ходе нет
- **THEN** вызов показывается элементом вызова, объявленного только запросом, в конце хода, с `subagent` и путём

#### Scenario: Тип звена по умолчанию
- **WHEN** у вызова `agent` корня `rawInput` без `type`, а `subagentCall.type` — `general`; приходит запрос внука `explore` (`depth: 2`)
- **THEN** путь — `general › explore`

#### Scenario: Запрос без сведений о субагенте
- **WHEN** запрос несёт `toolCallId` с `/`, но без `_meta.codelab.subagent`
- **THEN** `subagent == null`, запрос показывается и решается как обычный

### Requirement: Дерево вызовов потомков
`ToolCallView` SHALL получать необязательное `parentToolCallId` из `_meta.codelab.parentToolCallId` кадров `tool_call` и `tool_call_update` (этап 2; design.md change `add-subagents-and-tasks`, D21). `SessionView` SHALL давать представлению дерево: вызовы с `parentToolCallId` — дети вызова с этим id в том же ходе, в порядке прихода; вызов, чей родитель неизвестен, SHALL показываться на верхнем уровне, а не теряться. Неверная форма поля → `null`.

Ожидающее одобрение вызова потомка SHALL оставаться привязанным к его `toolCallId` (PERM-4); путь от корня до такого вызова SHALL быть доступен представлению, чтобы раскрыть его. Повтор кадров реплея и живого хода SHALL не дублировать детей (идемпотентность по `toolCallId`, `AGENTS.md` §9).

При дереве вызов потомка объявлен своим `tool_call`, и правило «без отдельного элемента» требования «Запрос одобрения от субагента» к нему не применяется: вызов остаётся вложенной строкой. Его ожидающее одобрение и исход SHALL при этом быть доступны и у строки вызова `agent` корневого уровня (`subagent.parentToolCallId`, как без дерева — D27 п. 4, D43 п. 2), и у вложенной строки. Решение представление принимает в блоке под строкой корня; вложенная строка показывает ожидание и исход (design.md, D47 Т9).

#### Scenario: Запрос в дереве
- **WHEN** при дереве внук просит `exec` для вызова `call_1/call_2/call_1`, объявленного `tool_call` с `parentToolCallId: "call_1/call_2"`, а запрос несёт `subagent.parentToolCallId: "call_1"`
- **THEN** ожидающее одобрение доступно у строки `call_1` (как без дерева) и у вложенной строки `call_1/call_2/call_1`, отдельного элемента верхнего уровня нет; путь — типы `subagentCall` вызовов `call_1` и `call_1/call_2` без `…`; после ответа исход виден там же, а ответ уходит один раз в этот запрос

#### Scenario: Вложенность по parentToolCallId
- **WHEN** агент присылает `tool_call` `call_1` (`agent`), затем `call_1/call_1` и `call_1/call_2/call_1` с `parentToolCallId` `call_1` и `call_1/call_2`, причём `call_1/call_2` пришёл раньше своего ребёнка
- **THEN** дерево: `call_1` → [`call_1/call_1`, `call_1/call_2` → [`call_1/call_2/call_1`]]

#### Scenario: Неизвестный родитель
- **WHEN** приходит `tool_call` с `parentToolCallId: "call_9"`, которого в ходе нет
- **THEN** вызов показывается на верхнем уровне, ошибки нет

#### Scenario: Реплей без дублей
- **WHEN** сессия с деревом вызовов загружается дважды подряд в один `ClientWorkspace`
- **THEN** у каждого вызова `agent` ровно столько детей, сколько в журнале

### Requirement: Итог и хвост субагента
Вызов SHALL считаться вызовом `agent` с первого кадра, если его `tool_call` несёт `_meta.codelab.subagent` (`ToolCallView.subagentCall`: `type` и необязательный `id`; D28). Без `id` приходит реплей отклонённого вызова: у него нет записи `subagent` (design.md, D36, Т15). Отсутствие поля, `type` не строкой, неверная форма или неизвестные ключи SHALL давать `null` без отказа; такой вызов (сторонний агент) — обычный вызов `think`.

`ToolCallView` вызова `agent` SHALL получать `subagentSummary` (`toolCalls`, `inputTokens`, `outputTokens`, `duration`) из `_meta.codelab.subagent.summary` финального обновления (design.md change `add-subagents-and-tasks`, D24). Отсутствие, неверная форма или неизвестные ключи SHALL давать `null` или игнорироваться без отказа обработки. Kit SHALL давать готовую строку итога `N tool calls · N.Nk tokens · <время>` и её сокращённый вид для свёрнутой строки `N tool calls · N.Nk · <время>` (D27) (токены — `input + output`, `k` с одним знаком; время — `48s`, `2m 05s`, `1h 02m`).

Для работающего вызова `agent` с потомками в дереве (acp-client-kit «Дерево вызовов потомков») `SessionView` SHALL давать «хвост» (D25): три последних вызова его поддерева по порядку прихода их `tool_call`, в этом порядке, и `moreCount` — число остальных вызовов поддерева. Вызовами поддерева SHALL считаться все вызовы потомков, включая вложенные вызовы `agent` и операции со списком задач, — как в `summary.toolCalls` (D24), поэтому счётчик работающего вызова не прыгает при завершении (design.md, D47 Т9). Токенов в хвосте нет: kit НЕ SHALL разбирать строку прогресса; токены даёт только `subagentSummary` завершённого вызова (D24, D25, Q15). Без вызовов потомков хвост пуст, и представление показывает строку прогресса.

#### Scenario: Вызов agent с первого кадра
- **WHEN** приходит `tool_call` с `kind: think` и `_meta.codelab.subagent: {"id": "sub_a1", "type": "explore", "x": 1}`, потомков и запросов ещё нет
- **THEN** `subagentCall` — `sub_a1`, `explore`; неизвестный ключ проигнорирован; тот же кадр без `_meta` даёт `subagentCall == null`

#### Scenario: Итог в представлении
- **WHEN** финальный `tool_call_update` вызова `agent` несёт `summary` `{"toolCalls": 4, "tokens": {"input": 15200, "output": 3000}, "durationMs": 48000, "future": 1}`
- **THEN** строка итога — `4 tool calls · 18.2k tokens · 48s`, неизвестный ключ проигнорирован

#### Scenario: Сторонний агент без итога
- **WHEN** вызов `agent` завершается без `_meta.codelab.subagent.summary`
- **THEN** `subagentSummary == null`, строки итога нет

#### Scenario: Хвост из пяти вызовов
- **WHEN** у работающего вызова `agent` пять вызовов потомков
- **THEN** хвост — три последних, `moreCount` — 2, токенов у хвоста нет, даже если строка прогресса их содержит

### Requirement: Операции со списком задач в ленте
Kit SHALL распознавать вызов операции со списком задач только по ключу `plan._meta.codelab.taskChange` (design.md, D35), без разбора текста, заголовка и порядка кадров: вызов любого уровня дерева вызовов (у потомка `toolCallId` — цепочка) вида `think`, без `_meta.codelab.subagent`, завершившийся `completed`, на который ссылается `taskChange.toolCallId` хотя бы одного `plan`. Такой вызов SHALL становиться в транскрипте элементом `TaskOpsItem` с изменением из ключей: добавленные id (`op: create`), удалённые (`op: delete` и `deleted`), ставшие `completed` (`op: update`, пункт `completed` в этом `plan` и не `completed` в предыдущем плане сессии) и прочие изменённые id (`changed`). Подряд идущие `TaskOpsItem` без других элементов транскрипта между ними SHALL сливаться в один (изменения объединяются) только среди соседей одного родителя: операция потомка становится вложенным элементом строки своего `agent` и не сливается с операциями корня или другого потомка (design.md, D48 п. 3; решение пользователя 2026-11-15, Q35 (а)). В счётчике и хвосте поддерева операция остаётся вызовом (требование «Итог и хвост субагента»).

`plan` без `taskChange` (сторонний или старый агент, реплей) и `taskChange` без `toolCallId` (`restore`, `assign`) SHALL только обновлять план сессии; вызовы при этом остаются обычными `ToolCallView`. Запасного распознавания по сравнению планов или по статусу вызова в момент прихода `plan` НЕ SHALL быть. Неизвестные ключи и значения `taskChange` SHALL игнорироваться; ключ неверной формы — как отсутствующий.

Kit SHALL давать текст элемента: «Task #3 added to the plan» / «Tasks #1–#4 added to the plan» (подряд идущие id — диапазоном, иначе списком `#1, #3`), «Task #2 done», «Task #2 removed», «Task #2 updated»; части объединяются через `; `.

Вызов `failed` и вызов, на который не ссылается ни один `taskChange` (чтение `task_list`, `task_get`; план стороннего агента), SHALL оставаться обычным `ToolCallView`.

После `session/load` прошлые вызовы `task_*` приходят реплеем завершёнными `tool_call`, а план — одним `plan` после истории без `taskChange` (agent-acp-server «Реплей плана без taskChange»). Поэтому в реплее они SHALL показываться обычными строками вызовов, а не `TaskOpsItem`: это ожидаемо, текущий список виден по `plan` в хвосте.

#### Scenario: Слияние созданий
- **WHEN** четыре вызова `think` подряд, на каждый ссылается `plan` с `taskChange` `{op: create, toolCallId: <id вызова>, changed: [<новый id>]}` (`#1`…`#4`), все `completed`
- **THEN** транскрипт содержит один `TaskOpsItem` с текстом «Tasks #1–#4 added to the plan»

#### Scenario: Операции ребёнка в дереве
- **WHEN** при дереве ребёнок вызова `call_1` делает два успешных `task_update` `call_1/call_2` и `call_1/call_3` подряд, на каждый ссылается `plan` с `taskChange.toolCallId`, а корень между ними — свой `task_update` `call_4`
- **THEN** под `call_1` — один вложенный `TaskOpsItem` с обоими изменениями; операция корня — отдельный `TaskOpsItem` верхнего уровня, слияния между уровнями нет

#### Scenario: Отклонённая операция
- **WHEN** вызов `think` завершился `failed`, ни один `plan` на него не ссылается
- **THEN** вызов — обычный `ToolCallView` со статусом `failed`

#### Scenario: Параллельный пакет с чтением между операциями
- **WHEN** ответ модели — пакет `[task_create, read, task_create]` с id `c1`, `r1`, `c2`; `plan` с `taskChange {op: create, toolCallId: "c2", changed: ["2"]}` приходит раньше `plan` для `c1` (`changed: ["1"]`); все три вызова `completed`
- **THEN** транскрипт — `TaskOpsItem` «Task #1 added to the plan», строка `read`, `TaskOpsItem` «Task #2 added to the plan»: каждый `plan` отнесён к своему вызову по ключу независимо от порядка кадров, `read` разделяет элементы, слияния нет

#### Scenario: task_list в пакете не операция
- **WHEN** пакет `[task_create, task_list]`; `plan` с `taskChange.toolCallId` вызова `task_create` приходит, пока оба вызова `in_progress`
- **THEN** `task_create` — `TaskOpsItem` «Task #1 added to the plan», `task_list` — обычный `ToolCallView`

#### Scenario: plan без taskChange
- **WHEN** агент CodeLab старой версии присылает вызов `think` и во время него `plan` с `_meta.codelab.task`, но без `taskChange`
- **THEN** план сессии обновлён, вызов — обычный `ToolCallView`, `TaskOpsItem` нет

#### Scenario: restore без toolCallId
- **WHEN** во время хода приходит `plan` с `taskChange {op: restore, actor: main}` без `toolCallId`, пока вызов `think` в `in_progress`
- **THEN** план сессии заменён, вызов после `completed` — обычный `ToolCallView`

#### Scenario: Реплей прошлых операций
- **WHEN** `session/load` проигрывает три завершённых вызова `task_create`, затем один `plan` со списком `#1`–`#3` без `taskChange`
- **THEN** три вызова — обычные строки `ToolCallView`, `TaskOpsItem` нет; план сессии — `#1`–`#3`

#### Scenario: Сторонний агент
- **WHEN** агент без `_meta.codelab.task` присылает вызов `think` и `plan` во время него
- **THEN** вызов — обычный `ToolCallView`, план показывается как прежде

### Requirement: Список субагентов сессии
`SessionView.subagents` SHALL давать список субагентов сессии для панели Agents v1 (решение пользователя 2026-11-12, Q13; design.md change `add-subagents-and-tasks`, D33): по одной строке `SubagentRowView` на каждый вызов сессии с `ToolCallView.subagentCall` (требование «Итог и хвост субагента»), за все ходы, включая вызовы потомков из дерева (требование «Дерево вызовов потомков») и вызовы, проигранные `session/load`. Порядок — обход в глубину в порядке прихода: строки потомков стоят под строкой своего родительского вызова `agent`. Вызов без `subagentCall` (сторонний агент) строки НЕ SHALL давать.

Строка SHALL содержать:
- `toolCallId` вызова на проводе (ключ строки), id и `type` субагента, заголовок — `rawInput.description`, а без него — `title` вызова как есть;
- состояние `running`, `awaitingApproval`, `completed`, `failed` или `cancelled`: терминальные — по статусу вызова `agent`, как у его строки в ленте, кроме позднего неитогового кадра (до follow-up F.1, ниже); `awaitingApproval` — если есть ожидающее одобрение этой строки (ниже); иначе `running`;
- время: у терминальной строки — `duration` из `subagentSummary`; у работающей — `startedAt`, момент, когда kit впервые увидел `tool_call` вызова, по часам, внедрённым в `ClientWorkspace` (повтор кадра его не сдвигает); у терминальной строки без `subagentSummary` времени нет. Kit SHALL давать формат длительности тот же, что у строки итога (`48s`, `2m 05s`, `1h 02m`);
- число вызовов инструментов: у терминальной строки — `subagentSummary.toolCalls`, у работающей — число вызовов её поддерева в дереве; токены `input + output` — только из `subagentSummary`;
- последнее действие: у работающей строки — `title` последнего пришедшего вызова её поддерева, у `failed` — `_meta.codelab.subagent.failure`; иначе нет;
- глубину: 1 для вызова без `parentToolCallId` или с неизвестным родителем, иначе глубина строки-родителя плюс 1;
- id пунктов плана, у которых `PlanEntryView.owner` — id этого субагента, и id из `rawInput.task`;
- `approvalId` ожидающего одобрения, у которого `PendingApprovalView.subagent.id` — id этого субагента; если строки с таким id нет, одобрение SHALL относиться к строке корневого уровня с `toolCallId`, равным `subagent.parentToolCallId`. Кроме того, строка SHALL получать `awaitingApproval` и `approvalId` ожидающего одобрения, чей `toolCallId` равен её собственному `toolCallId`: запуск самой строки ждёт решения (design.md, D50 п. 3). Отметка спрашивающего при этом остаётся; при нескольких одобрениях строки `approvalId` — самого раннего. Счётчик `awaitingApproval` считает строки, а не одобрения.

`SessionView` SHALL давать счётчики строк по состояниям.

Kit НЕ SHALL разбирать `title`, строку прогресса и текст отчёта: состояния `queued` и `waiting`, шаги и токены работающего субагента в строке НЕ SHALL появляться (D33). Отсутствие или неверная форма любого источника SHALL давать пустое поле, а не отказ обработки обновления.

Список SHALL быть функцией транскрипта, ожидающих одобрений и плана сессии: повтор кадров, реплей и повторная загрузка сессии SHALL давать тот же список без дублей (идемпотентность по `toolCallId`, `AGENTS.md` §9). Кадр вызова `agent`, пришедший после его терминального статуса, НЕ SHALL возвращать строку в `running` (поздние события): kit SHALL помнить последний итоговый статус вызова, а смена одного итога другим (итоговый `completed` после `cancelled`) SHALL следовать ленте. До follow-up F.1, который делает итог окончательным для всех вызовов, это правило действует только для строки списка, а `ToolCallView.status` и лента не меняются (design.md, D50 п. 1).

#### Scenario: Строки ребёнка и внука
- **WHEN** клиент с `subagentToolCalls` получает `tool_call` `call_1` (`agent`, `_meta.codelab.subagent: {"id": "sub_a1", "type": "review"}`, `rawInput.description: "Check the diff"`), затем `call_1/call_1` (`read`) и `call_1/call_2` (`agent`, `sub_b2`, `explore`) с `parentToolCallId: "call_1"`, затем `call_1/call_2/call_1` (`ls`) с `parentToolCallId: "call_1/call_2"`
- **THEN** `SessionView.subagents` — две строки: `sub_a1` `review` «Check the diff» глубины 1, `running`, 3 вызова поддерева, последнее действие — `title` вызова `ls`; под ней `sub_b2` `explore` глубины 2, `running`, 1 вызов

#### Scenario: Итог завершённого субагента
- **WHEN** вызов `agent` `sub_a1` завершается `completed` с `summary` `{"toolCalls": 4, "tokens": {"input": 15200, "output": 3000}, "durationMs": 48000}`
- **THEN** строка — `completed`, 4 вызова, 18.2k токенов, 48s, последнего действия нет; счётчик `completed` равен 1

#### Scenario: Отмена и отказ
- **WHEN** один вызов `agent` завершается `failed` с `_meta.codelab.subagent.failure: "budget_exceeded:steps"`, другой — `failed` с `_meta.codelab.outcome: "cancelled"`
- **THEN** первая строка — `failed` с последним действием `budget_exceeded:steps`, вторая — `cancelled`

#### Scenario: Ожидание одобрения потомка
- **WHEN** у работающего `sub_b2` (внук) ожидает ответа `session/request_permission` с `_meta.codelab.subagent.id: "sub_b2"`
- **THEN** строка `sub_b2` — `awaitingApproval` с `approvalId` этого запроса, строка `sub_a1` остаётся `running`; после ответа пользователя строка `sub_b2` снова `running`

#### Scenario: Одобрение без дерева
- **WHEN** клиент без вызовов потомков получает запрос внука `sub_b2` с `parentToolCallId: "call_1"`, а строки `sub_b2` нет
- **THEN** `awaitingApproval` с `approvalId` этого запроса получает строка `call_1`

#### Scenario: Пункты списка у субагента
- **WHEN** план содержит `#2` с `_meta.codelab.task.owner: "sub_a1"`, а `rawInput.task` вызова `sub_a1` — `"2"`
- **THEN** строка `sub_a1` несёт один пункт `2`

#### Scenario: Реплей без дублей в списке
- **WHEN** сессия с двумя вызовами `agent`, у одного из которых вызов `agent` потомка, загружается дважды подряд в один `ClientWorkspace`
- **THEN** `SessionView.subagents` — ровно три строки, все терминальные, со временем и вызовами из `summary`

#### Scenario: Поздний кадр после завершения
- **WHEN** после `tool_call_update` `completed` вызова `agent` приходит ещё один `tool_call_update` того же `toolCallId` со `status: in_progress`
- **THEN** строка остаётся `completed`; `ToolCallView.status` этого вызова следует общему слиянию кадров, как до этого change (до F.1)

#### Scenario: Запуск ждёт одобрения
- **WHEN** ребёнок `sub_a1` запускает внука: приходит `tool_call` `call_1/call_2` (`agent`, `_meta.codelab.subagent: {"id": "sub_b2", "type": "explore"}`, `status: pending`), и `session/request_permission` для `toolCallId` `call_1/call_2` с `_meta.codelab.subagent.id: "sub_a1"` ждёт ответа
- **THEN** строки `sub_a1` и `sub_b2` — `awaitingApproval` с `approvalId` этого запроса, счётчик `awaitingApproval` равен 2; после ответа обе строки — `running`

#### Scenario: Время работающего субагента
- **WHEN** часы `ClientWorkspace` показывают `10:00:00`, когда приходит `tool_call` вызова `agent`, и `10:00:30`, когда тот же `tool_call` приходит повторно
- **THEN** `startedAt` строки — `10:00:00`, формат длительности для 41 с — `41s`; после завершения с `summary.durationMs: 48000` время строки — 48s из `summary`

#### Scenario: Сторонний агент без признака
- **WHEN** агент присылает вызов `think` с заголовком «Subagent explore: …» без `_meta.codelab.subagent`
- **THEN** `SessionView.subagents` пуст

### Requirement: Отмена по признаку агента
Запись вызова SHALL хранить признак агента `_meta.codelab.outcome` из последнего кадра вызова (`tool_call` или `tool_call_update`), где признак был: кадр с признаком заменяет прежнее значение, кадр без признака (в том числе повтор `tool_call` в реплее и поздний неитоговый `pending`/`in_progress`) его не снимает, снимает только кадр с итоговым статусом `completed` (design.md change `add-subagents-and-tasks`, D41, п. 1). `ToolCallView.status` SHALL быть `cancelled`, если статус вызова — `failed`, а сохранённый признак — `"cancelled"`, у вызова любого инструмента, вживую и в реплее `session/load`. Так вызов, отменённый в прошлом ходе, после загрузки сессии показывается так же, как вживую (agent-workbench-ui «Отменяемый ход в workbench»). Другие значения `outcome` (`rejected`, `interrupted`, неизвестные), его отсутствие и неверная форма (не строка) SHALL оставлять `failed`. Статус вызова признак не меняет: он сливается из кадров по общим правилам. Пометка вызова, отменённого самим клиентом (`cancelTurn`), SHALL работать как прежде: признак агента её дополняет, а не заменяет.

#### Scenario: Отменённый субагент после загрузки
- **WHEN** `session/load` проигрывает `tool_call` вызова `agent` со `status: failed` и `_meta.codelab: {"outcome": "cancelled", "subagent": {"id": "sub_a1", "type": "explore", "summary": {"toolCalls": 2, "tokens": {"input": 900, "output": 100}, "durationMs": 4000}}}`
- **THEN** `ToolCallView.status` — `cancelled`, `subagentSummary` разобран; строка панели Agents этого вызова — `cancelled`

#### Scenario: Отмена не клиентом вживую
- **WHEN** во время хода, который клиент не отменял, приходит `tool_call_update` вызова `exec` со `status: failed` и `_meta.codelab.outcome: "cancelled"`
- **THEN** `ToolCallView.status` — `cancelled`

#### Scenario: Кадр без признака не снимает отмену
- **WHEN** приходит `tool_call_update` вызова `agent` со `status: failed` и `_meta.codelab.outcome: "cancelled"`, затем `tool_call_update` того же вызова со `status: failed` без `_meta.codelab.outcome`
- **THEN** `ToolCallView.status` — `cancelled`

#### Scenario: Итоговый completed снимает признак
- **WHEN** после кадра со `status: failed` и `_meta.codelab.outcome: "cancelled"` приходит кадр того же вызова со `status: completed`
- **THEN** `ToolCallView.status` — `succeeded`, признак `outcome` записи снят

#### Scenario: Другие исходы остаются Failed
- **WHEN** реплей отдаёт два вызова `failed`: один с `_meta.codelab.outcome: "interrupted"`, другой с `"rejected"`, и третий — с `outcome: 5`
- **THEN** у всех трёх `ToolCallView.status` — `failed`, ошибки обработки нет

### Requirement: Usage сессии
`SessionView` SHALL содержать `usage` (`UsageView`) — usage и стоимость последнего хода и сессии и заполнение контекста по уведомлениям `_codelab/session/usage` (design.md change `add-usage-extension`, D2, D6–D9). Разбор формы SHALL жить в одном месте пакета (`UsageDecoder`); остальная модель от формы на проводе не зависит. Kit SHALL NOT суммировать ходы и оценивать окно модели сам: все значения берутся из последнего применённого снимка.

Состояния `UsageView.support`:
- `unknown` — агент не объявил `usage` и снимков не было; клиенты показывают «неизвестно», а не нули (VIEW-6);
- `awaiting` — агент объявил `usage`, снимков ещё нет;
- `reported` — применён хотя бы один снимок.

Свёртка SHALL подчиняться правилам:
- снимок применяется, только если его `seq` больше последнего применённого для этой сессии в текущем поколении соединения; равный или меньший — отбрасывается с записью DEBUG `usage.stale` (`session_id`, `seq`, `last_seq`, `connection_generation`);
- смена поколения соединения (переподключение, перезапуск агента) и `session/load` SHALL сбрасывать `usage` сессии в `awaiting` или `unknown` по объявлению нового соединения; сброс при `session/load` SHALL происходить в начале загрузки, до отправки запроса, а не по ответу: снимок `trigger: "load"`, который агент шлёт после ответа (change `add-usage-ledger`, D8, D10), не стирается, в каком бы порядке kit ни обработал ответ и уведомление;
- снимок для сессии, загрузка которой идёт, но которой ещё нет в рабочем пространстве, SHALL ждать её регистрации: kit хранит последний по `seq` такой снимок и применяет его при регистрации сессии, а при сбое загрузки отбрасывает с записью DEBUG `usage.unknown_session`;
- `trigger` `load` SHALL разбираться как известный повод (`UsageTrigger.load`): снимок без `turnId`, меняет `session` и `context`, `lastTurn` не меняет;
- каждый снимок с `turnId` заменяет `lastTurn` агрегатом `turn` (тот же `turnId` — ход идёт); снимок без `turnId` (`compaction`) `lastTurn` не меняет и меняет только `session` и `context`; новый `turnId` без разобранного `turn` — `lastTurn` пуст;
- деньги SHALL храниться в целых микроединицах (`Money.micros`) с валютой; строка `cost` разбирается без `double`; целая часть — не более 9 цифр (не более `999999999.999999`), чтобы микроединицы оставались точным целым и на web; неверная строка, большее значение или `cost` без `currency` — стоимость отсутствует (цена неизвестна), предупреждение `usage.decode_failed` с `reason: wrong_format` для неверной строки и большего значения;
- `currency` SHALL приниматься только как код ISO 4217 вида `^[A-Z]{3}$`; иная строка — поле неверно: стоимостей снимка нет, как у `cost` без `currency`, предупреждение `usage.decode_failed` с `field: currency`, `reason: wrong_format`; токены и контекст снимка применяются (решение пользователя 2026-11-16 по ревью итерации 3, design.md, D9, D23 Т9 п. 5);
- причины `partial` переводятся в множество известных значений (`noUsage`, `noPrice`, `beforeLoad`); незнакомые строки отбрасываются;
- `context.fraction` SHALL быть `null` без `size` или при `size == 0`; `context.compactionSoon` SHALL быть `true` только при известном `compactAt` и `used ≥ 0.9 × compactAt` (design.md, D11; решение пользователя Q3 (б)) и SHALL считаться без переполнения при больших значениях (D22);
- не разобрались обязательные поля (`sessionId`, `seq`, `trigger`, `session.tokens`) — снимок отбрасывается целиком; необязательное поле неверного типа — поле отсутствует; в обоих случаях — предупреждение `usage.decode_failed` (`session_id`, `field`, `reason`, `connection_generation`; не чаще раза на сессию и поле) без payload, исключения нет;
- снимок для сессии, которой нет в рабочем пространстве, отбрасывается с записью DEBUG `usage.unknown_session` (`session_id`, `connection_generation`).

Публикация `SessionView` с новым `usage` SHALL идти тем же путём, что и другие изменения сессии (одно изменение — одна ревизия).

#### Scenario: Агент без расширения
- **WHEN** агент не объявил `usage` и не прислал `_codelab/session/usage`
- **THEN** `SessionView.usage.support` — `unknown`, `lastTurn`, `session` и `context` — `null`

#### Scenario: Два хода
- **WHEN** агент присылает снимки двух ходов (`turnId` A, затем B) с суммой сессии в каждом
- **THEN** `lastTurn` — итог хода B, `session` — сумма из последнего снимка, `support` — `reported`

#### Scenario: Дубль и опоздание
- **WHEN** приходят снимки с `seq` 3, 5, затем 4 и снова 5
- **THEN** применены только 3 и 5, `lastSeq` — 5

#### Scenario: Деньги без накопления ошибки
- **WHEN** 1 000 снимков подряд несут `session.cost`, растущую на `"0.000001"`
- **THEN** `session.cost.micros` последнего снимка равно значению из его строки точно

#### Scenario: Валюта не ISO 4217
- **WHEN** снимок несёт `session.cost` `"1.2"` и `currency` `"usd"`, `"US$"` или `"\u001b[31m"`
- **THEN** снимок применён с токенами и контекстом, `session.cost` — `null`, записано одно предупреждение `usage.decode_failed` с `field: currency` и `reason: wrong_format`; с `currency` `"EUR"` — `session.cost.micros` `1200000` и `currency` `EUR`

#### Scenario: Неверный тип поля
- **WHEN** снимок содержит `context: {"used": "many", "size": 200000}`
- **THEN** снимок применён без `context`, записано одно предупреждение `usage.decode_failed`, исключения нет

#### Scenario: Скорое сжатие
- **WHEN** снимок несёт `context: {"used": 168000, "size": 200000, "compactAt": 183616}`, затем `context: {"used": 168000, "size": 200000}`
- **THEN** `compactionSoon` сначала `true`, затем `false`

#### Scenario: Причины неполноты
- **WHEN** `session.partial` — `["beforeLoad", "future"]`
- **THEN** `session.partial` в `UsageView` — `{beforeLoad}`

#### Scenario: Переподключение
- **WHEN** после применённого снимка с `seq` 9 соединение переподключается, и новый агент присылает снимок с `seq` 1
- **THEN** снимок с `seq` 1 применён

#### Scenario: Снимок load после загрузки
- **WHEN** открытую в рабочем пространстве сессию загружают заново, агент отвечает на `session/load` и сразу присылает снимок `trigger: "load"` с суммой сессии, а kit обрабатывает уведомление раньше обновления сессии по ответу
- **THEN** после загрузки `support` — `reported`, `session` — сумма снимка, `lastTurn` — `null`; снимок не стёрт сбросом загрузки (`session_usage_test.dart`; change `add-usage-ledger`, D10)

#### Scenario: Снимок load до регистрации сессии
- **WHEN** сессию из списка (её нет среди открытых) загружают впервые, и снимок `trigger: "load"` обработан до регистрации сессии в рабочем пространстве
- **THEN** после регистрации `session` — сумма этого снимка; записи `usage.unknown_session` нет

#### Scenario: Сорвавшаяся загрузка открытой сессии
- **WHEN** у открытой сессии `usage` — `reported`, и её повторный `session/load` завершился ошибкой
- **THEN** `usage` остаётся сброшенным (`awaiting` или `unknown`) до следующего снимка; прежние числа не восстанавливаются

#### Scenario: Загрузка сорвалась
- **WHEN** снимок пришёл для загружаемой сессии, а `session/load` завершился ошибкой
- **THEN** снимок отброшен с записью DEBUG `usage.unknown_session`, состояние рабочего пространства не меняется

### Requirement: Журнал usage сессии в клиенте
`SessionView` SHALL содержать `usageLedger` — состояние журнала usage сессии, полученного запросом `_codelab/session/usage/ledger` (design.md change `add-usage-ledger`, D6, D10). Состояние — закрытая иерархия: `unavailable` (агент не объявил `usageLedger`), `idle` (объявил, журнал не запрашивали), `loading` (с предыдущим журналом, если был), `loaded` (журнал), `failed` (причина `UsageLedgerFailure(kind, code)` с видами `agentError`, `decode`, `request` и предыдущий журнал, если был). Модель журнала — `UsageLedgerView` с `seq` (может быть `0` — снимков не было), `turns`, `turnCount` и `total` типа `UsageTotals`.

`ClientWorkspace.refreshUsageLedger(sessionId, {rebuild = false})` SHALL:
- для сессии, которой нет в рабочем пространстве, завершаться `Future.error(ClientWorkspaceException)`, как другие операции `ClientWorkspace` с неизвестным id;
- без объявленного `usageLedger` не отправлять запрос и оставлять `unavailable`;
- перед отправкой слитого следующего запроса заново проверять объявление `usageLedger`, `dispose` рабочего пространства, эпоху сессии и поколение соединения;
- держать на сессию не больше одного запроса в полёте; вызовы во время полёта сливаются в один следующий запрос, `rebuild` в слиянии побеждает;
- применять ответ, только если с момента отправки не сменились поколение соединения и поколение загрузки сессии; иначе отбрасывать с записью DEBUG `usage.ledger.stale` — в том числе ошибку, которой ядро завершило запрос при замене транспорта: состояние тогда `idle`, а не `failed`;
- при ошибке JSON-RPC переходить в `failed` с кодом ошибки и записью WARNING `usage.ledger.failed {session_id, code}`.

Переподключение и `session/load` SHALL сбрасывать `usageLedger` в `idle` или `unavailable` по объявлению соединения. Kit НЕ SHALL складывать журнал со снимками `_codelab/session/usage` и сам ничего не суммирует; решение, когда обновлять журнал, принимает хост, сравнивая `usageLedger.seq` с `usage.lastSeq`.

Разбор ответа SHALL жить в одном месте пакета (`UsageLedgerDecoder`) и SHALL использовать те же правила денег, валюты и причин, что `UsageDecoder` (требование «Usage сессии»): микроединицы без `double`, `currency` по `^[A-Z]{3}$`, незнакомые причины отбрасываются. Не разобрались `sessionId`, `seq` или `total.tokens` — ответ отбрасывается, состояние `failed` с причиной `decode`; ход или шаг без обязательных полей пропускается; необязательное поле неверного типа отсутствует; в каждом случае — WARNING `usage.ledger.decode_failed {session_id, field, reason}` (`reason`: `required` для обязательных полей, `wrong_format` для денег и валюты) не чаще раза на сессию и поле (ограничение держит `ClientWorkspace`), без payload, исключения нет. Шаг SHALL сохранять `toolCallIds`, чтобы хост подписывал шаг по транскрипту. Ответ, который не JSON-объект, и ответ с `sessionId`, отличным от запрошенного, SHALL давать `failed` вида `decode`; несовпадение — с WARNING `usage.ledger.decode_failed {field: sessionId, reason: mismatch}`. Строки агента (`title`, `model`, `ledger.reason`, `toolCallIds`) SHALL очищаться от управляющих символов C0/C1 и ограничиваться длиной (`title` — 64 руны).

#### Scenario: Журнал неизвестной сессии
- **WHEN** хост вызывает `refreshUsageLedger` для id, которого нет в рабочем пространстве
- **THEN** операция завершается `ClientWorkspaceException`, запрос не отправлен

#### Scenario: Чужой sessionId в ответе
- **WHEN** запрос ушёл для сессии A, а ответ несёт `sessionId` B
- **THEN** `usageLedger` сессии A — `failed` вида `decode`, записан WARNING `usage.ledger.decode_failed` с `field: sessionId`, `reason: mismatch`

#### Scenario: Управляющие символы в подписи
- **WHEN** `title` хода содержит `\u001b[31m` и длиннее 64 рун
- **THEN** в `UsageLedgerView` подпись без управляющих символов и не длиннее 64 рун

#### Scenario: Агент без журнала
- **WHEN** агент не объявил `usageLedger`, и хост вызывает `refreshUsageLedger`
- **THEN** запрос не отправлен, `usageLedger` — `unavailable`

#### Scenario: Журнал загружен
- **WHEN** агент объявил `usageLedger` и отвечает журналом с двумя ходами
- **THEN** `usageLedger` — `loaded`, у журнала `seq` ответа, два хода с шагами, `toolCallIds` шагов, суммы в микроединицах (фикстура `acp/usage-ledger-request`, клиентская роль)

#### Scenario: Слияние вызовов
- **WHEN** во время запроса хост вызывает `refreshUsageLedger` дважды, второй раз с `rebuild: true`
- **THEN** после ответа на первый уходит ровно один запрос с `rebuild: true`

#### Scenario: Ответ старого соединения
- **WHEN** запрос ушёл, соединение переподключилось, затем пришёл ответ
- **THEN** ответ не применён, записан DEBUG `usage.ledger.stale`, `usageLedger` — `idle`

#### Scenario: Ошибка агента
- **WHEN** агент отвечает `-32002`
- **THEN** `usageLedger` — `failed` с кодом `-32002` и предыдущим журналом, если он был

### Requirement: Бюджет хода в usage сессии
`UsageView` SHALL содержать `budget` — прогресс бюджета хода из поля `budget` снимков `_codelab/session/usage` (design.md change `add-desktop-usage-pane`, D9). В нём необязательные подполя `steps`, `tokens` (`used`, `limit` — целые), `cost` (израсходованное — `Money?`, лимит — `Money`) и `duration` (`usedMs`, `limitMs` — целые), а также `turnId` снимка, `receivedAt` — момент применения снимка по часам рабочего пространства (`ClientWorkspace(clock: …)`) — и признак `ended` «итог хода»: бюджет взят из снимка с поводом `turn` (решение пользователя Q11 (а)). Свёртка SHALL оставаться чистой: момент применения передаёт вызывающий, а kit НЕ SHALL вызывать `DateTime.now` в проекции.

Разбор SHALL жить в `UsageDecoder` по общим правилам снимка:
- `budget` SHALL читаться только у снимка с `turnId`; у снимка без `turnId`, в том числе с `turnId` неверного типа, поле `budget` НЕ SHALL читаться и НЕ SHALL давать предупреждений `budget*`;
- `steps`, `tokens`, `duration` — объект с обоими целыми ≥ 0;
- `cost.limit` обязателен, `cost.used` необязателен; оба разбираются правилом `cost` (микроединицы без `double`, целая часть не длиннее 9 цифр). Отсутствующий `used` — цена неизвестна, `used` или `limit` не по формату — подполя `cost` нет;
- `budget.cost` без `currency` SHALL отсутствовать с общим предупреждением `currency` (`required_with_cost`);
- неверное подполе — подполя нет, WARNING `usage.decode_failed` с `field: budget.<подполе>`; `budget` не объект — поля нет, `field: budget`. Предупреждения подчиняются правилу «не чаще раза на сессию и поле», снимок применяется;
- незнакомые ключи внутри `budget` и его подполей SHALL игнорироваться без предупреждения;
- `budget` без единого разобранного известного подполя SHALL считаться отсутствующим в снимке.

Свёртка: снимок с `turnId` и `budget` SHALL заменять `budget`, `ended` SHALL быть истинен только у снимка с поводом `turn`; снимок с тем же `turnId` без `budget` его не меняет, кроме снимка `turn`, который SHALL ставить `ended` при прежних числах; `ended` SHALL оставаться истинным для того же `turnId`: снимок `step` того же хода после итогового `turn` обновляет числа и `receivedAt`, но `ended` не снимает; снимок с новым `turnId` без `budget` SHALL делать его `null`; снимок без `turnId` (`compaction`, `compactionDiscarded`, `load`, незнакомый повод) его не меняет. Правила `seq`, поколения соединения, сброса при переподключении и `session/load` — те же, что у остального `usage` (требование «Usage сессии»): сброс SHALL делать `budget` равным `null`. Kit НЕ SHALL досчитывать время сам: оценку между снимками делает хост по `receivedAt`.

#### Scenario: Бюджет из снимка шага
- **WHEN** снимок `step` хода A несёт `budget` с `tokens {used 92000, limit 200000}` и `cost {used "0.41", limit "0.5"}` при `currency` `USD`, а часы рабочего пространства показывают T
- **THEN** `usage.budget.tokens` — 92000 из 200000, `cost.used.micros` — 410000, `cost.limit.micros` — 500000, `turnId` — A, `receivedAt` — T, `ended` ложен, а `steps` и `duration` отсутствуют

#### Scenario: Итог хода
- **WHEN** после снимков `step` хода A с `budget` приходит снимок `turn` хода A с `budget`
- **THEN** `usage.budget` — числа снимка `turn`, `ended` истинен; следующий снимок `step` хода B с `budget` делает `ended` ложным

#### Scenario: Шаг после итога того же хода
- **WHEN** после снимка `turn` хода A с `budget` приходит снимок `step` хода A с `budget` (нарушение порядка агентом)
- **THEN** `usage.budget` — числа и `receivedAt` снимка `step`, `ended` остаётся истинным

#### Scenario: Бюджет без хода не читается
- **WHEN** снимок без `turnId` или с `turnId` неверного типа несёт `budget` — строку
- **THEN** `usage.budget` не меняется, предупреждений с `field: budget` нет (у `turnId` неверного типа — только его предупреждение `turnId`)

#### Scenario: Цена неизвестна
- **WHEN** `budget.cost` — `{"limit": "0.5"}` без `used`, `currency` — `USD`
- **THEN** `usage.budget.cost.used` — `null`, `cost.limit.micros` — 500000, предупреждений нет

#### Scenario: Тот же ход без бюджета
- **WHEN** после снимка `step` хода A с `budget` приходит снимок хода A без `budget`
- **THEN** `usage.budget` и его `receivedAt` не меняются

#### Scenario: Новый ход без лимитов
- **WHEN** после хода A с `budget` приходит снимок `step` хода B без `budget`
- **THEN** `usage.budget` — `null`

#### Scenario: Снимки без хода
- **WHEN** после снимка `turn` хода A с `budget` приходят снимки `compaction` и `compactionDiscarded`
- **THEN** `usage.budget` не меняется

#### Scenario: Неверное подполе
- **WHEN** `budget.tokens` — `{"used": "many", "limit": 200000}`
- **THEN** снимок применён, `usage.budget.tokens` — `null`, остальные подполя разобраны, записано одно предупреждение `usage.decode_failed` с `field: budget.tokens`

#### Scenario: Бюджет не объект
- **WHEN** `budget` — строка
- **THEN** снимок применён как снимок без `budget`, записано одно предупреждение `usage.decode_failed` с `field: budget`

#### Scenario: Сброс при переподключении и загрузке
- **WHEN** у сессии есть `usage.budget`, и рабочее пространство переподключается к агенту или начинает `session/load` этой сессии
- **THEN** `usage.budget` — `null` вместе со сбросом остального `usage`

### Requirement: Точная запись суммы usage
Kit SHALL предоставлять `formatUsageMoneyExact(Money)` — точную десятичную строку суммы для экспорта (design.md change `add-desktop-usage-pane`, D5): целая часть, точка и до 6 знаков без хвостовых нулей, ноль — `0`, без символа и кода валюты, без `double`. Строка SHALL совпадать с формой `cost` на проводе (D9 change `add-usage-extension`), так что разбор строки даёт исходные микроединицы.

#### Scenario: Обратимость
- **WHEN** `Money.micros` — 2260000, 41, 0 и 999999999999999
- **THEN** строки — `2.26`, `0.000041`, `0` и `999999999.999999`, и разбор каждой строки правилом `cost` даёт исходные микроединицы

