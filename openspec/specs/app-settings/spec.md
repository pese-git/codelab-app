# app-settings Specification

## Purpose
Экран настроек codelab-app (`apps/codelab_desktop`) по reference Claude Design (`docs/design/claude-design/`): переход из рабочего места и обратно через `NavigationCubit` без потери сессии, навигация по страницам с поиском, недоступность рабочего места с клавиатуры и заметное ожидающее одобрение. Страница «Connection» управляет профилями из общего с CLI `$CODELAB_HOME/profiles.json`: встроенный агент, профиль по умолчанию, «Use» (выбор профиля окна для следующего старта; агент стартует сам по триггерам рабочего места), «Add connection profile» с проверкой только `initialize`, «Rename» и «Remove», «Restart agent» (единственный перезапуск, во время хода — с подтверждением). Токен профиля — только ссылка `env:<NAME>`; значения секретов, URL с путём и тексты исключений не попадают в UI и журнал. Устройство — `docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` §12.4.9; история решений — архивы changes `2026-11-05-add-app-settings-shell` и `2026-11-12-require-project-folder`.
## Requirements
### Requirement: Переход в настройки и обратно
Переход между рабочим местом и настройками codelab-app SHALL идти только через `NavigationCubit` (`apps/codelab_desktop/lib/app/navigation/`, `dart-agent-and-clients` §12.3 A13, DSK-24). `AppDestination` SHALL быть закрытой иерархией; в этом change в ней две ветки — `WorkbenchDestination` и `SettingsDestination(page)` (design.md, D1).

Настройки SHALL открываться двумя способами:
- сочетанием Cmd+, на macOS и Ctrl+, на других ОС;
- кнопкой «Settings» в подвале сайдбара.

Открываться SHALL последняя выбранная страница (`shared_preferences` `codelab.settings.last_page`, значение — kebab-case slug страницы, например `mcp-servers`). «Connection» SHALL открываться в трёх случаях:
- при первом открытии;
- когда сохранённая страница не видна в этой сборке;
- когда сохранённое значение неизвестно.

Если «Connection» не видна, SHALL открываться первая видимая страница. Если видимых страниц нет, открытие SHALL ничего не делать. Страница, выбранная явно, пока читается `codelab.settings.last_page`, SHALL перекрывать результат чтения.

Esc и кнопка «Back» на экране настроек SHALL возвращать на рабочее место — к сессии, активной в момент ухода, если она ещё открыта; иначе SHALL оставаться текущая активная сессия. Уход в настройки и возврат НЕ SHALL терять текст композера, прокрутку ленты и раскрытые блоки. На рабочем месте без открытого оверлея Esc SHALL сохранять прежний смысл — отмену хода. Ошибка чтения или записи `codelab.settings.last_page` SHALL давать предупреждение в журнале и НЕ SHALL мешать открытию настроек.

#### Scenario: Первое открытие
- **WHEN** ключа `codelab.settings.last_page` нет, и пользователь нажимает Cmd+, на macOS (Ctrl+, на других ОС)
- **THEN** открывается экран настроек со страницей «Connection», пункт `settings-nav-connection` выбран, а после выбора страницы `codelab.settings.last_page` содержит её slug

#### Scenario: Нет видимых страниц
- **WHEN** набор видимых страниц пуст, и пользователь нажимает Cmd/Ctrl+,
- **THEN** экран настроек не открывается, рабочее место не меняется

#### Scenario: Возврат к исходной сессии
- **WHEN** активна сессия `B`, в композере набран текст, пользователь открывает настройки кнопкой «Settings» и нажимает Esc
- **THEN** рабочее место показывает сессию `B` с тем же текстом в композере

#### Scenario: Возврат, когда исходная сессия закрыта
- **WHEN** открыты сессии `A` и `B`, активна `B`, пользователь открывает настройки, сессия `B` закрывается, активной становится `A`, и пользователь нажимает «Back»
- **THEN** рабочее место показывает сессию `A`

#### Scenario: Повторный вход сохраняет исходную сессию
- **WHEN** активна сессия `B`, пользователь открывает настройки, затем снова нажимает Cmd/Ctrl+, и выбирает другую страницу
- **THEN** «Back» возвращает к сессии `B`

#### Scenario: Явная страница во время чтения
- **WHEN** чтение `codelab.settings.last_page` со значением `general` ещё не завершилось, а пользователь выбрал страницу «Connection»
- **THEN** открыта «Connection», и позднее завершение чтения её не меняет

#### Scenario: Сохранённая страница скрыта
- **WHEN** `codelab.settings.last_page` содержит `providers`, а в сборке страница «Providers» недоступна
- **THEN** открывается «Connection»

#### Scenario: Esc на рабочем месте
- **WHEN** экран настроек закрыт, идёт ход, и пользователь нажимает Esc
- **THEN** ход отменяется, как раньше, а настройки не открываются

### Requirement: Рабочее место недоступно с клавиатуры из настроек
Пока открыт экран настроек, смонтированное под ним рабочее место НЕ SHALL получать фокус и клавиатурные события (design.md, D2, H1). Из настроек клавиатурой НЕ SHALL можно:
- отправить промпт (`session/prompt`);
- ответить на запрос разрешения;
- отменить ход (`session/cancel`).

Esc на экране настроек SHALL только возвращать на рабочее место. После возврата фокус SHALL восстанавливаться в элементе, где он был до ухода, если тот ещё существует, иначе — в композере активной сессии.

#### Scenario: Esc в настройках во время хода
- **WHEN** в активной сессии идёт ход, пользователь открывает настройки и нажимает Esc
- **THEN** экран возвращается на рабочее место, агенту не отправлен `session/cancel`, ход продолжается

#### Scenario: Клавиши не отвечают на одобрение
- **WHEN** в активной сессии ждёт карточка одобрения, пользователь открывает настройки и нажимает Tab, Space и Enter
- **THEN** фокус ходит только по элементам настроек, ответ на `session/request_permission` не отправлен, карточка по-прежнему ждёт

#### Scenario: Ввод не уходит в композер
- **WHEN** фокус был в композере, пользователь открывает настройки, вводит текст и нажимает Enter и Cmd/Ctrl+Enter
- **THEN** агенту не отправлен `session/prompt`, текст композера не изменился, а после «Back» фокус снова в композере

### Requirement: Ожидающее одобрение видно из настроек
Пока открыт экран настроек и у активной или любой открытой сессии есть ожидающий запрос разрешения, над страницей настроек SHALL показываться InfoBar уровня `warning` (ключ `settings-pending-approval`) с текстом `Agent is waiting for your approval` и кнопкой `Back to session` (решение пользователя 2026-11-04).

