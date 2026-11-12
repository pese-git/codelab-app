## MODIFIED Requirements

### Requirement: Список профилей на странице «Connection»
Страница «Connection» SHALL показывать профили подключения в таком порядке:
1. встроенный агент — первым, всегда, независимо от файла; в `profiles.json` он НЕ SHALL сохраняться;
2. профили `ProfileStore` из `$CODELAB_HOME/profiles.json` в порядке файла. Это тот же файл и тот же `JsonFileProfileStore`, что у CLI. `CODELAB_HOME` SHALL разрешаться той же функцией `codelab_client_io`, что у CLI (design.md, D7): по умолчанию `~/.codelab`, `~` и `~/…` раскрываются через `HOME`, а `~user/…` и `~` без `HOME` — ошибка.

Строка профиля SHALL показывать:
- заголовок (`title`) — `label` в одну строку с многоточием и полным текстом в подсказке. Если `label` пуст или совпадает со значением `--agent`, из которого профиль создан (начинается с `stdio:`, `ws://` или `wss://`), заголовком SHALL быть `id`. Тем же правилом `title` SHALL пользоваться подтверждение «Remove» и подпись профиля на экране подключения и в баннере соединения рабочего места; сырой `label` там НЕ SHALL показываться;
- вторую строку — команду stdio без аргументов или origin WebSocket-адреса (`scheme://host:port`), без `env` и значения токена;
- метку «Current» — только у профиля работающего агента окна (принятый профиль в `Connected` или `Reconnecting`). После сбоя и во время новой попытки «Current» НЕ SHALL быть ни у одной строки, кроме случая отказа до обращения к workspace при живом соединении;
- бейдж попытки (ключ `connection-profile-status-<id>`): `Connecting…`, `Connected` или `Failed` — у строки профиля последней попытки (`ConnectionCommands.attemptProfile`), без текста ошибки;
- метки «Default», «Current», «Selected» (профиль окна для следующего старта агента, если он не «Current») и «Not tested»;
- результат последней проверки в этом открытии страницы (ключ `connection-profile-probe-<id>`, текст — по требованию «Диалог «Add connection profile»», раздел «Проверка»).

Строка SHALL предлагать действия «Test connection», «Use», «Rename» и «Remove». У встроенного агента НЕ SHALL быть «Test connection», «Rename» и «Remove». «Remove» SHALL быть недоступна у профиля работающего агента и у выбранного профиля окна, с подсказкой `Use another profile first.`.

У выбранного профиля окна кнопки «Use» НЕ SHALL быть; у остальных строк она SHALL быть. Ручного подключения и «Disconnect» на странице НЕ SHALL быть: агент стартует сам по триггерам рабочего места (spec agent-workbench-ui «Агент стартует сам»), перезапуск — «Restart agent» блока «Behavior» (design.md change `require-project-folder`, D18).

Радиокнопка строки SHALL выбирать профиль по умолчанию (`shared_preferences` `codelab.connection.default_profile`). Профиль по умолчанию SHALL быть начальным профилем окна. «Use» SHALL делать профиль строки профилем окна для следующего старта агента и НЕ SHALL менять профиль по умолчанию. «Use» НЕ SHALL запускать, останавливать или перезапускать агента: если агент работает с другим профилем, новый профиль применяется «Restart agent» (требование «Блок «Behavior» страницы «Connection»»).

Без сохранённого выбора профилем по умолчанию SHALL быть встроенный агент. `default` — второе имя встроенного агента (design.md, D21): запись с id `default` в `profiles.json` SHALL игнорироваться и НЕ SHALL показываться строкой профиля.

Если такая запись есть, страница SHALL показывать InfoBar уровня `warning` (ключ `connection-profiles-ignored-default`) с текстом `Profile "default" in profiles.json is ignored: default is the built-in agent. Remove it with codelab profiles remove default.` и кнопкой «Remove». Кнопка после подтверждения удаляет запись через `ProfileStore.remove('default')`. Команду, аргументы, URL и `env` записи InfoBar НЕ SHALL показывать. Без действия пользователя файл НЕ SHALL перезаписываться. Сохранённый id, которого нет в списке, SHALL удаляться, и профилем по умолчанию SHALL становиться встроенный агент.

