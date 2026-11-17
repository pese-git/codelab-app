## ADDED Requirements

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
`ProfileTokenRef.parse(ref)` SHALL понимать `WebSocketProfile.tokenRef` вида `env:<NAME>` для любой переменной с допустимым именем как ссылку на переменную окружения процесса. Любую другую ссылку он SHALL возвращать как неподдерживаемую в этой версии (design.md change `add-app-settings-shell`, D15).

`ProfileSecretSource(environment)` SHALL реализовывать `SecretSource` по этому правилу. Для пустой или отсутствующей переменной и для неподдерживаемой ссылки результат SHALL быть `null`, и подключение идёт без токена. Источник SHALL использоваться и app, и CLI.

#### Scenario: Формы ссылки
- **WHEN** `ProfileSecretSource` с окружением `CODELAB_AGENT_TOKEN=t1`, `DEVBOX_TOKEN=t2`, `EMPTY=` читает `env:CODELAB_AGENT_TOKEN`, `env:DEVBOX_TOKEN`, `env:EMPTY`, `env:MISSING` и `codelab/profiles/dev/token`
- **THEN** результаты — `t1`, `t2`, `null`, `null` и `null`, а `ProfileTokenRef.parse('codelab/profiles/dev/token')` — неподдерживаемая ссылка

### Requirement: Записи профилей с зарезервированным id
`usableStoredProfiles(profiles)` SHALL отделять от прочитанного списка запись с зарезервированным id `default` (`ignoredDefault`) и возвращать остальные профили в порядке файла. Хосты SHALL выбирать профиль только из отделённого списка и сообщать пользователю о проигнорированной записи; `ProfileStore.load` при этом SHALL возвращать файл как есть. `JsonFileProfileStore.save` SHALL отклонять профиль с id из `reservedProfileIds` `ArgumentError`, не меняя файл. `ProfileStore.remove('default')` SHALL удалять такую запись, как любую другую.

#### Scenario: Старая запись default отделяется
- **WHEN** `ProfileStore.load` возвращает профили `default` и `dev`
- **THEN** `usableStoredProfiles` возвращает только `dev` и признак проигнорированной записи `default`

#### Scenario: Запись default нельзя сохранить, но можно удалить
- **WHEN** `JsonFileProfileStore.save` получает stdio-профиль с id `default`, а затем на файле со старой записью `default` вызывается `remove('default')`
- **THEN** `save` бросает `ArgumentError` и файл не меняется; `remove` возвращает `true`, и запись удалена

## MODIFIED Requirements

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