Кнопка SHALL возвращать на рабочее место и делать активной сессию с запросом. Если сессий с запросом несколько, выбирается активная, иначе первая в порядке сайдбара. Ответ на запрос SHALL даваться только на рабочем месте; в настройках вариантов ответа НЕ SHALL быть. Автоматического возврата на рабочее место НЕ SHALL быть.

InfoBar SHALL исчезать, когда ожидающих запросов не осталось. Пока соединение не в состоянии `Connected`, и для сессии со статусом `detached`, InfoBar НЕ SHALL показываться: на запрос мёртвого соединения ответить нельзя. Событие журнала `settings.pending_approval_shown` пишется один раз при появлении, `settings.back_to_approval` — при нажатии кнопки. Id запроса и поля tool call в эти события НЕ SHALL попадать.

#### Scenario: Запрос в фоновой сессии
- **WHEN** открыты настройки, активна сессия `A`, а в сессии `B` агент присылает `session/request_permission`
- **THEN** показан InfoBar `settings-pending-approval`, экран настроек остаётся открытым, а после `Back to session` рабочее место показывает сессию `B` с карточкой одобрения

#### Scenario: Запрос снят
- **WHEN** InfoBar показан, и ход сессии с запросом отменяется
- **THEN** InfoBar исчезает, экран настроек остаётся открытым

#### Scenario: Соединение потеряно
- **WHEN** InfoBar показан, и соединение с агентом потеряно
- **THEN** InfoBar исчезает, экран настроек остаётся открытым

#### Scenario: Сессия не загрузилась после переподключения
- **WHEN** после переподключения `session/load` сессии с прежним ожидающим запросом завершился ошибкой, и сессия стала `detached`
- **THEN** InfoBar для неё не показывается

#### Scenario: Без вариантов ответа
- **WHEN** InfoBar показан
- **THEN** на экране настроек нет кнопок вариантов одобрения, и журнал не содержит id запроса и имени инструмента

### Requirement: Навигация настроек
Экран настроек SHALL показывать одну навигацию (Fluent `NavigationView`) с полем поиска «Find a setting» и группами «Agent» и «App» в фиксированном порядке `dart-agent-and-clients` §12.4.9:
- Agent: Connection, Providers, MCP servers, Agents & modes, Permissions & tools, Redaction, Skills & extensions, Code & web;
- App: General, Appearance, Keyboard.

Страница без содержимого в текущей сборке SHALL быть скрыта, а не пуста (SETUP-17); группа без видимых страниц НЕ SHALL показывать заголовок. Набор видимых страниц SHALL задавать composition root. Пункт навигации SHALL иметь ключ теста `settings-nav-<page>` (kebab-case: `settings-nav-connection`, `settings-nav-mcp-servers`).

Поиск SHALL отбирать страницы по совпадению подстроки без учёта регистра с заголовком страницы или её ключевыми словами. При пустом результате SHALL показываться строка `No settings match "<query>"`.

При ширине окна меньше 760 px навигация SHALL располагаться сверху, при 760 px и шире — панелью слева.

#### Scenario: Только существующие страницы
- **WHEN** сборка содержит только страницу «Connection»
- **THEN** навигация показывает группу «Agent» с единственным пунктом `settings-nav-connection`, заголовка «App» и пунктов других страниц нет

#### Scenario: Порядок не зависит от регистрации
- **WHEN** тестовая сборка регистрирует страницы `keyboard`, `connection`, `general` в этом порядке
- **THEN** навигация показывает Connection в группе «Agent», затем General и Keyboard в группе «App»

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `token` в «Find a setting»
- **THEN** в навигации остаётся «Connection», а выбор результата открывает эту страницу

#### Scenario: Узкое окно
- **WHEN** ширина окна 700 px
- **THEN** пункты навигации настроек расположены сверху, а не панелью слева

### Requirement: Список профилей на странице «Connection»
Страница «Connection» SHALL показывать профили подключения в таком порядке:
1. встроенный агент — первым, всегда, независимо от файла; в `profiles.json` он НЕ SHALL сохраняться;
2. профили `ProfileStore` из `$CODELAB_HOME/profiles.json` в порядке файла. Это тот же файл и тот же `JsonFileProfileStore`, что у CLI. `CODELAB_HOME` SHALL разрешаться той же функцией `codelab_client_io`, что у CLI (design.md, D7): по умолчанию `~/.codelab`, `~` и `~/…` раскрываются через `HOME`, а `~user/…` и `~` без `HOME` — ошибка.

Строка профиля SHALL показывать:
- заголовок (`title`) — `label` в одну строку с многоточием и полным текстом в подсказке. Если `label` пуст или совпадает со значением `--agent`, из которого профиль создан (начинается с `stdio:`, `ws://` или `wss://`), заголовком SHALL быть `id`. Тем же правилом `title` SHALL пользоваться подтверждение «Remove» и подпись профиля на экране подключения и в баннере соединения рабочего места; сырой `label` там НЕ SHALL показываться;
- вторую строку — команду stdio без аргументов или origin WebSocket-адреса (`scheme://host:port`), без `env` и значения токена;
- метку «Current» — только у профиля работающего агента окна (принятый профиль в `Connected` или `Reconnecting`). После сбоя и во время новой попытки «Current» НЕ SHALL быть ни у одной строки, кроме случая отказа до обращения к workspace при живом соединении;
- бейдж попытки (ключ `connection-profile-status-<id>`): `Connecting…`, `Connected` или `Failed` — у строки профиля последней попытки (`ConnectionCommands.attemptProfile`), без текста ошибки;
- метки «Default», «Current» и «Selected» (профиль окна для следующего старта агента, если он не «Current»).

Метки проверки профиля («Not tested») и исхода проверки строка НЕ SHALL показывать: отдельной проверки профиля в app нет, профиль проверяется стартом агента после «Use» (design.md change `remove-test-connection`, D1, D4).

Строка SHALL предлагать действия «Use», «Rename» и «Remove». Действия «Test connection» НЕ SHALL быть ни у одной строки. У встроенного агента НЕ SHALL быть «Rename» и «Remove». «Remove» SHALL быть недоступна у профиля работающего агента и у выбранного профиля окна, с подсказкой `Use another profile first.`.

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

#### Scenario: Строка без проверки профиля
- **WHEN** `profiles.json` содержит профили `dev` (stdio) и `remote` (WebSocket), и пользователь открывает «Connection»
- **THEN** ни у одной строки нет кнопки `connection-profile-test-<id>`, исхода `connection-profile-probe-<id>` и метки «Not tested»; у `dev` и `remote` есть «Use», «Rename» и «Remove»

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

