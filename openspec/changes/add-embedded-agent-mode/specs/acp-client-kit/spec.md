## MODIFIED Requirements

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
