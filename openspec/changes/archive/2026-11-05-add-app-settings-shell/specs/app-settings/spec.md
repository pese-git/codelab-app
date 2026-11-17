## ADDED Requirements

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
- метку «Current» — только у профиля, к которому workspace сейчас подключён (принятый профиль в `Connected` или `Reconnecting`). После сбоя и во время новой попытки «Current» НЕ SHALL быть ни у одной строки, кроме случая отказа до обращения к workspace при живом соединении;
- бейдж попытки (ключ `connection-profile-status-<id>`): `Connecting…`, `Connected` или `Failed` — у строки профиля последней попытки (`ConnectionCommands.attemptProfile`), без текста ошибки;
- метки «Default», «Current» и «Not tested»;
- результат последней проверки в этом открытии страницы (ключ `connection-profile-probe-<id>`, текст — по требованию «Диалог «Add connection profile»», раздел «Проверка»).

Строка SHALL предлагать действия «Test connection», «Connect», «Rename» и «Remove». У встроенного агента НЕ SHALL быть «Test connection», «Rename» и «Remove». «Remove» SHALL быть недоступна у профиля текущего подключения, с подсказкой «Disconnect first».

У строки с меткой «Current» (принятое соединение в `Connected` или `Reconnecting`) кнопки «Connect» НЕ SHALL быть: переподключение вручную — «Restart agent» блока «Behavior» (решение пользователя 2026-11-05; design.md, D5, D9). Это касается и встроенного агента. У остальных строк «Connect» SHALL оставаться; во время попытки (`Connecting…`) и после сбоя (`Failed`) «Current» нет, и «Connect» SHALL быть во всех строках.

Радиокнопка строки SHALL выбирать профиль по умолчанию (`shared_preferences` `codelab.connection.default_profile`). Профиль по умолчанию используется при старте и кнопкой «Connect» до первого подключения окна. «Connect» SHALL подключать текущее окно к профилю строки и НЕ SHALL менять профиль по умолчанию.

Без сохранённого выбора профилем по умолчанию SHALL быть встроенный агент. `default` — второе имя встроенного агента (design.md, D21): запись с id `default` в `profiles.json` SHALL игнорироваться и НЕ SHALL показываться строкой профиля.

Если такая запись есть, страница SHALL показывать InfoBar уровня `warning` (ключ `connection-profiles-ignored-default`) с текстом `Profile "default" in profiles.json is ignored: default is the built-in agent. Remove it with codelab profiles remove default.` и кнопкой «Remove». Кнопка после подтверждения удаляет запись через `ProfileStore.remove('default')`. Команду, аргументы, URL и `env` записи InfoBar НЕ SHALL показывать. Без действия пользователя файл НЕ SHALL перезаписываться. Сохранённый id, которого нет в списке, SHALL удаляться, и профилем по умолчанию SHALL становиться встроенный агент.

Если `profiles.json` не разбирается или имеет неизвестную версию, страница SHALL показывать строку встроенного агента и ошибку `Cannot read <path>: <причина>. Fix or remove the file; CodeLab will not overwrite it.`. Если `CODELAB_HOME` недопустим, страница SHALL показывать строку встроенного агента и причину ошибки `CODELAB_HOME`. В обоих случаях:
- «Add profile», «Rename» и «Remove» SHALL быть недоступны;
- файл НЕ SHALL перезаписываться;
- блок «Behavior» («Connect on start», «Restart agent») SHALL оставаться видимым и рабочим: он не зависит от `profiles.json`.

Предупреждение о проигнорированной записи `default` SHALL писаться в журнал один раз за жизнь страницы, а не при каждом перечитывании файла.

Строка WebSocket-профиля SHALL показывать источник токена:
- `No token`;
- `From $<NAME>`, с пометкой `<NAME> is not set in CodeLab's environment.`, если переменной нет в окружении app;
- `unrecognized token reference (not supported in this version)` для ссылки не вида `env:`. Значение ссылки НЕ SHALL выводиться ни в UI, ни в журнал, ни в диагностику: вместо имени секрета там может стоять сам токен. «Connect» с таким профилем SHALL подключаться без токена и писать в диагностику `The token-reference format of profile <id> is not supported in this version; connecting without a token.`.

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

#### Scenario: Connect не меняет профиль по умолчанию
- **WHEN** профиль по умолчанию — встроенный агент, и пользователь нажимает «Connect» в строке `dev`
- **THEN** окно подключается к `dev`, строка `dev` получает метку «Current», метка «Default» остаётся у встроенного агента