### Requirement: Предупреждение и справка для удалённого агента
Пока текущий профиль — WebSocket в состоянии `Connected`, страница «Connection» SHALL показывать InfoBar уровня `warning`: `Read-only: this agent runs on <scheme://host:port>. Change providers and MCP on that host: codelab provider add, codelab mcp add, codelab config set.`. Путь, query и userinfo URL в этом тексте НЕ SHALL показываться. Профили клиента при этом SHALL оставаться редактируемыми.

Страница SHALL содержать свёрнутый по умолчанию Expander «Join a session started in the CLI» со статичной справкой о запуске `codelab-agent serve --ws` и выборе того же WebSocket-профиля в app и CLI. Справка НЕ SHALL описывать блокировку сессии, режим только для чтения и «Fork»: lease не реализован (design.md, D10).

#### Scenario: InfoBar при WebSocket
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp?x=1`
- **THEN** InfoBar содержит `wss://devbox:7420`, не содержит `/acp` и `x=1`, а «Add profile» доступна

### Requirement: Диалог «Add connection profile»
Кнопка «Add profile» SHALL открывать `ContentDialog` «Add connection profile». Логика черновика SHALL жить в `codelab_client_core` (`ProfileDraft`, `ProfileCommitter`; spec acp-client-kit), а диалог только рисует её через `AddProfileCubit`.

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
- Значение нового токена диалог SHALL держать только в памяти (`SecretText`) и НЕ SHALL показывать после ввода; значение выбранного «Use stored secret» диалог НЕ SHALL читать (design.md change `remove-test-connection`, D4).
- Для «From environment variable» под полем SHALL показываться подсказка `CodeLab reads the token from this environment variable when it connects. Token values are not saved in profiles.json.` и строка `Apps opened from Finder do not see variables set in your shell profile.`.
- Если переменная не задана в окружении app, диалог SHALL показывать `<NAME> is not set in CodeLab's environment.` один раз — подсказкой под полем имени переменной. Других предупреждений о незаданной переменной диалог НЕ SHALL показывать (решение пользователя 2026-11-05; design.md change `add-app-settings-shell`, D13). Сохранение с незаданной переменной SHALL оставаться доступным.

**Проверки подключения нет.** Диалог НЕ SHALL открывать транспорт, запускать процесс агента или отправлять ACP-запросы: кнопки «Test connection», строки «Check» и исхода проверки в нём нет. Профиль проверяется стартом агента после «Use» в строке профиля (design.md change `remove-test-connection`, D1, D4).

**Сохранение с токеном в хранилище.** Для «Store a new token» запись SHALL идти через `ProfileCommitter` в порядке «секрет → профиль» с откатом секрета, если профиль не записан (SETUP-19; spec acp-client-kit «Запись профиля с новым токеном»). Если секрет `codelab/profiles/<id>/token` уже существует, диалог SHALL показывать у поля токена `A stored token codelab/profiles/<id>/token already exists in <backend>. Choose it with "Use stored secret" or remove it with codelab secret delete.` и НЕ SHALL ничего записывать. Ошибка отката SHALL показываться текстом `The profile was not saved; the token stays in <backend> as <имя>. Remove it with codelab secret delete <имя>.`.

**Сохранение.** Кнопка записи SHALL называться «Save». Флажок «Use by default» (по умолчанию выключен) делает профиль профилем по умолчанию; текущее подключение диалог НЕ SHALL менять.

Нажатие «Save» SHALL переводить диалог в состояние записи до чтения списка существующих id; повторное нажатие в этом состоянии НЕ SHALL давать второй записи. Пока идёт запись, «Cancel» SHALL быть неактивна, а Esc и закрытие диалога SHALL быть заблокированы. «Save anyway» SHALL перед записью заново читать список id: если id уже занят, диалог SHALL показывать ошибку `idTaken` у поля id, а существующий профиль НЕ SHALL перезаписываться.

**Подтверждение `ws://` к нелокальному хосту.** Сохранение профиля с `ws://` к хосту вне `localhost`, `127.0.0.0/8` и `::1` SHALL всегда требовать подтверждения — и с токеном, и без него (решение пользователя 2026-11-05). Подтверждение — панель InfoBar уровня `warning` внутри диалога «Add connection profile», как в артборде `AddProfile`, с заголовком «Unencrypted connection» и кнопкой «Save anyway» (ключ `add-profile-save-anyway`); текст:
- с токеном — `The token for <scheme://host:port> will travel in clear text. Use wss:// if the host supports it.`;
- без токена — `Prompts and files sent to <scheme://host:port> will travel in clear text. Use wss:// if the host supports it.`.

В адресе SHALL показываться только `scheme://host:port`; путь, query и userinfo URL НЕ SHALL показываться. Отдельной кнопки отказа у панели нет: отказ — правка черновика или «Cancel»; без «Save anyway» запись НЕ SHALL происходить.

Подтверждение SHALL действовать для пары «URL, выбор токена» черновика: повторное «Save» после «Save anyway» (после ошибки записи или правки id) повторного подтверждения НЕ SHALL требовать. Изменение URL, варианта токена, имени переменной, выбранного секрета или значения нового токена SHALL сбрасывать подтверждение, даже если значение затем возвращено к прежнему; «Add another» SHALL начинать черновик без подтверждения.

Старт агента с профилем, выбранным «Use», подтверждения `ws://` НЕ SHALL спрашивать (решение пользователя 2026-11-05; «Use» заменил «Connect», design.md change `require-project-folder`, D18).

После сохранения диалог SHALL показывать экран «Profile saved» с id, текстом `The running agent is unchanged. Select it with Use in the profile row; Restart agent applies it.` (design.md change `require-project-folder`, Q22 (a)) и кнопками «Done» и «Add another». InfoBar экрана SHALL содержать `Added to profiles.json as <id>` и, если профиль сделан профилем по умолчанию, ` · used by default`; пометки о проверке профиля (`marked "Not tested"`) на экране НЕ SHALL быть (design.md change `remove-test-connection`, D4). «Cancel» и Esc без сохранения SHALL закрывать диалог без записи в `profiles.json` и `shared_preferences`.

После закрытия диалога страница «Connection» SHALL показывать все профили, сохранённые за жизнь диалога (в том числе сохранённые до «Add another»).

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
- **WHEN** при `secrets.backend: file` пользователь создаёт WebSocket-профиль `devbox` с «Store a new token» `sk-test-leak-0123456789` и сохраняет
- **THEN** `profiles.json` у `devbox` содержит `tokenRef: secret:codelab/profiles/devbox/token` и не содержит маркера, `codelab secret list` показывает `codelab/profiles/devbox/token`, транспорт не открывался, а ни журнал, ни состояние диалога, ни экран не содержат маркера

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
- **WHEN** app запущено с `DEVBOX_TOKEN=t`, пользователь создаёт WebSocket-профиль `devbox` с «From environment variable» `DEVBOX_TOKEN` и сохраняет, затем нажимает «Use» в строке `devbox`, и агент стартует на scripted-агенте, требующем токен `t`
- **THEN** `profiles.json` у `devbox` содержит `tokenRef: env:DEVBOX_TOKEN` и не содержит `t`, а строка `devbox` получает «Current» и `Connected`

