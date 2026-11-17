## ADDED Requirements

### Requirement: Чтение папки проекта в границах рабочей папки
`codelab_client_core` SHALL объявлять порт `ProjectFiles` (`canonicalRoot`, `list`, `read`) с моделями `ProjectEntry`, `DirectoryListing`, `FilePreview` (`TextPreview`, `BinaryPreview`, `TooLargePreview`) и типизированной ошибкой `ProjectFilesFailure` вида `outsideRoot | notFound | unreadable | invalidPath` в `lib/src/files/`, без `dart:io` и без новых зависимостей. Правила SHALL быть чистыми функциями kit, общими для всех реализаций порта:
- `normalizeRelativePath` — POSIX-путь от корня, проверка лексическая, до обращения к диску и не зависящая от платформы; `\0`, абсолютный путь или `..`, поднимающийся выше корня, дают `invalidPath`, а `..` внутри пути вычисляется (`a/../b` → `b`);
- `classifyPreview` — байт NUL в первых 8 КиБ даёт `BinaryPreview`, размер больше `maxBytes` (по умолчанию 1 МиБ) — `TooLargePreview`, иначе `TextPreview` в UTF-8 с заменой неверных байт;
- `isMaybeSecretFileName` — имена `.env*`, `*.pem`, `*.key`, `id_*` без учёта регистра; одно правило для браузера файлов и вложений;
- `relativeToRoot` — абсолютный путь места вызова относительно `cwd` сессии или канонического корня; путь вне обоих — `null`.

Записи `DirectoryListing` SHALL идти папками, затем файлами, по имени без учёта регистра; `.git` в них НЕ SHALL попадать (design.md change `add-file-preview-and-tree`, D1–D5, D8).

#### Scenario: Выход из корня через `..`
- **WHEN** `normalizeRelativePath` получает `lib/../../etc/passwd`
- **THEN** результат — ошибка `invalidPath`

#### Scenario: `..` внутри пути вычисляется
- **WHEN** `normalizeRelativePath` получает `lib/../README.md`
- **THEN** результат — `README.md`

#### Scenario: Двоичный файл по содержимому, а не по расширению
- **WHEN** `classifyPreview` получает файл `notes.txt`, в первых 8 КиБ которого есть байт NUL
- **THEN** результат — `BinaryPreview` с размером файла

#### Scenario: Имя файла с секретами
- **WHEN** `isMaybeSecretFileName` проверяет `.env.local`, `server.pem`, `id_ed25519` и `env.dart`
- **THEN** первые три — `true`, `env.dart` — `false`

#### Scenario: Имя секрета без учёта регистра
- **WHEN** `isMaybeSecretFileName` проверяет `.ENV`, `Server.PEM` и `ID_RSA`
- **THEN** все три — `true`

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
- `IoProjectFiles` — порт `ProjectFiles`: лексическая проверка вместе со склейкой пути в стиле текущей ОС до обращения к диску (на Windows сегмент с `\` или `:` даёт `invalidPath`); realpath корня; проверка границы по realpath до перечисления и чтения; если цель не разрешается (любая ошибка разрешения), путь проходится от корня без перехода по ссылкам: ссылка, чей realpath не разрешается или разрешается вне корня, либо ближайший разрешимый предок вне корня дают `outsideRoot`, иначе — исходная ошибка (`notFound`, `unreadable`); перечисление одного уровня с лимитом записей, чтение не больше `maxBytes + 1` байт с классификацией `classifyPreview` kit; символическая ссылка с целью вне корня перечисляется как `symlinkOutside` и не раскрывается; битая ссылка, FIFO и сокет перечисляются как `other`; `list` файла и `read` папки дают `unreadable` (design.md change `add-file-preview-and-tree`, D3, Q16);
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

#### Scenario: Символическая ссылка наружу
- **WHEN** `IoProjectFiles.list` перечисляет корень временной папки со ссылкой `out` на папку вне корня, а затем вызывается `read(root, 'out/x.txt')`
- **THEN** `out` перечислен как `symlinkOutside`, а чтение даёт `ProjectFilesFailure` вида `outsideRoot`, и файл вне корня не открывается

#### Scenario: Несуществующий файл за ссылкой наружу
- **WHEN** в корне ссылка `out` на папку вне корня, и `IoProjectFiles.read` читает `out/missing.txt`, которого нет
- **THEN** результат — `ProjectFilesFailure` вида `outsideRoot`, а не `notFound`

#### Scenario: Битая и рабочая ссылки наружу неразличимы
- **WHEN** в корне ссылка `gone` на несуществующий путь вне корня и ссылка `real` на существующий файл вне корня, и `IoProjectFiles.read` читает обе
- **THEN** оба результата — `ProjectFilesFailure` вида `outsideRoot`

#### Scenario: Ошибка разрешения за ссылкой наружу
- **WHEN** за ссылкой `out` на папку вне корня путь `out/file.txt/x` даёт ENOTDIR, путь `out/locked/x` — EACCES, а путь `out/loop/x` — ELOOP
- **THEN** все три чтения дают `ProjectFilesFailure` вида `outsideRoot`

#### Scenario: Ошибка разрешения внутри корня
- **WHEN** внутри корня читаются `lib/missing.dart` (нет файла) и `locked/x` (папка `locked` внутри корня без прав)
- **THEN** результаты — `notFound` и `unreadable` соответственно

#### Scenario: Windows-сегмент отклоняется адаптером
- **WHEN** `IoProjectFiles` со стилем путей Windows получает относительный путь `lib\a.dart` или `C:x`
- **THEN** результат — `ProjectFilesFailure` вида `invalidPath` до обращения к диску

#### Scenario: Перечисление файла и чтение папки
- **WHEN** `IoProjectFiles.list` вызывается для файла `a.txt`, а `IoProjectFiles.read` — для папки `lib`
- **THEN** оба результата — `ProjectFilesFailure` вида `unreadable`

#### Scenario: FIFO в перечислении
- **WHEN** в корне лежит именованный канал `pipe`
- **THEN** `pipe` перечислен с видом `other`, и чтение его не открывает

#### Scenario: Большой файл читается не целиком
- **WHEN** `IoProjectFiles.read` читает файл 3 МиБ с `maxBytes` 1 МиБ
- **THEN** результат — `TooLargePreview` с размером 3 МиБ, а прочитано не больше 1 МиБ + 1 байта
