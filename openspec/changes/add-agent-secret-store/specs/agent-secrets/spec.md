## ADDED Requirements

### Requirement: Имена секретов
Имя секрета SHALL проверяться одним правилом `SecretNames` ядра: совпадение с `^[a-z0-9][a-z0-9._/-]{0,127}$`, без `..` и без `/` в конце (`agent-core-architecture` §17.5.2; design.md, D2). Правило SHALL применяться к `api_key_secret`, к имени в `${secret:<name>}` и к аргументу подкоманд `secret`. Неверное имя SHALL давать текст `expected a secret name: lowercase letters, digits and . _ / -, up to 128 characters`; само значение в текст НЕ SHALL попадать.

`SecretNames.envOverride(name)` SHALL возвращать `CODELAB_SECRET_` и имя в верхнем регистре, где каждый символ вне `[A-Z0-9]` заменён на `_`. `SecretNames.suggestFor(path)` SHALL возвращать:
- `codelab/<id>` для ключей `providers.<id>.*`;
- `codelab/mcp/<server>/<key>` для `mcp.servers[<server>].env.<KEY>` и `….headers.<Key>` — обе части в нижнем регистре, символы вне `[a-z0-9._-]` заменены на `-`; так же `SecretNames.forMcp(server, key)`;
- `codelab/search-<b>` для `tools.web.search.backends.<b>.*`.

Результат `suggestFor` и `forMcp` SHALL проходить правило имени.

#### Scenario: Переменная переопределения
- **WHEN** вызывается `SecretNames.envOverride("codelab/mcp/github/authorization")`
- **THEN** результат — `CODELAB_SECRET_CODELAB_MCP_GITHUB_AUTHORIZATION`

#### Scenario: Предлагаемое имя MCP
- **WHEN** вызываются `SecretNames.forMcp("GitHub", "Authorization")` и `SecretNames.suggestFor("mcp.servers[GitHub].headers.Authorization")`
- **THEN** оба дают `codelab/mcp/github/authorization`, и имя проходит правило

#### Scenario: Неверные имена
- **WHEN** проверяются `Codelab/OpenAI`, `a/../b`, `codelab/`, `my key` и строка из 129 символов
- **THEN** каждое отклонено с текстом правила, текст не содержит проверяемой строки

### Requirement: Резолвер секретов
Ядро SHALL получать значение секрета только через `SecretResolver` (`codelab_agent_core/lib/src/secrets/`, чистый Dart, без `dart:io`). `SecretResolver.secret(name, purpose)` SHALL возвращать `SecretFound(value, source)`, `SecretMissing(backend)` или `SecretUnavailable(backend, reason)` (design.md, D3).

Порядок:
1. Кэш процесса содержит имя → `SecretFound(source: "cache")`.
2. Переменная `SecretNames.envOverride(name)` задана и непуста → её значение, `source: "env"`.
3. `DescribedSecretStore.read(name)`:
   - найдено → `source` — id бэкенда;
   - `null` или пусто → `SecretMissing`;
   - `SecretStoreUnavailableException` → `SecretUnavailable` и предупреждение `secrets.backend.unavailable {backend, reason}`, не чаще одного раза на пару `(backend, reason)` за процесс.

Найденное значение SHALL кэшироваться до конца жизни резолвера, ненайденное НЕ SHALL кэшироваться. Одновременные запросы одного имени SHALL приводить к одному вызову `read`. Переменная переопределения SHALL побеждать хранилище при любом бэкенде. `SecretFound.toString()` НЕ SHALL содержать значение. `SecretResolver.env(variable, purpose)` SHALL читать только окружение, переданное резолверу.

#### Scenario: Переменная побеждает хранилище
- **WHEN** `MemorySecretStore` содержит `codelab/openai = store-value`, а окружение — `CODELAB_SECRET_CODELAB_OPENAI=env-value`
- **THEN** `secret("codelab/openai")` даёт `env-value` с `source: env`, а `read` хранилища не вызывается

#### Scenario: Кэш и отсутствие
- **WHEN** секрет `codelab/a` найден в хранилище, а `codelab/b` отсутствует; оба запрашиваются дважды, а между запросами `codelab/b` записывается в хранилище
- **THEN** `read("codelab/a")` вызван один раз, второй ответ — `source: cache`; `codelab/b` сначала `SecretMissing`, затем `SecretFound`

