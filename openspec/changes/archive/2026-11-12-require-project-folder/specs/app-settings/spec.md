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

**«Restart agent».** Строка SHALL перезапускать агента окна с выбранным профилем окна (метка «Selected» или «Current»). Корень процесса SHALL выбираться так: папка сессии в фокусе, если она не корень диска; иначе выбранный проект; иначе прежний корень; папка сессии в корне диска (открытой после подтверждения, spec agent-workbench-ui «Подтверждение открытия сессии в корне диска») — только если других кандидатов нет (design.md change `require-project-folder`, D18, Q27 (a)). Перезапуск НЕ SHALL менять выбранный проект. Это то же действие, что «Restart agent» диалога переноса секретов (design.md change `add-app-settings-shell`, D9) и пункт палитры `/reconnect` (spec agent-workbench-ui «Командная палитра открывается и выполняет доступные действия»). Перезапуск — единственный способ сменить профиль работающего агента и восстановиться после сбоя (design.md change `require-project-folder`, D22).

Если хотя бы одна сессия окна в ходе, ждёт одобрения или отменяется, перезапуск SHALL сначала показывать диалог `Restart <title>? This interrupts <n> running session(s): <titles>. Queued prompts stay.` с «Restart agent» и «Cancel». «Cancel» НЕ SHALL ничего менять. Без работы в сессиях диалога НЕ SHALL быть. Пока диалог открыт, повторные перезапуски SHALL игнорироваться. Перезапуск НЕ SHALL отправлять `session/cancel`: ходы обрываются заменой транспорта, ждущие одобрения снимаются, очередь сохраняется, открытые сессии загружаются заново.

Подпись строки:
- если выбранный профиль совпадает с профилем работающего агента — `Reconnects <title> and reloads open sessions. A running turn is interrupted; queued prompts stay.`;
- если выбран другой профиль — `Restart <title> to use it.`, где `<title>` — выбранный профиль;
- для профиля WebSocket строка SHALL называться «Reconnect»; её описание НЕ SHALL обещать отмену хода.

Строка SHALL быть доступна и во время старта агента: перезапуск вытесняет идущую попытку старта (зависший старт иначе не прервать), диалога подтверждения при этом нет — ходов ещё нет; вытесненная попытка освобождается резолвером и не меняет статус (design.md change `require-project-folder`, Q25 (a)). Пока открыт диалог подтверждения, строка не начинает второй перезапуск. Без проекта и без прежнего корня процесса строка SHALL быть недоступна с подсказкой `Starts when you open a project.`.

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

#### Scenario: Зависший старт прерывается перезапуском
- **WHEN** выбор проекта `/work/app` стартовал встроенного агента, открытие не завершается, и пользователь нажимает «Restart agent»
- **THEN** диалога нет, прежняя попытка вытеснена без промежуточного `failed`, её агент освобождён, стартует новая попытка с корнем `/work/app`

#### Scenario: Корень перезапуска при сессии в корне диска
- **WHEN** выбран проект `/work/app`, в фокусе сессия `s2` с `cwd` `/`, открытая после подтверждения, и пользователь нажимает «Restart agent»
- **THEN** агент перезапущен с корнем процесса `/work/app`, `s2` загружена заново с `cwd` `/`, выбранный проект не изменился

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

### Requirement: Диалог «Add connection profile»
Кнопка «Add profile» SHALL открывать `ContentDialog` «Add connection profile». Логика черновика SHALL жить в `codelab_client_core` (`ProfileDraft`, `ProfileProbe`; spec acp-client-kit), а диалог только рисует её через `AddProfileCubit`.

**Тип.** Типы SHALL определяться зарегистрированными `TransportResolver`. Если хост поддерживает один тип, переключателя типа SHALL не быть (SETUP-22). Новый диалог SHALL открываться на первом доступном типе: «Local stdio», а без stdio-резолвера — «WebSocket» (решение пользователя 2026-11-05).

**Имя и id.** Поле «Name» и под ним id: по умолчанию из имени, редактируемый до сохранения. Подпись «cannot change after saving». Ошибки id выводятся у поля.

**stdio.**
- «Command» — по умолчанию `codelab-agent`.
- «Arguments» — по умолчанию `serve --stdio`, подсказка «Parsed like a shell: quotes and escapes work.».
- «Run in the project folder» — по умолчанию включено.
- «Environment» — свёрнуто, строки `KEY=value`.

