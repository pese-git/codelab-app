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
2. профили `ProfileStore` из `$CODELAB_HOME/profiles.json` (`CODELAB_HOME` по умолчанию `~/.codelab`) в порядке файла. Это тот же файл и тот же `JsonFileProfileStore`, что у CLI.

Строка профиля SHALL показывать:
- `label`;
- тип и сводку: команду или `scheme://host:port`, без аргументов, `env` и значения токена;
- метки «Default», «Current» и «Not tested»;
- результат последней проверки в этом открытии страницы.

Строка SHALL предлагать действия «Test connection», «Connect», «Rename» и «Remove». У встроенного агента НЕ SHALL быть «Test connection», «Rename» и «Remove». «Remove» SHALL быть недоступна у профиля текущего подключения, с подсказкой «Disconnect first».

Радиокнопка строки SHALL выбирать профиль по умолчанию (`shared_preferences` `codelab.connection.default_profile`). Профиль по умолчанию используется при старте и кнопкой «Connect» до первого подключения окна. «Connect» SHALL подключать текущее окно к профилю строки и НЕ SHALL менять профиль по умолчанию.

Без сохранённого выбора профилем по умолчанию SHALL быть встроенный агент. `default` — второе имя встроенного агента (design.md, D21): запись с id `default` в `profiles.json` SHALL игнорироваться и НЕ SHALL показываться строкой профиля.

Если такая запись есть, страница SHALL показывать InfoBar уровня `warning` (ключ `connection-profiles-ignored-default`) с текстом `Profile "default" in profiles.json is ignored: default is the built-in agent. Remove it with codelab profiles remove default.` и кнопкой «Remove». Кнопка после подтверждения удаляет запись через `ProfileStore.remove('default')`. Команду, аргументы, URL и `env` записи InfoBar НЕ SHALL показывать. Без действия пользователя файл НЕ SHALL перезаписываться. Сохранённый id, которого нет в списке, SHALL удаляться, и профилем по умолчанию SHALL становиться встроенный агент.

Если `profiles.json` не разбирается или имеет неизвестную версию, страница SHALL показывать строку встроенного агента и ошибку `Cannot read <path>: <причина>. Fix or remove the file; CodeLab will not overwrite it.`. «Add profile», «Rename» и «Remove» в этом случае SHALL быть недоступны, и файл НЕ SHALL перезаписываться.

Строка WebSocket-профиля SHALL показывать источник токена:
- `No token`;
- `From $<NAME>`, с пометкой `<NAME> is not set in CodeLab's environment.`, если переменной нет в окружении app;
- `Token: <ref> (not supported in this version)` для ссылки не вида `env:`. «Connect» с таким профилем SHALL подключаться без токена и писать предупреждение в диагностику без значения.

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
- **WHEN** `profiles.json` содержит WebSocket-профиль с `tokenRef: codelab/ws-devbox`
- **THEN** строка показывает `Token: codelab/ws-devbox (not supported in this version)`, а «Connect» подключается без токена с предупреждением в диагностике

#### Scenario: Битый profiles.json
- **WHEN** `profiles.json` содержит `{"version": 2, "profiles": []}`
- **THEN** страница показывает встроенного агента и ошибку чтения, «Add profile» недоступна, а содержимое файла после закрытия страницы прежнее

#### Scenario: Текущий профиль не удаляется
- **WHEN** окно подключено к профилю `dev`
- **THEN** «Remove» в строке `dev` недоступна с подсказкой «Disconnect first»

### Requirement: Блок «Behavior» страницы «Connection»
Блок «Behavior» SHALL содержать две строки.

**«Connect on start».** Переключатель хранится в `shared_preferences` `codelab.connection.connect_on_start`, по умолчанию выключен. При включённом переключателе app SHALL после первого кадра и после восстановления проекта один раз подключаться к профилю по умолчанию. Сбой такого подключения SHALL отображаться как сбой обычного подключения (`ConnectionFailed` и баннер) без повторов. При выключенном переключателе app SHALL открываться без подключения.

**«Restart agent».** Строка SHALL вызывать переподключение текущим профилем (`ClientWorkspace.reconnect`) — то же действие, что «Restart agent» диалога переноса секретов (design.md, D9). Для профиля WebSocket строка SHALL называться «Reconnect». Её описание НЕ SHALL обещать отмену хода (`session/cancel`); оно SHALL сообщать, что идущий ход прерывается, открытые сессии загружаются заново, а очередь промптов сохраняется. Строка SHALL быть недоступна без текущего профиля и во время подключения или переподключения.

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

**Тип.** Типы SHALL определяться зарегистрированными `TransportResolver`. Если хост поддерживает один тип, переключателя типа SHALL не быть (SETUP-22).