#### Scenario: Одно обращение на имя
- **WHEN** три вызова `secret("codelab/a")` начинаются до завершения первого `read`
- **THEN** хранилище получает один `read`, все три вызова получают одно значение

#### Scenario: Хранилище недоступно
- **WHEN** `read` бросает `SecretStoreUnavailableException(backend: "file", reason: "<path> has permissions 0644; run: chmod 600 <path>")` на двух разных именах
- **THEN** оба вызова дают `SecretUnavailable`, а в логе ровно одно `secrets.backend.unavailable`

### Requirement: Ключ провайдера при запросе
Ключ провайдера SHALL разрешаться при первом запросе к провайдеру в `createRoutedStreamFunction`, а не при загрузке конфига (design.md, D4):
- `api_key_secret` — через `SecretResolver.secret`;
- `api_key_env` — через `SecretResolver.env`;
- `${secret:<name>}` в `providers.<id>.headers.*` — через `SecretResolver.secret`.

Ответы:
- `SecretMissing` для ключа SHALL давать ошибку хода класса `auth` без HTTP-запроса с текстом `API key secret <name> is not set. Run: codelab secret set <name>`;
- `SecretMissing` для заголовка SHALL давать ошибку `auth` с текстом `secret <name> is not set (providers.<id>.headers.<H>). Run: codelab secret set <name>`;
- `SecretUnavailable` SHALL давать ошибку `auth` с текстом, который называет бэкенд, причину и переменную `SecretNames.envOverride(name)`.

После неудачи следующий запрос SHALL разрешать ссылку заново. Цепочка провайдера с найденными значениями SHALL кэшироваться на процесс; найденные значения SHALL входить в `ProviderConfig.secrets`. Отмена хода во время ожидания хранилища SHALL завершать поток с `cancelled`, не дожидаясь хранилища. Текст ошибки, журнал и лог НЕ SHALL содержать значение секрета.

#### Scenario: Ключ из хранилища
- **WHEN** провайдер `openai` задаёт `api_key_secret: codelab/openai`, хранилище содержит `sk-test-0123456789abcdef`, а сессия выбирает `openai/gpt-4o`
- **THEN** запрос к фейковому HTTP-клиенту несёт `Authorization: Bearer sk-test-0123456789abcdef`, хранилище прочитано один раз за два хода

#### Scenario: Секрет не задан
- **WHEN** провайдер задаёт `api_key_secret: codelab/openai`, хранилище пусто, переменной нет
- **THEN** ход завершается ошибкой `API key secret codelab/openai is not set. Run: codelab secret set codelab/openai` класса `auth`, HTTP-запроса нет; после записи секрета следующий ход выполняется без перезапуска

#### Scenario: Отмена во время ожидания хранилища
- **WHEN** `read` хранилища не завершается, а ход отменяется через 100 мс
- **THEN** поток провайдера завершается `cancelled` не позже чем через 1 с после отмены, HTTP-запроса нет

### Requirement: Секреты MCP-серверов конфигурации
Значения `env.*` и `headers.*` MCP-сервера конфигурации с `${secret:<name>}` SHALL храниться в `CoreConfig` шаблоном из литералов и ссылок, а не строкой, и раскрываться рантаймом перед `services.mcp.connect` при создании и загрузке сессии (design.md, D4). Сервер с ненайденным секретом НЕ SHALL подключаться: лог `mcp.server.failed {server, reason}` с причиной `secret <name> is not set` или `secret <name> cannot be read: <backend> is unavailable`, сессия создаётся без его инструментов. `${secret:…}` в серверах `session/new.mcpServers` SHALL оставаться литералом. Литерал `$${secret:x}` SHALL давать строку `${secret:x}` без обращения к резолверу. Без `AgentCoreServices.secrets` ссылка SHALL давать сбой сервера с причиной `no secret store`.

#### Scenario: Заголовок из хранилища
- **WHEN** конфиг объявляет http-сервер `gh` с `headers.Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`, а хранилище содержит `tok-test-secret`
- **THEN** коннектор получает заголовок `Bearer tok-test-secret`, а лог и журнал не содержат `tok-test-secret`