Если `profiles.json` не разбирается или имеет неизвестную версию, страница SHALL показывать строку встроенного агента и ошибку `Cannot read <path>: <причина>. Fix or remove the file; CodeLab will not overwrite it.`. Если `CODELAB_HOME` недопустим, страница SHALL показывать строку встроенного агента и причину ошибки `CODELAB_HOME`. В обоих случаях:
- «Add profile», «Rename» и «Remove» SHALL быть недоступны;
- файл НЕ SHALL перезаписываться;
- блок «Behavior» («Restart agent») SHALL оставаться видимым и рабочим: он не зависит от `profiles.json`.

Предупреждение о проигнорированной записи `default` SHALL писаться в журнал один раз за жизнь страницы, а не при каждом перечитывании файла.

Строка WebSocket-профиля SHALL показывать источник токена:
- `No token`;
- `From $<NAME>`, с пометкой `<NAME> is not set in CodeLab's environment.`, если переменной нет в окружении app;
- `Token secret <имя>` с тегом `<backend> · set` или `<backend> · missing` для ссылки `secret:<имя>` (design.md change `add-provider-setup-ui`, D14). Наличие секрета SHALL определяться без чтения значения (`ProfileSecrets.isSet`); имя показывается текстом, а не редактируемым полем; старт агента с профилем, чей секрет не задан, SHALL подключаться без токена и писать в диагностику `Profile <id> has no stored secret value; connecting without a token.`, а в журнал — событие `connection_profile.token_secret_missing` с единственным полем `profile_id` (имя секрета и значение там НЕ SHALL встречаться; design.md change `add-provider-setup-ui`, D13).
- `unrecognized token reference (not supported in this version)` для ссылки не вида `env:` и `secret:`. Значение ссылки НЕ SHALL выводиться ни в UI, ни в журнал, ни в диагностику: вместо имени секрета там может стоять сам токен. старт агента с таким профилем SHALL подключаться без токена и писать в диагностику `The token-reference format of profile <id> is not supported in this version; connecting without a token.`.

Страница «Connection», диалог «Add connection profile» и (с итерации 2) страница «Providers» SHALL при каждом открытии заново открывать `ClientSecretAccess` и перечитывать `secrets.backend`, чтобы правка `config.yaml` применялась без перезапуска app (design.md change `add-provider-setup-ui`, D3, D4).

#### Scenario: Профиль CLI виден в app
- **WHEN** `codelab profiles add dev 'stdio:codelab-agent serve --stdio'` выполнен с тем же `CODELAB_HOME`, и пользователь открывает «Connection»
- **THEN** список содержит «Embedded agent» первым и строку `dev` с командой `codelab-agent`

#### Scenario: Профиль по умолчанию на новой установке
- **WHEN** ключа `codelab.connection.default_profile` нет, а `profiles.json` содержит профиль `dev`
- **THEN** метку «Default» имеет встроенный агент

#### Scenario: Старая запись default
- **WHEN** `profiles.json` содержит записи `default` (stdio, команда `/opt/secret-agent`) и `dev`
- **THEN** список показывает «Embedded agent» и `dev`, строки `default` нет, InfoBar `connection-profiles-ignored-default` показан и не содержит `/opt/secret-agent`, а файл не изменён

#### Scenario: Удаление старой записи default из app
- **WHEN** пользователь нажимает «Remove» в InfoBar старой записи `default` и подтверждает
- **THEN** `profiles.json` больше не содержит `default`, запись `dev` на месте, InfoBar скрыт

#### Scenario: Use не меняет профиль по умолчанию и не запускает агента
- **WHEN** профиль по умолчанию — встроенный агент, агент не запущен, и пользователь нажимает «Use» в строке `dev`
- **THEN** процесс `dev` не запускается, строка `dev` получает метку «Selected», метка «Default» остаётся у встроенного агента, а следующий триггер старта (выбор проекта, «New session») запускает `dev`

#### Scenario: Неподдерживаемая ссылка на токен
- **WHEN** `profiles.json` содержит WebSocket-профиль `devbox` с `tokenRef: sk-test-leak-0123456789`
- **THEN** строка показывает `unrecognized token reference (not supported in this version)`; старт агента с `devbox` идёт без токена, а диагностика содержит предупреждение с `devbox`. Ни страница, ни журнал, ни диагностика (в том числе после `SecretRedactor`) не содержат `sk-test-leak-0123456789`