#### Scenario: Неподдерживаемая ссылка на токен
- **WHEN** `profiles.json` содержит WebSocket-профиль `devbox` с `tokenRef: sk-test-leak-0123456789`
- **THEN** строка показывает `unrecognized token reference (not supported in this version)`; «Connect» подключается без токена, а диагностика содержит предупреждение с `devbox`. Ни страница, ни журнал, ни диагностика (в том числе после `SecretRedactor`) не содержат `sk-test-leak-0123456789`

#### Scenario: Заголовок строки
- **WHEN** `profiles.json` содержит профиль `py` с `label` `stdio:python -m "codelab agent" --stdio`, профиль `ws` с пустым `label` и профиль `dev` с `label` длиннее строки
- **THEN** заголовки — `py`, `ws` и `label` профиля `dev` с многоточием и полным текстом в подсказке; вторая строка `py` — `python`, без аргументов

#### Scenario: Connect скрыт у текущего профиля
- **WHEN** `profiles.json` содержит профили `dev` и `plain`, пользователь нажимает «Connect» в строке `dev`, и подключение принято
- **THEN** у `dev` «Current» и `Connected`, кнопки `connection-profile-connect-dev` нет, а у `plain` и встроенного агента «Connect» есть

#### Scenario: Connect при переподключении и после сбоя
- **WHEN** окно подключено к `dev`, соединение переходит в `Reconnecting`, затем переподключение не удаётся
- **THEN** в `Reconnecting` у `dev` «Current» и бейдж `Connecting…`, кнопки `connection-profile-connect-dev` нет, а у других строк «Connect» есть; после сбоя «Current» нет ни у кого, у `dev` бейдж `Failed`, а «Connect» есть во всех строках

#### Scenario: Бейдж состояния текущего профиля
- **WHEN** окно ещё ни к чему не подключалось, пользователь нажимает «Connect» в строке `dev`, и подключение сначала идёт, потом завершается ошибкой
- **THEN** бейдж `connection-profile-status-dev` показывает `Connecting…`, затем `Failed`, без текста ошибки; у других строк бейджа нет, «Current» нет ни у кого

#### Scenario: Бейдж после принятого подключения
- **WHEN** окно подключено к `a` («Current» и `Connected` у `a`), и пользователь нажимает «Connect» в строке `b`, которая подключается успешно
- **THEN** пока идёт попытка, бейдж `Connecting…` стоит у `b`, а «Current» нет ни у кого; после успеха «Current» и `Connected` у `b`, у `a` ни метки, ни бейджа

#### Scenario: Недопустимый CODELAB_HOME
- **WHEN** app запущено с `CODELAB_HOME=~bob/cl`
- **THEN** страница показывает встроенного агента и причину ошибки `CODELAB_HOME`, «Add profile» недоступна, ни один файл не создан, а «Connect on start» и «Restart agent» видны

#### Scenario: Битый profiles.json
- **WHEN** `profiles.json` содержит `{"version": 2, "profiles": []}`
- **THEN** страница показывает встроенного агента и ошибку чтения, «Add profile» недоступна, а содержимое файла после закрытия страницы прежнее

#### Scenario: Текущий профиль не удаляется
- **WHEN** окно подключено к профилю `dev`
- **THEN** «Remove» в строке `dev` недоступна с подсказкой «Disconnect first»

### Requirement: Блок «Behavior» страницы «Connection»
Блок «Behavior» SHALL содержать две строки.

**«Connect on start».** Переключатель хранится в `shared_preferences` `codelab.connection.connect_on_start`, по умолчанию выключен. При включённом переключателе app SHALL после первого кадра и после восстановления проекта один раз подключаться к профилю по умолчанию. Сбой такого подключения SHALL отображаться как сбой обычного подключения (`ConnectionFailed` и баннер) без повторов. При выключенном переключателе app SHALL открываться без подключения.