#### Scenario: Ненайденный секрет MCP
- **WHEN** у сервера `gh` секрет не задан, а у сервера `docs` ссылок нет
- **THEN** сессия создаётся, `docs` подключён, `gh` — `mcp.server.failed` с причиной `secret codelab/mcp/gh/authorization is not set`

#### Scenario: Ссылка от клиента ACP — литерал
- **WHEN** `session/new.mcpServers` содержит http-сервер с заголовком `${secret:codelab/openai}`
- **THEN** резолвер не вызывается, коннектор получает строку `${secret:codelab/openai}`

#### Scenario: Недоверенный проект не читает секреты
- **WHEN** `<cwd>/.codelab/config.yaml` недоверенного проекта объявляет сервер с `${secret:codelab/openai}`
- **THEN** сервер отброшен правилом доверия, резолвер не вызывается

### Requirement: Бэкенды env и file
`codelab_agent_io` SHALL предоставлять бэкенды `DescribedSecretStore` `env` (только чтение `CODELAB_SECRET_<…>`) и `file` (requirement «Бэкенд file»). Запись и удаление у `env` SHALL давать `SecretStoreUnavailableException("env backend is read-only")`. Значение с `\n` или `\r` SHALL отклоняться при записи. Текст исключений НЕ SHALL содержать значение. Порт `SecretStore` SHALL оставаться прежним (§10.3), чтобы бэкенды хранилищ ОС подключались после 1.0 изменением только `openSecretStore` (design.md, D13). Значение секрета НЕ SHALL передаваться в argv дочерних процессов.

#### Scenario: env только для чтения
- **WHEN** `EnvSecretStore` с окружением `CODELAB_SECRET_CODELAB_A=v` читает `codelab/a`, затем вызываются `write("codelab/a", "x")` и `delete("codelab/a")`
- **THEN** чтение возвращает `v`, запись и удаление бросают `SecretStoreUnavailableException` с причиной `env backend is read-only`

### Requirement: Бэкенд file
Бэкенд `file` SHALL хранить секреты открытым текстом в `$CODELAB_HOME/secrets.yaml` — отображении «имя → строка» в строгом профиле YAML. Он SHALL выбираться только явным `secrets.backend: file`. Файл SHALL создаваться только записью (`secret set`); чтение, удаление и `names()` отсутствующего файла его НЕ SHALL создавать.

Перед каждым чтением, записью и `names()` бэкенд SHALL отказывать (`SecretStoreUnavailableException` и одно на процесс предупреждение `secrets.file.refused`), если:
- путь — символическая ссылка: причина `<path> is a symbolic link; refusing to read secrets`;
- права шире `0600` (`mode & 0o077 != 0`): причина `<path> has permissions <mode>; run: chmod 600 <path>`.

Запись SHALL быть атомарной: временный файл в том же каталоге получает права `0600` до записи значения, затем заменяет `secrets.yaml` переименованием. Сбой до переименования SHALL оставлять прежний файл. На Windows бэкенд SHALL отказывать: права NTFS `dart:io` не проверяет. При каждом старте хоста с бэкендом `file` SHALL писаться предупреждение `secrets.backend.plaintext {path}`. Конструктор SHALL принимать явный путь, чтобы тестовое хранилище этапа 7 (`CODELAB_TEST_SECRET_STORE`) использовало ту же реализацию с `backend.id == "file"`.

#### Scenario: Права шире 0600
- **WHEN** `secrets.yaml` содержит `codelab/openai` и имеет права `0644`
- **THEN** `read("codelab/openai")` даёт `SecretStoreUnavailableException` с текстом `has permissions 0644; run: chmod 600 <path>`, значение не возвращено и не залогировано, резолвер возвращает `SecretUnavailable`

#### Scenario: Символическая ссылка
- **WHEN** `secrets.yaml` — символическая ссылка на файл с правами `0600`
- **THEN** чтение отклонено с причиной `is a symbolic link`

#### Scenario: Файл создаёт только запись
- **WHEN** файла нет, а выполняются `read`, `delete` и `names()`, затем `write("codelab/a", "v")`
- **THEN** до `write` файла нет; после — файл есть, права `0600`, `read` возвращает `v`

