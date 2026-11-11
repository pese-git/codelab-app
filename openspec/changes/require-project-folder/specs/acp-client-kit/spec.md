## MODIFIED Requirements

### Requirement: Сессии после переподключения
После успешного `reconnect()` kit SHALL загружать каждую открытую сессию через `session/load` с её собственным `cwd`, начиная с активной, если агент объявил `loadSession`. Транскрипт загруженной сессии SHALL строиться из реплея заново, а не дополняться. Если агент не объявил `loadSession` или `session/load` открытой сессии завершился ошибкой, сессия SHALL получать статус `detached`, а в её транскрипт SHALL добавляться уведомление о потере связи. `detached`-сессия НЕ SHALL отправлять промпты агенту — `send()` SHALL завершаться исходом `PromptFailed` — и НЕ SHALL сливать свою очередь. `loadSession` SHALL принимать и `detached`-сессию: после успешной загрузки она снова принимает промпты, а её очередь сливается по общим правилам (design.md change `require-project-folder`, D16).

#### Scenario: Переподключение к агенту с loadSession
- **WHEN** открыты две сессии, и `reconnect()` подключается к агенту с `loadSession`
- **THEN** kit отправляет `session/load` сначала для активной сессии, затем для второй, и транскрипт каждой совпадает с реплеем агента

#### Scenario: Агент без loadSession
- **WHEN** `reconnect()` подключается к агенту без `loadSession`
- **THEN** каждая открытая сессия получает статус `detached` и уведомление `The agent cannot restore sessions after reconnecting.`, а промпт в неё завершается `PromptFailed` без запроса к агенту

#### Scenario: Сессии разных папок
- **WHEN** открыты сессии с `cwd` `/work/a` и `/work/b`, и `reconnect()` подключается с корнем процесса `/work/a`
- **THEN** `session/load` отправлен для обеих сессий, каждой — с её `cwd`

#### Scenario: Загрузка detached-сессии
- **WHEN** сессия `a1` в состоянии `detached` с очередью из одного промпта, агент подключён и объявил `loadSession`, и хост вызывает `loadSession(a1, cwd: '/work/a')`
- **THEN** сессия загружена, её статус больше не `detached`, а промпт из очереди отправлен агенту после загрузки

## ADDED Requirements

### Requirement: Агент по требованию хоста
Kit SHALL предоставлять операцию `ClientWorkspace.ensureAgent(directory, {profile})` и поле `WorkspaceState.agentDirectory` — корень процесса текущего соединения (design.md change `require-project-folder`, D11, D15, D16):

- **Профиль.** Берётся `profile`, иначе профиль текущего или последнего соединения. Без профиля — `ClientWorkspaceException`, без обращения к резолверам.
- **Работающий агент.** При `Connected` операция SHALL завершаться без запросов к агенту и резолверам, какую бы папку ни передали.
- **Single-flight.** Если идёт попытка (`Connecting`, `Reconnecting`), операция SHALL возвращать её результат и НЕ SHALL открывать второй транспорт.
- **Новая попытка.** Иначе kit SHALL открывать соединение с корнем процесса `directory` по правилам `connect` (вытеснение, `Connecting`, `ConnectionFailed`). `agentDirectory` SHALL становиться `directory`. `projectDirectory` (выбранный проект и снимок) НЕ SHALL меняться.
- **Совместимость.** `connect(profile, projectDirectory:)` SHALL по-прежнему задавать и `projectDirectory`, и `agentDirectory`. `reconnect(projectDirectory:)` SHALL задавать `agentDirectory`. Поведение хостов, которые вызывают только `connect` (CLI), не меняется.
- **Список при смене проекта.** `selectProject(path)` при `Connected` SHALL сбрасывать список и курсор и запрашивать первую страницу `session/list` для `path`, если агент объявил `sessionCapabilities.list`. Ответ, пришедший после следующей смены проекта или подключения, НЕ SHALL менять список.
- **Восстановление.** Восстановление снимка при первом успешном подключении в запуске SHALL загружать активную сессию снимка, только если её `cwd` равен проекту снимка. Иначе сессия SHALL оставаться строкой `notLoaded` без `session/load` и `session/new`.

#### Scenario: Работающий агент не трогается
- **WHEN** агент подключён с корнем процесса `/work/a`, и вызывается `ensureAgent('/work/b')`
- **THEN** резолвер не вызывается, запросов к агенту нет, `agentDirectory` — `/work/a`

#### Scenario: Первый старт
- **WHEN** соединения нет, выбран проект `/work/app`, и вызывается `ensureAgent('/work/app')`
- **THEN** резолвер открывает транспорт с папкой `/work/app`, после подключения `agentDirectory` — `/work/app`, `projectDirectory` прежний, запрошен `session/list` для `/work/app`

#### Scenario: Повторный вызов во время попытки
- **WHEN** `ensureAgent('/work/a')` ждёт открытия транспорта, и вызывается `ensureAgent('/work/b')`
- **THEN** резолвер вызван один раз, с `/work/a`; оба вызова завершаются после одного подключения

#### Scenario: Смена проекта перезапрашивает список
- **WHEN** агент подключён, `session/list` для `/work/a` ещё не ответил, и хост вызывает `selectProject('/work/b')`
- **THEN** отправлен `session/list` с `cwd` `/work/b`; поздний ответ для `/work/a` список не меняет

#### Scenario: Активная сессия снимка в другой папке
- **WHEN** снимок содержит проект `/work/app` и активную сессию `s2` с `cwd` `/`, и первое подключение в запуске — `ensureAgent('/work/app')`
- **THEN** `session/load` и `session/new` для `s2` не отправлены, `s2` в списке со статусом `notLoaded`

#### Scenario: CLI-путь не меняется
- **WHEN** хост вызывает `connect(profile, projectDirectory: '/work/app')` и создаёт сессии без `cwd`
- **THEN** `agentDirectory` и `projectDirectory` — `/work/app`, сессии создаются с `cwd` `/work/app`, а `reconnect()` загружает их все
