## ADDED Requirements

### Requirement: Хранилище недавних проектов в CODELAB_HOME
`JsonFileRecentProjectsStore` SHALL хранить недавние проекты в одном JSON-файле вида `{"version": 1, "projects": [{"path": <строка>, "lastOpenedAt": <ISO-8601>}]}`; клиенты SHALL создавать его на файле `$CODELAB_HOME/recent_projects.json` — общем файле CLI и app (design.md change `share-recent-projects-store`, D1). Правило списка SHALL задавать чистая функция kit `mergeRecentProjects(a, b)` в `codelab_client_core`: одна запись на путь (точное сравнение строк) с наибольшим `lastOpenedAt`, порядок — по `lastOpenedAt` по убыванию (при равенстве — сначала записи `a`), не больше `recentProjectsLimit` записей (D5). `record(path)` SHALL давать результат `mergeRecentProjects([RecentProject(path, now)], текущий список)`, а метод класса `merge(projects)` — `mergeRecentProjects(projects, текущий список)`.

Отсутствующий файл SHALL читаться как пустой список. Файл, который не является JSON-объектом, с `version`, отличной от `1`, без списка `projects` или с записью неверного вида (не объект, `path` не непустая строка, `lastOpenedAt` не строка ISO-8601), SHALL давать `FormatException`, а не `TypeError`. `record` и `merge` при таком файле SHALL завершаться той же ошибкой и НЕ SHALL менять файл (D2). Запись SHALL идти через уникальный временный файл в том же каталоге, сброшенный на диск до атомарного переименования, как у `profiles.json`. Операции одного экземпляра хранилища SHALL выполняться по очереди: следующая начинается после завершения предыдущей, ошибка одной не отменяет следующие (D3). Порядка записи между разными процессами хранилище не гарантирует.

#### Scenario: Последний открытый — первым, не больше лимита
- **WHEN** хранилище на пустом временном файле записывает `recentProjectsLimit + 2` разных путей по очереди, а затем снова первый путь, и новое хранилище на том же файле читает список
- **THEN** список содержит `recentProjectsLimit` записей, первый путь — с самым поздним временем, а файл содержит `"version": 1`

#### Scenario: Две записи одного процесса без ожидания друг друга
- **WHEN** на одном экземпляре хранилища вызываются `record('/work/a')` и `record('/work/b')` без ожидания первого, затем оба завершаются
- **THEN** новое хранилище на том же файле читает обе записи

#### Scenario: Битый файл не перезаписывается
- **WHEN** файл содержит `{not json`, и вызываются `load()`, затем `record('/work/a')`
- **THEN** оба вызова завершаются `FormatException`, а байты файла не изменились

#### Scenario: Незнакомая версия не перезаписывается
- **WHEN** файл содержит `{"version": 2, "projects": []}`, и вызывается `record('/work/a')`
- **THEN** вызов завершается `FormatException`, а байты файла не изменились

#### Scenario: Запись неверного вида — FormatException
- **WHEN** файл содержит `{"version": 1, "projects": [{"path": 42, "lastOpenedAt": "2026-11-22T10:00:00.000"}]}`, и вызывается `load()`
- **THEN** результат — `FormatException`, а не `TypeError`

#### Scenario: Слияние по пути с более поздним временем
- **WHEN** `mergeRecentProjects` получает `[/work/a в 10:00, /work/b в 09:00]` и `[/work/a в 11:00, /work/c в 08:00]`
- **THEN** результат — `/work/a в 11:00`, `/work/b в 09:00`, `/work/c в 08:00`, по одной записи на путь

#### Scenario: Повторное слияние ничего не меняет
- **WHEN** `merge` с одним и тем же списком вызывается на хранилище дважды
- **THEN** после второго вызова файл читается тем же списком, что после первого

## MODIFIED Requirements

### Requirement: IO-адаптеры клиента
`dart:io`-реализации портов клиента SHALL жить в `packages/dart/codelab_client_io`:
- `IoTextFileIo`;
- `IoTerminalProcessRunner`;
- `IoWorkingDirectoryProvider`;
- `ioTransportResolver` — `ConfigTransportResolver` kit с настоящими транспортами stdio и WebSocket;
- `JsonFileProfileStore` (`$CODELAB_HOME/profiles.json`, общий файл CLI и app);
- `JsonFileRecentProjectsStore` (`$CODELAB_HOME/recent_projects.json`, общий файл CLI и app; требование «Хранилище недавних проектов в CODELAB_HOME»).

Реализации на Flutter-плагинах (`FileSelectorProjectFolderPicker`) SHALL оставаться в app; отдельной реализации `RecentProjectsStore` на `shared_preferences` в app НЕ SHALL быть (design.md change `share-recent-projects-store`, D9). `ProfileStore.remove(id)` SHALL удалять профиль с этим `id` и возвращать `true`, а без такого профиля — возвращать `false` и не менять файл. `JsonFileProfileStore` SHALL записывать `profiles.json` через уникальный временный файл в том же каталоге, сброшенный на диск (`flush`) до атомарного переименования: прерванная запись НЕ SHALL оставлять под именем `profiles.json` пустой или неполный файл (design.md change `add-app-settings-shell`, D7). Классификатора ошибок проверки профиля (`classifyProbeFailure`) в пакете НЕ SHALL быть: проверка профиля удалена (design.md change `remove-test-connection`, D2).

#### Scenario: Профили сохраняются в JSON
- **WHEN** `JsonFileProfileStore` сохраняет профиль `WebSocketProfile` и читает его заново
- **THEN** профиль восстановлен полностью, а файл не содержит значения токена

#### Scenario: Удаление профиля
- **WHEN** в `JsonFileProfileStore` сохранены профили `remote` и `local`, и вызывается `remove('remote')`
- **THEN** результат — `true`, а новое хранилище на том же файле читает только `local`

#### Scenario: Барель без классификатора проверки
- **WHEN** код импортирует `package:codelab_client_io/codelab_client_io.dart`
- **THEN** `classifyProbeFailure` не экспортируется, а `ioTransportResolver`, `JsonFileProfileStore` и `JsonFileRecentProjectsStore` доступны