**WebSocket.**
- «URL». URL с userinfo (`ws://user:pass@host…`, в том числе только с именем) SHALL отклоняться ошибкой у поля `Remove the user name and password from the URL; use the Token setting instead.` (проблема черновика `urlUserInfo`), и профиль НЕ SHALL сохраняться: userinfo попал бы в `profiles.json` и ушёл бы на сервер заголовком Basic auth. Текст ошибки НЕ SHALL содержать URL и userinfo.
- Предупреждение под полем для `ws://` к нелокальному хосту: с токеном (любой вариант, кроме «No token») —  `ws:// to another machine: the token is sent unencrypted.`, без токена — `ws:// to another machine: traffic is sent unencrypted.`.
- «Token» SHALL предлагать четыре варианта в таком порядке (design.md change `add-provider-setup-ui`, D14; «From environment variable» — отступление от артборда, D24):
  - «No token»;
  - «Use stored secret» — список имён хранилища секретов агента `ProfileSecrets.names()`, отфильтрованный функцией kit `selectableProfileTokenSecrets`: только `codelab/profiles/*`, которые принимает `ProfileTokenRef`. Ключи провайдеров и секреты MCP в списке НЕ SHALL показываться: ключ LLM не должен уйти агенту заголовком Bearer (решение пользователя 2026-11-05; design.md change `add-provider-setup-ui`, D14). В профиль идёт `tokenRef: secret:<имя>`. Ручная ссылка `secret:<любое допустимое имя>` в `profiles.json` SHALL продолжать работать. Если подходящих имён нет или хранилище не читается, вариант SHALL быть неактивен с подсказкой `No stored secrets in <backend>.`;
  - «Store a new token» — поле со скрытым вводом и подсказка `Saved as codelab/profiles/<id>/token in <backend>. The value is never shown again or written to profiles.json.`; в профиль идёт `tokenRef: secret:codelab/profiles/<id>/token`. Если бэкенд только для чтения, вариант SHALL быть неактивен с подсказкой того же текста, что у `codelab secret set`: `Secret store <backend> is read-only. Add 'secrets.backend: file' to <home>/config.yaml to store secrets in <home>/secrets.yaml (plaintext, 0600), or set <CODELAB_SECRET_…> in the environment.`, а на Windows — без части про файл (design.md change `add-provider-setup-ui`, D3); Если `ClientSecretAccess.configProblem` не пуст (битый `config.yaml`, недопустимое значение `secrets.backend`), вместо этой подсказки SHALL показываться эта причина; при обычном `auto → env` подсказка про `secrets.backend: file` остаётся (design.md change `add-provider-setup-ui`, D3).
  - «From environment variable» — поле имени переменной, по умолчанию `CODELAB_AGENT_TOKEN`, в профиль идёт `tokenRef: env:<NAME>`.
- Значение нового токена диалог SHALL держать только в памяти (`SecretText`) и НЕ SHALL показывать после ввода; значение выбранного «Use stored secret» диалог НЕ SHALL читать, кроме проверки.
- Для «From environment variable» под полем SHALL показываться подсказка `CodeLab reads the token from this environment variable when it connects. Token values are not saved in profiles.json.` и строка `Apps opened from Finder do not see variables set in your shell profile.`.
- Если переменная не задана в окружении app, диалог SHALL показывать `<NAME> is not set in CodeLab's environment.` один раз — подсказкой под полем имени переменной. Других предупреждений о незаданной переменной, в том числе в блоке проверки до и после «Test connection», диалог НЕ SHALL показывать (решение пользователя 2026-11-05; design.md change `add-app-settings-shell`, D12, D13). Проверка с незаданной переменной SHALL выполняться.

**Проверка.** «Test connection» SHALL выполнять `ProfileProbe` и показывать исход (решение пользователя 2026-11-05, design.md D12):
- `Reachable · <N> ms · <name> <version>` — имя и версия из `agentInfo` ответа `initialize`;
- `Command not found: <command>` — значение поля «Command» профиля, без аргументов и `env`;
- `Unreachable: connection refused`, `Unreachable: host not found`, `Unreachable: TLS handshake failed` или `Unreachable: HTTP <status>` по типизированной причине `UnreachableReason` исхода (`connectionRefused`, `hostNotFound`, `tlsFailed`, `httpStatus` со `statusCode`), а при причине `unknown` — просто `Unreachable`;
- `Unauthorized: the agent rejected the token`, если токен действительно отправлен: введён новый токен, выбранный секрет найден или переменная `<NAME>` задана в окружении app. Во всех остальных случаях («No token», переменная не задана, секрета нет, неподдерживаемая ссылка) — `Unauthorized: the agent requires a token`: текст описывает то, что реально ушло на сервер;
- `Timed out`;
- `Not an ACP agent`.