#### Scenario: Секрет токена в строке
- **WHEN** `secrets.backend: file`, `profiles.json` содержит WebSocket-профили `devbox` с `tokenRef: secret:codelab/profiles/devbox/token` (секрет сохранён) и `ci` с `tokenRef: secret:codelab/ws-ci` (секрета нет)
- **THEN** строка `devbox` показывает `Token secret codelab/profiles/devbox/token` и `file · set`, строка `ci` — `Token secret codelab/ws-ci` и `file · missing`; значение секрета не читалось

#### Scenario: Подключение с незаданным секретом
- **WHEN** профиль `ci` ссылается на `secret:codelab/profiles/ci/token`, которого нет в хранилище, и агент окна стартует с профилем `ci`
- **THEN** подключение идёт без токена, диагностика содержит `Profile ci has no stored secret value; connecting without a token.`, журнал — `connection_profile.token_secret_missing` с `profile_id: ci` и без имени секрета

#### Scenario: Правка secrets.backend без перезапуска
- **WHEN** app открыто при `secrets.backend` по умолчанию, пользователь добавляет в `config.yaml` `secrets.backend: file` и снова открывает страницу «Connection», а затем «Add connection profile»
- **THEN** строки показывают бэкенд `file`, а «Store a new token» доступен — без перезапуска app

#### Scenario: Заголовок строки
- **WHEN** `profiles.json` содержит профиль `py` с `label` `stdio:python -m "codelab agent" --stdio`, профиль `ws` с пустым `label` и профиль `dev` с `label` длиннее строки
- **THEN** заголовки — `py`, `ws` и `label` профиля `dev` с многоточием и полным текстом в подсказке; вторая строка `py` — `python`, без аргументов

#### Scenario: Use скрыт у выбранного профиля
- **WHEN** `profiles.json` содержит профили `dev` и `plain`, пользователь нажимает «Use» в строке `dev`, и агент окна стартует с `dev`
- **THEN** у `dev` «Current» и `Connected`, кнопки `connection-profile-use-dev` нет, а у `plain` и встроенного агента «Use» есть

#### Scenario: Строка при переподключении и после сбоя
- **WHEN** окно подключено к `dev`, соединение переходит в `Reconnecting`, затем переподключение не удаётся
- **THEN** в `Reconnecting` у `dev` «Current» и бейдж `Connecting…`; после сбоя «Current» нет ни у кого, у `dev` бейдж `Failed` и метка «Selected», кнопки `connection-profile-use-dev` нет, а у других строк «Use» есть

#### Scenario: Бейдж состояния текущего профиля
- **WHEN** агент ещё не запускался, профиль окна — `dev`, пользователь выбирает проект, и старт `dev` сначала идёт, потом завершается ошибкой
- **THEN** бейдж `connection-profile-status-dev` показывает `Connecting…`, затем `Failed`, без текста ошибки; у других строк бейджа нет, «Current» нет ни у кого

#### Scenario: Бейдж после принятого подключения
- **WHEN** агент работает с `a` («Current» и `Connected` у `a`), ходов нет, пользователь нажимает «Use» в строке `b`, затем «Restart agent», и `b` подключается успешно
- **THEN** пока идёт попытка, бейдж `Connecting…` стоит у `b`, а «Current» нет ни у кого; после успеха «Current» и `Connected` у `b`, у `a` ни метки, ни бейджа

#### Scenario: Недопустимый CODELAB_HOME
- **WHEN** app запущено с `CODELAB_HOME=~bob/cl`
- **THEN** страница показывает встроенного агента и причину ошибки `CODELAB_HOME`, «Add profile» недоступна, ни один файл не создан, а «Restart agent» виден

#### Scenario: Битый profiles.json
- **WHEN** `profiles.json` содержит `{"version": 2, "profiles": []}`
- **THEN** страница показывает встроенного агента и ошибку чтения, «Add profile» недоступна, а содержимое файла после закрытия страницы прежнее

