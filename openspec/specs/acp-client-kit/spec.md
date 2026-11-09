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
`TranscriptProjector` SHALL строить `TranscriptItem` сессии инкрементально по новым `session/update`: дельты `agent_message_chunk` и `agent_thought_chunk` подряд дописываются в один элемент того же вида, любое другое обновление закрывает отрезок; `tool_call` с известным `toolCallId` обновляет существующий элемент, а не добавляет второй; статус и одобрение вызова берутся из read-модели хода ядра клиента; запрос разрешения привязывается к `ToolCallItem` по `toolCallId`, а для вызова без `tool_call` — к элементу вызова в конце хода; сорвавшийся ход добавляет `NoticeItem` вида `error` с типизированным сбоем хода (`PromptFailure`), завершённый ход без вывода агента — `NoticeItem` вида `emptyTurn`; ход, завершённый с `stopReason` `max_tokens`, `max_turn_requests` или `refusal`, — `NoticeItem` вида `turnStopped` всегда, даже при выводе агента, и вместо `emptyTurn` у хода без вывода (решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q33, D27). Заметка `turnStopped` SHALL строиться только по `stopReason` ответа на `session/prompt`: у ходов реплея `session/load` его нет, и заметки у них нет (Q36). Тексты `turnStopped`: `max_tokens` — `The model reached its token limit, so the turn ended.`; `max_turn_requests` — `The turn reached the limit of model requests.`; `refusal` — `The agent refused to continue.`. Повторно обработанный снимок сессии SHALL быть no-op. Для любой последовательности обновлений результат инкрементальной проекции SHALL совпадать с проекцией с нуля по всем ходам сессии.

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
`SessionView.pendingApprovals` SHALL содержать запросы `session/request_permission` с `toolCallId`, заголовком, видом, сырыми аргументами и вариантами ответа по `kind`. `PendingApprovalView.critical` SHALL быть `true` только тогда, когда `_meta.codelab.critical` запроса или его `toolCall` равно `true` (Dart-агент помечает так опасные команды в `toolCall`); другое значение или его отсутствие SHALL давать `false`. `SessionHandle.respond` SHALL отправлять выбранный `optionId` только в запрос этой сессии; ответ в одной сессии НЕ SHALL менять одобрения другой.

#### Scenario: Ответ в фоновой сессии
- **WHEN** у сессий A и B ожидают одобрения, и пользователь отвечает в B
- **THEN** одобрение A остаётся ожидающим

#### Scenario: Критичный запрос
- **WHEN** агент присылает `session/request_permission` с `toolCall._meta: {"codelab": {"critical": true}}` или с `_meta: {"codelab": {"critical": true}}` у запроса
- **THEN** у соответствующего `PendingApprovalView` `critical == true`, у запроса без этого поля или со значением, отличным от `true`, — `false`

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
- `JsonFileRecentProjectsStore`;
- `classifyProbeFailure` — перевод ошибок IO-транспортов в исход `ProfileProbe` только по типам и кодам ошибок, без разбора текста:
  - отсутствующая команда (`ProcessException` с errno `ENOENT`) — `CommandNotFound`;
  - `AcpWebSocketHandshakeRejected` со статусом 401 или 403 — `Unauthorized`, с другим статусом — `Unreachable` с причиной `httpStatus` и этим `statusCode`;
  - `SocketException`, чей `osError.errorCode` — код «соединение отклонено» текущей платформы, — `Unreachable(connectionRefused)`; код «хост не найден» (ошибка разрешения имени) — `Unreachable(hostNotFound)`; коды берутся из таблицы по платформе;
  - `HandshakeException` или `TlsException` — `Unreachable(tlsFailed)`;
  - остальное — `Unreachable(unknown)`.

Реализации на Flutter-плагинах (`SharedPreferencesRecentProjectsStore`, `FileSelectorProjectFolderPicker`) SHALL оставаться в app. `ProfileStore.remove(id)` SHALL удалять профиль с этим `id` и возвращать `true`, а без такого профиля — возвращать `false` и не менять файл. `JsonFileProfileStore` SHALL записывать `profiles.json` через уникальный временный файл в том же каталоге, сброшенный на диск (`flush`) до атомарного переименования: прерванная запись НЕ SHALL оставлять под именем `profiles.json` пустой или неполный файл (design.md change `add-app-settings-shell`, D7).

#### Scenario: Профили сохраняются в JSON
- **WHEN** `JsonFileProfileStore` сохраняет профиль `WebSocketProfile` и читает его заново
- **THEN** профиль восстановлен полностью, а файл не содержит значения токена