Детали текста SHALL браться только из типизированных данных исхода и полей профиля. Текст исключения и поле `message` исхода `Unreachable` НЕ SHALL показываться в UI: `message` после `describeFailure` предназначен только для журнала и диагностики. Тот же текст SHALL показываться в строке профиля на странице «Connection» (ключ `connection-profile-probe-<id>`).

Повторная проверка и закрытие диалога SHALL отменять идущую проверку, а её поздний исход НЕ SHALL менять диалог.

**Подтверждение `ws://` перед проверкой** (решение пользователя 2026-11-05). Если URL — `ws://` к хосту вне `localhost`, `127.0.0.0/8` и `::1`, а выбран любой вариант токена, кроме «No token» (задана переменная или нет, найден секрет или нет), «Test connection» SHALL сначала показывать InfoBar «Unencrypted connection» с текстом `The token for <scheme://host:port> will travel in clear text. Use wss:// if the host supports it.` и кнопкой «Test anyway» (ключ `add-profile-test-anyway`). До «Test anyway» проверка НЕ SHALL начинаться: транспорт не открывается, токен не отправляется. С «No token» или к локальному хосту проверка SHALL начинаться сразу.

**Сохранение с токеном в хранилище.** Для «Store a new token» запись SHALL идти через `ProfileCommitter` в порядке «секрет → профиль» с откатом секрета, если профиль не записан (SETUP-19; spec acp-client-kit «Запись профиля с новым токеном»). Если секрет `codelab/profiles/<id>/token` уже существует, диалог SHALL показывать у поля токена `A stored token codelab/profiles/<id>/token already exists in <backend>. Choose it with "Use stored secret" or remove it with codelab secret delete.` и НЕ SHALL ничего записывать. Ошибка отката SHALL показываться текстом `The profile was not saved; the token stays in <backend> as <имя>. Remove it with codelab secret delete <имя>.`.

**Сохранение.** Кнопка SHALL называться «Save» после успешной проверки и «Save without test» иначе; без успешной проверки строка профиля получает метку «Not tested». Флажок «Use by default» (по умолчанию выключен) делает профиль профилем по умолчанию; текущее подключение диалог НЕ SHALL менять.

Нажатие «Save» SHALL переводить диалог в состояние записи до чтения списка существующих id; повторное нажатие в этом состоянии НЕ SHALL давать второй записи. Пока идёт запись, «Cancel» SHALL быть неактивна, а Esc и закрытие диалога SHALL быть заблокированы. «Save anyway» SHALL перед записью заново читать список id: если id уже занят, диалог SHALL показывать ошибку `idTaken` у поля id, а существующий профиль НЕ SHALL перезаписываться.

**Подтверждение `ws://` к нелокальному хосту.** Сохранение профиля с `ws://` к хосту вне `localhost`, `127.0.0.0/8` и `::1` SHALL всегда требовать подтверждения — и с токеном, и без него (решение пользователя 2026-11-05). Подтверждение — панель InfoBar уровня `warning` внутри диалога «Add connection profile», как в артборде `AddProfile`, с заголовком «Unencrypted connection» и кнопкой «Save anyway» (ключ `add-profile-save-anyway`); текст:
- с токеном — `The token for <scheme://host:port> will travel in clear text. Use wss:// if the host supports it.`;
- без токена — `Prompts and files sent to <scheme://host:port> will travel in clear text. Use wss:// if the host supports it.`.

В адресе SHALL показываться только `scheme://host:port`; путь, query и userinfo URL НЕ SHALL показываться. Отдельной кнопки отказа у панели нет: отказ — правка черновика или «Cancel»; без «Save anyway» запись НЕ SHALL происходить.

Подтверждение SHALL действовать для пары «URL, выбор токена» черновика: после «Test anyway» перед «Save» и после «Save anyway» перед «Test connection» повторного подтверждения НЕ SHALL быть. Изменение URL, варианта токена, имени переменной, выбранного секрета или значения нового токена SHALL сбрасывать подтверждение, даже если значение затем возвращено к прежнему; «Add another» SHALL начинать черновик без подтверждения.

«Test connection» в строке сохранённого профиля и старт агента с профилем, выбранным «Use», подтверждения `ws://` НЕ SHALL спрашивать (решение пользователя 2026-11-05; «Use» заменил «Connect», design.md change `require-project-folder`, D18).

После сохранения диалог SHALL показывать экран «Profile saved» с id, текстом `The running agent is unchanged. Select it with Use in the profile row; Restart agent applies it.` (design.md change `require-project-folder`, Q22 (a)) и кнопками «Done» и «Add another». «Cancel» и Esc без сохранения SHALL закрывать диалог без записи в `profiles.json` и `shared_preferences`.