#### Scenario: Переменная не задана
- **WHEN** пользователь вводит имя переменной `MISSING_TOKEN`, которой нет в окружении app
- **THEN** диалог показывает `MISSING_TOKEN is not set in CodeLab's environment.` ровно один раз, под полем имени переменной, и сохранение остаётся доступным

#### Scenario: Отмена
- **WHEN** пользователь заполнил диалог и нажал Esc
- **THEN** `profiles.json` и `shared_preferences` не изменены

#### Scenario: Тип по умолчанию
- **WHEN** пользователь открывает «Add connection profile» на хосте со stdio- и WebSocket-резолверами, а затем на хосте только с WebSocket-резолвером
- **THEN** в первом случае выбран «Local stdio», во втором переключателя типа нет и открыта форма WebSocket

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

#### Scenario: Одно подтверждение на URL и токен
- **WHEN** пользователь подтвердил «Save anyway» для `ws://10.0.0.5:8765` с «From environment variable» `DEVBOX_TOKEN`, запись `profiles.json` завершилась ошибкой, и пользователь снова нажимает «Save»
- **THEN** профиль записан без повторной панели «Unencrypted connection»

#### Scenario: Возврат к прежнему значению не восстанавливает подтверждение
- **WHEN** пользователь подтвердил «Save anyway» для `ws://10.0.0.5:8765` с `DEVBOX_TOKEN`, запись завершилась ошибкой, пользователь меняет URL на `ws://10.0.0.6:8765`, возвращает `ws://10.0.0.5:8765` и нажимает «Save»
- **THEN** снова показана панель «Unencrypted connection» с кнопкой «Save anyway»

#### Scenario: Add another начинает без подтверждения
- **WHEN** пользователь сохранил профиль `ws://10.0.0.5:8765` после «Save anyway», нажал «Add another», ввёл тот же URL с другим id и нажимает «Save»
- **THEN** снова показана панель «Unencrypted connection»

#### Scenario: Строка сохранённого профиля не спрашивает подтверждения
- **WHEN** `profiles.json` содержит профиль `remote` с `ws://10.0.0.5:8765` и `tokenRef: env:DEVBOX_TOKEN`, и пользователь нажимает «Use» в строке `remote` и выбирает проект
- **THEN** старт агента начинается без панели «Unencrypted connection»

#### Scenario: Смена токена или URL сбрасывает подтверждение
- **WHEN** пользователь подтвердил «Save anyway» для `ws://10.0.0.5:8765` с `DEVBOX_TOKEN`, запись завершилась ошибкой, пользователь меняет имя переменной на `OTHER_TOKEN` и нажимает «Save», затем отказывается правкой URL на `ws://10.0.0.6:8765` и снова нажимает «Save»
- **THEN** оба раза снова показана панель с кнопкой «Save anyway» (во второй раз — с адресом `ws://10.0.0.6:8765`); без подтверждения запись не происходит

#### Scenario: Userinfo в URL
- **WHEN** пользователь вводит URL `ws://u:sk-test-leak-0123456789@10.0.0.5:8765`
- **THEN** у поля «URL» показано `Remove the user name and password from the URL; use the Token setting instead.`, «Save» недоступна, `profiles.json` не изменён, а ни диалог, ни журнал не содержат `u:` и `sk-test-leak-0123456789`

#### Scenario: Запись блокирует закрытие
- **WHEN** пользователь нажал «Save», и запись в `profiles.json` ещё не завершилась
- **THEN** «Cancel» неактивна, Esc не закрывает диалог, а повторное нажатие «Save» не даёт второй записи

#### Scenario: Id занят во время подтверждения
- **WHEN** показана панель «Unencrypted connection» для черновика с id `devbox`, за это время `codelab profiles add devbox …` записал профиль `devbox`, и пользователь нажимает «Save anyway»
- **THEN** у поля id показано `A profile with id "devbox" already exists.`, профиль, записанный CLI, не изменён

#### Scenario: Add another, затем Cancel
- **WHEN** пользователь сохраняет профиль `a`, нажимает «Add another», сохраняет профиль `b`, снова нажимает «Add another», затем «Cancel»
- **THEN** страница «Connection» показывает строки `a` и `b`, и ни у одной нет метки «Not tested» и исхода проверки

#### Scenario: Диалог без проверки подключения
- **WHEN** пользователь открывает «Add connection profile» на хосте со stdio- и WebSocket-резолверами и заполняет корректный stdio-черновик, затем переключается на WebSocket
- **THEN** ни в одной форме нет строки «Check», кнопок `add-profile-test` и `add-profile-test-anyway` и исхода `add-profile-probe-result`; кнопка `add-profile-save` называется «Save»

#### Scenario: Сохранение не обращается к агенту
- **WHEN** при `secrets.backend: file` и сохранённом секрете `codelab/profiles/ci/token` пользователь сохраняет WebSocket-профиль `ws://localhost:8765` с «Use stored secret» `codelab/profiles/ci/token`, затем stdio-профиль с командой `/nonexistent/agent`
- **THEN** оба профиля записаны в `profiles.json`, ни один транспорт не открыт, процесс не запущен, `ProfileSecrets.read` не вызывался, а журнал не содержит событий `connection_profile.probe_*`

#### Scenario: Экран «Profile saved» без пометки проверки
- **WHEN** пользователь сохраняет профиль `dev` без флажка «Use by default», затем через «Add another» — профиль `dev2` с флажком
- **THEN** InfoBar первого экрана содержит `Added to profiles.json as dev` без `Not tested`; второго — `Added to profiles.json as dev2 · used by default`

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

### Requirement: События журнала настроек без секретов
Экран настроек и страница «Connection» SHALL писать в журнал приложения структурные события с `profile_id` (design.md change `add-app-settings-shell`, D17):
- `settings.opened`, `settings.page_selected`, `settings.closed`;
- `connection_profile.saved`, `connection_profile.renamed`, `connection_profile.removed`, `connection_profile.save_failed`;
- `connection_profile.default_changed`, `connection_profile.unreadable`, `connection_profile.token_ref_unsupported`, `connection_profile.default_ignored`, `connection_profile.default_removed`;
- `connection_profile.token_stored`, `connection_profile.token_rollback`, `connection_profile.token_rollback_failed`, `connection_profile.token_deleted`, `connection_profile.token_delete_failed` — с `profile_id` и `backend` (design.md change `add-provider-setup-ui`, D18);
- `connection_profile.token_secret_missing` — только с `profile_id` (D13).

