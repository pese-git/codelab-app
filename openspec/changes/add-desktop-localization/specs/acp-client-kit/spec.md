## ADDED Requirements

### Requirement: Типизированная причина заметки транскрипта
`NoticeItem` видов `emptyTurn`, `turnStopped`, `detached` и `reconnected` SHALL нести типизированную причину, по которой хост строит текст заметки на своём языке, не разбирая `text`:
- `emptyTurn` — `stopReason` хода (`null`, если его нет);
- `turnStopped` — `stopReason` хода и, для `max_turn_requests`, имя исчерпанного лимита бюджета, если оно входит в известный набор (`steps`, `tokens`, `cost`, `duration`, `deadline`); незнакомое имя SHALL давать причину без имени лимита, как и текст;
- `detached` и `reconnected` — закрытое перечисление причины: агент не умеет восстанавливать сессии; восстановить не удалось; для причины с сессией — её id.

Поле `text` и его значения SHALL не меняться: CLI и TUI по-прежнему показывают `text`. `NoticeItem` вида `error` SHALL по-прежнему нести типизированный сбой хода (`PromptFailure`). Новые поля SHALL быть аддитивными, ядро клиента SHALL оставаться web-безопасным и без зависимости от локали. Для любой последовательности обновлений инкрементальная проекция и проекция с нуля SHALL давать равные причины.

#### Scenario: Причина остановки по лимиту бюджета
- **WHEN** ход завершается с `stopReason: max_turn_requests` и `budgetExceeded: tokens`
- **THEN** `NoticeItem` вида `turnStopped` несёт причину с `stopReason` `maxTurnRequests` и лимитом `tokens`, а его `text` — `The turn stopped: budget exceeded: tokens.`

#### Scenario: Незнакомый лимит
- **WHEN** ход завершается с `stopReason: max_turn_requests` и `budgetExceeded: gpu_hours`
- **THEN** причина заметки не содержит имени лимита, а `text` — `The turn reached the limit of model requests.`

#### Scenario: Сессия не восстановлена после переподключения
- **WHEN** после переподключения сессия `s1` не загрузилась
- **THEN** `NoticeItem` вида `detached` несёт причину «восстановить не удалось» с id `s1`, а `text` совпадает с прежним

#### Scenario: CLI не меняется
- **WHEN** CLI показывает ленту хода, остановленного по `max_tokens`
- **THEN** строка заметки — `The model reached its token limit, so the turn ended.`, как до изменения

### Requirement: Подпись агента у решённого одобрения
`ApprovalStateView.resolved` (`ResolvedApprovalView`) SHALL нести подпись от агента `agentLabel` (`String?`), по которой хост отличает название варианта агента от запасной подписи ядра:
- выбран вариант из `options` запроса — `agentLabel` SHALL быть его названием (`name`);
- выбран id варианта, которого нет среди `options`, — `agentLabel` SHALL быть этим id;
- запрос отменён или вариант не выбран — `agentLabel` SHALL быть `null`.

Поле `label` и его значения SHALL не меняться: при `agentLabel` оно равно `agentLabel`, иначе — запасная подпись ядра `Cancelled` (отмена) или `Resolved` (вариант не выбран). CLI и TUI по-прежнему показывают `label`. Поле SHALL быть аддитивным; ядро клиента SHALL оставаться web-безопасным и без зависимости от локали. Для любой последовательности обновлений инкрементальная проекция и проекция с нуля SHALL давать равные `agentLabel`.

#### Scenario: Выбран вариант агента
- **WHEN** агент запросил разрешение с вариантом `allow-once` под названием `Allow once`, и пользователь выбрал его
- **THEN** решённое одобрение несёт `agentLabel` `Allow once` и `label` `Allow once`

#### Scenario: Неизвестный id варианта
- **WHEN** запрос решён вариантом `custom-1`, которого нет среди `options`
- **THEN** `agentLabel` и `label` равны `custom-1`

#### Scenario: Отмена и невыбранный вариант
- **WHEN** запрос разрешения отменён, или он решён без выбранного варианта
- **THEN** `agentLabel` — `null`, а `label` — `Cancelled` при отмене и `Resolved` без варианта

#### Scenario: CLI не меняет подпись решённого одобрения
- **WHEN** CLI показывает ленту с отменённым запросом разрешения
- **THEN** строка исхода — `Cancelled`, как до изменения

### Requirement: Причина хранилища у отказа записи профиля
`ProfileSaveFailed` SHALL нести поле `storeReason` (`String?`), по которому хост отличает причину, названную хранилищем секретов, от запасной строки ядра:
- причина `secretReadOnly`, и хранилище назвало причину (`ReadOnly.reason`) — `storeReason` SHALL быть этой причиной;
- причина `secretReadOnly` без причины хранилища — `storeReason` SHALL быть `null`;
- другие причины (`secretWrite`, `profileWrite`) — `storeReason` SHALL быть `null`.