После закрытия диалога страница «Connection» SHALL показывать все профили, сохранённые за жизнь диалога (в том числе сохранённые до «Add another»), каждый со своим исходом проверки из диалога или меткой «Not tested». Исход проверки в строке профиля SHALL сбрасываться, если при перечитывании `profiles.json` профиль с тем же id изменился в полях, значимых для подключения (тип, команда, аргументы, `env`, папка запуска, URL, ссылка на токен); изменение `label` («Rename») исход НЕ SHALL сбрасывать. Исход, пришедший для профиля, который за время проверки изменился в этих полях, SHALL отбрасываться.

#### Scenario: Ошибки id
- **WHEN** пользователь вводит имя `Embedded`, затем `Default`, затем имя, чей id совпадает с существующим `dev`, затем правит id на `a:b`
- **THEN** у поля по очереди показываются `"embedded" is reserved for the built-in agent.`, `"default" is reserved for the built-in agent.`, `A profile with id "dev" already exists.` и ошибка допустимых символов; «Save» недоступна

#### Scenario: Секретоподобный ключ окружения
- **WHEN** в «Environment» введена строка `OPENAI_API_KEY=sk-x`
- **THEN** у поля показано `OPENAI_API_KEY looks like a secret. Set it in the system environment or reference it from the agent config as ${secret:…}.`, сохранение недоступно, а `sk-x` не появляется ни в логе, ни в тексте ошибки

#### Scenario: Варианты токена
- **WHEN** выбран тип WebSocket при `secrets.backend: file` и сохранённых секретах `codelab/profiles/ci/token`, `codelab/anthropic` и `codelab/mcp/github/authorization`
- **THEN** вариантов токена четыре в порядке «No token», «Use stored secret», «Store a new token», «From environment variable»; список «Use stored secret» содержит только `codelab/profiles/ci/token`

#### Scenario: Хранилище только для чтения
- **WHEN** выбран тип WebSocket при `secrets.backend` по умолчанию (`env`) на macOS
- **THEN** «Store a new token» неактивен, под ним подсказка `Secret store env is read-only. Add 'secrets.backend: file' …`; «From environment variable» доступен

#### Scenario: Новый токен сохраняется в хранилище
- **WHEN** при `secrets.backend: file` пользователь создаёт WebSocket-профиль `devbox` с «Store a new token» `sk-test-leak-0123456789`, проверяет его на scripted-агенте, требующем этот токен, и сохраняет
- **THEN** проверка показывает `Reachable`, `profiles.json` у `devbox` содержит `tokenRef: secret:codelab/profiles/devbox/token` и не содержит маркера, `codelab secret list` показывает `codelab/profiles/devbox/token`, а ни журнал, ни состояние диалога, ни экран не содержат маркера

#### Scenario: Use stored secret
- **WHEN** пользователь создаёт профиль `ci2` с «Use stored secret» `codelab/profiles/ci/token` и сохраняет
- **THEN** `profiles.json` у `ci2` содержит `tokenRef: secret:codelab/profiles/ci/token`, хранилище не изменено, а `codelab -a ci2` подключается с этим токеном

#### Scenario: Ключ провайдера не предлагается как токен
- **WHEN** в хранилище есть только `codelab/anthropic` и `codelab/mcp/github/authorization`
- **THEN** «Use stored secret» неактивен с подсказкой `No stored secrets in file.`; а профиль из `profiles.json` с ручной ссылкой `secret:codelab/anthropic` по-прежнему подключается с этим значением

#### Scenario: Битый config.yaml
- **WHEN** `config.yaml` содержит синтаксическую ошибку, и пользователь открывает «Add connection profile»
- **THEN** «Store a new token» неактивен, под ним причина бэкенда, а совета добавить `secrets.backend: file` нет

#### Scenario: Секрет с тем же именем уже есть
- **WHEN** в хранилище есть `codelab/profiles/devbox/token`, и пользователь сохраняет новый профиль `devbox` с «Store a new token»
- **THEN** у поля токена показано предупреждение о существующем секрете, ни секрет, ни `profiles.json` не изменены

#### Scenario: Токен из переменной
- **WHEN** app запущено с `DEVBOX_TOKEN=t`, пользователь создаёт WebSocket-профиль `devbox` с «From environment variable» `DEVBOX_TOKEN`, проверяет его на scripted-агенте, требующем токен `t`, и сохраняет
- **THEN** проверка показывает `Reachable`, `profiles.json` у `devbox` содержит `tokenRef: env:DEVBOX_TOKEN` и не содержит `t`

