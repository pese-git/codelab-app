# app-settings Specification

## Purpose
Экран настроек codelab-app (`apps/codelab_desktop`) по reference Claude Design (`docs/design/claude-design/`): переход из рабочего места и обратно через `NavigationCubit` без потери сессии, навигация по страницам с поиском, недоступность рабочего места с клавиатуры и заметное ожидающее одобрение. Страница «Connection» управляет профилями из общего с CLI `$CODELAB_HOME/profiles.json`: встроенный агент, профиль по умолчанию, «Use» (выбор профиля окна для следующего старта; агент стартует сам по триггерам рабочего места), «Add connection profile» с проверкой только `initialize`, «Rename» и «Remove», «Restart agent» (единственный перезапуск, во время хода — с подтверждением). Токен профиля — только ссылка `env:<NAME>`; значения секретов, URL с путём и тексты исключений не попадают в UI и журнал. Страница «Agents & modes» задаёт режим разрешений и уровень рассуждения новой сессии и показывает определения агентов только для чтения (архив change `2026-11-18-add-settings-agents-modes`). Устройство — `docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` §12.4.9; история решений — архивы changes `2026-11-05-add-app-settings-shell` и `2026-11-12-require-project-folder`.
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
- App: General, Appearance, Keyboard, Legal.

Страница без содержимого в текущей сборке SHALL быть скрыта, а не пуста (SETUP-17); группа без видимых страниц НЕ SHALL показывать заголовок. Набор видимых страниц SHALL задавать composition root. Пункт навигации SHALL иметь ключ теста `settings-nav-<page>` (kebab-case: `settings-nav-connection`, `settings-nav-mcp-servers`, `settings-nav-legal`).

Заголовки групп и страниц SHALL показываться на языке интерфейса (требование «Локализация интерфейса app»); ключ теста и значение `codelab.settings.last_page` от языка НЕ SHALL зависеть.

Поиск SHALL отбирать страницы по совпадению подстроки без учёта регистра с заголовком страницы на языке интерфейса, с её английским заголовком, с её ключевыми словами на языке интерфейса или с её английскими ключевыми словами. Ключевые слова SHALL браться из каталогов ARB `en` и `ru` (сообщение на страницу, слова через запятую); ключевые слова другого языка, кроме английского, страницу НЕ SHALL находить. При пустом результате SHALL показываться строка `No settings match "<query>"` на языке интерфейса.

При ширине окна меньше 760 px навигация SHALL располагаться сверху, при 760 px и шире — панелью слева.

#### Scenario: Только существующие страницы
- **WHEN** сборка содержит только страницу «Connection»
- **THEN** навигация показывает группу «Agent» с единственным пунктом `settings-nav-connection`, заголовка «App» и пунктов других страниц нет

#### Scenario: Порядок не зависит от регистрации
- **WHEN** тестовая сборка регистрирует страницы `keyboard`, `connection`, `general` в этом порядке
- **THEN** навигация показывает Connection в группе «Agent», затем General и Keyboard в группе «App»

#### Scenario: Legal — последний пункт группы «App»
- **WHEN** тестовая сборка регистрирует страницы `legal`, `general`, `keyboard`, `appearance` в этом порядке
- **THEN** группа «App» показывает General, Appearance, Keyboard и `settings-nav-legal` последним

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `token` в «Find a setting»
- **THEN** в навигации остаётся «Connection», а выбор результата открывает эту страницу

#### Scenario: Поиск по английскому заголовку при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит `providers` в поле поиска настроек
- **THEN** в навигации остаётся страница «Providers» с переведённым заголовком

#### Scenario: Поиск по переведённому заголовку
- **WHEN** app работает на русском, и пользователь вводит часть переведённого заголовка страницы «General» из `app_ru.arb`
- **THEN** в навигации остаётся страница `settings-nav-general`

#### Scenario: Русское ключевое слово при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит `токен` в поле поиска настроек
- **THEN** в навигации остаётся страница `settings-nav-connection`

#### Scenario: Английское ключевое слово при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит `token` в поле поиска настроек
- **THEN** в навигации остаётся страница `settings-nav-connection`

#### Scenario: Русское ключевое слово при английском интерфейсе
- **WHEN** app работает на английском, и пользователь вводит `токен` в поле поиска настроек
- **THEN** ни одной страницы не найдено, показана строка `No settings match "токен"`

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
Composition root SHALL делать видимыми страницы «Connection», «Providers», «MCP servers», «Agents & modes» и «Skills & extensions» группы «Agent» в порядке требования «Навигация настроек»; остальные страницы остаются скрытыми (SETUP-17). Тела страниц SHALL иметь ключи `settings-providers`, `settings-mcp`, `settings-agents-modes` и `settings-skills`. Поиск «Find a setting» SHALL находить «Providers» по ключевым словам `provider`, `model`, `api key`, `key storage`, `base url`, «MCP servers» — по `mcp`, `server`, `tools`, `headers`, «Agents & modes» — по `mode`, `permission`, `bypass`, `plan`, `effort`, `reasoning`, `agent`, `definition`, `subagent` (design.md change `add-settings-agents-modes`, D9, D20), а «Skills & extensions» — по `skill`, `agents.md`, `context`, `template`, `prompt`, `extension` (design.md change `add-app-skills-page`, D13).

#### Scenario: Пять страниц группы Agent
- **WHEN** пользователь открывает настройки
- **THEN** навигация показывает в группе «Agent» пункты `settings-nav-connection`, `settings-nav-providers`, `settings-nav-mcp-servers`, `settings-nav-agents-and-modes`, `settings-nav-skills-and-extensions` в этом порядке, заголовка «App» нет

#### Scenario: Поиск ключа API
- **WHEN** пользователь вводит `api key` в «Find a setting»
- **THEN** в навигации остаётся «Providers»

#### Scenario: Поиск режима bypass
- **WHEN** пользователь вводит `bypass` в «Find a setting»
- **THEN** в навигации остаётся «Agents & modes», а выбор результата открывает тело `settings-agents-modes`

#### Scenario: Поиск AGENTS.md
- **WHEN** пользователь вводит `agents.md` в «Find a setting»
- **THEN** в навигации остаётся «Skills & extensions»

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

### Requirement: Непривязанный MCP-сервер на странице MCP servers
Сервер проектного слоя, заблокированный правилом привязки (capability `agent-secrets`, «Ссылки MCP-сервера проектного слоя привязаны к адресу»; design.md change `bind-mcp-secrets-to-origin`, D4, D5), SHALL показываться на странице «MCP servers» существующими средствами, без новых элементов:
- панель «Agent status» встроенного агента SHALL показывать строку сервера с состоянием `failed` и в `LAST ERROR` — текст причины агента как есть (`key bound to another address: move the server to config.local.yaml or the user config (<reference>)`);
- строка списка серверов SHALL оставаться прежней (источник `this project` или `defined in <file>`); InfoBar `mcp-rejected` НЕ SHALL показываться: непривязанная ссылка — предупреждение загрузки, а не проблема;
- сервер, записанный страницей с целью «This project only» (`config.local.yaml` доверенного проекта) или «Save to User config», SHALL подключаться без блокировки, если остальные условия подключения выполнены.

Ни экран, ни журнал приложения (`mcp_settings.*`) НЕ SHALL содержать значение секрета или переменной непривязанной ссылки.

#### Scenario: Заблокированный сервер в панели Agent status
- **WHEN** встроенный агент открыл сессию в доверенном проекте, чей `config.yaml` задаёт HTTP-сервер `relay` с `headers.Authorization: "Bearer ${secret:codelab/mcp/github/authorization}"` и чужим адресом, секрет хранит значение `sk-test-leak-0123456789`, и пользователь открывает «MCP servers»
- **THEN** таблица «Agent status» показывает `relay` в состоянии `failed` и в `LAST ERROR` — `key bound to another address: move the server to config.local.yaml or the user config (secret codelab/mcp/github/authorization)`; `mcp-rejected` не показан; маркера нет ни на экране, ни в журнале приложения

#### Scenario: Сервер «This project only» не блокируется
- **WHEN** пользователь добавляет на странице HTTP-сервер `team` с секретным заголовком `Authorization` и целью «This project only» в доверенном проекте, затем открывает новую сессию этого проекта
- **THEN** `config.local.yaml` содержит `team` со ссылкой `${secret:codelab/mcp/team/authorization}`, баннер `saved` без предупреждения о привязке, «Agent status» показывает `team` не в состоянии `failed` с причиной блокировки

### Requirement: Страница «Agents & modes» только для чтения
Страница «Agents & modes» SHALL вычислять доступ так же, как «Providers» и «MCP servers»: `resolveSettingsAccess` для профиля текущего подключения, без подключения — для профиля по умолчанию; папка — папка сессии в фокусе, иначе выбранный проект, иначе без папки (требование «Доступ к настройкам агента на страницах Providers и MCP servers»). Смена подключения или папки SHALL перечитывать доступ и снимок, в том числе смена папки сессии в фокусе при открытых настройках без смены профиля (design.md, D11).

Для `RemoteReadOnly` и `NotManaged` страница НЕ SHALL читать локальный конфиг и файлы определений, НЕ SHALL показывать блоков режима, effort и таблицы определений и SHALL показывать InfoBar уровня `warning` `agents-modes-read-only`: `Read-only: this agent runs on <scheme://host:port>. Change its modes and agents on that host: codelab config set, .codelab/agents.` или `Agent settings are managed by <agentName>.` (решение пользователя 2026-11-16, Q5 (а)).

Если `config.yaml` не разбирается или нарушает схему (в том числе `permissions.mode: autopilot` в файле), страница SHALL показывать проблемы загрузчика с путём ключа (`agents-modes-unreadable`) и НЕ SHALL предлагать запись.

#### Scenario: WebSocket-агент
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp`, а в локальном `$CODELAB_HOME/agents/` есть `reviewer.md`
- **THEN** страница показывает InfoBar `agents-modes-read-only` с `wss://devbox:7420` без `/acp`, радиогруппы режима, effort и таблицы `agents-definitions-table` нет; локальный конфиг и `reviewer.md` не читались

#### Scenario: autopilot в файле
- **WHEN** `$CODELAB_HOME/config.yaml` содержит `permissions.mode: autopilot`, а профиль окна — встроенный агент
- **THEN** страница показывает `agents-modes-unreadable` с путём `permissions.mode` и не предлагает записи; файл не изменён

### Requirement: Режим разрешений новой сессии на странице «Agents & modes»
Блок «Default permission mode» SHALL показывать радиогруппу `plan`, `ask`, `standard`, `accept-edits`, `bypass` с выбранным итоговым режимом снимка и его источником (`agents-modes-mode-source`: `default`, `user`, `project`, `local` и т. п.) и неактивную строку `autopilot` с текстом `Only as a launch flag of the agent (codelab-agent serve --permission-mode autopilot); never saved in config.` Значение `autopilot` НЕ SHALL записываться никогда.

Выбор режима, кроме `bypass`, SHALL записывать `SetValue('permissions.mode', <id>)` одним `AgentConfigStore.apply` в цель переключателя `agents-modes-target` (требование «Цель записи на странице «Agents & modes»»). Выбор `bypass` SHALL сначала открывать `ContentDialog` `agents-modes-bypass-confirm` с заголовком `Use bypass for new sessions?` и текстом `Only critical commands, changes to the agent's configuration and network tools still ask. Commands run without asking and can reach the network too. Use bypass only in a disposable checkout.` (решение пользователя 2026-11-16, Q13 (а); design.md, D15); запись SHALL выполняться только после «Use bypass»; «Cancel» и Esc SHALL возвращать выбор к итоговому режиму без записи (решение пользователя 2026-11-16, Q4 (б)).

Подтверждение SHALL быть привязано к состоянию на момент открытия диалога: номеру загрузки и цели записи (design.md, D17). Если к «Use bypass» сменились загрузка, доступ, папка или цель, запись НЕ SHALL выполняться, а страница SHALL показывать баннер `agents-modes-banner` `Settings changed while the dialog was open; bypass was not saved.` и писать `agents_modes.save_failed` с `outcome: stale`. Если цели записи нет в снимке, запись любого режима и effort НЕ SHALL выполняться, страница SHALL показывать баннер `Cannot save: the target config file is not available.` и НЕ SHALL подменять цель на `user`.

После `ConfigSaved` с `permissions.mode` в `restartRequiredKeys` страница SHALL перечитывать снимок и строить баннер `agents-modes-banner` по действующему значению нового снимка (design.md, D16): если оно равно записанному — `Saved. New sessions use <mode> after Restart agent.`, когда агент профиля подключён, иначе `Saved. New sessions use <mode> when the agent starts.`; если оно перекрыто другим слоем или сужено недоверенным проектом — баннер уровня `warning` `Saved to <target>; <source> overrides it: new sessions use <effective>` с тем же хвостом про перезапуск. Баннер НЕ SHALL утверждать, что новые сессии получат записанное значение, если действующее от него отличается. Страница НЕ SHALL менять режим открытых сессий и НЕ SHALL отправлять агенту `session/set_mode` или `session/set_config_option` (решение пользователя 2026-11-16, Q2 (а)).

Если итог загрузки содержит предупреждение `config.project.untrusted_key` для `permissions.mode`, страница SHALL показывать InfoBar `agents-modes-mode-narrowed` уровня `warning` с итоговым режимом: `This project is not trusted, so its config can only make the mode stricter. New sessions here use <effective>.` Итог «`ask` с запретом `write` и `exec`» SHALL показываться как `ask (edits and commands blocked by plan)`.

Конфликт записи (`ConfigConflict`) SHALL давать баннер и перечитывание снимка без автоповтора (SETUP-6); пока запись идёт, повторные выборы SHALL игнорироваться.

#### Scenario: Выбор accept-edits
- **WHEN** встроенный агент подключён, `permissions.mode` нигде не задан, и пользователь выбирает `accept-edits`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `permissions.mode: accept-edits`, баннер `agents-modes-banner` содержит `after Restart agent`, источник режима — `user`; агенту не отправлено ни одного запроса

#### Scenario: Отказ от bypass
- **WHEN** пользователь выбирает `bypass` и нажимает «Cancel» в `agents-modes-bypass-confirm`
- **THEN** файл конфига не изменён, выбран прежний итоговый режим, журнал содержит `agents_modes.bypass_cancelled`

#### Scenario: Подтверждённый bypass
- **WHEN** пользователь выбирает `bypass` и нажимает «Use bypass»
- **THEN** цель записи содержит `permissions.mode: bypass`, журнал содержит `agents_modes.mode_changed` с `mode: bypass`

#### Scenario: Текст подтверждения bypass
- **WHEN** пользователь выбирает `bypass`
- **THEN** `agents-modes-bypass-confirm` содержит `Commands run without asking and can reach the network too.` и `Use bypass only in a disposable checkout.`, файл конфига ещё не изменён

#### Scenario: Смена доступа при открытом диалоге bypass
- **WHEN** диалог `agents-modes-bypass-confirm` открыт, подключение переходит на профиль `wss://devbox:7420/acp` (или папка сессии в фокусе меняется), и пользователь нажимает «Use bypass»
- **THEN** ни один файл конфига не изменён, диалог закрыт, журнал содержит `agents_modes.save_failed` с `outcome: stale`, `agents_modes.mode_changed` нет

#### Scenario: Смена цели при открытом диалоге bypass
- **WHEN** диалог открыт при цели «All projects», цель переключается на «This project only», и пользователь нажимает «Use bypass»
- **THEN** записи нет, баннер `agents-modes-banner` содержит `bypass was not saved`

#### Scenario: Нет целевого слоя
- **WHEN** цель записи «This project only», но слоя `projectLocal` этой папки нет в снимке, и пользователь выбирает `plan`
- **THEN** ни `<project>/.codelab/config.local.yaml`, ни `$CODELAB_HOME/config.yaml` не изменены, баннер содержит `Cannot save`, журнал содержит `agents_modes.save_failed` с `outcome: rejected`

#### Scenario: Перекрытое значение после записи
- **WHEN** выбран проект `/work/demo`, его `.codelab/config.local.yaml` задаёт `permissions.mode: plan`, цель — «All projects», агент подключён, и пользователь выбирает `accept-edits`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `permissions.mode: accept-edits`, баннер уровня `warning` содержит `Saved to All projects;`, `overrides it: new sessions use plan` и `after Restart agent`, но не содержит `New sessions use accept-edits`

#### Scenario: Суженное значение после записи
- **WHEN** папка проекта не в `trusted_projects`, её `config.local.yaml` задаёт `plan`, цель — «All projects», и пользователь выбирает `ask`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `permissions.mode: ask`, баннер уровня `warning` содержит `the untrusted project overrides it: new sessions use ask (edits and commands blocked by plan)`, InfoBar `agents-modes-mode-narrowed` показан

#### Scenario: Недоверенный проект не смягчает режим
- **WHEN** пользовательский слой задаёт `ask`, папка проекта не в `trusted_projects`, а `<project>/.codelab/config.local.yaml` задаёт `bypass`
- **THEN** выбран `ask`, показан `agents-modes-mode-narrowed` с `New sessions here use ask`

#### Scenario: Сочетание ask и plan
- **WHEN** пользовательский слой задаёт `ask`, а недоверенный проект — `plan`
- **THEN** итоговый режим показан как `ask (edits and commands blocked by plan)`

### Requirement: Уровень рассуждения новой сессии на странице «Agents & modes»
Блок «Default reasoning effort» SHALL показывать ComboBox `agents-modes-effort` со значениями `low`, `medium`, `high`, выбранным итоговым `agent.effort` и его источником. Выбор SHALL записывать `SetValue('agent.effort', <value>)` в цель переключателя `agents-modes-target`. После `ConfigSaved` страница SHALL перечитывать снимок; без `agent.effort` в `restartRequiredKeys` баннер SHALL быть `Saved. New sessions use <effort>.`, с ним — как у режима; если действующий effort отличается от записанного — баннер `warning` по правилу режима (design.md, D16). Подпись блока SHALL говорить, что значение отправляется опцией сессии, только если модель поддерживает рассуждение, а одну сессию меняет композер.

#### Scenario: Смена effort
- **WHEN** встроенный агент подключён и пользователь выбирает `high`
- **THEN** цель записи содержит `agent.effort: high`, баннер `Saved. New sessions use high.` без `Restart agent`

### Requirement: Цель записи на странице «Agents & modes»
Режим и effort SHALL записываться по правилу «Default model»: в слой, где ключ определён сейчас, если он редактируемый, иначе в `user` (решение пользователя 2026-11-16, Q3 (б)). Переключатель `agents-modes-target` SHALL предлагать «All projects» (`user`) и «This project only» (`projectLocal(<папка>)`); второй вариант SHALL быть только при известной папке и цели `projectLocal` у `EditableSettings`. Переключатель SHALL быть один на оба блока: выбранная цель SHALL применяться и к записи режима, и к записи effort (решение пользователя 2026-11-16, Q10 (а)). Начальное положение SHALL соответствовать редактируемому слою источника `permissions.mode`, иначе `user`. Слой `project` и файл `--config` НЕ SHALL записываться (SETUP-3).

#### Scenario: Без папки нет цели проекта
- **WHEN** проект не выбран и пользователь открывает «Agents & modes»
- **THEN** переключатель `agents-modes-target` не содержит «This project only», файлы `/.codelab/` не читаются

#### Scenario: Только этот проект
- **WHEN** выбран проект `/work/demo` и пользователь переключает цель на «This project only» и выбирает `plan`
- **THEN** `/work/demo/.codelab/config.local.yaml` содержит `permissions.mode: plan`, `$CODELAB_HOME/config.yaml` не изменён, `.codelab/config.yaml` не изменён

#### Scenario: Одна цель для режима и effort
- **WHEN** выбран проект `/work/demo`, цель переключена на «This project only», и пользователь выбирает effort `low`
- **THEN** `/work/demo/.codelab/config.local.yaml` содержит `agent.effort: low`, `$CODELAB_HOME/config.yaml` не изменён

### Requirement: Таблица определений агентов на странице «Agents & modes»
Блок «Agent definitions» SHALL показывать таблицу `agents-definitions-table` только для чтения со строками моста (spec client-agent-setup «Строки определений агентов в мосте») и колонками Name, Description, Source, Available in, Tools, Model, Status: строка `default`, встроенные типы субагентов `general`, `explore`, `review`, `plan`, затем определения из файлов (решение пользователя 2026-11-16, Q6 (б)). Статус SHALL быть тегом с текстом: `Available`, `Model not configured`, `Error · line N` или `Error`, `Not loaded: duplicate name`, `Shadowed by project`, `Overridden by <путь>`, `Subagents off`.

У строк отклонённых файлов (`Model not configured`, `Not loaded: duplicate name`, `Shadowed by project`, `Error…`) ячейки «Available in», «Tools» и «Model» SHALL быть `—`. «Model» SHALL быть `session model` у `default`, встроенных типов и рабочих определений без модели (design.md, D7, D19).

