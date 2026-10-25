## ADDED Requirements

### Requirement: ListingOverlayEnv
`ListingOverlayEnv(primary, listing)` SHALL реализовывать `ExecutionEnv` и `DirectoryListing`: `listDir` и `stat` берутся у `listing`, остальные операции (`readText`, `writeText`, `exec`) — у `primary`. `stat` локальный, потому что в ACP нет метода stat и каталог через клиента не проверить (design.md, D15). Сессия оборачивает его в `BoundedEnv` целиком, поэтому граница рабочей папки одна для обоих env (§4.7, §10.4 документа ядра; design.md change `add-dart-agent-acp-server`, D5).

Хост ACP-сервера передаёт `listing`, только когда клиент и агент работают на одной машине (stdio). Без него `ls` и `search` выключены с причиной.

#### Scenario: Листинг локально, чтение через клиента
- **WHEN** `ls` и `read` вызываются над `ListingOverlayEnv(fakeClientEnv, memoryEnv)`
- **THEN** `ls` возвращает содержимое `memoryEnv` без запросов к клиенту, а `read` идёт в `fakeClientEnv`

#### Scenario: Граница общая
- **WHEN** `ls` вызывается с путём вне `cwd` сессии над `BoundedEnv(ListingOverlayEnv(...))`
- **THEN** вызов отклоняется `outsideWorkspace` до обращения к `listing`