#### Scenario: Переменная не задана
- **WHEN** пользователь вводит имя переменной `MISSING_TOKEN`, которой нет в окружении app
- **THEN** диалог показывает `MISSING_TOKEN is not set in CodeLab's environment.` ровно один раз, под полем имени переменной, и сохранение остаётся доступным; после «Test connection» второго предупреждения о переменной нет

#### Scenario: Отмена
- **WHEN** пользователь заполнил диалог и нажал Esc
- **THEN** `profiles.json` и `shared_preferences` не изменены

#### Scenario: Закрытие во время проверки
- **WHEN** «Test connection» stdio-профиля ждёт ответа на `initialize`, и пользователь закрывает диалог
- **THEN** процесс агента проверки завершён, и исход проверки не записан в состояние страницы

#### Scenario: Тип по умолчанию
- **WHEN** пользователь открывает «Add connection profile» на хосте со stdio- и WebSocket-резолверами, а затем на хосте только с WebSocket-резолвером
- **THEN** в первом случае выбран «Local stdio», во втором переключателя типа нет и открыта форма WebSocket

#### Scenario: Команда не найдена
- **WHEN** stdio-черновик с «Command» `/nonexistent/agent` и аргументами `--token sk-test-leak-0123456789` проверяется
- **THEN** диалог показывает `Command not found: /nonexistent/agent`, без аргументов

#### Scenario: Причины недоступности
- **WHEN** «Test connection» WebSocket-профиля получает по очереди исходы `Unreachable` с причинами `connectionRefused`, `hostNotFound`, `tlsFailed`, `httpStatus` со `statusCode` 500 и `unknown`, у каждого `message` содержит `sk-test-leak-0123456789`
- **THEN** диалог показывает `Unreachable: connection refused`, `Unreachable: host not found`, `Unreachable: TLS handshake failed`, `Unreachable: HTTP 500` и `Unreachable`, а маркер на экране не появляется

#### Scenario: Отказ в доступе с токеном и без
- **WHEN** app запущено с `DEVBOX_TOKEN=t`, и проверка WebSocket-профиля с «From environment variable» `DEVBOX_TOKEN`, затем с «From environment variable» `MISSING_TOKEN` (переменной нет в окружении app), затем с «No token» даёт исход `Unauthorized`
- **THEN** диалог показывает `Unauthorized: the agent rejected the token`, затем дважды `Unauthorized: the agent requires a token`

#### Scenario: Предупреждение под URL
- **WHEN** в поле «URL» введён `ws://10.0.0.5:8765` при «From environment variable», затем выбран «No token»
- **THEN** под полем сначала `ws:// to another machine: the token is sent unencrypted.`, затем `ws:// to another machine: traffic is sent unencrypted.`

#### Scenario: Подтверждение ws:// с токеном
- **WHEN** пользователь сохраняет WebSocket-профиль `ws://10.0.0.5:8765/acp?t=x` с «From environment variable» `DEVBOX_TOKEN`
- **THEN** в диалоге показана панель «Unencrypted connection» с текстом `The token for ws://10.0.0.5:8765 will travel in clear text. Use wss:// if the host supports it.` и кнопкой «Save anyway»; текст не содержит `/acp` и `t=`; профиль записан только после «Save anyway»

#### Scenario: Подтверждение ws:// без токена
- **WHEN** пользователь сохраняет WebSocket-профиль `ws://10.0.0.5:8765` с «No token»
- **THEN** в диалоге показана панель «Unencrypted connection» с текстом `Prompts and files sent to ws://10.0.0.5:8765 will travel in clear text. Use wss:// if the host supports it.` и кнопкой «Save anyway»; без подтверждения `profiles.json` не изменён

#### Scenario: Локальный ws:// без подтверждения
- **WHEN** пользователь сохраняет WebSocket-профиль `ws://localhost:8765`
- **THEN** профиль записывается без панели «Unencrypted connection»

#### Scenario: Откат секрета при отказе записи профиля
- **WHEN** «Store a new token» для `devbox` записан в хранилище, а запись `profiles.json` завершилась ошибкой
- **THEN** секрет `codelab/profiles/devbox/token` удалён, диалог показывает ошибку записи профиля без значения токена, журнал содержит `connection_profile.token_rollback`

#### Scenario: Подтверждение ws:// перед проверкой
- **WHEN** app запущено с `DEVBOX_TOKEN=t`, пользователь вводит `ws://10.0.0.5:8765` с «From environment variable» `DEVBOX_TOKEN` и нажимает «Test connection»
- **THEN** в диалоге показана панель «Unencrypted connection» с текстом про токен и кнопкой «Test anyway» (`add-profile-test-anyway`); транспорт не открыт, и сервер не получил ни одного запроса, пока пользователь не нажал «Test anyway»