#### Scenario: Текущий профиль не удаляется
- **WHEN** агент окна работает с профилем `dev`
- **THEN** «Remove» в строке `dev` недоступна с подсказкой `Use another profile first.`

### Requirement: Блок «Behavior» страницы «Connection»
Блок «Behavior» SHALL содержать одну строку — «Restart agent». Строки «Connect on start» НЕ SHALL быть: ключ `codelab.connection.connect_on_start` app не читает и не пишет, а агент стартует сам по триггерам рабочего места (spec agent-workbench-ui «Агент стартует сам»; design.md change `require-project-folder`, D19).

**«Restart agent».** Строка SHALL перезапускать агента окна с выбранным профилем окна (метка «Selected» или «Current»). Корень процесса — папка сессии в фокусе, иначе выбранный проект, иначе прежний корень. Это то же действие, что «Restart agent» диалога переноса секретов (design.md change `add-app-settings-shell`, D9). Перезапуск — единственный способ сменить профиль работающего агента и восстановиться после сбоя (design.md change `require-project-folder`, D22).

Если хотя бы одна сессия окна в ходе, ждёт одобрения или отменяется, перезапуск SHALL сначала показывать диалог `Restart <title>? This interrupts <n> running session(s): <titles>. Queued prompts stay.` с «Restart agent» и «Cancel». «Cancel» НЕ SHALL ничего менять. Без работы в сессиях диалога НЕ SHALL быть. Пока диалог открыт, повторные перезапуски SHALL игнорироваться. Перезапуск НЕ SHALL отправлять `session/cancel`: ходы обрываются заменой транспорта, ждущие одобрения снимаются, очередь сохраняется, открытые сессии загружаются заново.

Подпись строки:
- если выбранный профиль совпадает с профилем работающего агента — `Reconnects <title> and reloads open sessions. A running turn is interrupted; queued prompts stay.`;
- если выбран другой профиль — `Restart <title> to use it.`, где `<title>` — выбранный профиль;
- для профиля WebSocket строка SHALL называться «Reconnect»; её описание НЕ SHALL обещать отмену хода.

Строка SHALL быть недоступна во время подключения или переподключения, а также без проекта и без прежнего корня процесса — с подсказкой `Starts when you open a project.`.

Попытка, вытесненная более новой, НЕ SHALL менять ни профиль окна, ни статус, ни соединение, даже если завершилась позже (номер попытки проверяется после каждого ожидания). Диагностика старта stdio SHALL называть только команду, без аргументов. Отказ до обращения к workspace (пустая команда stdio, нет папки) при работающем агенте НЕ SHALL трогать живое соединение: статус остаётся `connected`, причина идёт только в диагностику.

В CommandBar страницы SHALL быть только «Add profile»; второй кнопки «Restart agent» там НЕ SHALL быть.

#### Scenario: Старт без строки Connect on start
- **WHEN** в `shared_preferences` `codelab.connection.connect_on_start` — `true`, снимка нет, и app запускается
- **THEN** блок «Behavior» не содержит «Connect on start», агент не запущен, а «Restart agent» недоступна с подсказкой `Starts when you open a project.`

#### Scenario: Restart agent переподключает тем же профилем
- **WHEN** агент окна — встроенный, открыта сессия с завершённым ходом, и пользователь нажимает «Restart agent»
- **THEN** диалога нет, прежний встроенный агент освобождён, новый подключён тем же профилем, сессия загружена через `session/load`

#### Scenario: Смена профиля применяется перезапуском
- **WHEN** агент работает со встроенным профилем, пользователь нажимает «Use» в строке stdio-профиля `dev`
- **THEN** агент не перезапущен, строка «Restart agent» показывает `Restart dev to use it.`; после нажатия и без идущих ходов агент — `dev`, «Current» у `dev`

#### Scenario: Подтверждение при идущем ходе
- **WHEN** в сессии окна идёт ход, и пользователь нажимает «Restart agent»
- **THEN** показан диалог с названием сессии; после «Cancel» агент и ход прежние; после «Restart agent» агент перезапущен, ход оборван без `session/cancel`, очередь сохранена

#### Scenario: Сбой и восстановление
- **WHEN** выбранный профиль `dart` указывает на несуществующий бинарь, старт завершился `Failed`, пользователь нажимает «Use» во встроенном агенте, затем «Restart agent»
- **THEN** встроенный агент запущен, «Current» и `Connected` у встроенного агента, у `dart` ни метки, ни бейджа