#### Scenario: Атомарная запись
- **WHEN** запись прерывается после создания временного файла и до переименования
- **THEN** `secrets.yaml` содержит прежние значения, а следующая запись удаляет оставшийся временный файл

#### Scenario: file на Windows
- **WHEN** глобальный конфиг на Windows задаёт `secrets.backend: file`
- **THEN** загрузка даёт проблему `secrets.backend: file backend is not supported on Windows; use auto (Windows Credential Manager)`

### Requirement: Выбор бэкенда secrets.backend
Ключ `secrets.backend` (`auto` | `keychain` | `env` | `file`, по умолчанию `auto`) SHALL читаться только из пользовательского слоя и из файла `--config`/`CODELAB_CONFIG`; из проектных слоёв он отбрасывается правилом доверия. Другое значение SHALL давать проблему `value` с текстом `expected one of: auto, keychain, env, file` (design.md, D7).
- `auto` SHALL давать бэкенд `env` на всех ОС, без проб и процессов, с `unavailableReason`, который называет `secrets.backend: file` и переменные `CODELAB_SECRET_*`. `auto` НЕ SHALL выбирать `file` ни сразу, ни как запасной вариант, даже если `secrets.yaml` существует.
- `keychain` SHALL давать проблему конфигурации `secrets.backend: keychain is not supported yet (supported: auto, env, file)`: хранилища ОС появятся после 1.0.
- `env` SHALL использовать только переменные `CODELAB_SECRET_*`.
- `file` — requirement «Бэкенд file»; на Windows — проблема конфигурации, поэтому на Windows в этой версии доступен только `env`.

Выбранный бэкенд SHALL логироваться один раз: `secrets.backend.selected {backend, path, reason}`.

#### Scenario: auto — env на всех ОС
- **WHEN** `auto` на macOS, Linux и Windows (подменённая платформа)
- **THEN** бэкенд — `env`, ни одного дочернего процесса, `secrets.backend.selected {backend: env}` с причиной, называющей `secrets.backend: file`

#### Scenario: auto не выбирает file
- **WHEN** `auto`, а в `$CODELAB_HOME` лежит `secrets.yaml` с правами `0600` и секретом `codelab/openai`
- **THEN** бэкенд — `env`, файл не читается, `secret("codelab/openai")` даёт `SecretMissing(env)`

#### Scenario: keychain ещё не поддерживается
- **WHEN** глобальный конфиг задаёт `secrets.backend: keychain`
- **THEN** загрузка даёт проблему `secrets.backend: keychain is not supported yet (supported: auto, env, file)`; `serve` завершается кодом `64` до старта транспорта, `config check` — кодом `1`

#### Scenario: Неизвестный бэкенд
- **WHEN** глобальный конфиг задаёт `secrets.backend: vault`
- **THEN** загрузка даёт проблему `secrets.backend: expected one of: auto, keychain, env, file`

### Requirement: Подкоманды secret
`codelab secret set|delete|list` и `codelab-agent secret set|delete|list` SHALL использовать одну реализацию `SecretCommands` (`codelab_agent_io`); их stdout, stderr и коды выхода SHALL совпадать (design.md, D8). Подкоманды SHALL работать без запуска агента и без ACP. Бэкенд SHALL браться из `secrets.backend` пользовательского конфига и файла `CODELAB_CONFIG`; другие проблемы конфига НЕ SHALL мешать подкомандам.

- `set <name>`:
  - значение читается только из stdin: с TTY — без эха, с подсказкой в stderr; без TTY — весь поток без одного завершающего `\n` или `\r\n`;
  - значение аргументом — код `64` и `pass the secret value on stdin, not as an argument`, аргумент не печатается;
  - пустое значение — код `64` и `empty secret value`; значение с переводом строки — код `64` и `secret value must be a single line`;
  - неверное имя — код `64`;
  - имя, чья переменная `envOverride` совпадает с переменной другого сохранённого имени, — код `64`;
  - бэкенд `env` (в том числе при `auto`) — код `1`, stdin не читается, stderr подсказывает добавить `secrets.backend: file` в `<CODELAB_HOME>/config.yaml` (секреты будут в открытом `secrets.yaml` с правами `0600`) или задать переменную `envOverride(name)`; на Windows — только переменную;
  - успех — код `0` и `Stored secret <name> in <backend>`; существующее имя перезаписывается без вопроса и без флага `--force`, stdout — `Updated secret <name> in <backend>`.