#### Scenario: Проверка без токена и к локальному хосту сразу
- **WHEN** пользователь нажимает «Test connection» для `ws://10.0.0.5:8765` с «No token», затем для `ws://localhost:8765` с «From environment variable» `DEVBOX_TOKEN`
- **THEN** обе проверки начинаются без панели «Unencrypted connection»

#### Scenario: Одно подтверждение на URL и токен
- **WHEN** пользователь подтвердил «Test anyway» для `ws://10.0.0.5:8765` с «From environment variable» `DEVBOX_TOKEN`, проверка завершилась, и пользователь нажимает «Save»
- **THEN** профиль записан без повторной панели «Unencrypted connection»

#### Scenario: Возврат к прежнему значению не восстанавливает подтверждение
- **WHEN** пользователь подтвердил «Test anyway» для `ws://10.0.0.5:8765` с `DEVBOX_TOKEN`, меняет URL на `ws://10.0.0.6:8765`, возвращает `ws://10.0.0.5:8765` и нажимает «Save»
- **THEN** снова показана панель «Unencrypted connection» с кнопкой «Save anyway»

#### Scenario: Add another начинает без подтверждения
- **WHEN** пользователь сохранил профиль `ws://10.0.0.5:8765` после «Save anyway», нажал «Add another», ввёл тот же URL с другим id и нажимает «Save»
- **THEN** снова показана панель «Unencrypted connection»

#### Scenario: Строка сохранённого профиля не спрашивает подтверждения
- **WHEN** `profiles.json` содержит профиль `remote` с `ws://10.0.0.5:8765` и `tokenRef: env:DEVBOX_TOKEN`, и пользователь нажимает «Test connection», затем «Use» в строке `remote` и выбирает проект
- **THEN** проверка и старт агента начинаются без панели «Unencrypted connection»

#### Scenario: Смена токена или URL сбрасывает подтверждение
- **WHEN** пользователь подтвердил «Test anyway» для `ws://10.0.0.5:8765` с `DEVBOX_TOKEN`, меняет имя переменной на `OTHER_TOKEN` и нажимает «Save», затем отказывается правкой URL на `ws://10.0.0.6:8765` и нажимает «Test connection»
- **THEN** перед «Save» снова показана панель с кнопкой «Save anyway», а перед проверкой — панель с адресом `ws://10.0.0.6:8765` и кнопкой «Test anyway»; ни запись, ни проверка без подтверждения не происходят

#### Scenario: Userinfo в URL
- **WHEN** пользователь вводит URL `ws://u:sk-test-leak-0123456789@10.0.0.5:8765`
- **THEN** у поля «URL» показано `Remove the user name and password from the URL; use the Token setting instead.`, «Save» и «Save without test» недоступны, `profiles.json` не изменён, а ни диалог, ни журнал не содержат `u:` и `sk-test-leak-0123456789`

#### Scenario: Запись блокирует закрытие
- **WHEN** пользователь нажал «Save», и запись в `profiles.json` ещё не завершилась
- **THEN** «Cancel» неактивна, Esc не закрывает диалог, а повторное нажатие «Save» не даёт второй записи

#### Scenario: Id занят во время подтверждения
- **WHEN** показана панель «Unencrypted connection» для черновика с id `devbox`, за это время `codelab profiles add devbox …` записал профиль `devbox`, и пользователь нажимает «Save anyway»
- **THEN** у поля id показано `A profile with id "devbox" already exists.`, профиль, записанный CLI, не изменён

#### Scenario: Add another, затем Cancel
- **WHEN** пользователь проверяет и сохраняет профиль `a`, нажимает «Add another», сохраняет без проверки профиль `b`, снова нажимает «Add another», затем «Cancel»
- **THEN** страница «Connection» показывает строки `a` с результатом проверки `Reachable` и `b` с меткой «Not tested»

#### Scenario: Изменённый профиль теряет исход проверки
- **WHEN** строка профиля `dev` показывает результат проверки `Reachable`, `codelab` меняет команду профиля `dev` в `profiles.json`, и страница перечитывает файл
- **THEN** строка `dev` больше не показывает `Reachable`

#### Scenario: Rename сохраняет исход проверки
- **WHEN** строка профиля `dev` показывает `Reachable`, и пользователь переименовывает `dev` в «Build box»
- **THEN** строка `dev` по-прежнему показывает `Reachable`