**«Restart agent».** Строка SHALL вызывать переподключение (`ClientWorkspace.reconnect`) профиля последнего принятого подключения — цели `ConnectionCommands.restartTarget`; до первого принятого подключения целью SHALL быть последний выбранный профиль. Это то же действие, что «Restart agent» диалога переноса секретов (design.md, D9). Описание строки SHALL называть цель: `Reconnects <title> and reloads open sessions. A running turn is interrupted; queued prompts stay.` Для профиля WebSocket строка SHALL называться «Reconnect». Её описание НЕ SHALL обещать отмену хода (`session/cancel`); оно SHALL сообщать, что идущий ход прерывается, открытые сессии загружаются заново, а очередь промптов сохраняется. Подпись («Restart agent» или «Reconnect») и доступность строки SHALL считаться по цели. Строка SHALL быть недоступна без цели и во время подключения или переподключения.

До первого принятого подключения профиль окна SHALL быть последним выбранным профилем: экран подключения показывает его, а Reconnect работает с ним. После первого принятого подключения профиль окна SHALL меняться только после того, как workspace принял новую попытку (`Connected` этой попытки).

Connect к другому профилю SHALL разрывать текущее соединение до проверки нового (поведение kit `ClientWorkspace.connect`). Единственное исключение — попытка, отклонённая до обращения к workspace (пустая команда stdio, нет папки проекта). Если в этот момент workspace подключён:
- статус окна SHALL оставаться `connected`, «Current» — у живого профиля;
- причина SHALL идти только в диагностику, `connectionMessage` НЕ SHALL меняться, а баннер ошибки НЕ SHALL появляться;
- последующая потеря соединения SHALL давать `lost`.

Отказ до обращения к workspace НЕ SHALL вытеснять попытку, уже переданную в kit: её исход SHALL применяться как обычно. Вытесненная попытка «Connect» НЕ SHALL менять ни профиль окна, ни статус, ни соединение, даже если завершилась позже более новой (номер попытки проверяется после каждого ожидания). Диагностика подключения stdio SHALL называть только команду, без аргументов.

В CommandBar страницы SHALL быть только «Add profile»; второй кнопки «Restart agent» там НЕ SHALL быть.

#### Scenario: Подключение при старте
- **WHEN** `codelab.connection.connect_on_start` — `true`, профиль по умолчанию — scripted stdio-агент, и app запускается
- **THEN** после первого кадра app подключается к этому агенту ровно один раз

#### Scenario: Без подключения при старте
- **WHEN** ключа `codelab.connection.connect_on_start` нет, и app запускается
- **THEN** рабочее место показывает экран подключения, процесс агента не запущен

#### Scenario: Restart agent переподключает тем же профилем
- **WHEN** окно подключено к встроенному агенту с открытой сессией, и пользователь нажимает «Restart agent»
- **THEN** прежний встроенный агент освобождён, новый подключён тем же профилем, а сессия загружена через `session/load`

#### Scenario: Restart agent после неудачного Connect
- **WHEN** workspace подключён к встроенному агенту, пользователь нажимает «Connect» в строке `dev`, подключение к `dev` завершается `ConnectionFailed`, и пользователь нажимает «Restart agent»
- **THEN** переподключается встроенный агент — профиль последнего принятого подключения, — а не `dev`

#### Scenario: Connect к B отклонён до обращения к workspace при живом A
- **WHEN** окно подключено к профилю `a`, пользователь нажимает «Connect» в строке stdio-профиля `b` с пустой командой, и попытка отклонена до обращения к workspace
- **THEN** соединение с `a` живо, «Current» и бейдж `Connected` остаются у `a`, подпись и цель «Restart agent» — по `a`; причина отказа `b` есть только в диагностике, сообщение рабочего места не изменилось, баннера ошибки нет

#### Scenario: Connect к несуществующему бинарю разрывает встроенного агента
- **WHEN** окно подключено к встроенному агенту, пользователь нажимает «Connect» в строке stdio-профиля `dart` с несуществующим бинарём, затем — «Restart agent»
- **THEN** после неудачи у встроенного агента нет ни «Current», ни бейджа, у `dart` — бейдж `Failed`; «Restart agent» переподключает встроенного агента, после чего «Current» и `Connected` — у встроенного агента

#### Scenario: Отказ до kit не вытесняет попытку в kit
- **WHEN** пользователь нажимает «Connect» в строке WebSocket-профиля `a` и рукопожатие ещё висит, затем нажимает «Connect» в строке stdio-профиля `b`, чья папка проекта исчезла, после чего `a` подключается
- **THEN** статус окна — `connected`, «Current» у `a`, а отказ `b` записан только в диагностику

#### Scenario: Первый Connect не удался
- **WHEN** окно ещё ни к чему не подключалось, пользователь нажимает «Connect» в строке `dev`, и попытка не удаётся
- **THEN** экран подключения показывает профиль `dev`, а Reconnect повторяет подключение к `dev`