#### Scenario: Удаление профиля
- **WHEN** в `JsonFileProfileStore` сохранены профили `remote` и `local`, и вызывается `remove('remote')`
- **THEN** результат — `true`, а новое хранилище на том же файле читает только `local`

#### Scenario: Классификация отсутствующей команды
- **WHEN** `StdioAcpTransport` с командой `/nonexistent/agent` не стартует, и ошибка передана `classifyProbeFailure`
- **THEN** результат — `CommandNotFound`

#### Scenario: Закрытый порт
- **WHEN** `WebSocketAcpTransport` подключается к закрытому порту loopback, и ошибка передана `classifyProbeFailure`
- **THEN** результат — `Unreachable` с причиной `connectionRefused`

#### Scenario: Хост не найден
- **WHEN** `classifyProbeFailure` получает `SocketException` разрешения имени с кодом «хост не найден» текущей платформы
- **THEN** результат — `Unreachable` с причиной `hostNotFound`

#### Scenario: Сбой TLS
- **WHEN** `WebSocketAcpTransport` подключается по `wss://` к серверу на loopback, который не говорит TLS, и ошибка передана `classifyProbeFailure`
- **THEN** результат — `Unreachable` с причиной `tlsFailed`

#### Scenario: Отказ рукопожатия по статусу
- **WHEN** WebSocket-сервер на loopback отвечает на рукопожатие статусом 401, затем 403, затем 500
- **THEN** результаты — `Unauthorized`, `Unauthorized` и `Unreachable` с причиной `httpStatus` и `statusCode` 500

#### Scenario: Нераспознанная ошибка
- **WHEN** `classifyProbeFailure` получает исключение незнакомого типа, чей текст содержит `connection refused` и `401`
- **THEN** результат — `Unreachable` с причиной `unknown`: текст ошибки не влияет на классификацию

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
Kit SHALL сохранять снимок рабочего пространства через порт `WorkspaceSnapshotStore`: версия формата, проект, активная сессия и открытые сессии (`id`, `cwd`). Снимок НЕ SHALL содержать курсоры `session/list`, транскрипты, очереди промптов, профили и секреты. Запись SHALL выполняться после успешных создания, загрузки и активации сессии и смены проекта; записи НЕ SHALL накладываться — изменения во время записи SHALL склеиваться в одну следующую запись с последним снимком, а закрытие рабочего пространства SHALL дожидаться последней записи; ошибка записи SHALL быть диагностикой, а не отказом операции. До чтения снимка при старте хоста kit НЕ SHALL писать снимок. При старте хоста kit SHALL читать снимок и отдавать проект хосту; битый снимок или неизвестная версия SHALL удаляться с диагностикой. При первом успешном подключении в запуске kit SHALL восстанавливать сессии, если проект с тех пор не сменён; выбор другого проекта до подключения SHALL отменять восстановление: сессии снимка SHALL появляться в списке, активная сессия SHALL загружаться через `session/load`, если агент объявил `loadSession`. Агент без `loadSession` или ошибка загрузки активной сессии SHALL приводить к `session/new` в проекте снимка с уведомлением в транскрипте новой сессии; при ошибке загрузки id SHALL удаляться из снимка. Восстановление НЕ SHALL отправлять промпты и ответы на одобрения.

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

### Requirement: Проверка профиля без сессии
`ProfileProbe.probe(profile, {timeout})` SHALL:
1. открывать транспорт тем же набором `TransportResolver`, что `ClientWorkspace`;
2. отправлять ровно один `initialize` через временный `AcpClientApplication`, не связанный с соединением рабочего пространства;
3. закрывать транспорт по ответу, ошибке, таймауту (по умолчанию 10 s) и отмене.

`session/new` и другие запросы сессии проверка НЕ SHALL отправлять (SETUP-20).

Исход — `ProfileProbeOutcome`:
- `Reachable(latency, agentName, agentVersion)`;
- `Unauthorized`;
- `Unreachable(message, {reason = UnreachableReason.unknown, statusCode})` — `reason` типа `UnreachableReason` (enum: `connectionRefused`, `hostNotFound`, `tlsFailed`, `httpStatus`, `unknown`); `statusCode` — HTTP-статус отказа рукопожатия WebSocket (не 401/403) — SHALL быть задан только при `httpStatus`;
- `TimedOut`;
- `NotAcp`;
- `CommandNotFound`;
- `Unsupported`.

