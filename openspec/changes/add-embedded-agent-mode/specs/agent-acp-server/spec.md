## ADDED Requirements

### Requirement: Локальное окружение сессии от хоста
`AcpServerConfig` SHALL иметь необязательное поле `localEnv` — фабрику `ExecutionEnv` по `cwd` сессии (`agent-core-architecture` §13.1; design.md change `add-embedded-agent-mode`, D4). Если хост его задал, `session/new` и `session/load` SHALL ставить env сессии `localEnv(cwd)`. Файлы, команды и листинг тогда исполняет хост: запросы `fs/*` и `terminal/*` клиенту НЕ SHALL отправляться, даже если клиент объявил `fs` и `terminal` в `initialize`. Без `localEnv` поведение прежнее: файлы и команды — через клиента (`AcpClientExecutionEnv`), листинг — через `localListing`. Gate сессии в обоих случаях SHALL оставаться `AcpPermissionGate`: вопрос одобрения идёт клиенту `session/request_permission`. `localEnv` НЕ SHALL менять ответ `initialize` и не добавляет методов, полей и состояний ACP. Сервер с включённой `fileListing` SHALL принимать `localEnv` вместо `localListing`: окружение `localEnv` обязано реализовывать листинг каталога, иначе — `HostWiringException` при создании сервера. Для этой проверки сервер SHALL один раз вызывать фабрику `localEnv` с `cwd` `/` при создании; поэтому фабрика SHALL быть без побочных эффектов и без обращения к файловой системе. При заданном `localEnv` `session/new` и `session/load` SHALL проверять существование `cwd` листингом окружения `localEnv(cwd)`: несуществующий каталог SHALL давать ошибку `-32602` (invalid params) до создания сессии, так же как при `localListing`.

#### Scenario: Хост исполняет файлы сам
- **WHEN** сервер создан с `localEnv`, клиент объявил `fs.readTextFile` и `terminal`, а сценарий модели в режиме `bypass` зовёт `read` и `exec`
- **THEN** клиент не получает ни `fs/read_text_file`, ни `terminal/create`; результаты вызовов приходят в `tool_call_update`

#### Scenario: Одобрение по-прежнему у клиента
- **WHEN** сервер создан с `localEnv`, а сценарий модели в режиме `standard` зовёт `write`
- **THEN** клиент получает `session/request_permission` с `toolCallId` вызова, и запись выполняется только после `allow_once`

#### Scenario: Команда в standard спрашивает клиента
- **WHEN** сервер создан с `localEnv`, а сценарий модели в режиме `standard` зовёт `exec`
- **THEN** клиент получает `session/request_permission` с `toolCallId` вызова, `terminal/create` не отправляется, и процесс запускается только после `allow_once`

#### Scenario: Несуществующий cwd при localEnv
- **WHEN** сервер создан с `localEnv`, и клиент вызывает `session/new` или `session/load` с абсолютным `cwd`, которого нет на диске
- **THEN** ответ — ошибка `-32602`, сессия не создаётся, фабрика `localEnv` для этого `cwd` не оставляет побочных эффектов

#### Scenario: Без localEnv поведение прежнее
- **WHEN** сервер создан без `localEnv`, клиент объявил `fs.readTextFile`, а модель зовёт `read`
- **THEN** агент отправляет клиенту `fs/read_text_file`