- `delete <name>`: код `0` и `Deleted secret <name> from <backend>`; отсутствующее имя — код `0` и `Secret <name> was not set in <backend>`.
- `list`:
  - первая строка — `Backend: <id>` или `Backend: env (<reason>)`;
  - затем имена по алфавиту;
  - затем строка `Environment overrides: <VAR>, …`, если в окружении есть переменные `CODELAB_SECRET_*`;
  - код `0`.

Ни одна подкоманда НЕ SHALL печатать значение или длину секрета. Ошибка хранилища (в том числе отказ бэкенда `file` по правам) SHALL давать код `1`, ошибка использования — код `64` и справку `secret` в stderr. С бэкендом `file` каждая подкоманда SHALL писать в stderr `warning: secrets are stored unencrypted in <path>`.

#### Scenario: Значение аргументом
- **WHEN** запускается `codelab secret set codelab/openai sk-test-0123456789abcdef`
- **THEN** код `64`, stderr содержит `pass the secret value on stdin, not as an argument` и не содержит `sk-test-0123456789abcdef`, хранилище не вызывалось

#### Scenario: Значение из stdin без TTY
- **WHEN** в stdin `codelab-agent secret set codelab/openai` подана строка `sk-test-0123456789abcdef\n`, бэкенд — фейк с записью
- **THEN** записано значение без завершающего `\n`, stdout — `Stored secret codelab/openai in <backend>`, код `0`

#### Scenario: Перезапись существующего секрета
- **WHEN** `codelab/openai` уже сохранён, а `secret set codelab/openai` получает новое значение из stdin
- **THEN** значение заменено, stdout — `Updated secret codelab/openai in <backend>`, код `0`

#### Scenario: Конфиг с ключом значением не мешает set
- **WHEN** `config.yaml` содержит `providers.openai.api_key: sk-…` (конфиг невалиден), а запускается `secret set codelab/openai`
- **THEN** подкоманда выполняется, проблема `api_key` её не блокирует

#### Scenario: Коллизия переменной
- **WHEN** сохранён `codelab/a-b`, а запускается `secret set codelab/a.b`
- **THEN** код `64`, stderr называет оба имени и переменную `CODELAB_SECRET_CODELAB_A_B`

#### Scenario: Только чтение при auto
- **WHEN** конфиг не задаёт `secrets.backend` (`auto` = `env`), на macOS или Linux запускается `secret set codelab/openai`
- **THEN** код `1`, stdin не читается, stderr содержит `secrets.backend: file` и `CODELAB_SECRET_CODELAB_OPENAI`

#### Scenario: Сохранение в file
- **WHEN** глобальный конфиг задаёт `secrets.backend: file`, в stdin `secret set codelab/openai` подана строка `sk-test-0123456789abcdef`
- **THEN** код `0`, `<CODELAB_HOME>/secrets.yaml` создан с правами `0600`, stderr содержит `warning: secrets are stored unencrypted`, stdout и stderr не содержат значения

#### Scenario: Одинаковый вывод двух бинарей
- **WHEN** `codelab secret list` и `codelab-agent secret list` запускаются с одним окружением, `secrets.backend: env` и `CODELAB_SECRET_X=1`
- **THEN** stdout, stderr и коды совпадают; stdout содержит `Environment overrides: CODELAB_SECRET_X` и не содержит `1` как значение

### Requirement: Диагностика обращений к секретам
Флаг `serve --debug-secrets` и переменная `CODELAB_DEBUG_SECRETS=1` SHALL включать событие `secrets.lookup {name, purpose, source, found}` уровня `info` на каждое обращение к `SecretResolver`. `name` — имя секрета или переменной, `purpose` — путь ключа конфига, `source` — `cache`, `env` или id бэкенда. Без режима `secrets.lookup` НЕ SHALL писаться. Ни в одном режиме лог НЕ SHALL содержать значение секрета, его длину, префикс из 4 и более символов или хеш (CFG-10).