#### Scenario: Поздняя попытка
- **WHEN** пользователь нажимает «Restart agent» с профилем `slow`, затем, пока `slow` подключается, выбирает «Use» для `dev` и снова «Restart agent», и `dev` подключается раньше, чем завершается `slow`
- **THEN** агент — `dev`, метка «Current» у `dev`, поздний исход `slow` не меняет ни соединение, ни статус

#### Scenario: Подпись для WebSocket
- **WHEN** выбранный профиль — WebSocket и он же работает
- **THEN** строка называется «Reconnect», а её описание не содержит слов о перезапуске процесса агента

### Requirement: Доступ к настройкам агента на страницах Providers и MCP servers
Страницы «Providers» и «MCP servers» SHALL показывать настройки агента профиля текущего подключения, а без подключения — профиля по умолчанию; доступ SHALL вычислять `resolveSettingsAccess` (spec client-agent-setup «Доступ к настройкам агента»; design.md, D5). Смена подключения SHALL перечитывать доступ.

Папкой для `resolveSettingsAccess` SHALL быть папка сессии в фокусе, а без неё — выбранный проект: провайдеры, модель и запреты — ключи сессии её папки (spec agent-runtime «Конфигурация сессии вне корня запуска»). Без того и другого доступ SHALL вычисляться без папки (`cwd: null`): проектные слои `projectLocal` и `project` не читаются, цель записи `projectLocal` не предлагается, а текущая папка процесса CodeLab папкой не считается (spec client-agent-setup «Доступ к настройкам агента»; design.md change `require-project-folder`, D8).

Для `RemoteReadOnly` и `NotManaged` страницы НЕ SHALL читать локальный конфиг и НЕ SHALL показывать кнопок записи (SETUP-2). Они SHALL показывать InfoBar уровня `warning`: `Read-only: this agent runs on <scheme://host:port>. Change providers and MCP on that host: codelab provider add, codelab mcp add, codelab config set.` или `Provider settings are managed by <agentName>.` (ключи `providers-read-only`, `mcp-read-only`). «Providers» в этом состоянии SHALL показывать текущую модель активной сессии из `configOptions`, а «MCP servers» — только панель «Agent status».

Если `config.yaml` не разбирается или нарушает схему, страница SHALL показывать проблемы загрузчика с путём ключа (ключи `providers-unreadable`, `mcp-unreadable`) и НЕ SHALL предлагать запись: битый файл пользователя не перезаписывается. Для страницы «MCP servers» «не разбирается или нарушает схему» — это нечитаемый слой или проблемы видов `syntax`, `profile`, `unknownKey`, `type`; проблемы видов `value`, `semantic`, `inlineSecret` (например, незаданная переменная подстановки), кроме отсутствия обязательного ключа (`agent.default_model` без провайдеров), НЕ SHALL блокировать запись и показываются InfoBar `mcp-rejected` (требование «Страница «MCP servers»»; решение Q26 design.md).

#### Scenario: WebSocket-агент только для чтения
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp`, а в локальном `~/.codelab/config.yaml` есть провайдер `local`
- **THEN** «Providers» показывает InfoBar с `wss://devbox:7420` без `/acp`, строки `local` нет, кнопок «Add provider», «Edit», «Remove» нет; локальный файл не читался

#### Scenario: Сторонний stdio-агент (согласовано пользователем 2026-11-06)
- **WHEN** окно подключено к stdio-профилю с командой `python` и аргументами `-m other_agent`
- **THEN** обе страницы показывают `Provider settings are managed by python.` (решение по базовому имени команды: самоназвания агента из `initialize` клиенту в этой версии не доступно; design.md change `add-provider-setup-ui`, D5) и не пишут файлы

#### Scenario: Настройки без выбранного проекта
- **WHEN** проект не выбран, агент не запущен, текущая папка процесса — `/`, профиль окна — встроенный агент, и пользователь открывает «Providers»
- **THEN** страница показывает провайдеров из `$CODELAB_HOME/config.yaml`, файлы в `/.codelab/` не читаются, а цели «This project only» среди целей записи нет
