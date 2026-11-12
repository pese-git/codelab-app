## REMOVED Requirements

### Requirement: Проверка профиля без сессии
**Reason**: «Test connection» удалена из app по решению пользователя («Убрать совсем»): после change `require-project-folder` агент стартует сам по «Use» и триггерам рабочего места, и старт показывает то же, что проба `initialize`. Других потребителей у `ProfileProbe` нет (design.md change `remove-test-connection`, D1, D2).
**Migration**: `ProfileProbe`, `ProbeCancellation`, `ProbeFailureClassifier`, `ProfileProbeOutcome` с вариантами `Reachable`, `Unauthorized`, `Unreachable`, `TimedOut`, `NotAcp`, `CommandNotFound`, `Unsupported` и `UnreachableReason` удаляются из `codelab_client_core` без замены. Профиль проверяется подключением `ClientWorkspace` (`ensureAgent`, `connect`, `reconnect`); отказ по токену описывает `describeConnectFailureByToken`. Формат `profiles.json` не меняется.

### Requirement: Проверка нового токена до записи
**Reason**: Новый токен проверялся только пробой «Test connection», которая удалена (design.md change `remove-test-connection`, D2). Единственный потребитель подмены источника секретов — `ProfileProbe.probe(token:)`.
**Migration**: `SecretRebindableResolver` и `ConfigTransportResolver.withSecrets` удаляются. Новый токен записывается `ProfileCommitter` в порядке «секрет → профиль» (требование «Запись профиля с новым токеном», без изменений); неверный токен виден при старте агента текстом `the agent rejected the token (HTTP <код>)`.

## MODIFIED Requirements

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