#### Scenario: Значение не попадает в лог
- **WHEN** `MemorySecretStore` содержит `sk-test-0123456789abcdef`, резолвер в режиме отладки, а scripted-провайдер выполняет два хода (`core/debug-secrets-never-logs-value`)
- **THEN** есть записи `secrets.lookup` с `found: true` и `source` — `memory`, затем `cache`; сырые `LogRecord` (до любой редакции) не содержат значения, ни одной его подстроки длиной 4+, числа `24` в поле, связанном с секретом, и SHA-256 значения в шестнадцатеричном или base64 виде

#### Scenario: Без режима
- **WHEN** тот же прогон без `debug`
- **THEN** записей `secrets.lookup` нет

### Requirement: Секреты настольных хостов и встроенных профилей
Все настольные хосты — `codelab-agent`, встроенный агент desktop-приложения (`embedded-app-desktop`) и CLI (`embedded-cli`) — SHALL строить резолвер одной фабрикой `openHostSecrets` (`codelab_agent_io`) из `codelabHome`, окружения процесса, `secrets.backend` загруженного конфига и признака отладки (design.md, D15). Хост с ядром в отдельном isolate SHALL вызывать фабрику внутри этого isolate из сериализуемых данных; резолвер, его кэш и значения секретов НЕ SHALL пересылаться между isolate. Desktop SHALL использовать те же бэкенды, что CLI (в этой версии — те же переменные и тот же `secrets.yaml`), поэтому секрет, сохранённый `codelab secret set`, виден встроенному агенту приложения.

Известное ограничение до 8.10: найденное значение кэшируется до конца процесса, поэтому работающий агент не видит замену уже прочитанного секрета, сделанную в другом процессе, до перезапуска.

#### Scenario: Резолвер внутри isolate
- **WHEN** тест запускает `Isolate.run`, который получает только `codelabHome`, `secretsBackend: env` и `debug: true`, вызывает `openHostSecrets` с окружением, где задано `CODELAB_SECRET_CODELAB_P`, и разрешает `codelab/p`
- **THEN** isolate возвращает только признак `found: true` и `source: env`; запись `secrets.lookup` сделана логгером внутри isolate и не содержит значения

#### Scenario: Общий секрет CLI и встроенного агента
- **WHEN** `SecretAdmin` над бэкендом `file` во временном `CODELAB_HOME` сохраняет `codelab/p`, а затем `openHostSecrets` с тем же `CODELAB_HOME` и `secrets.backend: file` разрешает имя
- **THEN** значение найдено с `source: file`

#### Scenario: Замена прочитанного секрета требует перезапуска
- **WHEN** резолвер уже нашёл `codelab/p`, после чего другой экземпляр `SecretAdmin` перезаписывает значение
- **THEN** этот резолвер возвращает прежнее значение с `source: cache`; новый резолвер — новое значение

### Requirement: Программная запись секретов
`codelab_agent_io` SHALL предоставлять `SecretAdmin` — программный путь `store`, `delete`, `list` для страницы настроек приложения; `SecretCommands` SHALL быть построен поверх него, так что проверки и тексты причин совпадают. `codelab_setup/lib/io.dart` SHALL реэкспортировать `SecretAdmin`, его результаты и `openSecretStore`; основной барель `codelab_setup.dart` НЕ SHALL меняться. `store(name, value)` SHALL применять правило `SecretNames`, отклонять пустое и многострочное значение, коллизию `envOverride` и бэкенд только для чтения типизированным результатом, а не исключением. Значение SHALL передаваться только в памяти: не через argv, stdin или лог; результаты и их `toString` НЕ SHALL содержать значения. Список имён SHALL вести тот же бэкенд, что у CLI.

#### Scenario: Запись из приложения и список в CLI
- **WHEN** `SecretAdmin.store("codelab/openai", "sk-test-0123456789abcdef")` выполняется над бэкендом `file` во временном `CODELAB_HOME`, затем `codelab secret list` с тем же `CODELAB_HOME` и `secrets.backend: file`
- **THEN** результат — `Stored`, ни один дочерний процесс не получил значения в argv или stdin, `list` показывает `codelab/openai`

#### Scenario: Отказ без исключения
- **WHEN** `store("Bad Name", "v")` и `store("codelab/a", "a\nb")`
- **THEN** результаты `InvalidName` и `InvalidValue`, хранилище не вызывалось, тексты результатов не содержат значения
