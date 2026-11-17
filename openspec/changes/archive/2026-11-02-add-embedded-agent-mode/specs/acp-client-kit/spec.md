## MODIFIED Requirements

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