`message` SHALL проходить `describeFailure` и предназначен только для журнала и диагностики: хосты НЕ SHALL строить из него текст для пользователя (design.md change `add-app-settings-shell`, D12). Ошибки IO-транспорта SHALL классифицироваться функцией, которую передаёт хост (`classifyProbeFailure` из `codelab_client_io`). Причина SHALL определяться только по типам и кодам ошибок; если её нельзя установить по типу ошибки, исход SHALL быть `Unreachable` с причиной `unknown`; по тексту исход и причина НЕ SHALL угадываться. Ошибка, которую классификатор хоста не распознал или которого нет, SHALL давать `Unreachable` с причиной `unknown`. Отменённая проверка SHALL закрывать транспорт и завершаться без исхода для вызывающего.

#### Scenario: Успешная проверка
- **WHEN** проверяется stdio-профиль scripted-агента из `codelab_acp_testing`
- **THEN** исход — `Reachable` с `agentInfo` агента, агент получил только `initialize`, процесс завершён

#### Scenario: Молчание агента
- **WHEN** агент не отвечает на `initialize` за `timeout`
- **THEN** исход — `TimedOut`, транспорт закрыт

#### Scenario: Нет команды
- **WHEN** проверяется stdio-профиль с командой `/nonexistent/agent` и классификатором `codelab_client_io`
- **THEN** исход — `CommandNotFound`

#### Scenario: Отмена
- **WHEN** проверка отменяется до ответа на `initialize`
- **THEN** транспорт закрыт, и вызывающий не получает исход

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

### Requirement: Проверка нового токена до записи
`ProfileProbe.probe(profile, token: SecretText?)` (профиль, построенный из черновика `toProfile`) SHALL передавать транспорту значение нового токена из памяти через одноразовый источник, не записывая его в хранилище (§12.4.9, шаг 5; design.md, D13). Для «Use stored secret» проверка SHALL читать секрет тем же `ProfileSecretSource`, что подключение. Остальные правила проверки (только `initialize`, закрытие транспорта, отмена) SHALL оставаться прежними (требование «Проверка профиля без сессии»).

Пустое значение нового токена SHALL давать явный отказ проверки без открытия транспорта, а не проверку без токена. Резолвер, который не умеет подставить источник секрета (`SecretRebindableResolver.withSecrets`), SHALL давать исход `Unsupported`.

#### Scenario: Пустой новый токен
- **WHEN** проверяется WebSocket-черновик с «Store a new token» и пустым значением
- **THEN** проверка отказывает явно, транспорт не открыт, сервер не получил запроса

#### Scenario: Новый токен проверяется без записи
- **WHEN** черновик WebSocket-профиля с «Store a new token» `t` проверяется на `FakeAcpTransport`, требующем Bearer `t`
- **THEN** исход `Reachable`, транспорт получил заголовок с `t`, `ProfileSecrets.store` не вызывался

### Requirement: Отказ рукопожатия из-за токена
Kit SHALL определять отказ WebSocket-агента из-за токена одной web-безопасной функцией (`codelab_client_core/lib/src/connection/token_rejection.dart`; design.md, D25):
- `tokenRejectionStatus(error)` SHALL возвращать 401 или 403, найденные по цепочке `cause` ошибки (`AcpClientApplicationException` → `AcpTransportException` → `AcpWebSocketHandshakeRejected`) на ограниченную глубину, и `null` для любого другого статуса и ошибки. Текст ошибок НЕ SHALL разбираться;
- `describeTokenRejection(error, {tokenSent})` SHALL возвращать `the agent rejected the token (HTTP <код>)` при `tokenSent` и `the agent requires a token (HTTP <код>)` без него, а для прочих ошибок — `null`;
- `profileTokenSent(profile, SecretSource?)` SHALL отвечать, был ли токен отправлен, не читая значения: для `ProfileSecretSource` с `secret:` — через `isSet` порта, для `env:` — по наличию непустой переменной;
- `describeConnectFailureByToken(error, profile, SecretSource?)` SHALL сначала вычислять `tokenRejectionStatus(error)` и только при 401 или 403 обращаться к `profileTokenSent`; для прочих ошибок источник секретов НЕ SHALL вызываться, а результат — `null`. Результат — строчный текст `describeTokenRejection` без точки; хосты оформляют его сами.

`classifyProbeFailure` (`codelab_client_io`) SHALL определять `Unauthorized` через `tokenRejectionStatus`: таблица статусов одна для проверки профиля и подключения. Тексты согласованы с исходами проверки D12 change `add-app-settings-shell`.

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