Ключ строки SHALL быть `agents-definitions-row-<name>` для первой строки имени в порядке таблицы и `agents-definitions-row-<name>#<n>` (`n` с 2) для следующих строк того же имени; разделитель `#` не встречается в именах принятых определений (`^[a-z][a-z0-9-]{0,47}$`; у строки отклонённого файла имя — имя файла и теоретически может содержать `#`, такой редкий конфликт ключей допустим), поэтому ключ следующей строки не совпадает с ключом другого имени; два виджета строк с одним ключом НЕ SHALL появляться (design.md, D9, D19).

Текст из файлов определений — имя отклонённого файла, описание, путь источника, инструменты, путь в `Overridden by …` — и тексты InfoBar с путями (`agents-definitions-error-<n>`, `agents-definitions-untrusted`, `agents-definitions-open-failed`) SHALL выводиться как недоверенный простой текст: управляющие, невидимые и bidi-символы показываются видимыми, без markdown и ссылок (design.md, D20.4; D12 change `add-app-skills-page`).

Для каждого файла с диагностикой уровня `error` — прочий `error`, `Model not configured` и `duplicate` (в ядре уровень `error`) — страница SHALL показывать InfoBar `agents-definitions-error-<n>` уровня `error` с путём (`~` вместо домашнего каталога), строкой и фиксированным сообщением кода и кнопкой «Open folder» (`agents-definitions-open-file-<n>`), которая открывает каталог, где лежит файл (требование «Открытие каталогов определений»); для `duplicate` текст SHALL быть `Not loaded: another definition has the same name.` Сообщение НЕ SHALL содержать имени неизвестного ключа, значений, фрагментов файла и путей других файлов. Файл с `shadowed` (уровень `info`) НЕ SHALL получать InfoBar (design.md, D7). Недоверенный проект SHALL давать InfoBar `agents-definitions-untrusted` уровня `info`; признак — явный `projectTrusted` результата моста при известной папке, а не наличие диагностики `untrusted_project` (design.md, D19); загрузка дольше 5 с — `agents-definitions-timeout`; непредвиденная ошибка чтения — InfoBar `agents-definitions-failed` уровня `error` `Agent definitions could not be read.` без имени типа и пути (имя типа — только в журнал, design.md, D7).

«Reload» (`agents-definitions-reload`) SHALL перечитывать снимок и определения; результат прежней загрузки, пришедший после нового «Reload», смены доступа или закрытия страницы, НЕ SHALL применяться. Подпись блока SHALL говорить, что определения читаются при создании сессии, а выбор для одной сессии — в меню агента композера.

#### Scenario: Битое определение
- **WHEN** `$CODELAB_HOME/agents/migrator.md` содержит в строке 4 `tools: read` (строка вместо списка), а `reviewer.md` валиден
- **THEN** таблица содержит строку `reviewer` со статусом `Available` и строку `migrator` со статусом `Error · line 4`; InfoBar `agents-definitions-error-0` содержит `~/.codelab/agents/migrator.md` и `Open folder`, но не содержит `read`

#### Scenario: Модель вне каталога
- **WHEN** `docs-writer.md` задаёт `model: openai/gpt-x`, а провайдера `openai` в конфиге нет
- **THEN** строка `docs-writer` имеет статус `Model not configured`, и для `docs-writer.md` показан InfoBar `agents-definitions-error-<n>` уровня `error` с путём и кнопкой «Open folder»

#### Scenario: Определения не прочитаны
- **WHEN** загрузчик определений завершается непредвиденным исключением
- **THEN** страница показывает InfoBar `agents-definitions-failed` с текстом `Agent definitions could not be read.` без имени типа исключения и пути, блоки режима и effort доступны, журнал содержит `agents_modes.definitions_failed` с `reason: error`

#### Scenario: Встроенные типы и выключенные субагенты
- **WHEN** конфиг задаёт `subagents.enabled: false`
- **THEN** строки `general`, `explore`, `review`, `plan` с `Available in` = `subagent` видны и имеют статус `Subagents off` (решение пользователя 2026-11-16, Q12 (а)), строка `default` — `Available`

#### Scenario: Повторяющиеся имена строк
- **WHEN** `$CODELAB_HOME/agents/review.md` валиден со `scope: both`, а доверенный проект и `$CODELAB_HOME/agents` оба содержат валидный `reviewer.md`
- **THEN** встроенная строка `review` имеет ключ `agents-definitions-row-review`, строка файла `review.md` — `agents-definitions-row-review#2`; строки `reviewer` имеют ключи `agents-definitions-row-reviewer` и `agents-definitions-row-reviewer#2` в порядке таблицы; дубликатов ключей нет

#### Scenario: Ячейки отклонённого файла
- **WHEN** `docs-writer.md` задаёт `model: openai/gpt-x` и `tools: [read]`, а провайдера `openai` в конфиге нет
- **THEN** у строки `docs-writer` ячейки «Available in», «Tools» и «Model» — `—`, а не `session model` и не `read`; у строки `default` «Model» — `session model`

#### Scenario: Дубликат имени и затенённый файл
- **WHEN** `$CODELAB_HOME/agents/a.md` и `$CODELAB_HOME/agents/b.md` оба задают `name: helper`, а пользовательский `reviewer.md` затенён проектным `reviewer.md` доверенного проекта
- **THEN** для `a.md` и `b.md` показаны InfoBar `agents-definitions-error-<n>` уровня `error` с текстом `Not loaded: another definition has the same name.` и кнопкой «Open folder», без пути другого файла; для пользовательского `reviewer.md` со статусом `Shadowed by project` InfoBar нет

#### Scenario: Доверие по признаку моста
- **WHEN** порт загрузки возвращает для известной папки `projectTrusted: false` без диагностики `untrusted_project` (например, при тайм-ауте чтения)
- **THEN** страница считает проект недоверенным: меню «Open folder» не содержит `This project (.codelab/agents)`

#### Scenario: Невидимые символы в описании определения
- **WHEN** `$CODELAB_HOME/agents/reviewer.md` валиден, а его `description` содержит символ U+202E и тег Unicode U+E0041
- **THEN** ячейка «Description» строки `reviewer` показывает эти символы в видимой экранированной форме, а не применяет их

#### Scenario: Поздний результат после Reload
- **WHEN** первая загрузка определений не завершилась, пользователь нажимает «Reload», и вторая завершается раньше первой
- **THEN** таблица показывает результат второй загрузки, а поздний результат первой отброшен (`agents_modes.load_discarded`)

### Requirement: Открытие каталогов определений
«Open folder» в шапке блока и кнопка «Open folder» InfoBar ошибки определения SHALL открывать каталог в файловом менеджере ОС через порт платформы app `LocalFolderOpener` (`apps/codelab_desktop/lib/core/platform/`), общий со страницей «Skills & extensions», а не через `ExternalLinkOpener` (design.md, D8, D21). Файлы НЕ SHALL открываться и запускаться: кнопка InfoBar ошибки SHALL открывать каталог, где лежит файл определения (решение пользователя 2026-11-16, Q14 (б)).

Порт SHALL получать только каталоги `$CODELAB_HOME/agents` и `<project>/.codelab/agents` из текущего состояния страницы (последний — только при `projectTrusted` результата моста, design.md, D19); иной каталог SHALL отклоняться без вызова порта. Порт SHALL раскрывать символическую ссылку, отказывать (`failed`) без вызова платформы, если у имени раскрытого каталога есть расширение или суффикс `{…}` (каталог-пакет), давать `missing` для битой ссылки и не каталога и передавать платформе раскрытый путь (решение пользователя 2026-11-16, Q15 (а); D8 change `add-app-skills-page`). «Open folder» в шапке SHALL быть меню из пунктов `User definitions (<$CODELAB_HOME/agents с ~>)` и `This project (.codelab/agents)`. Сбой (`failed`), отсутствие (`missing`) и отказ страницы SHALL давать InfoBar `agents-definitions-open-failed` `Could not open <label>.` без причины.

Если по пути `$CODELAB_HOME/agents` нет никакой записи, «User definitions» SHALL создавать каталог (вместе с недостающими родителями) и открывать его; если по пути есть битая ссылка или файл, каталог НЕ SHALL создаваться. Если `<project>/.codelab/agents` нет, пункт «This project» SHALL быть неактивен с подсказкой `Create .codelab/agents in the project to add definitions.`, и app НЕ SHALL создавать каталоги в папке проекта (решение пользователя 2026-11-16, Q11 (а) + (б)).

#### Scenario: Каталог файла из InfoBar ошибки
- **WHEN** пользователь нажимает «Open folder» у InfoBar битого `$CODELAB_HOME/agents/migrator.md`
- **THEN** порт получает абсолютный путь каталога `$CODELAB_HOME/agents`, а не `migrator.md`; журнал содержит `agents_modes.open_path` с `kind: file_dir` и `outcome: opened` без пути

#### Scenario: Проект без доверия
- **WHEN** папка проекта не в `trusted_projects`
- **THEN** меню «Open folder» не содержит `This project (.codelab/agents)`

#### Scenario: Пользовательского каталога нет
- **WHEN** во временном `CODELAB_HOME` нет каталога `agents`, и пользователь выбирает «Open folder» → «User definitions»
- **THEN** каталог `$CODELAB_HOME/agents` создан и открыт, журнал содержит `agents_modes.open_path` с `kind: user_dir` и `outcome: created`

#### Scenario: Проектного каталога нет
- **WHEN** папка проекта доверенная, а `<project>/.codelab/agents` нет
- **THEN** пункт «This project (.codelab/agents)» неактивен с подсказкой `Create .codelab/agents in the project to add definitions.`, каталог в проекте не создан

#### Scenario: Каталог-ссылка
- **WHEN** `$CODELAB_HOME/agents` — символическая ссылка на каталог `/data/agents`, и пользователь выбирает «Open folder» → «User definitions»
- **THEN** платформа получает раскрытый путь `/data/agents`, каталог не создаётся, журнал содержит `agents_modes.open_path` с `outcome: opened`

#### Scenario: Ссылка на пакет приложения
- **WHEN** `<project>/.codelab/agents` доверенного проекта — символическая ссылка на `/Applications/Tool.app`, и пользователь выбирает «This project (.codelab/agents)»
- **THEN** порт возвращает `failed`, платформа не вызвана, страница показывает InfoBar `agents-definitions-open-failed`, журнал содержит `agents_modes.open_path` с `outcome: failed` без пути

#### Scenario: Битая ссылка вместо пользовательского каталога
- **WHEN** `$CODELAB_HOME/agents` — символическая ссылка на несуществующий путь, и пользователь выбирает «Open folder» → «User definitions»
- **THEN** ни каталог, ни цель ссылки не созданы, платформа не вызвана, страница показывает InfoBar `agents-definitions-open-failed`, журнал содержит `agents_modes.open_path` с `outcome: missing`

#### Scenario: Каталог вне состояния
- **WHEN** Cubit получает просьбу открыть каталог, которого нет среди каталогов определений текущего состояния
- **THEN** порт не вызван, журнал содержит `agents_modes.open_path` с `outcome: not_allowed` без пути

### Requirement: События журнала страницы «Agents & modes» без путей и значений
Страница SHALL писать события `agents_modes.{loaded,unreadable,load_discarded,definitions_failed,mode_changed,bypass_cancelled,effort_changed,save_failed,open_path}` в логгер `codelab_desktop.settings` с полями design.md change `add-settings-agents-modes`, D12. События НЕ SHALL содержать путей, имён файлов определений, описаний и тел определений, значений конфига, кроме `mode` и `effort`, и текстов исключений — только имя типа.

#### Scenario: Сбой записи без текста исключения
- **WHEN** запись режима завершается исключением, чей `toString()` содержит `/Users/demo/.codelab/config.yaml`
- **THEN** журнал содержит `agents_modes.save_failed` с `outcome: error` и именем типа, но не содержит `/Users/demo`

### Requirement: Язык интерфейса app
Страница «General» группы «App» SHALL быть видимой в рабочей сборке. Она SHALL содержать строку «Language» (ключ `settings-general-language`) с выбором из трёх значений в таком порядке:
- `System` (ключ `settings-language-system`) — по умолчанию;
- `English` (ключ `settings-language-en`);
- `Русский` (ключ `settings-language-ru`).

Названия `English` и `Русский` SHALL показываться на своём языке при любом языке интерфейса.

Выбор SHALL храниться в `shared_preferences` под ключом `codelab.app.language` со значениями `en` и `ru`. `System` SHALL удалять ключ. Файлы `$CODELAB_HOME` (`config.yaml`, `profiles.json`) выбор НЕ SHALL менять: это настройка app, а не агента и не CLI.

Язык интерфейса SHALL определяться так:
- `en` или `ru` в ключе — этот язык;
- ключа нет — язык системы: если первый язык в списке предпочтений системы — русский (`ru` с любым регионом), то `ru`, иначе `en`;
- незнакомое значение ключа SHALL читаться как `System`, без перезаписи ключа; в журнал пишется предупреждение без значения ключа;
- если хранилище не удалось прочитать при старте, язык SHALL определяться как при `System`, а app SHALL запускаться; в журнал пишется предупреждение без текста ошибки.

Первый кадр app SHALL показываться уже на определённом языке.

Выбор на странице SHALL применяться сразу, без перезапуска app. Сразу означает: до следующего кадра после выбора все уже показанные тексты app и `codelab_ui` SHALL быть пересобраны на новом языке — на рабочем месте, в доках, в открытых диалогах и на страницах настроек. Это относится и к уже показанным строкам ленты и заметкам, статусам, заголовкам, ошибкам и InfoBar. Смена языка НЕ SHALL терять ввод пользователя (текст композера, черновики диалогов), фокус и прокрутку ленты. Смена языка НЕ SHALL обращаться к агенту и НЕ SHALL менять состояние сессий, очереди и одобрений.

Источник текущего языка в app SHALL быть один. Компонент, который держит переведённый текст в своём состоянии, SHALL подписываться на смену языка один раз и отменять подписку при закрытии. Событие смены языка после закрытия компонента НЕ SHALL менять состояние.

Сразу НЕ SHALL меняться:
- меню macOS и системные панели (выбор файла и папки) — они следуют языку системы;
- язык при `System`, если язык системы изменился во время работы app, — новый язык системы применяется при следующем старте app или при повторном выборе `System`.

Если запись в `shared_preferences` не удалась, выбранный язык SHALL оставаться применённым до конца работы app, и страница SHALL показать ошибку `Couldn't save the language. CodeLab will use the previous language after restart.`. Текст исключения НЕ SHALL показываться. Рядом с ошибкой SHALL быть кнопка `Retry` (ключ `settings-language-save-retry`): она повторяет запись текущего выбора, не меняя язык. При нескольких выборах подряд SHALL применяться и сохраняться последний выбор.

Запись выбора SHALL давать событие `settings.language_changed` логгера `codelab_desktop.settings` с полями `language` (`system`, `en` или `ru`) и `locale`. Старт app SHALL давать событие `app.locale_resolved` с полями `preference` и `locale`.

#### Scenario: По умолчанию — язык системы
- **WHEN** ключа `codelab.app.language` нет, а первый язык системы — `ru-RU`
- **THEN** app стартует на русском, а «Language» показывает `System`

#### Scenario: Незнакомый язык системы
- **WHEN** ключа `codelab.app.language` нет, а первый язык системы — `de-DE`
- **THEN** app стартует на английском

#### Scenario: Явный выбор сильнее системы
- **WHEN** в ключе `codelab.app.language` записано `en`, а язык системы — `ru-RU`
- **THEN** app стартует на английском

#### Scenario: Смена языка применяется сразу на странице настроек
- **WHEN** app работает на английском, и пользователь выбирает `Русский` на странице «General»
- **THEN** в ключе записано `ru`, и без перезапуска заголовок страницы, навигация настроек и строка «Language» показываются на русском

#### Scenario: Живое рабочее место пересобирается
- **WHEN** на рабочем месте показаны ответ агента, вызов инструмента в статусе `running`, заметка хода `turnStopped`, сессии сайдбара в разных статусах и баннер потери соединения, и пользователь переключает язык на `Русский`
- **THEN** тег статуса вызова, заметка `turnStopped`, статусы сессий и баннер показываются на русском, ответ агента не изменился, и ни одна строка каталога `en` с отличающимся переводом не осталась на экране

#### Scenario: Уже показанные ошибки и InfoBar пересобираются
- **WHEN** страница «Providers» показывает сообщение об исходе удаления провайдера `openai`, и пользователь переключает язык на `Русский`
- **THEN** сообщение показывается на русском с тем же id провайдера
- **AND** InfoBar записи `default` на странице «Connection» (ключ `connection-profiles-ignored-default`), открытой после этого, тоже на русском, а команда `codelab profiles remove default` в нём не изменилась

#### Scenario: Ввод пользователя сохраняется
- **WHEN** в композере набран текст, лента прокручена вверх, и пользователь переключает язык
- **THEN** текст композера и положение прокрутки не изменились, а агенту ничего не отправлено

#### Scenario: Возврат к английскому
- **WHEN** app переключён на русский, и пользователь выбирает `English`
- **THEN** все тексты, которые пересобирались на русский, снова показываются на английском

#### Scenario: Закрытый компонент не реагирует на смену языка
- **WHEN** страница настроек закрыта, а затем язык переключён
- **THEN** её Cubit не публикует новое состояние, и подписок на смену языка у закрытых компонентов не осталось

#### Scenario: Незнакомое значение в хранилище
- **WHEN** в ключе `codelab.app.language` записано `fr`
- **THEN** язык определяется как при `System`, ключ не перезаписывается, а в журнале есть предупреждение без значения `fr`

#### Scenario: Сбой записи
- **WHEN** пользователь выбирает `Русский`, а запись в `shared_preferences` завершается ошибкой
- **THEN** интерфейс переключён на русский, «Language» показывает `Русский`, показана ошибка `Couldn't save the language. CodeLab will use the previous language after restart.` на русском и кнопка `Retry` на русском

#### Scenario: Повтор записи после сбоя
- **WHEN** после сбоя записи выбора `Русский` пользователь нажимает `Retry`, и запись проходит
- **THEN** в ключе `codelab.app.language` — `ru`, ошибка скрыта, интерфейс остаётся на русском

#### Scenario: Сбой чтения хранилища
- **WHEN** при старте app хранилище `shared_preferences` не удалось открыть или прочитать
- **THEN** app запускается, язык определяется как при `System`, а в журнале есть предупреждение без текста ошибки

#### Scenario: Два выбора подряд
- **WHEN** пользователь выбирает `Русский`, затем `English`, пока первая запись не завершилась
- **THEN** интерфейс на английском, а в ключе после завершения записей — `en`

#### Scenario: Меню macOS следует системе
- **WHEN** язык системы — английский, а пользователь выбрал `Русский`
- **THEN** окно app на русском, а меню macOS остаётся на английском

### Requirement: Локализация интерфейса app
App SHALL показывать интерфейс на английском (`en`) или русском (`ru`). Список языков app (`supportedLocales`) SHALL состоять только из `en` и `ru`.

Тексты интерфейса, приведённые в спецификациях, SHALL быть текстами языка `en`. При языке `ru` вместо них SHALL показываться переводы из каталогов app (`app_ru.arb`) и `codelab_ui` (`codelab_ui_ru.arb`). Ключи тестов (`ValueKey`), события журнала и их поля от языка НЕ SHALL зависеть.

Каталоги `en` и `ru` SHALL содержать одинаковый набор сообщений с одинаковыми плейсхолдерами. Количество в тексте SHALL склоняться по правилам языка (ICU `plural`; у `ru` — формы `one`, `few`, `many`, `other`).

Переводу НЕ SHALL подлежать, и при любом языке SHALL показываться как есть:
- содержимое от агента и модели: ответы, размышления, заголовки и вывод вызовов, тексты ошибок агента, имена и описания команд, режимов и опций, объявленных агентом;
- протокольные идентификаторы и значения провода (`stopReason`, `kind`, имена методов), ключи конфигурации, имена файлов, пути, URL, имена переменных окружения и секретов;
- команды CLI и slash-команды внутри текста (`codelab secret delete <name>`, `/usage`);
- названия продуктов и провайдеров (`CodeLab`, `MCP`, `ACP`, `OpenAI-compatible`, `Anthropic`, `Gemini`);
- обозначения клавиш (`⌘`, `Ctrl+K`);
- журналы, события журнала и содержимое панелей «Debug log» и «Inspector»;
- числа usage (токены, деньги, проценты) — формат общий с CLI и CSV (spec agent-workbench-ui «Строка статуса сессии под композером»).

Тексты от агента, пути и команды внутри переведённой фразы SHALL подставляться плейсхолдерами, а не склеиваться из частей фразы.