#### Scenario: Отказ до подключения при живом соединении
- **WHEN** окно подключено к `a`, и пользователь нажимает «Connect» в строке stdio-профиля, чья папка проекта исчезла
- **THEN** статус окна остаётся `connected`, причина видна только в диагностике, сообщение рабочего места не изменилось, а после потери соединения с `a` статус — `lost`

#### Scenario: Поздняя попытка Connect
- **WHEN** пользователь нажимает «Connect» в строке `slow`, затем, пока `slow` подключается, — «Connect» в строке `dev`, и `dev` подключается раньше, чем завершается `slow`
- **THEN** окно остаётся подключённым к `dev`, метка «Current» у `dev`, а поздний исход `slow` не меняет ни соединение, ни статус

#### Scenario: Подпись для WebSocket
- **WHEN** текущий профиль — WebSocket
- **THEN** строка называется «Reconnect», а её описание не содержит слов о перезапуске процесса агента

### Requirement: Предупреждение и справка для удалённого агента
Пока текущий профиль — WebSocket в состоянии `Connected`, страница «Connection» SHALL показывать InfoBar уровня `warning`: `Read-only: this agent runs on <scheme://host:port>. Change providers and MCP on that host: codelab provider add, codelab mcp add, codelab config set.`. Путь, query и userinfo URL в этом тексте НЕ SHALL показываться. Профили клиента при этом SHALL оставаться редактируемыми.

Страница SHALL содержать свёрнутый по умолчанию Expander «Join a session started in the CLI» со статичной справкой о запуске `codelab-agent serve --ws` и выборе того же WebSocket-профиля в app и CLI. Справка НЕ SHALL описывать блокировку сессии, режим только для чтения и «Fork»: lease не реализован (design.md, D10).

#### Scenario: InfoBar при WebSocket
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp?x=1`
- **THEN** InfoBar содержит `wss://devbox:7420`, не содержит `/acp` и `x=1`, а «Add profile» доступна

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
- Предупреждение под полем для `ws://` к нелокальному хосту: с токеном («From environment variable») — `ws:// to another machine: the token is sent unencrypted.`, без токена — `ws:// to another machine: traffic is sent unencrypted.`.
- «Token» в этой версии SHALL предлагать ровно два варианта (design.md, D13):
  - «No token»;
  - «From environment variable» — поле имени переменной, по умолчанию `CODELAB_AGENT_TOKEN`, в профиль идёт `tokenRef: env:<NAME>`.
- Значение токена диалог НЕ SHALL принимать, читать при сохранении и показывать.
- Под полем SHALL показываться подсказка `CodeLab reads the token from this environment variable when it connects. Token values are not saved in profiles.json.` и строка `Apps opened from Finder do not see variables set in your shell profile.`.
- Если переменная не задана в окружении app, диалог SHALL показывать `<NAME> is not set in CodeLab's environment.` один раз — подсказкой под полем имени переменной. Других предупреждений о незаданной переменной, в том числе в блоке проверки до и после «Test connection», диалог НЕ SHALL показывать (решение пользователя 2026-11-05; design.md, D12, D13). Проверка с незаданной переменной SHALL выполняться.
- Вариантов хранилища секретов и обещаний о них диалог НЕ SHALL показывать.

**Проверка.** «Test connection» SHALL выполнять `ProfileProbe` и показывать исход (решение пользователя 2026-11-05, design.md D12):
- `Reachable · <N> ms · <name> <version>` — имя и версия из `agentInfo` ответа `initialize`;
- `Command not found: <command>` — значение поля «Command» профиля, без аргументов и `env`;
- `Unreachable: connection refused`, `Unreachable: host not found`, `Unreachable: TLS handshake failed` или `Unreachable: HTTP <status>` по типизированной причине `UnreachableReason` исхода (`connectionRefused`, `hostNotFound`, `tlsFailed`, `httpStatus` со `statusCode`), а при причине `unknown` — просто `Unreachable`;
- `Unauthorized: the agent rejected the token`, если токен действительно отправлен: у профиля `tokenRef: env:<NAME>`, и переменная `<NAME>` задана в окружении app. Во всех остальных случаях («No token», переменная не задана, неподдерживаемая ссылка) — `Unauthorized: the agent requires a token`: текст описывает то, что реально ушло на сервер;
- `Timed out`;
- `Not an ACP agent`.

