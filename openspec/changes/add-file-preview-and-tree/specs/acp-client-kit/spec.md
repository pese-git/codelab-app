## ADDED Requirements

### Requirement: Чтение папки проекта в границах рабочей папки
`codelab_client_core` SHALL объявлять порт `ProjectFiles` (`canonicalRoot`, `list`, `read`) с моделями `ProjectEntry`, `DirectoryListing`, `FilePreview` (`TextPreview`, `BinaryPreview`, `TooLargePreview`) и типизированной ошибкой `ProjectFilesFailure` вида `outsideRoot | notFound | unreadable | invalidPath` в `lib/src/files/`, без `dart:io` и без новых зависимостей. Правила SHALL быть чистыми функциями kit, общими для всех реализаций порта:
- `normalizeRelativePath` — POSIX-путь от корня; `\0`, абсолютный путь или сегмент `..` после нормализации дают `invalidPath`;
- `classifyPreview` — байт NUL в первых 8 КиБ даёт `BinaryPreview`, размер больше `maxBytes` (по умолчанию 1 МиБ) — `TooLargePreview`, иначе `TextPreview` в UTF-8 с заменой неверных байт;
- `isMaybeSecretFileName` — имена `.env*`, `*.pem`, `*.key`, `id_*`; одно правило для браузера файлов и вложений;
- `relativeToRoot` — абсолютный путь места вызова относительно `cwd` сессии или канонического корня; путь вне обоих — `null`.

Записи `DirectoryListing` SHALL идти папками, затем файлами, по имени без учёта регистра; `.git` в них НЕ SHALL попадать (design.md change `add-file-preview-and-tree`, D1–D5, D8).

#### Scenario: Выход из корня через `..`
- **WHEN** `normalizeRelativePath` получает `lib/../../etc/passwd`
- **THEN** результат — ошибка `invalidPath`

#### Scenario: Двоичный файл по содержимому, а не по расширению
- **WHEN** `classifyPreview` получает файл `notes.txt`, в первых 8 КиБ которого есть байт NUL
- **THEN** результат — `BinaryPreview` с размером файла

#### Scenario: Имя файла с секретами
- **WHEN** `isMaybeSecretFileName` проверяет `.env.local`, `server.pem`, `id_ed25519` и `env.dart`
- **THEN** первые три — `true`, `env.dart` — `false`

#### Scenario: Место вызова через другой путь к той же папке
- **WHEN** `relativeToRoot` получает `/private/tmp/w/lib/a.dart` при `cwd` сессии `/tmp/w` и каноническом корне `/private/tmp/w`
- **THEN** результат — `lib/a.dart`

### Requirement: Места вызова с номером строки
`ToolCallView` SHALL нести `locations` — места вызова (`path` и необязательный `line` из ACP `ToolCallLocation`) в порядке прихода; поле `paths` SHALL сохраняться без изменений. Обновление вызова с новыми `locations` SHALL заменять места, как это делает доменная модель. Инкрементальная проекция SHALL совпадать с проекцией с нуля (требование «Инкрементальная проекция транскрипта»). Диапазон строк kit НЕ SHALL выводить: ACP его не определяет (design.md change `add-file-preview-and-tree`, D8).

#### Scenario: Место со строкой
- **WHEN** агент присылает `tool_call` с `locations: [{"path": "/w/lib/a.dart", "line": 42}]`
- **THEN** `ToolCallView.locations` содержит одно место с путём `/w/lib/a.dart` и строкой 42, а `paths` — `["/w/lib/a.dart"]`

#### Scenario: Место без строки
- **WHEN** агент присылает место без `line`
- **THEN** у места в `ToolCallView.locations` строка не задана

## MODIFIED Requirements

### Requirement: IO-адаптеры клиента
`dart:io`-реализации портов клиента SHALL жить в `packages/dart/codelab_client_io`:
- `IoTextFileIo`;
- `IoTerminalProcessRunner`;
- `IoWorkingDirectoryProvider`;
- `IoProjectFiles` — порт `ProjectFiles`: realpath корня, проверка границы по realpath до перечисления и чтения, перечисление одного уровня с лимитом записей, чтение не больше `maxBytes + 1` байт с классификацией `classifyPreview` kit; символическая ссылка с целью вне корня перечисляется как `symlinkOutside` и не раскрывается (design.md change `add-file-preview-and-tree`, D3);
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

#### Scenario: Символическая ссылка наружу
- **WHEN** `IoProjectFiles.list` перечисляет корень временной папки со ссылкой `out` на папку вне корня, а затем вызывается `read(root, 'out/x.txt')`
- **THEN** `out` перечислен как `symlinkOutside`, а чтение даёт `ProjectFilesFailure` вида `outsideRoot`, и файл вне корня не открывается

#### Scenario: Большой файл читается не целиком
- **WHEN** `IoProjectFiles.read` читает файл 3 МиБ с `maxBytes` 1 МиБ
- **THEN** результат — `TooLargePreview` с размером 3 МиБ, а прочитано не больше 1 МиБ + 1 байта