**Имя и id.** Поле «Name» и под ним id: по умолчанию из имени, редактируемый до сохранения. Подпись «cannot change after saving». Ошибки id выводятся у поля.

**stdio.**
- «Command» — по умолчанию `codelab-agent`.
- «Arguments» — по умолчанию `serve --stdio`, подсказка «Parsed like a shell: quotes and escapes work.».
- «Run in the project folder» — по умолчанию включено.
- «Environment» — свёрнуто, строки `KEY=value`.

**WebSocket.**
- «URL».
- Предупреждение `ws:// to another machine: the token is sent unencrypted.` для `ws://` к нелокальному хосту.
- «Token» в этой версии SHALL предлагать ровно два варианта (design.md, D13):
  - «No token»;
  - «From environment variable» — поле имени переменной, по умолчанию `CODELAB_AGENT_TOKEN`, в профиль идёт `tokenRef: env:<NAME>`.
- Значение токена диалог НЕ SHALL принимать, читать при сохранении и показывать.
- Под полем SHALL показываться подсказка `CodeLab reads the token from this environment variable when it connects. Token values are not saved in profiles.json.` и строка `Apps opened from Finder do not see variables set in your shell profile.`.
- Если переменная не задана в окружении app, диалог SHALL показывать `<NAME> is not set in CodeLab's environment.`.
- Вариантов хранилища секретов и обещаний о них диалог НЕ SHALL показывать.

**Проверка.** «Test connection» SHALL выполнять `ProfileProbe` и показывать исход:
- `Reachable · <ms> ms · <agentInfo.name> <version>`;
- `Unauthorized`;
- `Unreachable`;
- `Timed out`;
- `Not an ACP agent`;
- `Command not found`.

Повторная проверка и закрытие диалога SHALL отменять идущую проверку, а её поздний исход НЕ SHALL менять диалог.

**Сохранение.** Кнопка SHALL называться «Save» после успешной проверки и «Save without test» иначе; без успешной проверки строка профиля получает метку «Not tested». `ws://` к нелокальному хосту SHALL требовать подтверждения «Save anyway». Флажок «Use by default» (по умолчанию выключен) делает профиль профилем по умолчанию; текущее подключение диалог НЕ SHALL менять.

После сохранения диалог SHALL показывать экран «Profile saved» с id, текстом `The current connection is unchanged. Use Connect in the profile row to switch now.` и кнопками «Done» и «Add another». «Cancel» и Esc без сохранения SHALL закрывать диалог без записи в `profiles.json` и `shared_preferences`.

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
- **THEN** диалог показывает `MISSING_TOKEN is not set in CodeLab's environment.`, а сохранение остаётся доступным

#### Scenario: Отмена
- **WHEN** пользователь заполнил диалог и нажал Esc
- **THEN** `profiles.json` и `shared_preferences` не изменены

#### Scenario: Закрытие во время проверки
- **WHEN** «Test connection» stdio-профиля ждёт ответа на `initialize`, и пользователь закрывает диалог
- **THEN** процесс агента проверки завершён, и исход проверки не записан в состояние страницы

### Requirement: «Rename» и «Remove» профиля
«Rename» SHALL менять только `label` профиля; id SHALL оставаться прежним.

«Remove» SHALL спрашивать подтверждение «Remove profile <label>?» и удалять только запись из `profiles.json`; переменные окружения и другие хранилища app НЕ SHALL трогать. Удаление профиля по умолчанию SHALL сбрасывать `codelab.connection.default_profile`. Запрет удаления встроенного профиля и профиля текущего подключения SHALL проверяться перед вызовом `ProfileStore.remove`, а не только недоступностью кнопки.

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
- `connection_profile.probe_started`, `connection_profile.probe_finished`, `connection_profile.probe_discarded`;
- `connection_profile.default_changed`, `connection_profile.unreadable`, `connection_profile.token_ref_unsupported`, `connection_profile.default_ignored`, `connection_profile.default_removed`;
- `connection.connect_on_start`.

События и тексты ошибок на экране НЕ SHALL содержать:
- значения и имена переменных токена;
- аргументы и значения `env` stdio-профиля;
- путь, query и userinfo URL;
- текст `toString()` исключений — только имя типа.

#### Scenario: Маркер секрета не утекает
- **WHEN** app запущено с `DEVBOX_TOKEN=sk-test-leak-0123456789`, пользователь проверяет и сохраняет WebSocket-профиль с `env:DEVBOX_TOKEN` и URL `wss://u:p@host:1/acp?t=sk-test-leak-0123456789`, а запись профиля завершается исключением, чей `toString()` содержит тот же маркер
- **THEN** журнал содержит `connection_profile.save_failed` с именем типа исключения, а ни журнал, ни диалог не содержат `sk-test-leak-0123456789`, `u:p`, `/acp` и `t=`