Детали текста SHALL браться только из типизированных данных исхода и полей профиля. Текст исключения и поле `message` исхода `Unreachable` НЕ SHALL показываться в UI: `message` после `describeFailure` предназначен только для журнала и диагностики. Тот же текст SHALL показываться в строке профиля на странице «Connection» (ключ `connection-profile-probe-<id>`).

Повторная проверка и закрытие диалога SHALL отменять идущую проверку, а её поздний исход НЕ SHALL менять диалог.

**Подтверждение `ws://` перед проверкой** (решение пользователя 2026-11-05). Если URL — `ws://` к хосту вне `localhost`, `127.0.0.0/8` и `::1`, а токен — «From environment variable» (задана переменная или нет), «Test connection» SHALL сначала показывать InfoBar «Unencrypted connection» с текстом `The token for <scheme://host:port> will travel in clear text. Use wss:// if the host supports it.` и кнопкой «Test anyway» (ключ `add-profile-test-anyway`). До «Test anyway» проверка НЕ SHALL начинаться: транспорт не открывается, токен не отправляется. С «No token» или к локальному хосту проверка SHALL начинаться сразу.

**Сохранение.** Кнопка SHALL называться «Save» после успешной проверки и «Save without test» иначе; без успешной проверки строка профиля получает метку «Not tested». Флажок «Use by default» (по умолчанию выключен) делает профиль профилем по умолчанию; текущее подключение диалог НЕ SHALL менять.

Нажатие «Save» SHALL переводить диалог в состояние записи до чтения списка существующих id; повторное нажатие в этом состоянии НЕ SHALL давать второй записи. Пока идёт запись, «Cancel» SHALL быть неактивна, а Esc и закрытие диалога SHALL быть заблокированы. «Save anyway» SHALL перед записью заново читать список id: если id уже занят, диалог SHALL показывать ошибку `idTaken` у поля id, а существующий профиль НЕ SHALL перезаписываться.

**Подтверждение `ws://` к нелокальному хосту.** Сохранение профиля с `ws://` к хосту вне `localhost`, `127.0.0.0/8` и `::1` SHALL всегда требовать подтверждения — и с токеном, и без него (решение пользователя 2026-11-05). Подтверждение — панель InfoBar уровня `warning` внутри диалога «Add connection profile», как в артборде `AddProfile`, с заголовком «Unencrypted connection» и кнопкой «Save anyway» (ключ `add-profile-save-anyway`); текст:
- с токеном — `The token for <scheme://host:port> will travel in clear text. Use wss:// if the host supports it.`;
- без токена — `Prompts and files sent to <scheme://host:port> will travel in clear text. Use wss:// if the host supports it.`.

В адресе SHALL показываться только `scheme://host:port`; путь, query и userinfo URL НЕ SHALL показываться. Отдельной кнопки отказа у панели нет: отказ — правка черновика или «Cancel»; без «Save anyway» запись НЕ SHALL происходить.

Подтверждение SHALL действовать для пары «URL, выбор токена» черновика: после «Test anyway» перед «Save» и после «Save anyway» перед «Test connection» повторного подтверждения НЕ SHALL быть. Изменение URL, варианта токена или имени переменной SHALL сбрасывать подтверждение, даже если значение затем возвращено к прежнему; «Add another» SHALL начинать черновик без подтверждения.

«Test connection» и «Connect» в строке сохранённого профиля на странице «Connection» подтверждения `ws://` НЕ SHALL спрашивать (решение пользователя 2026-11-05).

После сохранения диалог SHALL показывать экран «Profile saved» с id, текстом `The current connection is unchanged. Use Connect in the profile row to switch now.` и кнопками «Done» и «Add another». «Cancel» и Esc без сохранения SHALL закрывать диалог без записи в `profiles.json` и `shared_preferences`.

После закрытия диалога страница «Connection» SHALL показывать все профили, сохранённые за жизнь диалога (в том числе сохранённые до «Add another»), каждый со своим исходом проверки из диалога или меткой «Not tested». Исход проверки в строке профиля SHALL сбрасываться, если при перечитывании `profiles.json` профиль с тем же id изменился в полях, значимых для подключения (тип, команда, аргументы, `env`, папка запуска, URL, ссылка на токен); изменение `label` («Rename») исход НЕ SHALL сбрасывать. Исход, пришедший для профиля, который за время проверки изменился в этих полях, SHALL отбрасываться.