`connection_profile.saved` SHALL содержать поле `token: none | env | secret` и НЕ SHALL содержать поля `tested`. События `connection_profile.probe_started`, `connection_profile.probe_finished` и `connection_profile.probe_discarded` НЕ SHALL писаться: проверки профиля в app нет (design.md change `remove-test-connection`, D6). Событие `connection.connect_on_start` НЕ SHALL писаться: «Connect on start» удалён (design.md change `require-project-folder`, D19). `connection_profile.save_failed` SHALL содержать поле `stage`: `profile` — не записан профиль в `profiles.json`, `default` — профиль записан, но не записан ключ «Use by default» `codelab.connection.default_profile`.

События и тексты ошибок на экране НЕ SHALL содержать:
- значения и имена переменных токена, значения нового токена, имена секретов токена и значения ссылок на токен не вида `env:` и `secret:`;
- аргументы и значения `env` stdio-профиля;
- путь, query и userinfo URL;
- текст `toString()` исключений — только имя типа.

#### Scenario: Маркер секрета не утекает
- **WHEN** app запущено с `DEVBOX_TOKEN=sk-test-leak-0123456789`, пользователь сохраняет WebSocket-профиль с `env:DEVBOX_TOKEN` и URL `wss://host:1/acp?t=sk-test-leak-0123456789`, а запись профиля завершается исключением, чей `toString()` содержит тот же маркер
- **THEN** журнал содержит `connection_profile.save_failed` с именем типа исключения, а ни журнал, ни диалог не содержат `sk-test-leak-0123456789`, `/acp` и `t=`

#### Scenario: События сохранения без проверки
- **WHEN** пользователь сохраняет stdio-профиль `dev`, затем открывает и закрывает страницу «Connection»
- **THEN** журнал содержит `connection_profile.saved` с `profile_id: dev` и `token: none` без поля `tested`, и не содержит событий `connection_profile.probe_*`

### Requirement: Страницы Providers и MCP servers в навигации
Composition root SHALL делать видимыми страницы «Connection», «Providers» и «MCP servers» группы «Agent» в порядке требования «Навигация настроек»; остальные страницы остаются скрытыми (SETUP-17). Тела страниц SHALL иметь ключи `settings-providers` и `settings-mcp`. Поиск «Find a setting» SHALL находить «Providers» по ключевым словам `provider`, `model`, `api key`, `key storage`, `base url`, а «MCP servers» — по `mcp`, `server`, `tools`, `headers`.

#### Scenario: Три страницы группы Agent
- **WHEN** пользователь открывает настройки
- **THEN** навигация показывает в группе «Agent» пункты `settings-nav-connection`, `settings-nav-providers`, `settings-nav-mcp-servers` в этом порядке, заголовка «App» нет

#### Scenario: Поиск ключа API
- **WHEN** пользователь вводит `api key` в «Find a setting»
- **THEN** в навигации остаётся «Providers»

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

### Requirement: Страница «Providers»
Страница «Providers» для `EditableSettings` SHALL показывать по артборду `Providers` (design.md, D10):
- «Add provider» в шапке;
- строку «Default model» (ComboBox моделей каталога) с подписью `Used by new sessions.` и, если у активной сессии есть опция `model`, `Active in this session: <model>`;
- строку «Key storage» с `id` бэкенда, тегом `writable` или `read-only` и подписью `Only key names and presence are read — values never enter the app`. Для `file` SHALL добавляться строка об открытом файле, а при `unavailableReason` — InfoBar с причиной;
- «Configured providers» — Expander на провайдера: id, метка «Default», подпись `<id> · <вид> · [<base_url> ·] <ключ> · <n> model(s)`, источник `defined in <file>` для слоя 3, файла `--config` и переменных окружения, тег последней проверки;
- `Config file: <path>`.

Статус ключа SHALL вычисляться без чтения значения: `Key: in <backend>`, `Key: missing in <backend>`, `Key: env <VAR> (set)` / `(not set)`, `No key`, `Key: in config file (plain text)` (литеральный `api_key` в файле). У провайдера с литеральным ключом «Check» SHALL быть неактивна с подсказкой `The key is written in config.yaml. Move it to the secret store: codelab secret migrate.`: app не читает литеральное значение из конфига, а проверка без ключа дала бы ложный `unauthorized` (design.md change `add-provider-setup-ui`, D10). Провайдеры слоя 3, `--config` и окружения SHALL показываться без «Edit» и «Remove».

Действия:
- **Check** SHALL читать ключ в адаптере composition root и передавать его прямо в `ProviderCheck`; в состоянии страницы остаётся только итог (`ok, <n> models`, вид отказа, время и длительность). Повторный Check и закрытие страницы SHALL отменять прежнюю проверку, поздний итог НЕ SHALL менять строку;
- **Default model** SHALL писать `agent.default_model` в слой, где ключ определён сейчас, если он редактируемый, иначе в `user`;
- **Edit** SHALL открывать мастер провайдера в режиме правки;
- **Remove** SHALL спрашивать подтверждение `Remove provider <id>?` с флажком «Also delete the stored key» (включён, если `api_key_secret` равен `codelab/<id>` и другие провайдеры этот секрет не используют) и выбором «New default model», если удаляется провайдер модели по умолчанию. Правки SHALL идти одним `apply`; секрет SHALL удаляться только после `ConfigSaved`. Последнего провайдера «Remove» SHALL не удалять: кнопка неактивна с подсказкой `The agent needs at least one provider. Add another provider first.`.

Без провайдеров страница SHALL показывать `No providers yet. The embedded agent needs one to run a turn.` и «Add provider» (ключ `providers-empty`).

Дополнительно для «Check» (design.md change `add-provider-setup-ui`, D8, D10):
- для `http://` к хосту вне `localhost`, `127.0.0.0/8` и `::1` рядом с «Check» SHALL показываться предупреждение `The key is sent unencrypted to <host>.`; «Check» остаётся доступной без диалога, потому что адрес уже записан в конфиге (трактовка SETUP-10 для страницы, решение пользователя 2026-11-06). Подтверждение адреса остаётся в мастере;
- для вида без проверки (`gemini` и неизвестные) «Check» SHALL быть неактивна с подсказкой `Check is not available for <kind> providers yet.`; список проверяемых видов и адреса по умолчанию даёт мост;
- смена подключения окна SHALL отменять идущие проверки страницы (D21).

Подпись строки SHALL показывать `base_url` без userinfo, query и fragment.

Значение ключа НЕ SHALL попадать в состояние Cubit, на экран и в журнал (SETUP-1).

#### Scenario: Статус ключа без чтения значения
- **WHEN** конфиг задаёт провайдеров `anthropic` (`api_key_secret: codelab/anthropic`, секрет есть в `file`), `openai` (`api_key_env: OPENAI_API_KEY`, переменная задана) и `team` (`api_key_secret: codelab/team`, секрета нет)
- **THEN** строки показывают `Key: in file`, `Key: env OPENAI_API_KEY (set)` и `Key: missing in file`; ни один секрет не читался