Ядро клиента (`codelab_client_core`) SHALL оставаться языконезависимым: app SHALL строить переведённый текст по типизированным данным ядра (кодам, видам, причинам), а НЕ SHALL переводить или разбирать английскую строку ядра. То же SHALL выполняться для моста настроек `codelab_setup`: ошибки и пояснения мастера провайдера, подписи пресетов и статуса ключа app SHALL строить по кодам, видам и id моста (spec client-agent-setup «Типизированные ошибки и пояснения мастера провайдера»). Так же app SHALL строить проблемы черновика MCP-сервера (по коду и аргументу, spec client-agent-setup «Типизированные проблемы черновика MCP-сервера»), подписи вида навыков (spec client-agent-setup «Типизированные подписи вида навыков»), статусы и области строк определений агентов, отказы записи списков навыков, состояния MCP-серверов и исходы очистки их секретов (по enum моста и встроенного агента). Сравнивать готовые строки ядра или моста, в том числе чтобы не показать одно сообщение дважды, app НЕ SHALL. Тексты, которые мост или ядро получают без типа от хранилища секретов или ядра агента, SHALL показываться как есть; тексты хранилища секретов SHALL показываться под переведённым заголовком, а не сами по себе. Это причина хранилища, подсказка бэкенда только для чтения, сообщения проверки конфига `ConfigIssue.message`, проблемы загрузчика, диагностики расширений агента `ExtensionDiagnostic.message`, фиксированный текст ошибки определения агента и причина отказа записи секрета MCP-сервера. Последняя ошибка MCP-сервера и ответ агента на `/mcp …` — содержимое от агента, они тоже показываются как есть.

Командная палитра (по `Ctrl/Cmd+K` и inline из композера) SHALL показывать подписи и описания команд app на языке интерфейса. Команду app палитра SHALL находить по подстроке её подписи или описания и на языке интерфейса, и на английском, как поиск настроек находит страницу по заголовку (требование «Навигация настроек»). Имя команды (`/new`, `/logs`) НЕ SHALL переводиться, и поиск по нему SHALL работать при любом языке. На английском набор и порядок результатов поиска SHALL совпадать с прежними, за одним исключением. У локального агента (встроенного или `stdio`) пункт `reconnect` показывается с подписью `Restart agent` и описанием `Restart the agent with the selected profile and reload open sessions.`. Палитра SHALL находить его по этим видимым подписи и описанию, а на русском — ещё по их английскому тексту. По имени `reconnect` пункт SHALL находиться как раньше. У удалённого агента пункт называется `Reconnect` и ищется по этой подписи. Команды агента SHALL показываться и находиться по имени и описанию от агента, без перевода и без английских дополнительных строк (spec acp-client-kit «Каталог команд палитры»).

Виджет `codelab_ui` без делегата `CodeLabLocalizations` в дереве SHALL показывать английские тексты кита.

#### Scenario: Тексты кита на русском
- **WHEN** app работает на русском, и в ленте есть вызов инструмента в статусе `running`
- **THEN** тег статуса вызова показывает перевод `Running` из `codelab_ui_ru.arb`, а заголовок вызова — строку агента без изменений

#### Scenario: Заметка исхода хода на русском
- **WHEN** app работает на русском, и ход завершился с `stopReason: max_tokens`
- **THEN** лента показывает перевод `The model reached its token limit, so the turn ended.` из `app_ru.arb`, построенный по `stopReason`, а не по тексту `NoticeItem.text`

#### Scenario: Запасная подпись решённого одобрения на русском
- **WHEN** app работает на русском, в ленте есть отменённый запрос разрешения, запрос, решённый без выбранного варианта, и запрос, решённый вариантом агента `Allow once`
- **THEN** у первых двух подпись исхода — переводы `Cancelled` и `Resolved` из `app_ru.arb`, построенные по исходу при пустой подписи агента (`agentLabel`); у третьего — `Allow once` без перевода

#### Scenario: Ответ агента не переводится
- **WHEN** app работает на русском, и агент отвечает текстом `Done. 3 files changed.`
- **THEN** лента показывает `Done. 3 files changed.` без изменений

#### Scenario: Склонение количества
- **WHEN** app работает на русском, и подтверждение перезапуска агента говорит о 2 и о 5 идущих ходах
- **THEN** тексты используют формы `few` и `many` из `app_ru.arb`

#### Scenario: Команда в переведённой фразе
- **WHEN** app работает на русском, и удаление провайдера `openai` не смогло удалить его собственный ключ из хранилища секретов
- **THEN** сообщение на русском содержит команду `codelab secret delete <имя секрета>` с именем этого ключа, как в английском тексте, без изменений

#### Scenario: Сообщения мастера провайдера на русском
- **WHEN** app работает на русском, в мастере провайдера пользователь отправляет пустой ключ, а в другом прогоне выбирает `Store in <backend> as "codelab/openai"` для провайдера `openai`, у которого в хранилище уже есть `codelab/openai`
- **THEN** ошибка шага — перевод `Enter the API key.` из `app_ru.arb`, построенный по коду ошибки моста; сообщение о существующем ключе показано один раз, на русском, с именем секрета в «ёлочках» — «codelab/openai»; в списке пресетов `Ollama (local, no key)` и `Custom OpenAI-compatible endpoint` переведены, а `OpenAI`, `Anthropic` и `OpenRouter` — как есть; план, записанный без проверки после `timeout`, показывает перевод предупреждения со словами «истекло время ожидания», а не значение `timeout`

#### Scenario: Текст хранилища секретов не переводится
- **WHEN** app работает на русском, и запись токена нового профиля отклонена хранилищем только для чтения: в одном прогоне с причиной хранилища `secret store keychain is read-only.`, в другом — без причины
- **THEN** в первом прогоне диалог показывает причину хранилища как есть под переведённым заголовком отказа из `app_ru.arb`, а не одну английскую строку; во втором — перевод `The secret store is read-only.` из `app_ru.arb`

#### Scenario: Подсказка хранилища в мастере провайдера
- **WHEN** app работает на русском, бэкенд секретов только для чтения и даёт английскую подсказку, и мастер провайдера на шаге ключа получает ошибку «хранилище секретов только для чтения»
- **THEN** шаг показывает одно предупреждение: переведённый заголовок из `app_ru.arb` и подсказку бэкенда как есть под ним; отдельной ошибки с тем же смыслом нет

#### Scenario: Встроенный агент во фразе
- **WHEN** app работает на русском, выбран профиль встроенного агента, и пользователь открывает подтверждение перезапуска агента
- **THEN** текст — отдельное сообщение для встроенного агента из `app_ru.arb` («Перезапустить встроенного агента? …»), а не общая фраза с подписью профиля, подставленной плейсхолдером

#### Scenario: Проблемы черновика MCP-сервера на русском
- **WHEN** app работает на русском, и пользователь сохраняет на странице «MCP servers» `http`-сервер с именем `a b`, URL `https://u:p@h/mcp` и двумя заголовками `Authorization`
- **THEN** форма показывает переводы `Use a name without spaces, [, ] or ".` и `Remove the user name and password from the URL.` из `app_ru.arb`, построенные по кодам проблем моста, и перевод `Two values are named Authorization.` с именем `Authorization` без изменений. Каждая проблема показана один раз, английского текста проблем на экране нет

#### Scenario: Таблица «Agent status» на русском
- **WHEN** app работает на русском, встроенный агент открыл сессию, сервер `github` в состоянии `failed` с повтором через 24 s и последней ошибкой `connection refused`, а сервер `docs` выключен
- **THEN** колонки таблицы — переводы `SERVER`, `STATE`, `TOOLS`, `LAST ERROR` из `app_ru.arb` без сокращений; состояние `github` — перевод `failed · retry in 24 s` с числом 24, последняя ошибка — `connection refused` как есть; у `docs` вместо числа инструментов и ошибки — прочерк; кнопки — переводы `Reconnect` и `Reload all` для сервера, отличные от перевода `Reconnect` подключения к агенту; время подписи `Live from the embedded agent` — в формате `HH:mm`, как на английском; при ширине 760 px переполнения нет

#### Scenario: Ответ /mcp на русском не переводится
- **WHEN** app работает на русском, окно подключено к агенту вне процесса, и агент ответил на `/mcp list` текстом `MCP servers (1)` / `github connected 3`
- **THEN** панель показывает этот текст как есть, а кнопки и подвал панели — на русском

#### Scenario: Отклонённый агентом конфиг на русском
- **WHEN** app работает на русском, и страница «MCP servers» показывает InfoBar `mcp-rejected` с проблемой `mcp.servers[postgres].env.DATABASE_URL`
- **THEN** заголовок, `Config: invalid`, фраза `The agent keeps running on the previous config until this is fixed.` и кнопка `Edit postgres` — переводы из `app_ru.arb` с именем `postgres` без изменений, а путь ключа и текст проблемы от ядра агента — как есть под переведённым заголовком

#### Scenario: Режим и баннер записи на русском
- **WHEN** app работает на русском, итоговый режим новой сессии — `ask` с запретом правок и команд от `plan`, и пользователь сохраняет уровень рассуждения `high`, который применится после перезапуска встроенного агента
- **THEN** подпись режима — `ask` без перевода с переведённой пометкой `(edits and commands blocked by plan)`; баннер записи — одно целое предложение из `app_ru.arb` с `high` без перевода, а не английская основа или английский хвост `after Restart agent.`; значения радиогруппы `plan`, `ask`, `standard`, `accept-edits`, `bypass`, `autopilot` — как есть

#### Scenario: Таблица определений агентов на русском
- **WHEN** app работает на русском, и в таблице определений агентов есть встроенный тип, доступный сессии и субагенту, файл с ошибкой в строке 4 и файл с повторяющимся именем
- **THEN** статусы — переводы `Available`, `Error · line 4` с числом 4 и `Not loaded: duplicate name` из `app_ru.arb`; колонка «Available in» — переводы `session` и `subagent`; текст ошибки определения от ядра показан как есть под переведённым заголовком; имена и описания определений — как есть

#### Scenario: Страница «Skills & extensions» на русском
- **WHEN** app работает на русском, навык проекта перекрывает навык пользователя, у другого навыка есть предупреждение ядра, файл контекста весит 4915 байт, и переключатель навыка неактивен, потому что ключ задан в проектном файле
- **THEN** подпись перекрытия — перевод по области пользователя; предупреждение ядра — как есть под переведённым заголовком; размер — `4.8 КБ`; подсказка переключателя — перевод `Set in <source>; edit that file.` с путём без изменений; имена и описания навыков и шаблонов — как есть

#### Scenario: Источник конфигурации на русском
- **WHEN** app работает на русском, режим новой сессии задан в `<project>/.codelab/config.local.yaml`, сервер `docs` задан в пользовательском конфиге, а на странице «General» значение строки переопределяет проектный файл
- **THEN** на «Agents & modes» источник режима — «локально», у строки `docs` на «MCP servers» — «пользователь», на «General» подпись переопределения называет источник «проект»; все подписи — из одной функции по `ConfigSourceKind`, а на английском — прежние `local`, `user` и `project`

#### Scenario: Страницы настроек II пересобираются при смене языка
- **WHEN** на странице «MCP servers» показан баннер записи с оставленным секретом, на «Agents & modes» — баннер записи с перекрытием слоем, на «Skills & extensions» — баннер отказа записи, и пользователь переключает язык на `Русский`, а затем обратно на `English`
- **THEN** после каждого переключения баннеры, InfoBar, статусы и подписи этих страниц показаны на новом языке, имена серверов, секретов и пути не изменились, и ни одна строка каталога старого языка с отличающимся переводом не осталась на экране

#### Scenario: Кит без делегата
- **WHEN** виджет-тест показывает `CodeLabToolCallTile` в `FluentApp` без `CodeLabLocalizations.delegate`
- **THEN** тег статуса показывает `Running`

#### Scenario: Каталоги согласованы
- **WHEN** в `app_en.arb` есть сообщение, которого нет в `app_ru.arb`, или плейсхолдеры сообщения различаются
- **THEN** тест согласованности каталогов падает и называет ключ сообщения

#### Scenario: Поиск команды хоста по английской подписи на русском
- **WHEN** app работает на русском, палитра открыта, и пользователь вводит `session`
- **THEN** палитра показывает команду `/new` с переведённой подписью из `app_ru.arb`, хотя ни её имя, ни перевод не содержат `session`

#### Scenario: Поиск команды хоста по переведённой подписи
- **WHEN** app работает на русском, и пользователь вводит в палитре часть перевода подписи `New session` из `app_ru.arb`
- **THEN** палитра показывает команду `/new`

#### Scenario: Поиск по имени команды при любом языке
- **WHEN** app работает на русском, и пользователь вводит `/logs` в композере
- **THEN** inline-палитра показывает команду `/logs` с переведённой подписью первой, как на английском

#### Scenario: Пункт перезапуска локального агента ищется по видимой подписи
- **WHEN** подключён локальный агент, палитра показывает пункт `reconnect` с подписью `Restart agent`, и пользователь вводит в палитре `restart`
- **THEN** палитра показывает этот пункт на английском и на русском; на русском — с переведённой подписью из `app_ru.arb`, а ввод `/reconnect` в композере по-прежнему находит его по имени

#### Scenario: Команда агента в палитре не переводится
- **WHEN** app работает на русском, агент объявил команду `review` с описанием `Review the plan`, и пользователь вводит в палитре `review the`
- **THEN** палитра показывает `/review` с описанием `Review the plan` без изменений

### Requirement: Страница «Appearance»: видимость и состав
Composition root SHALL делать видимой страницу «Appearance» группы «App» (`settings-nav-appearance`, тело `settings-appearance`) после «General» в порядке требования «Навигация настроек». Страница SHALL показывать блоки в порядке артборда «10 Settings — Appearance» (design.md change `add-app-appearance-page`, D14):
1. «Mode» (`settings-appearance-mode`);
2. «Accent color» (`settings-appearance-system-accent`) — только если платформа отдаёт системный акцент (требование «Системный акцент»);
3. «Color theme» — карточки тем (`settings-appearance-themes`);
4. «Custom themes» — путь каталога тем `<home>/themes/*.json` с `~` вместо домашнего каталога и кнопка «Import JSON…» (`settings-appearance-import`);
5. панель проблем выбранной темы (`settings-appearance-issues`) — только если у выбранной темы есть предупреждения, ошибка или незаданные роли;
6. «Preview» (`settings-appearance-preview`) с проверкой контраста и кнопками «Reset» (`settings-appearance-reset`) и «Use <name>» (`settings-appearance-use`).

При ширине области страницы от 960 px «Preview» SHALL стоять правой колонкой, при меньшей — под остальными блоками. Строка «Accent color» при ширине области меньше 560 px SHALL переносить переключатель под подпись и описание, а не обрезать их.

Поиск «Find a setting» SHALL находить «Appearance» по английским ключевым словам `theme`, `dark`, `light`, `mode`, `color`, `accent`, `contrast`, `json` при любом языке интерфейса, а при русском — ещё по `тема`, `тёмная`, `светлая`, `режим`, `цвет`, `акцент`, `контраст`, `оформление` (сообщение `settingsSearchKeywordsAppearance` в ARB `en` и `ru`).

Все тексты страницы SHALL браться из каталогов ARB `en` и `ru` (требование «Локализация интерфейса app»). Имена тем, ключи JSON, значения цветов, пути, текст файла темы и отношения контраста (`4.8:1`) SHALL показываться как есть. Названия встроенных тем `Fluent Light`, `Fluent Dark` SHALL не переводиться, `High contrast` SHALL переводиться.

#### Scenario: Страница видна
- **WHEN** пользователь открывает настройки рабочей сборки
- **THEN** в группе «App» после `settings-nav-general` стоит `settings-nav-appearance`, выбор открывает `settings-appearance`

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `contrast` в «Find a setting»
- **THEN** в навигации остаётся «Appearance»

#### Scenario: Узкая область
- **WHEN** ширина области страницы 800 px
- **THEN** блок «Preview» стоит под панелью проблем, а не правой колонкой

### Requirement: Режим оформления и темы режимов
«Mode» SHALL предлагать три значения в этом порядке: `Light` (`settings-appearance-mode-light`), `Dark` (`settings-appearance-mode-dark`), `Match system` (`settings-appearance-mode-system`). У `Match system` SHALL в скобках показываться текущий режим системы (`Match system (dark)`). По умолчанию — `Match system`.

App SHALL хранить две темы: тему светлого режима (по умолчанию `light`, «Fluent Light») и тему тёмного режима (по умолчанию `dark`, «Fluent Dark»). Действующая тема SHALL быть темой режима, который даёт «Mode»: `Light` — светлого, `Dark` — тёмного, `Match system` — режима системы в данный момент. Смена режима системы при `Match system` SHALL применяться сразу.

Каждая тема SHALL относиться к одному режиму: `light` — к светлому, `dark` и `high-contrast` — к тёмному, пользовательская — к режиму своей базы `extends` (`light` — светлый, иначе тёмный).

Встроенные темы SHALL задаваться так:
- `light` и `dark` — стандартная тема Fluent своего режима. В `light` тоны `success`, `warning`, `accent`, нейтральный тег, цвет ссылок и палитра кода SHALL совпадать с теми, что app показывал до этого change; тон `danger` SHALL иметь оттенок `Colors.red` (тон HSL ±3°) и SHALL быть затемнён до контраста не ниже 4,5:1 к фону страницы, карточки, кода и заливке тега. В `dark` тоны `success`, `warning`, `danger`, `accent` SHALL подгоняться по контрасту не ниже 4,5:1 к тем же четырём фонам, а нейтральный тег SHALL рисоваться вторичным текстом темы (design.md, D4);
- `high-contrast` — тёмная тема с чёрным фоном кода и палитрой из design.md, D6.

Пользовательская тема SHALL применяться поверх встроенной темы своей базы. Роли, которые тема задала, SHALL заменять роли базы (spec client-themes «Роли цветов темы»; применение ролей — design.md, D4). Тема, которая не загрузилась (ошибка разбора или чтения, файл удалён), SHALL заменяться встроенной темой своего режима (`light` или `dark`). Сохранённый выбор при этом НЕ SHALL меняться, а страница SHALL показывать InfoBar `settings-appearance-fallback`: `"<name>" couldn't be loaded. Using <built-in> until it is fixed.`.

Смена режима, темы или акцента SHALL применяться ко всему app до следующего кадра, без перезапуска. Она НЕ SHALL терять ввод пользователя (текст композера, черновики диалогов), фокус и прокрутку ленты и НЕ SHALL обращаться к агенту. Первый кадр app SHALL рисоваться уже в сохранённом оформлении.

#### Scenario: Тёмная система
- **WHEN** выбран `Match system`, обе темы по умолчанию, и система переходит в тёмный режим
- **THEN** app рисуется в «Fluent Dark», текст композера и прокрутка ленты сохранены

#### Scenario: Темы двух режимов
- **WHEN** тема светлого режима — `light`, тёмного — пользовательская `acme-night` (`extends: dark`), и пользователь переключает «Mode» с `Light` на `Dark`
- **THEN** app рисуется в `acme-night`; при возврате на `Light` — в «Fluent Light»

#### Scenario: Удалённый файл темы
- **WHEN** тема тёмного режима — `acme-night`, файл `acme-night.json` удалён, и app стартует в тёмном режиме
- **THEN** app рисуется в «Fluent Dark», `codelab.app.appearance` по-прежнему называет `acme-night`, а страница показывает `settings-appearance-fallback`

#### Scenario: Стандартная тема не меняет вид
- **WHEN** выбран `Light` с темой `light` и системный акцент выключен
- **THEN** тоны `success`, `warning`, `accent`, нейтральный тег и палитра кода совпадают с цветами до этого change, а тон `danger` отличается от `Colors.red` не больше чем на 3° оттенка и даёт не меньше 4,5:1 к фону страницы, карточки, кода и заливке тега (widget-тест сравнивает значения цветов)

#### Scenario: Тоны тёмной темы читаемы
- **WHEN** выбран `Dark` с темой `dark`
- **THEN** тоны `success`, `warning`, `danger`, `accent` дают не меньше 4,5:1 к фону страницы, карточки, кода и заливке тега, нейтральный тег нарисован `textFillColorSecondary` темы

#### Scenario: База пользовательской темы сменила режим
- **WHEN** тема тёмного режима — `acme-night`, пользователь поменял в файле `extends` на `light` и нажал «Reload» (или перезапустил app)
- **THEN** тёмный режим показывает «Fluent Dark», `codelab.app.appearance` по-прежнему называет `acme-night` в поле тёмного режима, страница показывает `settings-appearance-fallback`, в журнале `appearance.theme_invalid` с `code: wrongMode`

### Requirement: Системный акцент
Строка «Accent color» с переключателем «Use system accent» SHALL показываться, только если порт системного акцента сообщает поддержку: платформа поддерживается пакетом `system_theme` (macOS, Windows, Linux), и чтение акцента при старте app дало цвет (design.md, D7). Иначе строка SHALL быть скрыта (SETUP-17). Видимость строки НЕ SHALL меняться после первого кадра. По умолчанию переключатель выключен.