#### Scenario: Исход для изменившегося профиля отбрасывается
- **WHEN** идёт «Test connection» в строке `dev`, за это время `codelab` меняет URL профиля `dev`, страница перечитывает файл, и затем приходит исход `Reachable`
- **THEN** строка `dev` не показывает `Reachable`

### Requirement: «Rename» и «Remove» профиля
«Rename» SHALL менять только `label` профиля; id SHALL оставаться прежним. «Rename» SHALL открывать встроенный редактор `label` прямо в строке профиля (design.md, D14): контейнер редактора `connection-profile-rename-editor-<id>`, поле `connection-profile-rename-field-<id>`, кнопки `connection-profile-rename-save-<id>` и `connection-profile-rename-cancel-<id>`. Отмена SHALL закрывать редактор без записи в `profiles.json`.

«Remove» SHALL спрашивать подтверждение «Remove profile <title>?» (`title` — по правилу заголовка строки; заголовок диалога — 20 px semibold, как у «Add connection profile», design.md D14, D16) и удалять запись из `profiles.json`; переменные окружения и другие хранилища app НЕ SHALL трогать. Если профиль ссылается на собственный секрет `secret:codelab/profiles/<id>/token`, подтверждение SHALL содержать флажок «Also delete the stored token codelab/profiles/<id>/token» (ключ `connection-remove-delete-token`, по умолчанию включён; §12.4.9, шаг 8). Секрет SHALL удаляться только после успешного удаления профиля и только если ни один другой профиль на него не ссылается (spec acp-client-kit «Запись профиля с новым токеном»); секрет, выбранный «Use stored secret», флажка не получает и не удаляется. Ошибка удаления секрета SHALL показываться подсказкой `codelab secret delete <имя>`, профиль при этом остаётся удалённым. Удаление профиля по умолчанию SHALL сбрасывать `codelab.connection.default_profile`. Запрет удаления встроенного профиля, профиля работающего агента и выбранного профиля окна (spec app-settings «Список профилей на странице «Connection»», подсказка `Use another profile first.`) SHALL проверяться перед вызовом `ProfileStore.remove`, а не только недоступностью кнопки.

#### Scenario: Переименование
- **WHEN** пользователь переименовывает `devbox` в «Build box»
- **THEN** `profiles.json` содержит профиль с id `devbox` и `label` «Build box», а `codelab -a devbox` по-прежнему находит его

#### Scenario: Удаление профиля с собственным секретом
- **WHEN** пользователь удаляет профиль `devbox` с `tokenRef: secret:codelab/profiles/devbox/token`, оставив флажок «Also delete the stored token» включённым
- **THEN** `profiles.json` больше не содержит `devbox`, затем удалён секрет `codelab/profiles/devbox/token`; журнал содержит `connection_profile.removed` и `connection_profile.token_deleted`

#### Scenario: Чужой секрет не удаляется
- **WHEN** пользователь удаляет профиль `ci` с `tokenRef: secret:codelab/ws-ci`
- **THEN** флажка удаления секрета нет, профиль удалён, `codelab/ws-ci` остаётся в хранилище

#### Scenario: Удаление профиля
- **WHEN** пользователь удаляет профиль `devbox` по умолчанию с `tokenRef: env:DEVBOX_TOKEN`
- **THEN** `profiles.json` больше не содержит `devbox`, ключ `codelab.connection.default_profile` удалён, а профилем по умолчанию становится встроенный агент

### Requirement: Мастер провайдера в app
«Add provider» и «Edit» SHALL открывать `ProviderWizardDialog` (`ContentDialog`, ключ `provider-wizard`) поверх автомата `ProviderSetupFlow` (spec client-agent-setup «Мастер провайдера»): строка шагов `API type › Base URL › Key › Check › Model › Review`, по шагу на экран, «Back»/«Next»/«Cancel», на шаге ключа — скрытый ввод, на шаге проверки — индикатор и адрес запроса (`scheme://host:port` и путь `/models`), на шаге «Review» — сводка, «Make default» и «This project only» (последний — только при папке проекта). Тексты и варианты отказа проверки SHALL следовать артборду `Wizard`: для `notFound` — заголовок `Model list not found (404)` и варианты «Use <url>/v1» и «Enter the model manually»; для остальных отказов — заголовки `Key rejected (<код>)`, `Server unreachable`, `Timed out after 10 s`, `TLS error`, `Unexpected response (<код>)` и строка запроса `GET <url>/models → <код> · <n> ms`. Подписи шагов SHALL совпадать с артбордом `CliSetup`: `API type`, `Base URL`, `API key source` (`Store in <backend> as "codelab/<id>"`, `Read from environment variable (<VAR>)`, `No key`), `API key`, `Model (type to filter)`, `Enter model id manually` (design.md, D7).