#### Scenario: http:// к удалённому хосту
- **WHEN** провайдер `lan` задан с `base_url: http://10.0.0.5:8000/v1`
- **THEN** рядом с «Check» строки `lan` показано `The key is sent unencrypted to 10.0.0.5.`, «Check» доступна и выполняется без диалога; у `http://localhost:11434/v1` предупреждения нет

#### Scenario: Вид без проверки
- **WHEN** провайдер `g` задан с `kind: gemini`
- **THEN** «Check» строки `g` неактивна с подсказкой `Check is not available for gemini providers yet.`, запроса нет

#### Scenario: base_url без секретов в подписи
- **WHEN** провайдер задан с `base_url: https://u:sk-test-leak-0123456789@llm.example/v1?k=x#f`
- **THEN** подпись строки содержит `https://llm.example/v1` и не содержит `u:`, маркера, `k=x` и `#f`

#### Scenario: Смена подключения отменяет Check
- **WHEN** «Check» строки ждёт ответа, а окно переключается на другой профиль
- **THEN** проверка отменена, соединение закрыто, итог не записан в строку

#### Scenario: Литеральный ключ в config.yaml (согласовано пользователем 2026-11-06)
- **WHEN** провайдер `old` задан в `config.yaml` с `api_key: sk-test-leak-0123456789`
- **THEN** строка показывает `Key: in config file (plain text)`, «Check» неактивна с подсказкой про `codelab secret migrate`, запроса к `/models` нет, маркер не появляется на экране и в журнале

#### Scenario: Check с неверным ключом
- **WHEN** тестовый сервер `/models` отвечает `401`, и пользователь нажимает «Check» в строке `anthropic`
- **THEN** тег строки — `unauthorized`, состояние страницы и журнал не содержат значения ключа и тела ответа

#### Scenario: Закрытие страницы во время Check
- **WHEN** «Check» ждёт ответа, и пользователь уходит со страницы
- **THEN** отмена передана в `ProviderCheck.listModels`, соединение закрыто (сервер видит разрыв), итог не записан, журнал содержит `provider_settings.check_discarded`

#### Scenario: Удаление провайдера модели по умолчанию
- **WHEN** провайдеры `anthropic` (модель по умолчанию) и `local`, пользователь удаляет `anthropic`, выбирает новую модель `local/qwen` и оставляет флажок удаления ключа
- **THEN** одной записью удалена таблица `providers.anthropic`, `agent.default_model` = `local/qwen`; после записи удалён секрет `codelab/anthropic`; комментарии файла сохранены

#### Scenario: Последний провайдер
- **WHEN** в конфиге один провайдер
- **THEN** «Remove» неактивна с подсказкой о минимум одном провайдере

#### Scenario: Конфликт записи
- **WHEN** файл изменён на диске между открытием страницы и сменой «Default model»
- **THEN** страница показывает баннер конфликта, файл не перезаписан, страница перечитала снимок

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

### Requirement: Страница «MCP servers»
Страница «MCP servers» для `EditableSettings` SHALL показывать по артборду `Mcp` (design.md, D11) серверы эффективного конфига: имя, тип, источник (`user`, `this project`, `defined in <file>`), цель (команда или URL; `args`, `env` и `headers` — по правилу безопасного показа значений конфига ядра, как `codelab provider list` и `codelab config get`), переключатель `enabled`. Раскрытая строка SHALL содержать редактор `McpServerDraft` (имя, тип, поля типа, строки `headers`/`env` с флажком «Secret», «Save to User config» / «This project only», «Save», «Reconnect», «Remove»).

Правила записи:
- значение с флажком «Secret» SHALL записываться в хранилище под `SecretNames.forMcp(name, key)`, а в конфиг — `${secret:<имя>}`, в порядке «секрет → конфиг → откат» (SETUP-5). При бэкенде только для чтения флажок SHALL быть неактивен с причиной бэкенда. Существующий секрет с тем же именем НЕ SHALL перезаписываться без явного выбора «Replace it»; вопрос SHALL называть имя секрета и последствия замены, а «Keep it» SHALL закрывать вопрос без записи. Сохранённое секретное значение SHALL показываться как `stored`, пустое поле при правке SHALL означать «не менять». Так же SHALL показываться значение, которое строка списка маскирует (токен в `args`, секретный параметр query URL, литеральный заголовок или `env`, команда): маска с плейсхолдером `Hidden — leave empty to keep`, прежнее значение сохраняется, пока поле не изменено, а новое вводится целиком; значение и маркер секрета НЕ SHALL появляться на экране (ревью 5b, design.md D11). После записи сервера секреты страницы `codelab/mcp/<сервер>/…`, на которые новый элемент больше не ссылается, SHALL удаляться по правилу «Remove» (только без оставшихся ссылок в свежем снимке), а баннер `saved` SHALL называть оставленные и не удалённые; если свежий снимок не прочитан или в нём битый слой, ни один секрет НЕ SHALL удаляться (так же для «Remove»). Существующий секрет, найденный до записи, SHALL вызывать вопрос `A secret with this name is already stored` с именем секрета и фразами `The new value replaces the secret for every server that refers to it.` и `A running agent keeps the old value until the server reconnects.`; сбой чтения хранилища SHALL давать `The secret store could not be read, so nothing was saved.` без записи;
- переключатель `enabled` SHALL писать `UpsertMcpServer` в слой сервера; у сервера слоя 3 переключатель неактивен, а кнопка «Disable here» SHALL писать `{name, enabled: false}` в `projectLocal`; такая строка SHALL оставаться видимой по проектному слою с пометкой `disabled here` и кнопкой «Enable here», которая SHALL удалять переопределение (`RemoveMcpServer(name)` из `projectLocal`) (решение Q21 design.md). Переключатель и правка сервера своего слоя SHALL писать элемент слоя целиком с изменённым полем, без потери остальных ключей;
- «Add server» SHALL открывать карточку `New server` в начале списка с пустым редактором, «Save» и «Cancel»; «Cancel» SHALL убирать карточку без записи. Пустой список SHALL показывать `No MCP servers yet.` и «Add server». При правке существующего сервера имя и цель «Save to» SHALL быть только для чтения с подписью `To move a server to another file, remove it and add it again.`: переименование и перенос между слоями — «Remove» и «Add server» (решения Q25, Q27 design.md). Аргументы `stdio`-сервера SHALL вводиться по одному на строку как есть, пустые строки SHALL отбрасываться (design.md, D24);
- «Remove» SHALL сначала спрашивать подтверждение `Remove <name>?` со списком секретов страницы, которые будут удалены; без подтверждения запись НЕ SHALL выполняться. Затем «Remove» SHALL писать `RemoveMcpServer(name)` и после `ConfigSaved` удалять только секреты, созданные страницей для этого сервера (имена `codelab/mcp/<сервер>/<ключ>`), на которые ссылался удалённый элемент через `${secret:…}`, и только если на них не осталось ссылок в конфиге; прочие имена из ссылок SHALL оставаться, а страница SHALL показывать их как `kept` с именем (решение Q22 design.md; правило удаления провайдера, SETUP-24); баннер итога SHALL называть каждый оставшийся или не удалённый секрет (`kept`, «ещё используется», «не удалось удалить» с командой `codelab secret delete <имя>`; design.md, D11); сервер слоя 3 удалить нельзя. Раскрытая строка `disabled here` SHALL показывать пояснение `<name> is disabled in .codelab/config.local.yaml. "Enable here" removes this override.`