Включённый переключатель SHALL заменять роль `accent` действующей темы системным акцентом — у встроенных и у пользовательских тем. Это касается кнопок, выделения, фокуса и производных от акцента цветов. На macOS и Windows смена акцента в системе SHALL применяться сразу. На Linux платформа не сообщает о смене, поэтому акцент SHALL перечитываться при старте app и при каждом открытии страницы «Appearance». Если платформа перестала отдавать акцент (ошибка канала), SHALL применяться `accent` темы, а в журнал SHALL писаться предупреждение без текста ошибки.

#### Scenario: Системный акцент включён
- **WHEN** порт отдаёт акцент `#ff2d55`, и пользователь включает «Use system accent»
- **THEN** `FluentTheme.accentColor` действующей темы построен из `#ff2d55`, а превью и карточки показывают акцент своих тем

#### Scenario: Пользовательская тема и системный акцент
- **WHEN** действует `acme-night` с `"accent": "#b4a0ff"`, порт отдаёт `#ff2d55`, и переключатель включён
- **THEN** `FluentTheme.accentColor` построен из `#ff2d55`

#### Scenario: Linux без уведомлений
- **WHEN** app работает на Linux, переключатель включён, пользователь сменил тему GTK и открывает «Appearance»
- **THEN** порт перечитан один раз, и действующий акцент построен из нового цвета

#### Scenario: Плагин не отдал цвет
- **WHEN** платформа поддерживается пакетом, но чтение при старте вернуло запасной цвет-маркер или ошибку
- **THEN** строки `settings-appearance-system-accent` нет, запасной цвет пакета не применяется

#### Scenario: Платформа без системного акцента
- **WHEN** порт системного акцента сообщает, что поддержки нет
- **THEN** строки `settings-appearance-system-accent` на странице нет

### Requirement: Карточки тем и превью
«Color theme» SHALL показывать карточки: сначала встроенные `light`, `dark`, `high-contrast` (ключ `settings-appearance-theme-<id>`), затем пользовательские в порядке каталога тем (ключ `settings-appearance-theme-custom-<name>`). Встроенные и пользовательские темы SHALL различаться видом, а не только именем: файл каталога с именем встроенной темы (`dark.json`) SHALL быть карточкой пользовательской темы с ошибкой `reservedName`. Ниже в требованиях `<id>` в ключах карточки означает `<id>` встроенной темы или `custom-<name>` пользовательской. Карточка SHALL показывать мини-превью кода (`settings-appearance-theme-<id>-preview`) в цветах темы (фон кода, `text`, `code.keyword`, `code.string`, `code.comment`, `code.number`), имя темы и вид: `Built-in · default` у `light` и `dark`, `Built-in` у `high-contrast`, `Custom · extends <base>` у пользовательской. Карточка темы светлого режима SHALL нести тег `Light mode`, тёмного — `Dark mode`. Карточка с предупреждениями SHALL нести бейдж `settings-appearance-theme-<id>-warnings` с текстом `N warnings` (ICU `plural`). N — предупреждения разбора плюс роли с низким контрастом (требование «Контраст на фоне кода»). Тема, которая не загрузилась, SHALL нести тег `Invalid` вместо бейджа.

Нажатие карточки SHALL выбирать тему для превью и панели проблем и НЕ SHALL применять её. При открытии страницы выбрана действующая тема.

«Preview» SHALL рисовать в цветах выбранной темы:
- блок кода `dart` с подписью языка;
- строку удалённого и строку добавленного кода diff на фонах `diff_remove_bg` и `diff_add_bg`;
- статусы `Link` (`info`), `Done` (`success`), `84% context` (`warning`), `Failed` (`error`) — внутри той же карточки превью, на фоне кода темы, а не на фоне страницы: так статусы видны в цветах выбранной темы, а не текущей.

Тексты превью SHALL быть фиксированными данными app и НЕ SHALL браться из сессий.

«Use <name>» SHALL делать выбранную тему темой её режима. Если «Mode» стоит на другом режиме (`Light` или `Dark`), «Mode» SHALL переключаться на режим темы, чтобы выбор был виден сразу; при `Match system` «Mode» НЕ SHALL меняться. Кнопка SHALL быть недоступна для темы, которая не загрузилась, и для темы, которая уже назначена своему режиму.

«Reset» SHALL возвращать режиму выбранной темы встроенную тему по умолчанию (`light` или `dark`) и выбирать её для превью. Кнопка SHALL быть недоступна, если этому режиму уже назначена тема по умолчанию.

#### Scenario: Выбор карточки не применяет тему
- **WHEN** действующая тема — «Fluent Dark», и пользователь нажимает карточку `acme-night`
- **THEN** превью нарисовано цветами `acme-night`, app по-прежнему в «Fluent Dark», кнопка называется `Use acme-night`

#### Scenario: Пользовательский файл с именем встроенной темы
- **WHEN** в каталоге тем лежит `dark.json`
- **THEN** есть карточка `settings-appearance-theme-custom-dark` с тегом `Invalid` и проблемой `reservedName`, карточка `settings-appearance-theme-dark` («Fluent Dark») одна и работает

#### Scenario: Последний выбор побеждает
- **WHEN** пользователь нажимает «Use» у `acme-night`, файл читается медленно, и до конца чтения пользователь нажимает «Use» у «Fluent Dark»
- **THEN** тема тёмного режима — `dark`, позднее чтение `acme-night` ничего не меняет

#### Scenario: Use переключает фиксированный режим
- **WHEN** «Mode» — `Light`, и пользователь нажимает «Use» у выбранной `acme-night` (`extends: dark`)
- **THEN** тема тёмного режима — `acme-night`, «Mode» — `Dark`, app рисуется в `acme-night`

#### Scenario: Reset
- **WHEN** тема тёмного режима — `acme-night`, она выбрана, и пользователь нажимает «Reset»
- **THEN** тема тёмного режима — `dark`, выбрана карточка «Fluent Dark»

### Requirement: Пользовательские темы на странице «Appearance»
Страница SHALL читать каталог тем при открытии и по «Reload», только через порт каталога тем (spec client-themes «Каталог пользовательских тем»). Пока каталог читается, карточки встроенных тем SHALL работать, а на месте пользовательских SHALL стоять индикатор загрузки (`settings-appearance-themes-loading`). Если каталог не удалось прочитать целиком (порт бросил исключение), страница SHALL показывать встроенные темы и InfoBar уровня `warning` `settings-appearance-catalog-failed`: `Couldn't read <home>/themes. Custom themes are not shown.` без текста исключения и с кнопкой «Reload» (`settings-appearance-catalog-reload`), которая повторяет чтение. Результат чтения, начатого до закрытия страницы или до более нового «Reload», НЕ SHALL менять состояние страницы.

Если у выбранной темы есть предупреждения, панель проблем SHALL показывать:
- InfoBar уровня `warning` `settings-appearance-issues-summary`: `<name> loaded with N warnings` и пояснение по составу проблем: `Unknown keys were ignored; the theme is applied.`, если среди предупреждений есть неизвестные ключи, иначе `The theme is applied with warnings.`; если у темы есть незаданные роли, к нему добавляется `Missing roles come from extends: "<base>" (<built-in name>).`;
- кнопки «Open folder» (`settings-appearance-open-folder`) и «Reload» (`settings-appearance-reload`);
- текст файла с номерами строк (`settings-appearance-file`), где строки с предупреждением выделены (`CodeLabFilePreview`);
- список проблем `settings-appearance-issue-<n>` (n с 1, по порядку позиции; показываются первые 50, остальные — строкой `settings-appearance-issues-more` `… and {count} more warnings`, бейдж карточки считает все): `<file>:<line>:<col> unknown key "<key>"` с пояснением `Ignored. Did you mean "<role>"?` или `Ignored — not a theme role.`, `duplicate key "<key>"` — `The last value is used.`, `terminal color "<value>"` — `Terminal colors are not used by the app; the role comes from extends.`, а также строка о низком контрасте для каждой такой роли;
- справку `settings-appearance-unset-roles`: `N roles not set — taken from "<base>"` и список ролей с пояснением `For reference, not a warning`. Роли, которые app не применяет (`status_bg`, `approval_border`), в справку и в N НЕ SHALL входить.

Если тема не загрузилась, InfoBar SHALL быть уровня `error`: `<name> couldn't be loaded`. Под ним — та же проблема с позицией. Текст файла SHALL показываться, если файл прочитан и не больше 64 КиБ. Справки о ролях при этом нет.

Если у темы нет предупреждений и ошибок, но есть незаданные роли, SHALL показываться только справка.

Текст файла и значения из него SHALL проходить экранирование управляющих символов и символов направления текста (`escapeForDisplay`) перед показом. Текст файла SHALL экранироваться построчно: переводы строк сохраняются, и номер строки на экране совпадает с номером строки в позиции проблемы. Табуляция SHALL показываться четырьмя пробелами, остальные управляющие и невидимые символы — как `\uXXXX`.

«Open folder» SHALL открывать каталог тем через порт `LocalFolderOpener` (создавая его, если нет). Файл темы app НЕ SHALL открывать внешним приложением. «Reload» SHALL перечитывать каталог. Если выбранная тема назначена режиму, «Reload» SHALL заново применять её из файла.

#### Scenario: Пояснение без неизвестных ключей
- **WHEN** у выбранной темы только предупреждение о низком контрасте, и все роли заданы
- **THEN** пояснение InfoBar — `The theme is applied with warnings.`, без фраз о неизвестных ключах и `extends`

#### Scenario: Тема с двумя предупреждениями
- **WHEN** выбрана `acme-night` с ключами `acent` (строка 6) и `tab_bg` (строка 9)
- **THEN** InfoBar показывает `acme-night loaded with 2 warnings`, строки 6 и 9 текста выделены, `settings-appearance-issue-1` — `acme-night.json:6:5 unknown key "acent"` с `Did you mean "accent"?`, `settings-appearance-issue-2` — `acme-night.json:9:5 unknown key "tab_bg"` с `Ignored — not a theme role.`

#### Scenario: Reload применяет исправленный файл
- **WHEN** тема тёмного режима `acme-night` действует, пользователь исправил в файле `accent` и нажал «Reload»
- **THEN** app рисуется с новым `accent` без перезапуска

#### Scenario: Поздний результат чтения
- **WHEN** чтение каталога ещё идёт, и пользователь нажимает «Reload»
- **THEN** состояние страницы строит только второе чтение, событие `appearance.catalog_discarded` записано

#### Scenario: Каталог тем не читается
- **WHEN** порт каталога бросает исключение при чтении
- **THEN** карточки встроенных тем работают, показан `settings-appearance-catalog-failed` с кнопкой `settings-appearance-catalog-reload`, в журнале `appearance.catalog_failed` с `error_class` и без пути; нажатие кнопки читает каталог заново

#### Scenario: Управляющие символы в файле
- **WHEN** файл темы содержит в строке символ U+202E
- **THEN** текст файла на странице показывает его экранированным, а не меняет направление строки

#### Scenario: Экранирование не склеивает строки
- **WHEN** выбран файл темы из 13 строк с предупреждением в строке 6
- **THEN** просмотр `settings-appearance-file` показывает 13 строк, выделена строка 6, символов `\u000a` в тексте нет, табуляция в отступе показана четырьмя пробелами, а не `\u0009`

### Requirement: Импорт темы на странице «Appearance»
«Import JSON…» SHALL открывать системный диалог выбора одного файла `.json`. Отмена диалога SHALL ничего не менять. Выбранный файл SHALL импортироваться по spec client-themes «Импорт файла темы»:
- импорт удался — каталог перечитывается, импортированная тема выбирается для превью и НЕ применяется; если у неё есть предупреждения, показывается панель проблем;
- нужна замена — диалог `Replace the theme "<name>"?` с кнопками «Replace» (`settings-appearance-import-replace`) и «Cancel»; без «Replace» файл не меняется;
- тема уже есть с тем же содержимым — выбирается для превью без записи;
- ошибка разбора — InfoBar `error` `settings-appearance-import-failed`: `Couldn't import <file name>: <проблема с позицией>`, файл не копируется;
- источник не читается (нет доступа, не обычный файл, ошибка ввода-вывода) или тему не удалось записать в каталог тем — тот же InfoBar с `Couldn't import the theme. Check that the file is readable and try again.` без пути и текста исключения;
- источник изменился после вопроса о замене — тот же InfoBar с `The file changed after you chose it. Choose it again.`, файл не записан;
- системный диалог выбора файла не открылся — тот же InfoBar с `Couldn't open the file dialog.`, без текста исключения.

Пока идёт импорт, кнопка «Import JSON…» SHALL быть недоступна.

#### Scenario: Импорт и превью
- **WHEN** пользователь импортирует корректный файл `acme-night`
- **THEN** появляется карточка `settings-appearance-theme-custom-acme-night`, она выбрана, действующая тема не изменилась

#### Scenario: Диалог выбора файла не открылся
- **WHEN** системный диалог выбора файла бросает исключение
- **THEN** показан `settings-appearance-import-failed` с `Couldn't open the file dialog.`, в журнале `appearance.theme_imported` с `outcome: failed` и `error_class`, кнопка «Import JSON…» снова доступна

#### Scenario: Отказ от замены
- **WHEN** импортируется `acme-night` с другим содержимым, и пользователь нажимает «Cancel» в диалоге замены
- **THEN** файл `acme-night.json` не изменился

### Requirement: Контраст на фоне кода
Блок «Contrast on code background» (`settings-appearance-contrast`) SHALL показывать для выбранной темы строки `settings-appearance-contrast-<role>`: `Text` (`text`), `Comment` (`code.comment`), `Keyword` (`code.keyword`), `Link` (`info`), `Error` (`error`). В каждой строке — образец цвета, отношение контраста к `code.background` с одним знаком после точки (`4.8:1`) и вердикт `AA` (не меньше 4,5:1) или `Low`. Отношение SHALL считаться по WCAG 2 по относительной яркости непрозрачных цветов. Под строками — пояснение `Text roles need 4.5:1. A role below that still applies, with a warning on its card.`

Проверяемые роли — `text`, `info`, `error` и все роли `code.*`, кроме `code.background`. Роль ниже 4,5:1 SHALL применяться как задана и SHALL давать предупреждение `Low contrast` в бейдже карточки и в списке проблем. Встроенные темы НЕ SHALL иметь проверяемой роли ниже 4,5:1 ни при каком акценте.

#### Scenario: Низкий контраст пользовательской роли
- **WHEN** тема задаёт `"code": {"background": "#14121f", "comment": "#3a3650"}`
- **THEN** строка `settings-appearance-contrast-code.comment` показывает вердикт `Low`, бейдж карточки учитывает это предупреждение, комментарии в блоках кода рисуются цветом `#3a3650`

#### Scenario: Встроенные темы проходят
- **WHEN** тест перебирает встроенные темы `light`, `dark`, `high-contrast` с выключенным и включённым системным акцентом (несколько значений акцента)
- **THEN** у каждой проверяемой роли отношение к `code.background` не меньше 4,5:1

### Requirement: Хранение оформления
Режим, темы двух режимов и переключатель системного акцента SHALL храниться одним JSON-документом в `shared_preferences` под ключом `codelab.app.appearance`: `{"version": 1, "mode": "light" | "dark" | "system", "light_theme": "<id>", "dark_theme": "<id>", "system_accent": true | false}`. Отсутствующее поле SHALL браться по умолчанию. Файлы `$CODELAB_HOME` (`config.yaml`, `cli.yaml`, `profiles.json`) выбор НЕ SHALL менять.

Документ SHALL читаться до первого кадра вместе с файлами тем двух режимов. Каждый файл читается с ограничением времени 1 с; не прочитанный вовремя — как не загрузившийся. Незнакомый или нечитаемый документ и незнакомое значение поля SHALL читаться как значения по умолчанию для этих полей. Встроенная тема чужого режима в поле режима (`"light_theme": "dark"`) — тоже незнакомое значение. Пользовательская тема, база которой относится к другому режиму, SHALL считаться не загрузившейся для этого режима (требование «Режим оформления и темы режимов»), а не незнакомым значением: имя в документе сохраняется. Документ при этом НЕ SHALL перезаписываться до явного выбора пользователя, а в журнал SHALL писаться предупреждение без значения. Сбой хранилища при старте НЕ SHALL мешать запуску.

Если запись не удалась, выбор SHALL оставаться применённым до конца работы app, а страница SHALL показать ошибку (`settings-appearance-save-failed`) `Couldn't save the appearance. CodeLab will use the previous appearance after restart.` с кнопкой `Retry` (`settings-appearance-save-retry`). При нескольких выборах подряд SHALL применяться и сохраняться последний.

#### Scenario: Повреждённый документ
- **WHEN** `codelab.app.appearance` содержит `{"mode": "sepia"}`
- **THEN** app стартует с `Match system` и темами по умолчанию, ключ не перезаписан, в журнале предупреждение `appearance.stored_value_invalid` без значения

#### Scenario: Сбой записи
- **WHEN** запись `shared_preferences` бросает исключение после выбора `Dark`
- **THEN** app остаётся тёмным, страница показывает ошибку сохранения и `Retry`

### Requirement: События журнала оформления
События оформления SHALL писаться логгером `codelab_desktop.settings`:
- `app.appearance_resolved` при старте: `mode`, `light_theme`, `dark_theme`, `system_accent`, `fallback` (`none`, `light`, `dark`, `both`);
- `settings.appearance_changed`: `field` (`mode`, `light_theme`, `dark_theme`, `system_accent`) и новое значение;
- `appearance.theme_loaded`: `theme`, `extends`, `warnings` (число), `code_counts` (число предупреждений по каждому коду, без ключей и значений);
- `appearance.theme_invalid`: `theme`, `code`, `line`, `column`. `code` — код проблемы разбора (`ThemeIssueCode`), `missing` (файла нет), `tooLarge`, `notUtf8`, `unreadable` (ошибка чтения; при исключении порта — ещё поле `error_class`) или `wrongMode` (база темы относится к другому режиму); у проблем без позиции `line` и `column` равны 0;
- `appearance.theme_imported`: `outcome` (`imported`, `replaced`, `unchanged`, `cancelled`, `invalid`, `source_changed`, `failed`); при `failed` из-за исключения (в том числе диалога выбора файла) — ещё `error_class`;
- `appearance.catalog_failed`: `error_class` и, если порт сообщил причину, `failure` (`notADirectory` или `unreadable`) — каталог тем не удалось прочитать;
- `appearance.catalog_discarded`: `reason` (`reload`, `closed`);
- `appearance.save_failed` с именем типа ошибки (`error_class`); `appearance.save_timeout` с `timeout_ms`, если при закрытии запись не успела за 3 с;
- при старте: `appearance.stored_value_invalid` без полей (в документе незнакомое значение) и `appearance.read_failed` с `error_class` (хранилище не удалось прочитать);
- `appearance.system_accent_failed` с именем типа ошибки.

Идентификатор встроенной темы SHALL писаться как есть (`light`, `dark`, `high-contrast`), пользовательской — как `custom`. Пути, имена файлов и пользовательских тем, ключи и значения из файла и тексты исключений НЕ SHALL попадать в журнал.

#### Scenario: Журнал без имени пользовательской темы
- **WHEN** пользователь применяет `acme-night` и импортирует ещё одну тему
- **THEN** события содержат `theme: custom` и `outcome: imported`, строк `acme-night`, `themes/` и пути домашнего каталога в журнале нет

### Requirement: Открытие настроек из меню macOS
На macOS пункт главного меню приложения «Preferences…» (на русском интерфейсе ОС — «Настройки…») с сочетанием ⌘, SHALL открывать настройки так же, как сочетание `open-settings` (требование «Переход в настройки и обратно»): нативное меню передаёт команду в Dart по каналу `codelab/app_menu`, а Dart открывает настройки через `NavigationCubit` с источником `shortcut`. Пункт меню НЕ SHALL оставаться без действия: меню macOS перехватывает ⌘, раньше Flutter, и без действия сочетание не доходило бы до app. На других ОС Ctrl+, SHALL обрабатываться сочетанием Flutter (`CallbackShortcuts`), как раньше. Канал SHALL слушаться, пока жив владелец моста, и после его закрытия поздняя команда меню НЕ SHALL ничего делать (design.md change `add-app-appearance-page`, D15а).

#### Scenario: ⌘, на macOS
- **WHEN** app работает на macOS, и пользователь нажимает ⌘, или выбирает «Preferences…» в меню приложения
- **THEN** открывается экран настроек с последней выбранной страницей, событие `settings.opened` записано с `source: shortcut`

#### Scenario: Ctrl+, на других ОС
- **WHEN** app работает на Linux, и пользователь нажимает Ctrl+,
- **THEN** настройки открываются сочетанием Flutter, канал `codelab/app_menu` не участвует