«Edit» SHALL открывать мастер в слое провайдера без переключателя «This project only» и SHALL быть неактивна с подсказкой по тем же отказам, что «Remove»: провайдер не только в слоях `user`/`projectLocal`, в нескольких слоях или в нечитаемом файле (design.md, D7).

Пока идёт запись, «Cancel», Esc и закрытие диалога SHALL быть заблокированы, а повторное «Save» НЕ SHALL давать второй записи. Закрытие диалога SHALL отменять идущую проверку и сбрасывать введённый ключ.

После `ConfigSaved` страница SHALL перечитывать снимок и показывать баннер `saved`. Если ключ заменён под тем же именем, баннер SHALL добавлять `The new key is used after Restart agent (Settings › Connection).`; если агент подключён, а правило перечитывания конфига ядра откладывает записанного провайдера до перезапуска (новый провайдер с ключом или изменённая группа адреса и аутентификации, R0-4; сравнение снимков до и после записи), баннер SHALL быть `Provider <id> saved. Its models are available after Restart agent (Settings › Connection).` (решения Q17, Q35 design.md); иначе — `Provider <id> saved.`; если агент не работает — `Saved. The agent uses it the next time it starts.` без кнопки: агент стартует сам по триггерам рабочего места (spec agent-workbench-ui «Агент стартует сам»); если последний старт агента окна завершился сбоем — тот же текст и кнопка «Retry» (ключ `providers-banner-retry`), которая повторяет намерение, вызвавшее старт (design.md change `require-project-folder`, D13, Q22 (a); ранее — кнопка «Connect», design.md, D9). После `ConfigConflict` мастер SHALL возвращаться в «Review» с тем же черновиком (включая введённый ключ) и баннером `Config changed on disk — review and save again`; план SHALL пересобираться по перечитанному снимку (design.md, D9 «Конфликт и `reload`»), чтобы повторный «Save» не конфликтовал вечно.

#### Scenario: Правка моделей провайдера с прежним ключом
- **WHEN** встроенный агент подключён, и пользователь в мастере правит существующего провайдера с `api_key_secret`, меняя только список моделей
- **THEN** баннер — `Provider <id> saved.` без подсказки про «Restart agent»: агент применяет модели сразу

#### Scenario: Провайдер с ключом в хранилище
- **WHEN** при `secrets.backend: file` и пустом конфиге пользователь проходит мастер «Custom OpenAI-compatible» с адресом тестового сервера, ключом `sk-test-leak-0123456789` и моделью из списка
- **THEN** `config.yaml` содержит `api_key_secret: codelab/<id>` и не содержит маркера, секрет есть в `secrets.yaml`, строка провайдера показывает `Key: in file`; при подключённом встроенном агенте баннер — `Provider <id> saved. Its models are available after Restart agent (Settings › Connection).`, а после «Restart agent» модель видна в селекторе композера

#### Scenario: Только переменная при read-only бэкенде
- **WHEN** бэкенд по умолчанию `env`, и пользователь доходит до шага ключа
- **THEN** вариант «Store in …» отсутствует, показана причина бэкенда, доступны «Read from environment variable» и «No key»

#### Scenario: Отказ проверки по ключу
- **WHEN** проверка мастера получает `401`
- **THEN** шаг «Check» показывает заголовок `Key rejected (401)` и строку `GET <url>/models → 401 · <n> ms`, доступны «Retry» и «Back», «Save without check» нет

#### Scenario: Esc во время проверки
- **WHEN** мастер на шаге проверки ждёт ответа, и пользователь нажимает Esc
- **THEN** диалог закрыт, запрос закрыт, файлы не изменены, журнал содержит `provider_wizard.check_discarded`


#### Scenario: Провайдер сохранён без работающего агента
- **WHEN** агент окна ещё не стартовал (проект не выбран), и пользователь сохраняет провайдера в мастере
- **THEN** баннер — `Saved. The agent uses it the next time it starts.` без кнопки; агент не стартует, пока не сработает триггер рабочего места

#### Scenario: Провайдер сохранён после сбоя старта
- **WHEN** старт встроенного агента в проекте `/work/app` завершился сбоем, и пользователь сохраняет провайдера в мастере страницы «Providers»
- **THEN** баннер — `Saved. The agent uses it the next time it starts.` с кнопкой «Retry» (`providers-banner-retry`); нажатие повторяет намерение, вызвавшее старт, ровно одной попыткой