#### Scenario: Ошибки id
- **WHEN** пользователь вводит имя `Embedded`, затем `Default`, затем имя, чей id совпадает с существующим `dev`, затем правит id на `a:b`
- **THEN** у поля по очереди показываются `"embedded" is reserved for the built-in agent.`, `"default" is reserved for the built-in agent.`, `A profile with id "dev" already exists.` и ошибка допустимых символов; «Save» недоступна

#### Scenario: Секретоподобный ключ окружения
- **WHEN** в «Environment» введена строка `OPENAI_API_KEY=sk-x`
- **THEN** у поля показано `OPENAI_API_KEY looks like a secret. Set it in the system environment or reference it from the agent config as ${secret:…}.`, сохранение недоступно, а `sk-x` не появляется ни в логе, ни в тексте ошибки

#### Scenario: Варианты токена
- **WHEN** выбран тип WebSocket
- **THEN** вариантов токена ровно два — «No token» и «From environment variable», поля для значения токена нет

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
- **WHEN** `profiles.json` содержит профиль `remote` с `ws://10.0.0.5:8765` и `tokenRef: env:DEVBOX_TOKEN`, и пользователь нажимает «Test connection», затем «Connect» в строке `remote`
- **THEN** проверка и подключение начинаются без панели «Unencrypted connection»

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

«Remove» SHALL спрашивать подтверждение «Remove profile <title>?» (`title` — по правилу заголовка строки; заголовок диалога — 20 px semibold, как у «Add connection profile», design.md D14, D16) и удалять только запись из `profiles.json`; переменные окружения и другие хранилища app НЕ SHALL трогать. Удаление профиля по умолчанию SHALL сбрасывать `codelab.connection.default_profile`. Запрет удаления встроенного профиля и профиля текущего подключения SHALL проверяться перед вызовом `ProfileStore.remove`, а не только недоступностью кнопки.

#### Scenario: Переименование
- **WHEN** пользователь переименовывает `devbox` в «Build box»
- **THEN** `profiles.json` содержит профиль с id `devbox` и `label` «Build box», а `codelab -a devbox` по-прежнему находит его

#### Scenario: Удаление профиля
- **WHEN** пользователь удаляет профиль `devbox` по умолчанию с `tokenRef: env:DEVBOX_TOKEN`
- **THEN** `profiles.json` больше не содержит `devbox`, ключ `codelab.connection.default_profile` удалён, а профилем по умолчанию становится встроенный агент

### Requirement: События журнала настроек без секретов
Экран настроек и страница «Connection» SHALL писать в журнал приложения структурные события с `profile_id` и номером проверки `operation_id` (design.md, D17):
- `settings.opened`, `settings.page_selected`, `settings.closed`;
- `connection_profile.saved`, `connection_profile.renamed`, `connection_profile.removed`, `connection_profile.save_failed`;
- `connection_profile.probe_started`, `connection_profile.probe_finished`, `connection_profile.probe_discarded` — все три с `profile_id`: на странице — id профиля строки, в диалоге — id черновика (поля нет, только если id черновика пуст);
- `connection_profile.default_changed`, `connection_profile.unreadable`, `connection_profile.token_ref_unsupported`, `connection_profile.default_ignored`, `connection_profile.default_removed`;
- `connection.connect_on_start`.

`connection_profile.save_failed` SHALL содержать поле `stage`: `profile` — не записан профиль в `profiles.json`, `default` — профиль записан, но не записан ключ «Use by default» `codelab.connection.default_profile`.

События и тексты ошибок на экране НЕ SHALL содержать:
- значения и имена переменных токена и значения ссылок на токен не вида `env:`;
- аргументы и значения `env` stdio-профиля;
- путь, query и userinfo URL;
- текст `toString()` исключений — только имя типа.

#### Scenario: Маркер секрета не утекает
- **WHEN** app запущено с `DEVBOX_TOKEN=sk-test-leak-0123456789`, пользователь проверяет и сохраняет WebSocket-профиль с `env:DEVBOX_TOKEN` и URL `wss://host:1/acp?t=sk-test-leak-0123456789`, а запись профиля завершается исключением, чей `toString()` содержит тот же маркер
- **THEN** журнал содержит `connection_profile.save_failed` с именем типа исключения, а ни журнал, ни диалог не содержат `sk-test-leak-0123456789`, `/acp` и `t=`