После `ConfigSaved` страница SHALL проверять новый конфиг загрузкой с окружением агента (design.md, D11) и при ошибках показывать InfoBar `error` (ключ `mcp-rejected`): `Saved, but the agent rejected the new config`, `Config: invalid`, проблемы с путём ключа, `The agent keeps running on the previous config until this is fixed.` и кнопку `Edit <server>`. Если такие проблемы есть при открытии или перечитывании страницы без своей записи, InfoBar `mcp-rejected` SHALL показываться с заголовком `The agent rejects the current config` и тем же остальным содержимым, а запись SHALL оставаться доступной (решение Q26 design.md). Предупреждения `ConfigSaved.warnings` SHALL показываться баннером `saved`. Если подключённый агент применит записанный или включённый сервер только после перезапуска (правило перезагрузки конфига ядра: новый `stdio`-сервер, включение `enabled: false → true`, `http`-сервер с подстановкой `${…}`), баннер `saved` SHALL говорить об этом: после записи — `Server <name> saved. It starts after Restart agent (Settings › Connection).`, после включения переключателем или «Enable here» — `Server <name> enabled. It starts after Restart agent (Settings › Connection).`; «Save» в редакторе, который агент применит сразу или без подключённого агента, — `Server <name> saved.`; переключатель `enabled` в остальных случаях баннера НЕ SHALL показывать (решение пользователя 2026-11-08, design.md Q31).

#### Scenario: Сервер с секретным заголовком
- **WHEN** при `secrets.backend: file` пользователь добавляет `http`-сервер `github` с заголовком `Authorization` = `Bearer sk-test-leak-0123456789`, помеченным «Secret»
- **THEN** `config.yaml` содержит `Authorization: "${secret:codelab/mcp/github/authorization}"` и не содержит маркера, секрет сохранён, журнал содержит `mcp_settings.saved` без маркера

#### Scenario: Отклонённый агентом конфиг
- **WHEN** пользователь сохраняет stdio-сервер `postgres` с `env` `DATABASE_URL=${PG_URL}`, а `PG_URL` не задана в окружении встроенного агента
- **THEN** файл записан, показан InfoBar `mcp-rejected` с `Config: invalid` и путём `mcp.servers[postgres].env.DATABASE_URL` (формат пути ключа загрузчика; design.md, D24), промпт в сессию не отправлялся

#### Scenario: Открытие страницы с отклонённым конфигом
- **WHEN** в `config.yaml` есть stdio-сервер `postgres` с `env` `DATABASE_URL=${PG_URL}`, `PG_URL` не задана в окружении агента, и пользователь открывает «MCP servers»
- **THEN** страница показывает список серверов и InfoBar `mcp-rejected` с заголовком `The agent rejects the current config`, путём `mcp.servers[postgres].env.DATABASE_URL` и кнопкой `Edit postgres`; «Save» и «Add server» доступны, `mcp-unreadable` не показан

#### Scenario: Битый YAML блокирует запись
- **WHEN** пользовательский `config.yaml` не разбирается
- **THEN** страница показывает `mcp-unreadable` с проблемой загрузчика, кнопок записи нет

#### Scenario: Скрытый токен в аргументах при правке
- **WHEN** у stdio-сервера `docs` в `args` есть `--token sk-test-leak-0123456789`, и пользователь раскрывает строку и меняет только команду
- **THEN** поле аргументов показывает маску вместо токена, маркера нет ни на экране, ни в журнале; после «Save» в файле прежний `--token sk-test-leak-0123456789` и новая команда

#### Scenario: Секрет после снятия «Secret»
- **WHEN** у сервера `github` заголовок `Authorization` ссылается на `${secret:codelab/mcp/github/authorization}`, и пользователь удаляет эту строку и сохраняет
- **THEN** после записи конфига секрет `codelab/mcp/github/authorization` удалён, баннер `saved`; при отказе записи секрет на месте

#### Scenario: Подтверждение удаления
- **WHEN** пользователь нажимает «Remove» у сервера `github` с заголовком `${secret:codelab/mcp/github/authorization}` и затем «Cancel» в подтверждении
- **THEN** подтверждение называло `Remove github?` и `codelab/mcp/github/authorization`, файл и хранилище не изменены

#### Scenario: Новый сервер и отмена
- **WHEN** пользователь нажимает «Add server», вводит имя и нажимает «Cancel»
- **THEN** карточка `New server` исчезает, файл не изменён

#### Scenario: Новый stdio-сервер ждёт перезапуска
- **WHEN** встроенный агент подключён, и пользователь добавляет stdio-сервер `docs`
- **THEN** баннер `saved` — `Server docs saved. It starts after Restart agent (Settings › Connection).`; без подключения — `Server docs saved.`

#### Scenario: Сервер проектного слоя
- **WHEN** сервер `playwright` задан в `<project>/.codelab/config.yaml`, и пользователь нажимает «Disable here»
- **THEN** `<project>/.codelab/config.local.yaml` содержит `playwright` с `enabled: false`, проектный файл не изменён, «Remove» у строки нет, строка показывает `disabled here` и «Enable here»

#### Scenario: Enable here
- **WHEN** у сервера `playwright` проектного слоя есть переопределение `enabled: false` в `config.local.yaml`, и пользователь нажимает «Enable here»
- **THEN** элемент `playwright` удалён из `config.local.yaml`, проектный файл не изменён, сервер снова в эффективном конфиге с командой проектного файла; при подключённом агенте, который откладывает такой stdio-сервер до перезапуска, баннер — `Server playwright enabled. It starts after Restart agent (Settings › Connection).`, иначе баннера нет