Поле `message` и его значения SHALL не меняться: при `secretReadOnly` оно равно причине хранилища, а без неё — запасной строке ядра `The secret store is read-only.`. CLI показывает `message`, как раньше. Поле SHALL быть аддитивным; ядро клиента SHALL оставаться web-безопасным и без зависимости от локали.

#### Scenario: Хранилище назвало причину
- **WHEN** `ProfileCommitter` сохраняет профиль `devbox` с новым токеном, а `ProfileSecrets.store` возвращает `ReadOnly('secret store keychain is read-only.')`
- **THEN** результат — `ProfileSaveFailed` с причиной `secretReadOnly`, `storeReason` и `message` — `secret store keychain is read-only.`, профиль не записан

#### Scenario: Хранилище без причины
- **WHEN** `ProfileSecrets.store` возвращает `ReadOnly()` без причины
- **THEN** `storeReason` — `null`, а `message` — `The secret store is read-only.`

#### Scenario: Сбой записи секрета
- **WHEN** `ProfileSecrets.store` возвращает `Failed('disk full')`
- **THEN** результат — `ProfileSaveFailed` с причиной `secretWrite` и `storeReason` `null`

## MODIFIED Requirements

### Requirement: Каталог команд палитры
`codelab_client_core` SHALL предоставлять `CommandCatalog` — неизменяемое слияние команд хоста (`HostCommand`: id, имя, название, описание, доступность, дополнительные строки поиска) и команд агента активной сессии (`SessionView.agentCommands`). Какие команды есть у хоста, SHALL решать хост; kit НЕ SHALL знать о командах конкретного хоста и об иконках. `CommandCatalog.commands` SHALL перечислять команды хоста в порядке хоста, затем команды агента в порядке `available_commands_update`. Недоступная команда хоста SHALL исключаться, если агент объявил команду с тем же именем (без `/`, с учётом регистра); доступная команда хоста и одноимённая команда агента SHALL оставаться обе. Повтор имени внутри списка агента SHALL давать одну команду — первую. `CommandCatalog.search(query)` SHALL снимать пробелы по краям и ведущий `/`, сравнивать без учёта регистра и для пустого запроса возвращать `commands`; иначе SHALL возвращать подходящие команды в порядке правил: префикс имени, подстрока имени, подпоследовательность имени, подстрока названия, описания или дополнительной строки поиска команды хоста; внутри правила — в порядке `commands`.

Дополнительные строки поиска (`HostCommand.searchAliases`) задаёт хост; по умолчанию их нет. Их язык kit НЕ SHALL учитывать и НЕ SHALL показывать их как название или описание. Desktop кладёт туда английские название и описание команды, когда интерфейс не на английском (change `add-desktop-localization`, D4). У команд агента дополнительных строк поиска нет: они ищутся по имени и описанию от агента.

#### Scenario: Заглушка хоста уступает агенту
- **WHEN** хост передаёт недоступную `compact` и доступную `new`, а агент объявил `compact` и `new`
- **THEN** `commands` содержит `new` хоста, затем `compact` и `new` агента, без `compact` хоста

#### Scenario: Ранжирование поиска
- **WHEN** в каталоге команды агента `review` («Review the plan») и `plan`, и вызывается `search('pl')`
- **THEN** результат — `plan`, затем `review`

#### Scenario: Подпоследовательность имени
- **WHEN** в каталоге команда `compact`, и вызывается `search('/cpt')`
- **THEN** результат содержит `compact`

#### Scenario: Пустой запрос
- **WHEN** вызывается `search('/')`
- **THEN** результат совпадает с `commands`

#### Scenario: Поиск по дополнительной строке команды хоста
- **WHEN** хост передаёт команду `new` с названием «Новая сессия» и дополнительными строками поиска `New session` и `Start a new session.`, агент объявил команду `review` («Review the plan»), и вызывается `search('session')`
- **THEN** результат — только `new`; `search('новая')` тоже даёт `new`, а `search('plan')` — только `review` агента

#### Scenario: Дополнительная строка — последнее правило
- **WHEN** хост передаёт команды `new` с дополнительной строкой `New session` и `sessions` без дополнительных строк, и вызывается `search('sess')`
- **THEN** результат — `sessions` (префикс имени), затем `new` (дополнительная строка)

#### Scenario: Хост без дополнительных строк
- **WHEN** хост передаёт команды без `searchAliases`, как CLI
- **THEN** результаты `search` совпадают с результатами до появления поля