#### Scenario: Неизвестная команда меню
- **WHEN** нативная сторона вызывает в канале `codelab/app_menu` неизвестный метод
- **THEN** вызов получает «метод не реализован», состояние навигации не меняется

### Requirement: Страница «Keyboard»: видимость и навигация
Composition root SHALL делать видимой страницу «Keyboard» группы «App» в рабочей сборке app при любой ширине окна. Её место в навигации — по порядку требования «Навигация настроек»: после «General» и «Appearance». Ключ пункта навигации — `settings-nav-keyboard`, ключ тела страницы — `settings-keyboard`.

У страницы нет ключей конфигурации: её содержимое — каталог сочетаний сборки (требование «Сочетания app и страница «Keyboard» не расходятся»). Каталог в рабочей сборке не пуст, поэтому страница не попадает под правило «страница без содержимого скрыта» (SETUP-17). Это исключение и из фразы «остальные страницы остаются скрытыми» требования «Страницы Providers и MCP servers в навигации» (design.md, D7).

Поиск «Find a setting» SHALL находить страницу по заголовку и по ключевым словам сообщения `settingsSearchKeywordsKeyboard`: на английском — `shortcut`, `hotkey`, `keybinding`, `key`. Выбор страницы SHALL сохраняться в `codelab.settings.last_page` значением `keyboard`, как у других страниц.

Страница SHALL быть только для чтения:
- она НЕ SHALL читать и писать `config.yaml`, `profiles.json` и `shared_preferences`, кроме `codelab.settings.last_page` оболочки;
- она НЕ SHALL обращаться к агенту;
- на ней НЕ SHALL быть элементов, которые меняют или назначают сочетания.

#### Scenario: Страница видна в рабочей сборке
- **WHEN** app собран с `defaultSettingsPages`, и пользователь открывает настройки
- **THEN** в группе «App» пункт `settings-nav-keyboard` стоит после `settings-nav-general`, а его выбор показывает тело `settings-keyboard`

#### Scenario: Узкое окно не скрывает страницу
- **WHEN** ширина окна 600 px, и пользователь открывает настройки
- **THEN** пункт `settings-nav-keyboard` есть в навигации сверху

#### Scenario: Поиск страницы по ключевому слову
- **WHEN** пользователь вводит `shortcut` в «Find a setting»
- **THEN** в навигации остаётся «Keyboard», а выбор результата открывает `settings-keyboard`

#### Scenario: Последняя страница
- **WHEN** пользователь выбрал «Keyboard», вернулся на рабочее место и снова открыл настройки
- **THEN** открыта страница «Keyboard», а `codelab.settings.last_page` равен `keyboard`

#### Scenario: Страница ничего не меняет
- **WHEN** пользователь открывает «Keyboard», ищет и закрывает настройки
- **THEN** файлы `$CODELAB_HOME` и ключи `shared_preferences`, кроме `codelab.settings.last_page`, не изменились, агенту ничего не отправлено

### Requirement: Страница «Keyboard»: строки таблицы
Страница SHALL показывать сверху вниз:
1. заголовок `Keyboard shortcuts`;
2. поле поиска с подсказкой `Search by action or key` (ключ `settings-keyboard-search`);
3. подпись `Read-only list. Shortcuts are fixed in the app.`;
4. таблицу с колонками `Action`, `Shortcut`, `Where`;
5. строку `Agent commands have no shortcuts; open them from the command palette.` (ключ `settings-keyboard-footer`).

Строки таблицы SHALL быть сгруппированы. Над каждой группой — строка-заголовок (ключ `settings-keyboard-group-<группа>`). Группы идут в порядке `Global` (`global`), `Navigation` (`navigation`), `Transcript` (`transcript`), `Composer` (`composer`), `Approvals` (`approvals`).

Таблица SHALL содержать ровно строки ниже, в этом порядке. Ключ строки — `settings-keyboard-row-<id>`. Колонка «Shortcut» дана для macOS и для остальных ОС (требование «Страница «Keyboard»: обозначения клавиш»). Знак `/` разделяет альтернативные клавиши одной строки.

| Группа | id | Action | macOS | Windows, Linux | Where |
|---|---|---|---|---|---|
| Global | `command-palette` | Open the command palette | ⌘ K | Ctrl K | Workbench |
| Global | `new-session` | New session | ⌘ N | Ctrl N | Workbench |
| Global | `open-folder` | Open a folder as the project | ⌘ O | Ctrl O | Workbench |
| Global | `open-settings` | Open settings | ⌘ , | Ctrl , | Workbench |
| Global | `close-overlay` | Close the command palette, a dialog or a sliding panel | Esc | Esc | Command palette, dialog or sliding panel |
| Global | `leave-settings` | Back to the workbench | Esc | Esc | Settings |
| Navigation | `toggle-sidebar` | Show or hide the sidebar | ⌘ B | Ctrl B | Workbench |
| Navigation | `toggle-files` | Show or hide the Files pane | ⇧ ⌘ E | Ctrl Shift E | Workbench, when the Files pane is available |
| Navigation | `file-tree-move` | Move through files | ↑ / ↓ | ↑ / ↓ | Files tree |
| Navigation | `file-tree-fold` | Expand or collapse a folder | → / ← | → / ← | Files tree, on a folder |
| Navigation | `file-tree-open` | Open a file or expand a folder | ⏎ | Enter | Files tree |
| Transcript | `cancel-turn` | Cancel the running turn | Esc | Esc | Workbench or composer, while a turn runs |
| Composer | `send` | Send the message; it is queued while the session is busy | ⌘ ⏎ | Ctrl Enter | Composer |
| Composer | `command-menu-move` | Move through commands | ↑ / ↓ | ↑ / ↓ | Command menu after / |
| Composer | `command-menu-run` | Run the highlighted command | ⏎ | Enter | Command menu after / |
| Composer | `command-menu-close` | Close the command menu | Esc | Esc | Command menu after / |
| Approvals | `go-to-approval` | Go to approval | ⇧ ⌘ A | Ctrl Shift A | Workbench, while an approval is pending |
| Approvals | `allow-once` | Allow once | ⌘ Y | Alt Shift Y | Workbench, earliest pending approval, if it offers this option |
| Approvals | `allow-always` | Allow always | ⌥ ⌘ Y | Alt Shift Q | Workbench, earliest pending approval, if it offers this option |
| Approvals | `reject-once` | Reject once | ⌥ ⌘ Z | Alt Shift X | Workbench, earliest pending approval, if it offers this option |
| Approvals | `reject-always` | Reject always | ⌥ ⇧ ⌘ Z | Alt Shift W | Workbench, earliest pending approval, if it offers this option |

Сочетаний, которых нет среди привязок сборки, на странице НЕ SHALL быть. В этой сборке это Cmd/Ctrl+/, Cmd/Ctrl+Shift+I, Cmd/Ctrl+Shift+F, Cmd/Ctrl+\\, Cmd/Ctrl+Shift+D, Cmd/Ctrl+Shift+Enter, Alt+Enter, Ctrl+\` и Ctrl+Shift+\`; Alt+←/→ тоже не привязаны. Alt+←/→ зарезервированы за навигацией инспектора (DSK-18) и строкой НЕ SHALL быть, пока не привязаны (решение пользователя Q2, 2026-11-19). Навигация дерева Files и меню команд после `/` — привязки app и показываются строками (решение пользователя Q3). Строка `go-to-approval` — привязка рабочего места, которая ставит клавиатурный фокус на полосу решения активного одобрения (spec agent-workbench-ui «Переход к ожидающему одобрению с клавиатуры»). Строки `allow-once`, `allow-always`, `reject-once`, `reject-always` — сочетания ответа, которые действуют с любого места рабочего места и отвечают самому раннему ожидающему одобрению активной сессии (spec agent-workbench-ui «Ответ на одобрение сочетанием с любого места рабочего места»); их клавиши различаются по платформам не только обозначениями. Стандартное поведение элементов управления строками НЕ SHALL показываться: Tab, Space и Enter на кнопке, правка и копирование текста в полях.

#### Scenario: Полный список на Linux
- **WHEN** платформа — Linux, и пользователь открывает «Keyboard» без запроса поиска
- **THEN** таблица показывает пять групп и 21 строку таблицы выше в том же порядке, с клавишами из колонки «Windows, Linux»

#### Scenario: Сочетаний без поведения нет
- **WHEN** пользователь открывает «Keyboard»
- **THEN** на странице нет строк с клавишами `/`, `I`, `F`, `\`, `D`, `` ` `` и строки steering, а также строки Alt+← и Alt+→

#### Scenario: Строка «Agent commands»
- **WHEN** пользователь открывает «Keyboard»
- **THEN** под таблицей показана строка `settings-keyboard-footer`, а кнопок назначения или сброса сочетаний на странице нет

#### Scenario: Строка «Go to approval»
- **WHEN** платформа — macOS, и пользователь открывает «Keyboard»
- **THEN** в группе `Approvals` первая строка — `go-to-approval` с действием `Go to approval`, кейкапами `⇧`, `⌘`, `A` и местом `Workbench, while an approval is pending`; у строк `allow-once`, `allow-always`, `reject-once`, `reject-always` место — `Workbench, earliest pending approval, if it offers this option`; строка `reject-always` на macOS — кейкапы `⌥`, `⇧`, `⌘`, `Z`

#### Scenario: Поиск строки перехода
- **WHEN** пользователь вводит `ctrl shift a`
- **THEN** видна только группа `Approvals` со строкой `go-to-approval`

#### Scenario: Поиск сочетания ответа в чужой нотации
- **WHEN** платформа — macOS, и пользователь вводит `alt shift y`
- **THEN** видна только строка `allow-once` с кейкапами `⌘` и `Y`

#### Scenario: Строка «Open folder»
- **WHEN** платформа — macOS, и пользователь открывает «Keyboard»
- **THEN** в группе `Global` сразу после `new-session` стоит строка `open-folder` с действием `Open a folder as the project`, кейкапами `⌘` и `O` и местом `Workbench` (design.md change `add-empty-project-screen`, D7)

#### Scenario: Поиск строки «Open folder»
- **WHEN** пользователь вводит `ctrl o`
- **THEN** видна только группа `Global` со строкой `open-folder`

### Requirement: Страница «Keyboard»: обозначения клавиш
Клавиши SHALL показываться кейкапами: каждая клавиша — отдельная плашка с рамкой, текст моноширинным шрифтом (`CodeLabTextRole.mono`). Обозначения выбираются по платформе app:
- на macOS: ⌘ (основной модификатор), ⌥, ⇧, ⏎, ⌫, модификаторы в порядке ⌥ ⇧ ⌘;
- на остальных ОС: `Ctrl` (основной модификатор), `Alt`, `Shift`, `Enter`, `Backspace`, модификаторы в порядке `Ctrl` `Alt` `Shift`.

`Esc`, буквы, `,` и стрелки ↑ ↓ ← → одинаковы на всех платформах. Обозначения клавиш НЕ SHALL переводиться. Пояснения вида «on macOS Ctrl reads Cmd» на странице НЕ SHALL быть: клавиши уже показаны в обозначениях платформы (решение пользователя Q1, 2026-11-19).

Для чтения с экрана сочетание SHALL иметь одну подпись словами, без символов клавиш:
- на macOS — например, `Shift+Cmd+E`, `Option+Cmd+Enter`;
- на остальных ОС — `Ctrl+Shift+E`, `Ctrl+Alt+Enter`.

Альтернативы одной строки подписываются через `or` на языке интерфейса.

Короткие подсказки сочетаний на рабочем месте SHALL строиться по тем же правилам:
- поле «Search or run a command» в шапке: `⌘K` или `Ctrl+K`;
- «New session» в сайдбаре: `⌘N` или `Ctrl+N`;
- кнопки и пункты вариантов одобрения: `⌘Y`, `⌥⌘Y`, `⌥⌘Z`, `⌥⇧⌘Z` на macOS; `Alt+Shift+Y`, `Alt+Shift+Q`, `Alt+Shift+X`, `Alt+Shift+W` на остальных ОС.

Порядок модификаторов один для всех подсказок: `Ctrl`, `Alt`, `Shift` на Windows и Linux (design.md `add-app-keyboard-page`, D4; решение пользователя Q4, 2026-11-19). Сочетания ответа на одобрение различаются по платформам не только обозначениями: на каждой платформе показываются и привязываются её клавиши (spec agent-workbench-ui «Ответ на одобрение сочетанием с любого места рабочего места»).

#### Scenario: macOS
- **WHEN** платформа — macOS, и пользователь открывает «Keyboard»
- **THEN** строка `toggle-files` показывает кейкапы `⇧`, `⌘`, `E`, а строка `allow-always` — `⌥`, `⌘`, `Y`

#### Scenario: Windows
- **WHEN** платформа — Windows, и пользователь открывает «Keyboard»
- **THEN** строка `toggle-files` показывает кейкапы `Ctrl`, `Shift`, `E`, а строка `reject-once` — `Alt`, `Shift`, `X`

#### Scenario: Подпись для чтения с экрана
- **WHEN** платформа — macOS, и программа чтения с экрана доходит до клавиш строки `allow-always`
- **THEN** подпись — `Option+Cmd+Y`, а не символы `⌥⌘Y`

#### Scenario: Подсказка «Allow always» на Linux
- **WHEN** платформа — Linux, и в ленте ждёт одобрение с вариантом `allow_always`
- **THEN** кнопка или пункт этого варианта показывает подсказку `Alt+Shift+Q`, а нажатие Alt+Shift+Q при видимой полосе выбирает его; Ctrl+Alt+Enter ничего не выбирает

### Requirement: Страница «Keyboard»: поиск
Поиск на странице SHALL отбирать строки таблицы по подстроке без учёта регистра и пробелов по краям. Строка подходит, если запрос содержится в одном из текстов:
- текст «Action» на языке интерфейса;
- английский текст «Action»;
- обозначение её клавиш в одной из нотаций, независимо от платформы app. Нотаций три: символами macOS (`⌥⌘⏎`), словами Windows и Linux (`Ctrl+Alt+Enter`) и словами macOS (`Option+Cmd+Enter`).

Перед сравнением с обозначением клавиш из запроса и из обозначения SHALL удаляться пробелы и знаки `+`. Поэтому `ctrl k`, `Ctrl+K`, `cmd+k` и `⌘K` находят строку `command-palette`.

Группа, в которой не осталось строк, SHALL скрываться вместе с заголовком. При пустом результате вместо таблицы SHALL показываться строка `No shortcuts match "<query>"` (ключ `settings-keyboard-empty`); строка `settings-keyboard-footer` остаётся. Пустой запрос SHALL показывать всю таблицу. Запрос поиска — временное состояние страницы: он НЕ SHALL сохраняться между открытиями настроек.

#### Scenario: Поиск по действию
- **WHEN** пользователь вводит `sidebar`
- **THEN** видна только группа `Navigation` со строкой `toggle-sidebar`

#### Scenario: Поиск по клавише в чужой нотации
- **WHEN** платформа — Linux, и пользователь вводит `⌘K`
- **THEN** видна строка `command-palette` с кейкапами `Ctrl` и `K`

#### Scenario: Поиск по клавише словами
- **WHEN** пользователь вводит `ctrl shift e`
- **THEN** видна только строка `toggle-files`

#### Scenario: Английский текст при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит `allow always`
- **THEN** видна строка `allow-always` с переведённым текстом действия из `app_ru.arb`

#### Scenario: Переведённый текст при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит часть перевода `Cancel the running turn` из `app_ru.arb`
- **THEN** видна строка `cancel-turn`

#### Scenario: Ничего не найдено
- **WHEN** пользователь вводит `zzz`
- **THEN** таблицы и заголовков групп нет, показана строка `No shortcuts match "zzz"`, строка `settings-keyboard-footer` на месте

### Requirement: Страница «Keyboard»: язык, доступность и узкое окно
Тексты страницы SHALL быть сообщениями каталогов app `en` и `ru` (требование «Локализация интерфейса app»):
- заголовок, подсказка поиска, подпись, заголовки колонок и групп;
- тексты «Action» и «Where»;
- строка «Agent commands» и пустой результат.

Смена языка SHALL пересобирать страницу сразу и НЕ SHALL сбрасывать введённый запрос поиска.

Таблица SHALL оставаться таблицей для чтения с экрана: строка группы — заголовок, строка сочетания читается как «действие, клавиши, где». Строки таблицы НЕ SHALL быть остановками обхода Tab: на странице с клавиатуры фокусируется поле поиска, а Esc по-прежнему возвращает на рабочее место (требование «Рабочее место недоступно с клавиатуры из настроек»).

Если ширины тела страницы не хватает таблице, таблица SHALL прокручиваться по горизонтали внутри своего блока, а не обрезать текст: текст «Action» и «Where» переносится, кейкапы не переносятся и не сжимаются.

#### Scenario: Русский интерфейс
- **WHEN** app работает на русском, и пользователь открывает «Keyboard»
- **THEN** заголовок, колонки, группы, действия, места и строка «Agent commands» — переводы из `app_ru.arb`, а кейкапы те же, что на английском

#### Scenario: Смена языка с запросом
- **WHEN** на странице введён запрос `esc`, и пользователь меняет язык на «Русский»
- **THEN** страница показана на русском, в поле поиска по-прежнему `esc`, видны те же строки

#### Scenario: Минимальное окно
- **WHEN** ширина окна 800 px (минимальное окно app), и пользователь открывает «Keyboard»
- **THEN** все три колонки видны без горизонтальной прокрутки, тексты «Action» и «Where» переносятся, ошибки переполнения нет

#### Scenario: Узкое окно
- **WHEN** область страницы уже минимальной ширины таблицы (380 px; окно 440 px), и пользователь открывает «Keyboard»
- **THEN** таблица прокручивается по горизонтали, ошибки переполнения нет, все кейкапы строки `allow-always` видны целиком после прокрутки

#### Scenario: Обход с клавиатуры
- **WHEN** фокус в навигации настроек на пункте `settings-nav-keyboard`, и пользователь нажимает Tab
- **THEN** фокус переходит в поле `settings-keyboard-search`, а не на строки таблицы

### Requirement: Сочетания app и страница «Keyboard» не расходятся
Каждая клавиатурная привязка рабочего места, экрана настроек и диалогов app SHALL быть строкой страницы «Keyboard» с теми же клавишами. Каждая строка страницы SHALL быть привязкой, которая выполняет своё действие в указанном месте. Короткие подсказки сочетаний на рабочем месте SHALL показывать клавиши той привязки, которой подсказка соответствует.

Change, который вводит, меняет или убирает сочетание, SHALL в том же change менять строку страницы «Keyboard», её тексты `en` и `ru` и проверку нажатием. Основной модификатор SHALL привязываться и к Ctrl, и к ⌘ на всех платформах, как до этого change. Исключение — сочетания ответа на одобрение: у них свои клавиши на macOS и на остальных ОС, и на каждой платформе привязываются только её клавиши (Ctrl+Y на Windows и Linux ответом не становится: в других приложениях это повтор правки). Привязки НЕ SHALL переназначаться этим требованием (DSK-18).

#### Scenario: Каждая строка проверена нажатием
- **WHEN** тест нажимает клавиши каждой строки таблицы в её месте: Ctrl-вариант на всех платформах, ⌘-вариант — у строк с основным модификатором; у строк ответа на одобрение — клавиши macOS при платформе macOS и клавиши Windows и Linux при платформе Linux
- **THEN** выполняется действие строки. Например, `allow-always` выбирает вариант `allow_always` видимого активного одобрения, а `leave-settings` возвращает на рабочее место без `session/cancel`

#### Scenario: Привязка вне списка
- **WHEN** в коде кита или app появляется привязка клавиш, которой нет на странице «Keyboard»
- **THEN** тест-сторож пакета падает и называет файл с этой привязкой

#### Scenario: Строки при русской раскладке
- **WHEN** платформа — macOS, раскладка — русская, и пользователь нажимает клавиши строк с буквой или знаком, как на английской раскладке
- **THEN** выполняется то же действие, что при английской раскладке, а кейкапы строки на странице — латинские. На Windows и Linux проверяется вручную

#### Scenario: Отправка и одобрение на разных клавишах
- **WHEN** ждёт видимое активное одобрение, и пользователь нажимает Cmd/Ctrl+Enter один раз с фокусом на полосе одобрения, а другой раз с фокусом в композере с текстом
- **THEN** в первом случае ничего не выбрано, во втором сообщение поставлено в очередь, а одобрение по-прежнему ждёт; ⌘Y (Alt+Shift+Y на Windows и Linux) в обоих местах выбирает `allow_once`

