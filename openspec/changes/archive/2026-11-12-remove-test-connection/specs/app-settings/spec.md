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