#### Scenario: Удаление с секретами
- **WHEN** пользователь удаляет `github`, у которого заголовок ссылается на `${secret:codelab/mcp/github/authorization}`, а у сервера `GitHub` в том же файле есть секрет `codelab/mcp/github/token`
- **THEN** элемент `github` удалён из `mcp.servers`, после записи удалён только `codelab/mcp/github/authorization`; секрет `codelab/mcp/github/token` на месте; при отказе записи оба секрета на месте; секрет, на который ссылается другой сервер, не удаляется

#### Scenario: Ручной секрет остаётся
- **WHEN** пользователь удаляет сервер `docs`, у которого `env` ссылается на `${secret:team/docs-token}`, записанный `codelab secret set`
- **THEN** элемент удалён, секрет `team/docs-token` на месте, страница показывает `kept` и имя `team/docs-token`

#### Scenario: Вопрос о замене секрета называет имя
- **WHEN** при сохранении сервера `GitHub` с секретным заголовком `Authorization` в хранилище уже есть `codelab/mcp/github/authorization` (секрет сервера `github`)
- **THEN** вопрос «Replace it» называет имя `codelab/mcp/github/authorization`, без выбора секрет не перезаписывается

### Requirement: Панель «Agent status» страницы MCP servers
Панель «Agent status» (ключ `mcp-status`) SHALL показывать состояние серверов агента активной сессии (design.md, D12):
- для встроенного агента — при открытой сессии, независимо от объявления команды `/mcp` (решение Q24 design.md), — таблицу `SERVER · STATE · TOOLS · LAST ERROR` из потока состояний встроенного агента (spec embedded-agent «Состояние MCP-серверов для хоста») с подписью `Live from the embedded agent · <hh:mm>`; «Reconnect» строки SHALL вызывать переподключение сервера, «Reload all» — переподключение всех. Подписка SHALL быть одна; смена активной сессии, переподключение и закрытие страницы SHALL её отменять;
- для агента вне процесса — текст ответа `/mcp list` моноширинным блоком без разбора (SETUP-11); если ответ целиком — ровно один огороженный блок markdown (первая строка — ` ``` ` с необязательным языком, последняя — ` ``` `), внешнее ограждение SHALL сниматься, иначе текст показывается как есть (решение пользователя 2026-11-08, design.md Q34). Команды `/mcp list`, `/mcp reload <name>`, `/mcp reload` SHALL отправляться обычным промптом активной сессии только по явной кнопке пользователя («Refresh», «Reconnect», «Reload all») и только когда соединение `Connected` и у сессии нет идущего хода; иначе кнопки неактивны. Ответ, пришедший после смены активной сессии или закрытия страницы, НЕ SHALL менять панель. Панель SHALL показывать ответ последней команды страницы как есть: «Refresh» — ответ `/mcp list`, «Reconnect» — ответ `/mcp reload <name>`, «Reload all» — ответ `/mcp reload`; после `/mcp reload` страница НЕ SHALL сама отправлять `/mcp list` (решение Q29 design.md). Если ход команды не завершился ответом, панель SHALL показывать `/mcp list did not complete. Try Refresh again.` и сохранять прежний текст. Без объявленной агентом команды `/mcp` панель SHALL быть недоступной (ниже); при объявленной команде, но без `Connected`, во время хода или при непустой очереди панель SHALL оставаться текстовой с неактивными кнопками;
- без открытой сессии или если агент вне процесса не объявил `/mcp` — `Open a session to see live status`;
- подвал панели — `From the embedded agent. For a stdio or remote agent this panel shows the reply of /mcp list as text.` (решение Q23 design.md).

Страница НЕ SHALL отправлять команды агенту без действия пользователя.

#### Scenario: Живая таблица встроенного агента
- **WHEN** встроенный агент со сценарным MCP-сервером `github` открыл сессию, и пользователь открывает «MCP servers»
- **THEN** таблица показывает `github`, `connected` и число инструментов; «Reconnect» проводит строку через `connecting` в `connected` без промпта в сессию

#### Scenario: Текст /mcp list для stdio-агента
- **WHEN** окно подключено к локальному `codelab-agent serve --stdio`, сессия свободна, и пользователь нажимает «Refresh»
- **THEN** сессия получает промпт `/mcp list`, панель показывает текст ответа как есть

#### Scenario: Встроенный агент без команды /mcp
- **WHEN** встроенный агент открыл сессию, но не объявил команду `mcp` в `available_commands_update`
- **THEN** панель показывает таблицу из порта состояния MCP сессии (пустую, если серверов нет), а не `Open a session to see live status`

#### Scenario: Ответ /mcp reload в панели
- **WHEN** окно подключено к локальному `codelab-agent serve --stdio`, панель показывает текст прежнего `/mcp list`, сессия свободна, и пользователь нажимает «Reconnect» у `github`
- **THEN** сессия получает ровно один промпт `/mcp reload github`, панель показывает текст его ответа как есть, промпт `/mcp list` после него не отправляется

#### Scenario: Ответ /mcp list без внешнего ограждения
- **WHEN** агент вне процесса отвечает на `/mcp list` текстом ` ```text ` / `MCP servers (1)` / `github connected 3` / ` ``` `
- **THEN** панель показывает `MCP servers (1)` и `github connected 3` без строк ограждения; ответ `/mcp reload`, не огороженный целиком, показывается как есть

#### Scenario: Сбой /mcp list
- **WHEN** панель stdio-агента уже показывает текст прежнего ответа, пользователь нажимает «Refresh», и ход завершается ошибкой
- **THEN** панель показывает `/mcp list did not complete. Try Refresh again.` и прежний текст, текста исключения на экране нет

#### Scenario: Нет запросов во время хода
- **WHEN** у активной сессии stdio-агента идёт ход
- **THEN** «Refresh», «Reconnect» и «Reload all» неактивны, промпт `/mcp …` не отправляется

### Requirement: События журнала Providers и MCP servers без секретов
Страницы «Providers», «MCP servers» и мастер провайдера SHALL писать в журнал приложения структурные события design.md D18 (`provider_settings.*`, `provider_wizard.*`, `mcp_settings.*`) с id провайдера или имени сервера и номером операции `operation_id` для проверок. События и тексты на экране НЕ SHALL содержать значений ключей и секретов, имён переменных `api_key_env`, пути и query `base_url` и URL MCP-серверов (только `scheme://host:port`), значений `headers` и `env`, текстов ответов `/models` и `/mcp list`, текстов `toString()` исключений (только имя типа).

#### Scenario: Маркер не утекает из мастера
- **WHEN** пользователь вводит ключ `sk-test-leak-0123456789`, адрес `https://llm.example/v1?k=sk-test-leak-0123456789`, а запись конфига завершается исключением, чей `toString()` содержит маркер
- **THEN** журнал содержит `provider_wizard.save_failed` с именем типа исключения и `endpoint: https://llm.example:443`, а ни журнал, ни экран не содержат маркера и `k=`