### Requirement: Страница «General»: состав и порядок
Страница «General» группы «App» SHALL показывать блоки в таком порядке (артборд «26 Settings — General»; design.md change `add-app-general-page`, D17; design.md change `add-app-legal-page`, D9):
1. InfoBar `settings-general-shared-info` и блок «Agent defaults» (`settings-general-agent-defaults`) — требования «Умолчания агента на странице «General»: …»;
2. блок «Interface» со строкой «Language» (`settings-general-language`, spec app-settings «Язык интерфейса app»); строка и её поведение этим требованием не меняются;
3. блок «Startup and files» со строкой «Reopen the last project and its tabs» (`settings-general-reopen-last-project`);
4. блок «Privacy» (`settings-general-privacy`) со строкой «No telemetry» (`settings-general-no-telemetry`): описание `The app, the CLI and the agent send no usage analytics or crash reports. Prompts and files go only to the provider and tools you set up.` и ссылка «Privacy policy» (`settings-general-privacy-policy`), которая открывает страницу «Legal» на вкладке «Privacy policy»;
5. раздел «About» (`settings-general-about`).

Строка без поведения в текущей сборке НЕ SHALL показываться (SETUP-17). Строки «When I press Enter during a turn», «Sidebar opens on» и «Send crash reports» НЕ SHALL показываться (design.md change `add-app-general-page`, D8, D17; E-21). У строки «No telemetry» нет переключателя: телеметрии нет, и выключать нечего. Блок, в котором не осталось видимых строк, SHALL быть скрыт вместе с заголовком.

Поиск «Find a setting» SHALL находить «General» по английским ключевым словам `language`, `budget`, `steps`, `compaction`, `subagent`, `log level`, `startup`, `reopen`, `ignored`, `about`, `version`, `license`, `diagnostics`, `telemetry` при любом языке интерфейса, а при русском интерфейсе — ещё по русским `язык`, `бюджет`, `шаги`, `сжатие`, `субагент`, `уровень журнала`, `запуск`, `открывать`, `игнорируемые`, `о программе`, `версия`, `лицензия`, `диагностика`, `телеметрия`. Слова обоих языков SHALL храниться в каталогах ARB `en` и `ru` (`settingsSearchKeywordsGeneral`, список через запятую; spec app-settings «Навигация настроек», change `add-desktop-localization`).

Все тексты страницы SHALL браться из каталогов ARB `en` и `ru` (spec app-settings «Локализация интерфейса app»). Ключи конфигурации, значения, источники `default`, `user`, `project`, `local`, `config`, `env`, пути и версии SHALL показываться как есть.

#### Scenario: Порядок блоков
- **WHEN** встроенный агент подключён, проект выбран, и пользователь открывает «General»
- **THEN** сверху вниз идут `settings-general-shared-info`, `settings-general-agent-defaults`, `settings-general-language`, `settings-general-reopen-last-project`, `settings-general-no-telemetry`, `settings-general-about`; строк Enter во время хода, «Sidebar opens on» и «Send crash reports» нет

#### Scenario: «No telemetry» ведёт на политику
- **WHEN** пользователь нажимает `settings-general-privacy-policy`
- **THEN** экран настроек показывает страницу «Legal» с выбранной вкладкой `settings-legal-tab-privacy-policy`, пункт навигации `settings-nav-legal` выбран, сеть не используется

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `compaction` в «Find a setting»
- **THEN** в навигации остаётся «General», а выбор результата открывает её

#### Scenario: Русское ключевое слово «General» зависит от языка интерфейса
- **WHEN** пользователь вводит `сжатие` в «Find a setting» сначала на русском интерфейсе, затем на английском
- **THEN** на русском в навигации остаётся «General», на английском ни одной страницы не найдено и показано `No settings match "сжатие"`

### Requirement: Умолчания агента на странице «General»: доступ и строки
Блок «Agent defaults» SHALL вычислять доступ так же, как «Providers», «MCP servers» и «Agents & modes»: `resolveSettingsAccess` для профиля текущего подключения, без подключения — для профиля по умолчанию; папка — папка сессии в фокусе, иначе выбранный проект, иначе без папки (требование «Доступ к настройкам агента на страницах Providers и MCP servers»). Смена подключения или папки SHALL перечитывать доступ и снимок. Снимок и запись SHALL идти через `AgentConfigStore` сессии страницы, строки — через `settingFieldsOf` моста `codelab_setup` (spec client-agent-setup «Состав моста codelab_setup для настройки агента»).

Блок SHALL показывать строки ключей реестра со `scope: shared` из разделов реестра Budget, Agent, Subagents и Logging, кроме ключей, у которых есть своя страница: `budget.max_steps`, `budget.max_tokens`, `budget.max_cost`, `budget.max_duration`, `compaction.enabled`, ключи `subagents.*` и `logging.level`. Ключи `agent.default_model`, `providers.*` («Providers»), `permissions.mode`, `agent.effort` («Agents & modes»), `mcp.servers` («MCP servers»), `permissions.deny`, `permissions.tools` (будущая «Permissions & tools») и `trusted_projects` (граница доверия) НЕ SHALL показываться на «General» (design.md, D2). Ключ реестра `scope: shared`, который не отнесён ни к «General», ни к странице-владельцу, SHALL ронять тест классификации, а не появляться на странице сам.

Строки SHALL группироваться по разделу реестра в порядке Budget, Agent, Subagents, Logging; внутри раздела — в порядке реестра. Над каждой непустой группой SHALL быть подзаголовок раздела на языке интерфейса (`Budget`, `Agent`, `Subagents`, `Logging`) с ключом `settings-general-agent-group-<section>` (`budget`, `agent`, `subagents`, `logging`). Строка SHALL показывать подпись ключа на языке интерфейса, ключ (`budget.max_steps`), итоговое значение (`SettingFieldView.displayValue`; для незаданного ключа без умолчания — `Not set`), источник `default`, `user`, `project`, `local`, `config` или `env` и тег `shared`. Ключ с `restartRequired` SHALL нести пометку `(applies after restart)`. Ключ строки — `settings-general-agent-row-<key>`. Описание строки НЕ SHALL обрезаться: при нехватке ширины оно переносится. Ключ SHALL переноситься только после `.` или `_` и SHALL быть доступен скринридеру целиком одной меткой.

Над блоком SHALL быть InfoBar уровня `info` `settings-general-shared-info`: `Shared with the codelab CLI. Rows marked shared come from the agent's settings registry and are saved to <home>/config.yaml; codelab /settings shows them too.`, где `<home>` — `$CODELAB_HOME` с `~` вместо домашнего каталога.

Для `RemoteReadOnly` и `NotManaged` блок НЕ SHALL читать локальный конфиг, НЕ SHALL показывать строк и InfoBar `settings-general-shared-info` и SHALL показывать InfoBar уровня `warning` `settings-general-agent-read-only`: `Read-only: this agent runs on <scheme://host:port>. Change its settings on that host: codelab config set.` или `Agent settings are managed by <agentName>.` (SETUP-2). Остальные блоки страницы при этом SHALL работать.

Если `config.yaml` не разбирается или нарушает схему, блок SHALL показывать проблемы загрузчика с путём ключа (`settings-general-agent-unreadable`) и НЕ SHALL предлагать запись. Пока снимок загружается, блок SHALL показывать индикатор загрузки, а остальные блоки страницы — работать.

#### Scenario: Строки из своего подмножества
- **WHEN** встроенный агент подключён, `$CODELAB_HOME/config.yaml` задаёт `budget.max_steps: 80` и `permissions.mode: ask`
- **THEN** блок показывает строку `settings-general-agent-row-budget.max_steps` со значением `80` и источником `user`, строку `settings-general-agent-row-compaction.enabled` со значением `true` и источником `default`; строк `permissions.mode`, `agent.effort`, `agent.default_model`, `trusted_projects` нет

#### Scenario: Новый ключ реестра без решения
- **WHEN** в реестр добавлен ключ `scope: shared`, который не отнесён ни к «General», ни к странице-владельцу
- **THEN** тест классификации ключей страницы падает и называет ключ

#### Scenario: Одинаковые подписи в разных группах
- **WHEN** встроенный агент подключён, и пользователь открывает «General»
- **THEN** строка `settings-general-agent-row-budget.max_steps` стоит под подзаголовком `settings-general-agent-group-budget` (`Budget`), а строка `settings-general-agent-row-subagents.max_steps` — под `settings-general-agent-group-subagents` (`Subagents`); на русском подзаголовки — «Бюджет» и «Субагенты»

#### Scenario: Узкое окно не обрезает описания и ключи
- **WHEN** app работает на русском, ширина области страницы соответствует окну 760 px, и пользователь открывает «General»
- **THEN** описание строки `settings-general-reopen-last-project` показано целиком, включая «Применится при следующем запуске», описания строк ключей не обрезаны многоточием, ключ `subagents.heartbeat_interval` разорван только после `.` или `_`, переполнения нет

#### Scenario: Пометка перезапуска
- **WHEN** блок показывает `logging.level`
- **THEN** строка несёт `(applies after restart)`

#### Scenario: WebSocket-агент
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp`, а в локальном `$CODELAB_HOME/config.yaml` есть `budget.max_steps: 80`
- **THEN** блок показывает `settings-general-agent-read-only` с `wss://devbox:7420` без `/acp`, строк и `settings-general-shared-info` нет, локальный файл не читался, а строка «Language» и раздел «About» доступны

#### Scenario: Битый конфиг
- **WHEN** `$CODELAB_HOME/config.yaml` не разбирается как YAML
- **THEN** блок показывает `settings-general-agent-unreadable` и не показывает редакторов; файл не изменён

### Requirement: Умолчания агента на странице «General»: запись
Редактор строки SHALL соответствовать типу дескриптора: `bool` — переключатель, `enumeration` — выпадающий список `enumValues`, `int`, `float` и `duration` — поле ввода. Поле ввода SHALL применять значение по Enter и при потере фокуса. Введённую строку SHALL разбирать `SettingsRegistry.parseCliValue`. При ошибке разбора запись НЕ SHALL выполняться, а под полем SHALL показываться подсказка формата на языке интерфейса, построенная по типу и границам дескриптора: `Enter a whole number of 1 or greater.`, `Enter a whole number from 1 to 3.`, `Enter a number.`, `Enter a duration like 500ms, 30s, 2m or 1h.`. Введённое значение в подсказку НЕ SHALL попадать. Пустое поле у ключа, заданного в слое `user`, SHALL записывать `UnsetValue`; у ключа, не заданного в `user`, пустое поле SHALL возвращать показанное значение без записи.

Запись SHALL выполняться одним `AgentConfigStore.apply` с одной правкой в слой `user`. Слои `project`, `projectLocal` и файл `--config` блок НЕ SHALL записывать (SETUP-3; design.md, D4). Под заголовком блока SHALL быть подпись `Changes are saved for all projects.`.

Строка НЕ SHALL редактироваться, и вместо редактора SHALL показываться значение с причиной, если правило моста `settingEditRefusalOf` отказывает (spec client-agent-setup «Правила правки строк настроек агента»):
- ключ хранит имя секрета — `Change it with codelab secret set.`;
- значение замаскировано — `This value contains a secret; change it in the config file.`;
- источник `config` или `env` — `Set by <source>; it cannot be changed here.`.

Если источник строки — `project` или `local`, строка SHALL оставаться редактируемой и показывать подпись `This project overrides it (<source>).`.

После `ConfigSaved` блок SHALL перечитывать снимок и строить баннер `settings-general-agent-banner` по действующему значению нового снимка (как D16 change `add-settings-agents-modes`):
- значение совпало с записанным — `Saved.`;
- значение совпало, и ключ входит в `restartRequiredKeys` — `Saved. Applies after Restart agent.`, если агент профиля подключён, иначе `Saved. Applies when the agent starts.`;
- значение перекрыто другим слоем — баннер уровня `warning` `Saved to all projects; <source> overrides it: the agent uses <effective>.` с тем же хвостом о перезапуске;
- перечитать не удалось — `Saved to <home>/config.yaml.`.

`ConfigConflict` SHALL давать баннер `The config file changed on disk; the page was reloaded. Try again.` и перечитывание снимка без автоповтора (SETUP-6). `ConfigRejected` SHALL давать баннер уровня `error` с путём ключа и текстом проблемы писателя как есть. `ConfigInlineSecret` SHALL давать баннер `Change it with codelab secret set.`. Пока идёт запись, повторные правки блока SHALL игнорироваться. Новая правка строки — в том числе неверный ввод и пустое поле без записи — SHALL снимать баннер прошлой записи.

Результат загрузки или записи, начатой до смены подключения, папки или до закрытия страницы, НЕ SHALL менять состояние блока. Правка, начатая до новой загрузки, НЕ SHALL записываться.

Блок НЕ SHALL отправлять агенту запросов ACP.

#### Scenario: Смена лимита шагов
- **WHEN** встроенный агент подключён, `budget.max_steps` нигде не задан, и пользователь вводит `80` в поле строки `settings-general-agent-row-budget.max_steps` и нажимает Enter
- **THEN** `$CODELAB_HOME/config.yaml` содержит `budget.max_steps: 80`, источник строки — `user`, баннер `settings-general-agent-banner` — `Saved.`; агенту не отправлено ни одного запроса

#### Scenario: Неверное число
- **WHEN** пользователь вводит `0` в поле `budget.max_steps`
- **THEN** под полем показано `Enter a whole number of 1 or greater.` без `0`, файл конфига не изменён

#### Scenario: Ключ с перезапуском
- **WHEN** встроенный агент подключён, и пользователь выбирает `debug` в строке `logging.level`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `logging.level: debug`, баннер — `Saved. Applies after Restart agent.`

#### Scenario: Перекрытие проектным файлом
- **WHEN** выбран проект `/work/demo`, его `.codelab/config.local.yaml` задаёт `compaction.enabled: false`, и пользователь включает `compaction.enabled`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `compaction.enabled: true`, `/work/demo/.codelab/config.local.yaml` не изменён, баннер уровня `warning` содержит `Saved to all projects; local overrides it: the agent uses false`

#### Scenario: Значение из окружения
- **WHEN** `budget.max_steps` задан переменной окружения агента
- **THEN** строка показывает значение и `Set by env; it cannot be changed here.` без редактора

#### Scenario: Сброс поля
- **WHEN** `$CODELAB_HOME/config.yaml` задаёт `budget.max_tokens: 100000`, и пользователь очищает поле и нажимает Enter
- **THEN** ключ `budget.max_tokens` удалён из `$CODELAB_HOME/config.yaml`, строка показывает `Not set` и источник `default`

#### Scenario: Конфликт записи
- **WHEN** файл конфига изменён на диске после загрузки снимка, и пользователь меняет `compaction.enabled`
- **THEN** файл не перезаписан, баннер содержит `The config file changed on disk`, снимок перечитан, повторной записи нет

#### Scenario: Неверный ввод после успешной записи
- **WHEN** запись `budget.max_steps: 80` дала баннер `Saved.`, и затем пользователь вводит `0` в поле `budget.max_steps`
- **THEN** баннера `settings-general-agent-banner` нет, под полем показано `Enter a whole number of 1 or greater.`, файл конфига не изменён

#### Scenario: Смена подключения во время записи
- **WHEN** запись `budget.max_steps` идёт, и подключение переходит на профиль `wss://devbox:7420/acp`
- **THEN** блок показывает `settings-general-agent-read-only`, баннера о записи нет

### Requirement: Открытие последнего проекта при запуске
Строка «Reopen the last project and its tabs» (`settings-general-reopen-last-project`) SHALL быть переключателем настройки app `codelab.workspace.reopen_last_project` в `shared_preferences` (`bool`, по умолчанию включено; во включённом состоянии ключ удаляется). Подпись строки SHALL быть `On: open the last project and its open sessions. Off: start with recent projects in the sidebar. Applies at the next start.` «Its tabs» в этой сборке — открытые сессии снимка рабочего пространства (spec acp-client-kit «Восстановление после перезапуска»).

При старте app SHALL читать настройку до восстановления проекта прошлого запуска:
- включено — поведение не меняется (spec acp-client-kit «Восстановление после перезапуска»);
- выключено — app НЕ SHALL выбирать проект из снимка, НЕ SHALL восстанавливать его сессии и НЕ SHALL запускать агента при старте. Сайдбар SHALL показывать недавние проекты и «Open folder…» (spec agent-workbench-ui «"Open Project" offers native browse and recent projects»). Рабочее пространство SHALL стартовать через `ClientWorkspace.startWithoutRestore()`, так что снимок этого запуска пишется как обычно;
- значение не читается (сбой хранилища, нестроковое или небулево значение) — как при включённом, с предупреждением в журнале без текста ошибки; значение не перезаписывается.

Переключение SHALL сразу записывать значение и НЕ SHALL менять открытый проект, сессии и подключение. Сбой записи SHALL оставлять переключатель в выбранном положении и показывать `Couldn't save this setting. The previous value applies at the next start.` с кнопкой `Retry` (`settings-general-reopen-last-project-retry`).

#### Scenario: По умолчанию проект прошлого запуска открывается
- **WHEN** ключа `codelab.workspace.reopen_last_project` нет, а снимок прошлого запуска содержит проект `/work/app` с активной сессией `sess_42`
- **THEN** app выбирает `/work/app` и при первом подключении загружает `sess_42`, как раньше

#### Scenario: Выключено — старт без проекта
- **WHEN** пользователь выключил «Reopen the last project and its tabs», закрыл app и запустил снова, а снимок содержит проект `/work/app`
- **THEN** проект не выбран, агент не запущен, `session/load` и `session/new` не отправлены, сайдбар показывает недавние проекты с `/work/app` и «Open folder…»

#### Scenario: Выключено — снимок нового запуска пишется
- **WHEN** настройка выключена, app стартовал без проекта, пользователь выбрал проект `/work/other`, затем включил настройку и перезапустил app
- **THEN** при старте выбран `/work/other`, а не проект прошлого снимка

#### Scenario: Переключение не трогает текущую работу
- **WHEN** открыт проект `/work/app` с идущей сессией, и пользователь выключает настройку
- **THEN** проект, сессии и подключение не меняются, агенту не отправлено ни одного запроса

### Requirement: Раздел «About» страницы «General»
Раздел «About» (`settings-general-about`) SHALL быть Fluent `Expander`, по умолчанию свёрнутым. В заголовке SHALL быть `CodeLab <version>` и строка `<os> <arch> · embedded agent <agentVersion>`, где:
- `<version>` — версия сборки app из константы, которую тест сверяет с полем `version` в `apps/codelab_desktop/pubspec.yaml`;
- `<os>` и `<arch>` — операционная система и архитектура процесса (`macOS arm64`, `Linux x64`, `Windows x64`);
- `<agentVersion>` — `embeddedAgentVersion` моста `codelab_embedded` (spec embedded-agent «Версия встроенного агента для клиентов»).

В развёрнутом разделе SHALL быть:
- строка «License» — ссылка `MIT` (`settings-general-about-license`) и строка авторского права из `LICENSE`; ссылка открывает страницу «Legal» на вкладке «License»;
- строка «Config folder» — `$CODELAB_HOME`, разрешённый composition root, с `~` вместо домашнего каталога;
- кнопки «Copy diagnostics» (`settings-general-about-copy-diagnostics`), «Privacy policy» (`settings-general-about-privacy`), «Terms of use» (`settings-general-about-terms`), «Third-party notices» (`settings-general-about-third-party`), «Release notes» (`settings-general-about-release-notes`), «Open log folder» (`settings-general-about-open-logs`);
- InfoBar уровня `info` `settings-general-about-updates`: `Updates come from the installer or your package manager — the app does not update itself.` (D-16, U-29).

Строки «Channel» и «Signed by» НЕ SHALL показываться: в сборке нет источника этих значений (design.md change `add-app-general-page`, D11).

«Privacy policy», «Terms of use» и «Third-party notices» SHALL открывать страницу «Legal» на одноимённой вкладке без сети (design.md change `add-app-legal-page`, D9). Диалога `settings-general-third-party-dialog` НЕ SHALL быть: записи реестра и лицензии пакетов показывает только вкладка «Third-party notices» страницы «Legal», по тем же правилам (требование «Страница «Legal»: вкладка «Third-party notices»»).

«Release notes» SHALL открывать `CHANGELOG.md` репозитория CodeLab в браузере через порт `ExternalLinkOpener`. Адрес SHALL быть константой app, а не вводом пользователя.

«Open log folder» SHALL открывать каталог журналов app (`<application support>/logs`, тот же, что получает `CodeLabLoggingModule`) через порт `LocalFolderOpener` без создания каталога.

Сбой открытия ссылки или каталога SHALL показывать InfoBar `settings-general-about-open-failed`: `Couldn't open the release notes.` или `Couldn't open the log folder.`. Текст исключения и путь в InfoBar НЕ SHALL попадать.

Сбой «Copy diagnostics» (сбор данных окна, построение текста или запись в буфер обмена) SHALL показывать InfoBar уровня `warning` `settings-general-about-copy-failed`: `Couldn't copy the diagnostics.`. Подтверждение `Diagnostics copied.` при этом НЕ SHALL показываться, а текст диагностики НЕ SHALL класться в буфер обмена.

Если данные раздела не читаются (ресурсы `assets/legal/` сборки), вместо развёрнутого раздела под заголовком «About» SHALL показываться InfoBar уровня `warning` `settings-general-about-load-failed`: `Couldn't load the About section.`. Остальные блоки страницы при этом SHALL работать.

Текст исключения и путь НЕ SHALL попадать ни в один InfoBar раздела.

#### Scenario: Версии в заголовке
- **WHEN** app версии `0.1.0` запущен на macOS arm64, и пользователь открывает «General»
- **THEN** заголовок «About» содержит `CodeLab 0.1.0` и `macOS arm64 · embedded agent 0.1.0`, строк «Channel» и «Signed by» нет

#### Scenario: Ссылки «About» открывают вкладки Legal
- **WHEN** пользователь по очереди возвращается на «General» и нажимает `settings-general-about-privacy`, `settings-general-about-terms`, `settings-general-about-license` и `settings-general-about-third-party`
- **THEN** каждый раз открыта страница «Legal» с выбранной вкладкой `settings-legal-tab-privacy-policy`, `settings-legal-tab-terms-of-use`, `settings-legal-tab-license` и `settings-legal-tab-third-party-notices` соответственно, `ExternalLinkOpener.open` не вызывался

#### Scenario: Диалога сторонних уведомлений нет
- **WHEN** пользователь нажимает `settings-general-about-third-party`
- **THEN** диалога `settings-general-third-party-dialog` нет, вкладка «Third-party notices» страницы «Legal» показывает запись `JetBrains Mono (шрифт в пакете gpt_markdown)` и список лицензий пакетов

#### Scenario: Release notes через порт
- **WHEN** пользователь нажимает «Release notes»
- **THEN** `ExternalLinkOpener.open` вызван один раз с адресом `CHANGELOG.md` репозитория CodeLab

#### Scenario: Каталог журналов не открылся
- **WHEN** `LocalFolderOpener` возвращает `failed` для каталога журналов
- **THEN** показан InfoBar `settings-general-about-open-failed` с `Couldn't open the log folder.` без пути

#### Scenario: Диагностика не скопировалась
- **WHEN** запись в буфер обмена при «Copy diagnostics» завершается ошибкой
- **THEN** показан InfoBar `settings-general-about-copy-failed` с `Couldn't copy the diagnostics.` без текста исключения, `Diagnostics copied.` не показан, журнал содержит `settings.about_action` с `action: copy_diagnostics` и `outcome: failed`

#### Scenario: Данные раздела не прочитались
- **WHEN** ресурс `assets/legal/LICENSE` не читается, и пользователь открывает «General»
- **THEN** под заголовком «About» показан InfoBar `settings-general-about-load-failed` с `Couldn't load the About section.` без пути и текста исключения, кнопок раздела нет, блоки «Agent defaults», «Interface», «Startup and files» и «Privacy» работают; журнал содержит `settings.about_load_failed` с именем типа исключения

### Requirement: Диагностика для отчёта без секретов и путей
«Copy diagnostics» SHALL класть в буфер обмена текст на английском из фиксированных строк, независимо от языка интерфейса (spec app-settings «Локализация интерфейса app»: диагностика не переводится):
- `CodeLab <version>`;
- `OS: <os> <arch>`;
- `Embedded agent: <agentVersion>`;
- `UI language: <locale> (preference: system|en|ru)`;
- `Connection: <embedded|stdio|websocket> · <state>`, где `<state>` — состояние подключения окна (`connecting`, `connected`, `reconnecting`, `failed`, `disconnected`);
- `Agent settings: editable|remote-read-only|not-managed`;
- `Config folder: default|custom` — задан ли `CODELAB_HOME`.

Текст НЕ SHALL содержать пути (в том числе папки проекта, `$CODELAB_HOME` и каталога журналов), URL, адреса и порты, id и имена профилей, команды и аргументы stdio-профиля, имена и значения переменных окружения, имена и значения секретов, id сессий, значения конфигурации и тексты исключений. После копирования страница SHALL показывать подтверждение `Diagnostics copied.`.

#### Scenario: Ничего лишнего в буфере
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp?t=sk-test-leak-0123456789` с id `devbox`, выбран проект `/Users/alice/work/app`, `CODELAB_HOME` равен `/Users/alice/.codelab-test`, и пользователь нажимает «Copy diagnostics»
- **THEN** буфер обмена содержит `Connection: websocket · connected` и `Config folder: custom` и не содержит `sk-test-leak-0123456789`, `devbox`, `7420`, `/acp`, `alice` и `/Users`

#### Scenario: Текст не зависит от языка
- **WHEN** app работает на русском, и пользователь нажимает «Copy diagnostics»
- **THEN** буфер обмена содержит `UI language: ru (preference: ru)` и английские подписи строк

### Requirement: События журнала страницы «General»
Страница SHALL писать события логгера `codelab_desktop.settings`:
- `agent_defaults.loaded` (`rows`, `access`), `agent_defaults.unreadable`, `agent_defaults.load_discarded` (`reason: reload | access_changed | closed`);
- `agent_defaults.saved` (`key`, `restart_required`, `overridden`) и `agent_defaults.save_failed` (`key`, `outcome: conflict | rejected | inline_secret | stale | error`, при `error` — имя типа исключения);
- `settings.reopen_last_project_changed` (`enabled`) и `settings.reopen_last_project_save_failed` (имя типа исключения);
- `settings.about_action` (`action: copy_diagnostics | release_notes | open_logs`, `outcome: opened | copied | failed | rejected_scheme | missing`);
- `settings.legal_link` (`from: privacy_block | about`, `tab: privacy_policy | terms_of_use | license | third_party_notices`) — переход на страницу «Legal»;
- `settings.about_load_failed` (`error_type` — имя типа исключения) — данные раздела «About» не прочитались.

Старт app с выключенной настройкой SHALL писать `app.reopen_last_project_skipped`. Сбой чтения настройки SHALL писать `app.reopen_last_project_unreadable` с именем типа исключения.

События НЕ SHALL содержать значений ключей конфигурации, путей, URL и текстов исключений (CFG-10; AGENTS.md §16).

#### Scenario: Запись без значения в журнале
- **WHEN** пользователь записывает `budget.max_steps: 80`
- **THEN** журнал содержит `agent_defaults.saved` с `key: budget.max_steps` и не содержит `80` ни в одном поле события

#### Scenario: Переход на Legal в журнале
- **WHEN** пользователь нажимает `settings-general-about-terms`
- **THEN** журнал содержит `settings.legal_link` с `from: about` и `tab: terms_of_use`

### Requirement: Страница «Legal»: видимость и вкладки
Страница «Legal» (`settings-legal`, последний пункт группы «App») SHALL показывать правовые документы сборки на четырёх вкладках в таком порядке (`dart-agent-and-clients` §12.7.7а; артборды 32–35):
1. «Privacy policy» (`settings-legal-tab-privacy-policy`) — `PRIVACY.md`;
2. «Terms of use» (`settings-legal-tab-terms-of-use`) — `TERMS.md`;
3. «License» (`settings-legal-tab-license`) — требование «Страница «Legal»: вкладка «License»»;
4. «Third-party notices» (`settings-legal-tab-third-party-notices`) — требование «Страница «Legal»: вкладка «Third-party notices»».

Вкладки SHALL быть одной группой с подписью `Legal documents` для программ чтения с экрана; выбранная вкладка SHALL объявляться выбранной. В окне шириной 800 px и на русском языке подписи вкладок НЕ SHALL обрезаться: не помещающиеся вкладки прокручиваются по горизонтали.

Страница SHALL быть видна в каждой сборке app: её содержимое задают ресурсы сборки, а не конфигурация (SETUP-17; design.md, D1). Выбор пунктом навигации, поиском или последней сохранённой страницей SHALL открывать вкладку «Privacy policy». Переход со страницы «General» SHALL открывать вкладку, названную ссылкой. Выбранная вкладка и запрос поиска НЕ SHALL сохраняться между открытиями страницы; `codelab.settings.last_page` хранит только страницу (`legal`).

Под вкладками SHALL стоять подпись источника `settings-legal-source`: `Bundled with CodeLab <version> as <asset> · readable offline`, где `<asset>` — путь ресурса показанного документа (`assets/legal/PRIVACY.md`, `assets/legal/TERMS.ru.md`, `assets/legal/LICENSE`, `assets/legal/THIRD_PARTY_NOTICES.md`).

Страница НЕ SHALL обращаться к сети для показа документов. Кнопок и флажков принятия условий, записи о согласии в `shared_preferences` и `~/.codelab` НЕ SHALL быть (D-29, §12.7.7а). Кнопок «Copy link», «Open on the web», «Copy all», «Open LICENSE» и оглавления «On this page» артбордов НЕ SHALL быть в этой сборке (design.md, D12).

Поиск «Find a setting» SHALL находить «Legal» по английским ключевым словам `legal`, `privacy`, `terms`, `license`, `notices`, `third-party`, `telemetry`, `packages` при любом языке интерфейса, а при русском — ещё по `правовая`, `конфиденциальность`, `условия`, `лицензия`, `уведомления`, `телеметрия`, `пакеты` (`settingsSearchKeywordsLegal`).

#### Scenario: Пункт навигации открывает политику
- **WHEN** пользователь выбирает `settings-nav-legal`
- **THEN** выбрана вкладка `settings-legal-tab-privacy-policy`, показан текст `assets/legal/PRIVACY.md`, подпись `settings-legal-source` содержит `assets/legal/PRIVACY.md`

#### Scenario: Последняя страница без вкладки
- **WHEN** пользователь ушёл со страницы «Legal» с вкладки «License» и снова открыл настройки
- **THEN** открыта страница «Legal» на вкладке «Privacy policy»

#### Scenario: Принимать нечего
- **WHEN** пользователь открывает каждую из четырёх вкладок
- **THEN** на странице нет флажка, кнопки или переключателя согласия, а `shared_preferences` не изменились

#### Scenario: Узкое окно на русском
- **WHEN** app работает на русском в окне шириной 800 px, и пользователь открывает «Legal»
- **THEN** подписи четырёх вкладок видны целиком без многоточия, переполнения раскладки нет

#### Scenario: Поиск страницы по ключевому слову
- **WHEN** пользователь вводит `privacy` в «Find a setting»
- **THEN** в навигации остаётся `settings-nav-legal`

### Requirement: Страница «Legal»: документы на языке интерфейса
Вкладки «Privacy policy» и «Terms of use» SHALL показывать редакцию документа на языке интерфейса app (spec app-settings «Язык интерфейса app»): при русском — `assets/legal/PRIVACY.ru.md` и `assets/legal/TERMS.ru.md`, при любом другом — `assets/legal/PRIVACY.md` и `assets/legal/TERMS.md` (design.md, D2). Смена языка при открытой странице SHALL показывать редакцию нового языка без перезапуска; выбранная вкладка и запрос поиска при этом SHALL сохраняться.

Документ SHALL показываться как есть, без сокращений и правок, как markdown (`CodeLabMarkdown` кита) с выделением текста. Таблицы документа SHALL переносить текст ячеек по ширине: все столбцы видны без горизонтальной прокрутки (design.md, D6).

Если ресурс документа не читается, на месте документа SHALL показываться InfoBar уровня `warning` `settings-legal-load-failed`: `Couldn't load this document.`. Остальные вкладки SHALL работать. Путь и текст исключения в InfoBar НЕ SHALL попадать.

#### Scenario: Русская редакция
- **WHEN** app работает на русском, и пользователь открывает вкладку «Terms of use»
- **THEN** показан текст `assets/legal/TERMS.ru.md`, подпись `settings-legal-source` содержит `assets/legal/TERMS.ru.md`

#### Scenario: Английская редакция для другого языка
- **WHEN** app работает на английском, и пользователь открывает вкладку «Privacy policy»
- **THEN** показан текст `assets/legal/PRIVACY.md`

#### Scenario: Смена языка при открытой странице
- **WHEN** открыта вкладка «Privacy policy» на английском, и пользователь переключает язык интерфейса на русский
- **THEN** показан текст `assets/legal/PRIVACY.ru.md`, выбрана та же вкладка

#### Scenario: Широкая таблица переносится
- **WHEN** пользователь открывает документ с таблицей из четырёх столбцов в окне шириной 800 px
- **THEN** все четыре столбца видны без горизонтальной прокрутки, текст ячеек перенесён по ширине, переполнения раскладки нет

#### Scenario: Документ не прочитался
- **WHEN** ресурс `assets/legal/TERMS.md` не читается, и пользователь открывает вкладку «Terms of use» на английском
- **THEN** показан InfoBar `settings-legal-load-failed` с `Couldn't load this document.` без пути; вкладка «Privacy policy» показывает свой документ; журнал содержит `legal.document_load_failed` с `tab: terms_of_use` и именем типа исключения

### Requirement: Страница «Legal»: ссылки внутри документов
Ссылки в показанном документе SHALL обрабатываться политикой app, а не виджетом (`CodeLabMarkdownScope`; design.md, D8):
- относительная ссылка на `PRIVACY.md`, `PRIVACY.ru.md`, `TERMS.md`, `TERMS.ru.md`, `LICENSE` или `THIRD_PARTY_NOTICES.md` (с `./` или без, с якорем или без) SHALL переключать вкладку страницы на этот документ без сети;
- ссылка `https:` SHALL открываться в браузере через порт `ExternalLinkOpener`;
- остальные ссылки SHALL быть неактивными.

Изображения в документах НЕ SHALL загружаться.

Если порт не открыл ссылку `https:` (`failed` или `rejectedScheme`), SHALL показываться InfoBar `settings-legal-link-failed`: `Couldn't open the link.`. Адрес и текст исключения в InfoBar НЕ SHALL попадать.

#### Scenario: Ссылка условий на лицензию
- **WHEN** на вкладке «Terms of use» пользователь нажимает ссылку на `LICENSE`
- **THEN** выбрана вкладка `settings-legal-tab-license`, `ExternalLinkOpener.open` не вызывался, журнал содержит `legal.link_opened` с `target: tab` и `outcome: opened`

#### Scenario: Ссылка на неизвестный файл неактивна
- **WHEN** документ содержит ссылку `SECURITY.md`
- **THEN** ссылка показана неактивной, нажатие ничего не открывает

### Requirement: Страница «Legal»: вкладка «License»
Вкладка «License» SHALL показывать:
1. краткое содержание MIT (`settings-legal-license-summary`) из трёх строк: «Allowed» — `Use, copy, modify, merge, publish, distribute, sublicense and sell copies`, «Condition» — `Keep the copyright and license notice in copies or substantial portions`, «No warranty» — `Provided “as is”; the authors are not liable for damages`, и под ними — `This summary is not the license. The full text below is what applies.`;
2. абзац «Third-party components»: `Open-source packages bundled with CodeLab keep their own licenses. They are listed in Third-party notices.` со ссылкой `settings-legal-license-notices-link` внутри строки текста, которая выбирает вкладку «Third-party notices». Ссылка SHALL объявляться ссылкой для программ чтения с экрана, получать фокус и срабатывать по Enter и Space; кавычки вокруг неё НЕ SHALL отрываться от неё при переносе строки (design.md, D6);
3. полный текст `assets/legal/LICENSE` (`settings-legal-license-text`) как есть, моноширинно, с выделением.

Краткое содержание SHALL быть сообщениями ARB `en` и `ru`; полный текст `LICENSE` НЕ SHALL переводиться.

#### Scenario: Полный текст лицензии
- **WHEN** пользователь открывает вкладку «License» на русском
- **THEN** краткое содержание показано на русском, `settings-legal-license-text` побайтно совпадает с текстом `assets/legal/LICENSE` и содержит `MIT License`

#### Scenario: Переход к сторонним уведомлениям
- **WHEN** пользователь нажимает `settings-legal-license-notices-link`
- **THEN** выбрана вкладка `settings-legal-tab-third-party-notices`

### Requirement: Страница «Legal»: вкладка «Third-party notices»
Вкладка «Third-party notices» SHALL показывать два раздела (правила D13 change `add-app-general-page` сохраняются; design.md, D10):
1. «Notices register» (`settings-legal-notices-records`) — подпись `Entries of the CodeLab third-party notices register, as kept in the repository.` и записи раздела `## Записи` файла `assets/legal/THIRD_PARTY_NOTICES.md` как есть, без перевода, на любом языке интерфейса. Заголовок первого уровня файла, вводная и раздел `## Формат записи` НЕ SHALL показываться; если раздела `## Записи` нет, SHALL показываться весь файл без заголовка первого уровня;
2. «Package licenses» — InfoBar уровня `info` `settings-legal-packages-info`: `Every package the build collected, including development tools of the workspace. A longer list is safe; a missing license would not be.`, поле поиска (требование «Страница «Legal»: поиск по пакетам») и список пакетов.

Пакет SHALL быть уникальным именем из поля `packages` записей реестра лицензий Flutter (`LicenseRegistry`); запись с несколькими именами SHALL относиться к каждому. Пакеты SHALL идти по имени. Пакет SHALL показываться свёрнутым `Expander` (`settings-legal-package-<name>`) с именем в заголовке и числом лицензий (`1 license`, `2 licenses`); развёрнутый — текстами лицензий как есть, с выделением.

Пока реестр собирается, вместо списка SHALL показываться индикатор `settings-legal-packages-loading`. Сбой реестра НЕ SHALL прятать записи реестра уведомлений: список SHALL показывать то, что успело собраться.

#### Scenario: Записи реестра офлайн
- **WHEN** сети нет, и пользователь открывает вкладку «Third-party notices» на английском
- **THEN** `settings-legal-notices-records` содержит запись `JetBrains Mono (шрифт в пакете gpt_markdown)` и подпись `Entries of the CodeLab third-party notices register, as kept in the repository.`; раздела `Формат записи` и строки шаблона `<Название источника>` нет

#### Scenario: Пакет из записи с двумя именами
- **WHEN** реестр лицензий возвращает одну запись с пакетами `alpha` и `beta` и одну запись с пакетом `alpha`
- **THEN** список содержит `settings-legal-package-alpha` с `2 licenses` и `settings-legal-package-beta` с `1 license`, счётчик — `2 packages`

#### Scenario: Сбой реестра лицензий
- **WHEN** поток реестра лицензий отдаёт запись пакета `alpha` и завершается ошибкой
- **THEN** записи реестра уведомлений показаны, список содержит `settings-legal-package-alpha`, журнал содержит `legal.licenses_collected` с `packages: 1` и `failed: true`

### Requirement: Страница «Legal»: поиск по пакетам
Над списком пакетов вкладки «Third-party notices» SHALL стоять поле `settings-legal-packages-search` с подсказкой `Search packages` и доступным именем `Search packages by name` (§12.7.7а; артборды 35, 35a–35c; design.md, D5–D7). Поиск SHALL только сужать показ, а не менять состав списка:
- пакет показывается, если запрос без пробелов по краям входит в его имя как подстрока без учёта регистра; пустой запрос или запрос из одних пробелов показывает все пакеты;
- записи реестра уведомлений («Notices register») SHALL оставаться видимыми при любом запросе;
- счётчик `settings-legal-packages-count` SHALL показывать `<N> packages` при пустом запросе и `<M> of <N> packages` при непустом (`0 of <N> packages`, если совпадений нет), где `N` — число пакетов, `M` — число показанных;
- в имени показанного пакета SHALL подсвечиваться каждое вхождение запроса без учёта регистра; текст имени и его подпись для программ чтения с экрана SHALL оставаться прежними; раскрытие пакета SHALL работать так же, как без запроса;
- при непустом запросе в поле SHALL быть кнопка очистки `settings-legal-packages-clear` с доступным именем `Clear search`; она очищает запрос и возвращает полный список;
- если совпадений нет, вместо списка SHALL показываться блок `settings-legal-packages-empty`: заголовок `No packages match`, текст `No package name contains “<query>”. The notices register above is not affected by search.` и кнопка `Clear search` (`settings-legal-packages-empty-clear`) с тем же действием, что у крестика. Запрос в тексте SHALL показываться с экранированием управляющих и bidi-символов (`escapeForDisplay`).

Запрос SHALL жить только в состоянии страницы: НЕ SHALL сохраняться между открытиями страницы, НЕ SHALL попадать в журнал, `shared_preferences`, `~/.codelab` и запросы за пределы процесса. Подписи поля, счётчика, кнопок и пустого блока SHALL быть сообщениями ARB `en` и `ru` с ICU `plural`; имена пакетов НЕ SHALL переводиться.

#### Scenario: Совпадение без учёта регистра
- **WHEN** пакеты — `flutter`, `flutter_bloc`, `fpdart`, `val_latex_flutter`, и пользователь вводит `FLUTTER`
- **THEN** показаны `flutter`, `flutter_bloc`, `val_latex_flutter` в этом порядке, счётчик — `3 of 4 packages`, в каждом имени подсвечено `flutter`, записи реестра видны

#### Scenario: Все вхождения подсвечены
- **WHEN** есть пакет `aa_aa`, и пользователь вводит `aa`
- **THEN** в имени `aa_aa` подсвечены оба вхождения `aa`, видимый текст имени — `aa_aa`

#### Scenario: Пустой запрос
- **WHEN** пользователь вводит три пробела
- **THEN** показаны все пакеты, счётчик — `4 packages`, кнопки `settings-legal-packages-clear` нет

#### Scenario: Ничего не найдено
- **WHEN** пользователь вводит `reqwest`
- **THEN** списка нет, показан `settings-legal-packages-empty` с `No packages match` и `No package name contains “reqwest”. The notices register above is not affected by search.`, счётчик — `0 of 4 packages`, записи реестра видны

#### Scenario: Очистка из пустого блока
- **WHEN** совпадений нет, и пользователь нажимает `settings-legal-packages-empty-clear`
- **THEN** поле пусто, показаны все пакеты, счётчик — `4 packages`

#### Scenario: Запрос не сохраняется и не пишется в журнал
- **WHEN** пользователь вводит `marker-query-7f3a`, уходит со страницы «Legal» и возвращается на неё
- **THEN** поле поиска пусто, ни одна запись журнала не содержит `marker-query-7f3a`, `shared_preferences` не содержат `marker-query-7f3a`

#### Scenario: Русский интерфейс
- **WHEN** app работает на русском, пакетов 21, и пользователь вводит `flutter`, совпадают 5
- **THEN** счётчик — `5 из 21 пакета`, имена пакетов не переведены

### Requirement: События журнала страницы «Legal»
Страница «Legal» SHALL писать события логгера `codelab_desktop.settings`:
- `legal.tab_selected` (`tab: privacy_policy | terms_of_use | license | third_party_notices`, `source: open | tab | link`), уровень `debug`;
- `legal.document_load_failed` (`tab`, `error_type` — имя типа исключения), уровень `warning`;
- `legal.licenses_collected` (`packages` — число пакетов, `failed` — был ли сбой реестра), уровень `info`;
- `legal.link_opened` (`target: tab | external`, `outcome: opened | failed | rejected_scheme`); переход по ссылке на вкладку пишется с `target: tab` и `outcome: opened`, исходы `failed` и `rejected_scheme` бывают только у `target: external`.

События НЕ SHALL содержать запрос поиска, число совпадений, путей, URL, текстов документов и текстов исключений (AGENTS.md §16; design.md, D11).

#### Scenario: Поиск не оставляет следов в журнале
- **WHEN** пользователь вводит и очищает запрос на вкладке «Third-party notices»
- **THEN** за это время журнал не получил ни одного события

### Requirement: Страница «Skills & extensions»: доступ и папка
Страница «Skills & extensions» SHALL показывать данные агента профиля текущего подключения, а без подключения — профиля по умолчанию. Доступ SHALL вычислять `resolveSettingsAccess` (spec client-agent-setup «Доступ к настройкам агента»), смена подключения SHALL перечитывать страницу (design.md change `add-app-skills-page`, D2).

Папкой SHALL быть папка сессии в фокусе, без неё — выбранный проект; смена папки сессии в фокусе SHALL перечитывать страницу. Без папки страница SHALL показывать `Open a project folder to see the context files, skills and prompt templates the agent uses there.` (ключ `skills-no-folder`) и НЕ SHALL читать файлы.

Для `EditableSettings` страница SHALL читать файлы на машине клиента функцией моста (spec client-agent-setup «Обзор расширений агента»), с конфигурацией, `CODELAB_HOME` и окружением агента этого профиля (окружение app, дополненное `env` stdio-профиля). Агенту страница НЕ SHALL отправлять запросов и команд, ACP НЕ SHALL меняться.

Для `RemoteReadOnly` и `NotManaged` страница НЕ SHALL читать локальные файлы и конфиг и НЕ SHALL показывать элементов записи (SETUP-2). Она SHALL показывать InfoBar уровня `warning` (ключ `skills-read-only`): `Read-only: this agent runs on <scheme://host:port>. Its skills, context files and prompt templates are read on that host: codelab-agent config check.` или `Skills are managed by <agentName>.` (решение Q1 (а) design.md).

Если конфиг агента не разбирается или нарушает схему, страница SHALL показывать проблемы загрузчика с путём ключа (ключ `skills-unreadable`) и НЕ SHALL читать файлы проекта и навыков и писать конфиг.

Для проекта вне `trusted_projects` (доверие — тем же расчётом, что у агента и `config check`, fail-closed) страница SHALL показывать InfoBar `skills-untrusted`: `This project is not in trusted_projects, so the agent does not read its skills and prompt templates. Your own skills and AGENTS.md files are shown.` и строку `Trust is set in trusted_projects of <файл пользовательского конфига>.`. Навыки и шаблоны проекта НЕ SHALL читаться и показываться.

#### Scenario: WebSocket-агент
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp`, а в папке проекта есть `.codelab/skills/review/SKILL.md`
- **THEN** страница показывает InfoBar `skills-read-only` с `wss://devbox:7420` без `/acp`, таблицы навыков и выключателей нет, файлы проекта и `$CODELAB_HOME` не читались

#### Scenario: Сторонний stdio-агент
- **WHEN** окно подключено к stdio-профилю с командой `python` и аргументами `-m other_agent`
- **THEN** страница показывает `Skills are managed by python.` и не читает файлов

#### Scenario: Недоверенный проект
- **WHEN** папка `/work/repo` не в `trusted_projects`, в ней есть `/work/repo/AGENTS.md` и `.codelab/skills/deploy/SKILL.md`, а в `$CODELAB_HOME/skills/notes/SKILL.md` — навык пользователя
- **THEN** страница показывает InfoBar `skills-untrusted`, цепочку с `AGENTS.md`, навык `notes` и не показывает навык `deploy` и шаблоны `.codelab/prompts`

#### Scenario: Без папки проекта
- **WHEN** проект не выбран и сессий нет
- **THEN** страница показывает `skills-no-folder`, разделов навыков и шаблонов нет, загрузчик не вызывался

#### Scenario: Битый конфиг
- **WHEN** `$CODELAB_HOME/config.yaml` не разбирается
- **THEN** страница показывает `skills-unreadable` с проблемой загрузчика, выключателей нет, файлы навыков не читались

#### Scenario: Смена профиля перечитывает страницу
- **WHEN** страница открыта со встроенным агентом, а окно переподключается к WebSocket-профилю
- **THEN** страница переходит в состояние только для чтения, результат прежней загрузки, пришедший позже, не применяется

### Requirement: Страница «Skills & extensions»: контекстные файлы и шаблоны
Раздел «Context files» SHALL показывать цепочку файлов инструкций, которую агент добавит в системный промпт сессии этой папки: файлы в порядке агента (пользовательский `$CODELAB_HOME/AGENTS.md`, затем от корня репозитория к папке), путь, размер файла и итог `<n> files · <size>`. Файл, который ядро усечёт или опустит по бюджету `tools.project_context.max_bytes`, SHALL иметь пометку `truncated to <size>` или `not included (budget)`; бюджет считает функция ядра, а не app. `CLAUDE.md`, использованный на уровне без `AGENTS.md`, SHALL иметь пометку `used because this folder has no AGENTS.md` (E-01; решение Q6 (а) design.md). Без файлов раздел SHALL показывать `No AGENTS.md files for this folder.`

Раздел «Prompt templates» SHALL показывать шаблоны команд, которые агент объявит сессии этой папки: команду `/<name>` с подсказкой аргументов, описание и файл-источник. Шаблон проекта, заменивший шаблон пользователя с тем же именем, SHALL показываться один раз, как у агента. Без шаблонов раздел SHALL показывать `No prompt templates.`

Оба раздела SHALL быть только для чтения. Тексты файлов НЕ SHALL показываться на странице и попадать в состояние Cubit и журнал. Исключение — описание шаблона без `description` во frontmatter: им SHALL служить первая строка тела, как в `available_commands_update` агента; она показывается как недоверенный текст и НЕ SHALL попадать в журнал. Разделы Hooks, Plugins, System prompt override и Read context files of other agents артборда НЕ SHALL показываться (design.md, D13).

#### Scenario: Цепочка от внешнего к ближнему
- **WHEN** `/repo` — корень git, есть `/repo/AGENTS.md` (4,8 КБ) и `/repo/packages/ui/AGENTS.md` (1,3 КБ), папка — `/repo/packages/ui`
- **THEN** раздел показывает две строки в порядке `AGENTS.md`, `packages/ui/AGENTS.md`, итог `2 files · 6.1 KB`, пометок усечения нет

#### Scenario: CLAUDE.md вместо AGENTS.md
- **WHEN** на уровне `/repo/packages/ui` нет `AGENTS.md`, но есть `CLAUDE.md`
- **THEN** строка показывает `packages/ui/CLAUDE.md` с пометкой `used because this folder has no AGENTS.md`

#### Scenario: Бюджет контекста
- **WHEN** `tools.project_context.max_bytes: 4096`, а суммарный размер файлов цепочки 6 КБ
- **THEN** строки, которые ядро усекает или опускает, имеют пометки `truncated to <size>` или `not included (budget)`, совпадающие с результатом `assembleProjectContext`

#### Scenario: Шаблоны проекта и пользователя
- **WHEN** доверенный проект содержит `.codelab/prompts/review-pr.md` с `argument-hint: <number>`, а `$CODELAB_HOME/prompts/` — `review-pr.md` и `explain.md`
- **THEN** раздел показывает `/review-pr <number>` с источником `.codelab/prompts/review-pr.md` и `/explain` с источником в `$CODELAB_HOME/prompts`; второй строки `/review-pr` нет

#### Scenario: Текст файла не утекает
- **WHEN** `AGENTS.md` и тело шаблона содержат маркер `sk-test-leak-0123456789`
- **THEN** ни страница, ни состояние Cubit, ни журнал не содержат маркера

### Requirement: Страница «Skills & extensions»: навыки
Раздел «Skills» SHALL показывать навыки, которые агент загрузит в сессию этой папки, по правилам агента (корни, доверие, перекрытие, мягкая проверка, `skills.disabled`, `skills.max_skills`; spec agent-skills change `add-agent-skills`), и навыки, выключенные `skills.disabled`. Таблица (ключ строки `skills-row-<name>`) SHALL содержать:
- имя и описание;
- «Invoke as» — `/skill:<name>` и `argument-hint`, если есть; для навыка с `user-invocable: false` — `Model only`;
- «Source» — корень навыка: путь от папки проекта для корней проекта; для корней пользователя — путь с `~` вместо домашнего каталога (`~/.codelab/skills` при `CODELAB_HOME` по умолчанию, `~/.agents/skills`), вне домашнего каталога — абсолютный; элемент `skills.extra_roots` как записан с пометкой `(extra root)`;
- выключатель «Enabled» (ключ `skills-toggle-<name>`);
- тег `Overrides <user|project|extra> skill` (или `Overrides another skill` для того же уровня), если навык перекрыл одноимённый навык другого корня;
- тег `Command only` — навык вызывается командой, но модели недоступен (`disable-model-invocation: true` или запрет `skill:<name>` правилами разрешений);
- тег `<n> warning(s)` — предупреждения загрузки этого навыка с текстами в подсказке.

Ошибки и предупреждения, не относящиеся к показанному навыку (пропущенный навык, корень вне области, перекрытый навык, предел числа навыков), SHALL показываться InfoBar `skills-warnings` уровня `warning` с числом и фиксированными текстами диагностик агента и путями. Диагностики уровня `info` НЕ SHALL показываться, как в `config check`.

Под таблицей SHALL быть подпись порядка поиска по фактическим корням: `.codelab/skills`, затем `.agents/skills` от этой папки до корня репозитория; затем `$CODELAB_HOME/skills`, `~/.agents/skills`; extra roots — последними; ближний перекрывает дальний; `The list is fixed when a session opens: new and changed skills apply to new sessions.`

Если `skills.enabled: false` в конфигурации папки, раздел SHALL показывать `Skills are switched off: skills.enabled is false in <файл>.` и не читать навыки. Если навыки не прочитаны за 5 с или чтение завершилось исключением, раздел SHALL показывать `Skills were not read within 5 s.` или `Skills could not be read (<имя типа>).`, остальные разделы SHALL показываться.

Тексты из файлов навыков (имя, описание, подсказка аргументов) SHALL показываться как простой текст с видимыми управляющими, невидимыми и bidi-символами, без markdown и ссылок. Тело `SKILL.md` НЕ SHALL показываться и попадать в состояние Cubit и журнал.

#### Scenario: Перекрытие навыка пользователя
- **WHEN** доверенный проект содержит `.codelab/skills/release-notes/SKILL.md`, а `~/.agents/skills/release-notes/SKILL.md` — навык с тем же именем
- **THEN** одна строка `release-notes` с источником `.codelab/skills` и тегом `Overrides user skill`; InfoBar `skills-warnings` называет перекрытый `~/.agents/skills/release-notes/SKILL.md`

#### Scenario: Навык только для команды
- **WHEN** у навыка `deploy-check` в frontmatter `disable-model-invocation: true`
- **THEN** строка имеет тег `Command only` и «Invoke as» `/skill:deploy-check`

#### Scenario: Предупреждение загрузки
- **WHEN** у навыка в каталоге `pdf-tools` поле `name: pdf_tools` не совпадает с именем каталога
- **THEN** строка `pdf_tools` загружена и имеет тег `1 warning` с текстом `the skill name differs from its directory name; the name from the frontmatter is used`

#### Scenario: Выключенный навык виден
- **WHEN** `skills.disabled: [flutter-golden]` в `$CODELAB_HOME/config.yaml`, а навык `flutter-golden` есть в `.codelab/skills` доверенного проекта
- **THEN** строка `flutter-golden` показана с выключенным «Enabled», тега `Command only` нет

#### Scenario: Навыки выключены конфигом
- **WHEN** `skills.enabled: false` в `.codelab/config.local.yaml` доверенного проекта
- **THEN** раздел показывает `Skills are switched off: skills.enabled is false in .codelab/config.local.yaml.`, таблицы нет, остальные разделы показаны

#### Scenario: Невидимые символы в описании
- **WHEN** описание навыка содержит `U+202E`
- **THEN** ячейка показывает символ видимой escape-последовательностью, а не применяет его

#### Scenario: Тело навыка не утекает
- **WHEN** тело `SKILL.md` содержит маркер `sk-test-leak-0123456789`
- **THEN** ни страница, ни состояние Cubit, ни журнал не содержат маркера

### Requirement: Страница «Skills & extensions»: запись и применение
Выключатель «Enabled» SHALL писать `skills.disabled`, а переключатель согласия на каталог навыков другого агента (ключ `skills-consent-<kind>`) — `skills.extra_roots` по правилам моста (spec client-agent-setup «Правила записи skills.disabled и skills.extra_roots») через `AgentConfigStore.apply`. Других ключей страница НЕ SHALL писать.

Переключатели согласия SHALL показываться для каталогов фиксированного списка — `.claude/skills` в папке проекта и `~/.claude/skills` (решение Q3 (а) design.md), — только если каталог существует. Подпись SHALL называть число найденных подкаталогов навыков и область действия согласия (`in every trusted project` для относительного элемента в слое `user`), а также говорить, что `.agents/skills` доверенного проекта читается без отдельного согласия.

Если запись не может подействовать, элемент SHALL быть неактивен с подсказкой причины: `Set in <файл>; edit that file.`, `Disabled by the project config (<файл>).`, `Trust this project to read .claude/skills.`.

Пока идёт запись, повторные действия SHALL игнорироваться. `ConfigConflict` SHALL давать баннер `skills-banner` и перечитывание без автоповтора (SETUP-6); `ConfigRejected` — баннер с проблемами загрузчика, файл не изменён. После `ConfigSaved` страница SHALL перечитываться и показывать баннер `Saved. New sessions use it; open sessions keep their skills.`; подсказки «Restart agent» нет (design.md, D9).

«Reload» (ключ `skills-reload`) SHALL перечитывать конфиг и файлы. Агенту «Reload» НЕ SHALL отправлять команд.

#### Scenario: Выключение навыка
- **WHEN** `skills.disabled` нигде не задан, и пользователь выключает «Enabled» у `code-review`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `skills.disabled: [code-review]`, страница показывает строку выключенной и баннер `Saved. New sessions use it; open sessions keep their skills.`, идущая сессия не получает запросов

#### Scenario: Список задан в config.local.yaml
- **WHEN** `skills.disabled: [a]` задан в `.codelab/config.local.yaml` доверенного проекта, и пользователь выключает `b`
- **THEN** `.codelab/config.local.yaml` содержит `skills.disabled: [a, b]`, `$CODELAB_HOME/config.yaml` не изменён

#### Scenario: Ключ в файле --config
- **WHEN** stdio-профиль запускает `codelab-agent serve --stdio --config /etc/team.yaml`, а `skills.disabled` задан в `/etc/team.yaml`
- **THEN** выключатели неактивны с подсказкой `Set in /etc/team.yaml; edit that file.`, запись не выполняется

#### Scenario: Выключено недоверенным проектом
- **WHEN** `.codelab/config.yaml` недоверенного проекта задаёт `skills.disabled: [notes]`, а `notes` — навык пользователя
- **THEN** выключатель `notes` неактивен с подсказкой `Disabled by the project config (.codelab/config.yaml).`

#### Scenario: Согласие на .claude/skills
- **WHEN** доверенный проект содержит `.claude/skills/` с тремя каталогами навыков, `skills.extra_roots` нигде не задан, и пользователь включает переключатель согласия
- **THEN** `$CODELAB_HOME/config.yaml` содержит `skills.extra_roots: [.claude/skills]`, после перечитывания три навыка показаны с источником `.claude/skills (extra root)`, `.codelab/config.yaml` не изменён

#### Scenario: Согласие в недоверенном проекте
- **WHEN** проект недоверенный и содержит `.claude/skills/`
- **THEN** переключатель согласия неактивен с подсказкой `Trust this project to read .claude/skills.`

#### Scenario: Конфликт записи
- **WHEN** между открытием страницы и выключением навыка CLI меняет `$CODELAB_HOME/config.yaml`
- **THEN** страница показывает баннер `skills-banner` о конфликте и перечитывает снимок, правка CLI в файле сохранена, повторной записи нет

#### Scenario: Двойное нажатие
- **WHEN** пользователь дважды быстро переключает «Enabled» одного навыка во время записи
- **THEN** выполняется одна запись

### Requirement: Страница «Skills & extensions»: открытие папок
«Open .codelab folder» (ключ `skills-open-codelab`) SHALL открывать в файловом менеджере ОС `<папка проекта>/.codelab`, если каталог существует, иначе `$CODELAB_HOME` профиля; подсказка кнопки SHALL называть путь (решение Q4 (а) design.md). «Open» строки файла контекста, навыка или шаблона SHALL открывать каталог, где лежит файл (решение Q5 (а)). Путь SHALL браться только из показанных страницей данных.

Открытие SHALL идти через порт платформы app, принимающий только абсолютный путь существующего каталога. Файлы НЕ SHALL открываться и запускаться. Отказ платформы SHALL давать баннер `Could not open <путь>.` и событие без пути.

#### Scenario: Открытие папки проекта
- **WHEN** в папке проекта есть `.codelab/`, и пользователь нажимает «Open .codelab folder»
- **THEN** порт получает абсолютный путь `<папка проекта>/.codelab`

#### Scenario: Open строки навыка
- **WHEN** пользователь нажимает «Open» у навыка из `~/.agents/skills/pdf-tools/SKILL.md`
- **THEN** порт получает каталог `~/.agents/skills/pdf-tools` в абсолютной форме, а не путь `SKILL.md`

#### Scenario: Отказ платформы
- **WHEN** порт возвращает `failed`
- **THEN** страница показывает `Could not open <путь>.`, журнал содержит `skills_settings.open_failed` без пути

### Requirement: События журнала страницы Skills & extensions
Страница SHALL писать в журнал логгера `codelab_desktop.settings` события `skills_settings.loaded`, `skills_settings.read_only`, `skills_settings.unreadable`, `skills_settings.phase_failed`, `skills_settings.skill_toggled`, `skills_settings.root_consent`, `skills_settings.save_failed`, `skills_settings.load_discarded`, `skills_settings.open_failed` с видами, числами, именем навыка и слоем записи (design.md change `add-app-skills-page`, D10).

События НЕ SHALL содержать путей, описаний и тел навыков, текстов `AGENTS.md` и шаблонов, текстов диагностик и `toString()` исключений (только имя типа).

#### Scenario: События без содержимого
- **WHEN** пользователь открывает страницу, выключает навык `code-review`, а тело навыка и `AGENTS.md` содержат маркер `sk-test-leak-0123456789`
- **THEN** журнал содержит `skills_settings.loaded` с числами и `skills_settings.skill_toggled` с `name: code-review` и `layer: user`, и не содержит маркера и путей файлов

